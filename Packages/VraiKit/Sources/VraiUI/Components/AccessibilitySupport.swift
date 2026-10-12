import AppKit
import SwiftUI

public enum AccessibilityOverrides {
    public static let reduceMotion = flag("-VraiReduceMotion")
    public static let increaseContrast = flag("-VraiIncreaseContrast")

    static func flag(_ key: String) -> Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: key), index + 1 < arguments.count else { return false }
        return ["YES", "1", "true"].contains(arguments[index + 1])
        #else
        return false
        #endif
    }
}

struct ReduceMotionKey: EnvironmentKey {
    static let defaultValue = AccessibilityOverrides.reduceMotion
}

struct IncreaseContrastKey: EnvironmentKey {
    static let defaultValue = AccessibilityOverrides.increaseContrast
}

extension EnvironmentValues {
    var vraiReduceMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }

    var vraiIncreaseContrast: Bool {
        get { self[IncreaseContrastKey.self] }
        set { self[IncreaseContrastKey.self] = newValue }
    }
}

struct AccessibilityEnvironment: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemMotion
    @Environment(\.colorSchemeContrast) private var systemContrast

    func body(content: Content) -> some View {
        content
            .environment(\.vraiReduceMotion, systemMotion || AccessibilityOverrides.reduceMotion)
            .environment(\.vraiIncreaseContrast, systemContrast == .increased || AccessibilityOverrides.increaseContrast)
    }
}

public extension View {
    func vraiAccessibility() -> some View {
        modifier(AccessibilityEnvironment())
    }
}

extension AnyTransition {
    static func vrai(_ transition: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : transition
    }
}

extension Color.Vrai {
    enum Contrast {
        static let separator = contrastAware(Color.Vrai.separator, Color.Vrai.borderControl)
        static let border = contrastAware(Color.Vrai.border, Color.Vrai.borderControl)
        static let borderStrong = contrastAware(Color.Vrai.borderStrong, Color.Vrai.borderControl)
    }
}

private func contrastAware(_ standard: Color, _ increased: Color) -> Color {
    let base = NSColor(standard)
    let strong = NSColor(increased)
    return Color(nsColor: NSColor(name: nil) { appearance in
        let high = AccessibilityOverrides.increaseContrast || appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]).map { $0 == .accessibilityHighContrastAqua || $0 == .accessibilityHighContrastDarkAqua } == true
        let chosen = high ? strong : base
        var resolved = chosen
        appearance.performAsCurrentDrawingAppearance {
            resolved = chosen.usingColorSpace(.sRGB) ?? chosen
        }
        return resolved
    })
}
