@testable import WhisKeyCore
import XCTest

class FileLoggerTests: XCTestCase {

    // MARK: - Initialization

    func testLoggerHasValidLogFilePath() {
        let logger = FileLogger()
        let path = logger.logFilePath
        XCTAssertFalse(path.isEmpty)
        XCTAssertTrue(path.contains("Library/Logs/WhisKey"))
    }

    func testLogFilePathEndsWithFileName() {
        let logger = FileLogger()
        XCTAssertTrue(logger.logFilePath.hasSuffix("whiskey.log"))
    }

    // MARK: - Log Level enumeration

    func testLogLevelRawValues() {
        XCTAssertEqual(FileLogger.Level.info.rawValue, "INFO ")
        XCTAssertEqual(FileLogger.Level.warn.rawValue, "WARN ")
        XCTAssertEqual(FileLogger.Level.error.rawValue, "ERROR")
    }

    // MARK: - Logging (smoke tests — verify no crash)

    func testLogDefaultLevel() {
        let logger = FileLogger()
        logger.log(.info, "test message")
    }

    func testLogWithExplicitLevels() {
        let logger = FileLogger()
        logger.log(.info, "info message")
        logger.log(.warn, "warning message")
        logger.log(.error, "error message")
    }

    func testLogWithFileAndLineInfo() {
        let logger = FileLogger()
        logger.log(.info, "message", file: #file, line: #line)
    }

    func testMultipleLogsWithoutCrashing() {
        let logger = FileLogger()
        for index in 1...5 {
            logger.log(.info, "message \(index)")
        }
    }

    func testLogEmptyMessage() {
        let logger = FileLogger()
        logger.log(.info, "")
    }

    func testLogLongMessage() {
        let logger = FileLogger()
        logger.log(.warn, String(repeating: "x", count: 10_000))
    }

    func testLogSpecialCharacters() {
        let logger = FileLogger()
        logger.log(.info, "Special: 🔧 \n\t\"quotes\" & symbols!")
    }

    // MARK: - Shared instance

    func testSharedInstanceIsConsistent() {
        let shared1 = FileLogger.shared
        let shared2 = FileLogger.shared
        XCTAssertEqual(shared1.logFilePath, shared2.logFilePath)
    }
}
