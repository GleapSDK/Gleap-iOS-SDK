#import "GleapScreenCaptureHelper.h"
#import "GleapCore.h"

@implementation GleapScreenCaptureHelper

/*
 Captures the current screen as UIImage with comprehensive crash prevention.
 */
+ (UIImage *)captureScreen {
    return [self captureScreenWithRetryCount:3];
}

+ (UIImage *)captureScreenWithRetryCount:(NSInteger)retryCount {
    @try {
        // Ensure we're on the main thread
        if (![NSThread isMainThread]) {
            __block UIImage *capturedImage = nil;
            dispatch_sync(dispatch_get_main_queue(), ^{
                capturedImage = [self captureScreenWithRetryCount:retryCount];
            });
            return capturedImage;
        }
        
        // Check application state
        UIApplicationState appState = [UIApplication sharedApplication].applicationState;
        if (appState != UIApplicationStateActive) {
            NSLog(@"Gleap: Application is not active, skipping screenshot");
            return nil;
        }
        
        // Get key window with additional validation
        UIWindow *keyWindow = [self getValidKeyWindow];
        if (!keyWindow) {
            NSLog(@"Gleap: No valid key window found");
            return nil;
        }
        
        // Validate window bounds
        CGSize screenSize = keyWindow.bounds.size;
        if (CGSizeEqualToSize(screenSize, CGSizeZero) || 
            screenSize.width <= 0 || screenSize.height <= 0 ||
            screenSize.width > 10000 || screenSize.height > 10000) {
            NSLog(@"Gleap: Invalid screen size: %@", NSStringFromCGSize(screenSize));
            return nil;
        }
        
        // Check available memory before proceeding
        if (![self hasEnoughMemoryForScreenshot:screenSize]) {
            NSLog(@"Gleap: Insufficient memory for screenshot");
            return nil;
        }
        
        // Try primary capture method
        UIImage *capturedImage = [self performPrimaryCaptureForWindow:keyWindow withSize:screenSize];
        
        // If primary method fails and we have retries left, try alternative methods
        if (!capturedImage && retryCount > 0) {
            NSLog(@"Gleap: Primary capture failed, trying alternative method (retries left: %ld)", (long)retryCount);
            
            // Small delay before retry
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                // This will be handled by the caller
            });
            
            // Try alternative capture method
            capturedImage = [self performAlternativeCaptureForWindow:keyWindow withSize:screenSize];
            
            // If still failing, retry with reduced count
            if (!capturedImage) {
                return [self captureScreenWithRetryCount:retryCount - 1];
            }
        }
        
        // Validate the captured image
        if (capturedImage && [self isValidImage:capturedImage]) {
            return capturedImage;
        }
        
        NSLog(@"Gleap: Screenshot validation failed");
        return nil;
        
    } @catch (NSException *exception) {
        NSLog(@"Gleap: Exception in captureScreen: %@\n%@", exception.reason, exception.callStackSymbols);
        
        // If we have retries left, try again after a delay
        if (retryCount > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                // This will be handled by the caller
            });
            return [self captureScreenWithRetryCount:retryCount - 1];
        }
        
        return nil;
    }
}

+ (UIWindow *)getValidKeyWindow {
    UIWindow *keyWindow = nil;
    
    if (@available(iOS 13.0, *)) {
        // Try to find the most appropriate window scene
        for (UIWindowScene *windowScene in [UIApplication sharedApplication].connectedScenes) {
            if (windowScene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow || (!keyWindow && window.rootViewController)) {
                        keyWindow = window;
                        break;
                    }
                }
                if (keyWindow) break;
            }
        }
        
        // Fallback to first available window
        if (!keyWindow) {
            for (UIWindowScene *windowScene in [UIApplication sharedApplication].connectedScenes) {
                if (windowScene.windows.count > 0) {
                    keyWindow = windowScene.windows.firstObject;
                    break;
                }
            }
        }
    } else {
        keyWindow = [UIApplication sharedApplication].keyWindow;
    }
    
    // Additional validation
    if (keyWindow && keyWindow.rootViewController && !keyWindow.isHidden) {
        return keyWindow;
    }
    
    return nil;
}

+ (BOOL)hasEnoughMemoryForScreenshot:(CGSize)size {
    // Calculate approximate memory needed (4 bytes per pixel for RGBA)
    CGFloat scale = [UIScreen mainScreen].scale;
    NSUInteger bytesNeeded = (NSUInteger)(size.width * scale * size.height * scale * 4);
    
    // Check if we need more than 100MB (arbitrary threshold)
    if (bytesNeeded > 100 * 1024 * 1024) {
        NSLog(@"Gleap: Screenshot would require too much memory: %lu bytes", (unsigned long)bytesNeeded);
        return NO;
    }
    
    return YES;
}

