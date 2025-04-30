//
//  GleapUIOverlayViewController.m
//  
//
//  Created by Lukas Boehler on 11.09.22.
//

#import "GleapUIOverlayViewController.h"
#import "GleapSessionHelper.h"
#import "GleapConfigHelper.h"
#import "Gleap.h"

@interface GleapUIOverlayViewController ()

@end

@implementation GleapUIOverlayViewController

- (UIWindow *)getKeyWindow {
    UIWindow *keyWindow = nil;
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.isKeyWindow) {
            keyWindow = window;
            break;
        }
    }
    return keyWindow;
}

- (void)performNotificationAction:(UITapGestureRecognizer *)sender {
    if (sender == nil || sender.view == nil) {
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
        UIWindow *keyWindow = [self getKeyWindow];
        if (keyWindow != nil) {
            self.internalNotifications = [[NSMutableArray alloc] init];
            self.notificationViews = [[NSMutableArray alloc] init];
            
            // Render feedback button.
            self.feedbackButton = [[GleapFeedbackButton alloc] initWithFrame: CGRectMake(0, 0, 54.0, 54.0)];
            [keyWindow addSubview: self.feedbackButton];
            self.feedbackButton.layer.zPosition = INT_MAX;
            [self.feedbackButton applyConfig];
            [self.feedbackButton setUserInteractionEnabled: YES];
            [self.feedbackButton setNotificationCount: 0];
            
            UITapGestureRecognizer *feedbackButtonGesture =
            [[UITapGestureRecognizer alloc] initWithTarget: self
                                                    action: @selector(feedbackButtonPressed:)];
            [self.feedbackButton addGestureRecognizer: feedbackButtonGesture];
        }
    });
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
    [self.feedbackButton setNotificationCount: notificationCount];
}

