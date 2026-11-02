import XCTest
@testable import YT2DL

final class AudioTests: XCTestCase {
    private func arguments(format: String, bitrate: Int = 192) -> [String] {
        var options = Options()
        options.mode = .audio
        options.audioFormat = format
        options.audioBitrate = bitrate
        let video = Video(videoId: "abcdefghijk", title: "Test", thumbnail: "", author: "", duration: 0, viewCount: 0)
        return LocalEngine.arguments(Job(video: video, options: options))
    }
    func testAudioModesNeverRequestVideoMerge() {
        for format in ["mp3", "m4a", "opus", "flac", "best"] {
            let args = arguments(format: format)
            XCTAssertTrue(args.contains("-x"))
            XCTAssertEqual(args[args.firstIndex(of: "--audio-format")! + 1], format)
            XCTAssertFalse(args.contains("--merge-output-format"))
            XCTAssertFalse(args.contains("--remux-video"))
            XCTAssertTrue(args[args.firstIndex(of: "-f")! + 1].hasPrefix("bestaudio"))
        }
    }
    func testBitrateIsOnlyAppliedToLossyConversionFormats() {
        for format in ["mp3", "m4a", "opus"] {
            let args = arguments(format: format)
            XCTAssertEqual(args[args.firstIndex(of: "--audio-quality")! + 1], "192K")
        }
        for format in ["flac", "best"] {
            let args = arguments(format: format)
            XCTAssertFalse(args.contains("--audio-quality"))
        }
        let best = arguments(format: "mp3", bitrate: 0)
        XCTAssertEqual(best[best.firstIndex(of: "--audio-quality")! + 1], "0")
    }
    func testVersion12SettingsAndHistoryStillDecode() throws {
        let job = Job(video: Video(videoId: "abcdefghijk", title: "Test", thumbnail: "", author: "", duration: 0, viewCount: 0), options: Options())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as? [String: Any])
        var options = try XCTUnwrap(json["options"] as? [String: Any])
        for key in ["audioBitrate", "embedCover", "parallelFragments"] { options.removeValue(forKey: key) }
        options["folder"] = "/tmp/my music"
        json["options"] = options
        let migrated = try JSONDecoder().decode(Job.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(migrated.options.audioBitrate)
        XCTAssertEqual(migrated.options.folder, "/tmp/my music")
        XCTAssertEqual(migrated.id, job.id)
    }
    func testFragmentConcurrencyIsBounded() {
        var options = Options()
        let video = Video(videoId: "abcdefghijk", title: "", thumbnail: "", author: "", duration: 0, viewCount: 0)
        for (input, expected) in [(-4, "1"), (4, "4"), (200, "8")] {
            options.parallelFragments = input
            let args = LocalEngine.arguments(Job(video: video, options: options))
            XCTAssertEqual(args[args.firstIndex(of: "--concurrent-fragments")! + 1], expected)
        }
    }
    func testStreamingRunnerDoesNotRetainStdout() async throws {
        let result = try await ProcessRunner().run("/usr/bin/python3", ["-c", "print('x'*1000000)"], captureOutput: false)
        XCTAssertTrue(result.isEmpty)
    }
}
