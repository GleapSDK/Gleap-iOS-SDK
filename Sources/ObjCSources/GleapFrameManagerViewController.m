//
//  GleapWidgetViewController.m
//  Gleap
//
//  Created by Lukas on 13.01.19.
//  Copyright © 2019 Gleap. All rights reserved.
//

#import "GleapFrameManagerViewController.h"
#import "GleapCore.h"
#import "GleapReplayHelper.h"
#import "GleapSessionHelper.h"
#import "GleapTranslationHelper.h"
#import "GleapConfigHelper.h"
#import <SafariServices/SafariServices.h>
#import <CoreImage/CoreImage.h>
#import <math.h>
#import "GleapFeedback.h"
#import "GleapWidgetManager.h"
#import "GleapScreenshotManager.h"
#import "GleapUIHelper.h"
#import "GleapPreFillHelper.h"
#import "GleapAgentToolHelper.h"

// How long we may take to answer the widget's `collect-ticket-data` request.
// The widget drops the whole payload once its own timeout elapses, so this stays
// comfortably below it (see CommunicationManager.sendMessageWithResolver in the
// messenger).
static NSTimeInterval const kGleapCollectTicketDataDeadline = 0.4;

@interface GleapFrameManagerViewController ()

@property (retain, nonatomic) WKWebView *webView;
@property (retain, nonatomic) UIView *loadingView;
@property (retain, nonatomic) UIActivityIndicatorView *loadingActivityView;

// Loading-background state. The loading view mirrors the messenger's home
// background (matching the web SDK's loader) so the hand-off to the webview is
// seamless. The vector/gradient layers depend on bounds, so they are rebuilt in
// viewDidLayoutSubviews from the state captured here; the image view (if any)
// is laid out via Auto Layout and only its fade overlay is reframed.
@property (retain, nonatomic) UIImageView *loadingImageView;
@property (retain, nonatomic) CAGradientLayer *loadingImageFadeLayer;
@property (nonatomic, copy) NSString *loadingBgType;
@property (nonatomic) NSInteger loadingHomeVersion;
@property (nonatomic) BOOL loadingIsV4;
@property (nonatomic) BOOL loadingFadeBg;
@property (nonatomic) BOOL loadingBgBlur;
@property (retain, nonatomic) UIColor *loadingBackgroundColor;
@property (retain, nonatomic) UIColor *loadingHeaderColor;
@property (retain, nonatomic) UIColor *loadingHeaderColor2;
@property (retain, nonatomic) UIColor *loadingHeaderColor3;

@end

static id ObjectOrNull(id object)
{
  return object ?: [NSNull null];
}

@implementation GleapFrameManagerViewController

- (id)initWithFormat:(NSString *)format
{
   self = [super initWithNibName: nil bundle:nil];
   if (self != nil)
   {
       self.connected = NO;
       self.isCardSurvey = [format isEqualToString: @"survey"];
       
       // Apply preview only if not simple survey.
       if (!self.isCardSurvey) {
           self.view.backgroundColor = [UIColor colorWithRed: 0.0 green: 0.0 blue: 0.0 alpha: 0.7];
           
           NSDictionary *config = GleapConfigHelper.sharedInstance.config;
           if (config != nil) {
               NSString *backgroundColor = [config objectForKey: @"backgroundColor"];
               if (backgroundColor != nil && backgroundColor.length > 0) {
                   self.view.backgroundColor = [GleapUIHelper colorFromHexString: backgroundColor];
               } else {
                   if (@available(iOS 13.0, *)) {
                       self.view.backgroundColor = [UIColor systemBackgroundColor];
                   } else {
                       self.view.backgroundColor = [UIColor whiteColor];
                   }
               }
           }
       }
   }
   return self;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.userInteractionEnabled = NO;
    [self createWebView];
    [self setupLoadingView];
}

- (void)setupLoadingView {
    UIView *loadingView = [UIView new];
    self.loadingView = loadingView;

    if (self.isCardSurvey) {
        // Card surveys keep the centered spinner over a dimmed backdrop.
        UIActivityIndicatorView *loadingActivityView;
        if (@available(iOS 13.0, *)) {
            loadingActivityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        } else {
            loadingActivityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        }
        [loadingActivityView startAnimating];
        loadingView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
        loadingActivityView.color = UIColor.whiteColor;

        [self.view addSubview: loadingView];
        loadingView.translatesAutoresizingMaskIntoConstraints = NO;
        [self pinEdgesFrom: loadingView to: self.view];

        loadingActivityView.translatesAutoresizingMaskIntoConstraints = NO;
        [loadingView addSubview: loadingActivityView];
        [[loadingActivityView.centerXAnchor constraintEqualToAnchor: loadingView.centerXAnchor] setActive:YES];
        [[loadingActivityView.centerYAnchor constraintEqualToAnchor: loadingView.centerYAnchor] setActive:YES];
        self.loadingActivityView = loadingActivityView;
        return;
    }

    // Add the loading view to the hierarchy FIRST so it has resolved bounds
    // before we build the background onto it.
    [self.view addSubview: loadingView];
    loadingView.translatesAutoresizingMaskIntoConstraints = NO;
    [self pinEdgesFrom: loadingView to: self.view];

    // Widget loader: mirror the messenger's home background so the reveal is
    // seamless. No spinner — the background itself is the loading indicator
    // (matches the web SDK). Actual home entrance animations run inside the
    // webview once it boots.
    [self setupWidgetLoadingBackground];
}

