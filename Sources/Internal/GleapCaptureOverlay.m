//
//  GleapCaptureOverlay.m
//  Gleap
//

#import "GleapCaptureOverlay.h"
#import "GleapCaptureRenderer.h"
#import "GleapUIHelper.h"
#import "GleapWindowChecker.h"
#import <AVFoundation/AVFoundation.h>

static CGFloat const kGleapBarMargin = 12.0;
static CGFloat const kGleapBarWideWidth = 420.0;
static CGFloat const kGleapBarRecordingWidth = 320.0;
static CGFloat const kGleapBarBusyWidth = 120.0;

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
        @"barStart": @"Start recording",
        @"barStop": @"Stop",
        @"barRecording": @"Recording",
        @"microphone": @"Microphone",
        @"previewTitle": @"Send this recording?",
        @"previewSend": @"Send",
        @"previewRetake": @"Retake",
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

#pragma mark - Buttons

static UIFont *GleapCaptureFont(UIFontTextStyle style, CGFloat size, UIFontWeight weight, CGFloat maximum) {
    UIFont *font = [UIFont systemFontOfSize: size weight: weight];
    return [[UIFontMetrics metricsForTextStyle: style] scaledFontForFont: font maximumPointSize: maximum];
}

static UIButton *GleapCaptureButton(BOOL prominent, UIColor *background, UIColor *foreground, NSString *symbol, void (^handler)(void)) {
    UIButtonConfiguration *configuration = prominent ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration grayButtonConfiguration];
    configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(11, 14, 11, 14);
    if (prominent) {
        configuration.baseBackgroundColor = background;
        configuration.baseForegroundColor = foreground;
    }
    if (symbol != nil) {
        configuration.image = [UIImage systemImageNamed: symbol withConfiguration: [UIImageSymbolConfiguration configurationWithPointSize: 14 weight: UIImageSymbolWeightSemibold]];
        configuration.imagePadding = 6;
    }
    // Long translations wrap instead of being cut off.
    configuration.titleLineBreakMode = NSLineBreakByWordWrapping;
    configuration.titleAlignment = UIButtonConfigurationTitleAlignmentCenter;
    configuration.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attributes) {
        NSMutableDictionary *updated = [attributes mutableCopy];
        updated[NSFontAttributeName] = GleapCaptureFont(UIFontTextStyleSubheadline, 15, UIFontWeightSemibold, 22);
        return updated;
    };
    UIButton *button = [UIButton buttonWithConfiguration: configuration primaryAction: [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        if (handler != nil) {
            handler();
        }
    }]];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

static void GleapSetButtonTitle(UIButton *button, NSString *title) {
    UIButtonConfiguration *configuration = button.configuration;
    configuration.title = title;
    button.configuration = configuration;
    button.accessibilityLabel = title;
}

#pragma mark - Bar

@protocol GleapCaptureBarActions <NSObject>
- (void)barDidTapPrimary;
- (void)barDidTapCancel;
- (void)barDidTapStop;
@end

GLEAP_INTERNAL
@interface GleapCaptureBarViewController : GleapCaptureHostForwardingViewController
@property (nonatomic, strong) GleapCaptureLabels *labels;
@property (nonatomic, strong) UIColor *accentColor;
@property (nonatomic, weak) id<GleapCaptureBarActions> actions;
@property (nonatomic, assign) GleapCaptureBarMode mode;
@property (nonatomic, strong) UIView *barContainer;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UIStackView *buttonRow;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIButton *primaryButton;
@property (nonatomic, strong) UIStackView *recordingRow;
@property (nonatomic, strong) UIView *dotView;
@property (nonatomic, strong) UILabel *timerLabel;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UIView *busyRow;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *bottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *topConstraint;
@property (nonatomic, assign) BOOL pinnedToTop;
@property (nonatomic, assign) CGFloat keyboardOverlap;
@property (nonatomic, assign) BOOL hasAppeared;
@end

