//
//  GleapCaptureAPI.m
//  Gleap
//

#import "GleapCaptureAPI.h"
#import "GleapAPIClient.h"
#import "GleapCore.h"
#import "GleapMetaDataHelper.h"
#import "GleapLogsBundle.h"
#import <UIKit/UIKit.h>

static NSString * const kGleapCaptureDeviceIdKey = @"gleapCaptureDeviceId";
static NSString * const kGleapCaptureAPIErrorDomain = @"io.gleap.capture.api";
static NSUInteger const kGleapUploadChunkSize = 256 * 1024;
static NSUInteger const kGleapMaxUploadResponseBytes = 1024 * 1024;

#pragma mark - Upload

GLEAP_INTERNAL
@interface GleapCaptureUpload : NSObject <GleapCaptureCancellable, NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy) NSString *contentType;
@property (nonatomic, copy, nullable) void (^progress)(double fraction);
@property (nonatomic, copy, nullable) void (^completion)(NSString * _Nullable fileUrl, NSInteger statusCode, NSError * _Nullable error);
@property (nonatomic, strong, nullable) NSURL *bodyURL;
@property (nonatomic, strong, nullable) NSURLRequest *request;
@property (nonatomic, strong, nullable) NSURLSession *session;
@property (nonatomic, strong, nullable) NSURLSessionTask *task;
@property (nonatomic, strong) NSMutableData *responseData;
@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundTask;
@property (nonatomic, assign) BOOL retried;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL finished;
@end

@implementation GleapCaptureUpload

- (void)start {
    // A few more seconds to finish when the user leaves the app during the upload.
    __weak typeof(self) weakSelf = self;
    self.backgroundTask = [UIApplication.sharedApplication beginBackgroundTaskWithName: @"io.gleap.capture.upload" expirationHandler:^{
        [weakSelf endBackgroundTask];
    }];
    NSURL *fileURL = self.fileURL;
    NSString *fileName = self.fileName;
    NSString *contentType = self.contentType;
    NSString *boundary = [NSString stringWithFormat: @"GleapCaptureBoundary%@", [[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString: @"-" withString: @""]];
    NSURL *bodyURL = [[fileURL URLByDeletingLastPathComponent] URLByAppendingPathComponent: [NSString stringWithFormat: @"upload-%@.multipart", [NSUUID UUID].UUIDString]];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        BOOL written = [GleapCaptureAPI writeMultipartBodyForFileAtURL: fileURL fileName: fileName contentType: contentType boundary: boundary toURL: bodyURL error: &error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.cancelled) {
                [[NSFileManager defaultManager] removeItemAtURL: bodyURL error: nil];
                return;
            }
            if (!written) {
                [self finishWithFileUrl: nil statusCode: 0 error: error];
                return;
            }
            self.bodyURL = bodyURL;
            @try {
                NSMutableURLRequest *request = [GleapAPIClient requestWithMethod: @"POST" path: @"/uploads/attachments" identity: GleapRequestIdentityCurrentSession];
                request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
                request.HTTPShouldHandleCookies = NO;
                request.timeoutInterval = 120;
                [request setValue: [NSString stringWithFormat: @"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField: @"Content-Type"];
                [request setValue: @"application/json" forHTTPHeaderField: @"Accept"];
                self.request = request;
                [self send];
            } @catch (NSException *exception) {
                [self finishWithFileUrl: nil statusCode: 0 error: [NSError errorWithDomain: kGleapCaptureAPIErrorDomain code: 5 userInfo: @{ NSLocalizedDescriptionKey: exception.reason ?: @"The upload could not start." }]];
            }
        });
    });
}

- (void)send {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForRequest = 120;
    configuration.timeoutIntervalForResource = 15 * 60;
    // A session per upload for its progress; it keeps this object (its delegate) until it is invalidated.
    self.session = [NSURLSession sessionWithConfiguration: configuration delegate: self delegateQueue: [NSOperationQueue mainQueue]];
    self.responseData = [NSMutableData data];
    self.task = [self.session uploadTaskWithRequest: self.request fromFile: self.bodyURL];
    [self.task resume];
}

