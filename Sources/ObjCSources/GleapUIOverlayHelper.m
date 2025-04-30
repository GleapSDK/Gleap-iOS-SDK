//
//  GleapUIOverlayHelper.m
//  
//
//  Created by Lukas Boehler on 29.08.22.
//

#import "GleapUIOverlayHelper.h"
#import "Gleap.h"
#import "GleapSessionHelper.h"
#import "GleapWidgetManager.h"
#import "GleapWindowChecker.h"
#import <UIKit/UIKit.h>

@implementation GleapUIOverlayHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapUIOverlayHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapUIOverlayHelper alloc] init];
        [sharedInstance initializeUI];
    });
    return sharedInstance;
}

+ (void)updateUI {
    GleapWindowChecker *windowChecker = [[GleapWindowChecker alloc] init];
    [windowChecker waitForKeyWindowToBeReadyWithCompletion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [[GleapUIOverlayHelper sharedInstance].uiOverlayViewController updateUI];
        });
    }];
}

+ (void)clear {
    dispatch_async(dispatch_get_main_queue(), ^{
        GleapUIOverlayHelper *instance = [GleapUIOverlayHelper sharedInstance];
        instance.notifications = [[NSMutableArray alloc] init];
        
        if (instance.uiOverlayViewController != nil) {
            [instance.uiOverlayViewController setNotifications: instance.notifications];
            [instance.uiOverlayViewController updateUI];
            [GleapUIOverlayHelper updateNotificationCount: 0];
        }
    });
}

+ (void)showBanner:(NSDictionary *)bannerData {
    GleapWindowChecker *windowChecker = [[GleapWindowChecker alloc] init];
    [windowChecker waitForKeyWindowToBeReadyWithCompletion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [[GleapUIOverlayHelper sharedInstance].uiOverlayViewController showBanner: bannerData];
        });
    }];
}

+ (void)showModal:(NSDictionary *)modalData {
    GleapWindowChecker *windowChecker = [[GleapWindowChecker alloc] init];
    [windowChecker waitForKeyWindowToBeReadyWithCompletion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [[GleapUIOverlayHelper sharedInstance].uiOverlayViewController showModal: modalData];
        });
    }];
}

+ (void)showFeedbackButton:(bool)show {
    [GleapUIOverlayHelper sharedInstance].showButtonExternalOverwrite = YES;
    [GleapUIOverlayHelper sharedInstance].showButton = show;
    [GleapUIOverlayHelper updateUI];
}

- (void)initializeUI {
    self.notifications = [[NSMutableArray alloc] init];
    self.notificationCount = 0;
    self.showButton = NO;
    self.showButtonExternalOverwrite = NO;
    
    GleapWindowChecker *windowChecker = [[GleapWindowChecker alloc] init];
    [windowChecker waitForKeyWindowToBeReadyWithCompletion:^{
       dispatch_async(dispatch_get_main_queue(), ^{
           self.uiOverlayViewController = [[GleapUIOverlayViewController alloc] init];
           [self.uiOverlayViewController initializeUI];
       });
    }];
}

+ (void)updateNotificationCount:(int)notificationCount {
    GleapWindowChecker *windowChecker = [[GleapWindowChecker alloc] init];
    [windowChecker waitForKeyWindowToBeReadyWithCompletion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([GleapUIOverlayHelper sharedInstance].uiOverlayViewController != nil) {
                [[GleapUIOverlayHelper sharedInstance].uiOverlayViewController updateNotificationCount: notificationCount];
            }
            
            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(notificationCountUpdated:)]) {
                [Gleap.sharedInstance.delegate notificationCountUpdated: notificationCount];
            }
        });
    }];
}

+ (void)showNotification:(NSDictionary *)notification {
    GleapWindowChecker *windowChecker = [[GleapWindowChecker alloc] init];
    [windowChecker waitForKeyWindowToBeReadyWithCompletion:^{
        GleapUIOverlayHelper *sharedInstance = [GleapUIOverlayHelper sharedInstance];
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
    }];
}

@end
