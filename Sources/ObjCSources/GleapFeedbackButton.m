//
//  GleapFeedbackButton.m
//  
//
//  Created by Lukas Boehler on 09.09.22.
//

#import "GleapFeedbackButton.h"
#import "GleapConfigHelper.h"
#import "GleapUIOverlayHelper.h"
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
    
    // Initialization code
    if (@available(iOS 11, *)) {
        UILayoutGuide *guide = self.safeAreaLayoutGuide;
        self.safeAreaConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:guide attribute:NSLayoutAttributeLeft multiplier:1 constant: -12];

        self.edgeConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeLeft multiplier:1 constant: -12];

        [self updateConstraintsForOrientation];
    }

    // Register for notification
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationDidChange:) name:UIDeviceOrientationDidChangeNotification object:nil];
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
    
    if (![GleapUIOverlayHelper sharedInstance].showButton) {
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
    
    NSString *widgetButtonText = [config objectForKey: @"widgetButtonText"];
    NSString *feedbackButtonPosition = [config objectForKey: @"feedbackButtonPosition"];
    
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

    // Disable autoresizing masks to constraints conversion
    self.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Auto layout constraints
    NSLayoutConstraint *heightConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:buttonHeight];
    NSLayoutConstraint *widthConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:buttonWidth];
    [self addConstraints:@[heightConstraint, widthConstraint]];

    UIWindow *window = UIApplication.sharedApplication.windows.firstObject;

    // Set the auto layout constraints depending on the button position
    if ([feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC_LEFT"]) {
        rotation = 90;
        [window addConstraint: [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:window attribute:NSLayoutAttributeCenterY multiplier:1 constant: -(buttonWidth / 2)]];
        
        _edgeConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:window attribute:NSLayoutAttributeLeft multiplier:1 constant: -12];
        
        if (@available(iOS 11, *)) {
            UILayoutGuide *guide = window.safeAreaLayoutGuide;
            _safeAreaConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:guide attribute:NSLayoutAttributeLeft multiplier:1 constant: -12];
        }
    } else if ([feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC_BOTTOM"]) {
        rotation = 0;
        
        _edgeConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:window attribute:NSLayoutAttributeBottom multiplier:1 constant: -(buttonHeight / 2)];
        
        if (@available(iOS 11, *)) {
            UILayoutGuide *guide = window.safeAreaLayoutGuide;
            
            _safeAreaConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:guide attribute:NSLayoutAttributeBottom multiplier:1 constant: -(buttonHeight / 2)];
            
            [window addConstraint: [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:guide attribute: NSLayoutAttributeRight multiplier:1 constant: -((buttonWidth / 2) + 20)]];
        }
    } else {
        [window addConstraint: [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:window attribute:NSLayoutAttributeCenterY multiplier:1 constant: (buttonWidth / 2)]];
        
        _edgeConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:window attribute:NSLayoutAttributeRight multiplier:1 constant: 12];
        
        if (@available(iOS 11, *)) {
            UILayoutGuide *guide = window.safeAreaLayoutGuide;
            _safeAreaConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:guide attribute: NSLayoutAttributeRight multiplier:1 constant: 12];
        }
    }
    
    [self updateConstraintsForOrientation];
    
    // Update feedback text label frame.
    self.buttonTextLabel.frame = CGRectMake(16, 0, buttonWidth - 32, buttonHeight);
    
    self.transform = CGAffineTransformMakeRotation(rotation * M_PI/180);
}

- (void)orientationDidChange:(NSNotification *)notification {
    [self updateConstraintsForOrientation];
}

- (UIInterfaceOrientation)reliableInterfaceOrientation {
    UIInterfaceOrientation deviceOrientation = [UIApplication sharedApplication].statusBarOrientation;
    
    if (deviceOrientation == UIDeviceOrientationUnknown) {
        if (@available(iOS 13.0, *)) {
            deviceOrientation = [UIApplication sharedApplication].windows.firstObject.windowScene.interfaceOrientation;
        }
    }
    
    return deviceOrientation;
}

