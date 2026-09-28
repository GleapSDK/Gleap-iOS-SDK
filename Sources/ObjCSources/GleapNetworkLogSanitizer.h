//
//  GleapNetworkLogSanitizer.h
//  Gleap
//
//  Removes sensitive data from network logs before they leave the device.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapNetworkLogSanitizer : NSObject

/*
 Hosts that are never logged: Gleap's own API traffic.
 */
+ (NSArray<NSString *> *)defaultBlacklist;

/*
 YES when the URL contains one of the blacklist entries or a default Gleap host.
 */
+ (BOOL)isURLBlacklisted:(nullable NSString *)url blacklist:(nullable NSArray *)blacklist;

/*
 Returns sanitized copies of the network log entries:
 - entries whose URL matches the blacklist (or a Gleap host) are dropped,
 - request and response headers named like an ignored prop are removed (case-insensitive),
 - Authorization, Proxy-Authorization, Cookie and Set-Cookie values are replaced by "[REDACTED]",
 - ignored props are removed from JSON bodies at any depth (a prop with dots is also a path
   from the root, e.g. "user.password"), from form-encoded bodies and from URL query parameters.
 Entries that are not dictionaries are dropped. Bodies that do not change stay byte-identical.
 */
+ (NSArray<NSDictionary *> *)sanitizeNetworkLogs:(nullable NSArray *)networkLogs
                                    propsToIgnore:(nullable NSArray *)propsToIgnore
                                        blacklist:(nullable NSArray *)blacklist;

@end

NS_ASSUME_NONNULL_END
