//
//  GleapWebSocketPolicy.h
//  Gleap
//
//  The rules behind the realtime socket (GleapWebSocketHelper), kept free of state so they can be
//  tested: when to open a socket, when to keep the one that is open, and how long to wait before
//  reconnecting after an error (2 s, doubled per failure up to 60 s, each ±20 % so devices do not
//  reconnect in step).
//

#import <Foundation/Foundation.h>
#import "GleapInternal.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GleapWebSocketAction) {
    /// Nothing to connect to (no session yet).
    GleapWebSocketActionNone = 0,
    /// The open (or opening) socket already serves the wanted channel: leave it alone.
    GleapWebSocketActionKeep = 1,
    /// The app is in the background or offline: open nothing now, foreground / network return retries.
    GleapWebSocketActionWait = 2,
    /// Open a socket for the wanted channel (closing any other one).
    GleapWebSocketActionConnect = 3,
};

GLEAP_INTERNAL
@interface GleapWebSocketPolicy : NSObject

/// What to do for the channel `desiredURL` (gleapId, gleapHash and apiKey are in its query) while
/// `currentURL` is the channel of the socket that is open or opening (`socketAlive`), if any.
+ (GleapWebSocketAction)actionForDesiredURL:(nullable NSURL *)desiredURL
                                 currentURL:(nullable NSURL *)currentURL
                                socketAlive:(BOOL)socketAlive
                               inBackground:(BOOL)inBackground
                                     online:(BOOL)online;

/// Whether the same channel is wanted: same URL apart from the order of the query items.
+ (BOOL)isSameChannel:(nullable NSURL *)url as:(nullable NSURL *)otherURL;

/// The delay before reconnecting after `failures` failed connections in a row (1 = the first):
/// 2 s doubled per failure up to 60 s, times a factor between 0.8 and 1.2 (from `random` in
/// [0, 1)), never more than 60 s.
+ (NSTimeInterval)reconnectDelayAfterFailures:(NSInteger)failures random:(double)random;

/// Whether a socket that just failed counts as having worked, so the backoff starts over: it was
/// open for at least 30 s or received a message.
+ (BOOL)shouldResetBackoffAfterOpenFor:(NSTimeInterval)openDuration receivedMessage:(BOOL)receivedMessage;

@end

NS_ASSUME_NONNULL_END
