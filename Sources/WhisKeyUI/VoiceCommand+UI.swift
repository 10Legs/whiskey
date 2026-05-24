import WhisKeyCore

extension VoiceCommand {
    var displayLabel: String {
        switch self {
        case .insertNewParagraph:  return "New Paragraph"
        case .insertNewLine:       return "New Line"
        case .deleteLastUtterance: return "Scratch That"
        case .uppercaseLastWord:   return "All Caps"
        case .insertPeriod:        return "Period"
        case .insertComma:         return "Comma"
        case .insertQuestionMark:  return "Question Mark"
        }
    }
}
