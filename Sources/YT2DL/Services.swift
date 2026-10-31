import Foundation

enum LocalEngine {
    static func common(_ o: Options) -> [String] {
        var args = ["--ignore-config", "--no-warnings"] + BundledTools.arguments
        if !o.cookieBrowser.isEmpty { args += ["--cookies-from-browser", o.cookieBrowser] }
        return args
    }
    static func inspect(_ link: String, options o: Options, runner: ProcessRunner) async throws -> [Video] {
        let data = try await runner.run(try BundledTools.executable(options: o), common(o) + ["--dump-single-json", "--flat-playlist", "--playlist-end", String(o.limit), "--skip-download", "--", link])
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let entries = root["entries"] as? [[String: Any]] ?? [root]
        return entries.compactMap { item in
            guard let id = item["id"] as? String, id.count == 11 else { return nil }
            let thumbs = item["thumbnails"] as? [[String: Any]]
            return Video(videoId: id, title: item["title"] as? String ?? id,
                         thumbnail: item["thumbnail"] as? String ?? thumbs?.last?["url"] as? String ?? "https://i.ytimg.com/vi/\(id)/hqdefault.jpg",
                         author: item["uploader"] as? String ?? item["channel"] as? String ?? "",
                         duration: (item["duration"] as? NSNumber)?.doubleValue ?? 0,
                         viewCount: (item["view_count"] as? NSNumber)?.doubleValue ?? 0)
        }
    }
    static func arguments(_ job: Job) -> [String] {
        let o = job.options
        var a = common(o) + ["--no-playlist", "--progress", "--newline", "--continue", "--no-overwrites",
            "--progress-template", "download:PROGRESS:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
            "--print", "after_move:FILE:%(filepath)s", "-P", o.folder, "-o", "%(title).150B [%(id)s].%(ext)s"]
        switch o.mode {
        case .audio: a += ["-f", "bestaudio/best", "-x", "--audio-format", o.audioFormat]
        case .movie: a += ["-f", "bestvideo[height<=\(o.height)]+bestaudio/best[height<=\(o.height)]", "--merge-output-format", "mkv"]
        case .silent: a += ["-f", "bestvideo[height<=\(o.height)]"]
        }
        if o.metadata { a += ["--embed-metadata"] }
        if o.subtitles { a += ["--write-subs", "--write-auto-subs", "--sub-langs", "pl,en", "--sub-format", "srt/best"] }
        if o.thumbnail { a += ["--write-thumbnail"] }
        return a + ["--", job.video.url]
    }
}
struct APIEnvelope: Decodable { var status: Bool; var message: String; var data: Video? }
enum ServerAPI {
    static func endpoint(_ base: String, path: String) throws -> URL {
        guard let url = URL(string: base), ["http", "https"].contains(url.scheme ?? ""), url.host != nil, url.user == nil, url.password == nil else { throw AppError.message("Podaj poprawny adres serwera, np. http://localhost:3000.") }
        return url.appendingPathComponent(path)
    }
    static func inspect(_ link: String, base: String) async throws -> Video {
        if Links.playlist(link) { throw AppError.message("Serwer yt2dl nie obsługuje playlist. Wybierz tryb lokalny.") }
        var c = URLComponents(url: try endpoint(base, path: "api/video-info"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "url", value: link)]
        let (data, response) = try await URLSession.shared.data(from: c.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppError.message("Serwer nie zwrócił informacji o filmie. Sprawdź adres i dostępność filmu.") }
        let envelope = try JSONDecoder().decode(APIEnvelope.self, from: data)
        guard envelope.status, let video = envelope.data else { throw AppError.message(envelope.message) }
        return video
    }
}
// URLSessionDownloadTask streams to disk, avoiding buffering entire videos in RAM.
final class ServerDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var saved: URL?
    private var moveError: Error?
    var progress: @Sendable (Double) -> Void = { _ in }
    func start(_ job: Job) async throws -> URL {
        guard let format = job.format else { throw AppError.message("Wybierz format.") }
        var request = URLRequest(url: try ServerAPI.endpoint(job.options.server, path: "api/download"))
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["url": job.video.url, "token": format.token])
        request.timeoutInterval = 60
        let ext = format.mime.split(separator: "/").last.map(String.init) ?? "mp4"
        destination = URL(fileURLWithPath: job.options.folder).appendingPathComponent("\(Links.safeName(job.video.title)) [\(job.video.id)]-\(UUID().uuidString.prefix(6)).\(ext)")
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let config = URLSessionConfiguration.default; config.timeoutIntervalForResource = 86400
            session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            task = session!.downloadTask(with: request); task!.resume()
        }
    }
    func cancel() { task?.cancel() }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : -1)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode), !(response.mimeType ?? "").contains("json") else {
            moveError = AppError.message("Serwer odrzucił pobieranie. Odśwież podgląd i spróbuj ponownie."); return
        }
        do { try FileManager.default.moveItem(at: location, to: destination!); saved = destination } catch { moveError = error }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error ?? moveError { continuation?.resume(throwing: error) }
        else if let saved { continuation?.resume(returning: saved) }
        else { continuation?.resume(throwing: AppError.message("Nie zapisano pliku.")) }
        continuation = nil; session.finishTasksAndInvalidate(); self.session = nil
    }
}
