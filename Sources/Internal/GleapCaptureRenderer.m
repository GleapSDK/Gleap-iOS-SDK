//
//  GleapCaptureRenderer.m
//  Gleap
//

#import "GleapCaptureRenderer.h"
#import "GleapCore.h"
#import "GleapWindowChecker.h"

// A view hierarchy walk for secure text fields stops after this many views per window.
static NSUInteger const kGleapMaxViewsPerMaskWalk = 20000;

@implementation GleapCaptureRenderer

#pragma mark - Scene and windows

+ (UIWindowScene *)foregroundWindowScene {
    UIWindowScene *keyScene = [GleapWindowChecker getKeyWindow].windowScene;
    if (keyScene != nil && keyScene.activationState == UISceneActivationStateForegroundActive) {
        return keyScene;
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass: [UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene *)scene;
        }
    }
    return keyScene;
}

+ (CGRect)canvasBoundsForScene:(UIWindowScene *)scene {
    CGRect bounds = scene.coordinateSpace.bounds;
    if (CGRectIsEmpty(bounds)) {
        for (UIWindow *window in scene.windows) {
            if (!window.isHidden && !CGRectIsEmpty(window.bounds)) {
                return window.bounds;
            }
        }
    }
    return bounds;
}

+ (NSArray<UIWindow *> *)capturableWindowsInScene:(UIWindowScene *)scene {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIWindow *window in scene.windows) {
        if (window.isHidden || window.alpha < 0.01 || CGRectIsEmpty(window.bounds)) {
            continue;
        }
        if ([self isExcludedWindow: window] || [self isKeyboardWindow: window]) {
            continue;
        }
        [windows addObject: window];
    }
    // Back to front. The sort is stable, so windows of one level keep the scene's order.
    [windows sortWithOptions: NSSortStable usingComparator:^NSComparisonResult(UIWindow *first, UIWindow *second) {
        if (first.windowLevel < second.windowLevel) {
            return NSOrderedAscending;
        }
        if (first.windowLevel > second.windowLevel) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    return windows;
}

+ (BOOL)isExcludedWindow:(UIWindow *)window {
    return [window conformsToProtocol: @protocol(GleapExcludedFromCapture)];
}

+ (BOOL)isKeyboardWindow:(UIWindow *)window {
    // The keyboard (UIRemoteKeyboardWindow) and the text loupe / selection UI (UITextEffectsWindow) show what
    // the user types; they are never part of a capture.
    NSString *className = NSStringFromClass([window class]);
    if ([className hasPrefix: @"UITextEffectsWindow"] || [className hasPrefix: @"UIRemoteKeyboardWindow"]) {
        return YES;
    }
    return ([className hasPrefix: @"UI"] || [className hasPrefix: @"_UI"]) && [className containsString: @"Keyboard"];
}

#pragma mark - Drawing

+ (void)drawWindows:(NSArray<UIWindow *> *)windows
            inScene:(UIWindowScene *)scene
             canvas:(CGRect)canvas
        maskedViews:(NSArray<UIView *> *)maskedViews
            context:(CGContextRef)context {
    if (context == NULL) {
        return;
    }
    id<UICoordinateSpace> space = scene.coordinateSpace;
    BOOL isFlutter = [Gleap sharedInstance].applicationType == FLUTTER;
    for (UIWindow *window in windows) {
        @try {
            CGRect frame = [window convertRect: window.bounds toCoordinateSpace: space];
            frame = CGRectOffset(frame, -canvas.origin.x, -canvas.origin.y);
            if (CGRectIsEmpty(frame) || !CGRectIntersectsRect(frame, CGRectMake(0, 0, canvas.size.width, canvas.size.height))) {
                continue;
            }
            [self drawWindow: window inRect: frame isFlutter: isFlutter context: context];
            [self fillMasksOfWindow: window maskedViews: maskedViews space: space canvas: canvas context: context];
        } @catch (NSException *exception) {
            NSLog(@"[GLEAP_SDK] Could not capture a window: %@", exception.reason);
        }
    }
}

+ (void)drawWindow:(UIWindow *)window inRect:(CGRect)rect isFlutter:(BOOL)isFlutter context:(CGContextRef)context {
    BOOL drawn = NO;
    if (isFlutter) {
        // Flutter renders into its own layer; its top-level views are drawn one by one, each at its real frame
        // in the window (drawing them at their bounds origin put every smaller view at the top left).
        CGFloat scaleX = rect.size.width / MAX(window.bounds.size.width, 1.0);
        CGFloat scaleY = rect.size.height / MAX(window.bounds.size.height, 1.0);
        for (UIView *view in window.subviews) {
            if (view.isHidden || view.alpha < 0.01 || CGRectIsEmpty(view.bounds)) {
                continue;
            }
            @try {
                CGRect frame = [view convertRect: view.bounds toView: window];
                CGRect target = CGRectMake(rect.origin.x + frame.origin.x * scaleX,
                                           rect.origin.y + frame.origin.y * scaleY,
                                           frame.size.width * scaleX,
                                           frame.size.height * scaleY);
                if (!CGRectIsEmpty(target) && [view drawViewHierarchyInRect: target afterScreenUpdates: NO]) {
                    drawn = YES;
                }
            } @catch (NSException *exception) {}
        }
    }
    if (!drawn) {
        drawn = [window drawViewHierarchyInRect: rect afterScreenUpdates: NO];
    }
    if (!drawn) {
        // Last resort: the layer tree (misses Metal / video content, but better than a black window).
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, rect.origin.x, rect.origin.y);
        CGContextScaleCTM(context, rect.size.width / MAX(window.bounds.size.width, 1.0), rect.size.height / MAX(window.bounds.size.height, 1.0));
        @try {
            [window.layer renderInContext: context];
        } @catch (NSException *exception) {}
        CGContextRestoreGState(context);
    }
}

