import XCTest
@testable import Gleap

final class GleapColorSchemeTests: XCTestCase {
    private var theme: GleapThemeHelper { GleapThemeHelper.sharedInstance() }

    private let fullPalette: [AnyHashable: Any] = [
        "backgroundColor": "#ffffff", "color": "#485bff",
        "headerColor": "#aaaaaa", "headerColor2": "#bbbbbb", "headerColor3": "#cccccc",
        "darkBackgroundColor": "#101010", "darkColor": "#00FF00",
        "darkHeaderColor": "#123", "darkHeaderColor2": "#223344", "darkHeaderColor3": "#334455",
        "buttonColor": "#ff00ff",
    ]

    private let noPalette: [AnyHashable: Any] = [
        "backgroundColor": "#ffffff", "color": "#485bff",
        "headerColor": "#aaaaaa", "headerColor2": "#bbbbbb", "headerColor3": "#cccccc",
    ]

    override func setUp() {
        super.setUp()
        removeRuntimeColorScheme()
    }

    override func tearDown() {
        removeRuntimeColorScheme()
        super.tearDown()
    }

    /// Back to the state before any setColorScheme call: the dashboard setting applies.
    private func removeRuntimeColorScheme() {
        theme.colorScheme = nil
        theme.lightBackgroundColor = nil
        theme.darkBackgroundColor = nil
        theme.detectedColorScheme = "light"
    }

    private func dark(_ config: [AnyHashable: Any], darkBackgroundColor: String? = nil) -> [AnyHashable: Any] {
        return GleapThemeHelper.applyColorScheme("dark", toConfig: config, lightBackgroundColor: nil, darkBackgroundColor: darkBackgroundColor)
    }

    private func background(_ config: [AnyHashable: Any]) -> String? {
        return theme.apply(toConfig: config)["backgroundColor"] as? String
    }

    private func merged(_ config: [AnyHashable: Any], _ other: [AnyHashable: Any]) -> [AnyHashable: Any] {
        return config.merging(other) { _, new in new }
    }

    func testNormalizeHexColor() throws {
        XCTAssertEqual(GleapThemeHelper.normalizeHexColor("#ABC"), "#aabbcc")
        XCTAssertEqual(GleapThemeHelper.normalizeHexColor("#121212"), "#121212")
        XCTAssertEqual(GleapThemeHelper.normalizeHexColor(" #A0B1C2 "), "#a0b1c2")
        XCTAssertNil(GleapThemeHelper.normalizeHexColor("#12121280"))
        XCTAssertNil(GleapThemeHelper.normalizeHexColor("#12"))
        XCTAssertNil(GleapThemeHelper.normalizeHexColor("#ggg"))
        XCTAssertNil(GleapThemeHelper.normalizeHexColor("121212"))
        XCTAssertNil(GleapThemeHelper.normalizeHexColor("red"))
        XCTAssertNil(GleapThemeHelper.normalizeHexColor(42))
        XCTAssertNil(GleapThemeHelper.normalizeHexColor(nil))
    }

    func testHasDarkPalette() throws {
        XCTAssertFalse(GleapThemeHelper.hasDarkPalette(inConfig: noPalette, darkBackgroundColor: nil))
        XCTAssertFalse(GleapThemeHelper.hasDarkPalette(inConfig: nil, darkBackgroundColor: nil))
        XCTAssertTrue(GleapThemeHelper.hasDarkPalette(inConfig: fullPalette, darkBackgroundColor: nil))
        // Any one valid dark color is enough.
        for key in ["darkHeaderColor", "darkHeaderColor2", "darkHeaderColor3", "darkColor", "darkBackgroundColor"] {
            XCTAssertTrue(GleapThemeHelper.hasDarkPalette(inConfig: merged(noPalette, [key: "#222"]), darkBackgroundColor: nil), key)
        }
        // Invalid dark colors don't count.
        let invalid = merged(noPalette, ["darkBackgroundColor": "invalid", "darkColor": "red", "darkHeaderColor": "#12", "darkHeaderColor2": 5])
        XCTAssertFalse(GleapThemeHelper.hasDarkPalette(inConfig: invalid, darkBackgroundColor: nil))
        // A valid runtime dark background counts, an invalid one doesn't.
        XCTAssertTrue(GleapThemeHelper.hasDarkPalette(inConfig: noPalette, darkBackgroundColor: "#121212"))
        XCTAssertFalse(GleapThemeHelper.hasDarkPalette(inConfig: noPalette, darkBackgroundColor: "blue"))
    }

