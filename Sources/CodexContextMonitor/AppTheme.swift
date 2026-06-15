import AppKit
import SwiftUI

enum AppThemeChoice: String, CaseIterable, Identifiable {
    case light
    case dark
    case dracula
    case tokyoNight

    static let userDefaultsKey = "appTheme"
    static let menuChoices: [AppThemeChoice] = [.light, .dark, .dracula, .tokyoNight]

    var id: String {
        rawValue
    }

    static var saved: AppThemeChoice {
        guard let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey),
              let theme = AppThemeChoice(rawValue: rawValue) else {
            return .dark
        }
        return theme
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.userDefaultsKey)
    }

    func displayName(_ text: AppText) -> String {
        switch self {
        case .light:
            text.lightTheme
        case .dark:
            text.darkTheme
        case .dracula:
            "Dracula"
        case .tokyoNight:
            "Tokyo Night"
        }
    }

    var systemImage: String {
        switch self {
        case .light:
            "sun.max"
        case .dark:
            "moon"
        case .dracula:
            "sparkles"
        case .tokyoNight:
            "moon.stars"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .light:
            .light
        case .dark, .dracula, .tokyoNight:
            .dark
        }
    }

    var windowAppearance: NSAppearance? {
        switch self {
        case .light:
            NSAppearance(named: .aqua)
        case .dark, .dracula, .tokyoNight:
            NSAppearance(named: .darkAqua)
        }
    }

    var palette: AppThemePalette {
        switch self {
        case .light:
            .light
        case .dark:
            .dark
        case .dracula:
            .dracula
        case .tokyoNight:
            .tokyoNight
        }
    }
}

struct AppThemePalette {
    let dashboardBackground: Color
    let railBackground: Color
    let panelBackground: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let hairline: Color
    let blueAccent: Color
    let blueSoft: Color
    let violetAccent: Color
    let purpleAccent: Color
    let greenAccent: Color
    let greenText: Color
    let greenSoft: Color
    let orangeAccent: Color
    let coralAccent: Color
    let tealAccent: Color
    let steelAccent: Color
    let amberAccent: Color
    let grayAccent: Color
    let redAccent: Color
}

