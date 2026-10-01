//
//  GleapCaptureOverlay.m
//  Gleap
//

#import "GleapCaptureOverlay.h"
#import "GleapCaptureRenderer.h"
#import "GleapUIHelper.h"
#import "GleapWindowChecker.h"
#import <AVFoundation/AVFoundation.h>

// One look with the web SDK's bar: a dark, fully rounded pill whatever the app looks like, round controls, the main
// button in the widget color.
static CGFloat const kGleapBarContentHeight = 44.0;
static CGFloat const kGleapBarVerticalPadding = 4.0;
// As far from the ends as the 36 pt circles are from the top and bottom, so they sit concentric in the rounded ends.
static CGFloat const kGleapBarHorizontalPadding = 8.0;
static CGFloat const kGleapBarSpacing = 6.0;
// The bar starts this far above the safe area (or the keyboard) and is at most this much narrower than the screen.
static CGFloat const kGleapBarScreenMargin = 16.0;
// Dragged, it stays this far inside the safe area...
static CGFloat const kGleapBarEdgeMargin = 8.0;
// ...and snaps to the horizontal center when released this close to it.
static CGFloat const kGleapBarSnapDistance = 24.0;
static CGFloat const kGleapButtonHeight = 36.0;
// The touch target of the 36 pt buttons.
static CGFloat const kGleapMinimumHitSize = 44.0;
static CGFloat const kGleapCaptionMaxWidth = 280.0;
static NSTimeInterval const kGleapCaptionDuration = 4.0;
static CGFloat const kGleapPreviewButtonHeight = 48.0;

static UIColor *GleapCaptureColor(uint32_t rgb, CGFloat alpha) {
    return [UIColor colorWithRed: ((rgb >> 16) & 0xFF) / 255.0 green: ((rgb >> 8) & 0xFF) / 255.0 blue: (rgb & 0xFF) / 255.0 alpha: alpha];
}

static UIColor *GleapBarFillColor(void) { return GleapCaptureColor(0x16161A, 0.97); }
static UIColor *GleapHairlineColor(void) { return [UIColor colorWithWhite: 1.0 alpha: 0.10]; }
static UIColor *GleapStopColor(void) { return GleapCaptureColor(0xE5484D, 1.0); }

// Where the customer left the bar: a point in the safe area (0…1 on both axes), for the rest of the app's run.
static BOOL gleapBarHasPosition = NO;
static CGPoint gleapBarPosition;

#pragma mark - Labels

@interface GleapCaptureLabels ()
@property (nonatomic, copy) NSDictionary *labels;
@end

@implementation GleapCaptureLabels

+ (NSDictionary<NSString *, NSString *> *)defaultLabels {
    return @{
        @"barScreenshotHint": @"Go to the screen you want to show, then tap Capture.",
        @"barCapture": @"Capture",
        @"barCancel": @"Cancel",
        @"barRecordHint": @"Go to where the issue happens, then start recording.",
        @"barStart": @"Start",
        @"barStop": @"Stop",
        @"barRecording": @"Recording",
        @"barDragHint": @"Drag to move",
        @"microphone": @"Microphone",
        @"previewTitle": @"Send this recording?",
        @"previewSend": @"Send",
        @"previewRetake": @"Retake",
        @"previewPlay": @"Play",
        @"previewPause": @"Pause",
        @"uploading": @"Uploading…",
        @"recordingInterrupted": @"Recording stopped because the page changed.",
        @"recordAgain": @"Record again",
        @"permissionDenied": @"Screen capture was blocked. You can upload a file instead.",
        @"notSupported": @"Screen capture isn't available here. You can upload a file instead.",
        @"failed": @"That didn't work. Please try again or upload a file.",
    };
}

- (instancetype)initWithLabels:(id)labels {
    self = [super init];
    if (self) {
        _labels = [labels isKindOfClass: [NSDictionary class]] ? [labels copy] : @{};
    }
    return self;
}

- (NSString *)text:(NSString *)key {
    id value = self.labels[key];
    if ([value isKindOfClass: [NSString class]]) {
        NSString *text = [(NSString *)value stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (text.length > 0) {
            return text.length > 300 ? [text substringToIndex: 300] : text;
        }
    }
    return [GleapCaptureLabels defaultLabels][key] ?: @"";
}

@end

#pragma mark - Window

/// The capture UI's own window: never key (the app's key window keeps the keyboard and the SDK's overlay),
/// transparent to touches outside its controls, and never part of a capture.
GLEAP_INTERNAL
@interface GleapCaptureWindow : UIWindow <GleapExcludedFromCapture>
@end

@implementation GleapCaptureWindow

- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest: point withEvent: event];
    if (hit == self || hit == self.rootViewController.view) {
        return nil;
    }
    return hit;
}

@end

#pragma mark - Host forwarding

/// Orientation and status bar follow the app underneath, so the overlay never changes them.
GLEAP_INTERNAL
@interface GleapCaptureHostForwardingViewController : UIViewController
@end

@implementation GleapCaptureHostForwardingViewController

- (UIViewController *)gleap_orientationHost {
    UIWindow *keyWindow = [GleapWindowChecker getKeyWindow];
    if (keyWindow == nil || keyWindow == self.view.window || [GleapCaptureRenderer isExcludedWindow: keyWindow]) {
        return nil;
    }
    UIViewController *controller = keyWindow.rootViewController;
    while (controller.presentedViewController != nil && !controller.presentedViewController.isBeingDismissed) {
        controller = controller.presentedViewController;
    }
    return controller;
}

- (UIViewController *)gleap_statusBarHost {
    UIViewController *host = [GleapUIHelper getTopMostViewController];
    if (host == nil || host.view.window == self.view.window) {
        return nil;
    }
    return host;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    UIViewController *host = [self gleap_orientationHost];
    return host != nil ? host.supportedInterfaceOrientations : UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotate {
    UIViewController *host = [self gleap_orientationHost];
    return host != nil ? host.shouldAutorotate : YES;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    UIViewController *host = [self gleap_statusBarHost];
    return host != nil ? host.preferredStatusBarStyle : UIStatusBarStyleDefault;
}

- (BOOL)prefersStatusBarHidden {
    UIViewController *host = [self gleap_statusBarHost];
    return host != nil ? host.prefersStatusBarHidden : NO;
}

@end

#pragma mark - Guard

// Taps, gestures and notifications of the capture UI: an exception is logged, never passed on to the app.
static void GleapCaptureGuarded(dispatch_block_t block) {
    @try {
        block();
    } @catch (NSException *exception) {
        NSLog(@"[GLEAP_SDK] The capture bar failed: %@", exception.reason);
    }
}

#pragma mark - Material

/// The dark rounded surface of the bar and its caption: a dark blur under a near-opaque fill, a white hairline and a
/// soft shadow. Content goes on top.
GLEAP_INTERNAL
@interface GleapCaptureSurfaceView : UIView
- (instancetype)initWithCornerRadius:(CGFloat)cornerRadius shadowOffset:(CGFloat)shadowOffset shadowBlur:(CGFloat)shadowBlur;
@end

@implementation GleapCaptureSurfaceView {
    CGFloat _cornerRadius;
    UIVisualEffectView *_blur;
    UIView *_fill;
}

- (instancetype)initWithCornerRadius:(CGFloat)cornerRadius shadowOffset:(CGFloat)shadowOffset shadowBlur:(CGFloat)shadowBlur {
    self = [super initWithFrame: CGRectZero];
    if (self) {
        _cornerRadius = cornerRadius;
        self.backgroundColor = [UIColor clearColor];
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.3;
        self.layer.shadowOffset = CGSizeMake(0, shadowOffset);
        // A CSS blur of 40 is a shadow radius of 20.
        self.layer.shadowRadius = shadowBlur / 2.0;

        _blur = [[UIVisualEffectView alloc] initWithEffect: [UIBlurEffect effectWithStyle: UIBlurEffectStyleSystemThickMaterialDark]];
        _blur.layer.cornerRadius = cornerRadius;
        _blur.layer.cornerCurve = kCACornerCurveContinuous;
        _blur.clipsToBounds = YES;
        _blur.userInteractionEnabled = NO;
        [self addSubview: _blur];

        _fill = [[UIView alloc] init];
        _fill.backgroundColor = GleapBarFillColor();
        _fill.layer.cornerRadius = cornerRadius;
        _fill.layer.cornerCurve = kCACornerCurveContinuous;
        _fill.layer.borderWidth = 1.0;
        _fill.layer.borderColor = GleapHairlineColor().CGColor;
        _fill.userInteractionEnabled = NO;
        [self addSubview: _fill];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _blur.frame = self.bounds;
    _fill.frame = self.bounds;
    [self sendSubviewToBack: _fill];
    [self sendSubviewToBack: _blur];
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect: self.bounds cornerRadius: _cornerRadius].CGPath;
}

@end

#pragma mark - Buttons

typedef NS_ENUM(NSInteger, GleapCaptureButtonStyle) {
    /// The widget color (or white), the main action.
    GleapCaptureButtonStylePrimary,
    /// White at 12 %.
    GleapCaptureButtonStyleSecondary,
    /// Red, Stop.
    GleapCaptureButtonStyleStop,
};

static UIFont *GleapCaptureButtonFont(void) {
    return [UIFont systemFontOfSize: 15 weight: UIFontWeightSemibold];
}

static UIImage *GleapCaptureSymbol(NSString *name, CGFloat pointSize) {
    return [UIImage systemImageNamed: name withConfiguration: [UIImageSymbolConfiguration configurationWithPointSize: pointSize weight: UIImageSymbolWeightBold]];
}

// Stop: a 12 pt square with softly rounded corners.
static UIImage *GleapCaptureStopGlyph(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize: CGSizeMake(12, 12)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        [[UIColor whiteColor] setFill];
        [[UIBezierPath bezierPathWithRoundedRect: CGRectMake(0, 0, 12, 12) cornerRadius: 2.5] fill];
    }];
    return [image imageWithRenderingMode: UIImageRenderingModeAlwaysTemplate];
}

