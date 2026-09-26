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

static NSString * const GleapDefaultLightBackgroundColor = @"#ffffff";
static NSString * const GleapDefaultDarkBackgroundColor = @"#18181b";

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

// Runtime scheme first, then the dashboard setting.
- (NSString *)effectiveColorSchemeForConfig:(nullable NSDictionary *)config {
    NSString *colorScheme = [GleapThemeHelper validColorScheme: self.colorScheme];
    if (colorScheme == nil) {
        colorScheme = [GleapThemeHelper validColorScheme: [config objectForKey: @"colorScheme"]];
    }
    return colorScheme != nil ? colorScheme : GleapColorSchemeDefault;
}

- (nullable NSString *)activeColorSchemeForConfig:(nullable NSDictionary *)config {
    NSString *colorScheme = [self effectiveColorSchemeForConfig: config];
    if ([colorScheme isEqualToString: GleapColorSchemeAuto]) {
        return self.detectedColorScheme;
    }
    if ([colorScheme isEqualToString: GleapColorSchemeLight] || [colorScheme isEqualToString: GleapColorSchemeDark]) {
        return colorScheme;
    }
    return nil;
}

- (NSDictionary *)applyToConfig:(NSDictionary *)config {
    NSString *lightBackgroundColor = self.lightBackgroundColor;
    if (lightBackgroundColor == nil) {
        lightBackgroundColor = [GleapThemeHelper normalizeHexColor: [config objectForKey: @"lightBackgroundColor"]];
    }
    NSString *darkBackgroundColor = self.darkBackgroundColor;
    if (darkBackgroundColor == nil) {
        darkBackgroundColor = [GleapThemeHelper normalizeHexColor: [config objectForKey: @"darkBackgroundColor"]];
    }

    return [GleapThemeHelper applyColorScheme: [self activeColorSchemeForConfig: config]
                                     toConfig: config
                         lightBackgroundColor: lightBackgroundColor != nil ? lightBackgroundColor : GleapDefaultLightBackgroundColor
                          darkBackgroundColor: darkBackgroundColor != nil ? darkBackgroundColor : GleapDefaultDarkBackgroundColor];
}

+ (NSDictionary *)applyColorScheme:(nullable NSString *)activeColorScheme toConfig:(NSDictionary *)config lightBackgroundColor:(NSString *)lightBackgroundColor darkBackgroundColor:(NSString *)darkBackgroundColor {
    if (config == nil || activeColorScheme == nil) {
        return config;
    }

    BOOL dark = [activeColorScheme isEqualToString: GleapColorSchemeDark];
    NSString *configuredBackgroundColor = [config objectForKey: @"backgroundColor"];
    if (![configuredBackgroundColor isKindOfClass: [NSString class]] || configuredBackgroundColor.length == 0) {
        configuredBackgroundColor = GleapDefaultLightBackgroundColor;
    }

    // A dashboard background that already fits the scheme keeps the brand look.
    if (dark == [GleapThemeHelper isDarkBackgroundColor: configuredBackgroundColor]) {
        return config;
    }

    NSMutableDictionary *themedConfig = [config mutableCopy];
    [themedConfig setObject: dark ? darkBackgroundColor : lightBackgroundColor forKey: @"backgroundColor"];
    return themedConfig;
}

#pragma mark - Colors

// Parses #rgb, #rrggbb and #rrggbbaa into 0-255 channels.
+ (BOOL)parseHexColor:(nullable id)color red:(CGFloat *)red green:(CGFloat *)green blue:(CGFloat *)blue {
    if (![color isKindOfClass: [NSString class]]) {
        return NO;
    }
    NSString *value = [(NSString *)color stringByTrimmingCharactersInSet: NSCharacterSet.whitespaceCharacterSet];
    if (![value hasPrefix: @"#"]) {
        return NO;
    }
    NSString *hex = [value substringFromIndex: 1];
    NSCharacterSet *nonHex = [[NSCharacterSet characterSetWithCharactersInString: @"0123456789abcdefABCDEF"] invertedSet];
    if ([hex rangeOfCharacterFromSet: nonHex].location != NSNotFound) {
        return NO;
    }
    if (hex.length == 3) {
        unichar r = [hex characterAtIndex: 0], g = [hex characterAtIndex: 1], b = [hex characterAtIndex: 2];
        hex = [NSString stringWithFormat: @"%C%C%C%C%C%C", r, r, g, g, b, b];
    } else if (hex.length == 8) {
        hex = [hex substringToIndex: 6];
    } else if (hex.length != 6) {
        return NO;
    }

    unsigned int rgb = 0;
    [[NSScanner scannerWithString: hex] scanHexInt: &rgb];
    *red = (rgb >> 16) & 0xFF;
    *green = (rgb >> 8) & 0xFF;
    *blue = rgb & 0xFF;
    return YES;
}

+ (BOOL)isDarkBackgroundColor:(nullable NSString *)color {
    CGFloat red = 0, green = 0, blue = 0;
    if (![GleapThemeHelper parseHexColor: color red: &red green: &green blue: &blue]) {
        return NO;
    }
    CGFloat yiq = ((red * 299.0) + (green * 587.0) + (blue * 114.0)) / 1000.0;
    return yiq < 160.0;
}

+ (nullable NSString *)normalizeHexColor:(nullable id)color {
    if (![color isKindOfClass: [NSString class]]) {
        return nil;
    }
    NSString *value = [(NSString *)color stringByTrimmingCharactersInSet: NSCharacterSet.whitespaceCharacterSet];
    if (value.length != 4 && value.length != 7) {
        return nil;
    }
    CGFloat red = 0, green = 0, blue = 0;
    if (![GleapThemeHelper parseHexColor: value red: &red green: &green blue: &blue]) {
        return nil;
    }
    return [NSString stringWithFormat: @"#%02x%02x%02x", (int)red, (int)green, (int)blue];
}

@end
