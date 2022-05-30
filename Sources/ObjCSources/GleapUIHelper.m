//
//  GleapUIHelper.m
//  
//
//  Created by Lukas Boehler on 27.05.22.
//

#import "GleapUIHelper.h"

@implementation GleapUIHelper

+ (NSString *)getTopMostViewControllerName {
    NSString *currentViewControllerName = @"NotSet";
    UIViewController *topViewController = [self getTopMostViewController];
    if (topViewController != nil) {
        if (topViewController.title != nil) {
            currentViewControllerName = topViewController.title;
        } else {
            currentViewControllerName = NSStringFromClass([topViewController class]);
        }
    }
    return currentViewControllerName;
}

/*
 Returns the top most view controller.
 */
+ (UIViewController *)getTopMostViewController {
    UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
    return [self topViewControllerWith: keyWindow.rootViewController];
}

/*
 Returns the top most view controller.
 */
+ (UIViewController *)topViewControllerWith:(UIViewController *)rootViewController {
    if (rootViewController == nil) {
        return nil;
    }
    
    UIViewController *presentedViewController = rootViewController.presentedViewController;
    if (presentedViewController == nil) {
        if ([rootViewController isKindOfClass: [UINavigationController class]]) {
            UINavigationController *navController = (UINavigationController *)rootViewController;
            return [self topViewControllerWith: navController.viewControllers.lastObject];
        }
        
        if ([rootViewController isKindOfClass: [UITabBarController class]]) {
            UITabBarController *tabBarController = (UITabBarController *)rootViewController;
            return [self topViewControllerWith: tabBarController.selectedViewController];
        }
        
        return rootViewController;
    }
    return [self topViewControllerWith: presentedViewController];
}

+ (NSString *)getJSStringForNSDate:(NSDate *)date {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    return [dateFormatter stringFromDate: date];
}

@end
