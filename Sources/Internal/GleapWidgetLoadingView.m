//
//  GleapWidgetLoadingView.m
//  Gleap
//

#import "GleapWidgetLoadingView.h"
#import "GleapUIHelper.h"
#import <CoreImage/CoreImage.h>
#import <math.h>

@interface GleapWidgetLoadingView ()

// Loading-background state. The vector/gradient layers depend on bounds, so they
// are rebuilt in layoutSubviews from the state captured here; the image view (if
// any) is framed there as well and only its fade overlay is reframed.
@property (retain, nonatomic) UIImageView *imageView;
@property (retain, nonatomic) CAGradientLayer *imageFadeLayer;
@property (nonatomic, copy) NSString *bgImageURL;
@property (nonatomic, copy) NSString *bgType;
@property (nonatomic) NSInteger homeVersion;
@property (nonatomic) BOOL isV4;
@property (nonatomic) BOOL fadeBg;
@property (nonatomic) BOOL bgBlur;
@property (retain, nonatomic) UIColor *homeBackgroundColor;
@property (retain, nonatomic) UIColor *headerColor;
@property (retain, nonatomic) UIColor *headerColor2;
@property (retain, nonatomic) UIColor *headerColor3;
@property (nonatomic) BOOL configured;

@end

@implementation GleapWidgetLoadingView

- (void)layoutSubviews {
    [super layoutSubviews];
    [self renderBackground];
}

// Captures the background and header colors from the config.
- (void)applyColorsFromConfig:(NSDictionary *)config {
    // Background color (fallback to the system/white default).
    UIColor *backgroundColor = nil;
    NSString *backgroundColorHex = [config objectForKey: @"backgroundColor"];
    if (backgroundColorHex != nil && [backgroundColorHex isKindOfClass: [NSString class]] && backgroundColorHex.length > 0) {
        backgroundColor = [GleapUIHelper colorFromHexString: backgroundColorHex];
    } else {
        backgroundColor = UIColor.systemBackgroundColor;
    }
    self.homeBackgroundColor = backgroundColor;
    self.backgroundColor = backgroundColor;

    // Header colors. headerColor2/3 fall back to headerColor, exactly like the
    // messenger's getHeaderColorSecondary.
    NSString *headerColorHex = [config objectForKey: @"headerColor"];
    UIColor *headerColor = (headerColorHex != nil && [headerColorHex isKindOfClass: [NSString class]] && headerColorHex.length > 0)
        ? [GleapUIHelper colorFromHexString: headerColorHex]
        : [GleapUIHelper colorFromHexString: @"#485BFF"];
    NSString *headerColor2Hex = [config objectForKey: @"headerColor2"];
    NSString *headerColor3Hex = [config objectForKey: @"headerColor3"];
    self.headerColor = headerColor;
    self.headerColor2 = (headerColor2Hex != nil && [headerColor2Hex isKindOfClass: [NSString class]] && headerColor2Hex.length > 0)
        ? [GleapUIHelper colorFromHexString: headerColor2Hex] : headerColor;
    self.headerColor3 = (headerColor3Hex != nil && [headerColor3Hex isKindOfClass: [NSString class]] && headerColor3Hex.length > 0)
        ? [GleapUIHelper colorFromHexString: headerColor3Hex] : headerColor;
}

- (void)updateThemeFromConfig:(NSDictionary *)config {
    if (!self.configured) {
        return;
    }
    [self applyColorsFromConfig: config];
    [self applyImageFromConfig: config];
    [self renderBackground];
}

// Reads the fetched config, captures the loading-background state, and builds
// the persistent subviews (background layer container + optional image view).
// Bounds-dependent drawing happens in layoutSubviews.
- (void)setUpFromConfig:(NSDictionary *)config {
    [self applyColorsFromConfig: config];

    // bgType + version resolution (mirrors resolveHomeVersion: 1-3 are the
    // classic homes, anything else — incl. unset — resolves to v4).
    NSString *bgType = [config objectForKey: @"bgType"];
    self.bgType = ([bgType isKindOfClass: [NSString class]]) ? bgType : @"";
    NSInteger version = [[config objectForKey: @"v"] respondsToSelector: @selector(integerValue)] ? [[config objectForKey: @"v"] integerValue] : 0;
    self.homeVersion = version;
    self.isV4 = !(version == 1 || version == 2 || version == 3);
    id fadeBgValue = [config objectForKey: @"fadebg"];
    self.fadeBg = (fadeBgValue == nil) ? YES : [fadeBgValue boolValue];
    id bgBlurValue = [config objectForKey: @"bgBlur"];
    self.bgBlur = (bgBlurValue == nil) ? YES : [bgBlurValue boolValue];

    [self applyImageFromConfig: config];

    self.configured = YES;
    [self renderBackground];
}