#pragma mark - Masks

+ (void)fillMasksOfWindow:(UIWindow *)window
              maskedViews:(NSArray<UIView *> *)maskedViews
                    space:(id<UICoordinateSpace>)space
                   canvas:(CGRect)canvas
                  context:(CGContextRef)context {
    NSMutableArray<NSValue *> *rects = [NSMutableArray array];
    for (UIView *view in maskedViews) {
        if (view.window == window && [self isViewVisible: view]) {
            [rects addObject: [NSValue valueWithCGRect: [self rectOfView: view inSpace: space canvas: canvas]]];
        }
    }
    [self collectSensitiveInputRectsInWindow: window space: space canvas: canvas into: rects];
    if (rects.count == 0) {
        return;
    }
    CGContextSaveGState(context);
    CGContextSetFillColorWithColor(context, [UIColor blackColor].CGColor);
    for (NSValue *value in rects) {
        CGContextFillRect(context, value.CGRectValue);
    }
    CGContextRestoreGState(context);
}

+ (BOOL)isViewVisible:(UIView *)view {
    if (CGRectIsEmpty(view.bounds)) {
        return NO;
    }
    for (UIView *current = view; current != nil; current = current.superview) {
        if (current.isHidden || current.alpha < 0.01) {
            return NO;
        }
    }
    return YES;
}

+ (CGRect)rectOfView:(UIView *)view inSpace:(id<UICoordinateSpace>)space canvas:(CGRect)canvas {
    CGRect rect = [view convertRect: view.bounds toCoordinateSpace: space];
    rect = CGRectOffset(rect, -canvas.origin.x, -canvas.origin.y);
    // A point more on each side, so no antialiased edge of the content shows.
    return CGRectInset(rect, -1.0, -1.0);
}

+ (void)collectSensitiveInputRectsInWindow:(UIWindow *)window
                                     space:(id<UICoordinateSpace>)space
                                    canvas:(CGRect)canvas
                                      into:(NSMutableArray<NSValue *> *)rects {
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject: window];
    NSUInteger visited = 0;
    while (stack.count > 0 && visited < kGleapMaxViewsPerMaskWalk) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        visited++;
        if (view.isHidden || view.alpha < 0.01) {
            continue;
        }
        if ([self isSensitiveTextInput: view]) {
            if (!CGRectIsEmpty(view.bounds)) {
                [rects addObject: [NSValue valueWithCGRect: [self rectOfView: view inSpace: space canvas: canvas]]];
            }
            continue;
        }
        [stack addObjectsFromArray: view.subviews];
    }
}

+ (BOOL)isSensitiveTextInput:(UIView *)view {
    if ([view isKindOfClass: [UITextField class]]) {
        UITextField *field = (UITextField *)view;
        return field.isSecureTextEntry || [self isSensitiveContentType: field.textContentType];
    }
    if ([view isKindOfClass: [UITextView class]]) {
        UITextView *textView = (UITextView *)view;
        return textView.isSecureTextEntry || [self isSensitiveContentType: textView.textContentType];
    }
    return NO;
}