    func testDefaultKeepsTheConfig() throws {
        let themed = GleapThemeHelper.applyColorScheme(nil, toConfig: fullPalette, lightBackgroundColor: "#fafafa", darkBackgroundColor: "#121212")
        XCTAssertEqual(themed as NSDictionary, fullPalette as NSDictionary)
    }

    func testLightMode() throws {
        // Unchanged: the base colors are the light palette, the dark palette and the runtime dark background are ignored.
        let themed = GleapThemeHelper.applyColorScheme("light", toConfig: fullPalette, lightBackgroundColor: nil, darkBackgroundColor: "#121212")
        XCTAssertEqual(themed as NSDictionary, fullPalette as NSDictionary)

        // The runtime light background replaces only the background.
        let overridden = GleapThemeHelper.applyColorScheme("light", toConfig: fullPalette, lightBackgroundColor: "#FAFAFA", darkBackgroundColor: nil)
        XCTAssertEqual(overridden as NSDictionary, merged(fullPalette, ["backgroundColor": "#fafafa"]) as NSDictionary)

        // An invalid runtime light background is ignored.
        let invalid = GleapThemeHelper.applyColorScheme("light", toConfig: fullPalette, lightBackgroundColor: "white", darkBackgroundColor: nil)
        XCTAssertEqual(invalid as NSDictionary, fullPalette as NSDictionary)
    }

    func testDarkModeWithAFullPalette() throws {
        let themed = dark(fullPalette)
        let expected = merged(fullPalette, [
            "backgroundColor": "#101010", "color": "#00ff00",
            "headerColor": "#112233", "headerColor2": "#223344", "headerColor3": "#334455",
        ])
        // Exactly the five palette colors change (normalized); everything else is kept.
        XCTAssertEqual(themed as NSDictionary, expected as NSDictionary)

        // The raw config is never mutated.
        XCTAssertEqual(fullPalette["backgroundColor"] as? String, "#ffffff")
        XCTAssertEqual(fullPalette["headerColor"] as? String, "#aaaaaa")
    }

    func testDarkModeWithAPartialPalette() throws {
        let config = merged(noPalette, ["darkBackgroundColor": "#101010", "darkHeaderColor": "#222222"])
        let themed = dark(config)
        XCTAssertEqual(themed["backgroundColor"] as? String, "#101010")
        XCTAssertEqual(themed["headerColor"] as? String, "#222222")
        // Missing dark colors keep the base colors as they are.
        XCTAssertEqual(themed["color"] as? String, "#485bff")
        XCTAssertEqual(themed["headerColor2"] as? String, "#bbbbbb")
        XCTAssertEqual(themed["headerColor3"] as? String, "#cccccc")

        // A missing base color is only added when its dark color is set.
        let sparse = dark(["darkColor": "#ff0000"])
        XCTAssertEqual(sparse as NSDictionary, ["darkColor": "#ff0000", "color": "#ff0000"] as NSDictionary)
    }

    func testInvalidDarkColorsAreIgnored() throws {
        let config = merged(noPalette, [
            "darkBackgroundColor": "invalid", "darkColor": "red", "darkHeaderColor": "#12", "darkHeaderColor2": 5,
            "darkHeaderColor3": "#334455",
        ])
        let themed = dark(config)
        XCTAssertEqual(themed["headerColor3"] as? String, "#334455")
        XCTAssertEqual(themed["backgroundColor"] as? String, "#ffffff")
        XCTAssertEqual(themed["color"] as? String, "#485bff")
        XCTAssertEqual(themed["headerColor"] as? String, "#aaaaaa")
        XCTAssertEqual(themed["headerColor2"] as? String, "#bbbbbb")

        // Only invalid dark colors: no dark palette, so nothing changes.
        let onlyInvalid = merged(noPalette, ["darkBackgroundColor": "invalid", "darkColor": "red"])
        XCTAssertEqual(dark(onlyInvalid) as NSDictionary, onlyInvalid as NSDictionary)
    }

