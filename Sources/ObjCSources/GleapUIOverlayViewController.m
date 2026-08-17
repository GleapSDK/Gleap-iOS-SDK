//
//  GleapUIOverlayViewController.m
//
//
//  Created by Lukas Boehler on 11.09.22.
//

#import "GleapUIOverlayViewController.h"
#import "GleapSessionHelper.h"
#import "GleapConfigHelper.h"
#import "GleapTranslationHelper.h"
#import "GleapWindowChecker.h"
#import "Gleap.h"

// The gap between two expanded notification cards.
static const CGFloat kGleapNotificationCardGap = 12.0;

// Collapsed stack: how far the top edge of a card behind peeks out above the
// front card, per depth (depth 1 and depth 2 — anything deeper stays hidden
// until the stack expands).
static const CGFloat kGleapNotificationStackPeek1 = 9.0;
static const CGFloat kGleapNotificationStackPeek2 = 17.0;

// How far back a card scales at each peek depth when collapsed.
static const CGFloat kGleapNotificationStackScale1 = 0.955;
static const CGFloat kGleapNotificationStackScale2 = 0.91;

// Headroom above the front card that keeps the peeking edges inside the
// container, and with them the floating close button.
static const CGFloat kGleapNotificationStackHeadroom = 17.0;

/**
 * The notifications container spans the whole stack (plus the headroom the
 * peeking cards need), so empty regions must hand touches back to the app,
 * and the close button — floating slightly outside the top corner — must
 * still be tappable.
 */
@interface GleapNotificationsContainerView : UIView

@property (nonatomic, weak) UIView *overhangingCloseButton;

@end

@implementation GleapNotificationsContainerView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // The close button floats 9pt outside the container's top corner, so the
    // default hit testing would miss its overhanging half.
    if (self.overhangingCloseButton != nil && self.overhangingCloseButton.hidden == NO && self.overhangingCloseButton.alpha > 0.01) {
        CGPoint pointInButton = [self convertPoint: point toView: self.overhangingCloseButton];
        if ([self.overhangingCloseButton pointInside: pointInButton withEvent: event]) {
            return [self.overhangingCloseButton hitTest: pointInButton withEvent: event];
        }
    }

    UIView *hit = [super hitTest: point withEvent: event];

    // Touches that land on no card fall through to the host app.
    if (hit == self) {
        return nil;
    }
    return hit;
}

@end

@interface GleapUIOverlayViewController ()

@property (nonatomic, assign) int lastNotificationCount;
@property (nonatomic, assign) BOOL stackExpanded;
@property (nonatomic, retain) NSLayoutConstraint *notificationsContainerHeightConstraint;
@property (nonatomic, retain) UIView *notificationsCloseButton;

@end

@implementation GleapUIOverlayViewController

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}

- (UIWindow *)getKeyWindow {
    return [GleapWindowChecker getKeyWindow];
}

- (void)performNotificationAction:(UITapGestureRecognizer *)sender {
    if (sender == nil || sender.view == nil) {
        return;
    }

    // A collapsed stack expands on the first tap instead of activating the
    // front card — same as the web widget on touch devices.
    if ([self isStackCollapsed]) {
        [self setStackExpanded: YES animated: YES];
        return;
    }

    long tag = sender.view.tag;
    if (tag < 0 || tag >= self.internalNotifications.count) {
        return;
    }

    NSDictionary *notification = [self.internalNotifications objectAtIndex: tag];
    if (notification != nil) {
        NSString *shareToken = [notification valueForKeyPath: @"data.conversation.shareToken"];
        NSString *newsId = [notification valueForKeyPath: @"data.news.id"];
        NSString *checklistId = [notification valueForKeyPath: @"data.checklist.id"];
        if (shareToken != nil) {
            [Gleap openConversation: shareToken];
        } else if (newsId != nil) {
            [Gleap openNewsArticle: newsId andShowBackButton: YES];
        } else if (checklistId != nil) {
            [Gleap openChecklist: checklistId];
        } else {
            [Gleap open];
        }
    }
}

- (void)clearNotifications:(UITapGestureRecognizer *)sender {
    [GleapUIOverlayHelper clear];
}

- (void)feedbackButtonPressed:(UITapGestureRecognizer *)sender {
    [Gleap open];
}

- (void)initializeUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.internalNotifications = [[NSMutableArray alloc] init];
        self.notificationViews = [[NSMutableArray alloc] init];
        self.lastNotificationCount = 0;

        // Render the feedback button on the current key window.
        [self attachFeedbackButtonToKeyWindow];

        // The feedback button (and the notification overlay) lives as a subview of
        // the app's key window. Some hosts swap their key window at runtime – this is
        // common with Flutter and other embedded / multi-window setups – which would
        // leave the button stranded on the old, now-hidden window and make it
        // "disappear" a while after launch. Observe the relevant lifecycle events so
        // we can move the overlay back onto the active key window whenever that happens.
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(keyWindowMayHaveChanged:)
                                                     name: UIWindowDidBecomeKeyNotification
                                                   object: nil];
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(keyWindowMayHaveChanged:)
                                                     name: UIApplicationDidBecomeActiveNotification
                                                   object: nil];
        if (@available(iOS 13.0, *)) {
            [[NSNotificationCenter defaultCenter] addObserver: self
                                                     selector: @selector(keyWindowMayHaveChanged:)
                                                         name: UISceneDidActivateNotification
                                                       object: nil];
        }
    });
}

// Creates the feedback button and attaches it to the current key window.
- (void)attachFeedbackButtonToKeyWindow {
    UIWindow *keyWindow = [self getKeyWindow];
    if (keyWindow == nil) {
        return;
    }

    BOOL opened = [Gleap isOpened];

    self.feedbackButton = [[GleapFeedbackButton alloc] initWithFrame: CGRectMake(0, 0, 54.0, 54.0)];
    [keyWindow addSubview: self.feedbackButton];
    self.feedbackButton.layer.zPosition = INT_MAX;
    [self.feedbackButton applyConfig];
    [self.feedbackButton setUserInteractionEnabled: !opened];
    [self.feedbackButton setNotificationCount: self.lastNotificationCount];
    self.feedbackButton.alpha = opened ? 0.0 : 1.0;

    UITapGestureRecognizer *feedbackButtonGesture =
    [[UITapGestureRecognizer alloc] initWithTarget: self
                                            action: @selector(feedbackButtonPressed:)];
    [self.feedbackButton addGestureRecognizer: feedbackButtonGesture];
}