- (void)updateConstraintsForOrientation {
    NSDictionary *config = GleapConfigHelper.sharedInstance.config;
    if (config == nil) {
        return;
    }
    
    NSString *feedbackButtonPosition = [config objectForKey: @"feedbackButtonPosition"];
    if (![feedbackButtonPosition containsString: @"CLASSIC"]) {
        return;
    }
    
    UIInterfaceOrientation orientation = [self reliableInterfaceOrientation];
    
    self.layer.cornerRadius = 8.0;
    if (@available(iOS 11.0, *)) {
        self.layer.maskedCorners = kCALayerMaxXMinYCorner | kCALayerMinXMinYCorner;
    }
    
    if ([feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC_LEFT"]) {
        if (orientation == UIDeviceOrientationLandscapeLeft) {
            self.edgeConstraint.active = NO;
            self.safeAreaConstraint.active = YES;
            if (@available(iOS 11.0, *)) {
                self.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
            }
        } else {
            self.safeAreaConstraint.active = NO;
            self.edgeConstraint.active = YES;
        }
    } else if ([feedbackButtonPosition isEqualToString: @"BUTTON_CLASSIC_BOTTOM"]) {
        if (orientation == UIDeviceOrientationPortrait) {
            self.edgeConstraint.active = NO;
            self.safeAreaConstraint.active = YES;
            if (@available(iOS 11.0, *)) {
                self.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
            }
        } else {
            self.safeAreaConstraint.active = NO;
            self.edgeConstraint.active = YES;
        }
    } else {
        if (orientation == UIDeviceOrientationLandscapeRight) {
            self.edgeConstraint.active = NO;
            self.safeAreaConstraint.active = YES;
            if (@available(iOS 11.0, *)) {
                self.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
            }
        } else {
            self.safeAreaConstraint.active = NO;
            self.edgeConstraint.active = YES;
        }
    }
}

- (void)setupModernButton {
    NSDictionary *config = GleapConfigHelper.sharedInstance.config;
    if (config == nil) {
        self.hidden = YES;
        return;
    }
    
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.layer.cornerRadius = BUTTON_SIZE / 2.0;
    
    NSString *feedbackButtonPosition = [config objectForKey: @"feedbackButtonPosition"];
    
    NSString *buttonLogo = [config objectForKey: @"buttonLogo"];
    if (buttonLogo == nil || buttonLogo.length == 0) {
        buttonLogo = @"https://sdk.gleap.io/res/chatbubble.png";
    }
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
        NSLayoutConstraint *xConstraint;
        NSLayoutConstraint *yConstraint;
        NSLayoutConstraint *widthConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:BUTTON_SIZE];
        NSLayoutConstraint *heightConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:BUTTON_SIZE];
        
        if (@available(iOS 11, *)) {
            UILayoutGuide *guide = self.superview.safeAreaLayoutGuide;
            
            if ([feedbackButtonPosition isEqualToString: @"BOTTOM_LEFT"]) {
                xConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:guide attribute:NSLayoutAttributeLeading multiplier:1 constant: buttonX];
            } else {
                xConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:guide attribute:NSLayoutAttributeTrailing multiplier:1 constant: -buttonX];
            }
            
            yConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:guide attribute:NSLayoutAttributeBottom multiplier:1 constant: -buttonY];
        } else {
            if ([feedbackButtonPosition isEqualToString: @"BOTTOM_LEFT"]) {
                xConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self.superview attribute:NSLayoutAttributeLeadingMargin multiplier:1 constant: buttonX];
            } else {
                xConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:self.superview attribute:NSLayoutAttributeTrailingMargin multiplier:1 constant: -buttonX];
            }
            
            yConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.superview attribute:NSLayoutAttributeBottomMargin multiplier:1 constant: -buttonY];
        }
        
        [NSLayoutConstraint activateConstraints:@[xConstraint, yConstraint, widthConstraint, heightConstraint]];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
}

@end
