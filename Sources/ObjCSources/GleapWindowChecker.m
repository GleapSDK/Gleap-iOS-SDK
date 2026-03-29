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

+ (UIWindow *)getKeyWindow {
    UIWindow *keyWindow = nil;

    if (@available(iOS 15.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                if (windowScene.activationState == UISceneActivationStateForegroundActive) {
                    keyWindow = windowScene.keyWindow;
                    if (keyWindow) break;
                }
            }
        }
        if (!keyWindow) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    keyWindow = ((UIWindowScene *)scene).keyWindow;
                    if (keyWindow) break;
                }
            }
        }
    } else if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                if (windowScene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *window in windowScene.windows) {
                        if (window.isKeyWindow) {
                            keyWindow = window;
                            break;
                        }
                    }
                    if (keyWindow) break;
                }
            }
        }
    }

    if (!keyWindow) {
        keyWindow = [UIApplication sharedApplication].keyWindow;
    }

    return keyWindow;
}

+ (UIInterfaceOrientation)reliableInterfaceOrientation {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                if (windowScene.activationState == UISceneActivationStateForegroundActive) {
                    return windowScene.interfaceOrientation;
                }
            }
        }
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                return ((UIWindowScene *)scene).interfaceOrientation;
            }
        }
    }
    return [UIApplication sharedApplication].statusBarOrientation;
}

- (UIWindow *)getKeyWindowInstance {
    return [GleapWindowChecker getKeyWindow];
}

- (void)checkKeyWindowWithCompletion:(GleapWindowReadyCompletion)completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [GleapWindowChecker getKeyWindow];
        
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
