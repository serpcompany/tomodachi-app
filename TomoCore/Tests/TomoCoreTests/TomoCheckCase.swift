import XCTest
@testable import TomoCore

// MARK: - The rule checks, as XCTest (#55)
//
// TomoCore's rules are checked by functions that report each result to a `check` closure (TomoCheck.swift); the
// Mac's TOMO_SELFTEST=1 prints them, and these tests turn each into an assertion that fails with the check's own words.
// Nothing here touches a learner's data: every check makes its own temporary folder, and anything that opens the
// default store (TomoGame.shared) finds TOMO_DATA_DIR pointing at a fresh temporary folder, set before any test runs.

@MainActor
class TomoCheckCase: XCTestCase {
    nonisolated override class func setUp() {
        super.setUp()
        TomoTestData.use()
    }

    /// Runs `checks`, failing the test at each check that fails; fails too if no check ran.
    func expect(_ checks: ((Bool, String) -> Void) -> Void, file: StaticString = #filePath, line: UInt = #line) {
        var count = 0, failed: [String] = []
        checks { passed, what in
            count += 1
            if !passed { failed.append(what) }
        }
        for what in failed { XCTFail(what, file: file, line: line) }
        XCTAssertGreaterThan(count, 0, "no checks ran", file: file, line: line)
    }
}

/// The test process's data folder: a fresh temporary one, set once before the first test.
enum TomoTestData {
    nonisolated(unsafe) private static var folder: URL?

    static func use() {
        guard folder == nil else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tomo-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        setenv("TOMO_DATA_DIR", dir.path, 1)
        setenv("TOMO_HEADLESS", "1", 1)          // Tomo stays silent
        folder = dir
    }
}
