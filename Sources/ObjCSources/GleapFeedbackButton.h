//
//  GleapFeedbackButton.h
//  
//
//  Created by Lukas Boehler on 09.09.22.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapFeedbackButton : UIView

@property (nonatomic, retain) UIImageView *logoView;

- (void)applyConfig;
- (void)setNotificationCount:(int)notificationCount;

@property (nonatomic, retain) NSString *currentButtonUrl;
@property (nonatomic, retain) UIView *notificationBadgeView;
@property (nonatomic, retain) UILabel *notificationBadgeLabel;

@end

NS_ASSUME_NONNULL_END