    func testDarkModeWithoutAPaletteKeepsTheConfig() throws {
        // No dark colors = no dark mode: the config is returned as it is, no defaults, no adjustments.
        XCTAssertEqual(dark(noPalette) as NSDictionary, noPalette as NSDictionary)
        XCTAssertEqual(dark([:]) as NSDictionary, [:] as NSDictionary)
        XCTAssertEqual(dark(["backgroundColor": "#ffffff", "color": "#111111"]) as NSDictionary, ["backgroundColor": "#ffffff", "color": "#111111"] as NSDictionary)

        // Not treated as dark: dashboard "dark", "auto" in a dark app and a runtime "dark".
        let dashboardDark = merged(noPalette, ["colorScheme": "dark"])
        XCTAssertNil(theme.activeColorScheme(forConfig: dashboardDark))
        XCTAssertEqual(theme.apply(toConfig: dashboardDark) as NSDictionary, dashboardDark as NSDictionary)

        let auto = merged(noPalette, ["colorScheme": "auto"])
        theme.detectedColorScheme = "dark"
        XCTAssertNil(theme.activeColorScheme(forConfig: auto))
        XCTAssertEqual(theme.apply(toConfig: auto) as NSDictionary, auto as NSDictionary)

        let enabled = merged(noPalette, ["colorScheme": "light"])
        Gleap.setColorScheme("dark")
        XCTAssertNil(theme.activeColorScheme(forConfig: enabled))
        XCTAssertEqual(theme.apply(toConfig: enabled) as NSDictionary, enabled as NSDictionary)

        // Light still resolves to light without a dark palette.
        Gleap.setColorScheme("light")
        XCTAssertEqual(theme.activeColorScheme(forConfig: enabled), "light")
    }

    func testRuntimeDarkBackgroundAloneEnablesTheBackgroundSwap() throws {
        // Only the background changes; the other colors keep the base values.
        let themed = dark(noPalette, darkBackgroundColor: "#121212")
        XCTAssertEqual(themed as NSDictionary, merged(noPalette, ["backgroundColor": "#121212"]) as NSDictionary)

        let enabled = merged(noPalette, ["colorScheme": "auto"])
        Gleap.setColorScheme("dark", lightBackgroundColor: nil, darkBackgroundColor: "#121212")
        XCTAssertEqual(theme.activeColorScheme(forConfig: enabled), "dark")
        XCTAssertEqual(theme.apply(toConfig: enabled) as NSDictionary, merged(enabled, ["backgroundColor": "#121212"]) as NSDictionary)

        // An invalid runtime dark background doesn't enable dark mode.
        Gleap.setColorScheme("dark", lightBackgroundColor: nil, darkBackgroundColor: "blue")
        XCTAssertNil(theme.activeColorScheme(forConfig: enabled))
        XCTAssertEqual(theme.apply(toConfig: enabled) as NSDictionary, enabled as NSDictionary)
    }

    private let lightAssets: [AnyHashable: Any] = [
        "logo": "https://cdn/logo.png", "bgImage": "https://cdn/bg.png",
        "aurora": ["colors": ["#ff0000", "#00ff00"], "source": "custom", "seed": 7, "extra": true],
    ]

    private let darkAssets: [AnyHashable: Any] = [
        "darkLogo": "", "darkBgImage": "https://cdn/bg-dark.png",
        "darkAurora": ["colors": ["#111111", "#222222", "#333333"], "source": "palette", "seed": 42],
    ]