// Reads the fetched config, captures the loading-background state, and builds
// the persistent subviews (background layer container + optional image view).
// Bounds-dependent drawing happens in viewDidLayoutSubviews.
- (void)setupWidgetLoadingBackground {
    NSDictionary *config = GleapConfigHelper.sharedInstance.config;

    // Background color (fallback to the system/white default).
    UIColor *backgroundColor = nil;
    NSString *backgroundColorHex = [config objectForKey: @"backgroundColor"];
    if (backgroundColorHex != nil && [backgroundColorHex isKindOfClass: [NSString class]] && backgroundColorHex.length > 0) {
        backgroundColor = [GleapUIHelper colorFromHexString: backgroundColorHex];
    } else if (@available(iOS 13.0, *)) {
        backgroundColor = UIColor.systemBackgroundColor;
    } else {
        backgroundColor = UIColor.whiteColor;
    }
    self.loadingBackgroundColor = backgroundColor;
    self.loadingView.backgroundColor = backgroundColor;

    // Header colors. headerColor2/3 fall back to headerColor, exactly like the
    // messenger's getHeaderColorSecondary.
    NSString *headerColorHex = [config objectForKey: @"headerColor"];
    UIColor *headerColor = (headerColorHex != nil && [headerColorHex isKindOfClass: [NSString class]] && headerColorHex.length > 0)
        ? [GleapUIHelper colorFromHexString: headerColorHex]
        : [GleapUIHelper colorFromHexString: @"#485BFF"];
    NSString *headerColor2Hex = [config objectForKey: @"headerColor2"];
    NSString *headerColor3Hex = [config objectForKey: @"headerColor3"];
    self.loadingHeaderColor = headerColor;
    self.loadingHeaderColor2 = (headerColor2Hex != nil && [headerColor2Hex isKindOfClass: [NSString class]] && headerColor2Hex.length > 0)
        ? [GleapUIHelper colorFromHexString: headerColor2Hex] : headerColor;
    self.loadingHeaderColor3 = (headerColor3Hex != nil && [headerColor3Hex isKindOfClass: [NSString class]] && headerColor3Hex.length > 0)
        ? [GleapUIHelper colorFromHexString: headerColor3Hex] : headerColor;

    // bgType + version resolution (mirrors resolveHomeVersion: 1-3 are the
    // classic homes, anything else — incl. unset — resolves to v4).
    NSString *bgType = [config objectForKey: @"bgType"];
    self.loadingBgType = ([bgType isKindOfClass: [NSString class]]) ? bgType : @"";
    NSInteger version = [[config objectForKey: @"v"] respondsToSelector: @selector(integerValue)] ? [[config objectForKey: @"v"] integerValue] : 0;
    self.loadingHomeVersion = version;
    self.loadingIsV4 = !(version == 1 || version == 2 || version == 3);
    id fadeBgValue = [config objectForKey: @"fadebg"];
    self.loadingFadeBg = (fadeBgValue == nil) ? YES : [fadeBgValue boolValue];
    id bgBlurValue = [config objectForKey: @"bgBlur"];
    self.loadingBgBlur = (bgBlurValue == nil) ? YES : [bgBlurValue boolValue];

    NSString *bgImage = [config objectForKey: @"bgImage"];
    BOOL hasImage = [self.loadingBgType isEqualToString: @"image"] && [bgImage isKindOfClass: [NSString class]] && bgImage.length > 0;
    if (hasImage) {
        // White fallback + the background image fading in once loaded (matches
        // the web loader). Frames are assigned in renderLoadingBackground so
        // the image is cover-cropped in the SAME box the messenger uses —
        // v4: header-height, v1/v2: above the docked tab bar, v3: full-bleed.
        // Filling a different box would compute a different crop and the
        // loader would show a different slice of the image than the app.
        UIImageView *imageView = [UIImageView new];
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.clipsToBounds = YES;
        imageView.alpha = 0.0;
        [self.loadingView addSubview: imageView];
        self.loadingImageView = imageView;

        if (self.loadingIsV4) {
            // Mirrors the v4 image header's overlay: a soft legibility scrim at
            // the top, clear across the header, whitening into the composer.
            // Colors + locations are built in renderLoadingBackground (they
            // depend on the header box height).
            CAGradientLayer *fade = [CAGradientLayer layer];
            fade.startPoint = CGPointMake(0.5, 0.0);
            fade.endPoint = CGPointMake(0.5, 1.0);
            [self.loadingView.layer addSublayer: fade];
            self.loadingImageFadeLayer = fade;
        }

        [self loadLoadingImageFromURL: bgImage];
    }

    [self renderLoadingBackground];
}

// Downloads the background image and fades it in on the main thread.
- (void)loadLoadingImageFromURL:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString: urlString];
    if (url == nil) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithURL: url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (data == nil || error != nil) {
            return;
        }
        UIImage *image = [UIImage imageWithData: data];
        if (image == nil) {
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil || strongSelf.loadingImageView == nil) {
                return;
            }
            strongSelf.loadingImageView.image = image;
            [UIView animateWithDuration: 0.25 animations:^{
                strongSelf.loadingImageView.alpha = 1.0;
            }];
        });
    }] resume];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self renderLoadingBackground];
}