- (void)keyWindowMayHaveChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ensureOverlayAttachedToKeyWindow];
        [self renderNotifications];
    });
}

// Ensures the feedback button is attached to the app's current key window. If the
// key window has changed (e.g. the host app swapped windows), the button is
// recreated on the new window – recreating it guarantees the layout constraints,
// which are pinned to the previous window, are torn down (removeFromSuperview
// removes constraints referencing the view) and rebuilt cleanly. Banners and
// modals are transient and always created on the active key window at show-time,
// so they don't need to be tracked here.
- (void)ensureOverlayAttachedToKeyWindow {
    UIWindow *keyWindow = [self getKeyWindow];
    if (keyWindow == nil) {
        return;
    }

    if (self.feedbackButton != nil && self.feedbackButton.window == keyWindow) {
        // Already on the correct window – just keep it on top.
        [self bringViewToFront: self.feedbackButton];
        return;
    }

    if (self.feedbackButton != nil) {
        [self.feedbackButton removeFromSuperview];
        self.feedbackButton = nil;
    }

    [self attachFeedbackButtonToKeyWindow];
    [self.feedbackButton updateVisibility];
}

- (void)bringViewToFront:(UIView *)view {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (view != nil && view.superview != nil) {
            [view.superview bringSubviewToFront: view];
        }
    });
}

- (void)updateUIPositions {
    [self bringViewToFront: self.feedbackButton];
    [self bringViewToFront: self.notificationsContainerView];
    [self bringViewToFront: self.banner];
    [self bringViewToFront: self.modal];
}

- (void)showBanner:(NSDictionary *)bannerData {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow* keyWindow = [self getKeyWindow];
        if (keyWindow == nil) {
            return;
        }

        if (self.banner != nil) {
            [self.banner removeFromSuperview];
            self.banner = nil;
        }

        self.banner = [[GleapBanner alloc] initWithFrame: CGRectMake(0, 0, keyWindow.frame.size.width, 70.0)];
        self.banner.translatesAutoresizingMaskIntoConstraints = NO;
        self.banner.layer.zPosition = INT_MAX;
        [keyWindow addSubview: self.banner];

        @try {
            NSLayoutConstraint *trailing = [NSLayoutConstraint
                                            constraintWithItem: self.banner
                                            attribute: NSLayoutAttributeTrailing
                                            relatedBy: NSLayoutRelationEqual
                                            toItem: keyWindow
                                            attribute: NSLayoutAttributeTrailing
                                            multiplier: 1.0f
                                            constant: 0.f];
            NSLayoutConstraint *leading = [NSLayoutConstraint
                                           constraintWithItem: self.banner
                                           attribute: NSLayoutAttributeLeading
                                           relatedBy: NSLayoutRelationEqual
                                           toItem: keyWindow
                                           attribute: NSLayoutAttributeLeading
                                           multiplier: 1.0f
                                           constant: 0.f];
            [keyWindow addConstraint: leading];
            [keyWindow addConstraint: trailing];

            NSLayoutConstraint *top =[NSLayoutConstraint
                                      constraintWithItem: self.banner
                                      attribute: NSLayoutAttributeTop
                                      relatedBy: NSLayoutRelationEqual
                                      toItem: keyWindow
                                      attribute: NSLayoutAttributeTop
                                      multiplier: 1.0f
                                      constant: 0.f];
            [keyWindow addConstraint: top];
        }
        @catch (NSException *exception) {}

        [self.banner setupWithData: bannerData];
    });
}

- (void)showModal:(NSDictionary *)modalData {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [self getKeyWindow];
        if (!keyWindow) {
            return;
        }

        // If a modal is already showing, remove it first
        if (self.modal) {
            [self.modal removeFromSuperview];
            self.modal = nil;
        }

        // Create the modal full-screen
        self.modal = [[GleapModal alloc] initWithFrame:keyWindow.bounds];
        self.modal.translatesAutoresizingMaskIntoConstraints = NO;
        self.modal.layer.zPosition = INT_MAX;
        self.modal.alpha = 0.0; // start hidden
        [keyWindow addSubview:self.modal];

        @try {
            // Pin to all edges of the window
            [keyWindow addConstraints:@[
                [NSLayoutConstraint constraintWithItem:self.modal
                                             attribute:NSLayoutAttributeLeading
                                             relatedBy:NSLayoutRelationEqual
                                                toItem:keyWindow
                                             attribute:NSLayoutAttributeLeading
                                            multiplier:1.0
                                              constant:0],
                [NSLayoutConstraint constraintWithItem:self.modal
                                             attribute:NSLayoutAttributeTrailing
                                             relatedBy:NSLayoutRelationEqual
                                                toItem:keyWindow
                                             attribute:NSLayoutAttributeTrailing
                                            multiplier:1.0
                                              constant:0],
                [NSLayoutConstraint constraintWithItem:self.modal
                                             attribute:NSLayoutAttributeTop
                                             relatedBy:NSLayoutRelationEqual
                                                toItem:keyWindow
                                             attribute:NSLayoutAttributeTop
                                            multiplier:1.0
                                              constant:0],
                [NSLayoutConstraint constraintWithItem:self.modal
                                             attribute:NSLayoutAttributeBottom
                                             relatedBy:NSLayoutRelationEqual
                                                toItem:keyWindow
                                             attribute:NSLayoutAttributeBottom
                                            multiplier:1.0
                                              constant:0],
            ]];
        } @catch (NSException *exception) {
            // nothing to do
        }

        // Configure with data and fade in
        [self.modal setupWithData:modalData];
        [UIView animateWithDuration:0.3 animations:^{
            self.modal.alpha = 1.0;
        }];
    });
}

