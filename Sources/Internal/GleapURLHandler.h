//
//  GleapURLHandler.h
//  Gleap
//
//  What happens with a URL the widget, a banner, a modal or the app hands to Gleap.
//

#import <UIKit/UIKit.h>
#import "GleapInternal.h"

NS_ASSUME_NONNULL_BEGIN

GLEAP_INTERNAL
@interface GleapURLHandler : NSObject

/// gleap:// links open the matching Gleap screen. Other URLs go to the delegate's
/// openExternalLink: when it is implemented, otherwise web links open in Safari and any other
/// scheme in the app that handles it (closing the widget first, except for tel: and mailto:).
+ (void)handleURL:(nullable NSString *)url;

@end

NS_ASSUME_NONNULL_END
