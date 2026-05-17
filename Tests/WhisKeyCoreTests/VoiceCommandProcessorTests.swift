import XCTest
@testable import WhisKeyCore

final class VoiceCommandProcessorTests: XCTestCase {

    private let processor = VoiceCommandProcessor()

    // MARK: - Single command detection & stripping

    func test_newParagraph_detectedAndStripped() {
        let result = processor.process("Hello world new paragraph how are you")
        XCTAssertEqual(result.commands, [.insertNewParagraph])
        XCTAssertFalse(result.cleanedText.lowercased().contains("new paragraph"))
        XCTAssertTrue(result.cleanedText.contains("Hello world"))
        XCTAssertTrue(result.cleanedText.contains("how are you"))
    }

    func test_newLine_detectedAndStripped() {
        let result = processor.process("first sentence new line second sentence")
        XCTAssertEqual(result.commands, [.insertNewLine])
        XCTAssertFalse(result.cleanedText.lowercased().contains("new line"))
        XCTAssertTrue(result.cleanedText.contains("first sentence"))
        XCTAssertTrue(result.cleanedText.contains("second sentence"))
    }

    func test_scratchThat_detectedAndStripped() {
        let result = processor.process("I made a mistake scratch that")
        XCTAssertEqual(result.commands, [.deleteLastUtterance])
        XCTAssertFalse(result.cleanedText.lowercased().contains("scratch that"))
        XCTAssertTrue(result.cleanedText.contains("I made a mistake"))
    }

    func test_deleteThat_detectedAndStripped() {
        let result = processor.process("wrong word delete that")
        XCTAssertEqual(result.commands, [.deleteLastUtterance])
        XCTAssertFalse(result.cleanedText.lowercased().contains("delete that"))
    }

    func test_allCaps_detectedAndStripped() {
        let result = processor.process("the answer is yes all caps")
        XCTAssertEqual(result.commands, [.uppercaseLastWord])
        XCTAssertFalse(result.cleanedText.lowercased().contains("all caps"))
        XCTAssertTrue(result.cleanedText.contains("the answer is yes"))
    }

    func test_period_detectedAndStripped() {
        let result = processor.process("end of sentence period")
        XCTAssertEqual(result.commands, [.insertPeriod])
        XCTAssertFalse(result.cleanedText.lowercased().contains("period"))
        XCTAssertTrue(result.cleanedText.contains("end of sentence"))
    }

    func test_comma_detectedAndStripped() {
        let result = processor.process("apples comma oranges and pears")
        XCTAssertEqual(result.commands, [.insertComma])
        XCTAssertFalse(result.cleanedText.lowercased().contains("comma"))
        XCTAssertTrue(result.cleanedText.contains("apples"))
        XCTAssertTrue(result.cleanedText.contains("oranges and pears"))
    }

    func test_questionMark_detectedAndStripped() {
        let result = processor.process("are you there question mark")
        XCTAssertEqual(result.commands, [.insertQuestionMark])
        XCTAssertFalse(result.cleanedText.lowercased().contains("question mark"))
        XCTAssertTrue(result.cleanedText.contains("are you there"))
    }

    // MARK: - Case-insensitive matching

    func test_caseInsensitive_uppercase() {
        let result = processor.process("hello NEW PARAGRAPH world")
        XCTAssertEqual(result.commands, [.insertNewParagraph])
        XCTAssertFalse(result.cleanedText.lowercased().contains("new paragraph"))
    }

    func test_caseInsensitive_mixedCase() {
        let result = processor.process("stop Scratch That now")
        XCTAssertEqual(result.commands, [.deleteLastUtterance])
        XCTAssertFalse(result.cleanedText.lowercased().contains("scratch that"))
    }

    func test_caseInsensitive_Comma() {
        let result = processor.process("one Comma two")
        XCTAssertEqual(result.commands, [.insertComma])
    }

    // MARK: - Multiple commands in one utterance

