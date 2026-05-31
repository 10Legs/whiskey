import Foundation

public enum WaveformStyle: String, Codable, CaseIterable {
    case pulseRibbon
    case rodArray
    case liquidMercury

    public var displayName: String {
        switch self {
        case .pulseRibbon:   return "Pulse Ribbon"
        case .rodArray:      return "Rod Array"
        case .liquidMercury: return "Liquid Mercury"
        }
    }
}