// (Re)builds the bounds-dependent loading background onto the loading view for
// the current bounds. Cheap and safe to call repeatedly (removes/re-adds its
// own sublayers).
- (void)renderLoadingBackground {
    UIView *loadingView = self.loadingView;
    if (loadingView == nil || self.isCardSurvey || loadingView.hidden) {
        return;
    }
    CGRect bounds = loadingView.bounds;
    if (bounds.size.width <= 0 || bounds.size.height <= 0) {
        return;
    }

    [CATransaction begin];
    [CATransaction setDisableActions: YES];

    // Image type: frame the image view to the SAME box the messenger renders
    // the image into, so the aspect-fill crop is identical and the loader
    // shows the same slice of the image as the app. v4 shows it header-only
    // (~360pt: logo bar + one-line greeting + composer overlap — an
    // approximation, a multi-line welcome text shifts the real header),
    // v1/v2 full-bleed above the 80pt docked tab bar, v3 truly full-bleed.
    if ([self.loadingBgType isEqualToString: @"image"] && self.loadingImageView != nil) {
        CGFloat imageHeight = bounds.size.height;
        if (self.loadingIsV4) {
            imageHeight = MIN(360.0, bounds.size.height);
        } else if (self.loadingHomeVersion == 1 || self.loadingHomeVersion == 2) {
            imageHeight = MAX(0.0, bounds.size.height - 80.0);
        }
        self.loadingImageView.frame = CGRectMake(0, 0, bounds.size.width, imageHeight);

        if (self.loadingImageFadeLayer != nil && imageHeight > 0) {
            // Top legibility scrim (gone by 60pt), clear across the header,
            // then whitening into the composer as a SMOOTHSTEP band — same
            // easing as the colour variant, so the fade has no visible onset
            // line (Mach band). Centered like the messenger's ramp (solid
            // shortly above the box's bottom edge, so the image never bleeds
            // past the composer).
            UIColor *bg = self.loadingBackgroundColor;
            NSMutableArray *fadeColors = [NSMutableArray new];
            NSMutableArray *fadeLocations = [NSMutableArray new];
            [fadeColors addObject: (id)[[UIColor colorWithWhite: 0.0 alpha: 0.2] CGColor]];
            [fadeLocations addObject: @0.0];
            [fadeColors addObject: (id)[[UIColor colorWithWhite: 0.0 alpha: 0.0] CGColor]];
            [fadeLocations addObject: @(MIN(1.0, 60.0 / imageHeight))];
            CGFloat rampTop = imageHeight - 85.0;
            CGFloat rampBottom = imageHeight - 15.0;
            NSInteger steps = 12;
            for (NSInteger i = 0; i <= steps; i++) {
                CGFloat t = (CGFloat)i / (CGFloat)steps;
                CGFloat eased = t * t * (3.0 - 2.0 * t);
                CGFloat y = rampTop + (rampBottom - rampTop) * t;
                [fadeColors addObject: (id)[[bg colorWithAlphaComponent: eased] CGColor]];
                [fadeLocations addObject: @(MAX(0.0, MIN(1.0, y / imageHeight)))];
            }
            self.loadingImageFadeLayer.frame = self.loadingImageView.frame;
            self.loadingImageFadeLayer.colors = fadeColors;
            self.loadingImageFadeLayer.locations = fadeLocations;
        }
        [CATransaction commit];
        return;
    }

    // Rebuild the vector/gradient layers (tagged so we only clear our own).
    for (CALayer *layer in [loadingView.layer.sublayers copy]) {
        if ([layer.name isEqualToString: @"gleap-loading-bg"]) {
            [layer removeFromSuperlayer];
        }
    }

    if (self.loadingIsV4) {
        [self drawV4ColourBackgroundInBounds: bounds intoView: loadingView];
    } else if ([self.loadingBgType isEqualToString: @"classic"]) {
        [self drawClassicBackgroundInBounds: bounds intoView: loadingView];
    } else {
        [self drawGradientBlobsInBounds: bounds intoView: loadingView];
    }
    [CATransaction commit];
}

// v4 colour header: a vertical headerColor → headerColor2 gradient confined to
// the HEADER box (~360pt, same constant as the image variant), easing into the
// background color across the composer via the messenger's actual ramp stops
// (AgentHomeV4.scss: hold full colour until 120pt above the box bottom, solid
// background by 35pt above it). Used for both classic and gradient bgTypes on
// v4 — the app renders them identically. fadebg off hides the ramp: the colour
// runs to a hard edge at the header's bottom.
- (void)drawV4ColourBackgroundInBounds:(CGRect)bounds intoView:(UIView *)view {
    CGFloat headerHeight = MIN(360.0, bounds.size.height);
    if (headerHeight <= 0) {
        return;
    }
    CGRect headerFrame = CGRectMake(0, 0, bounds.size.width, headerHeight);

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.name = @"gleap-loading-bg";
    gradient.frame = headerFrame;
    gradient.colors = @[
        (id)[self.loadingHeaderColor CGColor],
        (id)[self.loadingHeaderColor2 CGColor]
    ];
    gradient.startPoint = CGPointMake(0.5, 0.0);
    gradient.endPoint = CGPointMake(0.5, 1.0);
    [view.layer insertSublayer: gradient atIndex: 0];

    if (self.loadingFadeBg) {
        // Composer fade. Same center as the messenger's ramp (~77pt above the
        // header's bottom edge), but shaped as a smoothstep with many small
        // segments: zero slope at BOTH ends, so there is no first-derivative
        // discontinuity where the fade begins — a sparse linear ramp shows a
        // visible "hard switch" line there (Mach banding).
        UIColor *bg = self.loadingBackgroundColor;
        CGFloat rampTop = headerHeight - 135.0;
        CGFloat rampBottom = headerHeight - 20.0;
        NSInteger steps = 12;
        NSMutableArray *rampColors = [NSMutableArray arrayWithCapacity: steps + 1];
        NSMutableArray *rampLocations = [NSMutableArray arrayWithCapacity: steps + 1];
        for (NSInteger i = 0; i <= steps; i++) {
            CGFloat t = (CGFloat)i / (CGFloat)steps;
            CGFloat eased = t * t * (3.0 - 2.0 * t);
            CGFloat y = rampTop + (rampBottom - rampTop) * t;
            [rampColors addObject: (id)[[bg colorWithAlphaComponent: eased] CGColor]];
            [rampLocations addObject: @(MAX(0.0, MIN(1.0, y / headerHeight)))];
        }
        CAGradientLayer *ramp = [CAGradientLayer layer];
        ramp.name = @"gleap-loading-bg";
        ramp.frame = headerFrame;
        ramp.colors = rampColors;
        ramp.locations = rampLocations;
        ramp.startPoint = CGPointMake(0.5, 0.0);
        ramp.endPoint = CGPointMake(0.5, 1.0);
        [view.layer insertSublayer: ramp above: gradient];
    }
}

