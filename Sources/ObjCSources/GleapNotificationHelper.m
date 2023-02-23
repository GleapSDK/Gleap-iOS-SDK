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

+ (void)clear {
    dispatch_async(dispatch_get_main_queue(), ^{
        GleapNotificationHelper *instance = [GleapNotificationHelper sharedInstance];
        instance.notifications = [[NSMutableArray alloc] init];
        
        if (instance.uiOverlayViewController != nil) {
            [instance.uiOverlayViewController setNotifications: instance.notifications];
            [instance.uiOverlayViewController updateNotificationCount: 0];
            [instance.uiOverlayViewController updateUI];
        }
    });
}

+ (void)showFeedbackButton:(bool)show {
    [GleapNotificationHelper sharedInstance].showButtonExternalOverwrite = YES;
    [GleapNotificationHelper sharedInstance].showButton = show;
    [GleapNotificationHelper updateUI];
}

- (void)initializeUI {
    self.notifications = [[NSMutableArray alloc] init];
    self.notificationCount = 0;
    self.showButton = NO;
    self.showButtonExternalOverwrite = NO;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow * currentKeyWindow = [[UIApplication sharedApplication] keyWindow];
        if (@available(iOS 13.0, *)) {
            UIScene *scene = [[[[UIApplication sharedApplication] connectedScenes] allObjects] firstObject];
            self.uiWindow = [[GleapUIWindow alloc] initWithWindowScene: (UIWindowScene *)scene];
        }
        if (self.uiWindow == nil) {
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
        if (view.tag == 999) {
            [GleapNotificationHelper clear];
        } else if (view.tag == INT_MAX) {
            [Gleap open];
        } else {
            NSDictionary *notification = [self.notifications objectAtIndex: view.tag];
            NSString *shareToken = [notification valueForKeyPath: @"data.conversation.shareToken"];
            NSString *newsId = [notification valueForKeyPath: @"data.news.id"];
            if (shareToken != nil) {
                [Gleap openConversation: shareToken];
            } else if (newsId != nil) {
                [Gleap openNewsArticle: newsId andShowBackButton: YES];
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
    // Prevent duplicates from showing up.
    int updateAtIndex = -1;
    for (int i = 0; i < sharedInstance.notifications.count; i++) {
        NSString * newOutbound = [notification objectForKey: @"outbound"];
        NSString * existingOutbound = [[sharedInstance.notifications objectAtIndex: i] objectForKey: @"outbound"];
        if (newOutbound != nil && existingOutbound != nil && [newOutbound isEqualToString: existingOutbound]) {
            updateAtIndex = i;
        }
    }
    if (updateAtIndex >= 0) {
        [sharedInstance.notifications replaceObjectAtIndex: updateAtIndex withObject: notification];
    } else {
        if ([sharedInstance.notifications count] >= 2) {
            [sharedInstance.notifications removeObjectAtIndex: 0];
        }
        [sharedInstance.notifications addObject: notification];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sharedInstance.uiOverlayViewController != nil) {
            [sharedInstance.uiOverlayViewController setNotifications: sharedInstance.notifications];
        }
    });
}

@end