@implementation GleapCaptureBarViewController

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.layer.shadowColor = [UIColor blackColor].CGColor;
    container.layer.shadowOpacity = 0.2;
    container.layer.shadowRadius = 18;
    container.layer.shadowOffset = CGSizeMake(0, 6);
    container.alpha = 0;
    [self.view addSubview: container];
    self.barContainer = container;

    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect: [UIBlurEffect effectWithStyle: UIBlurEffectStyleSystemChromeMaterial]];
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    blurView.layer.cornerRadius = 22;
    blurView.layer.cornerCurve = kCACornerCurveContinuous;
    blurView.clipsToBounds = YES;
    [container addSubview: blurView];

    UIStackView *content = [[UIStackView alloc] init];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 12;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    content.layoutMargins = UIEdgeInsetsMake(14, 16, 14, 16);
    content.layoutMarginsRelativeArrangement = YES;
    [blurView.contentView addSubview: content];

    // Ready: hint, then Cancel and the main action.
    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.numberOfLines = 0;
    self.hintLabel.font = GleapCaptureFont(UIFontTextStyleSubheadline, 15, UIFontWeightMedium, 24);
    self.hintLabel.adjustsFontForContentSizeCategory = YES;
    self.hintLabel.textColor = [UIColor labelColor];
    self.hintLabel.accessibilityTraits = UIAccessibilityTraitStaticText;

    UIColor *accent = self.accentColor ?: [UIColor systemBlueColor];
    __weak typeof(self) weakSelf = self;
    self.cancelButton = GleapCaptureButton(NO, nil, nil, nil, ^{ [weakSelf.actions barDidTapCancel]; });
    self.primaryButton = GleapCaptureButton(YES, accent, [GleapUIHelper contrastColorFrom: accent], nil, ^{ [weakSelf.actions barDidTapPrimary]; });
    // Cancel takes what its title needs, the main action the rest.
    [self.cancelButton setContentHuggingPriority: UILayoutPriorityDefaultHigh forAxis: UILayoutConstraintAxisHorizontal];
    [self.cancelButton setContentCompressionResistancePriority: UILayoutPriorityDefaultHigh + 1 forAxis: UILayoutConstraintAxisHorizontal];
    [self.primaryButton setContentHuggingPriority: UILayoutPriorityDefaultLow forAxis: UILayoutConstraintAxisHorizontal];
    self.buttonRow = [[UIStackView alloc] initWithArrangedSubviews: @[self.cancelButton, self.primaryButton]];
    self.buttonRow.axis = UILayoutConstraintAxisHorizontal;
    self.buttonRow.spacing = 10;
    self.buttonRow.distribution = UIStackViewDistributionFill;
    [self.cancelButton.widthAnchor constraintGreaterThanOrEqualToConstant: 96].active = YES;

    // Recording: red dot, "mm:ss / mm:ss", Stop.
    self.dotView = [[UIView alloc] init];
    self.dotView.translatesAutoresizingMaskIntoConstraints = NO;
    self.dotView.backgroundColor = [UIColor systemRedColor];
    self.dotView.layer.cornerRadius = 6;
    self.dotView.isAccessibilityElement = NO;
    [self.dotView.widthAnchor constraintEqualToConstant: 12].active = YES;
    [self.dotView.heightAnchor constraintEqualToConstant: 12].active = YES;

    self.timerLabel = [[UILabel alloc] init];
    self.timerLabel.font = [[UIFontMetrics metricsForTextStyle: UIFontTextStyleHeadline] scaledFontForFont: [UIFont monospacedDigitSystemFontOfSize: 16 weight: UIFontWeightSemibold] maximumPointSize: 24];
    self.timerLabel.adjustsFontForContentSizeCategory = YES;
    self.timerLabel.textColor = [UIColor labelColor];
    self.timerLabel.accessibilityTraits = UIAccessibilityTraitStaticText | UIAccessibilityTraitUpdatesFrequently;
    [self.timerLabel setContentHuggingPriority: UILayoutPriorityDefaultLow forAxis: UILayoutConstraintAxisHorizontal];

    self.stopButton = GleapCaptureButton(YES, [UIColor systemRedColor], [UIColor whiteColor], @"stop.fill", ^{ [weakSelf.actions barDidTapStop]; });
    [self.stopButton setContentHuggingPriority: UILayoutPriorityRequired forAxis: UILayoutConstraintAxisHorizontal];
    [self.stopButton setContentCompressionResistancePriority: UILayoutPriorityRequired forAxis: UILayoutConstraintAxisHorizontal];

    self.recordingRow = [[UIStackView alloc] initWithArrangedSubviews: @[self.dotView, self.timerLabel, self.stopButton]];
    self.recordingRow.axis = UILayoutConstraintAxisHorizontal;
    self.recordingRow.alignment = UIStackViewAlignmentCenter;
    self.recordingRow.spacing = 10;

    // Busy (finishing the video).
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle: UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.busyRow = [[UIView alloc] init];
    [self.busyRow addSubview: self.spinner];
    [NSLayoutConstraint activateConstraints: @[
        [self.spinner.centerXAnchor constraintEqualToAnchor: self.busyRow.centerXAnchor],
        [self.spinner.topAnchor constraintEqualToAnchor: self.busyRow.topAnchor constant: 6],
        [self.spinner.bottomAnchor constraintEqualToAnchor: self.busyRow.bottomAnchor constant: -6],
    ]];

    for (UIView *view in @[self.hintLabel, self.buttonRow, self.recordingRow, self.busyRow]) {
        [content addArrangedSubview: view];
    }

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    self.widthConstraint = [container.widthAnchor constraintEqualToConstant: kGleapBarWideWidth];
    self.widthConstraint.priority = UILayoutPriorityDefaultHigh;
    self.bottomConstraint = [container.bottomAnchor constraintEqualToAnchor: safeArea.bottomAnchor constant: -kGleapBarMargin];
    self.topConstraint = [container.topAnchor constraintEqualToAnchor: safeArea.topAnchor constant: kGleapBarMargin];
    [NSLayoutConstraint activateConstraints: @[
        [blurView.topAnchor constraintEqualToAnchor: container.topAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor: container.bottomAnchor],
        [blurView.leadingAnchor constraintEqualToAnchor: container.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor: container.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor: blurView.contentView.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor: blurView.contentView.bottomAnchor],
        [content.leadingAnchor constraintEqualToAnchor: blurView.contentView.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor: blurView.contentView.trailingAnchor],
        [container.centerXAnchor constraintEqualToAnchor: safeArea.centerXAnchor],
        [container.leadingAnchor constraintGreaterThanOrEqualToAnchor: safeArea.leadingAnchor constant: kGleapBarMargin],
        [container.trailingAnchor constraintLessThanOrEqualToAnchor: safeArea.trailingAnchor constant: -kGleapBarMargin],
        [container.topAnchor constraintGreaterThanOrEqualToAnchor: safeArea.topAnchor constant: kGleapBarMargin],
        self.widthConstraint,
        self.bottomConstraint,
    ]];

    // The bar can be dragged to the top or the bottom, out of the way of what the user wants to show.
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget: self action: @selector(handlePan:)];
    [container addGestureRecognizer: pan];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver: self selector: @selector(keyboardWillChangeFrame:) name: UIKeyboardWillChangeFrameNotification object: nil];
    [center addObserver: self selector: @selector(keyboardWillHide:) name: UIKeyboardWillHideNotification object: nil];

    [self applyMode: self.mode];
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self updateBottomSpacing];
}