- (void)cancel {
    if (self.finished || self.cancelled) {
        return;
    }
    self.cancelled = YES;
    [self.task cancel];
    [self.session invalidateAndCancel];
    self.session = nil;
    [self cleanUp];
}

- (void)cleanUp {
    if (self.bodyURL != nil) {
        NSURL *bodyURL = self.bodyURL;
        self.bodyURL = nil;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [[NSFileManager defaultManager] removeItemAtURL: bodyURL error: nil];
        });
    }
    [self endBackgroundTask];
}

- (void)endBackgroundTask {
    if (self.backgroundTask != UIBackgroundTaskInvalid) {
        [UIApplication.sharedApplication endBackgroundTask: self.backgroundTask];
        self.backgroundTask = UIBackgroundTaskInvalid;
    }
}

- (void)finishWithFileUrl:(NSString *)fileUrl statusCode:(NSInteger)statusCode error:(NSError *)error {
    if (self.finished || self.cancelled) {
        return;
    }
    self.finished = YES;
    [self cleanUp];
    void (^completion)(NSString *, NSInteger, NSError *) = self.completion;
    self.completion = nil;
    self.progress = nil;
    @try {
        if (completion != nil) {
            completion(fileUrl, statusCode, error);
        }
    } @catch (NSException *exception) {
        NSLog(@"[GLEAP_SDK] Handling the upload result failed: %@", exception.reason);
    }
}

#pragma mark NSURLSession delegate (main queue)

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend {
    @try {
        if (self.progress != nil && totalBytesExpectedToSend > 0 && !self.cancelled) {
            self.progress(MIN(1.0, MAX(0.0, (double)totalBytesSent / (double)totalBytesExpectedToSend)));
        }
    } @catch (NSException *exception) {}
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    @try {
        if (self.responseData.length + data.length <= kGleapMaxUploadResponseBytes) {
            [self.responseData appendData: data];
        }
    } @catch (NSException *exception) {}
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    @try {
        [self session: session task: task didCompleteWithError: error];
    } @catch (NSException *exception) {
        [self finishWithFileUrl: nil statusCode: 0 error: [NSError errorWithDomain: kGleapCaptureAPIErrorDomain code: 6 userInfo: @{ NSLocalizedDescriptionKey: exception.reason ?: @"The upload failed." }]];
    }
}

- (void)session:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    [session finishTasksAndInvalidate];
    if (session == self.session) {
        self.session = nil;
    }
    if (self.cancelled) {
        return;
    }
    NSInteger statusCode = [GleapAPIClient statusCodeOfResponse: task.response];
    // Like the SDK's other uploads: an overloaded server (503) gets one more try.
    if (error == nil && statusCode == 503 && !self.retried) {
        self.retried = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!self.cancelled && !self.finished) {
                @try {
                    [self send];
                } @catch (NSException *exception) {
                    [self finishWithFileUrl: nil statusCode: 0 error: nil];
                }
            }
        });
        return;
    }
    if (error != nil || ![GleapAPIClient isSuccessResponse: task.response]) {
        [self finishWithFileUrl: nil statusCode: statusCode error: error];
        return;
    }
    NSString *fileUrl = nil;
    @try {
        id json = [NSJSONSerialization JSONObjectWithData: self.responseData options: 0 error: nil];
        id fileUrls = [json isKindOfClass: [NSDictionary class]] ? [json objectForKey: @"fileUrls"] : nil;
        id first = [fileUrls isKindOfClass: [NSArray class]] ? [fileUrls firstObject] : nil;
        if ([first isKindOfClass: [NSString class]] && [first length] > 0) {
            fileUrl = first;
        }
    } @catch (NSException *exception) {}
    [self finishWithFileUrl: fileUrl statusCode: statusCode error: fileUrl == nil ? [NSError errorWithDomain: kGleapCaptureAPIErrorDomain code: 2 userInfo: @{ NSLocalizedDescriptionKey: @"The upload answer names no file." }] : nil];
}

@end

#pragma mark - API

@implementation GleapCaptureAPI

