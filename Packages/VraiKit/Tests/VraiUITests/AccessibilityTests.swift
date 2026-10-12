import AppKit
import SwiftUI
import Testing
@testable import VraiUI

@MainActor
struct AccessibilityTests {
    struct RGBA {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double

        func over(_ ground: RGBA) -> RGBA {
            RGBA(red: red * alpha + ground.red * (1 - alpha), green: green * alpha + ground.green * (1 - alpha), blue: blue * alpha + ground.blue * (1 - alpha), alpha: 1)
        }

        var luminance: Double {
            func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

        func contrast(_ other: RGBA) -> Double {
            let a = luminance
            let b = other.luminance
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
    }

    static func resolve(_ color: Color, dark: Bool) -> RGBA {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var result = RGBA(red: 0, green: 0, blue: 0, alpha: 0)
        appearance.performAsCurrentDrawingAppearance {
            let resolved = NSColor(color).usingColorSpace(.sRGB)!
            result = RGBA(red: resolved.redComponent, green: resolved.greenComponent, blue: resolved.blueComponent, alpha: resolved.alphaComponent)
        }
        return result
    }

    static let grounds: [Color] = [Color.Vrai.bg, Color.Vrai.bgSubtle, Color.Vrai.bgSunken, Color.Vrai.surface]

    @Test(arguments: [false, true])
    func increasedContrastHairlinesHoldThreeToOne(dark: Bool) {
        for ground in Self.grounds {
            let base = Self.resolve(ground, dark: dark)
            let line = Self.resolve(Color.Vrai.borderControl, dark: dark).over(base)
            #expect(line.contrast(base) >= 3, "hairline on a ground in \(dark ? "dark" : "light")")
        }
    }

    @Test(arguments: [false, true])
    func focusRingHoldsThreeToOne(dark: Bool) {
        for ground in Self.grounds {
            let base = Self.resolve(ground, dark: dark)
            #expect(Self.resolve(Color.Vrai.focus, dark: dark).contrast(base) >= 3)
        }
    }

    @Test(arguments: [false, true])
    func secondaryTextHoldsFourAndAHalfOnSelections(dark: Bool) {
        for ground in Self.grounds {
            let base = Self.resolve(ground, dark: dark)
            let fills = ground == Color.Vrai.surface ? [Color.Vrai.accentSoft, Color.Vrai.fill] : [Color.Vrai.accentSoft, Color.Vrai.accentSoftStrong, Color.Vrai.fill]
            for fill in fills {
                let selected = Self.resolve(fill, dark: dark).over(base)
                for text in [Color.Vrai.textSecondary, Color.Vrai.textTertiary] {
                    #expect(Self.resolve(text, dark: dark).contrast(selected) >= 4.5)
                }
            }
        }
    }

    @Test(arguments: [false, true])
    func contrastAwareColorsMatchTheirTokensByDefault(dark: Bool) {
        let pairs: [(Color, Color)] = [
            (Color.Vrai.Contrast.separator, Color.Vrai.separator),
            (Color.Vrai.Contrast.border, Color.Vrai.border),
            (Color.Vrai.Contrast.borderStrong, Color.Vrai.borderStrong)
        ]
        for (aware, token) in pairs {
            let left = Self.resolve(aware, dark: dark)
            let right = Self.resolve(token, dark: dark)
            #expect(abs(left.red - right.red) < 0.002 && abs(left.green - right.green) < 0.002 && abs(left.blue - right.blue) < 0.002 && abs(left.alpha - right.alpha) < 0.002)
        }
    }

    @Test func overridesStayOffWithoutLaunchArguments() {
        #expect(AccessibilityOverrides.reduceMotion == false)
        #expect(AccessibilityOverrides.increaseContrast == false)
    }
}
