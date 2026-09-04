import CoreAudio
import Foundation

/// One CoreAudio device that can actually record.
///
/// `uid` is the identity that gets persisted in settings: `deviceID` is a
/// process-lifetime handle that changes when devices come and go, while the UID
/// survives reboots and replugs.
nonisolated struct AudioInputDevice: Identifiable, Hashable, Sendable {
    var id: String { uid }
    let deviceID: AudioDeviceID
    let uid: String
    let name: String
    let isSystemDefault: Bool
    let inputChannelCount: Int
    let nominalSampleRate: Double
}

/// What the user picked in settings. Stored as `String?` in UserDefaults, where
/// `nil` means "follow the system default" — a distinct case from "this exact
/// device", because following the default has to keep working when the default
/// changes under us (AirPods connect, dock gets plugged in).
nonisolated enum AudioInputSelection: Hashable, Sendable {
    case systemDefault
    case uid(String)

    init(storedUID: String?) {
        if let storedUID, !storedUID.isEmpty { self = .uid(storedUID) } else { self = .systemDefault }
    }

    var storedUID: String? {
        switch self {
        case .systemDefault: nil
        case .uid(let uid): uid
        }
    }
}

/// The outcome of turning a stored selection into something to record from.
/// `missing` is its own case so the UI can say "your microphone is gone, using
/// <fallback> instead" rather than silently recording from the wrong device.
nonisolated enum AudioInputResolution: Sendable {
    case systemDefault(AudioInputDevice?)
    case device(AudioInputDevice)
    case missing(uid: String, fallback: AudioInputDevice?)

    /// The device to actually record from, or `nil` when the capture engine
    /// should leave the audio unit on whatever the system default is.
    var deviceToUse: AudioInputDevice? {
        switch self {
        case .systemDefault: nil
        case .device(let device): device
        case .missing: nil
        }
    }

    /// The device the user will hear themselves through, default included.
    var effectiveDevice: AudioInputDevice? {
        switch self {
        case .systemDefault(let device): device
        case .device(let device): device
        case .missing(_, let fallback): fallback
        }
    }
}

/// CoreAudio input-device enumeration.
///
/// Listing devices needs no TCC permission at all (only pulling samples does),
/// so this is safe to call from anywhere — settings UI, probes, launch.
nonisolated enum AudioDeviceList {
    // MARK: - Public API

    /// Every device with at least one input channel, in CoreAudio order.
    static func inputDevices() -> [AudioInputDevice] {
        let defaultID = defaultInputDeviceID()
        return allDeviceIDs().compactMap { id in
            describe(id, defaultInputDeviceID: defaultID)
        }
    }

    /// The device macOS currently treats as the default input, if any.
    static func defaultInputDevice() -> AudioInputDevice? {
        guard let id = defaultInputDeviceID() else { return nil }
        return describe(id, defaultInputDeviceID: id)
    }

    static func device(withUID uid: String) -> AudioInputDevice? {
        inputDevices().first { $0.uid == uid }
    }

    /// Turns a stored selection into a concrete recording target, reporting the
    /// "saved device has disappeared" case instead of hiding it.
    static func resolve(_ selection: AudioInputSelection) -> AudioInputResolution {
        switch selection {
        case .systemDefault:
            return .systemDefault(defaultInputDevice())
        case .uid(let uid):
            if let device = device(withUID: uid) { return .device(device) }
            return .missing(uid: uid, fallback: defaultInputDevice())
        }
    }

    // MARK: - CoreAudio plumbing

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        let status = ids.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, buffer.baseAddress!
            )
        }
        guard status == noErr else { return [] }
        return ids
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else { return nil }
        return deviceID
    }

    /// `nil` for anything that cannot record (every output-only device).
    private static func describe(_ id: AudioDeviceID, defaultInputDeviceID: AudioDeviceID?) -> AudioInputDevice? {
        let channels = inputChannelCount(id)
        guard channels > 0 else { return nil }
        guard let uid = stringProperty(kAudioDevicePropertyDeviceUID, of: id) else { return nil }
        let name = stringProperty(kAudioObjectPropertyName, of: id) ?? uid
        return AudioInputDevice(
            deviceID: id,
            uid: uid,
            name: name,
            isSystemDefault: id == defaultInputDeviceID,
            inputChannelCount: channels,
            nominalSampleRate: nominalSampleRate(id)
        )
    }

    /// Total input channels across every input stream — the standard test for
    /// "is this device an input device at all".
    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }

        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func nominalSampleRate(_ id: AudioDeviceID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &rate) == noErr else { return 0 }
        return rate
    }

    /// CoreAudio hands back a +1 CFString; `Unmanaged` is the only way to take
    /// that reference without leaking it.
    private static func stringProperty(_ selector: AudioObjectPropertySelector, of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