// Builds the background image view for the config's bgImage (it changes with the
// color scheme), or removes it when there is no image. No-op when unchanged.
- (void)applyImageFromConfig:(NSDictionary *)config {
    NSString *bgImage = [config objectForKey: @"bgImage"];
    BOOL hasImage = [self.bgType isEqualToString: @"image"] && [bgImage isKindOfClass: [NSString class]] && bgImage.length > 0;
    NSString *bgImageURL = hasImage ? bgImage : nil;
    if (bgImageURL == self.bgImageURL || [bgImageURL isEqualToString: self.bgImageURL]) {
        return;
    }
    self.bgImageURL = bgImageURL;
    [self.imageView removeFromSuperview];
    self.imageView = nil;
    [self.imageFadeLayer removeFromSuperlayer];
    self.imageFadeLayer = nil;

    if (hasImage) {
        // White fallback + the background image fading in once loaded (matches
        // the web loader). Frames are assigned in renderBackground so
        // the image is cover-cropped in the SAME box the messenger uses —
        // v4: header-height, v1/v2: above the docked tab bar, v3: full-bleed.
        // Filling a different box would compute a different crop and the
        // loader would show a different slice of the image than the app.
        UIImageView *imageView = [UIImageView new];
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.clipsToBounds = YES;
        imageView.alpha = 0.0;
        [self addSubview: imageView];
        self.imageView = imageView;

        if (self.isV4) {
            // Mirrors the v4 image header's overlay: a soft legibility scrim at
            // the top, clear across the header, whitening into the composer.
            // Colors + locations are built in renderBackground (they
            // depend on the header box height).
            CAGradientLayer *fade = [CAGradientLayer layer];
            fade.startPoint = CGPointMake(0.5, 0.0);
            fade.endPoint = CGPointMake(0.5, 1.0);
            [self.layer addSublayer: fade];
            self.imageFadeLayer = fade;
        }

        [self loadImageFromURL: bgImage intoImageView: imageView];
    }
}

// Downloads the background image and fades it in on the main thread, unless the
// image view has been replaced in the meantime.
- (void)loadImageFromURL:(NSString *)urlString intoImageView:(UIImageView *)imageView {
    NSURL *url = [NSURL URLWithString: urlString];
    if (url == nil) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    __weak UIImageView *weakImageView = imageView;
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
            UIImageView *strongImageView = weakImageView;
            if (strongSelf == nil || strongImageView == nil || strongImageView != strongSelf.imageView) {
                return;
            }
            strongImageView.image = image;
            [UIView animateWithDuration: 0.25 animations:^{
                strongImageView.alpha = 1.0;
            }];
        });
    }] resume];
}

