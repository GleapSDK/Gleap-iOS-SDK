//
//  GleapPingBackoff.m
//  Gleap
//

#import "GleapPingBackoff.h"

static NSTimeInterval const kGleapPingFirstDelay = 3.0;
static NSTimeInterval const kGleapPingMaxDelay = 60.0;
static double const kGleapPingJitter = 0.2;
static NSTimeInterval const kGleapPingMaxRetryAfter = 5 * 60.0;

@implementation GleapPingBackoff

- (NSTimeInterval)failureAt:(NSTimeInterval)now retryAfter:(NSTimeInterval)retryAfter random:(double)random {
    _failures++;
    NSTimeInterval delay = [GleapPingBackoff delayAfterFailures: _failures random: random];
    if (retryAfter > 0) {
        delay = MAX(delay, MIN(retryAfter, kGleapPingMaxRetryAfter));
    }
    _retryAt = now + delay;
    return delay;
}

- (void)reset {
    _failures = 0;
    _retryAt = 0;
}

- (NSTimeInterval)remainingAt:(NSTimeInterval)now {
    return _retryAt > now ? _retryAt - now : 0;
}

+ (NSTimeInterval)delayAfterFailures:(NSInteger)failures random:(double)random {
    NSInteger doublings = MIN(MAX(failures - 1, 0), 5);
    NSTimeInterval base = MIN(kGleapPingFirstDelay * (double)(1L << doublings), kGleapPingMaxDelay);
    double factor = 1 - kGleapPingJitter + 2 * kGleapPingJitter * MIN(MAX(random, 0.0), 1.0);
    return MIN(base * factor, kGleapPingMaxDelay);
}

+ (NSTimeInterval)retryAfterFromValue:(NSString *)value now:(NSDate *)now {
    NSString *trimmed = [value stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    if (trimmed.length == 0) {
        return -1;
    }
    NSCharacterSet *nonDigits = [[NSCharacterSet characterSetWithCharactersInString: @"0123456789"] invertedSet];
    if ([trimmed rangeOfCharacterFromSet: nonDigits].location == NSNotFound) {
        return trimmed.doubleValue;
    }
    // An asctime date pads single-digit days with a second space.
    while ([trimmed containsString: @"  "]) {
        trimmed = [trimmed stringByReplacingOccurrencesOfString: @"  " withString: @" "];
    }
    for (NSDateFormatter *formatter in [self HTTPDateFormatters]) {
        NSDate *date = [formatter dateFromString: trimmed];
        if (date != nil) {
            return MAX(0, [date timeIntervalSinceDate: now]);
        }
    }
    return -1;
}

// IMF-fixdate (the one servers send), then the obsolete RFC 850 and asctime formats.
+ (NSArray<NSDateFormatter *> *)HTTPDateFormatters {
    static NSArray<NSDateFormatter *> *formatters = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray *result = [NSMutableArray array];
        for (NSString *format in @[@"EEE, dd MMM yyyy HH:mm:ss zzz", @"EEEE, dd-MMM-yy HH:mm:ss zzz", @"EEE MMM d HH:mm:ss yyyy"]) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.locale = [NSLocale localeWithLocaleIdentifier: @"en_US_POSIX"];
            formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT: 0];
            formatter.dateFormat = format;
            [result addObject: formatter];
        }
        formatters = [result copy];
    });
    return formatters;
}

+ (BOOL)isRetryableStatusCode:(NSInteger)statusCode {
    return statusCode == 408 || statusCode == 429 || statusCode >= 500;
}

@end
