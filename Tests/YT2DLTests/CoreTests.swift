import XCTest
@testable import YT2DL
final class CoreTests: XCTestCase {
    func testRejectsSpoofedHostsAndShellInput() {
        for link in ["https://youtube.com.evil.test/watch?v=abcdefghijk", "file:///tmp/file", "--exec", "$(touch /tmp/bad)", "https://evil.test/youtube.com/watch?v=abcdefghijk"] {
            XCTAssertThrowsError(try Links.parse(link))
        }
    }
    func testMultipleLinksDeduplicate() throws {
        let value = "https://youtu.be/abcdefghijk"
        XCTAssertEqual(try Links.parse("\(value)\n\(value)"), [value])
        XCTAssertTrue(Links.playlist("https://www.youtube.com/playlist?list=WL"))
    }
    func testActualUpstreamEnvelopeDecodesGroupedFormats() throws {
        let json = """
        {"status":true,"message":"OK","data":{"videoId":"abcdefghijk","title":"Film","thumbnail":"","author":"Autor","duration":125,"viewCount":10,"formats":{"bundle":[{"quality":"720p","codec":"H264","size":"12 MB","mime":"video/mp4","token":"token"}],"video":[],"audio":[]}}}
        """
        let result = try JSONDecoder().decode(APIEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(result.data?.formats?.bundle.first?.token, "token")
        XCTAssertEqual(result.data?.time, "2:05")
    }
    func testDownloadArgumentsKeepURLAsSingleArgument() {
        let video = Video(videoId: "abcdefghijk", title: "Film", thumbnail: "", author: "", duration: 0, viewCount: 0)
        var options = Options(); options.mode = .audio; options.folder = "/tmp/a folder"; options.audioFormat = "opus"
        let args = LocalEngine.arguments(Job(video: video, options: options))
        XCTAssertEqual(Array(args.suffix(2)), ["--", video.url])
        XCTAssertTrue(args.contains("/tmp/a folder")); XCTAssertTrue(args.contains("opus"))
        XCTAssertFalse(args.contains("--cookies-from-browser"))
    }
    func testCredentialURLsRejected() {
        XCTAssertThrowsError(try ServerAPI.endpoint("https://user:secret@localhost:3000", path: "api/video-info"))
    }
    func testRunnerDrainsLargeStderrWithoutDeadlock() async throws {
        let result = try await ProcessRunner().run("/usr/bin/python3", ["-c", "import sys; sys.stderr.write('x'*200000); print('ok')"])
        XCTAssertEqual(String(decoding: result, as: UTF8.self), "ok\n")
    }
    func testRunnerCancellationBeforeStart() async {
        let runner = ProcessRunner(); runner.cancel()
        do { _ = try await runner.run("/usr/bin/true", []); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testFileNamesCannotEscapeFolder() {
        XCTAssertFalse(Links.safeName("../../a/b").contains("/"))
        XCTAssertEqual(Links.safeName("  "), "video")
    }
}
