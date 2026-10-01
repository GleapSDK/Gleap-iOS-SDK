//
//  GleapCaptureAPI.h
//  Gleap
//
//  The capture request endpoints (/v3/shared/capture-requests/{id}/…) and the streamed upload of a
//  recording to /uploads/attachments. Every request carries the session's Api-Token, Gleap-Id and
//  Gleap-Hash; completions run on the main queue.
//

#import <Foundation/Foundation.h>
#import "GleapInternal.h"

NS_ASSUME_NONNULL_BEGIN

/// A running upload.
@protocol GleapCaptureCancellable <NSObject>
- (void)cancel;
@end

typedef void (^GleapCaptureAPICompletion)(NSInteger statusCode, NSDictionary * _Nullable body, NSError * _Nullable error);

GLEAP_INTERNAL
@interface GleapCaptureAPI : NSObject

/// YES for ids that may go into a request path (letters, digits, - and _, at most 64).
+ (BOOL)isValidRequestId:(nullable id)requestId;

/// `NATIVE`, `REACTNATIVE`, `FLUTTER`, `CORDOVA` or `CAPACITOR`.
+ (NSString *)sdkType;

/// A random id of this app installation (not the vendor id), for the server's "claimed on another device".
+ (NSString *)deviceId;

/// POST …/claim with this device.
+ (void)claimRequest:(NSString *)requestId completion:(GleapCaptureAPICompletion)completion;

/// POST …/event (`released`, `failed`, `unsupported`, `declined`).
+ (void)postEventType:(NSString *)type reason:(nullable NSString *)reason requestId:(NSString *)requestId completion:(nullable GleapCaptureAPICompletion)completion;

/// POST …/complete.
+ (void)completeRequest:(NSString *)requestId body:(NSDictionary *)body completion:(GleapCaptureAPICompletion)completion;

/// POST …/logs with a gzipped JSON body (Content-Encoding: gzip).
+ (void)postLogs:(NSData *)gzippedJSON requestId:(NSString *)requestId completion:(GleapCaptureAPICompletion)completion;

/// Uploads a file to /uploads/attachments (multipart field `file`) streamed from disk: the multipart body is
/// written to a temporary file next to it, never held in memory. `progress` gets 0…1. The completion gets the
/// first of the answer's `fileUrls`, or nil with the status / error.
+ (id<GleapCaptureCancellable>)uploadFileAtURL:(NSURL *)fileURL
                                      fileName:(NSString *)fileName
                                   contentType:(NSString *)contentType
                                      progress:(nullable void (^)(double fraction))progress
                                    completion:(void (^)(NSString * _Nullable fileUrl, NSInteger statusCode, NSError * _Nullable error))completion;

/// Writes the multipart body (`--boundary`, the file part named `file`, the closing boundary) for `fileURL` to
/// `bodyURL`, copying the file in chunks. Returns NO on I/O errors.
+ (BOOL)writeMultipartBodyForFileAtURL:(NSURL *)fileURL
                              fileName:(NSString *)fileName
                           contentType:(NSString *)contentType
                              boundary:(NSString *)boundary
                                 toURL:(NSURL *)bodyURL
                                 error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
