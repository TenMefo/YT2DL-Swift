import Foundation

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
enum Engine: String, Codable, CaseIterable { case local = "Lokalnie · playlisty", server = "Serwer yt2dl" }
enum MediaMode: String, Codable, CaseIterable { case movie = "Wideo i dźwięk", audio = "Tylko audio", silent = "Wideo bez dźwięku" }
struct Options: Codable, Equatable {
    var engine = Engine.local
    var server = "http://localhost:3000"
    var executable = "/opt/homebrew/bin/yt-dlp"
    var mode = MediaMode.movie
    var height = 1080
    var audioFormat = "mp3"
    var subtitles = false
    var metadata = true
    var thumbnail = false
    var folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.path
    var limit = 100
    var cookieBrowser = ""
}
struct StreamFormat: Codable, Identifiable, Hashable {
    var quality: String
    var codec: String
    var size: String
    var mime: String
    var token: String
    var id: String { token }
    var label: String { "\(quality) · \(codec) · \(size)" }
}
struct Formats: Codable { var bundle: [StreamFormat]; var video: [StreamFormat]; var audio: [StreamFormat] }
struct Video: Codable, Identifiable {
    var videoId: String
    var title: String
    var thumbnail: String
    var author: String
    var duration: Double
    var viewCount: Double
    var formats: Formats?
    var id: String { videoId }
    var url: String { "https://www.youtube.com/watch?v=\(videoId)" }
    var time: String { let s = Int(duration); return String(format: "%d:%02d", s / 60, s % 60) }
}
enum JobState: String, Codable { case waiting = "W kolejce", running = "Pobieranie", done = "Gotowe", failed = "Błąd", cancelled = "Anulowano" }
struct Job: Codable, Identifiable {
    var id = UUID()
    var video: Video
    var options: Options
    var format: StreamFormat?
    var state = JobState.waiting
    var progress: Double = 0
    var detail = "Oczekuje"
    var file: String?
}
enum Links {
    static func parse(_ text: String) throws -> [String] {
        let values = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !values.isEmpty else { throw AppError.message("Wklej co najmniej jeden link.") }
        var seen = Set<String>()
        return try values.map { value in
            guard let u = URLComponents(string: value), u.scheme == "https" || u.scheme == "http",
                  let host = u.host?.lowercased(), ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be"].contains(host) else {
                throw AppError.message("Nieprawidłowy link YouTube: \(value)")
            }
            return value
        }.filter { seen.insert($0).inserted }
    }
    static func playlist(_ value: String) -> Bool { URLComponents(string: value)?.queryItems?.contains(where: { $0.name == "list" }) == true }
    static func safeName(_ title: String) -> String {
        let clean = String(title.components(separatedBy: CharacterSet(charactersIn: "/\\:\n\r")).joined(separator: "_").prefix(150))
        return clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "video" : clean
    }
}