/// A button whose touch target is at least 44 pt, however small it looks.
GLEAP_INTERNAL
@interface GleapCaptureButton : UIButton
@end

@implementation GleapCaptureButton

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGFloat dx = MAX(0, (kGleapMinimumHitSize - self.bounds.size.width) / 2.0);
    CGFloat dy = MAX(0, (kGleapMinimumHitSize - self.bounds.size.height) / 2.0);
    return CGRectContainsPoint(CGRectInset(self.bounds, -dx, -dy), point);
}

@end

/// A fully rounded button of the capture UI: a pill with a title, a circle without one. `imageTrailing` puts the image
/// after the title (it flips with the layout direction).
static UIButton *GleapCaptureMakeButton(GleapCaptureButtonStyle style, UIColor *accent, UIImage *image, NSString *title, CGFloat height, BOOL imageTrailing, void (^handler)(void)) {
    UIColor *fill;
    UIColor *pressedFill;
    UIColor *foreground;
    switch (style) {
        case GleapCaptureButtonStylePrimary:
            fill = accent ?: [UIColor whiteColor];
            pressedFill = [fill colorWithAlphaComponent: 0.82];
            foreground = accent != nil ? [GleapUIHelper contrastColorFrom: accent] : GleapCaptureColor(0x16161A, 1.0);
            break;
        case GleapCaptureButtonStyleStop:
            fill = GleapStopColor();
            pressedFill = [fill colorWithAlphaComponent: 0.82];
            foreground = [UIColor whiteColor];
            break;
        case GleapCaptureButtonStyleSecondary:
            fill = [UIColor colorWithWhite: 1.0 alpha: 0.12];
            pressedFill = [UIColor colorWithWhite: 1.0 alpha: 0.20];
            foreground = [UIColor whiteColor];
            break;
    }
    BOOL iconOnly = title.length == 0;
    UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
    configuration.baseForegroundColor = foreground;
    configuration.background.backgroundColor = fill;
    configuration.background.cornerRadius = height / 2.0;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleFixed;
    configuration.contentInsets = iconOnly ? NSDirectionalEdgeInsetsZero : NSDirectionalEdgeInsetsMake(0, 16, 0, 16);
    configuration.image = image;
    configuration.imagePadding = 6;
    configuration.imagePlacement = imageTrailing ? NSDirectionalRectEdgeTrailing : NSDirectionalRectEdgeLeading;
    if (!iconOnly) {
        configuration.title = title;
        configuration.titleLineBreakMode = NSLineBreakByTruncatingTail;
        configuration.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attributes) {
            NSMutableDictionary *updated = [attributes mutableCopy];
            updated[NSFontAttributeName] = GleapCaptureButtonFont();
            return updated;
        };
    }
    UIButton *button = [GleapCaptureButton buttonWithConfiguration: configuration primaryAction: [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        if (handler != nil) {
            GleapCaptureGuarded(handler);
        }
    }]];
    // Pressed: a lighter (or softer) fill; disabled: dimmed.
    button.configurationUpdateHandler = ^(__kindof UIButton * _Nonnull updatedButton) {
        UIButtonConfiguration *updated = updatedButton.configuration;
        BOOL enabled = updatedButton.isEnabled;
        updated.background.backgroundColor = updatedButton.isHighlighted ? pressedFill : (enabled ? fill : [fill colorWithAlphaComponent: CGColorGetAlpha(fill.CGColor) * 0.5]);
        updated.baseForegroundColor = enabled ? foreground : [foreground colorWithAlphaComponent: 0.5];
        updatedButton.configuration = updated;
    };
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.heightAnchor constraintEqualToConstant: height].active = YES;
    if (iconOnly) {
        [button.widthAnchor constraintEqualToConstant: height].active = YES;
    }
    [button setContentCompressionResistancePriority: UILayoutPriorityRequired forAxis: UILayoutConstraintAxisVertical];
    button.pointerInteractionEnabled = YES;
    // Fixed size in the bar: with large text, a long press shows the button enlarged.
    button.showsLargeContentViewer = YES;
    button.largeContentTitle = title;
    button.largeContentImage = image;
    button.scalesLargeContentImage = YES;
    return button;
}

static void GleapCaptureSetButtonTitle(UIButton *button, NSString *title) {
    UIButtonConfiguration *configuration = button.configuration;
    configuration.title = title;
    button.configuration = configuration;
    button.accessibilityLabel = title;
    button.largeContentTitle = title;
}

static void GleapCaptureSetButtonImage(UIButton *button, UIImage *image) {
    UIButtonConfiguration *configuration = button.configuration;
    configuration.image = image;
    button.configuration = configuration;
    button.largeContentImage = image;
}

// For a button without a title: what VoiceOver and the large content viewer say.
static void GleapCaptureSetButtonName(UIButton *button, NSString *name) {
    button.accessibilityLabel = name;
    button.largeContentTitle = name;
}

/// A spinner in place of the button's icon; the button keeps its width and ignores taps meanwhile.
static void GleapCaptureSetButtonBusy(UIButton *button, BOOL busy, NSLayoutConstraint * __strong *widthConstraint) {
    if (busy && *widthConstraint == nil && button.bounds.size.width > 0) {
        *widthConstraint = [button.widthAnchor constraintEqualToConstant: button.bounds.size.width];
        (*widthConstraint).active = YES;
    } else if (!busy && *widthConstraint != nil) {
        (*widthConstraint).active = NO;
        *widthConstraint = nil;
    }
    UIButtonConfiguration *configuration = button.configuration;
    configuration.showsActivityIndicator = busy;
    button.configuration = configuration;
    button.userInteractionEnabled = !busy;
    button.accessibilityTraits = busy ? (UIAccessibilityTraitButton | UIAccessibilityTraitNotEnabled) : UIAccessibilityTraitButton;
}

#pragma mark - Grip

/// Six dots on the leading edge of the bar: drag here (or anywhere on the bar but its buttons) to move it.
GLEAP_INTERNAL
@interface GleapCaptureGripView : UIView
@end

@implementation GleapCaptureGripView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame: frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentMode = UIViewContentModeRedraw;
        self.isAccessibilityElement = YES;
        // VoiceOver passes touches on the grip through, so the bar can be dragged with VoiceOver on.
        self.accessibilityTraits = UIAccessibilityTraitAllowsDirectInteraction;
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(26, kGleapBarContentHeight);
}

- (void)drawRect:(CGRect)rect {
    CGFloat dot = 3.0;
    CGFloat gap = 3.5;
    CGFloat width = dot * 2 + gap;
    CGFloat height = dot * 3 + gap * 2;
    CGFloat x = floor((self.bounds.size.width - width) / 2.0);
    CGFloat y = floor((self.bounds.size.height - height) / 2.0);
    [[UIColor colorWithWhite: 1.0 alpha: 0.45] setFill];
    for (NSInteger row = 0; row < 3; row++) {
        for (NSInteger column = 0; column < 2; column++) {
            [[UIBezierPath bezierPathWithOvalInRect: CGRectMake(x + column * (dot + gap), y + row * (dot + gap), dot, dot)] fill];
        }
    }
}

@end

#pragma mark - Caption

/// The instruction, briefly, in a small bubble next to the bar.
GLEAP_INTERNAL
@interface GleapCaptureCaptionView : GleapCaptureSurfaceView
@property (nonatomic, strong) UILabel *label;
@end

@implementation GleapCaptureCaptionView

- (instancetype)init {
    self = [super initWithCornerRadius: 12 shadowOffset: 8 shadowBlur: 24];
    if (self) {
        self.label = [[UILabel alloc] init];
        self.label.font = [UIFont systemFontOfSize: 13 weight: UIFontWeightRegular];
        self.label.textColor = [UIColor colorWithWhite: 1.0 alpha: 0.9];
        self.label.numberOfLines = 2;
        self.label.textAlignment = NSTextAlignmentCenter;
        self.label.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview: self.label];
        // Its text is the main button's VoiceOver hint already.
        self.isAccessibilityElement = NO;
        self.label.isAccessibilityElement = NO;
    }
    return self;
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGSize text = [self.label sizeThatFits: CGSizeMake(MAX(0, size.width - 24), CGFLOAT_MAX)];
    return CGSizeMake(MIN(size.width, ceil(text.width) + 24), ceil(text.height) + 14);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.label.frame = CGRectInset(self.bounds, 12, 7);
}

@end

#pragma mark - Bar