- (void)updateUI {
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
        for (UIView *notificationView in self.notificationViews) {
            if (notificationView != nil && notificationView.superview != nil) {
                NSMutableArray *constraintsToRemove = [NSMutableArray array];
                for (NSLayoutConstraint *constraint in notificationView.superview.constraints) {
                    if (constraint.firstItem == self || constraint.secondItem == self) {
                        [constraintsToRemove addObject:constraint];
                    }
                }
                
                [notificationView.superview removeConstraints:constraintsToRemove];
                [notificationView removeConstraints: constraintsToRemove];
            }
        }
        
        [self.notificationViews removeAllObjects];
        if (_notificationsContainerView != nil) {
            [_notificationsContainerView removeFromSuperview];
        }
        
        if (self.internalNotifications.count <= 0) {
            return;
        }
        
        // Render notification views.
        UIView *window = [self getKeyWindow];
        CGFloat width = (window.frame.size.width * 0.9);
        if (width > 320) {
            width = 320;
        }
        
        _notificationsContainerView = [[UIView alloc] initWithFrame: CGRectMake(0, 0, 0, 0)];
        _notificationsContainerView.backgroundColor = [UIColor clearColor];
        _notificationsContainerView.layer.zPosition = INT_MAX;
        _notificationsContainerView.translatesAutoresizingMaskIntoConstraints = NO;
        [window addSubview: _notificationsContainerView];
        
        UIView *previousView = nil;
        
        // Create new notifications.
        for (NSDictionary *notification in self.internalNotifications) {
            UIView *localNotificationView = [self createNotificationViewFor: notification andWith: width];
            if (localNotificationView != nil) {
                localNotificationView.translatesAutoresizingMaskIntoConstraints = NO;
                localNotificationView.tag = [self.internalNotifications indexOfObject:notification];
                
                UITapGestureRecognizer *performNotificationActionGesture =
                [[UITapGestureRecognizer alloc] initWithTarget:self
                                                        action:@selector(performNotificationAction:)];
                [localNotificationView addGestureRecognizer: performNotificationActionGesture];
                
                [_notificationsContainerView addSubview: localNotificationView];
                [self.notificationViews addObject: localNotificationView];
                
                // Set height.
                [localNotificationView.heightAnchor constraintEqualToConstant: localNotificationView.frame.size.height].active = YES;
                
                // Pin to left and right.
                [localNotificationView.leadingAnchor constraintEqualToAnchor: _notificationsContainerView.leadingAnchor constant: 0].active = YES;
                [localNotificationView.trailingAnchor constraintEqualToAnchor: _notificationsContainerView.trailingAnchor constant: 0].active = YES;
                
                if (previousView) {
                    [localNotificationView.bottomAnchor constraintEqualToAnchor: previousView.topAnchor constant: -10.0].active = YES;
                } else {
                    [localNotificationView.bottomAnchor constraintEqualToAnchor: _notificationsContainerView.bottomAnchor constant: 0].active = YES;
                }
                
                previousView = localNotificationView;
            }
        }
        
        // Create close button.
        UIView *closeButton = [self generateCloseButton];
        [_notificationsContainerView addSubview: closeButton];
        
        closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        
        // Set height.
        [closeButton.widthAnchor constraintEqualToConstant: closeButton.frame.size.width].active = YES;
        [closeButton.heightAnchor constraintEqualToConstant: closeButton.frame.size.height].active = YES;
        
        [closeButton.trailingAnchor constraintEqualToAnchor: _notificationsContainerView.trailingAnchor constant: 0].active = YES;
        [closeButton.bottomAnchor constraintEqualToAnchor: previousView.topAnchor constant: -10.0].active = YES;
        
        int containerHeight = (previousView.frame.size.height * self.internalNotifications.count) + (10 * (self.internalNotifications.count - 1)) + closeButton.frame.size.height + 10;
        [_notificationsContainerView.widthAnchor constraintEqualToConstant: width].active = YES;
        [_notificationsContainerView.heightAnchor constraintEqualToConstant: containerHeight].active = YES;
        
        int notificationViewOffsetY = [Gleap sharedInstance].notificationViewOffsetY;
        
        NSString *feedbackButtonPosition = [config objectForKey: @"feedbackButtonPosition"];
        if ([feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC_LEFT"]) {
            [_notificationsContainerView.bottomAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.bottomAnchor constant: -20].active = YES;
            [_notificationsContainerView.leadingAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.leadingAnchor constant: 20].active = YES;
        } else if ([feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC"]) {
            [_notificationsContainerView.bottomAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.bottomAnchor constant: -20].active = YES;
            [_notificationsContainerView.trailingAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.trailingAnchor constant: -20].active = YES;
        } else if ([feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC_BOTTOM"]) {
            [_notificationsContainerView.bottomAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.bottomAnchor constant: -20].active = YES;
            [_notificationsContainerView.trailingAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.trailingAnchor constant: -20].active = YES;
        } else if ([feedbackButtonPosition isEqualToString: @"BOTTOM_LEFT"]) {
            if (self.feedbackButton != nil && self.feedbackButton.isHidden == NO) {
                [_notificationsContainerView.bottomAnchor constraintEqualToAnchor: self.feedbackButton.topAnchor constant: -10].active = YES;
                [_notificationsContainerView.leadingAnchor constraintEqualToAnchor: self.feedbackButton.leadingAnchor constant: 0].active = YES;
            } else {
                [_notificationsContainerView.bottomAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.bottomAnchor constant: -notificationViewOffsetY].active = YES;
                [_notificationsContainerView.leadingAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.leadingAnchor constant: 20].active = YES;
            }
        } else if ([feedbackButtonPosition isEqualToString: @"BOTTOM_RIGHT"]) {
            if (self.feedbackButton != nil && self.feedbackButton.isHidden == NO) {
                [_notificationsContainerView.bottomAnchor constraintEqualToAnchor: self.feedbackButton.topAnchor constant: -10].active = YES;
                [_notificationsContainerView.trailingAnchor constraintEqualToAnchor: self.feedbackButton.trailingAnchor constant: 0].active = YES;
            } else {
                [_notificationsContainerView.bottomAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.bottomAnchor constant: -notificationViewOffsetY].active = YES;
                [_notificationsContainerView.trailingAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.trailingAnchor constant: -20].active = YES;
            }
        } else if ([feedbackButtonPosition isEqualToString: @"BUTTON_NONE"]) {
            if (self.feedbackButton != nil && self.feedbackButton.isHidden == NO) {
                [_notificationsContainerView.bottomAnchor constraintEqualToAnchor: self.feedbackButton.topAnchor constant: -10].active = YES;
                [_notificationsContainerView.trailingAnchor constraintEqualToAnchor: self.feedbackButton.trailingAnchor constant: 0].active = YES;
            } else {
                
                [_notificationsContainerView.bottomAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.bottomAnchor constant: -notificationViewOffsetY].active = YES;
                [_notificationsContainerView.trailingAnchor constraintEqualToAnchor: window.safeAreaLayoutGuide.trailingAnchor constant: -20].active = YES;
            }
        }
        
        _notificationsContainerView.alpha = 0.0;
        [UIView animateWithDuration:0.3f animations:^{
            self.notificationsContainerView.alpha = 1.0;
        }];
    } @catch(id anException) {
        
    }
}

- (UIView *)generateCloseButton {
    UIView *closeButton = [[UIView alloc] initWithFrame: CGRectMake(0, 0, 32, 32)];
    closeButton.layer.cornerRadius = 16;
    closeButton.alpha = 0.8;
    closeButton.layer.cornerRadius = 16.0;
    closeButton.layer.shadowRadius  = 8.0;
    closeButton.layer.shadowColor   = [UIColor blackColor].CGColor;
    closeButton.layer.shadowOffset  = CGSizeMake(2.0f, 2.0f);
    closeButton.layer.shadowOpacity = 0.08;
    closeButton.autoresizesSubviews = NO;
    closeButton.backgroundColor = [UIColor colorWithRed: 0.9 green: 0.9 blue: 0.9 alpha: 1.0];
    
    UITapGestureRecognizer *clearNotificationsGesture =
      [[UITapGestureRecognizer alloc] initWithTarget:self
                                              action:@selector(clearNotifications:)];
    [closeButton addGestureRecognizer: clearNotificationsGesture];
    
    UIView * crossLeft = [[UIView alloc] initWithFrame: CGRectMake(0, 0, 16.0, 2.0)];
    crossLeft.backgroundColor = [UIColor blackColor];
    crossLeft.center = CGPointMake(16.0, 16.0);
    crossLeft.autoresizingMask = UIViewAutoresizingNone;
    crossLeft.transform = CGAffineTransformMakeRotation(45 * -1 * M_PI/180);
    [closeButton addSubview: crossLeft];
    
    UIView * crossRight = [[UIView alloc] initWithFrame: CGRectMake(0, 0, 16.0, 2.0)];
    crossRight.backgroundColor = [UIColor blackColor];
    crossRight.center = CGPointMake(16.0, 16.0);
    crossRight.autoresizingMask = UIViewAutoresizingNone;
    crossRight.transform = CGAffineTransformMakeRotation(45 * M_PI/180);
    [closeButton addSubview: crossRight];
    
    return closeButton;
}

- (UIView *)createNotificationViewFor:(NSDictionary *)notification andWith:(int)width {
    NSDictionary *config = GleapConfigHelper.sharedInstance.config;
    if (config == nil) {
        return nil;
    }
    
    NSDictionary *notificationData = [notification objectForKey: @"data"];
    NSDictionary * sender = [notificationData objectForKey: @"sender"];
    
    CGFloat chatBubbleViewWidth = width - 48.0;
    
    NSString *userName = [[GleapSessionHelper sharedInstance] getSessionName];
    NSString *textContent = [notificationData objectForKey: @"text"];
    textContent = [textContent stringByReplacingOccurrencesOfString:@"{{name}}" withString: userName];
    
    if ([[notificationData objectForKey: @"type"] isEqualToString: @"news"]) {
        // Build the chat message.
        UIView * chatBubbleView = [[UIView alloc] initWithFrame: CGRectMake(0.0, 0.0, width, 235.0)];
        chatBubbleView.layer.cornerRadius = 8.0;
        chatBubbleView.layer.shadowRadius  = 8.0;
        chatBubbleView.layer.shadowColor   = [UIColor blackColor].CGColor;
        chatBubbleView.layer.shadowOffset  = CGSizeMake(3.0f, 3.0f);
        chatBubbleView.layer.shadowOpacity = 0.1;
        chatBubbleView.layer.masksToBounds = NO;
        chatBubbleView.clipsToBounds = NO;
        if (@available(iOS 13.0, *)) {
            chatBubbleView.backgroundColor = [UIColor systemBackgroundColor];
        } else {
            chatBubbleView.backgroundColor = [UIColor whiteColor];
        }
        
        // Build the news message.
        UIImageView * newsImageView = [[UIImageView alloc] initWithFrame: CGRectMake(0.0, 0.0, chatBubbleView.frame.size.width, 155.0)];
        newsImageView.backgroundColor = [UIColor grayColor];
        newsImageView.layer.cornerRadius = 8.0;
        if (@available(iOS 11.0, *)) {
            newsImageView.layer.maskedCorners = kCALayerMaxXMinYCorner | kCALayerMinXMinYCorner;
        }
        newsImageView.contentMode = UIViewContentModeScaleAspectFill;
        newsImageView.clipsToBounds = YES;
        [chatBubbleView addSubview: newsImageView];
        
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
        
        UIFont *contentFont = [UIFont systemFontOfSize: 16 weight: UIFontWeightSemibold];
        UILabel *contentLabel = [[UILabel alloc] initWithFrame: CGRectMake(16.0, 171.0, chatBubbleView.frame.size.width - 32.0, 18.0)];
        contentLabel.text = textContent;
        contentLabel.font = contentFont;
        contentLabel.adjustsFontSizeToFitWidth = NO;
        contentLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        contentLabel.numberOfLines = 1;
        if (@available(iOS 13.0, *)) {
            contentLabel.textColor = [UIColor labelColor];
        } else {
            contentLabel.textColor = [UIColor blackColor];
        }
        
        [chatBubbleView addSubview: contentLabel];
        
        UIImageView * senderImageView = [[UIImageView alloc] initWithFrame: CGRectMake(16.0, 195.0, 22.0, 22.0)];
        senderImageView.backgroundColor = [UIColor grayColor];
        senderImageView.layer.cornerRadius = 11.0;
        senderImageView.contentMode = UIViewContentModeScaleAspectFill;
        senderImageView.clipsToBounds = YES;
        [chatBubbleView addSubview: senderImageView];
        
        dispatch_async(dispatch_get_global_queue(0,0), ^{
            NSData * data = [[NSData alloc] initWithContentsOfURL: [NSURL URLWithString: [sender objectForKey: @"profileImageUrl"]]];
            if (data == nil) {
                return;
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (senderImageView != nil) {
                    senderImageView.image = [UIImage imageWithData: data];
                }
            });
        });
        
        UILabel *senderLabel = [[UILabel alloc] initWithFrame: CGRectMake(43.0, 195.0, chatBubbleView.frame.size.width - 43.0 - 16.0, 22.0)];
        senderLabel.text = [sender objectForKey: @"name"];
        senderLabel.font = [UIFont systemFontOfSize: 14];
        senderLabel.alpha = 0.5;
        if (@available(iOS 13.0, *)) {
            senderLabel.textColor = [UIColor labelColor];
        } else {
            senderLabel.textColor = [UIColor blackColor];
        }
        [chatBubbleView addSubview: senderLabel];
        
        UIView * _notificationsContainerView = [[UIView alloc] initWithFrame: CGRectMake(0.0, 0, width, chatBubbleView.frame.size.height)];
        
        [_notificationsContainerView addSubview: chatBubbleView];
        
        return _notificationsContainerView;
    } else if ([[notificationData objectForKey: @"type"] isEqualToString: @"checklist"]) {
        // Build the chat message.
        UIView * chatBubbleView = [[UIView alloc] initWithFrame: CGRectMake(0.0, 0.0, width, 100.0)];
        chatBubbleView.layer.cornerRadius = 8.0;
        chatBubbleView.layer.shadowRadius  = 8.0;
        chatBubbleView.layer.shadowColor   = [UIColor blackColor].CGColor;
        chatBubbleView.layer.shadowOffset  = CGSizeMake(3.0f, 3.0f);
        chatBubbleView.layer.shadowOpacity = 0.1;
        chatBubbleView.layer.masksToBounds = NO;
        chatBubbleView.clipsToBounds = NO;
        if (@available(iOS 13.0, *)) {
            chatBubbleView.backgroundColor = [UIColor systemBackgroundColor];
        } else {
            chatBubbleView.backgroundColor = [UIColor whiteColor];
        }
        
        UIFont *contentFont = [UIFont systemFontOfSize: 16 weight: UIFontWeightSemibold];
        UILabel *contentLabel = [[UILabel alloc] initWithFrame: CGRectMake(16.0, 16.0, chatBubbleView.frame.size.width - 32.0, 18.0)];
        contentLabel.text = textContent;
        contentLabel.font = contentFont;
        contentLabel.adjustsFontSizeToFitWidth = NO;
        contentLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        contentLabel.numberOfLines = 1;
        if (@available(iOS 13.0, *)) {
            contentLabel.textColor = [UIColor labelColor];
        } else {
            contentLabel.textColor = [UIColor blackColor];
        }
        
        [chatBubbleView addSubview: contentLabel];
        
        UILabel *nextStepLabel = [[UILabel alloc] initWithFrame: CGRectMake(16.0, 66.0, chatBubbleView.frame.size.width - 32.0, 18.0)];
        nextStepLabel.text = [notificationData objectForKey: @"nextStepTitle"];
        nextStepLabel.adjustsFontSizeToFitWidth = NO;
        nextStepLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        nextStepLabel.numberOfLines = 1;
        nextStepLabel.font = [UIFont systemFontOfSize: 14];
        nextStepLabel.alpha = 0.5;
        if (@available(iOS 13.0, *)) {
            nextStepLabel.textColor = [UIColor labelColor];
        } else {
            nextStepLabel.textColor = [UIColor blackColor];
        }
        
        [chatBubbleView addSubview: nextStepLabel];
        
        UIView *progressBarViewBG = [[UIView alloc] initWithFrame: CGRectMake(16.0, 46.0, chatBubbleView.frame.size.width - 32.0, 8.0)];
        progressBarViewBG.layer.cornerRadius = 4.0;
        progressBarViewBG.layer.masksToBounds = YES;
        progressBarViewBG.clipsToBounds = YES;
        progressBarViewBG.alpha = 0.15;
        if (@available(iOS 13.0, *)) {
            progressBarViewBG.backgroundColor = [UIColor labelColor];
        } else {
            progressBarViewBG.backgroundColor = [UIColor blackColor];
        }
        [chatBubbleView addSubview: progressBarViewBG];
        
        int maxWidth = chatBubbleView.frame.size.width - 32.0;
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

        UIView *progressBarView = [[UIView alloc] initWithFrame: CGRectMake(16.0, 46.0, maxWidth, 8.0)];
        progressBarView.layer.cornerRadius = 4.0;
        progressBarView.layer.masksToBounds = YES;
        progressBarView.clipsToBounds = YES;
        progressBarView.alpha = 1;
        NSString *mainColor = [config objectForKey: @"color"];
        if (mainColor != nil && mainColor.length > 0) {
            progressBarView.backgroundColor = [GleapUIHelper colorFromHexString: mainColor];
        } else {
            progressBarView.backgroundColor = [UIColor blackColor];
        }
        [chatBubbleView addSubview: progressBarView];
        
        UIView * _notificationsContainerView = [[UIView alloc] initWithFrame: CGRectMake(0.0, 0, width, chatBubbleView.frame.size.height)];
        
        [_notificationsContainerView addSubview: chatBubbleView];
        
        return _notificationsContainerView;
    } else {
        // Build the chat message.
        UIFont *contentFont = [UIFont systemFontOfSize: 16];
        CGSize contentLabelSize = [textContent boundingRectWithSize:CGSizeMake(chatBubbleViewWidth - 32, 39.0)
                                                          options:NSStringDrawingUsesLineFragmentOrigin
                                                       attributes:@{
                                                                    NSFontAttributeName : contentFont
                                                                    }
                                                          context:nil].size;
        
        UIView * chatBubbleView = [[UIView alloc] initWithFrame: CGRectMake(48.0, 0.0, chatBubbleViewWidth, 52.0 + contentLabelSize.height)];
        chatBubbleView.layer.cornerRadius = 8.0;
        chatBubbleView.layer.shadowRadius  = 8.0;
        chatBubbleView.layer.shadowColor   = [UIColor blackColor].CGColor;
        chatBubbleView.layer.shadowOffset  = CGSizeMake(3.0f, 3.0f);
        chatBubbleView.layer.shadowOpacity = 0.12;
        chatBubbleView.layer.masksToBounds = NO;
        chatBubbleView.clipsToBounds = NO;
        chatBubbleView.alpha = 0.0;
        if (@available(iOS 13.0, *)) {
            chatBubbleView.backgroundColor = [UIColor systemBackgroundColor];
        } else {
            chatBubbleView.backgroundColor = [UIColor whiteColor];
        }
        
        UIView * senderOuterImageView = [[UIView alloc] initWithFrame: CGRectMake(0.0, 8.0, 36.0, 36.0)];
        senderOuterImageView.layer.cornerRadius = 18.0;
        senderOuterImageView.layer.shadowRadius  = 8.0;
        senderOuterImageView.layer.shadowColor   = [UIColor blackColor].CGColor;
        senderOuterImageView.layer.shadowOffset  = CGSizeMake(0.0f, 0.0f);
        senderOuterImageView.layer.shadowOpacity = 0.15;
        senderOuterImageView.layer.masksToBounds = NO;
        senderOuterImageView.clipsToBounds = NO;
        
        UIImageView * senderImageView = [[UIImageView alloc] initWithFrame: CGRectMake(0.0, 0.0, 36.0, 36.0)];
        senderImageView.backgroundColor = [UIColor grayColor];
        senderImageView.layer.cornerRadius = 18.0;
        senderImageView.contentMode = UIViewContentModeScaleAspectFill;
        senderImageView.clipsToBounds = YES;
        [senderOuterImageView addSubview: senderImageView];
        
        dispatch_async(dispatch_get_global_queue(0,0), ^{
            NSData * data = [[NSData alloc] initWithContentsOfURL: [NSURL URLWithString: [sender objectForKey: @"profileImageUrl"]]];
            if (data == nil) {
                return;
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (senderImageView != nil) {
                    senderImageView.image = [UIImage imageWithData: data];
                }
                [UIView animateWithDuration:0.3f animations:^{
                    chatBubbleView.alpha = 1.0;
                }];
            });
        });
        
        UILabel *senderLabel = [[UILabel alloc] initWithFrame: CGRectMake(16, 16, chatBubbleView.frame.size.width - 32, 14)];
        senderLabel.text = [sender objectForKey: @"name"];
        senderLabel.font = [UIFont systemFontOfSize: 14];
        senderLabel.alpha = 0.5;
        if (@available(iOS 13.0, *)) {
            senderLabel.textColor = [UIColor labelColor];
        } else {
            senderLabel.textColor = [UIColor blackColor];
        }
        [chatBubbleView addSubview: senderLabel];
        
        UILabel *contentLabel = [[UILabel alloc] initWithFrame: CGRectMake(16, 36, chatBubbleView.frame.size.width - 32, contentLabelSize.height)];
        contentLabel.text = textContent;
        contentLabel.font = contentFont;
        contentLabel.lineBreakMode = NSLineBreakByWordWrapping;
        contentLabel.numberOfLines = 2;
        if (@available(iOS 13.0, *)) {
            senderLabel.textColor = [UIColor labelColor];
        } else {
            senderLabel.textColor = [UIColor blackColor];
        }
        
        [chatBubbleView addSubview: contentLabel];
        
        UIView * _notificationsContainerView = [[UIView alloc] initWithFrame: CGRectMake(0.0, 0, width, chatBubbleView.frame.size.height)];
        
        [_notificationsContainerView addSubview: chatBubbleView];
        [_notificationsContainerView addSubview: senderOuterImageView];
        
        return _notificationsContainerView;
    }
}

-(void)calculateHeightForLabel:(UILabel *)label {
    CGSize constraint = CGSizeMake(label.frame.size.width, CGFLOAT_MAX);
    CGSize size;
    NSStringDrawingContext *context = [[NSStringDrawingContext alloc] init];
    CGSize boundingBox = [label.text boundingRectWithSize:constraint    options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: label.font}
                                            context:context].size;
    size = CGSizeMake(ceil(boundingBox.width), ceil(boundingBox.height));
    label.frame = CGRectMake(label.frame.origin.x, label.frame.origin.y, label.frame.size.width, size.height);
}

@end