// (Re)builds the bounds-dependent background for the current bounds. Cheap and
// safe to call repeatedly (removes/re-adds its own sublayers).
- (void)renderBackground {
    UIView *loadingView = self;
    if (!self.configured || loadingView.hidden) {
        return;
    }
    CGRect bounds = loadingView.bounds;
    if (bounds.size.width <= 0 || bounds.size.height <= 0) {
        return;
    }

    [CATransaction begin];
    [CATransaction setDisableActions: YES];

    // Clear the vector/gradient layers (tagged so we only clear our own); also
    // when the image replaces them after a color scheme change.
    for (CALayer *layer in [loadingView.layer.sublayers copy]) {
        if ([layer.name isEqualToString: @"gleap-loading-bg"]) {
            [layer removeFromSuperlayer];
        }
    }

    // Image type: frame the image view to the SAME box the messenger renders
    // the image into, so the aspect-fill crop is identical and the loader
    // shows the same slice of the image as the app. v4 shows it header-only
    // (~360pt: logo bar + one-line greeting + composer overlap — an
    // approximation, a multi-line welcome text shifts the real header),
    // v1/v2 full-bleed above the 80pt docked tab bar, v3 truly full-bleed.
    if ([self.bgType isEqualToString: @"image"] && self.imageView != nil) {
        CGFloat imageHeight = bounds.size.height;
        if (self.isV4) {
            imageHeight = MIN(360.0, bounds.size.height);
        } else if (self.homeVersion == 1 || self.homeVersion == 2) {
            imageHeight = MAX(0.0, bounds.size.height - 80.0);
        }
        self.imageView.frame = CGRectMake(0, 0, bounds.size.width, imageHeight);

        if (self.imageFadeLayer != nil && imageHeight > 0) {
            // Top legibility scrim (gone by 60pt), clear across the header,
            // then whitening into the composer as a SMOOTHSTEP band — same
            // easing as the colour variant, so the fade has no visible onset
            // line (Mach band). Centered like the messenger's ramp (solid
            // shortly above the box's bottom edge, so the image never bleeds
            // past the composer).
            UIColor *bg = self.homeBackgroundColor;
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
            self.imageFadeLayer.frame = self.imageView.frame;
            self.imageFadeLayer.colors = fadeColors;
            self.imageFadeLayer.locations = fadeLocations;
        }
        [CATransaction commit];
        return;
    }

    // Rebuild the vector/gradient layers.
    if (self.isV4) {
        [self drawV4ColourBackgroundInBounds: bounds intoView: loadingView];
    } else if ([self.bgType isEqualToString: @"classic"]) {
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
        (id)[self.headerColor CGColor],
        (id)[self.headerColor2 CGColor]
    ];
    gradient.startPoint = CGPointMake(0.5, 0.0);
    gradient.endPoint = CGPointMake(0.5, 1.0);
    [view.layer insertSublayer: gradient atIndex: 0];

    if (self.fadeBg) {
        // Composer fade. Same center as the messenger's ramp (~77pt above the
        // header's bottom edge), but shaped as a smoothstep with many small
        // segments: zero slope at BOTH ends, so there is no first-derivative
        // discontinuity where the fade begins — a sparse linear ramp shows a
        // visible "hard switch" line there (Mach banding).
        UIColor *bg = self.homeBackgroundColor;
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
    CGFloat baseHeight = (self.fadeBg ? 503.0 : 362.0) * scale;
    CAGradientLayer *base = [CAGradientLayer layer];
    base.name = @"gleap-loading-bg";
    base.frame = CGRectMake(0, 0, width, baseHeight);
    base.colors = @[(id)[self.headerColor2 CGColor], (id)[self.headerColor CGColor]];
    base.startPoint = CGPointMake(0.0, 0.0);
    base.endPoint = CGPointMake(1.0, 0.5);
    [view.layer insertSublayer: base atIndex: 0];

    if (self.fadeBg) {
        // Vertical fade into the background color (BGclassic paint1: y 158→473).
        CGFloat fadeTop = 158.0 * scale;
        CAGradientLayer *fade = [CAGradientLayer layer];
        fade.name = @"gleap-loading-bg";
        fade.frame = CGRectMake(0, fadeTop, width, bounds.size.height - fadeTop);
        fade.colors = @[
            (id)[[self.homeBackgroundColor colorWithAlphaComponent: 0.0] CGColor],
            (id)[self.homeBackgroundColor CGColor]
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

    if (!self.bgBlur) {
        [view.layer insertSublayer: [self blobLayerFromPoints: blob2 scale: scale color: self.headerColor] atIndex: 0];
        [view.layer insertSublayer: [self blobLayerFromPoints: blob1 scale: scale color: self.headerColor2] atIndex: 1];
        [view.layer insertSublayer: [self blobLayerFromPoints: blob3 scale: scale color: self.headerColor3] atIndex: 2];
        return;
    }

    // Render at scale 1 — the result is blurred anyway, and it keeps the
    // CoreImage pass cheap (radius maps 1:1 to CSS blur px).
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1.0;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize: bounds.size format: format];
    UIImage *sharpImage = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        [self.homeBackgroundColor setFill];
        UIRectFill(CGRectMake(0, 0, bounds.size.width, bounds.size.height));
        [self.headerColor setFill];
        [[self blobPathFromPoints: blob2 scale: scale] fill];
        [self.headerColor2 setFill];
        [[self blobPathFromPoints: blob1 scale: scale] fill];
        [self.headerColor3 setFill];
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

@end