- (void)applyMode:(GleapCaptureBarMode)mode {
    self.mode = mode;
    if (!self.isViewLoaded) {
        return;
    }
    BOOL ready = mode == GleapCaptureBarModeScreenshot || mode == GleapCaptureBarModeRecordReady;
    self.hintLabel.hidden = !ready;
    self.buttonRow.hidden = !ready;
    self.recordingRow.hidden = mode != GleapCaptureBarModeRecording;
    self.busyRow.hidden = mode != GleapCaptureBarModeBusy;

    GleapSetButtonTitle(self.cancelButton, [self.labels text: @"barCancel"]);
    GleapSetButtonTitle(self.stopButton, [self.labels text: @"barStop"]);
    if (mode == GleapCaptureBarModeScreenshot) {
        self.hintLabel.text = [self.labels text: @"barScreenshotHint"];
        GleapSetButtonTitle(self.primaryButton, [self.labels text: @"barCapture"]);
        [self setPrimarySymbol: @"camera.viewfinder"];
    } else if (mode == GleapCaptureBarModeRecordReady) {
        self.hintLabel.text = [self.labels text: @"barRecordHint"];
        GleapSetButtonTitle(self.primaryButton, [self.labels text: @"barStart"]);
        [self setPrimarySymbol: @"record.circle"];
    }

    if (mode == GleapCaptureBarModeRecording) {
        [self startPulsing];
    } else {
        [self.dotView.layer removeAllAnimations];
    }
    if (mode == GleapCaptureBarModeBusy) {
        [self.spinner startAnimating];
    } else {
        [self.spinner stopAnimating];
    }
    self.cancelButton.enabled = YES;
    self.primaryButton.enabled = YES;
    self.stopButton.enabled = YES;

    switch (mode) {
        case GleapCaptureBarModeRecording:
            self.widthConstraint.constant = kGleapBarRecordingWidth;
            break;
        case GleapCaptureBarModeBusy:
            self.widthConstraint.constant = kGleapBarBusyWidth;
            break;
        default:
            self.widthConstraint.constant = kGleapBarWideWidth;
            break;
    }

    if (self.hasAppeared) {
        [UIView animateWithDuration: UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.25 animations:^{
            [self.view layoutIfNeeded];
        }];
    }

    // VoiceOver: read the instruction / the recording state when the bar changes.
    id focus = ready ? self.hintLabel : (mode == GleapCaptureBarModeRecording ? self.timerLabel : nil);
    if (focus != nil) {
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, focus);
    }
}