    func test_multipleCommands_newParagraphAndComma() {
        let result = processor.process("hello new paragraph the answer is yes comma and more")
        XCTAssertTrue(result.commands.contains(.insertNewParagraph))
        XCTAssertTrue(result.commands.contains(.insertComma))
        XCTAssertFalse(result.cleanedText.lowercased().contains("new paragraph"))
        XCTAssertFalse(result.cleanedText.lowercased().contains("comma"))
    }

    func test_multipleCommands_orderPreserved() {
        let result = processor.process("start new line middle comma end")
        let newLineIdx = result.commands.firstIndex(of: .insertNewLine)
        let commaIdx   = result.commands.firstIndex(of: .insertComma)
        XCTAssertNotNil(newLineIdx)
        XCTAssertNotNil(commaIdx)
        if let a = newLineIdx, let b = commaIdx {
            XCTAssertLessThan(a, b, "new line should appear before comma in command list")
        }
    }

    func test_allCommandsInOneUtterance() {
        let input = "alpha new paragraph beta new line gamma scratch that delta all caps epsilon period zeta comma eta question mark"
        let result = processor.process(input)
        XCTAssertTrue(result.commands.contains(.insertNewParagraph))
        XCTAssertTrue(result.commands.contains(.insertNewLine))
        XCTAssertTrue(result.commands.contains(.deleteLastUtterance))
        XCTAssertTrue(result.commands.contains(.uppercaseLastWord))
        XCTAssertTrue(result.commands.contains(.insertPeriod))
        XCTAssertTrue(result.commands.contains(.insertComma))
        XCTAssertTrue(result.commands.contains(.insertQuestionMark))
        // None of the command phrases should survive in the cleaned text.
        let lower = result.cleanedText.lowercased()
        XCTAssertFalse(lower.contains("new paragraph"))
        XCTAssertFalse(lower.contains("new line"))
        XCTAssertFalse(lower.contains("scratch that"))
        XCTAssertFalse(lower.contains("all caps"))
        XCTAssertFalse(lower.contains("question mark"))
    }

    // MARK: - Unknown phrases pass through unchanged

    func test_unknownPhrase_passesThrough() {
        let input = "This is just normal dictation without any commands."
        let result = processor.process(input)
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertEqual(result.cleanedText, input)
    }

    func test_nearMiss_notMatched() {
        // "new paragraph" as a substring of a larger word should NOT match.
        // This tests that boundary checking works.
        let result = processor.process("I am talking about a new paradigm here")
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertEqual(result.cleanedText, "I am talking about a new paradigm here")
    }

    func test_emptyInput_returnsEmpty() {
        let result = processor.process("")
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertEqual(result.cleanedText, "")
    }

    func test_onlyWhitespace_returnsEmpty() {
        let result = processor.process("   ")
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertEqual(result.cleanedText, "")
    }

    // MARK: - Text preservation around stripped phrases

    func test_textPreserved_beforeAndAfterCommand() {
        let result = processor.process("Hello new paragraph World")
        XCTAssertTrue(result.cleanedText.contains("Hello"))
        XCTAssertTrue(result.cleanedText.contains("World"))
    }

    func test_commandAtStart_textAfterPreserved() {
        let result = processor.process("new paragraph this is text")
        XCTAssertFalse(result.cleanedText.lowercased().contains("new paragraph"))
        XCTAssertTrue(result.cleanedText.contains("this is text"))
    }

    func test_commandAtEnd_textBeforePreserved() {
        let result = processor.process("this is text new paragraph")
        XCTAssertFalse(result.cleanedText.lowercased().contains("new paragraph"))
        XCTAssertTrue(result.cleanedText.contains("this is text"))
    }

    func test_commandOnly_producesEmptyCleanedText() {
        let result = processor.process("new paragraph")
        XCTAssertEqual(result.commands, [.insertNewParagraph])
        XCTAssertEqual(result.cleanedText, "")
    }

    // MARK: - deleteThat vs scratchThat both map to deleteLastUtterance

    func test_bothDeletePhrases_mapToSameCommand() {
        let r1 = processor.process("oops scratch that")
        let r2 = processor.process("oops delete that")
        XCTAssertEqual(r1.commands, [.deleteLastUtterance])
        XCTAssertEqual(r2.commands, [.deleteLastUtterance])
    }
}