+ (UIImage *)performPrimaryCaptureForWindow:(UIWindow *)keyWindow withSize:(CGSize)screenSize {
    @try {
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = [UIScreen mainScreen].scale;
        format.opaque = NO; // Allow transparency
        
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:screenSize format:format];
        
        UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
            @try {
                if (Gleap.sharedInstance.applicationType == FLUTTER) {
                    [self drawFlutterViewsInWindow:keyWindow withContext:rendererContext];
                } else {
                    [self drawStandardViewInWindow:keyWindow withContext:rendererContext];
                }
            } @catch (NSException *innerException) {
                NSLog(@"Gleap: Exception during view drawing: %@", innerException.reason);
                // Fill with a solid color as fallback
                [[UIColor lightGrayColor] setFill];
                UIRectFill(CGRectMake(0, 0, screenSize.width, screenSize.height));
            }
        }];
        
        return img;
    } @catch (NSException *exception) {
        NSLog(@"Gleap: Exception in primary capture: %@", exception.reason);
        return nil;
    }
}

+ (UIImage *)performAlternativeCaptureForWindow:(UIWindow *)keyWindow withSize:(CGSize)screenSize {
    @try {
        // Alternative method using older UIGraphicsBeginImageContext
        CGFloat scale = [UIScreen mainScreen].scale;
        UIGraphicsBeginImageContextWithOptions(screenSize, NO, scale);
        
        CGContextRef context = UIGraphicsGetCurrentContext();
        if (!context) {
            UIGraphicsEndImageContext();
            return nil;
        }
        
        @try {
            // Try to render the layer instead of the view hierarchy
            [keyWindow.layer renderInContext:context];
        } @catch (NSException *exception) {
            NSLog(@"Gleap: Exception in alternative capture: %@", exception.reason);
            // Fill with placeholder
            CGContextSetFillColorWithColor(context, [UIColor lightGrayColor].CGColor);
            CGContextFillRect(context, CGRectMake(0, 0, screenSize.width, screenSize.height));
        }
        
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        return image;
    } @catch (NSException *exception) {
        NSLog(@"Gleap: Exception in alternative capture method: %@", exception.reason);
        return nil;
    }
}

+ (void)drawFlutterViewsInWindow:(UIWindow *)keyWindow withContext:(UIGraphicsImageRendererContext *)rendererContext {
    NSArray *views = keyWindow.subviews;
    for (UIView *view in views) {
        @try {
            // Additional validation for each view
            if ([self isViewSafeToRender:view] && 
                CGRectIntersectsRect(keyWindow.bounds, view.frame)) {
                
                // Use bounds instead of frame for drawing
                CGRect drawRect = view.bounds;
                if (!CGRectIsEmpty(drawRect) && !CGRectIsInfinite(drawRect)) {
                    [view drawViewHierarchyInRect:drawRect afterScreenUpdates:NO];
                }
            }
        } @catch (NSException *viewException) {
            NSLog(@"Gleap: Exception drawing Flutter view: %@", viewException.reason);
            // Continue with next view
        }
    }
}

+ (void)drawStandardViewInWindow:(UIWindow *)keyWindow withContext:(UIGraphicsImageRendererContext *)rendererContext {
    @try {
        BOOL success = [keyWindow drawViewHierarchyInRect:keyWindow.bounds afterScreenUpdates:NO];
        if (!success) {
            NSLog(@"Gleap: drawViewHierarchyInRect failed, trying layer rendering");
            // Fallback to layer rendering
            [keyWindow.layer renderInContext:rendererContext.CGContext];
        }
    } @catch (NSException *exception) {
        NSLog(@"Gleap: Exception in standard view drawing: %@", exception.reason);
        // Fallback to layer rendering
        @try {
            [keyWindow.layer renderInContext:rendererContext.CGContext];
        } @catch (NSException *layerException) {
            NSLog(@"Gleap: Layer rendering also failed: %@", layerException.reason);
        }
    }
}

+ (BOOL)isViewSafeToRender:(UIView *)view {
    if (!view || view.isHidden || view.alpha <= 0.0) {
        return NO;
    }
    
    // Check for valid frame
    CGRect frame = view.frame;
    if (CGRectIsEmpty(frame) || CGRectIsInfinite(frame) || CGRectIsNull(frame)) {
        return NO;
    }
    
    // Check for reasonable size limits
    if (frame.size.width > 10000 || frame.size.height > 10000) {
        return NO;
    }
    
    return YES;
}

+ (BOOL)isValidImage:(UIImage *)image {
    if (!image) {
        return NO;
    }
    
    CGSize size = image.size;
    if (CGSizeEqualToSize(size, CGSizeZero) || 
        size.width <= 0 || size.height <= 0) {
        return NO;
    }
    
    // Check if image has valid CGImage
    if (!image.CGImage) {
        return NO;
    }
    
    return YES;
}

@end