+ (BOOL)isValidRequestId:(id)requestId {
    if (![requestId isKindOfClass: [NSString class]]) {
        return NO;
    }
    NSString *value = requestId;
    if (value.length == 0 || value.length > 64) {
        return NO;
    }
    static NSCharacterSet *invalidCharacters = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        invalidCharacters = [[NSCharacterSet characterSetWithCharactersInString: @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"] invertedSet];
    });
    return [value rangeOfCharacterFromSet: invalidCharacters].location == NSNotFound;
}

+ (NSString *)sdkType {
    switch ([Gleap sharedInstance].applicationType) {
        case REACTNATIVE:
            return @"REACTNATIVE";
        case FLUTTER:
            return @"FLUTTER";
        case CORDOVA:
            return @"CORDOVA";
        case CAPACITOR:
            return @"CAPACITOR";
        default:
            return @"NATIVE";
    }
}

+ (NSString *)deviceId {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *deviceId = [defaults stringForKey: kGleapCaptureDeviceIdKey];
    if (deviceId.length == 0) {
        deviceId = [[NSUUID UUID].UUIDString lowercaseString];
        [defaults setObject: deviceId forKey: kGleapCaptureDeviceIdKey];
    }
    return deviceId;
}

+ (NSString *)pathForRequest:(NSString *)requestId action:(NSString *)action {
    return [NSString stringWithFormat: @"/v3/shared/capture-requests/%@/%@", requestId, action];
}

+ (void)postJSON:(NSDictionary *)body path:(NSString *)path completion:(GleapCaptureAPICompletion)completion {
    NSData *jsonData = nil;
    @try {
        jsonData = [NSJSONSerialization dataWithJSONObject: [GleapLogsBundle JSONSafeObject: body] options: 0 error: nil];
    } @catch (NSException *exception) {}
    if (jsonData == nil) {
        if (completion) {
            completion(0, nil, [NSError errorWithDomain: kGleapCaptureAPIErrorDomain code: 1 userInfo: @{ NSLocalizedDescriptionKey: @"The request could not be encoded." }]);
        }
        return;
    }
    NSMutableURLRequest *request = [GleapAPIClient JSONRequestWithMethod: @"POST" path: path identity: GleapRequestIdentityCurrentSession];
    request.HTTPBody = jsonData;
    request.timeoutInterval = 30;
    [self sendRequest: request completion: completion];
}

+ (void)sendRequest:(NSURLRequest *)request completion:(GleapCaptureAPICompletion)completion {
    [GleapAPIClient sendReportRequest: request completion:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSInteger statusCode = [GleapAPIClient statusCodeOfResponse: response];
        NSDictionary *json = nil;
        if (data.length > 0) {
            @try {
                id parsed = [NSJSONSerialization JSONObjectWithData: data options: 0 error: nil];
                if ([parsed isKindOfClass: [NSDictionary class]]) {
                    json = parsed;
                }
            } @catch (NSException *exception) {}
        }
        @try {
            if (completion) {
                completion(statusCode, json, error);
            }
        } @catch (NSException *exception) {
            NSLog(@"[GLEAP_SDK] Handling a capture request answer failed: %@", exception.reason);
        }
    }];
}

+ (void)claimRequest:(NSString *)requestId completion:(GleapCaptureAPICompletion)completion {
    [self postJSON: @{
        @"deviceId": [self deviceId],
        @"platform": @"ios",
        @"sdkType": [self sdkType],
        @"sdkVersion": SDK_VERSION,
    } path: [self pathForRequest: requestId action: @"claim"] completion: completion];
}

+ (void)postEventType:(NSString *)type reason:(NSString *)reason requestId:(NSString *)requestId completion:(GleapCaptureAPICompletion)completion {
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithObject: type forKey: @"type"];
    if (reason.length > 0) {
        body[@"reason"] = reason;
    }
    [self postJSON: body path: [self pathForRequest: requestId action: @"event"] completion: completion];
}

+ (void)completeRequest:(NSString *)requestId body:(NSDictionary *)body completion:(GleapCaptureAPICompletion)completion {
    [self postJSON: body path: [self pathForRequest: requestId action: @"complete"] completion: completion];
}

