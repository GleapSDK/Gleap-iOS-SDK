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

@implementation GleapFeedbackButton

- (id)initWithFrame:(CGRect)aRect
{
    if ((self = [super initWithFrame:aRect])) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    float padding = 10.0;
    self.logoView = [[UIImageView alloc] initWithFrame: CGRectMake(padding, 8.0, self.frame.size.width - (padding * 2), self.frame.size.height - (padding * 2))];
    self.logoView.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview: self.logoView];
    
    self.tag = INT_MAX;
    
    float notificationBadgeSize = 22.0;
    self.notificationBadgeView = [[UIView alloc] initWithFrame: CGRectMake(self.frame.size.width - (notificationBadgeSize - 5.0), -5.0, notificationBadgeSize, notificationBadgeSize)];
    self.notificationBadgeView.backgroundColor = [UIColor redColor];
    self.notificationBadgeView.layer.cornerRadius = notificationBadgeSize / 2.0;
    [self addSubview: self.notificationBadgeView];
    self.notificationBadgeView.hidden = YES;
    
    self.notificationBadgeLabel = [[UILabel alloc] initWithFrame: CGRectMake(0, 0, notificationBadgeSize, notificationBadgeSize)];
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
    
    self.layer.cornerRadius = self.frame.size.height / 2.0;
    self.layer.shadowRadius  = 10.0;
    self.layer.shadowColor   = [UIColor blackColor].CGColor;
    self.layer.shadowOffset  = CGSizeMake(0.0f, 0.0f);
    self.layer.shadowOpacity = 0.3;
    self.layer.masksToBounds = NO;
    self.clipsToBounds = NO;
    
    NSString *feedbackButtonPosition = [config objectForKey: @"feedbackButtonPosition"];
    NSString *buttonColor = [config objectForKey: @"buttonColor"];
    if (buttonColor != nil && buttonColor.length > 0) {
        self.backgroundColor = [GleapUIHelper colorFromHexString: buttonColor];
    } else {
        self.backgroundColor = [GleapUIHelper colorFromHexString: @"#485bff"];
    }
    
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
                    self.logoView.image = [UIImage imageWithData: data];
                    self.hidden = NO;
                }
            });
        });
    }
    
    float buttonX = [[GleapConfigHelper sharedInstance] getButtonX];
    float buttonY = [[GleapConfigHelper sharedInstance] getButtonY];
    
    float buttonSize = 52.0;
    if (self.superview != nil) {
        float x = self.superview.frame.size.width - buttonSize - buttonX;
        if (
            [feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC_LEFT"] ||
            [feedbackButtonPosition isEqualToString: @"BOTTOM_LEFT"]
        ) {
            x = buttonX;
        }
        
        CGFloat borderBottom = buttonY;
        if (@available(iOS 11.0, *)) {
            UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
            borderBottom += window.safeAreaInsets.bottom;
        }
        
        self.frame = CGRectMake(x, self.superview.frame.size.height - buttonSize - borderBottom, buttonSize, buttonSize);
    }
}

@end
