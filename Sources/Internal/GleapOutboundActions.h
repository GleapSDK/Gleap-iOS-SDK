//
//  GleapOutboundActions.h
//  Gleap
//
//  The actions a banner or modal can trigger (start a conversation, open a form, survey,
//  news article, help article or checklist, open a URL).
//

#import <Foundation/Foundation.h>
#import "GleapInternal.h"

NS_ASSUME_NONNULL_BEGIN

GLEAP_INTERNAL
@interface GleapOutboundActions : NSObject

/// YES for the message names performAction:data: handles.
+ (BOOL)handlesAction:(nullable NSString *)name;

/// Performs the action a banner or modal message asked for; does nothing for other names.
+ (void)performAction:(nullable NSString *)name data:(nullable id)data;

/// Hands a banner's or modal's custom action to the app: customActionCalled:withShareToken: when
/// the delegate implements it, otherwise customActionCalled:. An action that is not a string is
/// dropped.
+ (void)notifyCustomAction:(nullable id)action;

@end

NS_ASSUME_NONNULL_END