+ (void)postLogs:(NSData *)gzippedJSON requestId:(NSString *)requestId completion:(GleapCaptureAPICompletion)completion {
    NSMutableURLRequest *request = [GleapAPIClient JSONRequestWithMethod: @"POST" path: [self pathForRequest: requestId action: @"logs"] identity: GleapRequestIdentityCurrentSession];
    [request setValue: @"gzip" forHTTPHeaderField: @"Content-Encoding"];
    request.HTTPBody = gzippedJSON;
    request.timeoutInterval = 60;
    [self sendRequest: request completion: completion];
}

+ (id<GleapCaptureCancellable>)uploadFileAtURL:(NSURL *)fileURL
                                      fileName:(NSString *)fileName
                                   contentType:(NSString *)contentType
                                      progress:(void (^)(double))progress
                                    completion:(void (^)(NSString * _Nullable, NSInteger, NSError * _Nullable))completion {
    GleapCaptureUpload *upload = [[GleapCaptureUpload alloc] init];
    upload.fileURL = fileURL;
    upload.fileName = fileName;
    upload.contentType = contentType;
    upload.progress = progress;
    upload.completion = completion;
    upload.backgroundTask = UIBackgroundTaskInvalid;
    [upload start];
    return upload;
}

+ (BOOL)writeMultipartBodyForFileAtURL:(NSURL *)fileURL
                              fileName:(NSString *)fileName
                           contentType:(NSString *)contentType
                              boundary:(NSString *)boundary
                                 toURL:(NSURL *)bodyURL
                                 error:(NSError **)error {
    NSCharacterSet *unsafe = [NSCharacterSet characterSetWithCharactersInString: @"\"\r\n\\"];
    NSString *safeName = [[fileName componentsSeparatedByCharactersInSet: unsafe] componentsJoinedByString: @"_"];
    NSString *safeType = [[contentType componentsSeparatedByCharactersInSet: [NSCharacterSet newlineCharacterSet]] componentsJoinedByString: @""];

    [[NSFileManager defaultManager] removeItemAtURL: bodyURL error: nil];
    NSOutputStream *output = [NSOutputStream outputStreamWithURL: bodyURL append: NO];
    NSInputStream *input = [NSInputStream inputStreamWithURL: fileURL];
    if (output == nil || input == nil) {
        if (error) { *error = [NSError errorWithDomain: kGleapCaptureAPIErrorDomain code: 3 userInfo: @{ NSLocalizedDescriptionKey: @"The upload file could not be opened." }]; }
        return NO;
    }
    [output open];
    [input open];

    BOOL (^writeAll)(const uint8_t *, NSUInteger) = ^BOOL(const uint8_t *bytes, NSUInteger length) {
        NSUInteger offset = 0;
        while (offset < length) {
            NSInteger written = [output write: bytes + offset maxLength: length - offset];
            if (written <= 0) {
                return NO;
            }
            offset += (NSUInteger)written;
        }
        return YES;
    };

    NSData *head = [[NSString stringWithFormat: @"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\nContent-Type: %@\r\n\r\n", boundary, safeName, safeType] dataUsingEncoding: NSUTF8StringEncoding];
    BOOL ok = writeAll(head.bytes, head.length);
    uint8_t *buffer = malloc(kGleapUploadChunkSize);
    if (buffer == NULL) {
        ok = NO;
    }
    while (ok) {
        NSInteger read = [input read: buffer maxLength: kGleapUploadChunkSize];
        if (read < 0) {
            ok = NO;
            break;
        }
        if (read == 0) {
            break;
        }
        ok = writeAll(buffer, (NSUInteger)read);
    }
    if (buffer != NULL) {
        free(buffer);
    }
    NSData *tail = [[NSString stringWithFormat: @"\r\n--%@--\r\n", boundary] dataUsingEncoding: NSUTF8StringEncoding];
    if (ok) {
        ok = writeAll(tail.bytes, tail.length);
    }
    NSError *streamError = output.streamError ?: input.streamError;
    [input close];
    [output close];
    if (!ok) {
        [[NSFileManager defaultManager] removeItemAtURL: bodyURL error: nil];
        if (error) {
            *error = streamError ?: [NSError errorWithDomain: kGleapCaptureAPIErrorDomain code: 4 userInfo: @{ NSLocalizedDescriptionKey: @"The upload body could not be written." }];
        }
    }
    return ok;
}

@end
