//
//  UIWindow+GleapTouchRecognizer.m
//  Gleap
//
//  Created by Lukas Boehler on 15.01.21.
//

#import "UIWindow+GleapTouchRecognizer.h"
#import "GleapTouchHelper.h"
#import "GleapReplayHelper.h"

// UIWindow has no touch methods of its own, so these category methods add them; calling super
// hands the touches on to UIResponder, which passes them along the responder chain.
@implementation UIWindow (GleapTouchRecognizer)

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([GleapReplayHelper sharedInstance].running) {
        UITouch *touch = touches.allObjects.firstObject;
        CGPoint point = [touch locationInView: self];
        float x = point.x / self.frame.size.width;
        float y = point.y / self.frame.size.height;
        [GleapTouchHelper addX: x andY: y andType: @"TU"];
    }
    [super touchesEnded: touches withEvent: event];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([GleapReplayHelper sharedInstance].running) {
        UITouch *touch = touches.allObjects.firstObject;
        CGPoint point = [touch locationInView: self];
        float x = point.x / self.frame.size.width;
        float y = point.y / self.frame.size.height;
        [GleapTouchHelper addX: x andY: y andType: @"TD"];
    }
    [super touchesBegan: touches withEvent: event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([GleapReplayHelper sharedInstance].running) {
        UITouch *touch = touches.allObjects.firstObject;
        CGPoint point = [touch locationInView: self];
        float x = point.x / self.frame.size.width;
        float y = point.y / self.frame.size.height;
        [GleapTouchHelper addX: x andY: y andType: @"TM"];
    }
    [super touchesMoved: touches withEvent: event];
}

@end