- (void)setNotifications:(NSMutableArray *)notifications {
    self.internalNotifications = notifications;
    [self renderNotifications];

    // Hide the button if notifications are available and it's a classic button left or right.
    NSDictionary *config = GleapConfigHelper.sharedInstance.config;
    if (config != nil) {
        NSString *feedbackButtonPosition = [config objectForKey: @"feedbackButtonPosition"];
        // Hide feedback button.
        if ([feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC_LEFT"] || [feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC"] || [feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC_BOTTOM"]) {
            if (![Gleap isOpened]) {
                if (notifications != nil && notifications.count > 0) {
                    [UIView animateWithDuration: 0.3f animations:^{
                        self.feedbackButton.alpha = 0.0;
                    } completion:^(BOOL finished) {}];
                } else {
                    [UIView animateWithDuration: 0.3f animations:^{
                            self.feedbackButton.alpha = 1.0;
                    } completion:^(BOOL finished) {}];
                }
            }
        }
    }
}

- (void)updateNotificationCount:(int)notificationCount {
    self.lastNotificationCount = notificationCount;
    [self.feedbackButton setNotificationCount: notificationCount];
}

- (void)updateUI {
    // Safety net: make sure the button is on the current key window before we
    // refresh its state. updateUI is invoked on most lifecycle / config events.
    [self ensureOverlayAttachedToKeyWindow];

    if ([Gleap isOpened]) {
        self.internalNotifications = [[NSMutableArray alloc] init];

        [UIView animateWithDuration:0.1f animations:^{
            self.feedbackButton.alpha = 0.0;
            if (self.banner != nil) {
                self.banner.alpha = 0.0;
            }
            if (self.modal != nil) {
                self.modal.alpha = 0.0;
            }
        } completion:^(BOOL finished) {
            [self.feedbackButton setUserInteractionEnabled: NO];
            if (self.banner != nil) {
                [self.banner setUserInteractionEnabled: NO];
            }
            if (self.modal != nil) {
                [self.modal setUserInteractionEnabled: NO];
            }
        }];
    } else {
        [UIView animateWithDuration:0.3f animations:^{
            self.feedbackButton.alpha = 1.0;
            if (self.banner != nil) {
                self.banner.alpha = 1.0;
            }
            if (self.modal != nil) {
                self.modal.alpha = 1.0;
            }
        } completion:^(BOOL finished) {
            [self.feedbackButton setUserInteractionEnabled: YES];
            if (self.banner != nil) {
                [self.banner setUserInteractionEnabled: YES];
            }
            if (self.modal != nil) {
                [self.modal setUserInteractionEnabled: YES];
            }
        }];
    }

    [self.feedbackButton updateVisibility];
    [self renderNotifications];
}

#pragma mark - Notification theming

// The widget theme drives the notification look — the same colors the web
// widget derives in injectStyledCSS, so a dark-themed project gets dark cards
// on every platform, independent of the OS appearance.

+ (UIColor *)notificationBackgroundColor {
    NSDictionary *config = GleapConfigHelper.sharedInstance.config;
    NSString *backgroundColor = [config objectForKey: @"backgroundColor"];
    if (backgroundColor == nil || backgroundColor.length == 0) {
        backgroundColor = @"#ffffff";
    }
    return [GleapUIHelper colorFromHexString: backgroundColor];
}

// YIQ >= 160 reads as a light background — the same threshold the web
// widget's calculateContrast uses.
+ (BOOL)notificationUsesDarkTheme {
    UIColor *backgroundColor = [GleapUIOverlayViewController notificationBackgroundColor];
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    [backgroundColor getRed: &red green: &green blue: &blue alpha: &alpha];
    CGFloat yiq = ((red * 255.0 * 299.0) + (green * 255.0 * 587.0) + (blue * 255.0 * 114.0)) / 1000.0;
    return yiq < 160.0;
}

+ (UIColor *)notificationContrastColor {
    return [GleapUIOverlayViewController notificationUsesDarkTheme] ? [UIColor whiteColor] : [UIColor blackColor];
}

// Shifts every channel by `amount` (0-255 scale), clamped — mirrors the web
// widget's calculateShadeColor, which derives the muted text color from the
// background.
+ (UIColor *)shadeOfNotificationBackground:(CGFloat)amount {
    UIColor *backgroundColor = [GleapUIOverlayViewController notificationBackgroundColor];
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    [backgroundColor getRed: &red green: &green blue: &blue alpha: &alpha];
    CGFloat shift = amount / 255.0;
    return [UIColor colorWithRed: MAX(0.0, MIN(1.0, red + shift))
                           green: MAX(0.0, MIN(1.0, green + shift))
                            blue: MAX(0.0, MIN(1.0, blue + shift))
                           alpha: 1.0];
}

+ (UIColor *)notificationSubTextColor {
    if ([GleapUIOverlayViewController notificationUsesDarkTheme]) {
        return [GleapUIOverlayViewController shadeOfNotificationBackground: 100.0];
    }
    return [GleapUIOverlayViewController shadeOfNotificationBackground: -120.0];
}

// A drop shadow alone cannot separate a dark card from a dark page, so the
// card also carries a hairline in the direction the theme needs.
+ (UIColor *)notificationHairlineColor {
    if ([GleapUIOverlayViewController notificationUsesDarkTheme]) {
        return [UIColor colorWithWhite: 1.0 alpha: 0.1];
    }
    return [UIColor colorWithWhite: 0.0 alpha: 0.04];
}

+ (CGFloat)notificationConfiguredBorderRadius {
    NSDictionary *config = GleapConfigHelper.sharedInstance.config;
    if (config != nil && [config objectForKey: @"borderRadius"] != nil) {
        return [[config objectForKey: @"borderRadius"] floatValue];
    }
    return 20.0;
}

// The card corner radius, derived from the project's border radius setting
// exactly like the web widget's containerRadius.
+ (CGFloat)notificationContainerRadius {
    return round([GleapUIOverlayViewController notificationConfiguredBorderRadius] * 0.8);
}

// The bot's avatar is a rounded rectangle rather than a circle — the same
// shape the dashboard and the messenger give it. Derived from the project's
// radius so a squared-off widget theme keeps squared-off marks; 7pt at the
// default 20 on the 32pt notification avatar.
+ (CGFloat)notificationBotAvatarRadiusForSize:(CGFloat)size {
    CGFloat formItemRadius = round([GleapUIOverlayViewController notificationConfiguredBorderRadius] * 0.4);
    return MAX(2.0, round((formItemRadius * size) / 36.0));
}

#pragma mark - Relative time

/**
 * "now" / "5 minutes ago" label for a notification's age, localized by the
 * system through NSRelativeDateTimeFormatter. Returns nil whenever a truthful
 * label can't be produced (no timestamp, an unparsable one, or an OS without
 * the formatter), so callers drop the label instead of printing a placeholder.
 *
 * The age is taken from sendAt rather than createdAt: a scheduled outbound is
 * written to the database long before it is delivered, and its creation time
 * would surface as an hours-old message the user just received.
 */
+ (NSString *)relativeTimeLabelForNotification:(NSDictionary *)notification {
    @try {
        if (@available(iOS 13.0, *)) {
            id timestamp = [notification objectForKey: @"sendAt"];
            if (timestamp == nil || ![timestamp isKindOfClass: [NSString class]] || [timestamp length] == 0) {
                timestamp = [notification objectForKey: @"createdAt"];
            }
            if (timestamp == nil || ![timestamp isKindOfClass: [NSString class]] || [timestamp length] == 0) {
                return nil;
            }

            NSISO8601DateFormatter *isoFormatter = [[NSISO8601DateFormatter alloc] init];
            isoFormatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
            NSDate *date = [isoFormatter dateFromString: timestamp];
            if (date == nil) {
                isoFormatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
                date = [isoFormatter dateFromString: timestamp];
            }
            if (date == nil) {
                return nil;
            }

            NSRelativeDateTimeFormatter *formatter = [[NSRelativeDateTimeFormatter alloc] init];
            formatter.dateTimeStyle = NSRelativeDateTimeFormatterStyleNamed;

            // The widget's language override, falling back to the device locale.
            NSString *language = GleapTranslationHelper.sharedInstance.language;
            if (language != nil && language.length > 0) {
                NSLocale *locale = [NSLocale localeWithLocaleIdentifier: language];
                if (locale != nil) {
                    formatter.locale = locale;
                }
            }

            // Clamped at 0: a notification scheduled a few seconds ahead (or a
            // client clock running behind the server's) must never read as
            // "in 1 minute". Under a minute collapses to "now" rather than
            // ticking "9 seconds ago".
            NSTimeInterval seconds = MIN(0.0, [date timeIntervalSinceNow]);
            if (seconds > -60.0) {
                seconds = 0.0;
            }
            return [formatter localizedStringFromTimeInterval: seconds];
        }
    } @catch (id exp) {}

    return nil;
}

#pragma mark - Rendering

- (BOOL)isStackCollapsed {
    return self.internalNotifications.count > 1 && !self.stackExpanded;
}

- (void)renderNotifications {
    UIApplicationState state = [[UIApplication sharedApplication] applicationState];
    if (state == UIApplicationStateBackground || state == UIApplicationStateInactive) {
        return;
    }

    @try {
        NSDictionary *config = GleapConfigHelper.sharedInstance.config;
        if (config == nil) {
            return;
        }

        // Cleanup existing notifications.
        [self.notificationViews removeAllObjects];
        self.notificationsCloseButton = nil;
        self.notificationsContainerHeightConstraint = nil;
        if (_notificationsContainerView != nil) {
            [_notificationsContainerView removeFromSuperview];
            _notificationsContainerView = nil;
        }

        if (self.internalNotifications.count <= 0) {
            return;
        }

        // Any re-render — a new arrival, a config refresh — collapses the
        // stack again.
        self.stackExpanded = NO;

        // Render notification views.
        UIView *window = [self getKeyWindow];
        CGFloat width = (window.frame.size.width * 0.9);
        if (width > 320) {
            width = 320;
        }

        GleapNotificationsContainerView *containerView = [[GleapNotificationsContainerView alloc] initWithFrame: CGRectMake(0, 0, 0, 0)];
        containerView.backgroundColor = [UIColor clearColor];
        containerView.layer.zPosition = INT_MAX;
        containerView.translatesAutoresizingMaskIntoConstraints = NO;
        containerView.clipsToBounds = NO;
        _notificationsContainerView = containerView;
        [window addSubview: _notificationsContainerView];

        // Build the cards oldest → newest, so the newest ends up last — the
        // front card of the stack, and the bottom card of the expanded list.
        for (NSDictionary *notification in self.internalNotifications) {
            UIView *localNotificationView = [self createNotificationViewFor: notification andWith: width];
            if (localNotificationView != nil) {
                localNotificationView.tag = [self.internalNotifications indexOfObject: notification];

                UITapGestureRecognizer *performNotificationActionGesture =
                [[UITapGestureRecognizer alloc] initWithTarget:self
                                                        action:@selector(performNotificationAction:)];
                [localNotificationView addGestureRecognizer: performNotificationActionGesture];

                [_notificationsContainerView addSubview: localNotificationView];
                [self.notificationViews addObject: localNotificationView];
            }
        }

        if (self.notificationViews.count == 0) {
            [_notificationsContainerView removeFromSuperview];
            _notificationsContainerView = nil;
            return;
        }

        // The close button floats over the stack's top-right corner instead of
        // taking a row of its own above it.
        UIView *closeButton = [self generateCloseButton];
        [_notificationsContainerView addSubview: closeButton];
        self.notificationsCloseButton = closeButton;
        containerView.overhangingCloseButton = closeButton;

        [_notificationsContainerView.widthAnchor constraintEqualToConstant: width].active = YES;
        self.notificationsContainerHeightConstraint = [_notificationsContainerView.heightAnchor constraintEqualToConstant: [self stackHeightForWidth: width]];
        self.notificationsContainerHeightConstraint.active = YES;

        int notificationViewOffsetY = [Gleap sharedInstance].notificationViewOffsetY + 20;
        int notificationViewOffsetX = [Gleap sharedInstance].notificationViewOffsetX + 20;

        NSString *feedbackButtonPosition = [config objectForKey: @"feedbackButtonPosition"];
        if ([feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC_LEFT"]) {
            [_notificationsContainerView.bottomAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.bottomAnchor constant: -notificationViewOffsetY].active = YES;
            [_notificationsContainerView.leadingAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.leadingAnchor constant: notificationViewOffsetX].active = YES;
        } else if ([feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC"]) {
            [_notificationsContainerView.bottomAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.bottomAnchor constant: -notificationViewOffsetY].active = YES;
            [_notificationsContainerView.trailingAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.trailingAnchor constant: -notificationViewOffsetX].active = YES;
        } else if ([feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC_BOTTOM"]) {
            [_notificationsContainerView.bottomAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.bottomAnchor constant: -notificationViewOffsetY].active = YES;
            [_notificationsContainerView.trailingAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.trailingAnchor constant: -notificationViewOffsetX].active = YES;
        } else if ([feedbackButtonPosition isEqualToString: @"BOTTOM_LEFT"]) {
            if (self.feedbackButton != nil && self.feedbackButton.isHidden == NO) {
                [_notificationsContainerView.bottomAnchor constraintEqualToAnchor: self.feedbackButton.topAnchor constant: -10].active = YES;
                [_notificationsContainerView.leadingAnchor constraintEqualToAnchor: self.feedbackButton.leadingAnchor constant: 0].active = YES;
            } else {
                [_notificationsContainerView.bottomAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.bottomAnchor constant: -notificationViewOffsetY].active = YES;
                [_notificationsContainerView.leadingAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.leadingAnchor constant: notificationViewOffsetX].active = YES;
            }
        } else if ([feedbackButtonPosition isEqualToString: @"BOTTOM_RIGHT"]) {
            if (self.feedbackButton != nil && self.feedbackButton.isHidden == NO) {
                [_notificationsContainerView.bottomAnchor constraintEqualToAnchor: self.feedbackButton.topAnchor constant: -10].active = YES;
                [_notificationsContainerView.trailingAnchor constraintEqualToAnchor: self.feedbackButton.trailingAnchor constant: 0].active = YES;
            } else {
                [_notificationsContainerView.bottomAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.bottomAnchor constant: -notificationViewOffsetY].active = YES;
                [_notificationsContainerView.trailingAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.trailingAnchor constant: -notificationViewOffsetX].active = YES;
            }
        } else if ([feedbackButtonPosition isEqualToString: @"BUTTON_NONE"]) {
            if (self.feedbackButton != nil && self.feedbackButton.isHidden == NO) {
                [_notificationsContainerView.bottomAnchor constraintEqualToAnchor: self.feedbackButton.topAnchor constant: -10].active = YES;
                [_notificationsContainerView.trailingAnchor constraintEqualToAnchor: self.feedbackButton.trailingAnchor constant: 0].active = YES;
            } else {
                [_notificationsContainerView.bottomAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.bottomAnchor constant: -notificationViewOffsetY].active = YES;
                [_notificationsContainerView.trailingAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.trailingAnchor constant: -notificationViewOffsetX].active = YES;
            }
        }

        [self applyStackLayoutForWidth: width];

        // Only the front card plays the entrance animation — a slide-up with a
        // fade, matching the web widget.
        UIView *frontCard = [self.notificationViews lastObject];
        CGAffineTransform finalTransform = frontCard.transform;
        frontCard.alpha = 0.0;
        frontCard.transform = CGAffineTransformConcat(finalTransform, CGAffineTransformMakeTranslation(0, 12.0));
        [UIView animateWithDuration: 0.45
                              delay: 0.0
                            options: UIViewAnimationOptionCurveEaseOut
                         animations: ^{
            frontCard.alpha = 1.0;
            frontCard.transform = finalTransform;
        } completion: nil];
    } @catch(id anException) {

    }
}

// The container height the current stack state needs: the whole list when
// expanded, the front card plus the peek headroom when collapsed.
- (CGFloat)stackHeightForWidth:(CGFloat)width {
    NSUInteger count = self.notificationViews.count;
    if (count == 0) {
        return 0;
    }

    CGFloat frontHeight = ((UIView *)[self.notificationViews lastObject]).frame.size.height;
    if (count == 1) {
        return frontHeight;
    }

    if ([self isStackCollapsed]) {
        return frontHeight + kGleapNotificationStackHeadroom;
    }

    CGFloat totalHeight = 0;
    for (UIView *cardView in self.notificationViews) {
        totalHeight += cardView.frame.size.height;
    }
    return totalHeight + (kGleapNotificationCardGap * (count - 1));
}

/**
 * Places every card for the current stack state. Cards are bottom-anchored:
 * expanded they form a column with a fixed gap, collapsed the newest card sits
 * in front with up to two older cards peeking out behind its top edge, scaled
 * back like a deck. Anything deeper stays hidden until the stack expands.
 */
- (void)applyStackLayoutForWidth:(CGFloat)width {
    NSUInteger count = self.notificationViews.count;
    if (count == 0) {
        return;
    }

    CGFloat containerHeight = [self stackHeightForWidth: width];
    self.notificationsContainerHeightConstraint.constant = containerHeight;

    BOOL collapsed = [self isStackCollapsed];
    CGFloat frontHeight = ((UIView *)[self.notificationViews lastObject]).frame.size.height;
    CGFloat frontTop = containerHeight - frontHeight;

    // Walk newest → oldest so each card knows its depth behind the front.
    CGFloat expandedBottom = containerHeight;
    for (NSInteger i = count - 1; i >= 0; i--) {
        UIView *cardView = [self.notificationViews objectAtIndex: i];
        CGFloat cardHeight = cardView.frame.size.height;
        NSInteger depth = (count - 1) - i;

        if (collapsed && depth > 0) {
            CGFloat peek = depth == 1 ? kGleapNotificationStackPeek1 : kGleapNotificationStackPeek2;
            CGFloat scale = depth == 1 ? kGleapNotificationStackScale1 : kGleapNotificationStackScale2;

            cardView.transform = CGAffineTransformMakeScale(scale, scale);
            cardView.center = CGPointMake(width / 2.0, (frontTop - peek) + ((cardHeight * scale) / 2.0));
            cardView.alpha = depth > 2 ? 0.0 : 1.0;

            // Clips a taller card behind down to the front card's bottom edge,
            // so e.g. a news cover can't hang out below the stack. The negative
            // insets keep the shadow outside the clipped edge alive.
            CGFloat visibleCardHeight = (frontHeight + peek) / scale;
            if (cardHeight > visibleCardHeight) {
                CALayer *maskLayer = [CALayer layer];
                maskLayer.backgroundColor = [UIColor blackColor].CGColor;
                maskLayer.frame = CGRectMake(-40.0, -40.0, cardView.bounds.size.width + 80.0, visibleCardHeight + 40.0);
                cardView.layer.mask = maskLayer;
            } else {
                cardView.layer.mask = nil;
            }
        } else {
            cardView.transform = CGAffineTransformIdentity;
            cardView.center = CGPointMake(width / 2.0, expandedBottom - (cardHeight / 2.0));
            cardView.alpha = 1.0;
            cardView.layer.mask = nil;
        }

        expandedBottom -= cardHeight + kGleapNotificationCardGap;
    }

    // The close button floats over the container's top corner. It trails the
    // stack in LTR and mirrors to the leading edge in RTL layouts.
    BOOL isRTL = NO;
    if (self.notificationsContainerView != nil) {
        isRTL = [UIView userInterfaceLayoutDirectionForSemanticContentAttribute: self.notificationsContainerView.semanticContentAttribute] == UIUserInterfaceLayoutDirectionRightToLeft;
    }
    CGFloat closeSize = self.notificationsCloseButton.frame.size.width;
    CGFloat closeX = isRTL ? -9.0 : width - closeSize + 9.0;
    self.notificationsCloseButton.frame = CGRectMake(closeX, -9.0, closeSize, closeSize);
}

- (void)setStackExpanded:(BOOL)expanded animated:(BOOL)animated {
    if (self.stackExpanded == expanded || self.notificationViews.count <= 1) {
        return;
    }
    self.stackExpanded = expanded;

    CGFloat width = self.notificationsContainerView.frame.size.width;
    if (width <= 0) {
        width = 320;
    }

    // Release the clip before the spread so nothing pops mid-animation.
    if (expanded) {
        for (UIView *cardView in self.notificationViews) {
            cardView.layer.mask = nil;
        }
    }

    if (!animated || UIAccessibilityIsReduceMotionEnabled()) {
        [self applyStackLayoutForWidth: width];
        [self.notificationsContainerView.superview layoutIfNeeded];
        return;
    }

    [UIView animateWithDuration: 0.3
                          delay: 0.0
                        options: UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations: ^{
        [self applyStackLayoutForWidth: width];
        [self.notificationsContainerView.superview layoutIfNeeded];
    } completion: nil];
}

- (UIView *)generateCloseButton {
    UIColor *backgroundColor = [GleapUIOverlayViewController notificationBackgroundColor];
    UIColor *crossColor = [GleapUIOverlayViewController notificationContrastColor];

    UIView *closeButton = [[UIView alloc] initWithFrame: CGRectMake(0, 0, 26, 26)];
    closeButton.layer.cornerRadius = 13.0;
    closeButton.layer.shadowRadius  = 4.0;
    closeButton.layer.shadowColor   = [UIColor blackColor].CGColor;
    closeButton.layer.shadowOffset  = CGSizeMake(0.0f, 2.0f);
    closeButton.layer.shadowOpacity = 0.18;
    closeButton.autoresizesSubviews = NO;
    closeButton.backgroundColor = backgroundColor;

    UITapGestureRecognizer *clearNotificationsGesture =
      [[UITapGestureRecognizer alloc] initWithTarget:self
                                              action:@selector(clearNotifications:)];
    [closeButton addGestureRecognizer: clearNotificationsGesture];

    UIView * crossLeft = [[UIView alloc] initWithFrame: CGRectMake(0, 0, 11.0, 1.5)];
    crossLeft.backgroundColor = crossColor;
    crossLeft.center = CGPointMake(13.0, 13.0);
    crossLeft.autoresizingMask = UIViewAutoresizingNone;
    crossLeft.layer.cornerRadius = 0.75;
    crossLeft.transform = CGAffineTransformMakeRotation(45 * -1 * M_PI/180);
    [closeButton addSubview: crossLeft];

    UIView * crossRight = [[UIView alloc] initWithFrame: CGRectMake(0, 0, 11.0, 1.5)];
    crossRight.backgroundColor = crossColor;
    crossRight.center = CGPointMake(13.0, 13.0);
    crossRight.autoresizingMask = UIViewAutoresizingNone;
    crossRight.layer.cornerRadius = 0.75;
    crossRight.transform = CGAffineTransformMakeRotation(45 * M_PI/180);
    [closeButton addSubview: crossRight];

    return closeButton;
}

// Every notification card shares one chrome: full container width, the
// project's container radius, a hairline border and a soft two-layer shadow.
// The wrapper carries the large ambient throw (it needs an explicit shadow
// path, being transparent), the card itself the contact shadow.
- (UIView *)styledCardWrapperWithCard:(UIView *)cardView {
    CGFloat containerRadius = [GleapUIOverlayViewController notificationContainerRadius];

    cardView.backgroundColor = [GleapUIOverlayViewController notificationBackgroundColor];
    cardView.layer.cornerRadius = containerRadius;
    cardView.layer.borderWidth = 1.0;
    cardView.layer.borderColor = [GleapUIOverlayViewController notificationHairlineColor].CGColor;
    cardView.layer.shadowRadius = 3.0;
    cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    cardView.layer.shadowOffset = CGSizeMake(0.0, 2.0);
    cardView.layer.shadowOpacity = 0.04;
    cardView.layer.masksToBounds = NO;
    cardView.clipsToBounds = NO;

    UIView *wrapperView = [[UIView alloc] initWithFrame: cardView.frame];
    wrapperView.backgroundColor = [UIColor clearColor];
    wrapperView.layer.shadowRadius = 15.0;
    wrapperView.layer.shadowColor = [UIColor blackColor].CGColor;
    wrapperView.layer.shadowOffset = CGSizeMake(0.0, 10.0);
    wrapperView.layer.shadowOpacity = 0.10;
    wrapperView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect: cardView.bounds cornerRadius: containerRadius].CGPath;
    wrapperView.layer.masksToBounds = NO;
    wrapperView.clipsToBounds = NO;

    CGRect cardFrame = cardView.frame;
    cardFrame.origin = CGPointZero;
    cardView.frame = cardFrame;
    [wrapperView addSubview: cardView];

    return wrapperView;
}

// Sender avatar, or nil when there is no image to show. Teammates stay
// circular and the bot gets a rounded square — the same split the messenger
// makes. `isBot` is absent on payloads from servers that don't send it yet,
// which falls through to the teammate shape.
- (UIImageView *)avatarViewForSender:(NSDictionary *)sender withFrame:(CGRect)frame {
    NSString *profileImageUrl = [sender objectForKey: @"profileImageUrl"];
    if (sender == nil || profileImageUrl == nil || ![profileImageUrl isKindOfClass: [NSString class]] || profileImageUrl.length == 0) {
        return nil;
    }

    BOOL isBot = [sender objectForKey: @"isBot"] != nil && [[sender objectForKey: @"isBot"] boolValue];

    UIImageView *avatarView = [[UIImageView alloc] initWithFrame: frame];
    avatarView.backgroundColor = [[GleapUIOverlayViewController notificationSubTextColor] colorWithAlphaComponent: 0.2];
    if (isBot) {
        avatarView.layer.cornerRadius = [GleapUIOverlayViewController notificationBotAvatarRadiusForSize: frame.size.width];
    } else {
        avatarView.layer.cornerRadius = frame.size.width / 2.0;
    }
    avatarView.contentMode = UIViewContentModeScaleAspectFill;
    avatarView.clipsToBounds = YES;

    dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSData * data = [[NSData alloc] initWithContentsOfURL: [NSURL URLWithString: profileImageUrl]];
        if (data == nil) {
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (avatarView != nil) {
                avatarView.image = [UIImage imageWithData: data];
            }
        });
    });

    return avatarView;
}

