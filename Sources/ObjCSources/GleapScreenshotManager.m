//
//  GleapScreenshotManager.m
//  
//
//  Created by Lukas Boehler on 28.05.22.
//

#import "GleapScreenshotManager.h"
#import "GleapScreenCaptureHelper.h"

@implementation GleapScreenshotManager

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapScreenshotManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapScreenshotManager alloc] init];
    });
    return sharedInstance;
}

+ (UIImage *)getScreenshot {
    return [GleapScreenshotManager sharedInstance].screenshot;
}

+ (UIImage *)getScreenshotToAttach {
    if ([GleapScreenshotManager sharedInstance].updatedScreenshot != nil) {
        return [GleapScreenshotManager sharedInstance].updatedScreenshot;
    }
    
    return [GleapScreenshotManager getScreenshot];
}

+ (void)takeScreenshot {
    [self takeScreenshotWithCompletion:nil];
}

+ (void)takeScreenshotWithCompletion:(void(^)(UIImage *screenshot, NSError *error))completion {
    // Ensure we're on the main thread for UI operations
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self takeScreenshotWithCompletion:completion];
        });
        return;
    }
    
    @try {
        UIImage *screenshot = [GleapScreenCaptureHelper captureScreen];
        
        if (screenshot != nil) {
            [GleapScreenshotManager sharedInstance].screenshot = screenshot;
            NSLog(@"Gleap: Screenshot captured successfully");
            
            if (completion) {
                completion(screenshot, nil);
            }
        } else {
            NSLog(@"Gleap: Failed to capture screenshot");
            NSError *error = [NSError errorWithDomain:@"GleapScreenshotError" 
                                               code:1001 
                                           userInfo:@{NSLocalizedDescriptionKey: @"Failed to capture screenshot"}];
            
            if (completion) {
                completion(nil, error);
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"Gleap: Exception in takeScreenshot: %@", exception.reason);
        NSError *error = [NSError errorWithDomain:@"GleapScreenshotError" 
                                           code:1002 
                                       userInfo:@{NSLocalizedDescriptionKey: @"Exception during screenshot capture",
                                                 @"ExceptionReason": exception.reason ?: @"Unknown"}];
        
        if (completion) {
            completion(nil, error);
        }
    }
}

@end
