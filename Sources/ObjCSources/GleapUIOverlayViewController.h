//
//  GleapUIOverlayViewController.h
//  
//
//  Created by Lukas Boehler on 11.09.22.
//

#import <UIKit/UIKit.h>
#import "GleapFeedbackButton.h"
#import "GleapBanner.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapUIOverlayViewController : NSObject

- (void)setNotifications:(NSMutableArray *)notifications;
- (void)updateNotificationCount:(int)notificationCount;
- (void)updateUI;
- (void)initializeUI;
- (void)showBanner:(NSDictionary *)bannerData;

@property (nonatomic, retain) NSMutableArray *internalNotifications;
@property (nonatomic, retain) UIView *closeButton;
@property (nonatomic, retain) GleapFeedbackButton *feedbackButton;
@property (nonatomic, retain, nullable) GleapBanner *banner;
@property (nonatomic, retain) NSMutableArray *notificationViews;

@end

NS_ASSUME_NONNULL_END
