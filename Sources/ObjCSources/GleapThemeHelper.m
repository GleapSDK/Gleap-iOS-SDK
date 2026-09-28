//
//  GleapThemeHelper.m
//
//
//  Created by Lukas Boehler on 26.09.26.
//

#import "GleapThemeHelper.h"
#import "GleapConfigHelper.h"
#import "GleapWindowChecker.h"

NSString * const GleapColorSchemeDefault = @"default";
NSString * const GleapColorSchemeAuto = @"auto";
NSString * const GleapColorSchemeLight = @"light";
NSString * const GleapColorSchemeDark = @"dark";

@class GleapTraitObserverView;

@interface GleapThemeHelper ()

@property (nonatomic, retain, nullable) GleapTraitObserverView *traitObserverView;
@property (nonatomic, assign) BOOL started;

- (void)checkColorScheme;

@end

// Invisible, non-interactive view in the app's key window that reports
// interface style changes (system appearance or the app's own
// overrideUserInterfaceStyle), as the window's subviews inherit its traits.
@interface GleapTraitObserverView : UIView
@end

@implementation GleapTraitObserverView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame: frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        self.accessibilityElementsHidden = YES;
        if (@available(iOS 17.0, *)) {
            [self registerForTraitChanges: @[UITraitUserInterfaceStyle.class] withTarget: self action: @selector(interfaceStyleDidChange)];
        }
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange: previousTraitCollection];
    if (@available(iOS 17.0, *)) {
        // Reported via registerForTraitChanges.
        return;
    }
    if (previousTraitCollection == nil || previousTraitCollection.userInterfaceStyle != self.traitCollection.userInterfaceStyle) {
        [self interfaceStyleDidChange];
    }
}

- (void)interfaceStyleDidChange {
    [[GleapThemeHelper sharedInstance] checkColorScheme];
}

@end

@implementation GleapThemeHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapThemeHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapThemeHelper alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        self.detectedColorScheme = GleapColorSchemeLight;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}

- (void)start {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.started) {
            self.started = YES;

            // Catch changes that happen while no observer view is attached
            // (e.g. while the app is in the background) and key window swaps.
            [[NSNotificationCenter defaultCenter] addObserver: self
                                                     selector: @selector(appearanceMayHaveChanged:)
                                                         name: UIApplicationDidBecomeActiveNotification
                                                       object: nil];
            [[NSNotificationCenter defaultCenter] addObserver: self
                                                     selector: @selector(appearanceMayHaveChanged:)
                                                         name: UIWindowDidBecomeKeyNotification
                                                       object: nil];
            [[NSNotificationCenter defaultCenter] addObserver: self
                                                     selector: @selector(appearanceMayHaveChanged:)
                                                         name: UISceneDidActivateNotification
                                                       object: nil];
        }

        [self updateTraitObserver];
        [self checkColorScheme];
    });
}

- (void)setColorScheme:(nullable NSString *)colorScheme lightBackgroundColor:(nullable NSString *)lightBackgroundColor darkBackgroundColor:(nullable NSString *)darkBackgroundColor {
    self.colorScheme = [GleapThemeHelper validColorScheme: colorScheme];
    self.lightBackgroundColor = [GleapThemeHelper normalizeHexColor: lightBackgroundColor];
    self.darkBackgroundColor = [GleapThemeHelper normalizeHexColor: darkBackgroundColor];

    [self start];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[GleapConfigHelper sharedInstance] refreshColorScheme];
    });
}

- (void)appearanceMayHaveChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateTraitObserver];
        [self checkColorScheme];
    });
}

// Re-detects the app's interface style and re-themes the config when it changed.
- (void)checkColorScheme {
    NSString *colorScheme = [GleapThemeHelper detectAppColorScheme];
    if ([colorScheme isEqualToString: self.detectedColorScheme]) {
        return;
    }
    self.detectedColorScheme = colorScheme;
    [[GleapConfigHelper sharedInstance] refreshColorScheme];
}

