//
//  GleapNotificationHelper.h
//  
//
//  Created by Lukas Boehler on 29.08.22.
//

#import <Foundation/Foundation.h>
#import "GleapUIWindow.h"
#import "GleapFeedbackButton.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapNotificationHelper : NSObject <GleapUIWindowDelegate>

+ (instancetype)sharedInstance;
+ (void)showNotification:(NSDictionary *)notification;
+ (void)updateNotificationCount:(int)notificationCount;
- (void)renderUI;

@property (nonatomic, assign) int internalNotificationCount;
@property (nonatomic, retain) GleapFeedbackButton *feedbackButton;
@property (nonatomic, retain) GleapUIWindow *uiWindow;
@property (nonatomic, retain) NSMutableArray *notifications;
@property (nonatomic, retain) NSMutableArray *notificationViews;

@end

NS_ASSUME_NONNULL_END