@protocol GleapCaptureBarActions <NSObject>
- (void)barDidTapPrimary;
- (void)barDidTapCancel;
- (void)barDidTapStop;
@end

typedef NS_ENUM(NSInteger, GleapCaptureCaptionState) {
    GleapCaptureCaptionStateNotShown,
    GleapCaptureCaptionStateShowing,
    GleapCaptureCaptionStateDismissed,
};

GLEAP_INTERNAL
@interface GleapCaptureBarViewController : GleapCaptureHostForwardingViewController <UIGestureRecognizerDelegate>
@property (nonatomic, strong) GleapCaptureLabels *labels;
/// The widget color; nil: white main buttons.
@property (nonatomic, strong, nullable) UIColor *accentColor;
@property (nonatomic, weak) id<GleapCaptureBarActions> actions;
/// What the bar shows: screenshot, record or recording (busy only puts a spinner into it).
@property (nonatomic, assign) GleapCaptureBarMode mode;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, strong) GleapCaptureSurfaceView *pill;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) GleapCaptureGripView *grip;
@property (nonatomic, strong) UIButton *primaryButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIView *recordingGroup;
@property (nonatomic, strong) UIView *dotView;
@property (nonatomic, strong) UILabel *timerLabel;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong, nullable) NSLayoutConstraint *busyWidthConstraint;
@property (nonatomic, strong) GleapCaptureCaptionView *caption;
@property (nonatomic, assign) GleapCaptureCaptionState captionState;
@property (nonatomic, assign) NSUInteger captionToken;
/// The docked keyboard in the view's coordinates; CGRectNull without one.
@property (nonatomic, assign) CGRect keyboardFrame;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, assign) CGPoint dragStartCenter;
/// Where the finger touched the bar: the bar moves with the finger from there, not from where the pan was recognized.
@property (nonatomic, assign) CGPoint touchDownLocation;
@property (nonatomic, assign) BOOL hasAppeared;
@property (nonatomic, assign) BOOL barHidden;
@property (nonatomic, assign) CGSize lastLayoutSize;
@end

@implementation GleapCaptureBarViewController

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    self.keyboardFrame = CGRectNull;
    __weak typeof(self) weakSelf = self;

    self.pill = [[GleapCaptureSurfaceView alloc] initWithCornerRadius: (kGleapBarContentHeight + kGleapBarVerticalPadding * 2) / 2.0 shadowOffset: 12 shadowBlur: 40];
    self.pill.alpha = 0;
    [self.view addSubview: self.pill];

    self.grip = [[GleapCaptureGripView alloc] init];
    self.grip.accessibilityLabel = [self.labels text: @"barDragHint"];
    [self.grip setContentHuggingPriority: UILayoutPriorityRequired forAxis: UILayoutConstraintAxisHorizontal];
    [self.grip setContentCompressionResistancePriority: UILayoutPriorityRequired forAxis: UILayoutConstraintAxisHorizontal];

    self.primaryButton = GleapCaptureMakeButton(GleapCaptureButtonStylePrimary, self.accentColor, GleapCaptureSymbol(@"camera.fill", 13), [self.labels text: @"barCapture"], kGleapButtonHeight, NO, ^{
        [weakSelf barButtonTapped: weakSelf.primaryButton];
    });
    // A long title gives way first (it is cut off at the screen's width).
    [self.primaryButton setContentCompressionResistancePriority: UILayoutPriorityDefaultLow forAxis: UILayoutConstraintAxisHorizontal];

    self.closeButton = GleapCaptureMakeButton(GleapCaptureButtonStyleSecondary, nil, GleapCaptureSymbol(@"xmark", 14), nil, kGleapButtonHeight, NO, ^{
        [weakSelf barButtonTapped: weakSelf.closeButton];
    });
    GleapCaptureSetButtonName(self.closeButton, [self.labels text: @"barCancel"]);

    // Recording: a pulsing red dot and "mm:ss / mm:ss".
    self.dotView = [[UIView alloc] init];
    self.dotView.translatesAutoresizingMaskIntoConstraints = NO;
    self.dotView.backgroundColor = GleapCaptureColor(0xFF4D4F, 1.0);
    self.dotView.layer.cornerRadius = 5;
    self.timerLabel = [[UILabel alloc] init];
    self.timerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.timerLabel.font = [UIFont monospacedDigitSystemFontOfSize: 15 weight: UIFontWeightSemibold];
    self.timerLabel.textColor = [UIColor colorWithWhite: 1.0 alpha: 0.85];
    self.timerLabel.text = @"00:00 / 00:00";
    [self.timerLabel setContentCompressionResistancePriority: UILayoutPriorityRequired forAxis: UILayoutConstraintAxisHorizontal];
    self.recordingGroup = [[UIView alloc] init];
    self.recordingGroup.isAccessibilityElement = YES;
    self.recordingGroup.accessibilityTraits = UIAccessibilityTraitStaticText | UIAccessibilityTraitUpdatesFrequently;
    [self.recordingGroup addSubview: self.dotView];
    [self.recordingGroup addSubview: self.timerLabel];
    [NSLayoutConstraint activateConstraints: @[
        [self.dotView.widthAnchor constraintEqualToConstant: 10],
        [self.dotView.heightAnchor constraintEqualToConstant: 10],
        [self.dotView.leadingAnchor constraintEqualToAnchor: self.recordingGroup.leadingAnchor constant: 4],
        [self.dotView.centerYAnchor constraintEqualToAnchor: self.recordingGroup.centerYAnchor],
        [self.timerLabel.leadingAnchor constraintEqualToAnchor: self.dotView.trailingAnchor constant: 8],
        [self.timerLabel.trailingAnchor constraintEqualToAnchor: self.recordingGroup.trailingAnchor constant: -6],
        [self.timerLabel.centerYAnchor constraintEqualToAnchor: self.recordingGroup.centerYAnchor],
        [self.recordingGroup.heightAnchor constraintEqualToConstant: kGleapBarContentHeight],
    ]];

    // Stop: a red circle with a rounded square.
    self.stopButton = GleapCaptureMakeButton(GleapCaptureButtonStyleStop, nil, GleapCaptureStopGlyph(), nil, kGleapButtonHeight, NO, ^{
        [weakSelf barButtonTapped: weakSelf.stopButton];
    });
    GleapCaptureSetButtonName(self.stopButton, [self.labels text: @"barStop"]);

    self.stack = [[UIStackView alloc] initWithArrangedSubviews: @[self.grip, self.primaryButton, self.recordingGroup, self.stopButton, self.closeButton]];
    self.stack.axis = UILayoutConstraintAxisHorizontal;
    self.stack.alignment = UIStackViewAlignmentCenter;
    self.stack.spacing = kGleapBarSpacing;
    [self.stack setCustomSpacing: 2 afterView: self.grip];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pill addSubview: self.stack];
    [NSLayoutConstraint activateConstraints: @[
        [self.stack.leadingAnchor constraintEqualToAnchor: self.pill.leadingAnchor constant: kGleapBarHorizontalPadding],
        [self.stack.trailingAnchor constraintEqualToAnchor: self.pill.trailingAnchor constant: -kGleapBarHorizontalPadding],
        [self.stack.topAnchor constraintEqualToAnchor: self.pill.topAnchor constant: kGleapBarVerticalPadding],
        [self.stack.bottomAnchor constraintEqualToAnchor: self.pill.bottomAnchor constant: -kGleapBarVerticalPadding],
        [self.grip.heightAnchor constraintEqualToConstant: kGleapBarContentHeight],
    ]];

    // Dragged from the grip or anywhere on the bar but its buttons.
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget: self action: @selector(handlePan:)];
    pan.delegate = self;
    pan.maximumNumberOfTouches = 1;
    [self.pill addGestureRecognizer: pan];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget: self action: @selector(handleBarTap:)];
    tap.delegate = self;
    [self.pill addGestureRecognizer: tap];
    [self.pill addInteraction: [[UILargeContentViewerInteraction alloc] init]];

    self.caption = [[GleapCaptureCaptionView alloc] init];
    self.caption.alpha = 0;
    self.caption.hidden = YES;
    [self.caption addGestureRecognizer: [[UITapGestureRecognizer alloc] initWithTarget: self action: @selector(handleBarTap:)]];
    [self.view addSubview: self.caption];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver: self selector: @selector(keyboardWillChangeFrame:) name: UIKeyboardWillChangeFrameNotification object: nil];
    [center addObserver: self selector: @selector(keyboardWillHide:) name: UIKeyboardWillHideNotification object: nil];

    [self applyMode: self.mode];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Rotation, a resized window, new safe areas: back into the bounds, at the remembered place.
    if (!CGSizeEqualToSize(self.lastLayoutSize, self.view.bounds.size)) {
        self.lastLayoutSize = self.view.bounds.size;
        [self layoutBar];
    }
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self layoutBar];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize: size withTransitionCoordinator: coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        GleapCaptureGuarded(^{
            [self layoutBar];
        });
    } completion: nil];
}

#pragma mark Modes

