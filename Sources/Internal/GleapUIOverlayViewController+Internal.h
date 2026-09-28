//
//  GleapUIOverlayViewController+Internal.h
//  Gleap
//
//  Private state of the overlay controller, shared with its notification stack category.
//

#import "GleapUIOverlayViewController.h"

/**
 * The notifications container spans the whole stack (plus the headroom the
 * peeking cards need), so empty regions must hand touches back to the app,
 * and the close button — floating slightly outside the top corner — must
 * still be tappable.
 */
@interface GleapNotificationsContainerView : UIView

@property (nonatomic, weak) UIView *overhangingCloseButton;

@end

@interface GleapUIOverlayViewController ()

@property (nonatomic, assign) int lastNotificationCount;
@property (nonatomic, assign) BOOL stackExpanded;
@property (nonatomic, assign) NSUInteger lastRenderedNotificationCount;
@property (nonatomic, retain, nullable) NSString *lastRenderedFrontOutboundId;
@property (nonatomic, retain, nullable) NSLayoutConstraint *notificationsContainerHeightConstraint;
@property (nonatomic, retain, nullable) UIView *notificationsCloseButton;

@end

/// Stacking, expanding and animating the notification cards.
@interface GleapUIOverlayViewController (NotificationStack)
- (BOOL)isStackCollapsed;
- (void)applyStackLayoutForWidth:(CGFloat)width;
- (void)animateArrivalForWidth:(CGFloat)width;
- (void)setStackExpanded:(BOOL)expanded animated:(BOOL)animated;
@end