    func testDarkModeSwapsLogoImageAndGlow() throws {
        let config = merged(merged(fullPalette, lightAssets), darkAssets)
        let themed = dark(config)
        // The dark values are taken as they are: "" = no logo in dark mode.
        XCTAssertEqual(themed["logo"] as? String, "")
        XCTAssertEqual(themed["bgImage"] as? String, "https://cdn/bg-dark.png")
        // The whole aurora dictionary is replaced, not merged.
        XCTAssertEqual(themed["aurora"] as? NSDictionary, darkAssets["darkAurora"] as? NSDictionary)
        XCTAssertNil((themed["aurora"] as? [String: Any])?["extra"])
        // The dark fields themselves and the colors are handled as before.
        XCTAssertEqual(themed["darkLogo"] as? String, "")
        XCTAssertEqual(themed["backgroundColor"] as? String, "#101010")

        // Only present dark keys swap; no validation of their values.
        let partial = dark(merged(merged(fullPalette, lightAssets), ["darkBgImage": ""]))
        XCTAssertEqual(partial["bgImage"] as? String, "")
        XCTAssertEqual(partial["logo"] as? String, "https://cdn/logo.png")
        XCTAssertEqual(partial["aurora"] as? NSDictionary, lightAssets["aurora"] as? NSDictionary)

        // A missing base key is added from its dark key.
        XCTAssertEqual(dark(merged(fullPalette, ["darkLogo": "https://cdn/logo-dark.png"]))["logo"] as? String, "https://cdn/logo-dark.png")

        // Also through the runtime / dashboard scheme.
        theme.detectedColorScheme = "dark"
        let auto = theme.apply(toConfig: merged(config, ["colorScheme": "auto"]))
        XCTAssertEqual(auto["logo"] as? String, "")
        XCTAssertEqual(auto["bgImage"] as? String, "https://cdn/bg-dark.png")
    }

    func testAbsentDarkAssetsKeepTheBase() throws {
        // Config saved before the dark fields existed: the base values stay.
        let config = merged(fullPalette, lightAssets)
        let themed = dark(config)
        XCTAssertEqual(themed["logo"] as? String, "https://cdn/logo.png")
        XCTAssertEqual(themed["bgImage"] as? String, "https://cdn/bg.png")
        XCTAssertEqual(themed["aurora"] as? NSDictionary, lightAssets["aurora"] as? NSDictionary)
        XCTAssertNil(themed["darkLogo"])

        // NSNull counts as absent.
        let nulls = dark(merged(config, ["darkLogo": NSNull(), "darkBgImage": NSNull(), "darkAurora": NSNull()]))
        XCTAssertEqual(nulls["logo"] as? String, "https://cdn/logo.png")
        XCTAssertEqual(nulls["bgImage"] as? String, "https://cdn/bg.png")
        XCTAssertEqual(nulls["aurora"] as? NSDictionary, lightAssets["aurora"] as? NSDictionary)
    }

    func testNoAssetSwapWithoutADarkPalette() throws {
        // No dark colors = no dark mode, also for the logo, image and glow.
        let config = merged(merged(merged(noPalette, lightAssets), darkAssets), ["colorScheme": "auto"])
        XCTAssertEqual(dark(config) as NSDictionary, config as NSDictionary)

        Gleap.setColorScheme("dark")
        XCTAssertNil(theme.activeColorScheme(forConfig: config))
        XCTAssertEqual(theme.apply(toConfig: config) as NSDictionary, config as NSDictionary)

        // Only the dark assets don't make a dark palette.
        XCTAssertFalse(GleapThemeHelper.hasDarkPalette(inConfig: config, darkBackgroundColor: nil))

        // A runtime dark background is a dark palette: dark mode swaps the assets too.
        let runtime = GleapThemeHelper.applyColorScheme("dark", toConfig: config, lightBackgroundColor: nil, darkBackgroundColor: "#121212")
        XCTAssertEqual(runtime["logo"] as? String, "")
        XCTAssertEqual(runtime["bgImage"] as? String, "https://cdn/bg-dark.png")
    }

