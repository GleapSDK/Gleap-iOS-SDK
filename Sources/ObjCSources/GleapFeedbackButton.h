//
//  GleapFeedbackButton.h
//  
//
//  Created by Lukas Boehler on 09.09.22.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapFeedbackButton : UIView

@property (nonatomic, retain) UIImageView *logoView;

- (void)applyConfig;
- (void)updateVisibility;
- (void)setNotificationCount:(int)notificationCount;

@property (nonatomic, assign) bool initialized;
@property (nonatomic, assign) bool showButton;
@property (nonatomic, retain) NSString *currentButtonUrl;
@property (nonatomic, retain) UIView *notificationBadgeView;
@property (nonatomic, retain) UILabel *notificationBadgeLabel;
@property (nonatomic, retain) UILabel *buttonTextLabel;
@property (strong, nonatomic) NSLayoutConstraint *safeAreaConstraint;
@property (strong, nonatomic) NSLayoutConstraint *edgeConstraint;

@end

NS_ASSUME_NONNULL_END