- (UIView *)createNotificationViewFor:(NSDictionary *)notification andWith:(int)width {
    NSDictionary *config = GleapConfigHelper.sharedInstance.config;
    if (config == nil) {
        return nil;
    }

    NSDictionary *notificationData = [notification objectForKey: @"data"];
    NSDictionary * sender = [notificationData objectForKey: @"sender"];

    UIColor *contrastColor = [GleapUIOverlayViewController notificationContrastColor];
    UIColor *subTextColor = [GleapUIOverlayViewController notificationSubTextColor];
    CGFloat containerRadius = [GleapUIOverlayViewController notificationContainerRadius];

    NSString *userName = [[GleapSessionHelper sharedInstance] getSessionName];
    NSString *textContent = [notificationData objectForKey: @"text"];
    textContent = [textContent stringByReplacingOccurrencesOfString:@"{{name}}" withString: userName];

    if ([[notificationData objectForKey: @"type"] isEqualToString: @"news"]) {
        CGFloat contentPadding = 16.0;
        CGFloat titleHeight = 21.0;
        CGFloat senderRowHeight = 20.0;
        BOOL hasSender = sender != nil && [sender objectForKey: @"name"] != nil;

        CGFloat cardHeight = 155.0 + contentPadding + titleHeight + contentPadding;
        if (hasSender) {
            cardHeight += 6.0 + senderRowHeight;
        }

        UIView * cardView = [[UIView alloc] initWithFrame: CGRectMake(0.0, 0.0, width, cardHeight)];

        // The cover image squares off against the card's rounded top corners.
        UIImageView * newsImageView = [[UIImageView alloc] initWithFrame: CGRectMake(0.0, 0.0, width, 155.0)];
        newsImageView.backgroundColor = [[GleapUIOverlayViewController notificationSubTextColor] colorWithAlphaComponent: 0.2];
        newsImageView.layer.cornerRadius = containerRadius;
        if (@available(iOS 11.0, *)) {
            newsImageView.layer.maskedCorners = kCALayerMaxXMinYCorner | kCALayerMinXMinYCorner;
        }
        newsImageView.contentMode = UIViewContentModeScaleAspectFill;
        newsImageView.clipsToBounds = YES;
        [cardView addSubview: newsImageView];

        dispatch_async(dispatch_get_global_queue(0,0), ^{
            NSData * data = [[NSData alloc] initWithContentsOfURL: [NSURL URLWithString: [notificationData objectForKey: @"coverImageUrl"]]];
            if (data == nil) {
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (newsImageView != nil) {
                    newsImageView.image = [UIImage imageWithData: data];
                }
            });
        });

        UIFont *contentFont = [UIFont systemFontOfSize: 15 weight: UIFontWeightSemibold];
        UILabel *contentLabel = [[UILabel alloc] initWithFrame: CGRectMake(contentPadding, 155.0 + contentPadding, width - (contentPadding * 2.0), titleHeight)];
        contentLabel.text = textContent;
        contentLabel.font = contentFont;
        contentLabel.adjustsFontSizeToFitWidth = NO;
        contentLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        contentLabel.numberOfLines = 1;
        contentLabel.textColor = contrastColor;
        [cardView addSubview: contentLabel];

        if (hasSender) {
            CGFloat senderRowY = 155.0 + contentPadding + titleHeight + 6.0;
            UIImageView *senderImageView = [self avatarViewForSender: sender withFrame: CGRectMake(contentPadding, senderRowY, 20.0, 20.0)];
            CGFloat senderLabelX = contentPadding;
            if (senderImageView != nil) {
                [cardView addSubview: senderImageView];
                senderLabelX += 20.0 + 8.0;
            }

            UILabel *senderLabel = [[UILabel alloc] initWithFrame: CGRectMake(senderLabelX, senderRowY, width - senderLabelX - contentPadding, senderRowHeight)];
            senderLabel.text = [sender objectForKey: @"name"];
            senderLabel.font = [UIFont systemFontOfSize: 14];
            senderLabel.textColor = subTextColor;
            senderLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            [cardView addSubview: senderLabel];
        }

        return [self styledCardWrapperWithCard: cardView];
    } else if ([[notificationData objectForKey: @"type"] isEqualToString: @"checklist"]) {
        CGFloat contentPadding = 16.0;

        UIView * cardView = [[UIView alloc] initWithFrame: CGRectMake(0.0, 0.0, width, 100.0)];

        UIFont *contentFont = [UIFont systemFontOfSize: 16 weight: UIFontWeightSemibold];
        UILabel *contentLabel = [[UILabel alloc] initWithFrame: CGRectMake(contentPadding, contentPadding, width - (contentPadding * 2.0), 18.0)];
        contentLabel.text = textContent;
        contentLabel.font = contentFont;
        contentLabel.adjustsFontSizeToFitWidth = NO;
        contentLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        contentLabel.numberOfLines = 1;
        contentLabel.textColor = contrastColor;
        [cardView addSubview: contentLabel];

        UILabel *nextStepLabel = [[UILabel alloc] initWithFrame: CGRectMake(contentPadding, 66.0, width - (contentPadding * 2.0), 18.0)];
        nextStepLabel.text = [notificationData objectForKey: @"nextStepTitle"];
        nextStepLabel.adjustsFontSizeToFitWidth = NO;
        nextStepLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        nextStepLabel.numberOfLines = 1;
        nextStepLabel.font = [UIFont systemFontOfSize: 14];
        nextStepLabel.textColor = subTextColor;
        [cardView addSubview: nextStepLabel];

        UIView *progressBarViewBG = [[UIView alloc] initWithFrame: CGRectMake(contentPadding, 46.0, width - (contentPadding * 2.0), 8.0)];
        progressBarViewBG.layer.cornerRadius = 4.0;
        progressBarViewBG.layer.masksToBounds = YES;
        progressBarViewBG.clipsToBounds = YES;
        progressBarViewBG.alpha = 0.15;
        progressBarViewBG.backgroundColor = contrastColor;
        [cardView addSubview: progressBarViewBG];

        int maxWidth = width - (contentPadding * 2.0);
        @try {
            NSNumber *currentStepNumber = [notificationData objectForKey:@"currentStep"];
            NSNumber *totalStepsNumber = [notificationData objectForKey:@"totalSteps"];

            if (currentStepNumber && totalStepsNumber) {
                double currentStep = [currentStepNumber doubleValue];
                double totalSteps = [totalStepsNumber doubleValue];

                double progress = currentStep / totalSteps;
                if (progress < 1.0) {
                    progress += 0.04;
                }
                maxWidth = maxWidth * progress;
            } else {
                maxWidth = maxWidth * 0.04;
            }

        } @catch (id exp) {
            maxWidth = maxWidth * 0.04;
        }

        UIView *progressBarView = [[UIView alloc] initWithFrame: CGRectMake(contentPadding, 46.0, maxWidth, 8.0)];
        progressBarView.layer.cornerRadius = 4.0;
        progressBarView.layer.masksToBounds = YES;
        progressBarView.clipsToBounds = YES;
        progressBarView.alpha = 1;
        NSString *mainColor = [config objectForKey: @"color"];
        if (mainColor != nil && mainColor.length > 0) {
            progressBarView.backgroundColor = [GleapUIHelper colorFromHexString: mainColor];
        } else {
            progressBarView.backgroundColor = contrastColor;
        }
        [cardView addSubview: progressBarView];

        return [self styledCardWrapperWithCard: cardView];
    } else {
        // Standard non-news notification. Avatar and text live inside one card
        // (no speech-bubble tail), with the sender + time as a meta line below
        // the message.
        CGFloat contentPadding = 16.0;
        CGFloat avatarSize = 32.0;

        UIImageView *avatarView = [self avatarViewForSender: sender withFrame: CGRectMake(contentPadding, contentPadding, avatarSize, avatarSize)];

        CGFloat bodyX = contentPadding + (avatarView != nil ? avatarSize + 10.0 : 0.0);
        CGFloat bodyWidth = width - bodyX - contentPadding;

        UIFont *contentFont = [UIFont systemFontOfSize: 15];
        UILabel *contentLabel = [[UILabel alloc] init];
        contentLabel.text = textContent;
        contentLabel.font = contentFont;
        contentLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        contentLabel.numberOfLines = 2;
        contentLabel.textColor = contrastColor;
        CGSize contentSize = [contentLabel sizeThatFits: CGSizeMake(bodyWidth, CGFLOAT_MAX)];
        CGFloat contentHeight = MIN(contentSize.height, contentFont.lineHeight * 2.0 + 2.0);
        contentLabel.frame = CGRectMake(bodyX, contentPadding, bodyWidth, contentHeight);

        // The "Sender · 5 minutes ago" line under the message. Either half may
        // be missing, so the separator only appears when both are present.
        NSString *senderName = sender != nil ? [sender objectForKey: @"name"] : nil;
        NSString *timeLabelText = [GleapUIOverlayViewController relativeTimeLabelForNotification: notification];
        BOOL hasMeta = (senderName != nil && senderName.length > 0) || (timeLabelText != nil && timeLabelText.length > 0);

        CGFloat metaHeight = hasMeta ? 18.0 : 0.0;
        CGFloat metaSpacing = hasMeta ? 5.0 : 0.0;
        CGFloat bodyHeight = contentHeight + metaSpacing + metaHeight;
        CGFloat innerHeight = MAX(avatarView != nil ? avatarSize : 0.0, bodyHeight);
        CGFloat cardHeight = contentPadding + innerHeight + contentPadding;

        UIView * cardView = [[UIView alloc] initWithFrame: CGRectMake(0.0, 0.0, width, cardHeight)];

        if (avatarView != nil) {
            [cardView addSubview: avatarView];
        }
        [cardView addSubview: contentLabel];

        if (hasMeta) {
            CGFloat metaY = contentPadding + contentHeight + metaSpacing;
            CGFloat metaX = bodyX;
            UIFont *metaFont = [UIFont systemFontOfSize: 13];
            UIFont *senderFont = [UIFont systemFontOfSize: 13 weight: UIFontWeightMedium];

            UILabel *timeLabel = nil;
            CGFloat timeWidth = 0;
            if (timeLabelText != nil && timeLabelText.length > 0) {
                timeLabel = [[UILabel alloc] init];
                timeLabel.text = timeLabelText;
                timeLabel.font = metaFont;
                timeLabel.textColor = subTextColor;
                timeWidth = ceil([timeLabel sizeThatFits: CGSizeMake(CGFLOAT_MAX, metaHeight)].width);
            }

            if (senderName != nil && senderName.length > 0) {
                UILabel *senderLabel = [[UILabel alloc] init];
                senderLabel.text = senderName;
                senderLabel.font = senderFont;
                senderLabel.textColor = subTextColor;
                senderLabel.lineBreakMode = NSLineBreakByTruncatingTail;

                // The sender may truncate; the timestamp never does.
                CGFloat dotWidth = timeLabel != nil ? 13.0 : 0.0;
                CGFloat senderMaxWidth = bodyWidth - timeWidth - dotWidth;
                CGFloat senderWidth = MIN(ceil([senderLabel sizeThatFits: CGSizeMake(CGFLOAT_MAX, metaHeight)].width), senderMaxWidth);
                senderLabel.frame = CGRectMake(metaX, metaY, MAX(senderWidth, 0), metaHeight);
                [cardView addSubview: senderLabel];
                metaX += MAX(senderWidth, 0);

                if (timeLabel != nil) {
                    UILabel *dotLabel = [[UILabel alloc] initWithFrame: CGRectMake(metaX, metaY, dotWidth, metaHeight)];
                    dotLabel.text = @"•";
                    dotLabel.font = metaFont;
                    dotLabel.textColor = [subTextColor colorWithAlphaComponent: 0.6];
                    dotLabel.textAlignment = NSTextAlignmentCenter;
                    [cardView addSubview: dotLabel];
                    metaX += dotWidth;
                }
            }

            if (timeLabel != nil) {
                timeLabel.frame = CGRectMake(metaX, metaY, MIN(timeWidth, width - metaX - contentPadding), metaHeight);
                [cardView addSubview: timeLabel];
            }
        }

        return [self styledCardWrapperWithCard: cardView];
    }
}

@end
