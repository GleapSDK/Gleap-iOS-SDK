//
//  UIWindow+GleapTouchRecognizer.m
//  Gleap
//
//  Created by Lukas Boehler on 15.01.21.
//

#import "UIWindow+GleapTouchRecognizer.h"
#import "GleapTouchHelper.h"
#import "GleapReplayHelper.h"

@implementation UIWindow (GleapTouchRecognizer)

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([GleapReplayHelper sharedInstance].running) {
        UITouch *touch = touches.allObjects.firstObject;
        CGPoint point = [touch locationInView: self];
        float x = point.x / self.frame.size.width;
        float y = point.y / self.frame.size.height;
        [GleapTouchHelper addX: x andY: y andType: @"TU"];
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([GleapReplayHelper sharedInstance].running) {
        UITouch *touch = touches.allObjects.firstObject;
        CGPoint point = [touch locationInView: self];
        float x = point.x / self.frame.size.width;
        float y = point.y / self.frame.size.height;
        [GleapTouchHelper addX: x andY: y andType: @"TD"];
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([GleapReplayHelper sharedInstance].running) {
        UITouch *touch = touches.allObjects.firstObject;
        CGPoint point = [touch locationInView: self];
        float x = point.x / self.frame.size.width;
        float y = point.y / self.frame.size.height;
        [GleapTouchHelper addX: x andY: y andType: @"TM"];
    }
}

@end
