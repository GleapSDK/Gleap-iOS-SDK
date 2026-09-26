import XCTest
@testable import Gleap

final class GleapColorSchemeTests: XCTestCase {
    private var theme: GleapThemeHelper { GleapThemeHelper.sharedInstance() }

    override func setUp() {
        super.setUp()
        Gleap.setColorScheme("default")
        theme.detectedColorScheme = "light"
    }

    override func tearDown() {
        Gleap.setColorScheme("default")
        theme.detectedColorScheme = "light"
        super.tearDown()
    }

    private func background(_ config: [AnyHashable: Any]) -> String? {
        return theme.apply(toConfig: config)["backgroundColor"] as? String
    }

    func testDarkDetection() throws {
        XCTAssertFalse(GleapThemeHelper.isDarkBackgroundColor("#ffffff"))
        XCTAssertFalse(GleapThemeHelper.isDarkBackgroundColor("#fff"))
        XCTAssertTrue(GleapThemeHelper.isDarkBackgroundColor("#18181b"))
        XCTAssertTrue(GleapThemeHelper.isDarkBackgroundColor("#000"))
        // YIQ 159 is dark, 160 is not.
        XCTAssertTrue(GleapThemeHelper.isDarkBackgroundColor("#9f9f9f"))
        XCTAssertFalse(GleapThemeHelper.isDarkBackgroundColor("#a0a0a0"))
        XCTAssertFalse(GleapThemeHelper.isDarkBackgroundColor("not a color"))
    }

    func testNormalizeHexColor() throws {
        XCTAssertEqual(GleapThemeHelper.normalizeHexColor("#ABC"), "#aabbcc")
        XCTAssertEqual(GleapThemeHelper.normalizeHexColor("#121212"), "#121212")
        XCTAssertNil(GleapThemeHelper.normalizeHexColor("#12121280"))
        XCTAssertNil(GleapThemeHelper.normalizeHexColor("red"))
        XCTAssertNil(GleapThemeHelper.normalizeHexColor(nil))
    }

    func testSwapRule() throws {
        let light: [AnyHashable: Any] = ["backgroundColor": "#ffffff", "color": "#485bff"]
        let dark: [AnyHashable: Any] = ["backgroundColor": "#222222", "color": "#485bff"]

        // Default: unchanged.
        XCTAssertEqual(GleapThemeHelper.applyColorScheme(nil, toConfig: light, lightBackgroundColor: "#ffffff", darkBackgroundColor: "#18181b")["backgroundColor"] as? String, "#ffffff")

        // Matching background: kept.
        XCTAssertEqual(GleapThemeHelper.applyColorScheme("dark", toConfig: dark, lightBackgroundColor: "#ffffff", darkBackgroundColor: "#18181b")["backgroundColor"] as? String, "#222222")
        XCTAssertEqual(GleapThemeHelper.applyColorScheme("light", toConfig: light, lightBackgroundColor: "#fafafa", darkBackgroundColor: "#18181b")["backgroundColor"] as? String, "#ffffff")

        // Mismatching background: swapped, everything else kept.
        let swapped = GleapThemeHelper.applyColorScheme("dark", toConfig: light, lightBackgroundColor: "#ffffff", darkBackgroundColor: "#18181b")
        XCTAssertEqual(swapped["backgroundColor"] as? String, "#18181b")
        XCTAssertEqual(swapped["color"] as? String, "#485bff")
        XCTAssertEqual(GleapThemeHelper.applyColorScheme("light", toConfig: dark, lightBackgroundColor: "#fafafa", darkBackgroundColor: "#18181b")["backgroundColor"] as? String, "#fafafa")

        // Missing background counts as white.
        XCTAssertEqual(GleapThemeHelper.applyColorScheme("dark", toConfig: [:], lightBackgroundColor: "#ffffff", darkBackgroundColor: "#18181b")["backgroundColor"] as? String, "#18181b")

        // The raw config is never mutated.
        XCTAssertEqual(light["backgroundColor"] as? String, "#ffffff")
    }

    func testDashboardColorScheme() throws {
        XCTAssertEqual(background(["backgroundColor": "#ffffff"]), "#ffffff")
        XCTAssertEqual(background(["backgroundColor": "#ffffff", "colorScheme": "default"]), "#ffffff")
        XCTAssertEqual(background(["backgroundColor": "#ffffff", "colorScheme": "unknown"]), "#ffffff")
        XCTAssertEqual(background(["backgroundColor": "#ffffff", "colorScheme": "dark"]), "#18181b")
        XCTAssertEqual(background(["backgroundColor": "#ffffff", "colorScheme": "dark", "darkBackgroundColor": "#123"]), "#112233")
        XCTAssertEqual(background(["backgroundColor": "#ffffff", "colorScheme": "dark", "darkBackgroundColor": "invalid"]), "#18181b")
        XCTAssertEqual(background(["backgroundColor": "#000000", "colorScheme": "light", "lightBackgroundColor": "#f4f4f5"]), "#f4f4f5")
    }

    func testAutoFollowsTheDetectedInterfaceStyle() throws {
        let config: [AnyHashable: Any] = ["backgroundColor": "#ffffff", "colorScheme": "auto"]
        XCTAssertEqual(background(config), "#ffffff")
        theme.detectedColorScheme = "dark"
        XCTAssertEqual(background(config), "#18181b")
    }

    func testRuntimeColorSchemeOverridesTheDashboard() throws {
        let config: [AnyHashable: Any] = ["backgroundColor": "#ffffff", "colorScheme": "light", "darkBackgroundColor": "#101010"]

        Gleap.setColorScheme("dark")
        XCTAssertEqual(background(config), "#101010")

        Gleap.setColorScheme("dark", lightBackgroundColor: nil, darkBackgroundColor: "#121212")
        XCTAssertEqual(background(config), "#121212")

        // Invalid runtime colors fall back to the dashboard color.
        Gleap.setColorScheme("dark", lightBackgroundColor: nil, darkBackgroundColor: "blue")
        XCTAssertEqual(background(config), "#101010")

        // "default" removes the override.
        Gleap.setColorScheme("default")
        XCTAssertEqual(background(config), "#ffffff")
    }
}
