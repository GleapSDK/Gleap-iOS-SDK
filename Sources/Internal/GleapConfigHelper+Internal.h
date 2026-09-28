//
//  GleapConfigHelper+Internal.h
//  Gleap
//
//  The part of the config helper the rest of the SDK uses but the public header doesn't show.
//

#import "GleapConfigHelper.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapConfigHelper ()

/// For an initialize with the API key the SDK already runs with (a reloaded JavaScript context:
/// React Native reload or OTA update, Capacitor WebView reload): once the config has loaded, tells
/// the delegate set at that point configLoaded: (with the loaded config) and then initialized, on
/// the main queue, without loading anything. Before the first load, the load that is still to come
/// tells that delegate, so nothing is repeated.
- (void)repeatInitializeCallbacks;

@end

NS_ASSUME_NONNULL_END
