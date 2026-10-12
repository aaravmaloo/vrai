import SwiftUI
import AppKit

public enum Vrai {}

private func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) == nil ? light : dark
    })
}

private func systemAccent(alpha: CGFloat = 1, darkAlpha: CGFloat? = nil, light: CGFloat = 0, dark: CGFloat = 0) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil
        var base = NSColor.systemBlue
        appearance.performAsCurrentDrawingAppearance {
            base = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor.systemBlue
        }
        let shift = isDark ? dark : light
        let shifted = shift == 0 ? base : (base.blended(withFraction: abs(shift), of: shift > 0 ? .white : .black) ?? base)
        return shifted.withAlphaComponent(isDark ? darkAlpha ?? alpha : alpha)
    })
}

public extension Color {
    enum Vrai {
        public static let bg = dynamic(NSColor(srgbRed: 1.0000, green: 1.0000, blue: 1.0000, alpha: 1.000), NSColor(srgbRed: 0.0902, green: 0.0902, blue: 0.1020, alpha: 1.000))
        public static let bgSubtle = dynamic(NSColor(srgbRed: 0.9686, green: 0.9686, blue: 0.9765, alpha: 1.000), NSColor(srgbRed: 0.1137, green: 0.1137, blue: 0.1294, alpha: 1.000))
        public static let bgSunken = dynamic(NSColor(srgbRed: 0.9373, green: 0.9373, blue: 0.9529, alpha: 1.000), NSColor(srgbRed: 0.0706, green: 0.0706, blue: 0.0824, alpha: 1.000))
        public static let surface = dynamic(NSColor(srgbRed: 1.0000, green: 1.0000, blue: 1.0000, alpha: 1.000), NSColor(srgbRed: 0.1373, green: 0.1373, blue: 0.1569, alpha: 1.000))
        public static let surfaceRaised = dynamic(NSColor(srgbRed: 1.0000, green: 1.0000, blue: 1.0000, alpha: 1.000), NSColor(srgbRed: 0.1647, green: 0.1647, blue: 0.1882, alpha: 1.000))
        public static let fill = dynamic(NSColor(srgbRed: 0.1176, green: 0.1176, blue: 0.1961, alpha: 0.050), NSColor(srgbRed: 0.9216, green: 0.9216, blue: 0.9804, alpha: 0.060))
        public static let fillHover = dynamic(NSColor(srgbRed: 0.1176, green: 0.1176, blue: 0.1961, alpha: 0.080), NSColor(srgbRed: 0.9216, green: 0.9216, blue: 0.9804, alpha: 0.090))
        public static let fillActive = dynamic(NSColor(srgbRed: 0.1176, green: 0.1176, blue: 0.1961, alpha: 0.120), NSColor(srgbRed: 0.9216, green: 0.9216, blue: 0.9804, alpha: 0.120))
        public static let fillStrong = dynamic(NSColor(srgbRed: 0.1176, green: 0.1176, blue: 0.1961, alpha: 0.200), NSColor(srgbRed: 0.9216, green: 0.9216, blue: 0.9804, alpha: 0.220))
        public static let border = dynamic(NSColor(srgbRed: 0.1176, green: 0.1176, blue: 0.1961, alpha: 0.110), NSColor(srgbRed: 0.9216, green: 0.9216, blue: 0.9804, alpha: 0.100))
        public static let borderStrong = dynamic(NSColor(srgbRed: 0.1176, green: 0.1176, blue: 0.1961, alpha: 0.240), NSColor(srgbRed: 0.9216, green: 0.9216, blue: 0.9804, alpha: 0.220))
        public static let borderControl = dynamic(NSColor(srgbRed: 0.1176, green: 0.1176, blue: 0.1961, alpha: 0.520), NSColor(srgbRed: 0.9216, green: 0.9216, blue: 0.9804, alpha: 0.440))
        public static let separator = dynamic(NSColor(srgbRed: 0.1176, green: 0.1176, blue: 0.1961, alpha: 0.080), NSColor(srgbRed: 0.9216, green: 0.9216, blue: 0.9804, alpha: 0.070))
        public static let text = dynamic(NSColor(srgbRed: 0.1059, green: 0.1059, blue: 0.1255, alpha: 1.000), NSColor(srgbRed: 0.9490, green: 0.9490, blue: 0.9608, alpha: 1.000))
        public static let textSecondary = dynamic(NSColor(srgbRed: 0.3020, green: 0.3020, blue: 0.3412, alpha: 1.000), NSColor(srgbRed: 0.7412, green: 0.7412, blue: 0.7765, alpha: 1.000))
        public static let textTertiary = dynamic(NSColor(srgbRed: 0.3647, green: 0.3647, blue: 0.4078, alpha: 1.000), NSColor(srgbRed: 0.6314, green: 0.6314, blue: 0.6745, alpha: 1.000))
        public static let textDisabled = dynamic(NSColor(srgbRed: 0.6471, green: 0.6471, blue: 0.6863, alpha: 1.000), NSColor(srgbRed: 0.3569, green: 0.3569, blue: 0.3961, alpha: 1.000))
        public static let onAccent = dynamic(NSColor(srgbRed: 1.0000, green: 1.0000, blue: 1.0000, alpha: 1.000), NSColor(srgbRed: 1.0000, green: 1.0000, blue: 1.0000, alpha: 1.000))
        public static let accent = systemAccent()
        public static let accentHover = systemAccent(light: -0.1, dark: 0.08)
        public static let accentActive = systemAccent(light: -0.2, dark: -0.12)
        public static let accentText = systemAccent()
        public static let accentSoft = systemAccent(alpha: 0.12, darkAlpha: 0.2)
        public static let accentSoftStrong = systemAccent(alpha: 0.17, darkAlpha: 0.27)
        public static let focus = systemAccent()
        public static let success = dynamic(NSColor(srgbRed: 0.0863, green: 0.4745, blue: 0.2275, alpha: 1.000), NSColor(srgbRed: 0.2980, green: 0.7804, blue: 0.4549, alpha: 1.000))
        public static let successSoft = dynamic(NSColor(srgbRed: 0.0863, green: 0.6275, blue: 0.2745, alpha: 0.110), NSColor(srgbRed: 0.2980, green: 0.7804, blue: 0.4549, alpha: 0.120))
        public static let warning = dynamic(NSColor(srgbRed: 0.5608, green: 0.3608, blue: 0.0000, alpha: 1.000), NSColor(srgbRed: 0.9098, green: 0.6902, blue: 0.2902, alpha: 1.000))
        public static let warningSoft = dynamic(NSColor(srgbRed: 0.8706, green: 0.5882, blue: 0.0000, alpha: 0.140), NSColor(srgbRed: 0.9098, green: 0.6902, blue: 0.2902, alpha: 0.120))
        public static let danger = dynamic(NSColor(srgbRed: 0.7843, green: 0.1255, blue: 0.1686, alpha: 1.000), NSColor(srgbRed: 1.0000, green: 0.4392, blue: 0.4392, alpha: 1.000))
        public static let dangerSoft = dynamic(NSColor(srgbRed: 0.8392, green: 0.1255, blue: 0.1725, alpha: 0.090), NSColor(srgbRed: 1.0000, green: 0.4392, blue: 0.4392, alpha: 0.120))
        public static let onDanger = dynamic(NSColor(srgbRed: 1.0000, green: 1.0000, blue: 1.0000, alpha: 1.000), NSColor(srgbRed: 0.1020, green: 0.0431, blue: 0.0471, alpha: 1.000))
        public static let lane1 = systemAccent()
        public static let lane2 = dynamic(NSColor(srgbRed: 0.7216, green: 0.2392, blue: 0.0431, alpha: 1.000), NSColor(srgbRed: 1.0000, green: 0.6078, blue: 0.3294, alpha: 1.000))
        public static let lane3 = dynamic(NSColor(srgbRed: 0.0863, green: 0.4745, blue: 0.2902, alpha: 1.000), NSColor(srgbRed: 0.3098, green: 0.8157, blue: 0.5412, alpha: 1.000))
        public static let lane4 = dynamic(NSColor(srgbRed: 0.7529, green: 0.0941, blue: 0.4157, alpha: 1.000), NSColor(srgbRed: 1.0000, green: 0.4745, blue: 0.7216, alpha: 1.000))
        public static let lane5 = dynamic(NSColor(srgbRed: 0.0549, green: 0.4549, blue: 0.5647, alpha: 1.000), NSColor(srgbRed: 0.2196, green: 0.7765, blue: 0.8667, alpha: 1.000))
        public static let lane6 = dynamic(NSColor(srgbRed: 0.5412, green: 0.3647, blue: 0.0000, alpha: 1.000), NSColor(srgbRed: 0.9490, green: 0.7882, blue: 0.2980, alpha: 1.000))
        public static let lane7 = dynamic(NSColor(srgbRed: 0.4784, green: 0.2353, blue: 0.9412, alpha: 1.000), NSColor(srgbRed: 0.7333, green: 0.6078, blue: 1.0000, alpha: 1.000))
        public static let lane8 = dynamic(NSColor(srgbRed: 0.7765, green: 0.1569, blue: 0.1569, alpha: 1.000), NSColor(srgbRed: 1.0000, green: 0.4824, blue: 0.4824, alpha: 1.000))
        public static let onLane = dynamic(NSColor(srgbRed: 1.0000, green: 1.0000, blue: 1.0000, alpha: 1.000), NSColor(srgbRed: 0.0667, green: 0.0667, blue: 0.0824, alpha: 1.000))
        public static let statusAdded = dynamic(NSColor(srgbRed: 0.0863, green: 0.4745, blue: 0.2275, alpha: 1.000), NSColor(srgbRed: 0.2980, green: 0.7804, blue: 0.4549, alpha: 1.000))
        public static let statusModified = dynamic(NSColor(srgbRed: 0.5608, green: 0.3608, blue: 0.0000, alpha: 1.000), NSColor(srgbRed: 0.9098, green: 0.6902, blue: 0.2902, alpha: 1.000))
        public static let statusDeleted = dynamic(NSColor(srgbRed: 0.7843, green: 0.1255, blue: 0.1686, alpha: 1.000), NSColor(srgbRed: 1.0000, green: 0.4392, blue: 0.4392, alpha: 1.000))
        public static let statusRenamed = dynamic(NSColor(srgbRed: 0.4275, green: 0.2078, blue: 0.8392, alpha: 1.000), NSColor(srgbRed: 0.7333, green: 0.6078, blue: 1.0000, alpha: 1.000))
        public static let statusUntracked = dynamic(NSColor(srgbRed: 0.0549, green: 0.4353, blue: 0.5412, alpha: 1.000), NSColor(srgbRed: 0.2196, green: 0.7765, blue: 0.8667, alpha: 1.000))
        public static let statusConflicted = dynamic(NSColor(srgbRed: 0.6902, green: 0.0863, blue: 0.3725, alpha: 1.000), NSColor(srgbRed: 1.0000, green: 0.4745, blue: 0.7216, alpha: 1.000))
        public static let diffAddBg = dynamic(NSColor(srgbRed: 0.0863, green: 0.6275, blue: 0.2745, alpha: 0.100), NSColor(srgbRed: 0.2980, green: 0.7804, blue: 0.4549, alpha: 0.120))
        public static let diffAddWord = dynamic(NSColor(srgbRed: 0.0863, green: 0.6275, blue: 0.2745, alpha: 0.200), NSColor(srgbRed: 0.2980, green: 0.7804, blue: 0.4549, alpha: 0.220))
        public static let diffAddGutter = dynamic(NSColor(srgbRed: 0.0863, green: 0.6275, blue: 0.2745, alpha: 0.160), NSColor(srgbRed: 0.2980, green: 0.7804, blue: 0.4549, alpha: 0.140))
        public static let diffDelBg = dynamic(NSColor(srgbRed: 0.8392, green: 0.1255, blue: 0.1725, alpha: 0.080), NSColor(srgbRed: 1.0000, green: 0.4392, blue: 0.4392, alpha: 0.110))
        public static let diffDelWord = dynamic(NSColor(srgbRed: 0.8392, green: 0.1255, blue: 0.1725, alpha: 0.170), NSColor(srgbRed: 1.0000, green: 0.4392, blue: 0.4392, alpha: 0.220))
        public static let diffDelGutter = dynamic(NSColor(srgbRed: 0.8392, green: 0.1255, blue: 0.1725, alpha: 0.130), NSColor(srgbRed: 1.0000, green: 0.4392, blue: 0.4392, alpha: 0.130))
        public static let diffHunkBg = systemAccent(alpha: 0.06, darkAlpha: 0.08)
        public static let conflictOurs = dynamic(NSColor(srgbRed: 0.1843, green: 0.3216, blue: 0.9020, alpha: 1.000), NSColor(srgbRed: 0.5608, green: 0.6471, blue: 1.0000, alpha: 1.000))
        public static let conflictOursBg = dynamic(NSColor(srgbRed: 0.2118, green: 0.3569, blue: 0.9490, alpha: 0.080), NSColor(srgbRed: 0.3529, green: 0.4706, blue: 1.0000, alpha: 0.130))
        public static let conflictTheirs = dynamic(NSColor(srgbRed: 0.4275, green: 0.2078, blue: 0.8392, alpha: 1.000), NSColor(srgbRed: 0.7333, green: 0.6078, blue: 1.0000, alpha: 1.000))
        public static let conflictTheirsBg = dynamic(NSColor(srgbRed: 0.4784, green: 0.2353, blue: 0.9412, alpha: 0.080), NSColor(srgbRed: 0.7333, green: 0.6078, blue: 1.0000, alpha: 0.130))
        public static let syntaxKeyword = dynamic(NSColor(srgbRed: 0.6078, green: 0.1647, blue: 0.5725, alpha: 1.000), NSColor(srgbRed: 1.0000, green: 0.5490, blue: 0.7529, alpha: 1.000))
        public static let syntaxString = dynamic(NSColor(srgbRed: 0.7216, green: 0.1412, blue: 0.1020, alpha: 1.000), NSColor(srgbRed: 1.0000, green: 0.6039, blue: 0.5451, alpha: 1.000))
        public static let syntaxNumber = dynamic(NSColor(srgbRed: 0.1686, green: 0.1647, blue: 0.7765, alpha: 1.000), NSColor(srgbRed: 0.8510, green: 0.7882, blue: 0.4863, alpha: 1.000))
        public static let syntaxComment = dynamic(NSColor(srgbRed: 0.3216, green: 0.3765, blue: 0.4235, alpha: 1.000), NSColor(srgbRed: 0.6039, green: 0.6471, blue: 0.6902, alpha: 1.000))
        public static let syntaxType = dynamic(NSColor(srgbRed: 0.0510, green: 0.3725, blue: 0.4549, alpha: 1.000), NSColor(srgbRed: 0.4196, green: 0.8745, blue: 1.0000, alpha: 1.000))
        public static let syntaxFunction = dynamic(NSColor(srgbRed: 0.1804, green: 0.4000, blue: 0.3137, alpha: 1.000), NSColor(srgbRed: 0.4863, green: 0.8118, blue: 0.7098, alpha: 1.000))
        public static let syntaxAttribute = dynamic(NSColor(srgbRed: 0.5020, green: 0.3412, blue: 0.0392, alpha: 1.000), NSColor(srgbRed: 0.8784, green: 0.6588, blue: 0.4549, alpha: 1.000))
        public static let glassFill = dynamic(NSColor(srgbRed: 0.9647, green: 0.9647, blue: 0.9804, alpha: 0.740), NSColor(srgbRed: 0.1333, green: 0.1333, blue: 0.1569, alpha: 0.760))
        public static let glassRim = dynamic(NSColor(srgbRed: 1.0000, green: 1.0000, blue: 1.0000, alpha: 0.900), NSColor(srgbRed: 1.0000, green: 1.0000, blue: 1.0000, alpha: 0.120))
        public static let glassEdge = dynamic(NSColor(srgbRed: 0.0784, green: 0.0784, blue: 0.1569, alpha: 0.100), NSColor(srgbRed: 0.0000, green: 0.0000, blue: 0.0000, alpha: 0.550))
        public static let scrim = dynamic(NSColor(srgbRed: 0.9412, green: 0.9412, blue: 0.9608, alpha: 0.550), NSColor(srgbRed: 0.0314, green: 0.0314, blue: 0.0392, alpha: 0.550))
        public static let trafficClose = dynamic(NSColor(srgbRed: 1.0000, green: 0.3725, blue: 0.3412, alpha: 1.000), NSColor(srgbRed: 1.0000, green: 0.3725, blue: 0.3412, alpha: 1.000))
        public static let trafficMinimize = dynamic(NSColor(srgbRed: 0.9961, green: 0.7373, blue: 0.1804, alpha: 1.000), NSColor(srgbRed: 0.9961, green: 0.7373, blue: 0.1804, alpha: 1.000))
        public static let trafficZoom = dynamic(NSColor(srgbRed: 0.1569, green: 0.7843, blue: 0.2510, alpha: 1.000), NSColor(srgbRed: 0.1569, green: 0.7843, blue: 0.2510, alpha: 1.000))
        public static let trafficIdle = dynamic(NSColor(srgbRed: 0.1176, green: 0.1176, blue: 0.1961, alpha: 0.160), NSColor(srgbRed: 0.9216, green: 0.9216, blue: 0.9804, alpha: 0.180))
        public static let desktopGround = dynamic(NSColor(srgbRed: 0.8510, green: 0.8667, blue: 0.9020, alpha: 1.000), NSColor(srgbRed: 0.0471, green: 0.0510, blue: 0.0706, alpha: 1.000))
        public static let desktopLine1 = dynamic(NSColor(srgbRed: 0.6235, green: 0.6902, blue: 0.9608, alpha: 1.000), NSColor(srgbRed: 0.1412, green: 0.2000, blue: 0.6039, alpha: 1.000))
        public static let desktopLine2 = dynamic(NSColor(srgbRed: 0.9529, green: 0.7059, blue: 0.5529, alpha: 1.000), NSColor(srgbRed: 0.4784, green: 0.2039, blue: 0.0706, alpha: 1.000))
        public static let desktopLine3 = dynamic(NSColor(srgbRed: 0.6235, green: 0.8471, blue: 0.7333, alpha: 1.000), NSColor(srgbRed: 0.0588, green: 0.3176, blue: 0.1961, alpha: 1.000))
        public static func lane(_ index: Int) -> Color {
            [lane1, lane2, lane3, lane4, lane5, lane6, lane7, lane8][((index % 8) + 8) % 8]
        }
    }
}

