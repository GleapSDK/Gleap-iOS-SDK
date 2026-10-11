//
//  GleapWebSocketPolicy.m
//  Gleap
//

#import "GleapWebSocketPolicy.h"

static NSTimeInterval const kGleapSocketFirstDelay = 2.0;
static NSTimeInterval const kGleapSocketMaxDelay = 60.0;
static double const kGleapSocketJitter = 0.2;
static NSTimeInterval const kGleapSocketStableAfter = 30.0;

@implementation GleapWebSocketPolicy

+ (GleapWebSocketAction)actionForDesiredURL:(NSURL *)desiredURL
                                 currentURL:(NSURL *)currentURL
                                socketAlive:(BOOL)socketAlive
                               inBackground:(BOOL)inBackground
                                     online:(BOOL)online {
    if (desiredURL == nil) {
        return GleapWebSocketActionNone;
    }
    if (inBackground || !online) {
        return GleapWebSocketActionWait;
    }
    if (socketAlive && [self isSameChannel: desiredURL as: currentURL]) {
        return GleapWebSocketActionKeep;
    }
    return GleapWebSocketActionConnect;
}

+ (BOOL)isSameChannel:(NSURL *)url as:(NSURL *)otherURL {
    if (url == nil || otherURL == nil) {
        return NO;
    }
    if ([url.absoluteString isEqualToString: otherURL.absoluteString]) {
        return YES;
    }
    NSURLComponents *a = [NSURLComponents componentsWithURL: url resolvingAgainstBaseURL: NO];
    NSURLComponents *b = [NSURLComponents componentsWithURL: otherURL resolvingAgainstBaseURL: NO];
    if (a == nil || b == nil) {
        return NO;
    }
    NSComparator byName = ^NSComparisonResult(NSURLQueryItem *x, NSURLQueryItem *y) {
        NSComparisonResult result = [x.name compare: y.name];
        return result != NSOrderedSame ? result : [(x.value ?: @"") compare: (y.value ?: @"")];
    };
    NSArray *queryA = [(a.queryItems ?: @[]) sortedArrayUsingComparator: byName];
    NSArray *queryB = [(b.queryItems ?: @[]) sortedArrayUsingComparator: byName];
    a.queryItems = nil;
    b.queryItems = nil;
    return [a.string isEqualToString: b.string] && [queryA isEqualToArray: queryB];
}

+ (NSTimeInterval)reconnectDelayAfterFailures:(NSInteger)failures random:(double)random {
    NSInteger doublings = MIN(MAX(failures - 1, 0), 6);
    NSTimeInterval base = MIN(kGleapSocketFirstDelay * (double)(1L << doublings), kGleapSocketMaxDelay);
    double factor = 1 - kGleapSocketJitter + 2 * kGleapSocketJitter * MIN(MAX(random, 0.0), 1.0);
    return MIN(base * factor, kGleapSocketMaxDelay);
}

+ (BOOL)shouldResetBackoffAfterOpenFor:(NSTimeInterval)openDuration receivedMessage:(BOOL)receivedMessage {
    return receivedMessage || openDuration >= kGleapSocketStableAfter;
}

@end
