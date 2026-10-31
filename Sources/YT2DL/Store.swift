import SwiftUI
import AppKit

@MainActor final class Store: ObservableObject {
    @Published var page = "Nowe pobieranie"
    @Published var options: Options
    @Published var jobs: [Job] = []
    @Published var videos: [Video] = []
    @Published var selected = Set<String>()
    @Published var chosenFormats: [String: String] = [:]
    @Published var input = ""
    @Published var busy = false
    @Published var paused = false
    @Published var error: String?
    @Published var notice = ""
    @Published var queueConfirmation: String?
    private var inspector: ProcessRunner?
    private var activeRunner: ProcessRunner?
    private var activeDownload: ServerDownload?
    private var activeID: UUID?
    private var inspectedOptions: Options?
    private let historyURL: URL
    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("YT2DL")
        historyURL = folder.appendingPathComponent("history.json")
        options = UserDefaults.standard.data(forKey: "options").flatMap { try? JSONDecoder().decode(Options.self, from: $0) } ?? Options()
        options.engine = .local
        if let data = try? Data(contentsOf: historyURL), let stored = try? JSONDecoder().decode([Job].self, from: data) {
            jobs = stored.map { var j = $0; if j.state == .running || j.state == .waiting { j.state = .cancelled; j.detail = "Przerwano przy zamknięciu aplikacji. Możesz ponowić." }; return j }
        }
    }
    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(options), forKey: "options")
        do { try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(jobs).write(to: historyURL, options: .atomic)
        } catch { self.error = "Nie można zapisać historii: \(error.localizedDescription)" }
    }
    func inspect() {
        guard !busy else { return }
        let links: [String]
        do { links = try Links.parse(input) } catch { self.error = error.localizedDescription; return }
        let snapshot = options
        busy = true; videos = []; selected = []; chosenFormats = [:]; notice = ""
        let runner = ProcessRunner(); inspector = runner
        Task {
            defer { busy = false; inspector = nil }
            var found: [Video] = [], failures: [String] = []
            for link in links {
                do {
                    let list: [Video]
                    if snapshot.engine == .local { list = try await LocalEngine.inspect(link, options: snapshot, runner: runner) }
                    else { list = [try await ServerAPI.inspect(link, base: snapshot.server)] }
                    for video in list where !found.contains(where: { $0.id == video.id }) { found.append(video) }
                } catch is CancellationError { return }
                catch { failures.append(error.localizedDescription) }
            }
            videos = found; selected = Set(found.map(\.id)); inspectedOptions = snapshot
            notice = "Znaleziono \(found.count) materiałów. Limit playlisty: \(snapshot.limit)."
            if !failures.isEmpty { error = failures.joined(separator: "\n\n") }
            else if found.isEmpty { error = "Brak dostępnych materiałów. Prywatne listy wymagają logowania w wybranej przeglądarce." }
        }
    }
    func cancelInspection() { inspector?.cancel() }
    func formats(_ video: Video) -> [StreamFormat] {
        guard let f = video.formats else { return [] }
        switch options.mode { case .movie: return f.bundle; case .audio: return f.audio; case .silent: return f.video }
    }
    func enqueue() {
        guard let source = inspectedOptions, source.engine == options.engine, source.server == options.server else { error = "Zmieniono źródło. Odśwież podgląd."; return }
        var added = 0
        for video in videos where selected.contains(video.id) {
            if jobs.contains(where: { $0.video.id == video.id && [.waiting, .running].contains($0.state) }) { continue }
            let available = formats(video)
            let format = available.first(where: { $0.token == chosenFormats[video.id] }) ?? available.first
            if options.engine == .server && format == nil { error = "Brak formatu dla wybranego trybu. Zmień tryb lub użyj pobierania lokalnego."; continue }
            jobs.append(Job(video: video, options: options, format: format)); added += 1
        }
        if added > 0 {
            queueConfirmation = "Dodano do kolejki: \(added)."
            notice = queueConfirmation!
        } else if error == nil {
            notice = "Wybrane materiały są już w kolejce."
        }
        save(); pump()
    }
    func pump() {
        guard activeID == nil, !paused, let index = jobs.firstIndex(where: { $0.state == .waiting }) else { return }
        let id = jobs[index].id; activeID = id; jobs[index].state = .running; jobs[index].detail = "Łączenie…"; save()
        let job = jobs[index]
        Task { [self] in
            do {
                try FileManager.default.createDirectory(atPath: job.options.folder, withIntermediateDirectories: true)
                if job.options.engine == .local {
                    let runner = ProcessRunner(); activeRunner = runner
                    _ = try await runner.run(try BundledTools.executable(options: job.options), LocalEngine.arguments(job)) { [weak self] line in
                        Task { @MainActor in self?.update(id, line: line) }
                    }
                } else {
                    let download = ServerDownload(); activeDownload = download
                    download.progress = { [weak self] progress in Task { @MainActor in
                        guard let i = self?.jobs.firstIndex(where: { $0.id == id }) else { return }
                        self?.jobs[i].progress = progress; self?.jobs[i].detail = progress < 0 ? "Pobieranie · rozmiar nieznany" : "\(Int(progress * 100))%"
                    } }
                    let file = try await download.start(job)
                    if let i = jobs.firstIndex(where: { $0.id == id }) { jobs[i].file = file.path }
                }
                if let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].state != .cancelled { jobs[i].state = .done; jobs[i].progress = 1; jobs[i].detail = "Zapisano w folderze docelowym" }
            } catch {
                if let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].state != .cancelled { jobs[i].state = .failed; jobs[i].detail = error.localizedDescription }
            }
            activeID = nil; activeRunner = nil; activeDownload = nil; save(); pump()
        }
    }
    private func update(_ id: UUID, line: String) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].state == .running else { return }
        if line.hasPrefix("PROGRESS:") {
            let parts = line.dropFirst(9).split(separator: "|", omittingEmptySubsequences: false)
            jobs[i].progress = Double((parts.first.map(String.init) ?? "").replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) .map { $0 / 100 } ?? -1
            jobs[i].detail = parts.joined(separator: " · ")
        } else if line.hasPrefix("FILE:") { jobs[i].file = String(line.dropFirst(5)) }
    }
    func cancel(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].state = .cancelled; jobs[i].detail = "Anulowano"
        if activeID == id { activeRunner?.cancel(); activeDownload?.cancel() }; save()
    }
    func retry(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), activeID != id else { return }
        jobs[i].state = .waiting; jobs[i].progress = 0; jobs[i].detail = "Ponawianie"; save(); pump()
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { options.folder = url.path; save() }
    }
    func reveal(_ job: Job) {
        if let file = job.file { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file)]) }
        else { NSWorkspace.shared.open(URL(fileURLWithPath: job.options.folder)) }
    }
    func shutdown() { inspector?.cancel(); activeRunner?.cancel(); activeDownload?.cancel(); save() }
}