public extension Vrai {
    enum Space {
        public static let s2: CGFloat = 2
        public static let s4: CGFloat = 4
        public static let s6: CGFloat = 6
        public static let s8: CGFloat = 8
        public static let s10: CGFloat = 10
        public static let s12: CGFloat = 12
        public static let s16: CGFloat = 16
        public static let s20: CGFloat = 20
        public static let s24: CGFloat = 24
        public static let s32: CGFloat = 32
        public static let s40: CGFloat = 40
        public static let s48: CGFloat = 48
        public static let s64: CGFloat = 64
    }
    enum Radius {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 6
        public static let md: CGFloat = 8
        public static let lg: CGFloat = 12
        public static let xl: CGFloat = 16
        public static let window: CGFloat = 20
        public static let full: CGFloat = 999
    }
    enum Size {
        public static let toolbar: CGFloat = 52
        public static let sidebar: CGFloat = 248
        public static let inspector: CGFloat = 340
        public static let filelist: CGFloat = 280
        public static let console: CGFloat = 220
        public static let row: CGFloat = 28
        public static let rowCompact: CGFloat = 24
        public static let rowComfortable: CGFloat = 32
        public static let controlSm: CGFloat = 22
        public static let control: CGFloat = 28
        public static let controlLg: CGFloat = 34
        public static let toolbarItem: CGFloat = 32
        public static let iconSm: CGFloat = 16
        public static let icon: CGFloat = 20
        public static let iconLg: CGFloat = 24
        public static let lane: CGFloat = 14
        public static let node: CGFloat = 9
        public static let line: CGFloat = 2
        public static let focusHalo: CGFloat = 3
        public static let pill: CGFloat = 18
        public static let sheet: CGFloat = 520
        public static let sheetWide: CGFloat = 720
        public static let palette: CGFloat = 640
        public static let menu: CGFloat = 220
        public static let field: CGFloat = 280
        public static let alert: CGFloat = 260
        public static let colAuthor: CGFloat = 160
        public static let colDate: CGFloat = 88
        public static let colHash: CGFloat = 76
        public static let colBlame: CGFloat = 240
    }
    enum Duration {
        public static let instant: Double = 0.08
        public static let fast: Double = 0.14
        public static let base: Double = 0.2
        public static let slow: Double = 0.32
        public static let graph: Double = 0.48
    }
}

