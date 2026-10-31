import SwiftUI
import AppKit

@main struct YT2DLApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in store.shutdown() }
        }.defaultSize(width: 1180, height: 780)
        Settings { SettingsView().environmentObject(store) }
    }
}
struct ContentView: View {
    @EnvironmentObject var s: Store
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 24) {
                Label("YT2DL", systemImage: "arrow.down.circle.fill").font(.largeTitle.bold()).foregroundStyle(.indigo)
                Text("Twoje materiały.\nW jednym miejscu.").foregroundStyle(.secondary)
                ForEach(["Nowe pobieranie", "Kolejka", "Historia", "Ustawienia"], id: \.self) { item in
                    Button { s.page = item } label: {
                        Label(item, systemImage: icon(item)).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(s.page == item ? Color.indigo.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Label(s.options.engine.rawValue, systemImage: "network").font(.caption).foregroundStyle(.secondary)
                Text("macOS · SwiftUI").font(.caption2).foregroundStyle(.tertiary)
            }.padding(20).navigationSplitViewColumnWidth(230)
        } detail: {
            Group {
                if s.page == "Nowe pobieranie" { newDownload }
                else if s.page == "Ustawienia" { SettingsView() }
                else { queue(history: s.page == "Historia") }
            }
            .navigationTitle(s.page)
            .toolbar { ToolbarItem { Button { s.chooseFolder() } label: { Label("Folder docelowy", systemImage: "folder") } } }
        }
        .frame(minWidth: 960, minHeight: 640)
        .overlay(alignment: .bottom) {
            if let message = s.queueConfirmation {
                HStack(spacing: 14) {
                    Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Pokaż kolejkę") { s.page = "Kolejka"; s.queueConfirmation = nil }
                    Button { s.queueConfirmation = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Zamknij komunikat")
                }
                .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 8).padding(20)
            }
        }
        .tint(.indigo)
        .alert("Nie udało się wykonać operacji", isPresented: Binding(get: { s.error != nil }, set: { if !$0 { s.error = nil } })) {
            Button("OK") { s.error = nil }
        } message: { Text(s.error ?? "") }
    }
    func icon(_ item: String) -> String {
        switch item { case "Kolejka": return "arrow.down.to.line"; case "Historia": return "clock"; case "Ustawienia": return "slider.horizontal.3"; default: return "plus.rectangle.on.rectangle" }
    }
    var newDownload: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Co dzisiaj pobieramy?").font(.system(size: 28, weight: .bold))
                Text("Wklej link do filmu lub playlisty. Możesz podać kilka linków, każdy w osobnym wierszu.").foregroundStyle(.secondary)
                TextEditor(text: $s.input).font(.body.monospaced()).frame(height: 80).padding(8)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                    .accessibilityLabel("Linki YouTube")
                HStack {
                    Button { if let text = NSPasteboard.general.string(forType: .string) { s.input = text } } label: { Label("Wklej", systemImage: "doc.on.clipboard") }
                    Spacer()
                    if s.busy {
                        ProgressView().controlSize(.small)
                        Button("Anuluj") { s.cancelInspection() }
                    }
                    Button("Pokaż podgląd") { s.inspect() }.buttonStyle(.borderedProminent).disabled(s.busy || s.input.isEmpty)
                }
                if !s.notice.isEmpty { Text(s.notice).font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Text("Podgląd").font(.headline)
                    Spacer()
                    Button("Wszystkie") { s.selected = Set(s.videos.map(\.id)) }.disabled(s.videos.isEmpty)
                    Button("Żadne") { s.selected = [] }.disabled(s.videos.isEmpty)
                }
                if s.videos.isEmpty {
                    ContentUnavailableView("Najpierw zobacz, potem pobierz", systemImage: "play.rectangle.on.rectangle", description: Text("Tutaj pojawią się miniatury, tytuły, autorzy i czas trwania."))
                } else {
                    List(s.videos) { video in
                        HStack(alignment: .top, spacing: 12) {
                            Toggle("", isOn: Binding(get: { s.selected.contains(video.id) }, set: { if $0 { s.selected.insert(video.id) } else { s.selected.remove(video.id) } })).labelsHidden().toggleStyle(.checkbox)
                            Thumbnail(url: video.thumbnail)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(video.title).font(.headline).lineLimit(2)
                                Text("\(video.author) · \(video.time)").font(.caption).foregroundStyle(.secondary)
                                if s.options.engine == .server {
                                    let formats = s.formats(video)
                                    if formats.isEmpty { Text("Brak formatu w tym trybie").foregroundStyle(.orange).font(.caption) }
                                    else {
                                        Picker("Format", selection: Binding(get: { s.chosenFormats[video.id] ?? formats.first!.token }, set: { s.chosenFormats[video.id] = $0 })) {
                                            ForEach(formats) { f in Text(f.label).tag(f.token) }
                                        }.labelsHidden()
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                        }.padding(.vertical, 8)
                    }.listStyle(.plain)
                }
                Button { s.enqueue() } label: {
                    Label("Pobierz (\(s.selected.count))", systemImage: "arrow.down.to.line").frame(maxWidth: .infinity).padding(5)
                }.buttonStyle(.borderedProminent).disabled(s.selected.isEmpty || s.busy)
            }.padding(24).frame(minWidth: 440)
            SettingsView(compact: true).frame(minWidth: 280, idealWidth: 300, maxWidth: 350)
        }
    }
    func queue(history: Bool) -> some View {
        let jobs = s.jobs.filter { history ? [.done, .failed, .cancelled].contains($0.state) : [.waiting, .running].contains($0.state) }
        return VStack {
            HStack {
                Text("\(jobs.count) materiałów").foregroundStyle(.secondary)
                Spacer()
                if !history { Button(s.paused ? "Wznów kolejkę" : "Wstrzymaj kolejkę") { s.paused.toggle(); s.pump() } }
                else { Button("Wyczyść historię") { s.jobs.removeAll { [.done, .failed, .cancelled].contains($0.state) }; s.save() } }
            }.padding()
            if jobs.isEmpty { ContentUnavailableView(history ? "Historia jest pusta" : "Kolejka jest pusta", systemImage: history ? "clock" : "tray", description: Text("Dodaj materiały z ekranu nowego pobierania.")) }
            else {
                List(jobs) { job in
                    HStack(alignment: .top, spacing: 14) {
                        Thumbnail(url: job.video.thumbnail)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(job.video.title).font(.headline)
                            Text("\(job.state.rawValue) · \(job.options.mode.rawValue)").font(.caption).foregroundStyle(job.state == .failed ? .red : .secondary)
                            if job.state == .running {
                                if job.progress < 0 { ProgressView() } else { ProgressView(value: job.progress) }
                            }
                            Text(job.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(5)
                        }
                        Spacer()
                        if job.state == .running || job.state == .waiting { Button("Anuluj") { s.cancel(job.id) } }
                        if job.state == .failed || job.state == .cancelled { Button("Ponów") { s.retry(job.id) } }
                        if job.state == .done { Button("Pokaż w Finderze") { s.reveal(job) } }
                    }.padding(.vertical, 10)
                }
            }
        }
    }
}
struct Thumbnail: View {
    var url: String
    var body: some View {
        AsyncImage(url: URL(string: url)) { image in image.resizable().scaledToFill() } placeholder: { ZStack { Color.secondary.opacity(0.12); Image(systemName: "play.rectangle").foregroundStyle(.secondary) } }
            .frame(width: 112, height: 64).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
struct SettingsView: View {
    @EnvironmentObject var s: Store
    var compact = false
    var body: some View {
        Form {
            Section("Źródło pobierania") {
                Picker("Silnik", selection: $s.options.engine) { ForEach(Engine.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                if s.options.engine == .server {
                    TextField("Adres serwera", text: $s.options.server)
                    Text("Uruchom serwer ipincamp/yt2dl. Playlisty wymagają trybu lokalnego.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Label(BundledTools.available ? "Wszystko gotowe do pobierania" : "Niekompletny pakiet aplikacji", systemImage: BundledTools.available ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(BundledTools.available ? .green : .orange)
                    Text("Silnik pobierania, obsługa dźwięku i wideo są wbudowane. Nie musisz nic instalować.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Co zapisać") {
                Picker("Tryb", selection: $s.options.mode) { ForEach(MediaMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                if s.options.engine == .local {
                    if s.options.mode != .audio {
                        Picker("Maks. jakość", selection: $s.options.height) {
                            ForEach([360, 480, 720, 1080, 1440, 2160], id: \.self) { Text("\($0)p").tag($0) }
                        }
                        Picker("Format wideo", selection: Binding(get: { s.options.container }, set: { s.options.videoContainer = $0 })) {
                            ForEach(VideoContainer.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                        }
                        Text("MP4 preferuje obraz H.264 i audio AAC. MKV pozwala wybrać najlepsze dostępne kodeki. Jakość zależy od źródła; zapis bez ponownej kompresji.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Format audio", selection: $s.options.audioFormat) {
                            ForEach(["mp3", "m4a", "opus", "flac"], id: \.self) { Text($0.uppercased()).tag($0) }
                        }
                    }
                    Toggle("Zapisz napisy PL / EN", isOn: $s.options.subtitles)
                    Toggle("Dodaj metadane", isOn: $s.options.metadata)
                    Toggle("Zapisz miniaturę", isOn: $s.options.thumbnail)
                } else {
                    Text("Dostępne formaty wybierzesz przy filmach w podglądzie. Wideo bez dźwięku jest osobnym trybem.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Miejsce zapisu") {
                Text(s.options.folder).font(.caption).textSelection(.enabled).lineLimit(3)
                Button("Wybierz folder…") { s.chooseFolder() }
            }
            if s.options.engine == .local {
                Section("Playlisty i biblioteka") {
                    Stepper("Limit podglądu: \(s.options.limit)", value: $s.options.limit, in: 10...1000, step: 10)
                    Picker("Logowanie z przeglądarki", selection: $s.options.cookieBrowser) {
                        Text("Bez logowania").tag("")
                        Text("Chrome").tag("chrome")
                        Text("Firefox").tag("firefox")
                        Text("Safari").tag("safari")
                    }
                    Text("Do prywatnych playlist, np. „Do obejrzenia”. yt-dlp odczyta lokalne cookies wybranej przeglądarki. System może poprosić o dostęp.").font(.caption).foregroundStyle(.secondary)
                    Text("Cała strona „Biblioteka” nie jest playlistą. Wklej link do konkretnej listy. Niedostępne filmy mogą zostać pominięte.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !compact {
                Section("O aplikacji") {
                    Text("YT2DL · 1.2.0 All-in-One\nNatywny klient macOS dla ipincamp/yt2dl z wbudowanym silnikiem pobierania.")
                    Button("Licencje i składniki") {
                        NSWorkspace.shared.open(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/ThirdParty"))
                    }
                    Link("Projekt źródłowy yt2dl", destination: URL(string: "https://github.com/ipincamp/yt2dl")!)
                }
            }
        }.formStyle(.grouped).onChange(of: s.options) { _, _ in s.save() }
    }
}
