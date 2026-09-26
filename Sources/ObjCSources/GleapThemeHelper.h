//
//  GleapThemeHelper.h
//
//
//  Created by Lukas Boehler on 26.09.26.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const GleapColorSchemeDefault;
extern NSString * const GleapColorSchemeAuto;
extern NSString * const GleapColorSchemeLight;
extern NSString * const GleapColorSchemeDark;

/**
 * Matches the widget background to a dark / light color scheme. The scheme
 * comes from Gleap.setColorScheme (runtime) or the dashboard's colorScheme
 * flow config field; "auto" follows the app's interface style.
 */
@interface GleapThemeHelper : NSObject

+ (instancetype)sharedInstance;

/**
 * Detects the app's interface style and starts observing it while the
 * effective scheme is "auto". Safe to call repeatedly.
 */
- (void)start;

/**
 * Sets the runtime color scheme. "default" (or nil / unknown) removes the
 * override, so the dashboard setting applies again. Invalid colors are ignored.
 */
- (void)setColorScheme:(nullable NSString *)colorScheme lightBackgroundColor:(nullable NSString *)lightBackgroundColor darkBackgroundColor:(nullable NSString *)darkBackgroundColor;

/**
 * Returns a copy of the flow config with the background matched to the active
 * scheme, or the config itself when nothing has to change.
 */
- (NSDictionary *)applyToConfig:(NSDictionary *)config;

/**
 * The scheme the widget renders in for the given flow config ("light" / "dark"),
 * or nil to keep the dashboard colors.
 */
- (nullable NSString *)activeColorSchemeForConfig:(nullable NSDictionary *)config;

/**
 * The swap rule: keeps a background that already fits the active scheme,
 * otherwise uses the light / dark background.
 */
+ (NSDictionary *)applyColorScheme:(nullable NSString *)activeColorScheme toConfig:(NSDictionary *)config lightBackgroundColor:(NSString *)lightBackgroundColor darkBackgroundColor:(NSString *)darkBackgroundColor;

/**
 * Whether the widget renders the color as dark (YIQ < 160 — the threshold the
 * widget uses to switch to light text).
 */
+ (BOOL)isDarkBackgroundColor:(nullable NSString *)color;

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
