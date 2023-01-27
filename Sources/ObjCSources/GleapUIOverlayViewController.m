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

- (void)viewWillAppear:(BOOL)animated {
    [self checkIfUpdateNeeded: NO];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self initializeUI];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return _lastStatusBarStyle;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return _lastOrientation;
}

- (BOOL)shouldAutorotate
{
    return _lastShouldAutoRotate;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    
    if (self.view != nil) {
        self.view.alpha = 0.0;
    }
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        
    } completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        [self updateUI];
        if (self.view != nil) {
            [UIView animateWithDuration:0.3f animations:^{
                self.view.alpha = 1.0;
            }];
        }
    }];
}

- (void)initializeUI {
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.modalPresentationCapturesStatusBarAppearance = NO;
    self.internalNotifications = [[NSMutableArray alloc] init];
    self.notificationViews = [[NSMutableArray alloc] init];
    
    self.closeButton = [[UIView alloc] initWithFrame: CGRectMake(self.view.frame.size.width - 16, 0, 32, 32)];
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
    
    [self.view addSubview: self.closeButton];
    
    // Render feedback button.
    self.feedbackButton = [[GleapFeedbackButton alloc] initWithFrame: CGRectMake(0, 0, 54.0, 54.0)];
    [self.view addSubview: self.feedbackButton];
    
    [self.feedbackButton applyConfig];
    [self.feedbackButton setNotificationCount: 0];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.topMostViewControllerTimer = [NSTimer scheduledTimerWithTimeInterval: 0.4
                                             target: self
                                           selector: @selector(checkIfUpdateNeeded)
                                           userInfo: nil
                                            repeats: YES];
    });
}

- (void)checkIfUpdateNeeded {
    [self checkIfUpdateNeeded: NO];
}

- (BOOL)isModal {
    UIViewController *topMostViewController = [GleapUIHelper getTopMostViewController];
    
    if (topMostViewController != nil) {
        if([topMostViewController presentingViewController]) {
            return YES;        }
        if([[[topMostViewController navigationController] presentingViewController] presentedViewController] == [topMostViewController navigationController]) {
            return YES;
        }
        if([[[topMostViewController tabBarController] presentingViewController] isKindOfClass:[UITabBarController class]]) {
            return YES;
        }
    }

    return NO;
 }

