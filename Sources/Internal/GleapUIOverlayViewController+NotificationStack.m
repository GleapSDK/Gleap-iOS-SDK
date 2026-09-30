//
//  GleapUIOverlayViewController+NotificationStack.m
//  Gleap
//
//  How the notification cards stack: collapsed as a deck with the newest card in front,
//  expanded as a column, and the animations between the two.
//

#import "GleapUIOverlayViewController+Internal.h"

// The gap between two expanded notification cards.
static const CGFloat kGleapNotificationCardGap = 12.0;

// Collapsed stack: how far the top edge of a card behind peeks out above the
// front card, per depth (depth 1 and depth 2 — anything deeper stays hidden
// until the stack expands).
static const CGFloat kGleapNotificationStackPeek1 = 9.0;
static const CGFloat kGleapNotificationStackPeek2 = 17.0;

// How far back a card scales at each peek depth when collapsed.
static const CGFloat kGleapNotificationStackScale1 = 0.955;
static const CGFloat kGleapNotificationStackScale2 = 0.91;

// Headroom above the front card that keeps the peeking edges inside the
// container, and with them the floating close button.
static const CGFloat kGleapNotificationStackHeadroom = 17.0;

@implementation GleapNotificationsContainerView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // The close button floats 9pt outside the container's top corner, so the
    // default hit testing would miss its overhanging half.
    if (self.overhangingCloseButton != nil && self.overhangingCloseButton.hidden == NO && self.overhangingCloseButton.alpha > 0.01) {
        CGPoint pointInButton = [self convertPoint: point toView: self.overhangingCloseButton];
        if ([self.overhangingCloseButton pointInside: pointInButton withEvent: event]) {
            return [self.overhangingCloseButton hitTest: pointInButton withEvent: event];
        }
    }

    UIView *hit = [super hitTest: point withEvent: event];

    // Touches that land on no card fall through to the host app.
    if (hit == self) {
        return nil;
    }
    return hit;
}

@end

@implementation GleapUIOverlayViewController (NotificationStack)

- (BOOL)isStackCollapsed {
    return self.internalNotifications.count > 1 && !self.stackExpanded;
}

/**
 * A new arrival on an existing stack is choreographed as one deck motion:
 * every card starts where the previous stack state had it (each one depth
 * shallower, the old front still in the front slot) and the new card starts
 * tucked behind the front slot — then the whole deck animates into its new
 * order, so the card visibly emerges from the stack rather than floating up
 * from the space below it.
 */
- (void)animateArrivalForWidth:(CGFloat)width {
    NSUInteger count = self.notificationViews.count;
    if (count < 2) {
        return;
    }

    CGFloat containerHeight = [self stackFrameHeight];
    CGFloat frontHeight = ((UIView *)[self.notificationViews lastObject]).bounds.size.height;
    CGFloat oldFrontHeight = ((UIView *)[self.notificationViews objectAtIndex: count - 2]).bounds.size.height;

    for (NSInteger i = count - 1; i >= 0; i--) {
        UIView *cardView = [self.notificationViews objectAtIndex: i];
        CGFloat cardHeight = cardView.bounds.size.height;
        NSInteger depth = (count - 1) - i;

        if (depth == 0) {
            // The new front card materializes in its slot — a fade with a
            // slight scale-up and NO travel, so it can never read as arriving
            // from somewhere else on the screen.
            cardView.alpha = 0.0;
            cardView.transform = CGAffineTransformMakeScale(0.97, 0.97);
            cardView.center = CGPointMake(width / 2.0, (containerHeight - frontHeight) + ((cardHeight * 0.97) / 2.0));
        } else if (depth == 1) {
            // The previous front, still in the front slot.
            cardView.transform = CGAffineTransformIdentity;
            cardView.alpha = 1.0;
            cardView.center = CGPointMake(width / 2.0, (containerHeight - oldFrontHeight) + (cardHeight / 2.0));
        } else {
            NSInteger previousDepth = depth - 1;
            CGFloat peek = previousDepth == 1 ? kGleapNotificationStackPeek1 : kGleapNotificationStackPeek2;
            CGFloat scale = previousDepth == 1 ? kGleapNotificationStackScale1 : kGleapNotificationStackScale2;
            cardView.transform = CGAffineTransformMakeScale(scale, scale);
            cardView.alpha = previousDepth > 2 ? 0.0 : 1.0;
            cardView.center = CGPointMake(width / 2.0, (containerHeight - oldFrontHeight - peek) + ((cardHeight * scale) / 2.0));
        }
    }

    [UIView animateWithDuration: 0.3
                          delay: 0.0
                        options: UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations: ^{
        [self applyStackLayoutForWidth: width animatedMasks: YES];
    } completion: nil];
}

