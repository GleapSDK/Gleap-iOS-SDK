//
//  GleapAPIClient.h
//  Gleap
//
//  Builds and sends the SDK's requests to the Gleap API. Each endpoint keeps the identity
//  headers it has always sent, so the modes below describe today's behaviour per endpoint
//  rather than a policy.
//

#import <Foundation/Foundation.h>
#import "GleapInternal.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GleapRequestIdentity) {
    // No headers at all (the remote config).
    GleapRequestIdentityNone,
    // Api-Token, plus the stored Gleap-Id / Gleap-Hash when both are set (session start).
    GleapRequestIdentityStoredIfComplete,
    // Api-Token and the stored Gleap-Id / Gleap-Hash (identify, partial update).
    GleapRequestIdentityStored,
    // Api-Token and the current session's Gleap-Id / Gleap-Hash (event stream, reports, uploads).
    GleapRequestIdentityCurrentSession,
};

typedef void (^GleapAPICompletion)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error);

GLEAP_INTERNAL
@interface GleapAPIClient : NSObject

/// A request to `path` (appended to the configured API URL) with the identity headers of `identity`.
+ (NSMutableURLRequest *)requestWithMethod:(NSString *)method path:(NSString *)path identity:(GleapRequestIdentity)identity;

/// Like requestWithMethod:path:identity:, with JSON Content-Type and Accept headers.
+ (NSMutableURLRequest *)JSONRequestWithMethod:(NSString *)method path:(NSString *)path identity:(GleapRequestIdentity)identity;

/// A multipart upload of `files` (dictionaries with `data`, `name` and `type`) with the current
/// session's identity. Files without data or name are skipped.
+ (NSMutableURLRequest *)uploadRequestWithPath:(NSString *)path files:(NSArray<NSDictionary *> *)files;

/// Sends a request on the shared API session. The completion runs on the main queue.
+ (void)sendRequest:(NSURLRequest *)request completion:(GleapAPICompletion)completion;

/// Sends an event ping on its own session. An answer that stalls for 15 seconds (connecting
/// included) or takes 30 seconds in total ends with a timeout error. The completion runs on the
/// main queue.
+ (void)sendPingRequest:(NSURLRequest *)request completion:(GleapAPICompletion)completion;

/// Sends a report on the shared API session. A 503 (server overloaded) is retried once after
/// its Retry-After delay, capped at 5 seconds. The completion runs on the main queue.
+ (void)sendReportRequest:(NSURLRequest *)request completion:(GleapAPICompletion)completion;

/// Sends an upload on the shared upload session, retrying a 503 once like reports. The
/// completion runs on the main queue.
+ (void)sendUploadRequest:(NSURLRequest *)request completion:(GleapAPICompletion)completion;

/// YES for an HTTP response with a 2xx status.
+ (BOOL)isSuccessResponse:(nullable NSURLResponse *)response;

/// The HTTP status code, or 0 without an HTTP response.
+ (NSInteger)statusCodeOfResponse:(nullable NSURLResponse *)response;

@end

NS_ASSUME_NONNULL_END