- (void)applyMode:(GleapCaptureBarMode)mode {
    if (mode == GleapCaptureBarModeBusy) {
        self.busy = YES;
    } else {
        self.mode = mode;
        self.busy = NO;
    }
    if (!self.isViewLoaded) {
        return;
    }
    GleapCaptureBarMode shown = self.mode;
    BOOL recording = shown == GleapCaptureBarModeRecording;
    self.primaryButton.hidden = recording;
    self.closeButton.hidden = recording;
    self.recordingGroup.hidden = !recording;
    self.stopButton.hidden = !recording;

    if (shown == GleapCaptureBarModeScreenshot) {
        GleapCaptureSetButtonTitle(self.primaryButton, [self.labels text: @"barCapture"]);
        GleapCaptureSetButtonImage(self.primaryButton, GleapCaptureSymbol(@"camera.fill", 13));
        self.primaryButton.accessibilityHint = [self.labels text: @"barScreenshotHint"];
    } else if (shown == GleapCaptureBarModeRecordReady) {
        GleapCaptureSetButtonTitle(self.primaryButton, [self.labels text: @"barStart"]);
        GleapCaptureSetButtonImage(self.primaryButton, GleapCaptureSymbol(@"record.circle", 13));
        self.primaryButton.accessibilityHint = [self.labels text: @"barRecordHint"];
    }

    // Only the button of the bar on screen waits while busy; the others are back to normal.
    NSLayoutConstraint *width = self.busyWidthConstraint;
    UIButton *busyButton = recording ? self.stopButton : self.primaryButton;
    UIButton *idleButton = recording ? self.primaryButton : self.stopButton;
    GleapCaptureSetButtonBusy(idleButton, NO, &width);
    GleapCaptureSetButtonBusy(busyButton, self.busy, &width);
    self.busyWidthConstraint = width;

    if (recording) {
        [self startPulsing];
        [self dismissCaption];
    } else {
        [self.dotView.layer removeAllAnimations];
    }
    // The order VoiceOver reads: the main action first, the grip last.
    self.pill.accessibilityElements = recording ? @[self.recordingGroup, self.stopButton, self.grip] : @[self.primaryButton, self.closeButton, self.grip];

    if (self.hasAppeared && !self.busy) {
        [UIView animateWithDuration: UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.3 delay: 0 usingSpringWithDamping: 0.9 initialSpringVelocity: 0 options: UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            [self layoutBar];
            [self.pill layoutIfNeeded];
        } completion: nil];
        [self announceMode];
    } else {
        [self layoutBar];
    }
}

- (void)startPulsing {
    [self.dotView.layer removeAllAnimations];
    if (UIAccessibilityIsReduceMotionEnabled()) {
        return;
    }
    // Clearly red most of the time, with a short dip to 40 %.
    CAKeyframeAnimation *pulse = [CAKeyframeAnimation animationWithKeyPath: @"opacity"];
    pulse.values = @[@1.0, @1.0, @0.4, @1.0];
    pulse.keyTimes = @[@0.0, @0.45, @0.72, @1.0];
    CAMediaTimingFunction *easing = [CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionEaseInEaseOut];
    pulse.timingFunctions = @[easing, easing, easing];
    pulse.duration = 1.4;
    pulse.repeatCount = HUGE_VALF;
    [self.dotView.layer addAnimation: pulse forKey: @"pulse"];
}

// VoiceOver: the instruction when the bar asks for something (it is the main button's hint too), the recording state
// once recording.
- (void)announceMode {
    if (self.barHidden) {
        return;
    }
    if (self.mode == GleapCaptureBarModeRecording) {
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self.recordingGroup);
    } else {
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self.primaryButton.accessibilityHint);
    }
}

- (void)updateElapsed:(NSTimeInterval)elapsed maxDuration:(NSTimeInterval)maxDuration {
    NSString *time = [NSString stringWithFormat: @"%@ / %@", [GleapCaptureOverlay formattedTime: elapsed], [GleapCaptureOverlay formattedTime: maxDuration]];
    BOOL grows = self.timerLabel.text.length != time.length;
    self.timerLabel.text = time;
    self.recordingGroup.accessibilityLabel = [NSString stringWithFormat: @"%@, %@", [self.labels text: @"barRecording"], time];
    if (grows && self.isViewLoaded) {
        [self layoutBar];
    }
}

- (void)barButtonTapped:(UIButton *)button {
    [self dismissCaption];
    if (button == self.primaryButton) {
        [self.actions barDidTapPrimary];
    } else if (button == self.closeButton) {
        [self.actions barDidTapCancel];
    } else if (button == self.stopButton) {
        [self.actions barDidTapStop];
    }
}

#pragma mark Showing and hiding

- (void)setBarHidden:(BOOL)hidden animated:(BOOL)animated completion:(void (^)(void))completion {
    [self loadViewIfNeeded];
    [self.view layoutIfNeeded];
    self.barHidden = hidden;
    BOOL firstShow = !hidden && !self.hasAppeared;
    if (!hidden) {
        self.hasAppeared = YES;
    }
    [self layoutBar];
    if (hidden) {
        [self dismissCaption];
    }
    if (firstShow) {
        self.pill.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0, 12), 0.96, 0.96);
    }
    void (^changes)(void) = ^{
        self.pill.alpha = hidden ? 0.0 : 1.0;
        self.pill.transform = CGAffineTransformIdentity;
    };
    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration: hidden ? 0.15 : 0.35 delay: 0 usingSpringWithDamping: 0.85 initialSpringVelocity: 0 options: UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations: changes completion:^(BOOL finished) {
            if (completion) {
                completion();
            }
        }];
    } else {
        changes();
        if (completion) {
            completion();
        }
    }
    if (firstShow) {
        [self showCaption];
        [self announceMode];
    }
}

#pragma mark Caption

// The instruction shows above (or below) the bar for a few seconds, once, and goes with the first drag or tap.
- (void)showCaption {
    if (self.captionState != GleapCaptureCaptionStateNotShown || self.mode == GleapCaptureBarModeRecording) {
        return;
    }
    NSString *text = self.primaryButton.accessibilityHint;
    if (text.length == 0) {
        return;
    }
    self.captionState = GleapCaptureCaptionStateShowing;
    self.caption.label.text = text;
    self.caption.hidden = NO;
    [self layoutCaption];
    [UIView animateWithDuration: UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.25 delay: 0.1 options: UIViewAnimationOptionAllowUserInteraction animations:^{
        self.caption.alpha = 1.0;
    } completion: nil];
    NSUInteger token = ++self.captionToken;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kGleapCaptionDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        GleapCaptureGuarded(^{
            if (weakSelf.captionToken == token) {
                [weakSelf dismissCaption];
            }
        });
    });
}

- (void)dismissCaption {
    if (self.captionState != GleapCaptureCaptionStateShowing) {
        if (self.captionState == GleapCaptureCaptionStateNotShown) {
            self.captionState = GleapCaptureCaptionStateDismissed;
        }
        return;
    }
    self.captionState = GleapCaptureCaptionStateDismissed;
    [UIView animateWithDuration: UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.3 delay: 0 options: UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.caption.alpha = 0;
    } completion:^(BOOL finished) {
        if (self.captionState == GleapCaptureCaptionStateDismissed) {
            self.caption.hidden = YES;
        }
    }];
}

- (void)layoutCaption {
    if (self.caption.hidden) {
        return;
    }
    CGRect area = [self movableFrameAvoidingKeyboard: YES];
    CGSize size = [self.caption sizeThatFits: CGSizeMake(MIN(kGleapCaptionMaxWidth, area.size.width), CGFLOAT_MAX)];
    CGRect pill = self.pill.frame;
    CGFloat x = MIN(MAX(CGRectGetMidX(pill) - size.width / 2.0, CGRectGetMinX(area)), CGRectGetMaxX(area) - size.width);
    CGFloat above = CGRectGetMinY(pill) - 8 - size.height;
    CGFloat y = above >= CGRectGetMinY(area) ? above : CGRectGetMaxY(pill) + 8;
    self.caption.frame = CGRectMake(round(x), round(y), size.width, size.height);
}

#pragma mark Position

- (CGRect)safeFrame {
    return UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
}

// Where the bar may be: the safe area less 8 pt, above a docked keyboard if asked to.
- (CGRect)movableFrameAvoidingKeyboard:(BOOL)avoidKeyboard {
    CGRect frame = CGRectInset([self safeFrame], kGleapBarEdgeMargin, kGleapBarEdgeMargin);
    if (avoidKeyboard && !CGRectIsNull(self.keyboardFrame)) {
        CGFloat limit = CGRectGetMinY(self.keyboardFrame) - kGleapBarEdgeMargin;
        if (limit < CGRectGetMaxY(frame)) {
            frame.size.height = MAX(0, limit - CGRectGetMinY(frame));
        }
    }
    return frame;
}

- (CGSize)barSize {
    CGSize content = [self.stack systemLayoutSizeFittingSize: UILayoutFittingCompressedSize];
    CGFloat width = ceil(content.width) + kGleapBarHorizontalPadding * 2;
    CGFloat maxWidth = MIN(self.view.bounds.size.width - kGleapBarScreenMargin * 2, [self movableFrameAvoidingKeyboard: NO].size.width);
    return CGSizeMake(MAX(0, MIN(width, maxWidth)), kGleapBarContentHeight + kGleapBarVerticalPadding * 2);
}

