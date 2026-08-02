import XCTest
@testable import SharedLogging

@MainActor
final class LogStoreTests: XCTestCase {
    func testLogAppendsEntry() {
        let store = LogStore.shared
        // A bogus App Group ID so this deliberately exercises the
        // Application Support fallback path instead of touching the real
        // group.com.dsward.antennahead container the actual apps use.
        store.configure(appName: "SharedLoggingTests-\(UUID().uuidString)",
                        appGroupID: "group.com.dsward.antennahead.nonexistent-test-group")
        store.clear()

        store.log(.info, source: "UnitTest", "hello world")

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.message, "hello world")
        XCTAssertEqual(store.entries.first?.source, "UnitTest")
        XCTAssertEqual(store.entries.first?.level, .info)
    }

    func testLevelOrdering() {
        XCTAssertLessThan(LogLevel.debug, LogLevel.info)
        XCTAssertLessThan(LogLevel.info, LogLevel.warning)
        XCTAssertLessThan(LogLevel.warning, LogLevel.error)
    }
}
