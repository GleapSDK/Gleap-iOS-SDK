//
//  GleapLogsBundle.h
//  Gleap
//
//  The logs sent for a capture request (POST /v3/shared/capture-requests/{id}/logs): the same data,
//  from the same collectors and in the same shapes as a bug report (/bugs/v2) — console log, network
//  logs, custom data, environment (metaData), custom events and, when asked for and enabled, the
//  native replay — gzipped. Keys that were not collected are left out.
//

#import <Foundation/Foundation.h>
#import "GleapInternal.h"

NS_ASSUME_NONNULL_BEGIN

GLEAP_INTERNAL
@interface GleapLogsBundle : NSObject

/// The request's `include` with its defaults: everything but `replays`.
+ (NSDictionary<NSString *, NSNumber *> *)normalizedInclude:(nullable id)include;

/// Collects the bundle. Call on the main queue; the completion runs on the main queue. Console logs are read off
/// the main queue (the unified log is slow); replay frames are uploaded first (/uploads/sdksteps), as for reports.
+ (void)collectWithInclude:(nullable id)include
               windowStart:(nullable NSDate *)windowStart
                 windowEnd:(nullable NSDate *)windowEnd
                completion:(void (^)(NSDictionary *bundle))completion;

/// The bundle as gzipped JSON, at most `maxBytes`: when it is larger, network logs, then console logs, then events
/// are left out until it fits. Nil when it cannot be encoded.
+ (nullable NSData *)gzippedJSONForBundle:(NSDictionary *)bundle maxBytes:(NSUInteger)maxBytes;

/// A copy of `object` that NSJSONSerialization always accepts: string keys only, dates as ISO strings, NaN and
/// infinity as null, other objects as their description.
+ (id)JSONSafeObject:(nullable id)object;

/// gzip (RFC 1952) of `data`; nil when zlib fails.
+ (nullable NSData *)gzipData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