static CGPoint GleapClampedCenter(CGPoint center, CGSize size, CGRect frame) {
    CGFloat minX = CGRectGetMinX(frame) + size.width / 2.0;
    CGFloat maxX = CGRectGetMaxX(frame) - size.width / 2.0;
    CGFloat minY = CGRectGetMinY(frame) + size.height / 2.0;
    CGFloat maxY = CGRectGetMaxY(frame) - size.height / 2.0;
    return CGPointMake(maxX < minX ? CGRectGetMidX(frame) : MIN(MAX(center.x, minX), maxX),
                       maxY < minY ? CGRectGetMidY(frame) : MIN(MAX(center.y, minY), maxY));
}

// The bar's center as a point in `frame`, 0…1 on both axes (0.5 where it cannot move).
static CGPoint GleapNormalizedPosition(CGPoint center, CGSize size, CGRect frame) {
    CGFloat rangeX = frame.size.width - size.width;
    CGFloat rangeY = frame.size.height - size.height;
    CGFloat x = rangeX > 0.5 ? (center.x - CGRectGetMinX(frame) - size.width / 2.0) / rangeX : 0.5;
    CGFloat y = rangeY > 0.5 ? (center.y - CGRectGetMinY(frame) - size.height / 2.0) / rangeY : 0.5;
    return CGPointMake(MIN(MAX(x, 0), 1), MIN(MAX(y, 0), 1));
}

static CGPoint GleapCenterForNormalizedPosition(CGPoint position, CGSize size, CGRect frame) {
    CGFloat rangeX = MAX(0, frame.size.width - size.width);
    CGFloat rangeY = MAX(0, frame.size.height - size.height);
    return CGPointMake(CGRectGetMinX(frame) + size.width / 2.0 + position.x * rangeX, CGRectGetMinY(frame) + size.height / 2.0 + position.y * rangeY);
}

// Where the bar rests: where the customer left it (kept as a point in the safe area), else bottom center 16 pt above
// the safe area; above the keyboard either way.
- (CGPoint)restingCenterForSize:(CGSize)size {
    CGPoint center;
    if (gleapBarHasPosition) {
        center = GleapCenterForNormalizedPosition(gleapBarPosition, size, [self movableFrameAvoidingKeyboard: NO]);
    } else {
        CGRect safe = [self safeFrame];
        CGFloat bottom = CGRectGetMaxY(safe);
        if (!CGRectIsNull(self.keyboardFrame)) {
            bottom = MIN(bottom, CGRectGetMinY(self.keyboardFrame));
        }
        center = CGPointMake(CGRectGetMidX(safe), bottom - kGleapBarScreenMargin - size.height / 2.0);
    }
    return GleapClampedCenter(center, size, [self movableFrameAvoidingKeyboard: YES]);
}

// On whole pixels, so the bar never renders blurred between them.
- (CGPoint)pixelAlignedCenter:(CGPoint)center size:(CGSize)size {
    CGFloat scale = self.view.window.screen.scale ?: UIScreen.mainScreen.scale;
    CGFloat x = round((center.x - size.width / 2.0) * scale) / scale;
    CGFloat y = round((center.y - size.height / 2.0) * scale) / scale;
    return CGPointMake(x + size.width / 2.0, y + size.height / 2.0);
}

- (void)layoutBar {
    if (!self.isViewLoaded || self.dragging || CGRectIsEmpty(self.view.bounds)) {
        return;
    }
    CGSize size = [self barSize];
    self.pill.bounds = CGRectMake(0, 0, size.width, size.height);
    self.pill.center = [self pixelAlignedCenter: [self restingCenterForSize: size] size: size];
    [self layoutCaption];
}

#pragma mark Dragging

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    // The buttons keep their touches.
    for (UIView *view = touch.view; view != nil && view != self.pill; view = view.superview) {
        if ([view isKindOfClass: [UIControl class]]) {
            return NO;
        }
    }
    self.touchDownLocation = [touch locationInView: self.view];
    return YES;
}

- (void)handleBarTap:(UITapGestureRecognizer *)tap {
    GleapCaptureGuarded(^{
        [self dismissCaption];
    });
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    GleapCaptureGuarded(^{
        switch (pan.state) {
            case UIGestureRecognizerStateBegan:
                [self beginDrag];
                [self dragBy: [self translationOfPan: pan]];
                break;
            case UIGestureRecognizerStateChanged:
                [self dragBy: [self translationOfPan: pan]];
                break;
            case UIGestureRecognizerStateEnded:
            case UIGestureRecognizerStateCancelled:
            case UIGestureRecognizerStateFailed:
                [self endDragWithVelocity: [pan velocityInView: self.view]];
                break;
            default:
                break;
        }
    });
}

// From the touch-down point: the pan's own translation starts only once the finger has moved a little (or far, when
// fast), and the bar would trail the finger by that much.
- (CGPoint)translationOfPan:(UIPanGestureRecognizer *)pan {
    CGPoint location = [pan locationInView: self.view];
    return CGPointMake(location.x - self.touchDownLocation.x, location.y - self.touchDownLocation.y);
}

- (void)beginDrag {
    [self dismissCaption];
    [self.pill.layer removeAllAnimations];
    self.dragging = YES;
    self.dragStartCenter = self.pill.center;
}

// 1:1 with the finger.
- (void)dragBy:(CGPoint)translation {
    if (!self.dragging) {
        return;
    }
    self.pill.center = CGPointMake(self.dragStartCenter.x + translation.x, self.dragStartCenter.y + translation.y);
}

// Springs back into the safe area (8 pt in), to the horizontal center when close to it, and stays there for the next
// captures of this run.
- (void)endDragWithVelocity:(CGPoint)velocity {
    if (!self.dragging) {
        return;
    }
    self.dragging = NO;
    CGSize size = self.pill.bounds.size;
    CGPoint target = GleapClampedCenter(self.pill.center, size, [self movableFrameAvoidingKeyboard: YES]);
    CGFloat middle = CGRectGetMidX([self safeFrame]);
    if (fabs(target.x - middle) <= kGleapBarSnapDistance) {
        target.x = middle;
    }
    gleapBarPosition = GleapNormalizedPosition(target, size, [self movableFrameAvoidingKeyboard: NO]);
    gleapBarHasPosition = YES;
    target = [self pixelAlignedCenter: target size: size];

    CGFloat distance = hypot(target.x - self.pill.center.x, target.y - self.pill.center.y);
    CGFloat speed = hypot(velocity.x, velocity.y);
    CGFloat relativeVelocity = distance > 1 ? MIN(speed / distance, 12) : 0;
    [UIView animateWithDuration: UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.45 delay: 0 usingSpringWithDamping: 0.82 initialSpringVelocity: relativeVelocity options: UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.pill.center = target;
    } completion: nil];
}

#pragma mark Keyboard

- (void)keyboardWillChangeFrame:(NSNotification *)notification {
    GleapCaptureGuarded(^{
        CGRect endFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
        UIScreen *screen = self.view.window.windowScene.screen ?: UIScreen.mainScreen;
        CGRect keyboard = [self.view convertRect: endFrame fromCoordinateSpace: screen.coordinateSpace];
        CGRect overlap = CGRectIntersection(keyboard, self.view.bounds);
        // Only a keyboard docked at the bottom moves the bar (a floating or split one does not).
        BOOL docked = !CGRectIsNull(overlap) && !CGRectIsEmpty(overlap) && CGRectGetMaxY(keyboard) >= CGRectGetMaxY(self.view.bounds) - 1;
        self.keyboardFrame = docked ? keyboard : CGRectNull;
        [self followKeyboardWithNotification: notification];
    });
}

- (void)keyboardWillHide:(NSNotification *)notification {
    GleapCaptureGuarded(^{
        self.keyboardFrame = CGRectNull;
        [self followKeyboardWithNotification: notification];
    });
}

- (void)followKeyboardWithNotification:(NSNotification *)notification {
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions curve = (UIViewAnimationOptions)([notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16);
    [UIView animateWithDuration: duration delay: 0 options: curve | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        [self layoutBar];
    } completion: nil];
}

@end

#pragma mark - Preview

/// The recording: an AVPlayerLayer with rounded corners and a centered play glyph while paused; a tap plays or
/// pauses. No AVKit, so no full screen, AirPlay, picture in picture or Now Playing entry, and nothing that could
/// dismiss the preview.
GLEAP_INTERNAL
@interface GleapCapturePlayerView : UIView
@property (nonatomic, strong, nullable) AVPlayer *player;
@property (nonatomic, strong, nullable) id timeObserver;
@property (nonatomic, assign) BOOL reachedEnd;
@property (nonatomic, assign) BOOL scrubbing;
@property (nonatomic, assign) BOOL wasPlayingBeforeScrub;
@property (nonatomic, strong) UIView *glyph;
@property (nonatomic, assign) BOOL interactionDisabled;
/// What VoiceOver calls a tap: play or pause (capture-start labels).
@property (nonatomic, copy) NSString *playLabel;
@property (nonatomic, copy) NSString *pauseLabel;
/// Where playback is, 0…1 (main queue, often).
@property (nonatomic, copy, nullable) void (^onProgress)(double fraction);
- (instancetype)initWithFileURL:(NSURL *)fileURL;
- (void)play;
- (void)pause;
- (void)beginScrubbing;
- (void)scrubToFraction:(double)fraction;
- (void)endScrubbing;
- (void)releasePlayer;
@end

