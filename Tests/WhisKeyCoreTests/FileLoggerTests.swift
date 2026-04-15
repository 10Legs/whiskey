import Testing
@testable import WhisKeyCore

@Suite struct FileLoggerTests {

    // MARK: - Initialization

    @Test func loggerHasValidLogFilePath() {
        let logger = FileLogger()
        let path = logger.logFilePath
        #expect(!path.isEmpty)
        #expect(path.contains("Library/Logs/WhisKey"))
    }

    @Test func logFilePathEndsWithFileName() {
        let logger = FileLogger()
        #expect(logger.logFilePath.hasSuffix("whiskey.log"))
    }

    // MARK: - Log Level enumeration

    @Test func logLevelRawValues() {
        #expect(FileLogger.Level.info.rawValue == "INFO ")
        #expect(FileLogger.Level.warn.rawValue == "WARN ")
        #expect(FileLogger.Level.error.rawValue == "ERROR")
    }

    // MARK: - Logging (smoke tests — verify no crash)

    @Test func logDefaultLevel() {
        let logger = FileLogger()
        logger.log(.info, "test message")
    }

    @Test func logWithExplicitLevels() {
        let logger = FileLogger()
        logger.log(.info, "info message")
        logger.log(.warn, "warning message")
        logger.log(.error, "error message")
    }

    @Test func logWithFileAndLineInfo() {
        let logger = FileLogger()
        logger.log(.info, "message", file: #file, line: #line)
    }

    @Test func multipleLogsWithoutCrashing() {
        let logger = FileLogger()
        for i in 1...5 {
            logger.log(.info, "message \(i)")
        }
    }

    @Test func logEmptyMessage() {
        let logger = FileLogger()
        logger.log(.info, "")
    }

    @Test func logLongMessage() {
        let logger = FileLogger()
        logger.log(.warn, String(repeating: "x", count: 10_000))
    }

    @Test func logSpecialCharacters() {
        let logger = FileLogger()
        logger.log(.info, "Special: 🔧 \n\t\"quotes\" & symbols!")
    }

    // MARK: - Shared instance

    @Test func sharedInstanceIsConsistent() {
        let shared1 = FileLogger.shared
        let shared2 = FileLogger.shared
        #expect(shared1.logFilePath == shared2.logFilePath)
    }
}
