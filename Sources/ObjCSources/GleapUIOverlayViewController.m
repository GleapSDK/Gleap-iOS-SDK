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

- (void)clearNotifications:(UITapGestureRecognizer *)sender {
    [GleapUIOverlayHelper clear];
}

- (void)feedbackButtonPressed:(UITapGestureRecognizer *)sender {
    [Gleap open];
}

- (void)initializeUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [self getKeyWindow];
        self.internalNotifications = [[NSMutableArray alloc] init];
        self.notificationViews = [[NSMutableArray alloc] init];
        
        self.closeButton = [[UIView alloc] initWithFrame: CGRectMake(0, 0, 32, 32)];
        self.closeButton.layer.cornerRadius = 16;
        self.closeButton.hidden = YES;
        self.closeButton.alpha = 0.8;
        self.closeButton.layer.cornerRadius = 16.0;
        self.closeButton.layer.shadowRadius  = 8.0;
        self.closeButton.layer.shadowColor   = [UIColor blackColor].CGColor;
        self.closeButton.layer.shadowOffset  = CGSizeMake(2.0f, 2.0f);
        self.closeButton.layer.shadowOpacity = 0.08;
        self.closeButton.autoresizesSubviews = NO;
        self.closeButton.backgroundColor = [UIColor colorWithRed: 0.9 green: 0.9 blue: 0.9 alpha: 1.0];
        self.closeButton.tag = 999;
        self.closeButton.layer.zPosition = INT_MAX;
        UITapGestureRecognizer *clearNotificationsGesture =
          [[UITapGestureRecognizer alloc] initWithTarget:self
                                                  action:@selector(clearNotifications:)];
        [self.closeButton addGestureRecognizer: clearNotificationsGesture];
        
        UIView * crossLeft = [[UIView alloc] initWithFrame: CGRectMake(0, 0, 16.0, 2.0)];
        crossLeft.backgroundColor = [UIColor blackColor];
        crossLeft.center = CGPointMake(16.0, 16.0);
        crossLeft.autoresizingMask = UIViewAutoresizingNone;
        crossLeft.transform = CGAffineTransformMakeRotation(45 * -1 * M_PI/180);
        [self.closeButton addSubview: crossLeft];
        
        UIView * crossRight = [[UIView alloc] initWithFrame: CGRectMake(0, 0, 16.0, 2.0)];
        crossRight.backgroundColor = [UIColor blackColor];
        crossRight.center = CGPointMake(16.0, 16.0);
        crossRight.autoresizingMask = UIViewAutoresizingNone;
        crossRight.transform = CGAffineTransformMakeRotation(45 * M_PI/180);
        [self.closeButton addSubview: crossRight];
        
        [keyWindow addSubview: self.closeButton];
        
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
    });
    
}

- (void)showBanner:(NSDictionary *)bannerData {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.banner != nil) {
            [self.banner removeFromSuperview];
            self.banner = nil;
        }
        
        self.banner = [[GleapBanner alloc] initWithFrame: CGRectMake(0, 0, [self getKeyWindow].frame.size.width, 70.0)];
        [[self getKeyWindow] addSubview: self.banner];
        
        NSLayoutConstraint *trailing = [NSLayoutConstraint
                                        constraintWithItem: self.banner
                                        attribute: NSLayoutAttributeTrailing
                                        relatedBy: NSLayoutRelationEqual
                                        toItem: [self getKeyWindow]
                                        attribute: NSLayoutAttributeTrailing
                                        multiplier: 1.0f
                                        constant: 0.f];
        NSLayoutConstraint *leading = [NSLayoutConstraint
                                       constraintWithItem: self.banner
                                       attribute: NSLayoutAttributeLeading
                                       relatedBy: NSLayoutRelationEqual
                                       toItem: [self getKeyWindow]
                                       attribute: NSLayoutAttributeLeading
                                       multiplier: 1.0f
                                       constant: 0.f];
        [[self getKeyWindow] addConstraint: leading];
        [[self getKeyWindow] addConstraint: trailing];
        
        NSLayoutConstraint *top =[NSLayoutConstraint
                                  constraintWithItem: self.banner
                                  attribute: NSLayoutAttributeTop
                                  relatedBy: NSLayoutRelationEqual
                                  toItem: [self getKeyWindow]
                                  attribute: NSLayoutAttributeTop
                                  multiplier: 1.0f
                                  constant: 0.f];
        [[self getKeyWindow] addConstraint: top];
        
        [self.banner setupWithData: bannerData];
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
        if ([feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC_LEFT"] || [feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC"]) {
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
        } completion:^(BOOL finished) {
            [self.feedbackButton setUserInteractionEnabled: NO];
            if (self.banner != nil) {
                [self.banner setUserInteractionEnabled: NO];
            }
        }];
    } else {
        [UIView animateWithDuration:0.3f animations:^{
            self.feedbackButton.alpha = 1.0;
            if (self.banner != nil) {
                self.banner.alpha = 1.0;
            }
        } completion:^(BOOL finished) {
            [self.feedbackButton setUserInteractionEnabled: YES];
            if (self.banner != nil) {
                [self.banner setUserInteractionEnabled: YES];
            }
        }];
    }
    
    [self.feedbackButton applyConfig];
    [self renderNotifications];
}