// Classic home: a diagonal headerColor2 → headerColor top region that fades
// into the background color (mirrors BGclassic.svg / BGclassicnofade.svg).
- (void)drawClassicBackgroundInBounds:(CGRect)bounds intoView:(UIView *)view {
    CGFloat width = bounds.size.width;
    CGFloat scale = width / 403.0;

    // Base diagonal gradient. fadebg on → 503pt-tall region, off → 362pt.
    CGFloat baseHeight = (self.loadingFadeBg ? 503.0 : 362.0) * scale;
    CAGradientLayer *base = [CAGradientLayer layer];
    base.name = @"gleap-loading-bg";
    base.frame = CGRectMake(0, 0, width, baseHeight);
    base.colors = @[(id)[self.loadingHeaderColor2 CGColor], (id)[self.loadingHeaderColor CGColor]];
    base.startPoint = CGPointMake(0.0, 0.0);
    base.endPoint = CGPointMake(1.0, 0.5);
    [view.layer insertSublayer: base atIndex: 0];

    if (self.loadingFadeBg) {
        // Vertical fade into the background color (BGclassic paint1: y 158→473).
        CGFloat fadeTop = 158.0 * scale;
        CAGradientLayer *fade = [CAGradientLayer layer];
        fade.name = @"gleap-loading-bg";
        fade.frame = CGRectMake(0, fadeTop, width, bounds.size.height - fadeTop);
        fade.colors = @[
            (id)[[self.loadingBackgroundColor colorWithAlphaComponent: 0.0] CGColor],
            (id)[self.loadingBackgroundColor CGColor]
        ];
        fade.startPoint = CGPointMake(0.5, 0.0);
        fade.endPoint = CGPointMake(0.5, 1.0);
        CGFloat fadeSpan = (473.0 - 158.0) * scale;
        CGFloat totalSpan = bounds.size.height - fadeTop;
        CGFloat end = (totalSpan > 0) ? MIN(1.0, fadeSpan / totalSpan) : 1.0;
        fade.locations = @[@0.0, @(end)];
        [view.layer insertSublayer: fade above: base];
    }
}