// Keeps the observer view on the current key window while the effective scheme
// is "auto", and removes it otherwise.
- (void)updateTraitObserver {
    NSString *colorScheme = [self effectiveColorSchemeForConfig: [GleapConfigHelper sharedInstance].rawConfig];
    if (![colorScheme isEqualToString: GleapColorSchemeAuto]) {
        [self.traitObserverView removeFromSuperview];
        self.traitObserverView = nil;
        return;
    }

    UIWindow *keyWindow = [GleapWindowChecker getKeyWindow];
    if (keyWindow == nil || self.traitObserverView.superview == keyWindow) {
        return;
    }

    [self.traitObserverView removeFromSuperview];
    self.traitObserverView = [[GleapTraitObserverView alloc] initWithFrame: CGRectZero];
    [keyWindow addSubview: self.traitObserverView];
}

// The app's effective interface style: the key window's traits respect the
// app's overrideUserInterfaceStyle, the screen's reflect the system setting.
+ (NSString *)detectAppColorScheme {
    UIUserInterfaceStyle style = UIUserInterfaceStyleUnspecified;
    UIWindow *keyWindow = [GleapWindowChecker getKeyWindow];
    if (keyWindow != nil) {
        style = keyWindow.traitCollection.userInterfaceStyle;
    }
    if (style == UIUserInterfaceStyleUnspecified) {
        style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    }
    return style == UIUserInterfaceStyleDark ? GleapColorSchemeDark : GleapColorSchemeLight;
}

#pragma mark - Config

+ (nullable NSString *)validColorScheme:(nullable id)colorScheme {
    if (![colorScheme isKindOfClass: [NSString class]]) {
        return nil;
    }
    NSString *value = [[(NSString *)colorScheme stringByTrimmingCharactersInSet: NSCharacterSet.whitespaceCharacterSet] lowercaseString];
    if ([value isEqualToString: GleapColorSchemeAuto] || [value isEqualToString: GleapColorSchemeLight] || [value isEqualToString: GleapColorSchemeDark]) {
        return value;
    }
    return nil;
}

// Dark / light mode is off unless the dashboard enables it (colorScheme
// "auto", "light" or "dark"); then the runtime scheme wins over the dashboard's.
- (NSString *)effectiveColorSchemeForConfig:(nullable NSDictionary *)config {
    NSString *dashboardColorScheme = [GleapThemeHelper validColorScheme: [config objectForKey: @"colorScheme"]];
    if (dashboardColorScheme == nil) {
        return GleapColorSchemeDefault;
    }
    NSString *colorScheme = [GleapThemeHelper validColorScheme: self.colorScheme];
    return colorScheme != nil ? colorScheme : dashboardColorScheme;
}

- (nullable NSString *)activeColorSchemeForConfig:(nullable NSDictionary *)config {
    NSString *colorScheme = [self effectiveColorSchemeForConfig: config];
    if ([colorScheme isEqualToString: GleapColorSchemeAuto]) {
        colorScheme = self.detectedColorScheme;
    }
    if ([colorScheme isEqualToString: GleapColorSchemeLight]) {
        return colorScheme;
    }
    // No dark colors = no dark mode.
    if ([colorScheme isEqualToString: GleapColorSchemeDark] &&
        [GleapThemeHelper hasDarkPaletteInConfig: config darkBackgroundColor: self.darkBackgroundColor]) {
        return colorScheme;
    }
    return nil;
}

- (NSDictionary *)applyToConfig:(NSDictionary *)config {
    return [GleapThemeHelper applyColorScheme: [self activeColorSchemeForConfig: config]
                                     toConfig: config
                         lightBackgroundColor: self.lightBackgroundColor
                          darkBackgroundColor: self.darkBackgroundColor];
}

// Base (light) key -> dark palette key.
+ (NSDictionary<NSString *, NSString *> *)darkPaletteKeys {
    return @{
        @"headerColor": @"darkHeaderColor",
        @"headerColor2": @"darkHeaderColor2",
        @"headerColor3": @"darkHeaderColor3",
        @"color": @"darkColor",
        @"backgroundColor": @"darkBackgroundColor"
    };
}