+ (BOOL)isSensitiveContentType:(UITextContentType)contentType {
    if (contentType.length == 0) {
        return NO;
    }
    static NSSet<NSString *> *sensitiveTypes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableSet *types = [NSMutableSet setWithArray: @[
            UITextContentTypePassword,
            UITextContentTypeNewPassword,
            UITextContentTypeOneTimeCode,
            UITextContentTypeCreditCardNumber,
        ]];
        if (@available(iOS 17.0, *)) {
            [types addObject: UITextContentTypeCreditCardSecurityCode];
        }
        sensitiveTypes = types;
    });
    return [sensitiveTypes containsObject: contentType];
}

#pragma mark - Screenshot

+ (UIImage *)screenshotOfScene:(UIWindowScene *)scene maxLongEdge:(CGFloat)maxLongEdge maskedViews:(NSArray<UIView *> *)maskedViews {
    CGRect canvas = [self canvasBoundsForScene: scene];
    NSArray<UIWindow *> *windows = [self capturableWindowsInScene: scene];
    if (CGRectIsEmpty(canvas) || windows.count == 0) {
        return nil;
    }
    CGFloat screenScale = scene.screen.scale > 0 ? scene.screen.scale : UIScreen.mainScreen.scale;
    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = [self pixelScaleForCanvasSize: canvas.size screenScale: screenScale maxLongEdge: maxLongEdge];
    format.opaque = YES;
    format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize: canvas.size format: format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        CGContextRef context = rendererContext.CGContext;
        CGContextSetFillColorWithColor(context, [UIColor blackColor].CGColor);
        CGContextFillRect(context, CGRectMake(0, 0, canvas.size.width, canvas.size.height));
        [self drawWindows: windows inScene: scene canvas: canvas maskedViews: maskedViews context: context];
    }];
}

#pragma mark - Geometry

+ (CGFloat)pixelScaleForCanvasSize:(CGSize)canvas screenScale:(CGFloat)screenScale maxLongEdge:(CGFloat)maxLongEdge {
    CGFloat scale = screenScale > 0 ? screenScale : 1.0;
    CGFloat longEdge = MAX(canvas.width, canvas.height);
    if (longEdge <= 0) {
        return scale;
    }
    if (maxLongEdge > 0 && longEdge * scale > maxLongEdge) {
        // Rounded down, so the rendered long edge never ends up a pixel above the limit.
        scale = floor((maxLongEdge / longEdge) * 1000.0) / 1000.0;
    }
    return MAX(scale, 0.001);
}

+ (CGSize)videoSizeForCanvasSize:(CGSize)canvas screenScale:(CGFloat)screenScale maxLongEdge:(CGFloat)maxLongEdge {
    CGFloat scale = screenScale > 0 ? screenScale : 1.0;
    CGFloat width = MAX(canvas.width, 0) * scale;
    CGFloat height = MAX(canvas.height, 0) * scale;
    CGFloat longEdge = MAX(width, height);
    if (maxLongEdge > 0 && longEdge > maxLongEdge) {
        CGFloat factor = maxLongEdge / longEdge;
        width *= factor;
        height *= factor;
    }
    width = MAX(2.0, floor((width + 0.001) / 2.0) * 2.0);
    height = MAX(2.0, floor((height + 0.001) / 2.0) * 2.0);
    return CGSizeMake(width, height);
}

+ (CGRect)letterboxRectForContentSize:(CGSize)contentSize inOutputSize:(CGSize)outputSize {
    if (contentSize.width <= 0 || contentSize.height <= 0 || outputSize.width <= 0 || outputSize.height <= 0) {
        return CGRectZero;
    }
    // The size the video was made for (only rounded to even pixels): fill it, instead of a hairline of black.
    CGFloat contentAspect = contentSize.width / contentSize.height;
    CGFloat outputAspect = outputSize.width / outputSize.height;
    if (fabs(contentAspect - outputAspect) / outputAspect < 0.01) {
        return CGRectMake(0, 0, outputSize.width, outputSize.height);
    }
    CGFloat scale = MIN(outputSize.width / contentSize.width, outputSize.height / contentSize.height);
    CGFloat width = MIN(round(contentSize.width * scale), outputSize.width);
    CGFloat height = MIN(round(contentSize.height * scale), outputSize.height);
    CGFloat x = floor((outputSize.width - width) / 2.0);
    CGFloat y = floor((outputSize.height - height) / 2.0);
    return CGRectMake(x, y, MAX(width, 1.0), MAX(height, 1.0));
}

@end
