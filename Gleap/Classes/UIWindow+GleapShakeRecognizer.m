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

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (motion == UIEventSubtypeMotionShake) {
        [Gleap shakeInvocation];
    }
}

@end
