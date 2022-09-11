//
//  GleapNotificationHelper.h
//  
//
//  Created by Lukas Boehler on 29.08.22.
//

#import <Foundation/Foundation.h>
#import "GleapUIWindow.h"
#import "GleapFeedbackButton.h"
#import "GleapUIOverlayViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapNotificationHelper : NSObject <GleapUIWindowDelegate>

+ (instancetype)sharedInstance;
+ (void)showNotification:(NSDictionary *)notification;
+ (void)updateNotificationCount:(int)notificationCount;
+ (void)updateUI;

@property (nonatomic, assign) int notificationCount;
@property (nonatomic, retain) GleapUIWindow *uiWindow;
@property (nonatomic, retain) GleapUIOverlayViewController *uiOverlayViewController;
@property (nonatomic, retain) NSMutableArray *notifications;

@end

NS_ASSUME_NONNULL_END
