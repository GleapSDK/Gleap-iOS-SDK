//
//  GleapCaptureRenderer.m
//  Gleap
//

#import "GleapCaptureRenderer.h"
#import "GleapBanner.h"
#import "GleapCore.h"
#import "GleapFeedbackButton.h"
#import "GleapModal.h"
#import "GleapUIOverlayViewController+Internal.h"
#import "GleapWindowChecker.h"
#import <QuartzCore/QuartzCore.h>

// A view hierarchy walk for secure text fields stops after this many views per window.
static NSUInteger const kGleapMaxViewsPerMaskWalk = 20000;
// Points added on every side of a mask: antialiased edges, and a little play between the masks' geometry and the
// snapshot of the screen.
static CGFloat const kGleapMaskPadding = 3.0;

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
        CGRect frame = CGRectNull;
        NSArray<UIView *> *targets = nil;
        NSArray<NSValue *> *before = nil;
        @try {
            frame = [window convertRect: window.bounds toCoordinateSpace: space];
            frame = CGRectOffset(frame, -canvas.origin.x, -canvas.origin.y);
            if (CGRectIsEmpty(frame) || !CGRectIntersectsRect(frame, CGRectMake(0, 0, canvas.size.width, canvas.size.height))) {
                continue;
            }
            // The snapshot shows the screen of this very moment, mid-animation. Core Animation reports the on-screen
            // (presentation) geometry of the moment the run loop turn began, though, which can be well before the
            // snapshot (windows drawn earlier take time). A flush starts a fresh transaction, so the geometry taken
            // right before and right after the snapshot brackets what it shows.
            [CATransaction flush];
            targets = [self maskTargetsInWindow: window maskedViews: maskedViews];
            before = [self presentationRectsOfViews: targets inWindow: window];
        } @catch (NSException *exception) {
            // Without knowing what to mask, the window is left out.
            NSLog(@"[GLEAP_SDK] Could not capture a window: %@", exception.reason);
            continue;
        }
        @try {
            [self drawWindow: window inRect: frame isFlutter: isFlutter context: context];
        } @catch (NSException *exception) {
            NSLog(@"[GLEAP_SDK] Could not capture a window: %@", exception.reason);
        }
        if (targets.count == 0) {
            continue;
        }
        NSArray<NSValue *> *after = nil;
        @try {
            [CATransaction flush];
            after = [self presentationRectsOfViews: targets inWindow: window];
        } @catch (NSException *exception) {
            after = nil;
        }
        [self fillMasksOfViews: targets inWindow: window windowFrame: frame before: before after: after space: space canvas: canvas context: context];
    }
}

