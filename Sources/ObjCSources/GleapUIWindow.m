//
//  GleapUIWindow.m
//  
//
//  Created by Lukas Boehler on 09.09.22.
//

#import "GleapUIWindow.h"

@implementation GleapUIWindow

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    for (int i = 0; i < self.subviews.count; i++) {
        UIView *view = [self.subviews objectAtIndex: i];
        if (view != nil) {
            CGPoint pointInView = [self convertPoint: point toView: view];
            return [view pointInside: pointInView withEvent: event];
        }
    }
    
    return NO;
}

@end