- (void)renderNotifications {
    self.closeButton.hidden = YES;
    NSDictionary *config = GleapConfigHelper.sharedInstance.config;
    if (config == nil) {
        return;
    }
    
    NSString *feedbackButtonPosition = [config objectForKey: @"feedbackButtonPosition"];
    CGFloat currentNotificationHeight = [[GleapConfigHelper sharedInstance] getButtonY];
    if (@available(iOS 11.0, *)) {
        UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
        currentNotificationHeight += window.safeAreaInsets.bottom;
    }
    
    if (!self.feedbackButton.isHidden) {
        if ([feedbackButtonPosition containsString: @"CLASSIC"]) {
            if ([feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC_BOTTOM"]) {
                currentNotificationHeight += 20.0;
            }
        } else {
            currentNotificationHeight += self.feedbackButton.frame.size.height;
        }
    }
    
    // Cleanup existing notifications.
    for (int i = 0; i < self.notificationViews.count; i++) {
        [[self.notificationViews objectAtIndex: i] removeFromSuperview];
    }
    
    int buttonX = [[GleapConfigHelper sharedInstance] getButtonX];
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    
    float lastX = 0;
    // Create new notifications.
    for (int i = 0; i < self.internalNotifications.count; i++) {
        NSDictionary * notification = [self.internalNotifications objectAtIndex: i];
        UIView *notificationView = [self createNotificationViewFor: notification onWindow: [self getKeyWindow]];
        notificationView.tag = i;
        
        float x = 0;
        if (
            [feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC_LEFT"] ||
            [feedbackButtonPosition isEqualToString: @"BOTTOM_LEFT"]
        ) {
            x = buttonX;
            
            if (@available(iOS 11.0, *)) {
                UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
                if (orientation == UIDeviceOrientationLandscapeLeft && window.safeAreaInsets.left && window.safeAreaInsets.left > 0) {
                    x += window.safeAreaInsets.left;
                }
            }
        } else {
            x = [self getKeyWindow].frame.size.width - notificationView.frame.size.width - buttonX;
            if (@available(iOS 11.0, *)) {
                UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
                if (orientation == UIDeviceOrientationLandscapeRight && window.safeAreaInsets.right && window.safeAreaInsets.right > 0) {
                    x -= window.safeAreaInsets.right;
                }
            }
        }
        lastX = x + notificationView.frame.size.width;
        
        notificationView.frame = CGRectMake(x, [self getKeyWindow].frame.size.height - notificationView.frame.size.height - 20.0 - currentNotificationHeight, notificationView.frame.size.width, notificationView.frame.size.height);
        
        [[self getKeyWindow] addSubview: notificationView];
        [self.notificationViews addObject: notificationView];
        
        currentNotificationHeight += notificationView.frame.size.height + 20.0;
    }
    
    if (self.internalNotifications.count > 0) {
        self.closeButton.frame = CGRectMake(lastX - 32.0, [self getKeyWindow].frame.size.height - 44.0 - currentNotificationHeight, self.closeButton.frame.size.width, self.closeButton.frame.size.height);
        self.closeButton.hidden = NO;
        self.closeButton.alpha = 0.0;
        
        [UIView animateWithDuration: 2.0f animations:^{
            self.closeButton.alpha = 1.0;
        } completion:^(BOOL finished) {}];
    }
}

- (UIView *)createNotificationViewFor:(NSDictionary *)notification onWindow:(UIView *)view {
    NSDictionary *notificationData = [notification objectForKey: @"data"];
    NSDictionary * sender = [notificationData objectForKey: @"sender"];
    
    CGFloat width = (view.frame.size.width * 0.9);
    if (width > 320) {
        width = 320;
    }
    
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
        chatBubbleView.alpha = 0.0;
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
                [UIView animateWithDuration:0.3f animations:^{
                    chatBubbleView.alpha = 1.0;
                }];
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
        
        UIView * containerView = [[UIView alloc] initWithFrame: CGRectMake(0.0, 0, width, chatBubbleView.frame.size.height)];
        
        [containerView addSubview: chatBubbleView];
        
        return containerView;
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
        
        UIView * containerView = [[UIView alloc] initWithFrame: CGRectMake(0.0, 0, width, chatBubbleView.frame.size.height)];
        
        [containerView addSubview: chatBubbleView];
        [containerView addSubview: senderOuterImageView];
        
        return containerView;
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