+ (void)drawWindow:(UIWindow *)window inRect:(CGRect)rect isFlutter:(BOOL)isFlutter context:(CGContextRef)context {
    BOOL drawn = NO;
    // The SDK's own views in the app's window (launcher, banner, modal, in-app notifications) are not part of what
    // the user shows: with one of them on screen, the window is drawn view by view without them.
    BOOL hasGleapOverlay = NO;
    for (UIView *view in window.subviews) {
        if ([self isGleapOverlayView: view] && [self isPossiblyVisible: view]) {
            hasGleapOverlay = YES;
            break;
        }
    }
    if (isFlutter || hasGleapOverlay) {
        drawn = [self drawSubviewsOfWindow: window inRect: rect skipInvisible: isFlutter context: context];
        if (!drawn && hasGleapOverlay) {
            // Nothing but the SDK's views: the window's background is all there is to show.
            return;
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

// The window's background, then its subviews one by one, each at its real frame in the window, without the SDK's
// own views. Flutter renders into its own layer and is drawn this way too: drawing its top-level views at their
// bounds origin put every smaller one at the top left.
+ (BOOL)drawSubviewsOfWindow:(UIWindow *)window inRect:(CGRect)rect skipInvisible:(BOOL)skipInvisible context:(CGContextRef)context {
    BOOL drawn = NO;
    CGFloat scaleX = rect.size.width / MAX(window.bounds.size.width, 1.0);
    CGFloat scaleY = rect.size.height / MAX(window.bounds.size.height, 1.0);
    UIColor *background = window.backgroundColor;
    if (background != nil && CGColorGetAlpha(background.CGColor) > 0) {
        CGContextSaveGState(context);
        CGContextSetFillColorWithColor(context, background.CGColor);
        CGContextFillRect(context, rect);
        CGContextRestoreGState(context);
    }
    for (UIView *view in window.subviews) {
        if (view.isHidden || CGRectIsEmpty(view.bounds) || [self isGleapOverlayView: view]) {
            continue;
        }
        if (skipInvisible && view.alpha < 0.01) {
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
    return drawn;
}

+ (BOOL)isGleapOverlayView:(UIView *)view {
    return [view isKindOfClass: [GleapFeedbackButton class]]
        || [view isKindOfClass: [GleapBanner class]]
        || [view isKindOfClass: [GleapModal class]]
        || [view isKindOfClass: [GleapNotificationsContainerView class]];
}

#pragma mark - Masks

// The masked views and sensitive text fields of `window` that may be on screen.
+ (NSArray<UIView *> *)maskTargetsInWindow:(UIWindow *)window maskedViews:(NSArray<UIView *> *)maskedViews {
    NSMutableArray<UIView *> *targets = [NSMutableArray array];
    for (UIView *view in maskedViews) {
        if (view.window == window && [self isPossiblyVisible: view]) {
            [targets addObject: view];
        }
    }
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject: window];
    NSUInteger visited = 0;
    while (stack.count > 0 && visited < kGleapMaxViewsPerMaskWalk) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        visited++;
        if ([self isHiddenNow: view]) {
            continue;
        }
        if ([self isSensitiveTextInput: view]) {
            if (![self hasNoArea: view] && ![targets containsObject: view]) {
                [targets addObject: view];
            }
            continue;
        }
        [stack addObjectsFromArray: view.subviews];
    }
    return targets;
}

// Hidden in the model (where a running animation ends) as well as on screen (where it is right now): a view fading
// out is already invisible in the model but still on screen.
+ (BOOL)isHiddenNow:(UIView *)view {
    if (!view.isHidden && view.alpha >= 0.01) {
        return NO;
    }
    CALayer *presentation = view.layer.presentationLayer;
    return presentation == nil || presentation.isHidden || presentation.opacity < 0.01;
}

+ (BOOL)hasNoArea:(UIView *)view {
    if (!CGRectIsEmpty(view.bounds)) {
        return NO;
    }
    CALayer *presentation = view.layer.presentationLayer;
    return presentation == nil || CGRectIsEmpty(presentation.bounds);
}

+ (BOOL)isPossiblyVisible:(UIView *)view {
    if ([self hasNoArea: view]) {
        return NO;
    }
    for (UIView *current = view; current != nil; current = current.superview) {
        if ([self isHiddenNow: current]) {
            return NO;
        }
    }
    return YES;
}

// Where each view is on screen right now, in its window's coordinates: its presentation layer, placed by the
// presentation layers above it. CGRectNull for a view that has none (not on screen yet).
+ (NSArray<NSValue *> *)presentationRectsOfViews:(NSArray<UIView *> *)views inWindow:(UIWindow *)window {
    NSMutableArray<NSValue *> *rects = [NSMutableArray arrayWithCapacity: views.count];
    for (UIView *view in views) {
        CGRect rect = CGRectNull;
        @try {
            CALayer *layer = view.layer.presentationLayer;
            // The window's layer is not the root of the tree (iOS 26 hosts windows in transform layers): the
            // presentation tree is walked up to the window.
            CALayer *windowLayer = nil;
            for (CALayer *current = layer; current != nil; current = current.superlayer) {
                if (current.modelLayer == window.layer) {
                    windowLayer = current;
                    break;
                }
            }
            if (layer != nil && windowLayer != nil) {
                rect = [layer convertRect: layer.bounds toLayer: windowLayer];
            }
        } @catch (NSException *exception) {
            rect = CGRectNull;
        }
        if (!CGRectIsNull(rect) && (!isfinite(rect.origin.x) || !isfinite(rect.origin.y) || !isfinite(rect.size.width) || !isfinite(rect.size.height))) {
            rect = CGRectNull;
        }
        [rects addObject: [NSValue valueWithCGRect: rect]];
    }
    return rects;
}

// Every view is blacked out where its model puts it (where a running animation ends) and wherever its presentation
// was from right before to right after the snapshot. Should that fail, the whole window is.
+ (void)fillMasksOfViews:(NSArray<UIView *> *)views
                inWindow:(UIWindow *)window
             windowFrame:(CGRect)windowFrame
                  before:(NSArray<NSValue *> *)before
                   after:(NSArray<NSValue *> *)after
                   space:(id<UICoordinateSpace>)space
                  canvas:(CGRect)canvas
                 context:(CGContextRef)context {
    NSMutableArray<NSValue *> *rects = [NSMutableArray arrayWithCapacity: views.count * 2];
    @try {
        [views enumerateObjectsUsingBlock:^(UIView *view, NSUInteger index, BOOL *stop) {
            [rects addObject: [NSValue valueWithCGRect: [view convertRect: view.bounds toView: window]]];
            CGRect first = index < before.count ? before[index].CGRectValue : CGRectNull;
            CGRect second = index < after.count ? after[index].CGRectValue : CGRectNull;
            CGRect swept = CGRectUnion(first, second);
            if (!CGRectIsNull(swept)) {
                [rects addObject: [NSValue valueWithCGRect: swept]];
            }
        }];
        for (NSUInteger index = 0; index < rects.count; index++) {
            CGRect rect = [window convertRect: rects[index].CGRectValue toCoordinateSpace: space];
            rect = CGRectOffset(rect, -canvas.origin.x, -canvas.origin.y);
            rects[index] = [NSValue valueWithCGRect: CGRectInset(rect, -kGleapMaskPadding, -kGleapMaskPadding)];
        }
    } @catch (NSException *exception) {
        NSLog(@"[GLEAP_SDK] Could not place the masks of a window: %@", exception.reason);
        [rects removeAllObjects];
        [rects addObject: [NSValue valueWithCGRect: windowFrame]];
    }
    CGContextSaveGState(context);
    CGContextSetFillColorWithColor(context, [UIColor blackColor].CGColor);
    for (NSValue *value in rects) {
        CGContextFillRect(context, value.CGRectValue);
    }
    CGContextRestoreGState(context);
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
