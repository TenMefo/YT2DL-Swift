import Foundation

// Drain stdout and stderr concurrently; never invoke a shell with user input.
final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; let p = process; lock.unlock(); if p?.isRunning == true { p?.interrupt() } }
    func run(_ executable: String, _ arguments: [String], captureOutput: Bool = true, line: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let p = Process(), output = Pipe(), error = Pipe()
                p.executableURL = URL(fileURLWithPath: executable)
                p.arguments = arguments
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = BundledTools.directory.path + ":/usr/bin:/bin:/usr/sbin:/sbin"
                env["DENO_NO_UPDATE_CHECK"] = "1"
                p.environment = env; p.standardOutput = output; p.standardError = error
                self.lock.lock()
                if self.cancelled { self.lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.process = p
                do { try p.run(); self.lock.unlock() } catch { self.lock.unlock(); continuation.resume(throwing: AppError.message("Nie można uruchomić silnika pobierania. \(error.localizedDescription)")); return }
                let group = DispatchGroup()
                let buffer = LockedData()
                group.enter()
                DispatchQueue.global().async {
                    while true {
                        let chunk = error.fileHandleForReading.availableData
                        if chunk.isEmpty { break }; buffer.append(chunk)
                    }
                    group.leave()
                }
                var result = Data(), pending = Data()
                while true {
                    let chunk = output.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    // Download output is small; metadata capped by playlist-end.
                    if captureOutput { result.append(chunk) }; pending.append(chunk)
                    while let range = pending.firstRange(of: Data([10])) {
                        line(String(decoding: pending[..<range.lowerBound], as: UTF8.self))
                        pending.removeSubrange(..<range.upperBound)
                    }
                }
                if !pending.isEmpty { line(String(decoding: pending, as: UTF8.self)) }
                p.waitUntilExit(); group.wait()
                self.lock.lock(); self.process = nil; let cancelled = self.cancelled; self.lock.unlock()
                if cancelled { continuation.resume(throwing: CancellationError()) }
                else if p.terminationStatus != 0 { continuation.resume(throwing: AppError.message(String(decoding: buffer.data.suffix(3000), as: UTF8.self))) }
                else { continuation.resume(returning: result) }
            }
        }
    }
}
private final class LockedData: @unchecked Sendable {
    private let lock = NSLock(); private var storage = Data()
    func append(_ data: Data) { lock.lock(); storage.append(data); if storage.count > 16000 { storage = Data(storage.suffix(8000)) }; lock.unlock() }
    var data: Data { lock.lock(); defer { lock.unlock() }; return storage }
}