// Gradient home: the three colour blobs from BG.svg (viewBox 403x598, scaled
// to the current width; paths use only straight segments so they map 1:1).
// With bgBlur (the default) the messenger shows these behind a 30px backdrop
// blur — soft colour clouds, not sharp polygons — so the loader pre-renders
// the blobs into a bitmap and Gaussian-blurs it once. The loader is static, so
// a pre-blurred bitmap is visually identical to the app's live backdrop blur.
// Only the slow blob movement (animateBG) is not replicated: the animation
// starts at scale 1, which is exactly the frame this renders.
- (void)drawGradientBlobsInBounds:(CGRect)bounds intoView:(UIView *)view {
    CGFloat scale = bounds.size.width / 403.0;

    // color2 → headerColor
    NSArray *blob2 = @[@[@0,@0],@[@403,@0],@[@403,@308.5],@[@350.5,@298.5],@[@294,@298.5],@[@144.5,@250],@[@78.5,@152.5],@[@27,@125],@[@0,@104]];
    // color1 → headerColor2
    NSArray *blob1 = @[@[@0,@151],@[@0,@101.5],@[@137,@101.5],@[@156,@151],@[@352,@300],@[@106,@340],@[@0,@344.5]];
    // color3 → headerColor3
    NSArray *blob3 = @[@[@254.5,@118],@[@331.5,@94],@[@403,@85],@[@403,@318],@[@347.5,@318],@[@221,@207]];

    if (!self.loadingBgBlur) {
        [view.layer insertSublayer: [self blobLayerFromPoints: blob2 scale: scale color: self.loadingHeaderColor] atIndex: 0];
        [view.layer insertSublayer: [self blobLayerFromPoints: blob1 scale: scale color: self.loadingHeaderColor2] atIndex: 1];
        [view.layer insertSublayer: [self blobLayerFromPoints: blob3 scale: scale color: self.loadingHeaderColor3] atIndex: 2];
        return;
    }

    // Render at scale 1 — the result is blurred anyway, and it keeps the
    // CoreImage pass cheap (radius maps 1:1 to CSS blur px).
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1.0;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize: bounds.size format: format];
    UIImage *sharpImage = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        [self.loadingBackgroundColor setFill];
        UIRectFill(CGRectMake(0, 0, bounds.size.width, bounds.size.height));
        [self.loadingHeaderColor setFill];
        [[self blobPathFromPoints: blob2 scale: scale] fill];
        [self.loadingHeaderColor2 setFill];
        [[self blobPathFromPoints: blob1 scale: scale] fill];
        [self.loadingHeaderColor3 setFill];
        [[self blobPathFromPoints: blob3 scale: scale] fill];
    }];

    // Clamp edges before blurring (mirrors backdrop-filter's edge behavior),
    // then crop back — otherwise the blur bleeds transparency in from the
    // borders as a dark vignette.
    UIImage *displayImage = sharpImage;
    @try {
        CIImage *inputImage = [CIImage imageWithCGImage: sharpImage.CGImage];
        CIFilter *blurFilter = [CIFilter filterWithName: @"CIGaussianBlur"];
        [blurFilter setValue: [inputImage imageByClampingToExtent] forKey: kCIInputImageKey];
        [blurFilter setValue: @30.0 forKey: kCIInputRadiusKey];
        CIImage *blurredImage = [blurFilter.outputImage imageByCroppingToRect: inputImage.extent];
        if (blurredImage != nil) {
            CIContext *ciContext = [CIContext contextWithOptions: nil];
            CGImageRef blurredCGImage = [ciContext createCGImage: blurredImage fromRect: inputImage.extent];
            if (blurredCGImage != NULL) {
                displayImage = [UIImage imageWithCGImage: blurredCGImage];
                CGImageRelease(blurredCGImage);
            }
        }
    }
    @catch (id exception) {}

    CALayer *imageLayer = [CALayer layer];
    imageLayer.name = @"gleap-loading-bg";
    imageLayer.frame = bounds;
    imageLayer.contents = (id)displayImage.CGImage;
    imageLayer.contentsGravity = kCAGravityResize;
    [view.layer insertSublayer: imageLayer atIndex: 0];
}

- (UIBezierPath *)blobPathFromPoints:(NSArray *)points scale:(CGFloat)scale {
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (NSUInteger i = 0; i < points.count; i++) {
        NSArray *p = points[i];
        CGPoint pt = CGPointMake([p[0] doubleValue] * scale, [p[1] doubleValue] * scale);
        if (i == 0) {
            [path moveToPoint: pt];
        } else {
            [path addLineToPoint: pt];
        }
    }
    [path closePath];
    return path;
}

- (CAShapeLayer *)blobLayerFromPoints:(NSArray *)points scale:(CGFloat)scale color:(UIColor *)color {
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.name = @"gleap-loading-bg";
    layer.path = [self blobPathFromPoints: points scale: scale].CGPath;
    layer.fillColor = color.CGColor;
    return layer;
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return nil;
}

- (void)invalidateTimeout {
    if (self.timeoutTimer) {
        [self.timeoutTimer invalidate];
        self.timeoutTimer = nil;
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [self invalidateTimeout];
}

- (void)closeWidget: (void (^)(void))completion {
    self.connected = NO;
    
    [[GleapWidgetManager sharedInstance] closeWidgetWithAnimation: !self.isCardSurvey andCompletion:^{
        if (completion != nil) {
            completion();
        }
    }];
}

- (void)sendSessionUpdate {
    NSDictionary *currentSession = @{};
    if (GleapSessionHelper.sharedInstance.currentSession != nil) {
        currentSession = [GleapSessionHelper.sharedInstance.currentSession toDictionary];
    }
    
    [self sendMessageWithData: @{
        @"name": @"session-update",
        @"data": @{
            @"sessionData": currentSession,
            @"apiUrl": Gleap.sharedInstance.apiUrl,
            @"sdkKey": Gleap.sharedInstance.token
        }
    }];
}

- (void)sendConfigUpdate {
    if (GleapConfigHelper.sharedInstance.config == nil || GleapConfigHelper.sharedInstance.projectActions == nil) {
        return;
    }
    
    [self sendMessageWithData: @{
        @"name": @"config-update",
        @"data": @{
            @"config": GleapConfigHelper.sharedInstance.config,
            @"actions": GleapConfigHelper.sharedInstance.projectActions,
            @"overrideLanguage": GleapTranslationHelper.sharedInstance.language,
            @"isApp": @(YES),
        }
    }];
}

// Full-screen presentations (iPad) extend the web view under the status bar
// and home indicator. env(safe-area-inset-*) is only available to the shell
// page, not to the messenger's iframe, and WebKit populates it late — so the
// insets the view controller knows for certain are sent explicitly. The
// messenger pads its headers with the top inset (--safe-area-top). Sent on
// connect and whenever UIKit reports a change (rotation, multitasking).
- (void)sendSafeAreaInsets {
    UIEdgeInsets insets = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        insets = self.view.safeAreaInsets;
    }
    [self sendMessageWithData: @{
        @"name": @"safe-area-update",
        @"data": @{
            @"top": @(MAX(0, insets.top)),
            @"right": @(MAX(0, insets.right)),
            @"bottom": @(MAX(0, insets.bottom)),
            @"left": @(MAX(0, insets.left)),
        }
    }];
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    if (self.connected) {
        [self sendSafeAreaInsets];
    }
}

