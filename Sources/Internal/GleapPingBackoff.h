//
//  GleapPingBackoff.h
//  Gleap
//
//  When the next event ping may go out after failed ones (429, 5xx, other error answers,
//  network errors): 3 s, then 6, 12, 24, 48 and at most 60 s after the failure, each ±20 % so
//  devices do not retry in step. When the server asks for a longer wait with Retry-After
//  (seconds or an HTTP date), that applies, up to 5 minutes. A delivered ping starts over.
//  Used on the main thread only.
//

#import <Foundation/Foundation.h>
#import "GleapInternal.h"

NS_ASSUME_NONNULL_BEGIN

GLEAP_INTERNAL
@interface GleapPingBackoff : NSObject

/// Failed pings in a row.
@property (nonatomic, assign, readonly) NSInteger failures;

/// Before this time (system uptime) no ping goes out; 0 without a backoff.
@property (nonatomic, assign, readonly) NSTimeInterval retryAt;

/// A ping failed at `now` (system uptime). `retryAfter` is the server's Retry-After in seconds,
/// negative without one; `random` lies in [0, 1) and sets the jitter. Returns the delay until the
/// next ping may go out.
- (NSTimeInterval)failureAt:(NSTimeInterval)now retryAfter:(NSTimeInterval)retryAfter random:(double)random;

/// A ping was delivered: the next failure starts over at 3 s.
- (void)reset;

/// How long the next ping still has to wait at `now` (system uptime), 0 when it may go out.
- (NSTimeInterval)remainingAt:(NSTimeInterval)now;

/// The delay after `failures` failed pings in a row: 3 s doubled per failure up to 60 s, times a
/// factor between 0.8 and 1.2 (from `random` in [0, 1)), never more than 60 s.
+ (NSTimeInterval)delayAfterFailures:(NSInteger)failures random:(double)random;

/// Whether a failed ping is worth sending again: 408, 429 or a 5xx. Other error answers mean the
/// server will not take these events.
+ (BOOL)isRetryableStatusCode:(NSInteger)statusCode;

/// A Retry-After value (delay-seconds or an HTTP date) in seconds from `now`: 0 for a date in the
/// past, -1 without a valid value.
+ (NSTimeInterval)retryAfterFromValue:(nullable NSString *)value now:(NSDate *)now;

@end

NS_ASSUME_NONNULL_END
