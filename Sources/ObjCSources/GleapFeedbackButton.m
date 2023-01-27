//
//  GleapFeedbackButton.m
//  
//
//  Created by Lukas Boehler on 09.09.22.
//

#import "GleapFeedbackButton.h"
#import "GleapConfigHelper.h"
#import "GleapNotificationHelper.h"
#import "GleapUIHelper.h"
#import "Gleap.h"

const double BUTTON_SIZE = 56.0;
const float NOTIFICATION_BADGE_SIZE = 22.0;

@implementation GleapFeedbackButton

- (id)initWithFrame:(CGRect)aRect
{
    if ((self = [super initWithFrame:aRect])) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.autoresizingMask = UIViewAutoresizingNone;
    
    float padding = (BUTTON_SIZE - (BUTTON_SIZE * 0.64)) / 2.0;
    self.logoView = [[UIImageView alloc] initWithFrame: CGRectMake(padding, padding, BUTTON_SIZE - (padding * 2), BUTTON_SIZE - (padding * 2))];
    self.logoView.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview: self.logoView];
    
    self.buttonTextLabel = [[UILabel alloc] initWithFrame: CGRectMake(0, 0, self.frame.size.width, self.frame.size.height)];
    self.buttonTextLabel.font = [UIFont systemFontOfSize: 15 weight: UIFontWeightMedium];
    self.buttonTextLabel.textColor = [UIColor whiteColor];
    [self addSubview: self.buttonTextLabel];
    
    self.tag = INT_MAX;
    
    self.notificationBadgeView = [[UIView alloc] initWithFrame: CGRectMake(self.frame.size.width - (NOTIFICATION_BADGE_SIZE - 5.0), -5.0, NOTIFICATION_BADGE_SIZE, NOTIFICATION_BADGE_SIZE)];
    self.notificationBadgeView.backgroundColor = [UIColor redColor];
    self.notificationBadgeView.layer.cornerRadius = NOTIFICATION_BADGE_SIZE / 2.0;
    [self addSubview: self.notificationBadgeView];
    self.notificationBadgeView.hidden = YES;
    
    self.notificationBadgeLabel = [[UILabel alloc] initWithFrame: CGRectMake(0, 0, NOTIFICATION_BADGE_SIZE, NOTIFICATION_BADGE_SIZE)];
    self.notificationBadgeLabel.font = [UIFont systemFontOfSize: 11 weight: UIFontWeightBold];
    self.notificationBadgeLabel.textColor = [UIColor whiteColor];
    self.notificationBadgeLabel.textAlignment = NSTextAlignmentCenter;
    [self.notificationBadgeView addSubview: self.notificationBadgeLabel];
}

- (void)setNotificationCount:(int)notificationCount {
    if (notificationCount > 0) {
        self.notificationBadgeView.hidden = NO;
        if (notificationCount > 9) {
            self.notificationBadgeLabel.text = @"9+";
        } else {
            self.notificationBadgeLabel.text = [NSString stringWithFormat:@"%d", notificationCount];
        }
    } else {
        self.notificationBadgeView.hidden = YES;
    }
}

- (void)applyConfig {
    NSDictionary *config = GleapConfigHelper.sharedInstance.config;
    if (config == nil) {
        self.hidden = YES;
        return;
    }
    
    if (![GleapNotificationHelper sharedInstance].showButton) {
        self.hidden = YES;
        return;
    } else {
        self.hidden = NO;
    }
    
    self.layer.shadowRadius  = 6.0;
    self.layer.shadowColor   = [UIColor blackColor].CGColor;
    self.layer.shadowOffset  = CGSizeMake(0.0f, 0.0f);
    self.layer.shadowOpacity = 0.2;
    self.layer.masksToBounds = NO;
    self.clipsToBounds = NO;
    
    NSString *feedbackButtonPosition = [config objectForKey: @"feedbackButtonPosition"];
    NSString *buttonColor = [config objectForKey: @"buttonColor"];
    if (buttonColor != nil && buttonColor.length > 0) {
        self.backgroundColor = [GleapUIHelper colorFromHexString: buttonColor];
    } else {
        self.backgroundColor = [GleapUIHelper colorFromHexString: @"#485bff"];
    }
    
    if ([feedbackButtonPosition containsString: @"CLASSIC"]) {
        [self setupClassicButton];
    } else {
        [self setupModernButton];
    }
}

