//
//  GleapUIOverlayViewController.m
//
//
//  Created by Lukas Boehler on 11.09.22.
//

#import "GleapUIOverlayViewController.h"
#import "GleapUIOverlayViewController+Internal.h"
#import "GleapNotificationCardFactory.h"
#import "GleapSessionHelper.h"
#import "GleapConfigHelper.h"
#import "GleapTranslationHelper.h"
#import "GleapWindowChecker.h"
#import "Gleap.h"

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
    if (tag < 0 || tag >= (long)self.internalNotifications.count) {
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
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(keyWindowMayHaveChanged:)
                                                     name: UISceneDidActivateNotification
                                                   object: nil];
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

#pragma mark - Rendering

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
            self.lastRenderedNotificationCount = 0;
            self.lastRenderedFrontOutboundId = nil;
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
            UIView *localNotificationView = [GleapNotificationCardFactory createNotificationViewFor: notification andWith: width];
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
        UIView *closeButton = [GleapNotificationCardFactory closeButtonWithTarget: self action: @selector(clearNotifications:)];
        [_notificationsContainerView addSubview: closeButton];
        self.notificationsCloseButton = closeButton;
        containerView.overhangingCloseButton = closeButton;

        [_notificationsContainerView.widthAnchor constraintEqualToConstant: width].active = YES;
        // The container keeps one FIXED height, tall enough for any stack.
        // Resizing it per state re-anchored the bottom-pinned cards while
        // animations were in flight — the whole deck rendered offset by the
        // height delta and visibly slid into place. With a constant height
        // nothing ever re-bases; only the card animations move cards. Empty
        // space passes touches through (see GleapNotificationsContainerView).
        CGFloat stackFrameHeight = MAX(window.bounds.size.height, 900.0);
        self.notificationsContainerHeightConstraint = [_notificationsContainerView.heightAnchor constraintEqualToConstant: stackFrameHeight];
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

        // A render happens for lifecycle events too (key window changes,
        // config refreshes) — only a genuinely new notification animates in.
        // The cap can hold the count steady while the front card changes, so
        // the front outbound id breaks that tie.
        NSString *frontOutboundId = nil;
        @try {
            id outboundValue = [[self.internalNotifications lastObject] objectForKey: @"outbound"];
            if (outboundValue != nil && [outboundValue isKindOfClass: [NSString class]]) {
                frontOutboundId = outboundValue;
            }
        } @catch (id exp) {}

        NSUInteger cardCount = self.notificationViews.count;
        BOOL isNewArrival = cardCount > self.lastRenderedNotificationCount
            || (self.lastRenderedNotificationCount > 0 && frontOutboundId != nil && ![frontOutboundId isEqualToString: self.lastRenderedFrontOutboundId]);
        self.lastRenderedNotificationCount = cardCount;
        self.lastRenderedFrontOutboundId = frontOutboundId;

        if (isNewArrival && !UIAccessibilityIsReduceMotionEnabled()) {
            if (cardCount == 1) {
                // The very first notification materializes in place — fade
                // plus a slight scale-up, no travel.
                UIView *frontCard = [self.notificationViews lastObject];
                CGAffineTransform finalTransform = frontCard.transform;
                frontCard.alpha = 0.0;
                frontCard.transform = CGAffineTransformConcat(finalTransform, CGAffineTransformMakeScale(0.97, 0.97));
                [UIView animateWithDuration: 0.35
                                      delay: 0.0
                                    options: UIViewAnimationOptionCurveEaseOut
                                 animations: ^{
                    frontCard.alpha = 1.0;
                    frontCard.transform = finalTransform;
                } completion: nil];
            } else {
                [self animateArrivalForWidth: width];
            }
        }
    } @catch(id anException) {

    }
}

@end
