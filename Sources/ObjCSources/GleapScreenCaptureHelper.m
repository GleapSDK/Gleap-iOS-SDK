#import "GleapScreenCaptureHelper.h"
#import "GleapCore.h"

@implementation GleapScreenCaptureHelper

/*
 Captures the current screen as UIImage.
 */
+ (UIImage *)captureScreen {
    @try {
        // Ensure we're on the main thread
        if (![NSThread isMainThread]) {
            __block UIImage *capturedImage = nil;
            dispatch_sync(dispatch_get_main_queue(), ^{
                capturedImage = [self captureScreen];
            });
            return capturedImage;
        }
        
        // Check application state
        UIApplicationState appState = [UIApplication sharedApplication].applicationState;
        if (appState != UIApplicationStateActive) {
            NSLog(@"Error: Application is not active");
            return nil;
        }
        
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) {
            NSLog(@"Error: keyWindow is nil");
            return nil;
        }
        
        CGSize screenSize = keyWindow.bounds.size;
        if (CGSizeEqualToSize(screenSize, CGSizeZero)) {
            NSLog(@"Error: Screen size is zero");
            return nil;
        }
        
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = [UIScreen mainScreen].scale;
        
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:screenSize format:format];
        
        UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
            if (Gleap.sharedInstance.applicationType == FLUTTER) {
                NSArray *views = keyWindow.subviews;
                for (UIView *view in views) {
                    if (!view.isHidden && view.alpha > 0.0 && CGRectIntersectsRect(keyWindow.bounds, view.frame)) {
                        [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:YES];
                    }
                }
            } else {
                BOOL success = [keyWindow drawViewHierarchyInRect:keyWindow.bounds afterScreenUpdates:NO];
                if (!success) {
                    NSLog(@"Error: drawViewHierarchyInRect failed");
                }
            }
        }];
        
        return img;
    } @catch (NSException *exception) {
        NSLog(@"Exception in captureScreen: %@\n%@", exception.reason, exception.callStackSymbols);
        return nil;
    }
}

@end