- (void)sendPreFillData {
    [self sendMessageWithData: @{
        @"name": @"prefill-form-data",
        @"data": [GleapPreFillHelper sharedInstance].preFillData
    }];
}

- (void)sendMessageWithData:(NSDictionary *)data {
    @try {
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject: data
                                                           options: 0
                                                             error:&error];
        if (!jsonData) {
            NSLog(@"[GLEAP_SDK] Error sending message: %@", error);
        } else {
            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    [self.webView evaluateJavaScript: [NSString stringWithFormat: @"sendMessage(%@)", jsonString] completionHandler: nil];
                }
                @catch(id exception) {}
            });
        }
    }
    @catch(id exception) {}
}

- (void)stopLoading {
    self.view.userInteractionEnabled = YES;

    // Cross-fade: the loading background (showing the same colors/image) fades
    // out as the webview fades in, so the hand-off reads as continuous. The
    // messenger's own home entrance animations then play inside the webview.
    if (self.loadingView != nil && !self.loadingView.hidden) {
        UIView *loadingView = self.loadingView;
        [UIView animateWithDuration: 0.3 delay: 0.0 options: UIViewAnimationOptionCurveEaseInOut animations:^{
            self.webView.alpha = 1.0;
            loadingView.alpha = 0.0;
        } completion:^(BOOL finished) {
            [loadingView setHidden: YES];
        }];
    } else {
        self.webView.alpha = 1.0;
    }
}

- (void)sendWidgetStatusUpdate {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try
        {
            [self sendMessageWithData: @{
                @"name": @"widget-status-update",
                @"data": @{
                    @"isWidgetOpen": @(YES)
                }
            }];
        }
        @catch(id exception) {}
    });
}

