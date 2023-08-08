//
//  UIViewController+GleapViewControllerHelper.m
//  
//
//  Created by Lukas Boehler on 07.08.23.
//

#import "UIViewController+GleapViewControllerHelper.h"
#import "GleapUIOverlayHelper.h"
#import <objc/runtime.h>

void swizzleMethod(Class class, SEL originalSelector, SEL swizzledSelector) {
    Method originalMethod = class_getInstanceMethod(class, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);

    BOOL didAddMethod = class_addMethod(class,
                                        originalSelector,
                                        method_getImplementation(swizzledMethod),
                                        method_getTypeEncoding(swizzledMethod));

    if (didAddMethod) {
        class_replaceMethod(class,
                            swizzledSelector,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

@implementation UIViewController (Swizzled)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        swizzleMethod([self class], @selector(viewDidAppear:), @selector(swizzled_viewDidAppear:));
        swizzleMethod([self class], @selector(viewDidDisappear:), @selector(swizzled_viewDidDisappear:));
    });
}

- (void)swizzled_viewDidAppear:(BOOL)animated {
    [self swizzled_viewDidAppear:animated];
    
    [[GleapUIOverlayHelper sharedInstance].uiOverlayViewController updateUIPositions];
}

- (void)swizzled_viewDidDisappear:(BOOL)animated {
    [self swizzled_viewDidDisappear:animated];
    
    [[GleapUIOverlayHelper sharedInstance].uiOverlayViewController updateUIPositions];
}

@end
