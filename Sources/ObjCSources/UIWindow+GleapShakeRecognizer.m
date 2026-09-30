//
//  UIWindow+GleapShakeRecognizer.m
//  Gleap
//
//  Created by Lukas on 13.01.19.
//  Copyright © 2019 Gleap. All rights reserved.
//

#import "UIWindow+GleapShakeRecognizer.h"
#import "GleapCore.h"

// UIWindow has no motion methods of its own, so these category methods add them; calling super
// hands the event on to UIResponder, which passes it along the responder chain (the application
// and its delegate) as it did before the category existed.
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
    [super motionBegan: motion withEvent: event];
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
    [super motionEnded: motion withEvent: event];
}

@end