- (void)setPrimarySymbol:(NSString *)symbol {
    UIButtonConfiguration *configuration = self.primaryButton.configuration;
    configuration.image = [UIImage systemImageNamed: symbol withConfiguration: [UIImageSymbolConfiguration configurationWithPointSize: 14 weight: UIImageSymbolWeightSemibold]];
    configuration.imagePadding = 6;
    self.primaryButton.configuration = configuration;
}

- (void)startPulsing {
    [self.dotView.layer removeAllAnimations];
    if (UIAccessibilityIsReduceMotionEnabled()) {
        return;
    }
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath: @"opacity"];
    pulse.fromValue = @1.0;
    pulse.toValue = @0.3;
    pulse.duration = 0.8;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    [self.dotView.layer addAnimation: pulse forKey: @"pulse"];
}

- (void)updateElapsed:(NSTimeInterval)elapsed maxDuration:(NSTimeInterval)maxDuration {
    NSString *time = [NSString stringWithFormat: @"%@ / %@", [GleapCaptureOverlay formattedTime: elapsed], [GleapCaptureOverlay formattedTime: maxDuration]];
    self.timerLabel.text = time;
    self.timerLabel.accessibilityLabel = [NSString stringWithFormat: @"%@, %@", [self.labels text: @"barRecording"], time];
}

- (void)setBarHidden:(BOOL)hidden animated:(BOOL)animated completion:(void (^)(void))completion {
    [self loadViewIfNeeded];
    [self.view layoutIfNeeded];
    BOOL firstShow = !hidden && !self.hasAppeared;
    self.hasAppeared = self.hasAppeared || !hidden;
    if (firstShow) {
        self.barContainer.transform = CGAffineTransformMakeTranslation(0, 24);
    }
    void (^changes)(void) = ^{
        self.barContainer.alpha = hidden ? 0.0 : 1.0;
        self.barContainer.transform = CGAffineTransformIdentity;
    };
    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration: hidden ? 0.15 : 0.3 delay: 0 usingSpringWithDamping: 0.9 initialSpringVelocity: 0 options: UIViewAnimationOptionBeginFromCurrentState animations: changes completion:^(BOOL finished) {
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
}

#pragma mark Dragging

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView: self.view];
    switch (pan.state) {
        case UIGestureRecognizerStateChanged:
            self.barContainer.transform = CGAffineTransformMakeTranslation(0, translation.y);
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            CGFloat visualCenterY = self.barContainer.center.y + translation.y;
            CGFloat velocity = [pan velocityInView: self.view].y;
            BOOL toTop = fabs(velocity) > 600 ? velocity < 0 : visualCenterY < CGRectGetMidY(self.view.bounds);
            self.barContainer.transform = CGAffineTransformIdentity;
            [self setPinnedToTop: toTop];
            [self.view layoutIfNeeded];
            self.barContainer.transform = CGAffineTransformMakeTranslation(0, visualCenterY - self.barContainer.center.y);
            [UIView animateWithDuration: 0.35 delay: 0 usingSpringWithDamping: 0.85 initialSpringVelocity: 0 options: UIViewAnimationOptionAllowUserInteraction animations:^{
                self.barContainer.transform = CGAffineTransformIdentity;
            } completion: nil];
            break;
        }
        default:
            break;
    }
}