private struct ThemeRGB {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

private extension ThemeRGB {
    static func hex(_ value: UInt32) -> ThemeRGB {
        ThemeRGB(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}

private struct ThemeRGBPalette {
    let dashboardBackground: ThemeRGB
    let railBackground: ThemeRGB
    let panelBackground: ThemeRGB
    let primaryText: ThemeRGB
    let secondaryText: ThemeRGB
    let tertiaryText: ThemeRGB
    let hairline: ThemeRGB
    let blueAccent: ThemeRGB
    let blueSoft: ThemeRGB
    let violetAccent: ThemeRGB
    let purpleAccent: ThemeRGB
    let greenAccent: ThemeRGB
    let greenText: ThemeRGB
    let greenSoft: ThemeRGB
    let orangeAccent: ThemeRGB
    let coralAccent: ThemeRGB
    let tealAccent: ThemeRGB
    let steelAccent: ThemeRGB
    let amberAccent: ThemeRGB
    let grayAccent: ThemeRGB
    let redAccent: ThemeRGB

    var palette: AppThemePalette {
        AppThemePalette(
            dashboardBackground: dashboardBackground.color,
            railBackground: railBackground.color,
            panelBackground: panelBackground.color,
            primaryText: primaryText.color,
            secondaryText: secondaryText.color,
            tertiaryText: tertiaryText.color,
            hairline: hairline.color,
            blueAccent: blueAccent.color,
            blueSoft: blueSoft.color,
            violetAccent: violetAccent.color,
            purpleAccent: purpleAccent.color,
            greenAccent: greenAccent.color,
            greenText: greenText.color,
            greenSoft: greenSoft.color,
            orangeAccent: orangeAccent.color,
            coralAccent: coralAccent.color,
            tealAccent: tealAccent.color,
            steelAccent: steelAccent.color,
            amberAccent: amberAccent.color,
            grayAccent: grayAccent.color,
            redAccent: redAccent.color
        )
    }
}

private extension AppThemePalette {
    static let lightRGB = ThemeRGBPalette(
        dashboardBackground: ThemeRGB(red: 0.966, green: 0.973, blue: 0.984),
        railBackground: ThemeRGB(red: 0.949, green: 0.960, blue: 0.976),
        panelBackground: ThemeRGB(red: 0.996, green: 0.997, blue: 1.000),
        primaryText: ThemeRGB(red: 0.070, green: 0.090, blue: 0.140),
        secondaryText: ThemeRGB(red: 0.365, green: 0.398, blue: 0.486),
        tertiaryText: ThemeRGB(red: 0.525, green: 0.557, blue: 0.635),
        hairline: ThemeRGB(red: 0.832, green: 0.854, blue: 0.890),
        blueAccent: ThemeRGB(red: 0.137, green: 0.502, blue: 0.956),
        blueSoft: ThemeRGB(red: 0.892, green: 0.936, blue: 1.000),
        violetAccent: ThemeRGB(red: 0.575, green: 0.330, blue: 0.890),
        purpleAccent: ThemeRGB(red: 0.640, green: 0.395, blue: 0.910),
        greenAccent: ThemeRGB(red: 0.275, green: 0.705, blue: 0.382),
        greenText: ThemeRGB(red: 0.115, green: 0.485, blue: 0.230),
        greenSoft: ThemeRGB(red: 0.866, green: 0.965, blue: 0.890),
        orangeAccent: ThemeRGB(red: 0.955, green: 0.565, blue: 0.125),
        coralAccent: ThemeRGB(red: 0.940, green: 0.310, blue: 0.282),
        tealAccent: ThemeRGB(red: 0.140, green: 0.720, blue: 0.760),
        steelAccent: ThemeRGB(red: 0.435, green: 0.592, blue: 0.820),
        amberAccent: ThemeRGB(red: 0.920, green: 0.665, blue: 0.110),
        grayAccent: ThemeRGB(red: 0.585, green: 0.625, blue: 0.702),
        redAccent: ThemeRGB(red: 0.910, green: 0.130, blue: 0.170)
    )

    static let darkRGB = ThemeRGBPalette(
        dashboardBackground: .hex(0x111418),
        railBackground: .hex(0x171b21),
        panelBackground: .hex(0x20242b),
        primaryText: .hex(0xf2f5f8),
        secondaryText: .hex(0xaeb7c2),
        tertiaryText: .hex(0x828c99),
        hairline: .hex(0x343b46),
        blueAccent: .hex(0x5aa9ff),
        blueSoft: .hex(0x203a58),
        violetAccent: .hex(0xa78bfa),
        purpleAccent: .hex(0xc084fc),
        greenAccent: .hex(0x55d187),
        greenText: .hex(0x86efac),
        greenSoft: .hex(0x1d3b2a),
        orangeAccent: .hex(0xf4a261),
        coralAccent: .hex(0xff6b6b),
        tealAccent: .hex(0x5ed9d1),
        steelAccent: .hex(0x8fb4d8),
        amberAccent: .hex(0xe9c46a),
        grayAccent: .hex(0x94a3b8),
        redAccent: .hex(0xff5a6a)
    )

    static let draculaRGB = ThemeRGBPalette(
        dashboardBackground: .hex(0x282a36),
        railBackground: .hex(0x21222c),
        panelBackground: .hex(0x343746),
        primaryText: .hex(0xf8f8f2),
        secondaryText: .hex(0xd6d6ee),
        tertiaryText: .hex(0xa7a4ba),
        hairline: .hex(0x51566e),
        blueAccent: .hex(0x8be9fd),
        blueSoft: .hex(0x44475a),
        violetAccent: .hex(0xbd93f9),
        purpleAccent: .hex(0xff79c6),
        greenAccent: .hex(0x50fa7b),
        greenText: .hex(0x50fa7b),
        greenSoft: .hex(0x335244),
        orangeAccent: .hex(0xffb86c),
        coralAccent: .hex(0xff5555),
        tealAccent: .hex(0x8be9fd),
        steelAccent: .hex(0x6272a4),
        amberAccent: .hex(0xf1fa8c),
        grayAccent: .hex(0xa0a0b6),
        redAccent: .hex(0xff5555)
    )

    static let tokyoNightRGB = ThemeRGBPalette(
        dashboardBackground: .hex(0x1a1b26),
        railBackground: .hex(0x16161e),
        panelBackground: .hex(0x24283b),
        primaryText: .hex(0xc0caf5),
        secondaryText: .hex(0xa9b1d6),
        tertiaryText: .hex(0x7982a9),
        hairline: .hex(0x414868),
        blueAccent: .hex(0x7aa2f7),
        blueSoft: .hex(0x2f354e),
        violetAccent: .hex(0xbb9af7),
        purpleAccent: .hex(0x9d7cd8),
        greenAccent: .hex(0x9ece6a),
        greenText: .hex(0x9ece6a),
        greenSoft: .hex(0x2b3f34),
        orangeAccent: .hex(0xff9e64),
        coralAccent: .hex(0xf7768e),
        tealAccent: .hex(0x73daca),
        steelAccent: .hex(0x7dcfff),
        amberAccent: .hex(0xe0af68),
        grayAccent: .hex(0x565f89),
        redAccent: .hex(0xf7768e)
    )

    static let light = lightRGB.palette
    static let dark = darkRGB.palette
    static let dracula = draculaRGB.palette
    static let tokyoNight = tokyoNightRGB.palette

}

extension Color {
    static var dashboardBackground: Color { AppThemeChoice.saved.palette.dashboardBackground }
    static var railBackground: Color { AppThemeChoice.saved.palette.railBackground }
    static var panelBackground: Color { AppThemeChoice.saved.palette.panelBackground }
    static var primaryText: Color { AppThemeChoice.saved.palette.primaryText }
    static var secondaryText: Color { AppThemeChoice.saved.palette.secondaryText }
    static var tertiaryText: Color { AppThemeChoice.saved.palette.tertiaryText }
    static var hairline: Color { AppThemeChoice.saved.palette.hairline }
    static var blueAccent: Color { AppThemeChoice.saved.palette.blueAccent }
    static var blueSoft: Color { AppThemeChoice.saved.palette.blueSoft }
    static var violetAccent: Color { AppThemeChoice.saved.palette.violetAccent }
    static var purpleAccent: Color { AppThemeChoice.saved.palette.purpleAccent }
    static var greenAccent: Color { AppThemeChoice.saved.palette.greenAccent }
    static var greenText: Color { AppThemeChoice.saved.palette.greenText }
    static var greenSoft: Color { AppThemeChoice.saved.palette.greenSoft }
    static var orangeAccent: Color { AppThemeChoice.saved.palette.orangeAccent }
    static var coralAccent: Color { AppThemeChoice.saved.palette.coralAccent }
    static var tealAccent: Color { AppThemeChoice.saved.palette.tealAccent }
    static var steelAccent: Color { AppThemeChoice.saved.palette.steelAccent }
    static var amberAccent: Color { AppThemeChoice.saved.palette.amberAccent }
    static var grayAccent: Color { AppThemeChoice.saved.palette.grayAccent }
    static var redAccent: Color { AppThemeChoice.saved.palette.redAccent }
}