// Base key -> dark key for the dashboard's dark logo, header background image
// and composer glow. Independent fields without fallback: a present dark value
// (also "") is used as it is, an absent one keeps the base value.
+ (NSDictionary<NSString *, NSString *> *)darkAssetKeys {
    return @{
        @"logo": @"darkLogo",
        @"bgImage": @"darkBgImage",
        @"aurora": @"darkAurora"
    };
}

+ (BOOL)hasDarkPaletteInConfig:(nullable NSDictionary *)config darkBackgroundColor:(nullable NSString *)darkBackgroundColor {
    if ([GleapThemeHelper normalizeHexColor: darkBackgroundColor] != nil) {
        return YES;
    }
    for (NSString *darkKey in [GleapThemeHelper darkPaletteKeys].allValues) {
        if ([GleapThemeHelper normalizeHexColor: [config objectForKey: darkKey]] != nil) {
            return YES;
        }
    }
    return NO;
}

+ (NSDictionary *)applyColorScheme:(nullable NSString *)activeColorScheme toConfig:(NSDictionary *)config lightBackgroundColor:(nullable NSString *)lightBackgroundColor darkBackgroundColor:(nullable NSString *)darkBackgroundColor {
    if (config == nil || activeColorScheme == nil) {
        return config;
    }

    if ([activeColorScheme isEqualToString: GleapColorSchemeLight]) {
        // The base colors are the light palette.
        NSString *backgroundColor = [GleapThemeHelper normalizeHexColor: lightBackgroundColor];
        if (backgroundColor == nil) {
            return config;
        }
        NSMutableDictionary *themedConfig = [config mutableCopy];
        [themedConfig setObject: backgroundColor forKey: @"backgroundColor"];
        return themedConfig;
    }

    if (![activeColorScheme isEqualToString: GleapColorSchemeDark] ||
        ![GleapThemeHelper hasDarkPaletteInConfig: config darkBackgroundColor: darkBackgroundColor]) {
        return config;
    }

    NSMutableDictionary *themedConfig = [config mutableCopy];
    NSDictionary<NSString *, NSString *> *darkPaletteKeys = [GleapThemeHelper darkPaletteKeys];
    for (NSString *key in darkPaletteKeys) {
        NSString *darkColor = [GleapThemeHelper normalizeHexColor: [config objectForKey: darkPaletteKeys[key]]];
        if (darkColor != nil) {
            [themedConfig setObject: darkColor forKey: key];
        }
    }
    NSString *runtimeDarkBackgroundColor = [GleapThemeHelper normalizeHexColor: darkBackgroundColor];
    if (runtimeDarkBackgroundColor != nil) {
        [themedConfig setObject: runtimeDarkBackgroundColor forKey: @"backgroundColor"];
    }
    NSDictionary<NSString *, NSString *> *darkAssetKeys = [GleapThemeHelper darkAssetKeys];
    for (NSString *key in darkAssetKeys) {
        id darkValue = [config objectForKey: darkAssetKeys[key]];
        if (darkValue != nil && darkValue != [NSNull null]) {
            [themedConfig setObject: darkValue forKey: key];
        }
    }
    return themedConfig;
}

#pragma mark - Colors

+ (nullable NSString *)normalizeHexColor:(nullable id)color {
    if (![color isKindOfClass: [NSString class]]) {
        return nil;
    }
    NSString *value = [[(NSString *)color stringByTrimmingCharactersInSet: NSCharacterSet.whitespaceCharacterSet] lowercaseString];
    if (![value hasPrefix: @"#"]) {
        return nil;
    }
    NSString *hex = [value substringFromIndex: 1];
    if (hex.length != 3 && hex.length != 6) {
        return nil;
    }
    NSCharacterSet *nonHex = [[NSCharacterSet characterSetWithCharactersInString: @"0123456789abcdef"] invertedSet];
    if ([hex rangeOfCharacterFromSet: nonHex].location != NSNotFound) {
        return nil;
    }
    if (hex.length == 3) {
        unichar r = [hex characterAtIndex: 0], g = [hex characterAtIndex: 1], b = [hex characterAtIndex: 2];
        hex = [NSString stringWithFormat: @"%C%C%C%C%C%C", r, r, g, g, b, b];
    }
    return [@"#" stringByAppendingString: hex];
}

@end