- (void)setPinnedToTop:(BOOL)pinnedToTop {
    _pinnedToTop = pinnedToTop;
    self.bottomConstraint.active = !pinnedToTop;
    self.topConstraint.active = pinnedToTop;
}

#pragma mark Keyboard

- (void)keyboardWillChangeFrame:(NSNotification *)notification {
    CGRect endFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    UIScreen *screen = self.view.window.windowScene.screen ?: UIScreen.mainScreen;
    CGRect keyboard = [self.view convertRect: endFrame fromCoordinateSpace: screen.coordinateSpace];
    CGRect overlap = CGRectIntersection(keyboard, self.view.bounds);
    self.keyboardOverlap = CGRectIsNull(overlap) || CGRectIsEmpty(overlap) ? 0 : MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(keyboard));
    [self animateBottomSpacingWithNotification: notification];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    self.keyboardOverlap = 0;
    [self animateBottomSpacingWithNotification: notification];
}

- (void)animateBottomSpacingWithNotification:(NSNotification *)notification {
    [self updateBottomSpacing];
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration: duration animations:^{
        [self.view layoutIfNeeded];
    }];
}

- (void)updateBottomSpacing {
    CGFloat extra = MAX(0, self.keyboardOverlap - self.view.safeAreaInsets.bottom);
    self.bottomConstraint.constant = -(kGleapBarMargin + extra);
}

@end

#pragma mark - Preview

/// The recording in the preview: an AVPlayerLayer with play / pause and a progress line. No AVKit, so no full
/// screen, AirPlay, picture in picture or Now Playing entry, and nothing that could dismiss the sheet.
GLEAP_INTERNAL
@interface GleapCapturePlayerView : UIView
@property (nonatomic, strong, nullable) AVPlayer *player;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong, nullable) id timeObserver;
@property (nonatomic, assign) BOOL reachedEnd;
- (void)play;
- (void)pause;
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
        AVPlayer *player = [AVPlayer playerWithURL: fileURL];
        player.muted = YES;
        player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
        player.preventsDisplaySleepDuringVideoPlayback = NO;
        self.player = player;
        AVPlayerLayer *playerLayer = (AVPlayerLayer *)self.layer;
        playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        playerLayer.player = player;

        __weak typeof(self) weakSelf = self;
        self.playButton = [UIButton buttonWithConfiguration: [UIButtonConfiguration filledButtonConfiguration] primaryAction: [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
            [weakSelf togglePlayback];
        }]];
        UIButtonConfiguration *configuration = self.playButton.configuration;
        configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        configuration.baseBackgroundColor = [[UIColor blackColor] colorWithAlphaComponent: 0.55];
        configuration.baseForegroundColor = [UIColor whiteColor];
        configuration.contentInsets = NSDirectionalEdgeInsetsMake(10, 10, 10, 10);
        self.playButton.configuration = configuration;
        self.playButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview: self.playButton];

        self.progressView = [[UIProgressView alloc] initWithProgressViewStyle: UIProgressViewStyleBar];
        self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
        self.progressView.progressTintColor = [UIColor whiteColor];
        self.progressView.trackTintColor = [[UIColor whiteColor] colorWithAlphaComponent: 0.25];
        self.progressView.isAccessibilityElement = NO;
        [self addSubview: self.progressView];

        [NSLayoutConstraint activateConstraints: @[
            [self.playButton.leadingAnchor constraintEqualToAnchor: self.leadingAnchor constant: 12],
            [self.playButton.bottomAnchor constraintEqualToAnchor: self.progressView.topAnchor constant: -10],
            [self.progressView.leadingAnchor constraintEqualToAnchor: self.leadingAnchor],
            [self.progressView.trailingAnchor constraintEqualToAnchor: self.trailingAnchor],
            [self.progressView.bottomAnchor constraintEqualToAnchor: self.bottomAnchor],
            [self.progressView.heightAnchor constraintEqualToConstant: 3],
        ]];

        self.timeObserver = [player addPeriodicTimeObserverForInterval: CMTimeMake(1, 10) queue: dispatch_get_main_queue() usingBlock:^(CMTime time) {
            [weakSelf updateProgress];
        }];
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(playerDidReachEnd:) name: AVPlayerItemDidPlayToEndTimeNotification object: player.currentItem];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget: self action: @selector(togglePlayback)];
        [self addGestureRecognizer: tap];
        [self updatePlayButton];
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

