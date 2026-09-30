//
//  GleapThemeHelper.h
//
//
//  Created by Lukas Boehler on 26.09.26.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const GleapColorSchemeDefault;
extern NSString * const GleapColorSchemeAuto;
extern NSString * const GleapColorSchemeLight;
extern NSString * const GleapColorSchemeDark;

/**
 * Applies the dark / light color scheme to the widget config. Only when the
 * dashboard enables it (colorScheme flow config field "auto", "light" or
 * "dark"); otherwise (missing, unknown, "default") the widget is never themed,
 * also not by Gleap.setColorScheme. When enabled, the runtime scheme from
 * Gleap.setColorScheme wins over the dashboard's; "auto" follows the app's
 * interface style. The base colors (headerColor,
 * headerColor2, headerColor3, color, backgroundColor) are the light palette; in
 * dark mode the dashboard's dark palette (darkHeaderColor, darkHeaderColor2,
 * darkHeaderColor3, darkColor, darkBackgroundColor) replaces them, and the
 * dark logo, header background image and composer glow (darkLogo, darkBgImage,
 * darkAurora) replace logo, bgImage and aurora. All choices come from the
 * dashboard; the SDK does no color math. Without dark colors there is no dark
 * mode.
 */
@interface GleapThemeHelper : NSObject

+ (instancetype)sharedInstance;

/**
 * Detects the app's interface style and starts observing it while the
 * effective scheme is "auto". Safe to call repeatedly.
 */
- (void)start;

/**
 * Sets the runtime color scheme: "auto", "light" or "dark"; any other value
 * (including "default" and nil) is treated as "auto". Before the first call
 * there is no runtime override and the dashboard setting applies. Only takes
 * effect while the dashboard enables dark / light mode. Invalid colors are
 * ignored.
 */
- (void)setColorScheme:(nullable NSString *)colorScheme lightBackgroundColor:(nullable NSString *)lightBackgroundColor darkBackgroundColor:(nullable NSString *)darkBackgroundColor;

/**
 * Returns a copy of the flow config with the palette of the active scheme, or
 * the config itself when nothing has to change.
 */
- (NSDictionary *)applyToConfig:(NSDictionary *)config;

/**
 * The scheme the widget renders in for the given flow config ("light" / "dark"),
 * or nil to keep the dashboard colors. nil when the dashboard's colorScheme is
 * not enabled (missing, unknown, "default"), whatever the runtime scheme. Never
 * "dark" without a dark palette.
 */
- (nullable NSString *)activeColorSchemeForConfig:(nullable NSDictionary *)config;

/**
 * Whether the config has a dark palette: at least one valid dark color
 * (darkHeaderColor, darkHeaderColor2, darkHeaderColor3, darkColor,
 * darkBackgroundColor) or a valid runtime darkBackgroundColor.
 */
+ (BOOL)hasDarkPaletteInConfig:(nullable NSDictionary *)config darkBackgroundColor:(nullable NSString *)darkBackgroundColor;

/**
 * Resolves the palette for the active scheme ("light" / "dark", nil keeps the
 * config). lightBackgroundColor / darkBackgroundColor are the runtime overrides
 * from Gleap.setColorScheme (nil when not set).
 *
 * light: unchanged, except backgroundColor = lightBackgroundColor if set.
 * dark:  unchanged without a dark palette. Otherwise each base color is replaced
 *        by its valid dark counterpart (normalized) and kept when there is none;
 *        the runtime darkBackgroundColor wins over the dashboard's. logo, bgImage
 *        and aurora take darkLogo, darkBgImage and darkAurora as they are when
 *        present (not nil / NSNull; "" = none in dark mode), else stay.
 */
+ (NSDictionary *)applyColorScheme:(nullable NSString *)activeColorScheme toConfig:(NSDictionary *)config lightBackgroundColor:(nullable NSString *)lightBackgroundColor darkBackgroundColor:(nullable NSString *)darkBackgroundColor;

/**
 * Returns #rrggbb for #rgb / #rrggbb input, nil for anything else.
 */
+ (nullable NSString *)normalizeHexColor:(nullable id)color;

@property (nonatomic, retain, nullable) NSString *colorScheme;
@property (nonatomic, retain, nullable) NSString *lightBackgroundColor;
@property (nonatomic, retain, nullable) NSString *darkBackgroundColor;

/**
 * The app's last detected interface style ("light" / "dark").
 */
@property (nonatomic, retain) NSString *detectedColorScheme;

@end

NS_ASSUME_NONNULL_END