public extension Font {
    enum Vrai {
        public static let display = Font.system(size: 34, weight: .bold)
        public static let title1 = Font.system(size: 22, weight: .bold)
        public static let title2 = Font.system(size: 17, weight: .semibold)
        public static let lead = Font.system(size: 17, weight: .regular)
        public static let title3 = Font.system(size: 15, weight: .semibold)
        public static let headline = Font.system(size: 13, weight: .semibold)
        public static let body = Font.system(size: 13, weight: .regular)
        public static let callout = Font.system(size: 12, weight: .regular)
        public static let caption = Font.system(size: 11, weight: .regular)
        public static let captionStrong = Font.system(size: 11, weight: .semibold)
        public static let overline = Font.system(size: 10, weight: .semibold)
        public static let code = Font.system(size: 12, weight: .regular, design: .monospaced)
        public static let codeStrong = Font.system(size: 12, weight: .semibold, design: .monospaced)
        public static let codeSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
    }
}

public extension Animation {
    enum Vrai {
        public static let standardInstant = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.08)
        public static let standardFast = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.14)
        public static let standardBase = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.2)
        public static let standardSlow = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.32)
        public static let standardGraph = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.48)
        public static let outFast = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.14)
        public static let outBase = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.2)
        public static let outSlow = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.32)
        public static let outGraph = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.48)
        public static let springGraph = Animation.timingCurve(0.34, 1.4, 0.64, 1, duration: 0.48)
    }
}