- (void)setupClassicButton {
    NSDictionary *config = GleapConfigHelper.sharedInstance.config;
    if (config == nil) {
        self.hidden = YES;
        return;
    }
    
    self.transform = CGAffineTransformIdentity;
    self.notificationBadgeView.transform = CGAffineTransformIdentity;
    self.logoView.hidden = YES;
    
    NSString *widgetButtonText = [GleapTranslationHelper localizedString: [config objectForKey: @"widgetButtonText"]];
    NSString *feedbackButtonPosition = [config objectForKey: @"feedbackButtonPosition"];
    
    self.layer.cornerRadius = 8.0;
    if (@available(iOS 11.0, *)) {
        self.layer.maskedCorners = kCALayerMaxXMinYCorner | kCALayerMinXMinYCorner;
    }
    
    self.buttonTextLabel.text = widgetButtonText;
    [self.buttonTextLabel setTextAlignment: NSTextAlignmentCenter];
    
    UIFont *feedbackButtonFont = [UIFont systemFontOfSize: 15 weight: UIFontWeightMedium];
    
    int buttonHeight = 42;
    CGSize frameSize = CGSizeMake(160, buttonHeight);
    CGRect feedbackButtonFrame = [widgetButtonText boundingRectWithSize:frameSize
                                           options:NSStringDrawingUsesLineFragmentOrigin
                                        attributes:@{ NSFontAttributeName: feedbackButtonFont }
                                           context:nil];
    int buttonWidth = feedbackButtonFrame.size.width + 40;
    
    // Set the anchor point.
    self.layer.anchorPoint = CGPointMake(0, 0);
    
    // Find the perfect position.
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    float rotation = -90;
    int x = self.superview.frame.size.width - buttonHeight;
    int y = (self.superview.frame.size.height / 2) + (buttonWidth / 2);
    self.notificationBadgeView.frame = CGRectMake(buttonWidth-6-(NOTIFICATION_BADGE_SIZE / 2), 6-(NOTIFICATION_BADGE_SIZE / 2), NOTIFICATION_BADGE_SIZE, NOTIFICATION_BADGE_SIZE);
    if ([feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC_LEFT"]) {
        rotation = 90;
        x = buttonHeight;
        
        if (@available(iOS 11.0, *)) {
            UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
            if (orientation == UIDeviceOrientationLandscapeLeft && window.safeAreaInsets.left && window.safeAreaInsets.left > 0) {
                x += window.safeAreaInsets.left;
                if (@available(iOS 11.0, *)) {
                    self.layer.maskedCorners = kCALayerMaxXMinYCorner | kCALayerMinXMinYCorner | kCALayerMaxXMaxYCorner | kCALayerMinXMaxYCorner;
                }
            }
        }
        
        y = (self.superview.frame.size.height / 2) - (buttonWidth / 2);
        self.notificationBadgeView.frame = CGRectMake(6-(NOTIFICATION_BADGE_SIZE/2), 6-(NOTIFICATION_BADGE_SIZE / 2), NOTIFICATION_BADGE_SIZE, NOTIFICATION_BADGE_SIZE);
    } else if ([feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC_BOTTOM"]) {
        rotation = 0;
        x = self.superview.frame.size.width - buttonWidth - 16;
        if (@available(iOS 11.0, *)) {
            UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
            if (orientation == UIDeviceOrientationLandscapeRight && window.safeAreaInsets.right && window.safeAreaInsets.right > 0) {
                x -= window.safeAreaInsets.right;
            }
        }
        
        y = self.superview.frame.size.height - buttonHeight;
        if (@available(iOS 11.0, *)) {
            UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
            if (window.safeAreaInsets.bottom && window.safeAreaInsets.bottom > 0) {
                y -= window.safeAreaInsets.bottom;
                if (@available(iOS 11.0, *)) {
                    self.layer.maskedCorners = kCALayerMaxXMinYCorner | kCALayerMinXMinYCorner | kCALayerMaxXMaxYCorner | kCALayerMinXMaxYCorner;
                }
            }
        }
        
        self.notificationBadgeView.frame = CGRectMake(buttonWidth - (NOTIFICATION_BADGE_SIZE - 5.0), -5.0, NOTIFICATION_BADGE_SIZE, NOTIFICATION_BADGE_SIZE);
    } else {
        if (@available(iOS 11.0, *)) {
            UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
            if (orientation == UIDeviceOrientationLandscapeRight && window.safeAreaInsets.right && window.safeAreaInsets.right > 0) {
                x -= window.safeAreaInsets.right;
                if (@available(iOS 11.0, *)) {
                    self.layer.maskedCorners = kCALayerMaxXMinYCorner | kCALayerMinXMinYCorner | kCALayerMaxXMaxYCorner | kCALayerMinXMaxYCorner;
                }
            }
        }
    }
    
    self.notificationBadgeView.layer.anchorPoint = CGPointMake(0.5, 0.5);
    self.notificationBadgeView.transform = CGAffineTransformMakeRotation(rotation * -1 * M_PI/180);
    
    self.frame = CGRectMake(x, y, buttonWidth, buttonHeight);
    
    // Update feedback text label frame.
    self.buttonTextLabel.frame = CGRectMake(16, 0, self.frame.size.width - 32, self.frame.size.height);
    
    self.transform = CGAffineTransformMakeRotation(rotation * M_PI/180);
}

- (void)setupModernButton {
    NSDictionary *config = GleapConfigHelper.sharedInstance.config;
    if (config == nil) {
        self.hidden = YES;
        return;
    }
    
    self.layer.cornerRadius = self.frame.size.height / 2.0;
    
    NSString *feedbackButtonPosition = [config objectForKey: @"feedbackButtonPosition"];
    
    NSString *buttonLogo = [config objectForKey: @"buttonLogo"];
    if (buttonLogo == nil || buttonLogo.length == 0) {
        buttonLogo = @"https://sdk.gleap.io/res/chatbubble.png";
    }
    // Prevent button from being loaded multiple times.
    if (![buttonLogo isEqualToString: self.currentButtonUrl]) {
        self.currentButtonUrl = buttonLogo;
        dispatch_async(dispatch_get_global_queue(0,0), ^{
            NSData * data = [[NSData alloc] initWithContentsOfURL: [NSURL URLWithString: buttonLogo]];
            if (data == nil) {
                return;
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.logoView != nil) {
                    self.logoView.hidden = NO;
                    self.logoView.image = [UIImage imageWithData: data];
                    self.hidden = NO;
                }
            });
        });
    }
    
    float buttonX = [[GleapConfigHelper sharedInstance] getButtonX];
    float buttonY = [[GleapConfigHelper sharedInstance] getButtonY];
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    
    if (self.superview != nil) {
        float x = self.superview.frame.size.width - BUTTON_SIZE - buttonX;
        
        if (
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
            if (@available(iOS 11.0, *)) {
                UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
                if (orientation == UIDeviceOrientationLandscapeRight && window.safeAreaInsets.right && window.safeAreaInsets.right > 0) {
                    x -= window.safeAreaInsets.right;
                }
            }
        }
        
        CGFloat borderBottom = buttonY;
        if (@available(iOS 11.0, *)) {
            UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
            borderBottom += window.safeAreaInsets.bottom;
        }
        
        self.frame = CGRectMake(x, self.superview.frame.size.height - BUTTON_SIZE - borderBottom, BUTTON_SIZE, BUTTON_SIZE);
    }
}

@end