@implementation GleapCapturePlayerView

+ (Class)layerClass {
    return [AVPlayerLayer class];
}

- (instancetype)initWithFileURL:(NSURL *)fileURL {
    self = [super initWithFrame: CGRectZero];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.layer.cornerRadius = 12;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1;
        self.layer.borderColor = GleapHairlineColor().CGColor;

        AVPlayer *player = [AVPlayer playerWithURL: fileURL];
        player.muted = YES;
        player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
        player.preventsDisplaySleepDuringVideoPlayback = NO;
        self.player = player;
        AVPlayerLayer *playerLayer = (AVPlayerLayer *)self.layer;
        playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        playerLayer.player = player;

        // A centered play glyph while paused.
        self.glyph = [[UIView alloc] init];
        self.glyph.translatesAutoresizingMaskIntoConstraints = NO;
        self.glyph.backgroundColor = [UIColor colorWithWhite: 0 alpha: 0.45];
        self.glyph.layer.cornerRadius = 28;
        self.glyph.userInteractionEnabled = NO;
        UIImageView *glyphImage = [[UIImageView alloc] initWithImage: [UIImage systemImageNamed: @"play.fill" withConfiguration: [UIImageSymbolConfiguration configurationWithPointSize: 22 weight: UIImageSymbolWeightBold]]];
        glyphImage.translatesAutoresizingMaskIntoConstraints = NO;
        glyphImage.tintColor = [UIColor whiteColor];
        glyphImage.isAccessibilityElement = NO;
        [self.glyph addSubview: glyphImage];
        [self addSubview: self.glyph];
        [NSLayoutConstraint activateConstraints: @[
            [self.glyph.centerXAnchor constraintEqualToAnchor: self.centerXAnchor],
            [self.glyph.centerYAnchor constraintEqualToAnchor: self.centerYAnchor],
            [self.glyph.widthAnchor constraintEqualToConstant: 56],
            [self.glyph.heightAnchor constraintEqualToConstant: 56],
            // The triangle's visual center is right of its box center.
            [glyphImage.centerXAnchor constraintEqualToAnchor: self.glyph.centerXAnchor constant: 2],
            [glyphImage.centerYAnchor constraintEqualToAnchor: self.glyph.centerYAnchor],
        ]];

        __weak typeof(self) weakSelf = self;
        self.timeObserver = [player addPeriodicTimeObserverForInterval: CMTimeMake(1, 20) queue: dispatch_get_main_queue() usingBlock:^(CMTime time) {
            GleapCaptureGuarded(^{
                [weakSelf updatePlaybackState];
            });
        }];
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(playerDidReachEnd:) name: AVPlayerItemDidPlayToEndTimeNotification object: player.currentItem];
        [self addGestureRecognizer: [[UITapGestureRecognizer alloc] initWithTarget: self action: @selector(handleTap:)]];

        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton | UIAccessibilityTraitAdjustable | UIAccessibilityTraitStartsMediaSession;
        [self updatePlaybackState];
    }
    return self;
}

- (void)dealloc {
    [self releasePlayer];
}

- (void)releasePlayer {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    if (self.timeObserver != nil) {
        [self.player removeTimeObserver: self.timeObserver];
        self.timeObserver = nil;
    }
    [self.player pause];
    [self.player replaceCurrentItemWithPlayerItem: nil];
    ((AVPlayerLayer *)self.layer).player = nil;
    self.player = nil;
}

- (void)setInteractionDisabled:(BOOL)interactionDisabled {
    _interactionDisabled = interactionDisabled;
    self.userInteractionEnabled = !interactionDisabled;
    self.accessibilityTraits = interactionDisabled ? UIAccessibilityTraitNotEnabled : (UIAccessibilityTraitButton | UIAccessibilityTraitAdjustable | UIAccessibilityTraitStartsMediaSession);
}

- (double)duration {
    CMTime duration = self.player.currentItem.duration;
    return CMTIME_IS_NUMERIC(duration) ? CMTimeGetSeconds(duration) : 0;
}

- (double)fraction {
    double total = [self duration];
    return total > 0 ? MIN(1.0, MAX(0.0, CMTimeGetSeconds(self.player.currentTime) / total)) : 0;
}

- (BOOL)isPlaying {
    return self.player.rate > 0;
}

- (void)play {
    if (self.player == nil) {
        return;
    }
    if (self.reachedEnd) {
        self.reachedEnd = NO;
        [self.player seekToTime: kCMTimeZero];
    }
    [self.player play];
    [self updatePlaybackState];
}

- (void)pause {
    [self.player pause];
    [self updatePlaybackState];
}

- (void)togglePlayback {
    if ([self isPlaying]) {
        [self pause];
    } else {
        [self play];
    }
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    GleapCaptureGuarded(^{
        [self togglePlayback];
    });
}

- (void)beginScrubbing {
    if (self.scrubbing) {
        return;
    }
    self.wasPlayingBeforeScrub = [self isPlaying];
    self.scrubbing = YES;
    [self.player pause];
    [self updatePlaybackState];
}

- (void)scrubToFraction:(double)fraction {
    double total = [self duration];
    if (total <= 0) {
        return;
    }
    fraction = MIN(1.0, MAX(0.0, fraction));
    self.reachedEnd = fraction >= 1.0;
    [self.player seekToTime: CMTimeMakeWithSeconds(total * fraction, 600) toleranceBefore: kCMTimeZero toleranceAfter: kCMTimeZero];
    if (self.onProgress) {
        self.onProgress(fraction);
    }
}

- (void)endScrubbing {
    if (!self.scrubbing) {
        return;
    }
    self.scrubbing = NO;
    if (self.wasPlayingBeforeScrub && !self.reachedEnd) {
        [self.player play];
    }
    [self updatePlaybackState];
}

- (void)playerDidReachEnd:(NSNotification *)notification {
    GleapCaptureGuarded(^{
        self.reachedEnd = YES;
        [self updatePlaybackState];
    });
}

- (void)updatePlaybackState {
    CGFloat glyphAlpha = [self isPlaying] || self.scrubbing ? 0.0 : 1.0;
    if (self.glyph.alpha != glyphAlpha) {
        [UIView animateWithDuration: 0.2 animations:^{
            self.glyph.alpha = glyphAlpha;
        }];
    }
    if (self.onProgress && !self.scrubbing) {
        self.onProgress([self fraction]);
    }
}

// VoiceOver: what a tap does, and where playback is.
- (NSString *)accessibilityLabel {
    return [self isPlaying] ? self.pauseLabel : self.playLabel;
}

- (NSString *)accessibilityValue {
    return [NSString stringWithFormat: @"%@ / %@", [GleapCaptureOverlay formattedTime: CMTimeGetSeconds(self.player.currentTime)], [GleapCaptureOverlay formattedTime: [self duration]]];
}

- (BOOL)accessibilityActivate {
    [self togglePlayback];
    return YES;
}

- (void)accessibilityIncrement {
    [self seekBySeconds: 5];
}

- (void)accessibilityDecrement {
    [self seekBySeconds: -5];
}

- (void)seekBySeconds:(double)seconds {
    double total = [self duration];
    if (total > 0) {
        [self scrubToFraction: (CMTimeGetSeconds(self.player.currentTime) + seconds) / total];
        [self updatePlaybackState];
    }
}

@end

/// A thin line under the video: where playback is; tap or drag to move there.
GLEAP_INTERNAL
@interface GleapCaptureScrubberView : UIView
@property (nonatomic, strong) UIView *track;
@property (nonatomic, strong) UIView *progress;
@property (nonatomic, assign) double fraction;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, copy, nullable) void (^onBegin)(void);
@property (nonatomic, copy, nullable) void (^onScrub)(double fraction);
@property (nonatomic, copy, nullable) void (^onEnd)(void);
@end

@implementation GleapCaptureScrubberView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame: frame];
    if (self) {
        self.track = [[UIView alloc] init];
        self.track.backgroundColor = [UIColor colorWithWhite: 1.0 alpha: 0.2];
        self.track.userInteractionEnabled = NO;
        self.progress = [[UIView alloc] init];
        self.progress.backgroundColor = [UIColor colorWithWhite: 1.0 alpha: 0.9];
        self.progress.userInteractionEnabled = NO;
        [self addSubview: self.track];
        [self addSubview: self.progress];
        [self addGestureRecognizer: [[UIPanGestureRecognizer alloc] initWithTarget: self action: @selector(handleGesture:)]];
        [self addGestureRecognizer: [[UITapGestureRecognizer alloc] initWithTarget: self action: @selector(handleGesture:)]];
        // The video itself is the VoiceOver control (adjustable).
        self.isAccessibilityElement = NO;
    }
    return self;
}

- (void)setFraction:(double)fraction {
    _fraction = MIN(1.0, MAX(0.0, fraction));
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = self.active ? 5 : 3;
    CGRect track = CGRectMake(0, round((self.bounds.size.height - height) / 2.0), self.bounds.size.width, height);
    self.track.frame = track;
    self.track.layer.cornerRadius = height / 2.0;
    self.progress.frame = CGRectMake(0, track.origin.y, track.size.width * self.fraction, height);
    self.progress.layer.cornerRadius = height / 2.0;
}

