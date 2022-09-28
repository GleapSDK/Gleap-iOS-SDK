//
//  GleapUIWindow.m
//  
//
//  Created by Lukas Boehler on 09.09.22.
//

#import "GleapUIWindow.h"

@implementation GleapUIWindow

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.rootViewController == nil) {
        return NO;
    }
    
    for (int i = 0; i < self.rootViewController.view.subviews.count; i++) {
        UIView *view = [self.rootViewController.view.subviews objectAtIndex: i];
        if (view != nil && !view.isHidden) {
            CGPoint pointInView = [self convertPoint: point toView: view];
            Boolean pointInside = [view pointInside: pointInView withEvent: event];
            if(pointInside && self.delegate != nil && [self.delegate respondsToSelector:@selector(pressedView:)]) {
                [self.delegate pressedView: view];
            }
        }
    }
    
    return NO;
}

- (BOOL)canBecomeFirstResponder
{
    return NO;
}

- (BOOL)becomeFirstResponder
{
    return NO;
}

- (void)becomeKeyWindow
{
    [[self class] findAndSetSuitableKeyWindow];
}

#pragma mark - Finding better key windows

static BOOL IsAllowedKeyWindow(UIWindow *window)
{
    NSString *className = [[window class] description];
    if([className isEqual:@"UIRemoteKeyboardWindow"])
        return NO;
    if([window isKindOfClass:[GleapUIWindow class]])
        return NO;

    return YES;
}

+ (UIWindow*)suitableWindowToMakeKeyExcluding:(UIWindow*)notThis
{
    NSArray *windows = [UIApplication sharedApplication].windows;
    NSInteger index = windows.count-1;

    UIWindow *nextWindow = [windows objectAtIndex:index];
    while((!IsAllowedKeyWindow(nextWindow) || nextWindow == notThis) && index >= 0) {
        nextWindow = windows[--index];
    }
    return nextWindow;
}

+ (UIWindow*)findAndSetSuitableKeyWindow
{
    UIWindow *nextWindow = [[self class] suitableWindowToMakeKeyExcluding:nil];
    [nextWindow makeKeyWindow];
    return nextWindow;
}

@end