// The container's fixed height (set once per render); card placement is
// bottom-anchored inside it.
- (CGFloat)stackFrameHeight {
    CGFloat height = self.notificationsContainerHeightConstraint.constant;
    if (height <= 0) {
        height = 900.0;
    }
    return height;
}

/**
 * Places every card for the current stack state. Cards are bottom-anchored:
 * expanded they form a column with a fixed gap, collapsed the newest card sits
 * in front with up to two older cards peeking out behind its top edge, scaled
 * back like a deck. Anything deeper stays hidden until the stack expands.
 */
- (void)applyStackLayoutForWidth:(CGFloat)width {
    [self applyStackLayoutForWidth: width animatedMasks: NO];
}

/**
 * Every card carries a mask at ALL times: generous insets (-40) keep the
 * shadow alive, the bottom edge either opens past the body (resting) or cuts
 * at the front card's height in card space (collapsed behind). Transitions
 * ANIMATE the mask in lockstep with the card's motion — the sweeping edge
 * never lets a tall card's body poke out below the stack mid-flight, matching
 * the web widget's animated clip-path. The edge starts clamped to the card's
 * body, which is a visual no-op for the body and only trims the last bit of
 * shadow throw for the duration of the flight.
 */
- (void)applyMaskToCard:(UIView *)cardView visibleHeight:(CGFloat)visibleHeight animated:(BOOL)animated {
    CALayer *maskLayer = cardView.layer.mask;
    CGRect targetFrame = CGRectMake(-40.0, -40.0, cardView.bounds.size.width + 80.0, visibleHeight + 40.0);

    if (maskLayer == nil) {
        maskLayer = [CALayer layer];
        maskLayer.backgroundColor = [UIColor blackColor].CGColor;
        [CATransaction begin];
        [CATransaction setDisableActions: YES];
        maskLayer.frame = targetFrame;
        cardView.layer.mask = maskLayer;
        [CATransaction commit];
        return;
    }

    [CATransaction begin];
    if (animated) {
        // Clamp the starting edge to the card's body so the sweep can never
        // trail below the front card's bottom.
        CGFloat cardHeight = cardView.bounds.size.height;
        if (maskLayer.frame.size.height - 40.0 > cardHeight) {
            [CATransaction setDisableActions: YES];
            maskLayer.frame = CGRectMake(-40.0, -40.0, cardView.bounds.size.width + 80.0, cardHeight + 40.0);
            [CATransaction commit];
            [CATransaction begin];
        }
        [CATransaction setAnimationDuration: 0.3];
        [CATransaction setAnimationTimingFunction: [CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionEaseOut]];
    } else {
        [CATransaction setDisableActions: YES];
    }
    maskLayer.frame = targetFrame;
    [CATransaction commit];
}