- (void)handleGesture:(UIGestureRecognizer *)gesture {
    GleapCaptureGuarded(^{
        BOOL tap = [gesture isKindOfClass: [UITapGestureRecognizer class]];
        UIGestureRecognizerState state = gesture.state;
        if (state == UIGestureRecognizerStateBegan || (tap && state == UIGestureRecognizerStateEnded)) {
            self.active = YES;
            if (self.onBegin) {
                self.onBegin();
            }
        }
        double fraction = self.bounds.size.width > 0 ? [gesture locationInView: self].x / self.bounds.size.width : 0;
        self.fraction = fraction;
        if (self.onScrub) {
            self.onScrub(self.fraction);
        }
        if (state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled || state == UIGestureRecognizerStateFailed) {
            self.active = NO;
            if (self.onEnd) {
                self.onEnd();
            }
        }
        [UIView animateWithDuration: 0.15 animations:^{
            [self layoutIfNeeded];
        }];
    });
}

@end

GLEAP_INTERNAL
@interface GleapCapturePreviewViewController : GleapCaptureHostForwardingViewController
@property (nonatomic, strong) NSURL *fileURL;
/// Pixels; the frame on screen keeps its aspect ratio.
@property (nonatomic, assign) CGSize videoSize;
@property (nonatomic, strong) GleapCaptureLabels *labels;
@property (nonatomic, strong, nullable) UIColor *accentColor;
@property (nonatomic, copy) void (^onSend)(void);
@property (nonatomic, copy) void (^onRetake)(void);
@property (nonatomic, copy) void (^onCancel)(void);
/// The preview went away without the overlay dismissing it.
@property (nonatomic, copy) void (^onDismissedUnexpectedly)(void);
/// Set by the overlay before it dismisses the preview itself.
@property (nonatomic, assign) BOOL dismissalExpected;
@property (nonatomic, strong) GleapCapturePlayerView *playerView;
@property (nonatomic, strong) GleapCaptureScrubberView *scrubber;
@property (nonatomic, strong) UILayoutGuide *mediaArea;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *retakeButton;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIStackView *buttonRow;
@property (nonatomic, strong) NSLayoutConstraint *buttonRowLeading;
@property (nonatomic, strong, nullable) NSLayoutConstraint *sendWidthConstraint;
@property (nonatomic, strong) NSNumberFormatter *percentFormatter;
@property (nonatomic, assign) BOOL uploading;
@property (nonatomic, assign) BOOL autoplayed;
@end

@implementation GleapCapturePreviewViewController

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersStatusBarHidden {
    return NO;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = GleapCaptureColor(0x0B0B0C, 1.0);
    self.view.accessibilityViewIsModal = YES;
    __weak typeof(self) weakSelf = self;
    self.percentFormatter = [[NSNumberFormatter alloc] init];
    self.percentFormatter.numberStyle = NSNumberFormatterPercentStyle;
    self.percentFormatter.maximumFractionDigits = 0;

    self.closeButton = GleapCaptureMakeButton(GleapCaptureButtonStyleSecondary, nil, GleapCaptureSymbol(@"xmark", 14), nil, kGleapButtonHeight, NO, ^{
        if (weakSelf.onCancel) {
            weakSelf.onCancel();
        }
    });
    GleapCaptureSetButtonName(self.closeButton, [self.labels text: @"barCancel"]);

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.text = [self.labels text: @"previewTitle"];
    self.titleLabel.font = [UIFont systemFontOfSize: 13 weight: UIFontWeightSemibold];
    self.titleLabel.textColor = [UIColor colorWithWhite: 1.0 alpha: 0.6];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
    [self.titleLabel setContentCompressionResistancePriority: UILayoutPriorityDefaultLow forAxis: UILayoutConstraintAxisHorizontal];

    self.playerView = [[GleapCapturePlayerView alloc] initWithFileURL: self.fileURL];
    self.playerView.playLabel = [self.labels text: @"previewPlay"];
    self.playerView.pauseLabel = [self.labels text: @"previewPause"];
    self.scrubber = [[GleapCaptureScrubberView alloc] init];
    self.playerView.onProgress = ^(double fraction) {
        weakSelf.scrubber.fraction = fraction;
    };
    self.scrubber.onBegin = ^{
        [weakSelf.playerView beginScrubbing];
    };
    self.scrubber.onScrub = ^(double fraction) {
        [weakSelf.playerView scrubToFraction: fraction];
    };
    self.scrubber.onEnd = ^{
        [weakSelf.playerView endScrubbing];
    };

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [UIFont systemFontOfSize: 13 weight: UIFontWeightRegular];
    self.statusLabel.textColor = GleapCaptureColor(0xFF9A9D, 1.0);
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 2;
    self.statusLabel.hidden = YES;

    self.retakeButton = GleapCaptureMakeButton(GleapCaptureButtonStyleSecondary, nil, GleapCaptureSymbol(@"arrow.counterclockwise", 13), [self.labels text: @"previewRetake"], kGleapPreviewButtonHeight, NO, ^{
        if (weakSelf.onRetake) {
            weakSelf.onRetake();
        }
    });
    // "Send ➤": the arrow after the label.
    self.sendButton = GleapCaptureMakeButton(GleapCaptureButtonStylePrimary, self.accentColor, GleapCaptureSymbol(@"paperplane.fill", 13), [self.labels text: @"previewSend"], kGleapPreviewButtonHeight, YES, ^{
        if (weakSelf.onSend) {
            weakSelf.onSend();
        }
    });
    for (UIButton *button in @[self.retakeButton, self.sendButton]) {
        [button.widthAnchor constraintGreaterThanOrEqualToConstant: 120].active = YES;
    }
    self.buttonRow = [[UIStackView alloc] initWithArrangedSubviews: @[self.retakeButton, self.sendButton]];
    self.buttonRow.axis = UILayoutConstraintAxisHorizontal;
    self.buttonRow.spacing = 12;
    self.buttonRow.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *bottom = [[UIStackView alloc] initWithArrangedSubviews: @[self.statusLabel]];
    bottom.axis = UILayoutConstraintAxisVertical;
    bottom.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview: self.playerView];
    [self.view addSubview: self.scrubber];
    [self.view addSubview: self.closeButton];
    [self.view addSubview: self.titleLabel];
    [self.view addSubview: bottom];
    [self.view addSubview: self.buttonRow];
    self.mediaArea = [[UILayoutGuide alloc] init];
    [self.view addLayoutGuide: self.mediaArea];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    self.buttonRowLeading = [self.buttonRow.leadingAnchor constraintEqualToAnchor: safe.leadingAnchor constant: 16];
    // The close button top right; the title centered, as wide as it can be while it stays clear of the button on both
    // sides (so it stays centered).
    [NSLayoutConstraint activateConstraints: @[
        [self.closeButton.topAnchor constraintEqualToAnchor: safe.topAnchor constant: 12],
        [self.closeButton.trailingAnchor constraintEqualToAnchor: safe.trailingAnchor constant: -16],
        [self.titleLabel.centerXAnchor constraintEqualToAnchor: safe.centerXAnchor],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor: self.closeButton.centerYAnchor],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor: self.closeButton.leadingAnchor constant: -12],
        [self.titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor: safe.leadingAnchor constant: 16 + kGleapButtonHeight + 12],

        [self.buttonRow.trailingAnchor constraintEqualToAnchor: safe.trailingAnchor constant: -16],
        [self.buttonRow.bottomAnchor constraintEqualToAnchor: safe.bottomAnchor constant: -16],
        [bottom.leadingAnchor constraintEqualToAnchor: safe.leadingAnchor constant: 16],
        [bottom.trailingAnchor constraintEqualToAnchor: safe.trailingAnchor constant: -16],
        [bottom.bottomAnchor constraintEqualToAnchor: self.buttonRow.topAnchor constant: -12],

        [self.mediaArea.topAnchor constraintEqualToAnchor: self.closeButton.bottomAnchor constant: 16],
        [self.mediaArea.bottomAnchor constraintEqualToAnchor: bottom.topAnchor constant: -16],
        [self.mediaArea.leadingAnchor constraintEqualToAnchor: safe.leadingAnchor constant: 16],
        [self.mediaArea.trailingAnchor constraintEqualToAnchor: safe.trailingAnchor constant: -16],
    ]];
    [self updateButtonRowLayout];
}

// iPhone: the two buttons fill the row; iPad: they sit on the right.
- (void)updateButtonRowLayout {
    BOOL wide = self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad && self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular;
    self.buttonRow.distribution = wide ? UIStackViewDistributionFill : UIStackViewDistributionFillEqually;
    self.buttonRowLeading.active = !wide;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange: previousTraitCollection];
    [self updateButtonRowLayout];
}

