import SwiftUI
import WyspaCore

public enum IslandMotion {
    /// Sprężyna rozwijania: szybka, lekko przestrzelona, jak Dynamic Island.
    public static let expand = Animation.spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0)
    public static let collapse = Animation.spring(response: 0.36, dampingFraction: 0.9, blendDuration: 0)
    public static let peek = Animation.spring(response: 0.28, dampingFraction: 0.7, blendDuration: 0)
    public static let tab = Animation.spring(response: 0.32, dampingFraction: 0.86, blendDuration: 0)

    public static func animation(to phase: IslandPhase) -> Animation {
        switch phase {
        case .expanded: expand
        case .peek: peek
        case .collapsed, .hidden: collapse
        }
    }
}
