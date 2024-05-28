//
//  GleapWindowChecker.m
//  
//
//  Created by Lukas Boehler on 28.05.24.
//

#import "GleapWindowChecker.h"

@implementation GleapWindowChecker

- (void)waitForKeyWindowToBeReadyWithCompletion:(GleapWindowReadyCompletion)completion {
    [self checkKeyWindowWithCompletion:completion];
}

- (UIWindow *)getKeyWindow {
    UIWindow *keyWindow = nil;
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.isKeyWindow) {
            keyWindow = window;
            break;
        }
    }
    return keyWindow;
}

- (void)checkKeyWindowWithCompletion:(GleapWindowReadyCompletion)completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [self getKeyWindow];
        
        if (keyWindow && keyWindow.isKeyWindow && !keyWindow.isHidden && keyWindow.rootViewController.viewIfLoaded.window != nil) {
            // The key window is ready, execute the completion block
            if (completion) {
                completion();
            }
        } else {
            // The key window is not ready, check again after a delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self checkKeyWindowWithCompletion:completion];
            });
        }
    });
}

@end