// The video as large as fits, keeping its aspect ratio, with the scrubber (a 24 pt touch area) right under it.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat scrubberHeight = 24;
    CGRect area = self.mediaArea.layoutFrame;
    area.size.height = MAX(0, area.size.height - scrubberHeight - 4);
    CGSize video = self.videoSize.width > 0 && self.videoSize.height > 0 ? self.videoSize : CGSizeMake(9, 16);
    CGRect frame = CGRectIsEmpty(area) ? CGRectZero : CGRectIntegral(AVMakeRectWithAspectRatioInsideRect(video, area));
    self.playerView.frame = frame;
    self.scrubber.frame = CGRectMake(frame.origin.x, CGRectGetMaxY(frame) + 4, frame.size.width, scrubberHeight);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear: animated];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self.titleLabel);
    // Plays once, muted, when the preview appears.
    if (!self.autoplayed) {
        self.autoplayed = YES;
        [self.playerView play];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear: animated];
    [self.playerView pause];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear: animated];
    // Only the buttons end the preview. Should anything else remove it, the flow must not be left waiting for a tap
    // that can no longer happen.
    if (!self.dismissalExpected && self.presentingViewController == nil && self.onDismissedUnexpectedly != nil) {
        void (^handler)(void) = self.onDismissedUnexpectedly;
        self.onDismissedUnexpectedly = nil;
        GleapCaptureGuarded(handler);
    }
}

- (void)releasePlayer {
    [self.playerView releasePlayer];
}

// Send shows a spinner and the percentage; Retake and the video wait. Close stays: it cancels the upload.
- (void)setUploadProgress:(double)progress {
    [self loadViewIfNeeded];
    double fraction = MIN(1.0, MAX(0.0, progress));
    if (!self.uploading) {
        self.uploading = YES;
        [self.playerView pause];
        self.playerView.interactionDisabled = YES;
        self.scrubber.userInteractionEnabled = NO;
        self.retakeButton.enabled = NO;
        self.statusLabel.hidden = YES;
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, [self.labels text: @"uploading"]);
    }
    NSLayoutConstraint *width = self.sendWidthConstraint;
    GleapCaptureSetButtonBusy(self.sendButton, YES, &width);
    self.sendWidthConstraint = width;
    NSString *percent = [self.percentFormatter stringFromNumber: @(fraction)] ?: @"";
    UIButtonConfiguration *configuration = self.sendButton.configuration;
    configuration.title = percent;
    self.sendButton.configuration = configuration;
    self.sendButton.accessibilityLabel = [self.labels text: @"uploading"];
    self.sendButton.accessibilityValue = percent;
}

- (void)setErrorMessage:(NSString *)message {
    [self loadViewIfNeeded];
    self.uploading = NO;
    self.playerView.interactionDisabled = NO;
    self.scrubber.userInteractionEnabled = YES;
    self.retakeButton.enabled = YES;
    NSLayoutConstraint *width = self.sendWidthConstraint;
    GleapCaptureSetButtonBusy(self.sendButton, NO, &width);
    self.sendWidthConstraint = width;
    GleapCaptureSetButtonTitle(self.sendButton, [self.labels text: @"previewSend"]);
    self.sendButton.accessibilityValue = nil;
    self.statusLabel.text = message;
    self.statusLabel.hidden = message.length == 0;
    if (message.length > 0) {
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
    }
}

@end

#pragma mark - Overlay

@interface GleapCaptureOverlay () <GleapCaptureBarActions>
@property (nonatomic, weak) id<GleapCaptureOverlayDelegate> delegate;
@property (nonatomic, strong) GleapCaptureLabels *labels;
@property (nonatomic, strong, nullable) UIColor *accentColor;
@property (nonatomic, strong, nullable) GleapCaptureWindow *window;
@property (nonatomic, strong, nullable) GleapCaptureBarViewController *barController;
@property (nonatomic, strong, nullable) GleapCapturePreviewViewController *preview;
@end

@implementation GleapCaptureOverlay

- (instancetype)initWithScene:(UIWindowScene *)scene labels:(GleapCaptureLabels *)labels accentColor:(UIColor *)accentColor delegate:(id<GleapCaptureOverlayDelegate>)delegate {
    self = [super init];
    if (self) {
        if (scene == nil) {
            return nil;
        }
        _delegate = delegate;
        _labels = labels;
        _accentColor = accentColor;

        GleapCaptureBarViewController *barController = [[GleapCaptureBarViewController alloc] init];
        barController.labels = labels;
        barController.accentColor = accentColor;
        barController.actions = self;
        _barController = barController;

        GleapCaptureWindow *window = [[GleapCaptureWindow alloc] initWithWindowScene: scene];
        window.windowLevel = UIWindowLevelAlert + 1;
        window.backgroundColor = [UIColor clearColor];
        // Dark over any app, like the web bar.
        window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        window.rootViewController = barController;
        _window = window;
    }
    return self;
}

- (void)showBarMode:(GleapCaptureBarMode)mode {
    if (self.window.isHidden) {
        // Shown without becoming key: the app's key window keeps the keyboard and the SDK's overlay.
        self.window.hidden = NO;
    }
    [self.barController applyMode: mode];
    [self.barController setBarHidden: NO animated: YES completion: nil];
}

- (void)setBarHidden:(BOOL)hidden animated:(BOOL)animated completion:(void (^)(void))completion {
    if (self.barController == nil) {
        if (completion) {
            completion();
        }
        return;
    }
    [self.barController setBarHidden: hidden animated: animated completion: completion];
}

- (void)updateElapsed:(NSTimeInterval)elapsed maxDuration:(NSTimeInterval)maxDuration {
    [self.barController updateElapsed: elapsed maxDuration: maxDuration];
}

- (void)presentPreviewWithFileURL:(NSURL *)fileURL videoSize:(CGSize)videoSize {
    if (self.barController == nil) {
        return;
    }
    self.window.hidden = NO;
    GleapCapturePreviewViewController *preview = [[GleapCapturePreviewViewController alloc] init];
    preview.fileURL = fileURL;
    preview.videoSize = videoSize;
    preview.labels = self.labels;
    preview.accentColor = self.accentColor;
    __weak typeof(self) weakSelf = self;
    preview.onSend = ^{ [weakSelf.delegate captureOverlayDidTapSend]; };
    preview.onRetake = ^{ [weakSelf.delegate captureOverlayDidTapRetake]; };
    preview.onCancel = ^{ [weakSelf.delegate captureOverlayDidTapPreviewCancel]; };
    preview.onDismissedUnexpectedly = ^{ [weakSelf.delegate captureOverlayPreviewWasDismissed]; };
    // Full screen and dark: the recording is all there is to look at.
    preview.modalPresentationStyle = UIModalPresentationOverFullScreen;
    preview.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    preview.modalPresentationCapturesStatusBarAppearance = YES;
    // Only the buttons end the preview.
    preview.modalInPresentation = YES;
    self.preview = preview;
    [self.barController presentViewController: preview animated: YES completion: nil];
}

- (void)setPreviewUploadProgress:(double)progress {
    [self.preview setUploadProgress: progress];
}

- (void)setPreviewErrorMessage:(NSString *)message {
    [self.preview setErrorMessage: message];
}

- (void)dismissPreviewWithCompletion:(void (^)(void))completion {
    GleapCapturePreviewViewController *preview = self.preview;
    self.preview = nil;
    preview.dismissalExpected = YES;
    if (preview == nil || preview.presentingViewController == nil) {
        [preview releasePlayer];
        if (completion) {
            completion();
        }
        return;
    }
    __block BOOL finished = NO;
    void (^finish)(void) = ^{
        if (finished) {
            return;
        }
        finished = YES;
        [preview releasePlayer];
        if (completion) {
            completion();
        }
    };
    [preview dismissViewControllerAnimated: YES completion: finish];
    // UIKit skips the completion when the dismissal cannot run; never leave the flow waiting.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), finish);
}

- (void)tearDownWithCompletion:(void (^)(void))completion {
    GleapCaptureWindow *window = self.window;
    void (^removeWindow)(void) = ^{
        window.hidden = YES;
        window.rootViewController = nil;
        if (completion) {
            completion();
        }
    };
    self.window = nil;
    self.barController.actions = nil;
    self.barController = nil;
    GleapCapturePreviewViewController *preview = self.preview;
    self.preview = nil;
    preview.dismissalExpected = YES;
    [preview releasePlayer];
    if (window == nil) {
        if (completion) {
            completion();
        }
        return;
    }
    if (preview != nil && preview.presentingViewController != nil) {
        __block BOOL finished = NO;
        void (^finish)(void) = ^{
            if (finished) {
                return;
            }
            finished = YES;
            removeWindow();
        };
        [preview dismissViewControllerAnimated: NO completion: finish];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), finish);
        return;
    }
    removeWindow();
}

+ (NSString *)formattedTime:(NSTimeInterval)seconds {
    NSInteger total = (NSInteger)floor(isfinite(seconds) ? MAX(0, seconds) : 0);
    return [NSString stringWithFormat: @"%02ld:%02ld", (long)(total / 60), (long)(total % 60)];
}

#pragma mark GleapCaptureBarActions

- (void)barDidTapPrimary {
    if (self.barController.busy) {
        return;
    }
    if (self.barController.mode == GleapCaptureBarModeScreenshot) {
        [self.delegate captureOverlayDidTapCapture];
    } else if (self.barController.mode == GleapCaptureBarModeRecordReady) {
        [self.delegate captureOverlayDidTapStart];
    }
}

- (void)barDidTapCancel {
    [self.delegate captureOverlayDidTapCancel];
}

- (void)barDidTapStop {
    if (self.barController.busy) {
        return;
    }
    [self.delegate captureOverlayDidTapStop];
}

@end
