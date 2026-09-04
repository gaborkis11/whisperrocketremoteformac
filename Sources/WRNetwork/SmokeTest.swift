import Foundation

/// F0 placeholder — replaced by DictationClient/HealthClient in F1.
/// This module's import list must stay Foundation-only.
public enum WRNetwork {
    public static let moduleName = "WRNetwork"

    public static func endpointURL(host: String, port: Int, path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = path
        return components.url
    }
}
