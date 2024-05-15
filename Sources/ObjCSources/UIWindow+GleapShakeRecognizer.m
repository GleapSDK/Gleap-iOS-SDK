//
//  UIWindow+GleapShakeRecognizer.m
//  Gleap
//
//  Created by Lukas on 13.01.19.
//  Copyright © 2019 Gleap. All rights reserved.
//

#import "UIWindow+GleapShakeRecognizer.h"
#import "GleapCore.h"

@implementation UIWindow (GleapShakeRecognizer)

NSNotificationName const WindowDidBeginMotionNotification = @"WindowDidBeginMotionNotification";
NSNotificationName const WindowDidEndMotionNotification = @"WindowDidEndMotionNotification";

NSString * const WindowMotionEventUserInfoKey = @"WindowMotionEventUserInfoKey";
NSString * const WindowMotionEventSubtypeUserInfoKey = @"WindowMotionEventSubtypeUserInfoKey";

- (void)motionBegan:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    NSDictionary *userInfo = @{
        WindowMotionEventUserInfoKey: event,
        WindowMotionEventSubtypeUserInfoKey: [NSNumber numberWithInteger: motion]
    };
    [[NSNotificationCenter defaultCenter] postNotificationName: WindowDidBeginMotionNotification
                                                        object: nil
                                                      userInfo: userInfo];
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    NSDictionary *userInfo = @{
        WindowMotionEventUserInfoKey: event,
        WindowMotionEventSubtypeUserInfoKey: [NSNumber numberWithInteger: motion]
    };
    [[NSNotificationCenter defaultCenter] postNotificationName: WindowDidEndMotionNotification
                                                        object: nil
                                                      userInfo: userInfo];

    if (motion == UIEventSubtypeMotionShake) {
        [Gleap shakeInvocation];
    }
}

@end
