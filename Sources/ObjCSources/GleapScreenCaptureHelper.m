//
//  GleapScreenCaptureHelper.m
//  
//
//  Created by Lukas Boehler on 25.05.22.
//

#import "GleapScreenCaptureHelper.h"
#import "GleapCore.h"

@implementation GleapScreenCaptureHelper

/*
 Captures the current screen as UIImage.
 */
+ (UIImage *)captureScreen {
    UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
    
    if (Gleap.sharedInstance.applicationType == FLUTTER) {
        UIGraphicsBeginImageContextWithOptions([keyWindow bounds].size, false, [UIScreen mainScreen].scale);
        NSArray *views = [keyWindow subviews];
        for (int i = 0; i < views.count; i++) {
            UIView *view = [views objectAtIndex: i];
            [view drawViewHierarchyInRect: view.bounds afterScreenUpdates: true];
        }
    } else {
        UIGraphicsBeginImageContextWithOptions([keyWindow bounds].size, false, [UIScreen mainScreen].scale);
        CGContextRef context = UIGraphicsGetCurrentContext();
        [keyWindow.layer renderInContext: context];
    }
    
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@end