- (BOOL)isModalStyle:(UIViewController *)vc {
    if (
        vc.modalPresentationStyle == UIModalPresentationFormSheet ||
        vc.modalPresentationStyle == UIModalPresentationPageSheet ||
        vc.modalPresentationStyle == UIModalPresentationPopover
    ) {
        return YES;
    }
    
    if (@available(iOS 13.0, *)) {
        if (
            vc.modalPresentationStyle == UIModalPresentationAutomatic
        ) {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)isModal:(UIViewController *)vc {
    if (vc.presentingViewController == nil) {
        return NO;
    }
    
    if(vc.navigationController != nil && [[[vc navigationController] presentingViewController] presentedViewController] == [vc navigationController]) {
        return [self isModalStyle: vc.navigationController];
    }
    
    if(vc.tabBarController != nil) {
        return [self isModalStyle: vc.tabBarController];
    }
    
    return [self isModalStyle: vc];
}

- (UIViewController *)getRotationViewController:(UIViewController *)vc {
    if (vc.presentingViewController == nil) {
        return vc;
    }
    
    if(vc.navigationController != nil && [[[vc navigationController] presentingViewController] presentedViewController] == [vc navigationController]) {
        return vc.navigationController;
    }
    
    if(vc.tabBarController != nil) {
        return vc.tabBarController;
    }
    
    return vc;
}

- (UIViewController *)getNonModalVC:(UIViewController *)vc {
    if (vc.presentingViewController != nil) {
        bool isModal = [self isModal: vc.presentingViewController];
        if (isModal) {
            return [self getNonModalVC: vc.presentingViewController];
        }
        
        return vc.presentingViewController;
    }
    
    return nil;
}

- (void)checkIfUpdateNeeded:(Boolean)isInit {
    UIViewController *topMostViewController = [GleapUIHelper getTopMostViewController];
    if (topMostViewController != nil) {
        bool needsRotationRefresh = NO;
        
        bool isModal = [self isModal: topMostViewController];
        UIInterfaceOrientationMask newOrientation = UIInterfaceOrientationMaskAll;
        UIViewController *rotationViewController = [self getRotationViewController: topMostViewController];
        bool newShouldAutoRotate = YES;
        if (!isModal) {
            newOrientation = rotationViewController.supportedInterfaceOrientations;
            newShouldAutoRotate = rotationViewController.shouldAutorotate;
        } else {
            // Try to get orientation from parent.
            UIViewController * nonModalParent = [self getNonModalVC: rotationViewController];
            if (nonModalParent != nil) {
                newOrientation = nonModalParent.supportedInterfaceOrientations;
                newShouldAutoRotate = nonModalParent.shouldAutorotate;
            }
        }
        if (_lastOrientation != newOrientation) {
            _lastOrientation = newOrientation;
            needsRotationRefresh = YES;
        }
        if (_lastShouldAutoRotate != newShouldAutoRotate) {
            _lastShouldAutoRotate = newShouldAutoRotate;
            needsRotationRefresh = YES;
        }
        
        if (needsRotationRefresh && !isInit) {
            /*if (@available(iOS 16.0, *)) {
                [self setNeedsUpdateOfSupportedInterfaceOrientations];
            }*/
            [UIViewController attemptRotationToDeviceOrientation];
        }
        
        if (!isInit) {
            UIStatusBarStyle newStatusBarStyle = topMostViewController.preferredStatusBarStyle;
            if (newStatusBarStyle == UIStatusBarStyleDefault && isModal) {
                newStatusBarStyle = UIStatusBarStyleLightContent;
            }
            
            if (_lastStatusBarStyle != newStatusBarStyle) {
                _lastStatusBarStyle = newStatusBarStyle;
                [topMostViewController setNeedsStatusBarAppearanceUpdate];
                [self setNeedsStatusBarAppearanceUpdate];
            }
        }
    }
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
        
        [UIView animateWithDuration:0.3f animations:^{
            self.feedbackButton.alpha = 0.0;
        } completion:^(BOOL finished) {
            self.view.hidden = YES;
        }];
    } else {
        if (self.view.hidden) {
            self.feedbackButton.alpha = 0.0;
            [UIView animateWithDuration:0.3f animations:^{
                self.feedbackButton.alpha = 1.0;
            }];
        }
        self.view.hidden = NO;
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
        UIView *notificationView = [self createNotificationViewFor: notification onWindow: self.view];
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
            x = self.view.frame.size.width - notificationView.frame.size.width - buttonX;
            if (@available(iOS 11.0, *)) {
                UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
                if (orientation == UIDeviceOrientationLandscapeRight && window.safeAreaInsets.right && window.safeAreaInsets.right > 0) {
                    x -= window.safeAreaInsets.right;
                }
            }
        }
        lastX = x + notificationView.frame.size.width;
        
        notificationView.frame = CGRectMake(x, self.view.frame.size.height - notificationView.frame.size.height - 20.0 - currentNotificationHeight, notificationView.frame.size.width, notificationView.frame.size.height);
        
        [self.view addSubview: notificationView];
        [self.notificationViews addObject: notificationView];
        
        currentNotificationHeight += notificationView.frame.size.height + 20.0;
    }
    
    if (self.internalNotifications.count > 0) {
        self.closeButton.frame = CGRectMake(lastX - 32.0, self.view.frame.size.height - 44.0 - currentNotificationHeight, self.closeButton.frame.size.width, self.closeButton.frame.size.height);
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
