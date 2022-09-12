//
//  GleapNotificationHelper.m
//  
//
//  Created by Lukas Boehler on 29.08.22.
//

#import "GleapNotificationHelper.h"
#import "Gleap.h"
#import "GleapSessionHelper.h"
#import "GleapWidgetManager.h"
#import <UIKit/UIKit.h>

@implementation GleapNotificationHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapNotificationHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapNotificationHelper alloc] init];
        [sharedInstance initializeUI];
    });
    return sharedInstance;
}

+ (void)updateUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[GleapNotificationHelper sharedInstance].uiOverlayViewController updateUI];
    });
}

- (void)initializeUI {
    self.notifications = [[NSMutableArray alloc] init];
    self.notificationCount = 0;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow * currentKeyWindow = [[UIApplication sharedApplication] keyWindow];
        
        if (@available(iOS 13.0, *)) {
            UIScene *scene = [[[[UIApplication sharedApplication] connectedScenes] allObjects] firstObject];
            self.uiWindow = [[GleapUIWindow alloc] initWithWindowScene: (UIWindowScene *)scene];
        }
        if (self.uiWindow == nil) {
            // Fallback initialization.
            self.uiWindow = [[GleapUIWindow alloc] init];
        }
        [self.uiWindow setFrame: UIScreen.mainScreen.bounds];
        self.uiWindow.backgroundColor = nil;
        self.uiWindow.windowLevel = CGFLOAT_MAX;
        self.uiWindow.hidden = NO;
        self.uiWindow.delegate = self;
        
        // Hook up view controller.
        self.uiOverlayViewController = [[GleapUIOverlayViewController alloc] init];
        self.uiWindow.rootViewController = self.uiOverlayViewController;
        
        [currentKeyWindow makeKeyWindow];
    });
}

- (void)pressedView:(UIView *)view {
    @try {
        if (view.tag == INT_MAX) {
            [Gleap open];
        } else {
            NSDictionary *notification = [self.notifications objectAtIndex: view.tag];
            NSString *shareToken = [notification valueForKeyPath: @"data.conversation.shareToken"];
            if (shareToken != nil) {
                [Gleap open];
                [[GleapWidgetManager sharedInstance] sendMessageWithData: @{
                    @"name": @"open-conversation",
                    @"data": @{
                        @"shareToken": shareToken
                    },
                }];
            } else {
                [Gleap open];
            }
        }
    } @catch(id exception) {}
}

+ (void)updateNotificationCount:(int)notificationCount {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([GleapNotificationHelper sharedInstance].uiOverlayViewController != nil) {
            [[GleapNotificationHelper sharedInstance].uiOverlayViewController updateNotificationCount: notificationCount];
        }
    });
}

+ (void)showNotification:(NSDictionary *)notification {
    GleapNotificationHelper *sharedInstance = [GleapNotificationHelper sharedInstance];
    if ([sharedInstance.notifications count] >= 2) {
        [sharedInstance.notifications removeObjectAtIndex: 0];
    }
    [sharedInstance.notifications addObject: notification];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sharedInstance.uiOverlayViewController != nil) {
            [sharedInstance.uiOverlayViewController setNotifications: sharedInstance.notifications];
        }
    });
}

@end
