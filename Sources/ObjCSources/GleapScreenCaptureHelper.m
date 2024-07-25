#import "GleapScreenCaptureHelper.h"
#import "GleapCore.h"

@implementation GleapScreenCaptureHelper

/*
 Captures the current screen as UIImage.
 */
+ (UIImage *)captureScreen {
    @try {
        UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
        CGSize screenSize = [keyWindow bounds].size;
        
        if (CGSizeEqualToSize(screenSize, CGSizeZero)) {
            NSLog(@"Error: Screen size is zero");
            return nil;
        }
        
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = [UIScreen mainScreen].scale;
        
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:screenSize format:format];
        
        UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
            if (Gleap.sharedInstance.applicationType == FLUTTER) {
                NSArray *views = [keyWindow subviews];
                for (UIView *view in views) {
                    [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:YES];
                }
            } else {
                [keyWindow.layer renderInContext:rendererContext.CGContext];
            }
        }];
        
        return img;
    } @catch (NSException *exception) {
        NSLog(@"Exception: %@", exception);
        return nil;
    }
}

@end
