//
//  GleapUIOverlayViewController.h
//  
//
//  Created by Lukas Boehler on 11.09.22.
//

#import <UIKit/UIKit.h>
#import "GleapUIWindow.h"
#import "GleapFeedbackButton.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapUIOverlayViewController : UIViewController

- (void)setNotifications:(NSMutableArray *)notifications;
- (void)updateNotificationCount:(int)notificationCount;
- (void)updateUI;

@property (nonatomic, assign) UIInterfaceOrientationMask lastOrientation;
@property (nonatomic, assign) bool lastShouldAutoRotate;
@property (nonatomic, assign) UIStatusBarStyle lastStatusBarStyle;
@property (nonatomic, retain) NSTimer *topMostViewControllerTimer;
@property (nonatomic, retain) NSMutableArray *internalNotifications;
@property (nonatomic, retain) UIView *closeButton;
@property (nonatomic, retain) GleapFeedbackButton *feedbackButton;
@property (nonatomic, retain) NSMutableArray *notificationViews;

@end

NS_ASSUME_NONNULL_END