- (void)userContentController:(WKUserContentController*)userContentController didReceiveScriptMessage:(WKScriptMessage*)message
{
    if ([message.name isEqualToString: @"gleapCallback"]) {
        NSString *name = [message.body objectForKey: @"name"];
        NSDictionary *messageData = [message.body objectForKey: @"data"];
        
        if ([name isEqualToString: @"ping"]) {
            [self invalidateTimeout];
            self.connected = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [self stopLoading];
            });
            
            [self sendWidgetStatusUpdate];
            [self sendConfigUpdate];
            [self sendSafeAreaInsets];
            [self sendSessionUpdate];
            [self sendPreFillData];
            [self sendScreenshotUpdate];
            
            if (self.delegate != nil && [self.delegate respondsToSelector:@selector(connected)]) {
                [self.delegate connected];
            }
        }
        
        if ([name isEqualToString: @"tool-execution"]) {
            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(onToolExecution:)]) {
                [Gleap.sharedInstance.delegate onToolExecution: messageData];
            }
        }

        if ([name isEqualToString: @"frontend-tool-execute"] && messageData != nil) {
            __weak typeof(self) weakSelf = self;
            [[GleapAgentToolHelper sharedInstance] executeToolWithData: messageData completion:^(NSDictionary *resultData) {
                [weakSelf sendMessageWithData: @{
                    @"name": @"frontend-tool-result",
                    @"data": resultData
                }];
            }];
        }
        
        if ([name isEqualToString: @"collect-ticket-data"]) {
            // The widget waits a fixed, short time for this reply and silently
            // creates the ticket with NO data at all when it is late — not just
            // without console logs, but without environment data, custom data and
            // tags too. So nothing here may block on slow collection: everything
            // except the console log is read from memory and is instant, and the
            // logs (OSLogStore, regularly slower than the widget will wait) are
            // collected under a deadline and dropped when they miss it.
            GleapFeedback *feedback = [[GleapFeedback alloc] init];
            __weak typeof(self) weakSelf = self;
            [feedback prepareDataWithDeadline: kGleapCollectTicketDataDeadline completion:^{
                [weakSelf sendMessageWithData: @{
                    @"name": @"collect-ticket-data",
                    @"data": @{
                        @"customData": ObjectOrNull([feedback.data objectForKey: @"customData"]),
                        @"formData": ObjectOrNull([feedback.data objectForKey: @"formData"]),
                        @"metaData": ObjectOrNull([feedback.data objectForKey: @"metaData"]),
                        @"consoleLog": ObjectOrNull([feedback.data objectForKey: @"consoleLog"]),
                        @"networkLogs": ObjectOrNull([feedback.data objectForKey: @"networkLogs"]),
                        @"customEventLog": ObjectOrNull([feedback.data objectForKey: @"customEventLog"]),
                        @"tags": ObjectOrNull([feedback.data objectForKey: @"tags"])
                    }
                }];
            }];
        }
        
        if ([name isEqualToString: @"cleanup-drawings"]) {
            [GleapScreenshotManager sharedInstance].updatedScreenshot = nil;
        }
        
        if ([name isEqualToString: @"close-widget"]) {
            [self closeWidget: nil];
        }
        
        if ([name isEqualToString: @"screenshot-updated"] && messageData != nil) {
            @try
            {
                NSString *screenshotBase64String = (NSString *)messageData;
                if (screenshotBase64String != nil) {
                    screenshotBase64String = [screenshotBase64String stringByReplacingOccurrencesOfString: @"data:image/png;base64," withString: @""];
                    NSData *dataEncoded = [[NSData alloc] initWithBase64EncodedString: screenshotBase64String options:0];
                    if (dataEncoded != nil) {
                        [GleapScreenshotManager sharedInstance].updatedScreenshot = [UIImage imageWithData:dataEncoded];
                    }
                }
            }
            @catch(id exception) {}
        }
        
        if ([name isEqualToString: @"run-custom-action"] && messageData != nil) {
            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(customActionCalled:withShareToken:)]) {
                NSString *shareToken = [message.body objectForKey: @"shareToken"];
                
                [Gleap.sharedInstance.delegate customActionCalled: (NSString *)messageData withShareToken: shareToken];
            }
            
            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(customActionCalled:)]) {
                [Gleap.sharedInstance.delegate customActionCalled: (NSString *)messageData];
            }
        }
        
        if ([name isEqualToString: @"open-url"] && messageData != nil) {
            if (Gleap.sharedInstance.closeWidgetOnExternalLinkOpen == YES) {
                [self closeWidget:^{
                    [Gleap handleURL: (NSString *)messageData];
                }];
            } else {
                [Gleap handleURL: (NSString *)messageData];
            }
        }
        
        if ([name isEqualToString: @"notify-event"] && messageData != nil) {
            NSString *eventType = [messageData objectForKey: @"type"];
            NSDictionary *eventData = [messageData objectForKey: @"data"];
            
            if ([eventType isEqualToString: @"flow-started"]) {
                [GleapScreenshotManager sharedInstance].updatedScreenshot = nil;
                
                if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(feedbackFlowStarted:)]) {
                    [Gleap.sharedInstance.delegate feedbackFlowStarted: eventData];
                }
            }
        }
        
        if ([name isEqualToString: @"send-feedback"] && messageData != nil) {
            NSDictionary *formData = [messageData objectForKey: @"formData"];
            NSDictionary *action = [messageData objectForKey: @"action"];
            NSString *outboundId = [messageData objectForKey: @"outboundId"];
            
            GleapFeedback *feedback = [[GleapFeedback alloc] init];
            [feedback appendData: @{
                @"formData": formData,
            }];
            
            NSString *spamToken = [messageData objectForKey: @"spamToken"];
            if (spamToken != nil) {
                [feedback appendData: @{
                    @"spamToken": spamToken,
                }];
            }
            
            // Attach exclude data.
            if (action != nil && [action objectForKey: @"excludeData"] != nil) {
                feedback.excludeData = [action objectForKey: @"excludeData"];
            }
            
            UIImage *screenshot = [GleapScreenshotManager getScreenshotToAttach];
            if (screenshot != nil) {
                feedback.screenshot = screenshot;
            }
            
            if (outboundId != nil) {
                feedback.outboundId = outboundId;
            }
            
            if (action != nil && [action objectForKey: @"feedbackType"] != nil) {
                feedback.feedbackType = [action objectForKey: @"feedbackType"];
            }
            
            [feedback send:^(bool success, NSDictionary* data) {
                if (success) {
                    [self sendMessageWithData: @{
                        @"name": @"feedback-sent",
                        @"data": data
                    }];
                    
                    @try {
                        if (outboundId != nil) {
                            [Gleap trackEvent: [NSString stringWithFormat: @"outbound-%@-submitted", outboundId] withData: formData];
                            
                            // Notify about outbound sent event.
                            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(outboundSent:)]) {
                                [Gleap.sharedInstance.delegate outboundSent: @{
                                    @"outboundId": ObjectOrNull(outboundId),
                                    @"outbound": ObjectOrNull(action),
                                    @"formData": ObjectOrNull(formData),
                                }];
                            }
                        }
                    } @catch (id exp) {}
                } else {
                    NSError *error;
                    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data options:0 error:&error];
                    
                    NSString *jsonString;
                    if (!jsonData) {
                        NSLog(@"Error converting data to JSON: %@", error);
                        jsonString = @"{\"error\": \"Conversion to JSON failed\"}";
                    } else {
                        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                    }

                    [self sendMessageWithData: @{
                        @"name": @"feedback-sending-failed",
                        @"data": jsonString
                    }];
                }
            }];
        }
    }
}

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler
{
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:message
                                                                             message:nil
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK"
                                                        style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction *action) {
                                                          completionHandler();
                                                      }]];
    [self presentViewController:alertController animated:YES completion:^{}];
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    NSURL *url = navigationAction.request.URL;
    [self openURLExternally: url fromViewController: self];
    return nil;
}

- (void)createWebView {
    WKWebViewConfiguration *webConfig = [[WKWebViewConfiguration alloc] init];
    WKUserContentController* userController = [[WKUserContentController alloc] init];
    [userController addScriptMessageHandler: self name: @"gleapCallback"];
    webConfig.userContentController = userController;
    webConfig.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    
    self.webView = [[WKWebView alloc] initWithFrame:self.view.frame configuration: webConfig];
    self.webView.opaque = false;
    self.webView.backgroundColor = UIColor.clearColor;
    self.webView.scrollView.backgroundColor = UIColor.clearColor;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.scrollView.bounces = NO;
    self.webView.scrollView.alwaysBounceVertical = NO;
    self.webView.scrollView.alwaysBounceHorizontal = NO;
    self.webView.scrollView.scrollEnabled = NO;
    self.webView.allowsBackForwardNavigationGestures = NO;
    
    if (@available(iOS 11.0, *)) {
        [self.webView.scrollView setContentInsetAdjustmentBehavior: UIScrollViewContentInsetAdjustmentNever];
    }
    
    [self.view addSubview: self.webView];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    [self pinEdgesFrom: self.webView to: self.view];
    
    self.timeoutTimer = [NSTimer scheduledTimerWithTimeInterval: 15
                                         target: self
                                       selector: @selector(requestTimedOut:)
                                       userInfo: nil
                                        repeats: NO];
    NSURLRequest * request = [NSURLRequest requestWithURL: [NSURL URLWithString: Gleap.sharedInstance.frameUrl]];
    [self.webView loadRequest: request];
}