    func testLightModeKeepsLogoImageAndGlow() throws {
        let config = merged(merged(fullPalette, lightAssets), darkAssets)
        let light = GleapThemeHelper.applyColorScheme("light", toConfig: config, lightBackgroundColor: nil, darkBackgroundColor: "#121212")
        XCTAssertEqual(light as NSDictionary, config as NSDictionary)

        let overridden = GleapThemeHelper.applyColorScheme("light", toConfig: config, lightBackgroundColor: "#fafafa", darkBackgroundColor: nil)
        XCTAssertEqual(overridden as NSDictionary, merged(config, ["backgroundColor": "#fafafa"]) as NSDictionary)

        // No scheme keeps the config.
        XCTAssertEqual(GleapThemeHelper.applyColorScheme(nil, toConfig: config, lightBackgroundColor: nil, darkBackgroundColor: nil) as NSDictionary, config as NSDictionary)

        // "auto" in a light app.
        let auto = merged(config, ["colorScheme": "auto"])
        XCTAssertEqual(theme.apply(toConfig: auto) as NSDictionary, auto as NSDictionary)
    }

    func testLiveRefreshPicksUpAnAssetOnlyChange() throws {
        // Same colors in both schemes, only the logo differs: the live refresh must still update the config.
        let configHelper = GleapConfigHelper.sharedInstance()
        let previousRawConfig = configHelper.rawConfig
        // Via KVC to keep a nil config nil (the property is nonnull in Swift).
        let previousConfig = configHelper.value(forKey: "config")
        defer {
            configHelper.rawConfig = previousRawConfig
            configHelper.setValue(previousConfig, forKey: "config")
        }

        let raw = merged(noPalette, [
            "colorScheme": "auto", "darkBackgroundColor": "#ffffff",
            "logo": "https://cdn/logo.png", "darkLogo": "https://cdn/logo-dark.png",
        ])
        configHelper.rawConfig = raw
        configHelper.config = theme.apply(toConfig: raw)
        XCTAssertEqual(configHelper.config["logo"] as? String, "https://cdn/logo.png")

        theme.detectedColorScheme = "dark"
        configHelper.refreshColorScheme()
        XCTAssertEqual(configHelper.config["backgroundColor"] as? String, "#ffffff")
        XCTAssertEqual(configHelper.config["logo"] as? String, "https://cdn/logo-dark.png")

        theme.detectedColorScheme = "light"
        configHelper.refreshColorScheme()
        XCTAssertEqual(configHelper.config["logo"] as? String, "https://cdn/logo.png")
    }

    func testDashboardColorScheme() throws {
        XCTAssertEqual(background(merged(fullPalette, [:])), "#ffffff")
        XCTAssertEqual(background(merged(fullPalette, ["colorScheme": "default"])), "#ffffff")
        XCTAssertEqual(background(merged(fullPalette, ["colorScheme": "unknown"])), "#ffffff")
        XCTAssertEqual(background(merged(fullPalette, ["colorScheme": "light"])), "#ffffff")
        XCTAssertEqual(background(merged(fullPalette, ["colorScheme": "dark"])), "#101010")
        XCTAssertEqual(background(merged(fullPalette, ["colorScheme": " Dark "])), "#101010")
        // The dashboard lightBackgroundColor is not used.
        XCTAssertEqual(background(merged(fullPalette, ["colorScheme": "light", "lightBackgroundColor": "#f4f4f5"])), "#ffffff")
    }

    func testAutoFollowsTheDetectedInterfaceStyle() throws {
        let config = merged(fullPalette, ["colorScheme": "auto"])
        XCTAssertEqual(theme.activeColorScheme(forConfig: config), "light")
        XCTAssertEqual(theme.apply(toConfig: config) as NSDictionary, config as NSDictionary)

        theme.detectedColorScheme = "dark"
        XCTAssertEqual(theme.activeColorScheme(forConfig: config), "dark")
        let themed = theme.apply(toConfig: config)
        XCTAssertEqual(themed["backgroundColor"] as? String, "#101010")
        XCTAssertEqual(themed["color"] as? String, "#00ff00")
        XCTAssertEqual(themed["headerColor"] as? String, "#112233")
    }

