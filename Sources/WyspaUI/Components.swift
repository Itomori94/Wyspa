import SwiftUI

/// Wciśnięcie zmniejsza element, jak przyciski w Dynamic Island.
public struct IslandPressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Półprzezroczysta kapsuła na czarnym tle wyspy, z wyraźnym stanem hover i wciśnięcia.
public struct IslandCapsuleButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        CapsuleLabel(configuration: configuration)
    }

    private struct CapsuleLabel: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.28 : (isHovered ? 0.2 : 0.12))))
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.15), value: isHovered)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
        }
    }
}