- (void)applyStackLayoutForWidth:(CGFloat)width animatedMasks:(BOOL)animatedMasks {
    NSUInteger count = self.notificationViews.count;
    if (count == 0) {
        return;
    }

    CGFloat containerHeight = [self stackFrameHeight];

    BOOL collapsed = [self isStackCollapsed];
    CGFloat frontHeight = ((UIView *)[self.notificationViews lastObject]).frame.size.height;
    CGFloat frontTop = containerHeight - frontHeight;

    // Walk newest → oldest so each card knows its depth behind the front.
    CGFloat expandedBottom = containerHeight;
    for (NSInteger i = count - 1; i >= 0; i--) {
        UIView *cardView = [self.notificationViews objectAtIndex: i];
        CGFloat cardHeight = cardView.frame.size.height;
        NSInteger depth = (count - 1) - i;

        if (collapsed && depth > 0) {
            CGFloat peek = depth == 1 ? kGleapNotificationStackPeek1 : kGleapNotificationStackPeek2;
            CGFloat scale = depth == 1 ? kGleapNotificationStackScale1 : kGleapNotificationStackScale2;

            cardView.transform = CGAffineTransformMakeScale(scale, scale);
            cardView.center = CGPointMake(width / 2.0, (frontTop - peek) + ((cardHeight * scale) / 2.0));
            cardView.alpha = depth > 2 ? 0.0 : 1.0;

            // Clips a taller card behind to the front card's own height (in
            // card space, like the web widget), so e.g. a news cover can't
            // hang out below the stack. After the peek offset and scale-back,
            // the clipped bottom lands above the front card's bottom — the
            // area behind its rounded corners stays clear, nothing shines
            // through them. The negative insets keep the shadow outside the
            // clipped edge alive.
            CGFloat visibleCardHeight = cardHeight > frontHeight ? frontHeight : cardHeight + 40.0;
            [self applyMaskToCard: cardView visibleHeight: visibleCardHeight animated: animatedMasks];
        } else {
            cardView.transform = CGAffineTransformIdentity;
            cardView.center = CGPointMake(width / 2.0, expandedBottom - (cardHeight / 2.0));
            cardView.alpha = 1.0;
            [self applyMaskToCard: cardView visibleHeight: cardHeight + 40.0 animated: animatedMasks];
        }

        expandedBottom -= cardHeight + kGleapNotificationCardGap;
    }

    // The close button floats over the stack's visual top corner and rides
    // along as the stack expands or collapses. It trails the stack in LTR and
    // mirrors to the leading edge in RTL layouts.
    CGFloat contentHeight = (kGleapNotificationCardGap * (count - 1));
    for (UIView *cardView in self.notificationViews) {
        contentHeight += cardView.bounds.size.height;
    }
    CGFloat visualTop;
    if (collapsed) {
        visualTop = containerHeight - frontHeight - kGleapNotificationStackHeadroom;
    } else {
        visualTop = containerHeight - contentHeight;
    }

    BOOL isRTL = NO;
    if (self.notificationsContainerView != nil) {
        isRTL = [UIView userInterfaceLayoutDirectionForSemanticContentAttribute: self.notificationsContainerView.semanticContentAttribute] == UIUserInterfaceLayoutDirectionRightToLeft;
    }
    CGFloat closeSize = self.notificationsCloseButton.frame.size.width;
    CGFloat closeX = isRTL ? -9.0 : width - closeSize + 9.0;
    self.notificationsCloseButton.frame = CGRectMake(closeX, visualTop - 9.0, closeSize, closeSize);
}

- (void)setStackExpanded:(BOOL)expanded animated:(BOOL)animated {
    if (self.stackExpanded == expanded || self.notificationViews.count <= 1) {
        return;
    }
    self.stackExpanded = expanded;

    CGFloat width = self.notificationsContainerView.frame.size.width;
    if (width <= 0) {
        width = 320;
    }

    if (!animated || UIAccessibilityIsReduceMotionEnabled()) {
        [self applyStackLayoutForWidth: width];
        [self.notificationsContainerView.superview layoutIfNeeded];
        return;
    }

    [UIView animateWithDuration: 0.3
                          delay: 0.0
                        options: UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations: ^{
        [self applyStackLayoutForWidth: width animatedMasks: YES];
        [self.notificationsContainerView.superview layoutIfNeeded];
    } completion: nil];
}

@end