- (void)play {
    if (self.player == nil) {
        return;
    }
    if (self.reachedEnd) {
        self.reachedEnd = NO;
        [self.player seekToTime: kCMTimeZero];
    }
    [self.player play];
    [self updatePlayButton];
}

- (void)pause {
    [self.player pause];
    [self updatePlayButton];
}

- (void)togglePlayback {
    if (self.player.rate > 0) {
        [self pause];
    } else {
        [self play];
    }
}

- (void)playerDidReachEnd:(NSNotification *)notification {
    self.reachedEnd = YES;
    [self updatePlayButton];
    [self updateProgress];
}

- (void)updateProgress {
    CMTime duration = self.player.currentItem.duration;
    double total = CMTIME_IS_NUMERIC(duration) ? CMTimeGetSeconds(duration) : 0;
    double current = CMTimeGetSeconds(self.player.currentTime);
    self.progressView.progress = total > 0 ? (float)MIN(1.0, MAX(0.0, current / total)) : 0;
    [self updatePlayButton];
}

- (void)updatePlayButton {
    BOOL playing = self.player.rate > 0;
    // System symbols come with localized VoiceOver labels (Play, Pause, Replay).
    NSString *symbol = playing ? @"pause.fill" : (self.reachedEnd ? @"arrow.counterclockwise" : @"play.fill");
    UIButtonConfiguration *configuration = self.playButton.configuration;
    configuration.image = [UIImage systemImageNamed: symbol withConfiguration: [UIImageSymbolConfiguration configurationWithPointSize: 15 weight: UIImageSymbolWeightBold]];
    self.playButton.configuration = configuration;
}

@end

GLEAP_INTERNAL
@interface GleapCapturePreviewViewController : GleapCaptureHostForwardingViewController
@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic, strong) GleapCaptureLabels *labels;
@property (nonatomic, strong) UIColor *accentColor;
@property (nonatomic, copy) void (^onSend)(void);
@property (nonatomic, copy) void (^onRetake)(void);
@property (nonatomic, copy) void (^onCancel)(void);
/// The sheet went away without the overlay dismissing it.
@property (nonatomic, copy) void (^onDismissedUnexpectedly)(void);
/// Set by the overlay before it dismisses the sheet itself.
@property (nonatomic, assign) BOOL dismissalExpected;
@property (nonatomic, strong) GleapCapturePlayerView *playerView;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *retakeButton;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UIStackView *statusStack;
@property (nonatomic, assign) BOOL uploading;
@property (nonatomic, assign) BOOL autoplayed;
@end