    func testRuntimeColorSchemeOverridesTheDashboard() throws {
        let config = merged(fullPalette, ["colorScheme": "light"])

        // The runtime scheme wins over the dashboard scheme.
        Gleap.setColorScheme("dark")
        XCTAssertEqual(background(config), "#101010")
        XCTAssertEqual(theme.apply(toConfig: config)["color"] as? String, "#00ff00")

        // The runtime dark background wins over the dashboard's; the other dark colors still apply.
        Gleap.setColorScheme("dark", lightBackgroundColor: nil, darkBackgroundColor: "#121212")
        XCTAssertEqual(background(config), "#121212")
        XCTAssertEqual(theme.apply(toConfig: config)["headerColor"] as? String, "#112233")

        // An invalid runtime color falls back to the dashboard's.
        Gleap.setColorScheme("dark", lightBackgroundColor: nil, darkBackgroundColor: "blue")
        XCTAssertEqual(background(config), "#101010")

        // The runtime light background applies in light mode.
        Gleap.setColorScheme("light", lightBackgroundColor: "#fafafa", darkBackgroundColor: "#121212")
        XCTAssertEqual(background(config), "#fafafa")
        XCTAssertEqual(theme.apply(toConfig: config)["color"] as? String, "#485bff")

        // A runtime light scheme overrides a dashboard dark scheme.
        XCTAssertEqual(background(merged(fullPalette, ["colorScheme": "dark"])), "#fafafa")
    }

    func testAnyOtherRuntimeValueMeansAuto() throws {
        // Before any call the dashboard setting applies.
        let config = merged(fullPalette, ["colorScheme": "dark"])
        XCTAssertEqual(theme.activeColorScheme(forConfig: config), "dark")

        for value in ["default", "unknown", ""] {
            Gleap.setColorScheme(value)
            XCTAssertEqual(theme.colorScheme, "auto", value)
            theme.detectedColorScheme = "light"
            XCTAssertEqual(theme.activeColorScheme(forConfig: config), "light", "follows the app, not the dashboard: \(value)")
            theme.detectedColorScheme = "dark"
            XCTAssertEqual(theme.activeColorScheme(forConfig: config), "dark", value)
        }
    }

    func testRuntimeColorSchemeIsIgnoredWhileTheDashboardDisablesIt() throws {
        // Dark / light mode disabled in the dashboard (missing, "default" or unknown colorScheme):
        // the widget is never themed, whatever the app sets.
        let configs = [
            fullPalette,
            merged(fullPalette, ["colorScheme": "default"]),
            merged(fullPalette, ["colorScheme": "unknown"]),
        ].map { merged(merged($0, lightAssets), darkAssets) }

        Gleap.setColorScheme("dark", lightBackgroundColor: nil, darkBackgroundColor: "#121212")
        for config in configs {
            XCTAssertNil(theme.activeColorScheme(forConfig: config))
            XCTAssertEqual(theme.apply(toConfig: config) as NSDictionary, config as NSDictionary)
        }

        // Also no runtime light background and no "auto" in a dark app.
        Gleap.setColorScheme("light", lightBackgroundColor: "#fafafa", darkBackgroundColor: nil)
        for config in configs {
            XCTAssertNil(theme.activeColorScheme(forConfig: config))
            XCTAssertEqual(theme.apply(toConfig: config) as NSDictionary, config as NSDictionary)
        }

        theme.detectedColorScheme = "dark"
        Gleap.setColorScheme("auto", lightBackgroundColor: "#fafafa", darkBackgroundColor: "#121212")
        for config in configs {
            XCTAssertNil(theme.activeColorScheme(forConfig: config))
            XCTAssertEqual(theme.apply(toConfig: config) as NSDictionary, config as NSDictionary)
        }
    }

    func testRuntimeColorSchemeAppliesWhileTheDashboardEnablesIt() throws {
        // Dashboard "auto" in a light app, runtime "dark" wins.
        let config = merged(fullPalette, ["colorScheme": "auto"])
        Gleap.setColorScheme("dark")
        XCTAssertEqual(theme.activeColorScheme(forConfig: config), "dark")
        let themed = theme.apply(toConfig: config)
        XCTAssertEqual(themed["backgroundColor"] as? String, "#101010")
        XCTAssertEqual(themed["color"] as? String, "#00ff00")
        XCTAssertEqual(themed["headerColor"] as? String, "#112233")
    }
}
