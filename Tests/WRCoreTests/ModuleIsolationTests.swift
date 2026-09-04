import Foundation
import Testing

/// The plan's structural guarantee, enforced instead of merely intended: the
/// two logic modules see nothing but Foundation, so no future change can let
/// the code that touches the wire reach AppKit, the audio engine, the settings
/// or the recording store.
@Suite struct ModuleIsolationTests {
    private var sourcesDirectory: URL {
        URL(filePath: #filePath)          // …/Tests/WRCoreTests/ModuleIsolationTests.swift
            .deletingLastPathComponent()  // …/Tests/WRCoreTests
            .deletingLastPathComponent()  // …/Tests
            .deletingLastPathComponent()  // package root
            .appending(path: "Sources")
    }

    @Test(arguments: ["WRCore", "WRNetwork"])
    func theModuleImportsNothingButFoundation(module: String) throws {
        let directory = sourcesDirectory.appending(path: module)
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty, "no sources found for \(module)")

        for file in files {
            let imports = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("import ") || $0.contains(" import ") }
            #expect(
                imports.allSatisfy { $0 == "import Foundation" },
                "\(module)/\(file.lastPathComponent) imports \(imports)"
            )
        }
    }
}
