import Foundation

enum BundledTools {
    static var directory: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true) }
    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }
    static let names = ["yt-dlp", "ffmpeg", "ffprobe", "deno"]
    static var available: Bool { names.allSatisfy { FileManager.default.isExecutableFile(atPath: url($0).path) } }
    // Always resolve at runtime: moving the app must never break queued jobs.
    static func executable(options: Options) throws -> String {
        if available { return url("yt-dlp").path }
        if FileManager.default.isExecutableFile(atPath: options.executable) { return options.executable }
        throw AppError.message("Pakiet aplikacji jest niekompletny. Pobierz ponownie wersję All-in-One.")
    }
    static var arguments: [String] {
        guard available else { return [] }
        return ["--ffmpeg-location", directory.path, "--js-runtimes", "deno:\(url("deno").path)"]
    }
}
