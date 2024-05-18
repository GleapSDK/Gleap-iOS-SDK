//
//  UIWindow+GleapShakeRecognizer.h
//  Gleap
//
//  Created by Lukas on 13.01.19.
//  Copyright © 2019 Gleap. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const WindowDidBeginMotionNotification;
extern NSNotificationName const WindowDidEndMotionNotification;

extern NSString * const WindowMotionEventUserInfoKey;
extern NSString * const WindowMotionEventSubtypeUserInfoKey;

@interface UIWindow (GleapShakeRecognizer)

@end

NS_ASSUME_NONNULL_END