- (void)addFullConstraintsFrom:(UIView *)view toOtherView:(UIView *)otherView {
    [otherView addConstraint:[NSLayoutConstraint constraintWithItem: view attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem: otherView attribute:NSLayoutAttributeCenterY multiplier:1.0 constant:0]];
    [otherView addConstraint:[NSLayoutConstraint constraintWithItem: view attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:otherView attribute:NSLayoutAttributeCenterX multiplier:1.0 constant:0]];
    [otherView addConstraint:[NSLayoutConstraint constraintWithItem: view attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem: otherView attribute:NSLayoutAttributeHeight multiplier:1.0 constant:0]];
    [otherView addConstraint:[NSLayoutConstraint constraintWithItem: view attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem: otherView attribute:NSLayoutAttributeWidth multiplier:1.0 constant:0]];
}

- (void)sendScreenshotUpdate {
    UIImage *screenshot = [GleapScreenshotManager getScreenshot];
    if (screenshot == nil) {
        return;
    }
    
    @try
    {
        NSData *data = UIImagePNGRepresentation(screenshot);
        NSString *base64Data = [data base64EncodedStringWithOptions: 0];
        [self sendMessageWithData: @{
            @"name": @"screenshot-update",
            @"data": [NSString stringWithFormat: @"data:image/png;base64,%@", base64Data]
        }];
    }
    @catch(id exception) {}
}

- (void)showSuccessMessage {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try
        {
            [self.webView evaluateJavaScript: @"Gleap.getInstance().showSuccessAndClose()" completionHandler: nil];
        }
        @catch(id exception) {}
    });
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self loadingFailed: error];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self loadingFailed: error];
}

- (void)requestTimedOut:(id)sender {
    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(failedToConnect)]) {
        [self.delegate failedToConnect];
    }
    [self closeWidget: nil];
}

- (void)loadingFailed:(NSError *)error {
    self.view.userInteractionEnabled = YES;
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle: error.localizedDescription
                                                                             message: nil
                                                                      preferredStyle: UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK"
                                                        style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction *action) {
        [self closeWidget: nil];
    }]];
    [self presentViewController:alertController animated:YES completion:^{}];
}

- (void)openURLExternally:(NSURL *)url fromViewController:(UIViewController *)presentingViewController {
    @try {
        if ([SFSafariViewController class]) {
            SFSafariViewController *viewController = [[SFSafariViewController alloc] initWithURL: url];
            viewController.modalPresentationStyle = UIModalPresentationFormSheet;
            viewController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
            [presentingViewController presentViewController:viewController animated:YES completion:nil];
        } else {
            if ([[UIApplication sharedApplication] canOpenURL: url]) {
                if (@available(iOS 10.0, *)) {
                    [[UIApplication sharedApplication] openURL: url options:@{} completionHandler:nil];
                }
            }
        }
    } @catch (id exp) {
        
    }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated) {
        NSURL *url = navigationAction.request.URL;
        if ([url.absoluteString hasPrefix: @"mailto:"]) {
            if ([[UIApplication sharedApplication] canOpenURL: url]) {
                if (@available(iOS 10.0, *)) {
                    [[UIApplication sharedApplication] openURL: url options:@{} completionHandler:nil];
                }
            }
        } else {
            [self openURLExternally: url fromViewController: self];
        }
        return decisionHandler(WKNavigationActionPolicyCancel);
    }
    
    return decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)pinEdgesFrom:(UIView *)subView to:(UIView *)parent {
    NSLayoutConstraint *trailing = [NSLayoutConstraint
                                    constraintWithItem: subView
                                    attribute: NSLayoutAttributeTrailing
                                    relatedBy: NSLayoutRelationEqual
                                    toItem: parent
                                    attribute: NSLayoutAttributeTrailing
                                    multiplier: 1.0f
                                    constant: 0.f];
    NSLayoutConstraint *leading = [NSLayoutConstraint
                                       constraintWithItem: subView
                                       attribute: NSLayoutAttributeLeading
                                       relatedBy: NSLayoutRelationEqual
                                       toItem: parent
                                       attribute: NSLayoutAttributeLeading
                                       multiplier: 1.0f
                                       constant: 0.f];
    [parent addConstraint: leading];
    [parent addConstraint: trailing];
    
    NSLayoutConstraint *bottom =[NSLayoutConstraint
                                 constraintWithItem: subView
                                 attribute: NSLayoutAttributeBottom
                                 relatedBy: NSLayoutRelationEqual
                                 toItem: parent
                                 attribute: NSLayoutAttributeBottom
                                 multiplier: 1.0f
                                 constant: 0.f];
    NSLayoutConstraint *top =[NSLayoutConstraint
                              constraintWithItem: subView
                              attribute: NSLayoutAttributeTop
                              relatedBy: NSLayoutRelationEqual
                              toItem: parent
                              attribute: NSLayoutAttributeTop
                              multiplier: 1.0f
                              constant: 0.f];
    [parent addConstraint: top];
    [parent addConstraint: bottom];
}

@end
