//
//  GleapNotificationCardFactory.h
//  Gleap
//
//  Builds the in-app notification cards and their close button, themed like the
//  web widget's notifications.
//

#import <UIKit/UIKit.h>
#import "GleapInternal.h"

NS_ASSUME_NONNULL_BEGIN

GLEAP_INTERNAL
@interface GleapNotificationCardFactory : NSObject

/// A card for a notification (news, checklist or message), `width` points wide, or nil
/// without a loaded config.
+ (nullable UIView *)createNotificationViewFor:(NSDictionary *)notification andWith:(int)width;

/// The round close button that clears all notifications.
+ (UIView *)closeButtonWithTarget:(id)target action:(SEL)action;

@end

NS_ASSUME_NONNULL_END
