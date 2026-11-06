//
//  GleapUserJwt.h
//  Gleap
//
//  Identity tokens (Gleap.setUserJwt): HS256 JWTs signed by the app's backend. The SDK only
//  reads the payload; the server checks the signature. The token is kept in memory only.
//

#import <Foundation/Foundation.h>
#import "GleapInternal.h"
#import "GleapCore.h"

NS_ASSUME_NONNULL_BEGIN

GLEAP_INTERNAL
@interface GleapUserJwt : NSObject

/// YES for a string shaped like a JWT: three non-empty base64url segments, at most 4096 characters.
+ (BOOL)isUserJwt:(nullable id)token;

/// The payload's `userId` (or `user_id`) as a string, or nil when the token is not a JWT or has
/// no user id (a non-empty string or a finite number). The signature is not checked.
+ (nullable NSString *)userIdOf:(nullable id)token;

/// The payload's `exp` (seconds since 1970), or nil without one.
+ (nullable NSNumber *)expirationOf:(nullable id)token;

/// YES when the token carries an `exp` that lies less than `window` seconds after `now`.
+ (BOOL)token:(nullable id)token expiresWithin:(NSTimeInterval)window of:(NSDate *)now;

/// What the token says, for "was this identify sent already": its `kid` and its claims without
/// iat/exp/nbf/jti, as sorted JSON. A token re-minted for the same user and data gives the same
/// value; a changed claim or key does not. Nil when the token is not a JWT.
+ (nullable NSString *)identityFingerprintOf:(nullable id)token;

/// YES for an identify refused because the project enforces identity verification and the
/// identify had no valid signature: HTTP 401 whose body names `signature_required`.
+ (BOOL)isSignatureRequiredForStatus:(NSInteger)status body:(nullable NSData *)body;

/// `token_expired` or `token_invalid` for an identify refusal (HTTP 401 whose body names the
/// code), nil for anything else.
+ (nullable NSString *)refusalCodeForStatus:(NSInteger)status body:(nullable NSData *)body;

/// YES for an identify refused because the session belongs to another user: HTTP 400 whose body
/// names `identity_mismatch`.
+ (BOOL)isIdentityMismatchForStatus:(NSInteger)status body:(nullable NSData *)body;

@end

/*
 Asks the app's JWT provider for a fresh token: one call at a time (later requests wait for the
 running one), given up after `timeout` (10 s), and after a failure (nil, not a JWT with a user id,
 or the timeout) no new call for `pauseAfterFailure` (30 s). Used on the main queue.
 */
GLEAP_INTERNAL
@interface GleapUserJwtProviderGate : NSObject

@property (nonatomic, copy, nullable) GleapUserJwtProvider provider;
@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, assign) NSTimeInterval pauseAfterFailure;
/// System uptime of the last failure, 0 after a success.
@property (nonatomic, assign, readonly) NSTimeInterval failedAt;
@property (nonatomic, assign, readonly) BOOL inFlight;

/// Runs `completion` on the main queue with a fresh token, or nil (no provider, failure, timeout,
/// or still pausing after a failure).
- (void)requestToken:(void (^)(NSString * _Nullable token))completion;

@end

NS_ASSUME_NONNULL_END