@implementation GleapCapturePreviewViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    __weak typeof(self) weakSelf = self;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = [self.labels text: @"previewTitle"];
    titleLabel.font = GleapCaptureFont(UIFontTextStyleHeadline, 17, UIFontWeightSemibold, 26);
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 2;
    titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;

    self.cancelButton = [UIButton buttonWithConfiguration: [UIButtonConfiguration plainButtonConfiguration] primaryAction: [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        if (weakSelf.onCancel) {
            weakSelf.onCancel();
        }
    }]];
    GleapSetButtonTitle(self.cancelButton, [self.labels text: @"barCancel"]);
    [self.cancelButton setContentHuggingPriority: UILayoutPriorityRequired forAxis: UILayoutConstraintAxisHorizontal];
    [self.cancelButton setContentCompressionResistancePriority: UILayoutPriorityRequired forAxis: UILayoutConstraintAxisHorizontal];
    UIView *balance = [[UIView alloc] init];
    balance.translatesAutoresizingMaskIntoConstraints = NO;
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews: @[self.cancelButton, titleLabel, balance]];
    header.axis = UILayoutConstraintAxisHorizontal;
    header.alignment = UIStackViewAlignmentCenter;
    header.spacing = 8;
    [balance.widthAnchor constraintEqualToAnchor: self.cancelButton.widthAnchor].active = YES;

    self.playerView = [[GleapCapturePlayerView alloc] initWithFileURL: self.fileURL];
    self.playerView.layer.cornerRadius = 14;
    self.playerView.layer.cornerCurve = kCACornerCurveContinuous;
    self.playerView.clipsToBounds = YES;
    [self.playerView setContentHuggingPriority: UILayoutPriorityDefaultLow forAxis: UILayoutConstraintAxisVertical];
    [self.playerView setContentCompressionResistancePriority: UILayoutPriorityDefaultLow forAxis: UILayoutConstraintAxisVertical];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = GleapCaptureFont(UIFontTextStyleFootnote, 13, UIFontWeightRegular, 20);
    self.statusLabel.adjustsFontForContentSizeCategory = YES;
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle: UIProgressViewStyleDefault];
    self.progressView.progressTintColor = self.accentColor;
    self.statusStack = [[UIStackView alloc] initWithArrangedSubviews: @[self.statusLabel, self.progressView]];
    self.statusStack.axis = UILayoutConstraintAxisVertical;
    self.statusStack.spacing = 8;
    self.statusStack.hidden = YES;

    UIColor *accent = self.accentColor ?: [UIColor systemBlueColor];
    self.retakeButton = GleapCaptureButton(NO, nil, nil, @"arrow.counterclockwise", ^{
        if (weakSelf.onRetake) {
            weakSelf.onRetake();
        }
    });
    GleapSetButtonTitle(self.retakeButton, [self.labels text: @"previewRetake"]);
    self.sendButton = GleapCaptureButton(YES, accent, [GleapUIHelper contrastColorFrom: accent], @"paperplane.fill", ^{
        if (weakSelf.onSend) {
            weakSelf.onSend();
        }
    });
    GleapSetButtonTitle(self.sendButton, [self.labels text: @"previewSend"]);
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews: @[self.retakeButton, self.sendButton]];
    buttons.axis = UILayoutConstraintAxisHorizontal;
    buttons.spacing = 12;
    buttons.distribution = UIStackViewDistributionFillEqually;

    UIStackView *layout = [[UIStackView alloc] initWithArrangedSubviews: @[header, self.playerView, self.statusStack, buttons]];
    layout.axis = UILayoutConstraintAxisVertical;
    layout.spacing = 16;
    layout.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview: layout];
    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints: @[
        [layout.topAnchor constraintEqualToAnchor: safeArea.topAnchor constant: 12],
        [layout.bottomAnchor constraintEqualToAnchor: safeArea.bottomAnchor constant: -16],
        [layout.leadingAnchor constraintEqualToAnchor: safeArea.leadingAnchor constant: 16],
        [layout.trailingAnchor constraintEqualToAnchor: safeArea.trailingAnchor constant: -16],
        [self.playerView.heightAnchor constraintGreaterThanOrEqualToConstant: 160],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear: animated];
    // Plays once, muted, when the sheet appears.
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
    // Only the buttons end the preview. Should anything else remove the sheet, the flow must not be left
    // waiting for a tap that can no longer happen.
    if (!self.dismissalExpected && self.presentingViewController == nil && self.onDismissedUnexpectedly != nil) {
        void (^handler)(void) = self.onDismissedUnexpectedly;
        self.onDismissedUnexpectedly = nil;
        handler();
    }
}

