import SwiftUI

/// Animacje ikon SF Symbols wspólne dla modułów. Przy „Ogranicz ruch” wszystkie są wyłączone.
/// Efekty z macOS 15 (wiggle, rotate, breathe, magiczna zamiana) mają zamienniki z macOS 14.

/// Jednorazowy efekt po kliknięciu.
public enum TapEffect: Sendable {
    case bounce
    case wiggle
    case rotate
}

/// Efekt trwający, dopóki coś się dzieje (zaznaczanie, rozpoznawanie, nagrywanie, para nad kubkiem).
public enum BusyEffect: Sendable {
    case pulse
    case variableColor
    case breathe
}

public extension View {
    /// Zmiana symbolu animowana „magicznie” (np. przekreślenie rysuje się kreską), na macOS 14 — zwykła zamiana.
    func symbolSwapTransition() -> some View {
        modifier(SymbolSwapModifier())
    }

    /// Efekt po kliknięciu: uruchamia się przy każdej zmianie `value`.
    func tapEffect(_ effect: TapEffect, value: Int) -> some View {
        modifier(TapEffectModifier(effect: effect, value: value))
    }

    /// Efekt trwający, dopóki `isActive`.
    func busyEffect(_ effect: BusyEffect, isActive: Bool) -> some View {
        modifier(BusyEffectModifier(effect: effect, isActive: isActive))
    }
}

private struct SymbolSwapModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else if #available(macOS 15, *) {
            content.contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer)))
        } else {
            content.contentTransition(.symbolEffect(.replace.downUp))
        }
    }
}

private struct TapEffectModifier: ViewModifier {
    let effect: TapEffect
    let value: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else if #available(macOS 15, *) {
            switch effect {
            case .bounce: content.symbolEffect(.bounce, value: value)
            case .wiggle: content.symbolEffect(.wiggle.forward, value: value)
            case .rotate: content.symbolEffect(.rotate.byLayer, value: value)
            }
        } else {
            content.symbolEffect(.bounce, value: value)
        }
    }
}

private struct BusyEffectModifier: ViewModifier {
    let effect: BusyEffect
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            switch effect {
            case .pulse: content.symbolEffect(.pulse, options: .repeating, isActive: isActive)
            case .variableColor: content.symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: isActive)
            case .breathe:
                if #available(macOS 15, *) {
                    content.symbolEffect(.breathe, options: .repeating, isActive: isActive)
                } else {
                    content.symbolEffect(.pulse, options: .repeating, isActive: isActive)
                }
            }
        }
    }
}

/// Symbol z dwoma stanami (np. mikrofon / przekreślony mikrofon): zmiana `isOn` przechodzi płynnie w tym samym miejscu.
/// Przy pojawieniu się animuje tylko z `animatesAppearance` (widok powstał razem ze zmianą stanu, np. po wyciszeniu);
/// zwykłe ponowne pokazanie wyspy pokazuje od razu bieżący stan.
public struct ToggleSymbol: View {
    let on: String
    let off: String
    let isOn: Bool
    @State private var shown: Bool?
    @Environment(\.islandStaticSnapshot) private var isStaticSnapshot

    public init(on: String, off: String, isOn: Bool, animatesAppearance: Bool = false) {
        self.on = on
        self.off = off
        self.isOn = isOn
        _shown = State(initialValue: animatesAppearance ? nil : isOn)
    }

    public var body: some View {
        Image(systemName: (isStaticSnapshot ? isOn : (shown ?? !isOn)) ? on : off)
            .symbolSwapTransition()
            .task(id: isOn) {
                if shown == nil { try? await Task.sleep(for: .milliseconds(120)) }
                withAnimation(.snappy) { shown = isOn }
            }
    }
}
