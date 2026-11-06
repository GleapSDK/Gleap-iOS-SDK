//
//  GleapGrant.h
//  Gleap
//
//  The grant: the session credential the server returns for a signed identify (`identity.grant`,
//  an HS256 JWT signed by Gleap). It is sent as `Gleap-Grant` on every request for the session it
//  was issued to and handed to the Messenger web view. Kept in memory and in NSUserDefaults next to
//  gleapId / gleapHash, with its `exp`, so an app restart stays signed until it expires.
//

#import <Foundation/Foundation.h>
#import "GleapInternal.h"

NS_ASSUME_NONNULL_BEGIN

GLEAP_INTERNAL
@interface GleapGrant : NSObject

+ (instancetype)sharedInstance;

/// The grant issued to `gleapId`, or nil. An expired grant is still returned: the server may
/// extend it once, otherwise it treats the request as unsigned.
- (nullable NSString *)grantForGleapId:(nullable NSString *)gleapId;

/// The grant's `exp`, or nil without a grant.
- (nullable NSDate *)expiresAt;

/// YES when `gleapId` has a grant that expires within `window` seconds. Without a grant (Classic
/// projects, unsigned identifies) there is nothing to renew.
- (BOOL)needsRenewalForGleapId:(nullable NSString *)gleapId within:(NSTimeInterval)window;

/// Takes the grant from a session answer: `identity.grant` (a string) is stored for the answer's
/// gleapId, `identity` without a grant drops it; an answer without `identity` keeps it. YES when
/// the stored grant changed.
- (BOOL)applySessionAnswer:(NSDictionary *)data;

/// Stores `grant` for `gleapId` (nil drops it). YES when the stored grant changed.
- (BOOL)setGrant:(nullable NSString *)grant forGleapId:(nullable NSString *)gleapId;

/// Drops the grant from memory and NSUserDefaults.
- (void)clear;

/// Adds `Gleap-Grant` when the request's `Gleap-Id` header names the session the grant belongs to.
- (void)applyToRequest:(NSMutableURLRequest *)request;

@end

NS_ASSUME_NONNULL_END