- (void)releasePlayer {
    [self.playerView releasePlayer];
}

- (void)setUploadProgress:(double)progress {
    [self loadViewIfNeeded];
    if (!self.uploading) {
        self.uploading = YES;
        [self.playerView pause];
        self.statusLabel.text = [self.labels text: @"uploading"];
        self.statusLabel.textColor = [UIColor secondaryLabelColor];
        self.progressView.hidden = NO;
        self.statusStack.hidden = NO;
        self.sendButton.enabled = NO;
        self.retakeButton.enabled = NO;
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, self.statusLabel.text);
    }
    [self.progressView setProgress: (float)MIN(1.0, MAX(0.0, progress)) animated: YES];
}

- (void)setErrorMessage:(NSString *)message {
    [self loadViewIfNeeded];
    self.uploading = NO;
    self.progressView.hidden = YES;
    self.progressView.progress = 0;
    self.statusLabel.text = message;
    self.statusLabel.textColor = [UIColor systemRedColor];
    self.statusStack.hidden = message.length == 0;
    self.sendButton.enabled = YES;
    self.retakeButton.enabled = YES;
    if (message.length > 0) {
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
    }
}

@end

#pragma mark - Overlay

@interface GleapCaptureOverlay () <GleapCaptureBarActions>
@property (nonatomic, weak) id<GleapCaptureOverlayDelegate> delegate;
@property (nonatomic, strong) GleapCaptureLabels *labels;
@property (nonatomic, strong) UIColor *accentColor;
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
        _accentColor = accentColor ?: [UIColor systemBlueColor];

        GleapCaptureBarViewController *barController = [[GleapCaptureBarViewController alloc] init];
        barController.labels = labels;
        barController.accentColor = _accentColor;
        barController.actions = self;
        _barController = barController;

        GleapCaptureWindow *window = [[GleapCaptureWindow alloc] initWithWindowScene: scene];
        window.windowLevel = UIWindowLevelAlert + 1;
        window.backgroundColor = [UIColor clearColor];
        // Light / dark like the app underneath.
        UIViewController *host = [GleapUIHelper getTopMostViewController];
        if (host != nil) {
            window.overrideUserInterfaceStyle = host.traitCollection.userInterfaceStyle;
        }
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

- (void)presentPreviewWithFileURL:(NSURL *)fileURL {
    if (self.barController == nil) {
        return;
    }
    self.window.hidden = NO;
    GleapCapturePreviewViewController *preview = [[GleapCapturePreviewViewController alloc] init];
    preview.fileURL = fileURL;
    preview.labels = self.labels;
    preview.accentColor = self.accentColor;
    __weak typeof(self) weakSelf = self;
    preview.onSend = ^{ [weakSelf.delegate captureOverlayDidTapSend]; };
    preview.onRetake = ^{ [weakSelf.delegate captureOverlayDidTapRetake]; };
    preview.onCancel = ^{ [weakSelf.delegate captureOverlayDidTapPreviewCancel]; };
    preview.onDismissedUnexpectedly = ^{ [weakSelf.delegate captureOverlayPreviewWasDismissed]; };
    BOOL pad = self.window.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad;
    preview.modalPresentationStyle = pad ? UIModalPresentationFormSheet : UIModalPresentationPageSheet;
    preview.preferredContentSize = CGSizeMake(540, 640);
    // Only the buttons end the preview; swiping it away would leave the flow hanging.
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
    NSInteger total = (NSInteger)floor(MAX(0, seconds));
    return [NSString stringWithFormat: @"%02ld:%02ld", (long)(total / 60), (long)(total % 60)];
}

#pragma mark GleapCaptureBarActions

- (void)barDidTapPrimary {
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
    [self.delegate captureOverlayDidTapStop];
}

@end
