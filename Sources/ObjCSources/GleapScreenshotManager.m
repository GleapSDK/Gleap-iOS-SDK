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
    [GleapScreenshotManager sharedInstance].screenshot = [GleapScreenCaptureHelper captureScreen];
}

@end
