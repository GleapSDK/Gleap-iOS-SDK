//
//  GleapAPIClient.m
//  Gleap
//

#import "GleapAPIClient.h"
#import "GleapCore.h"
#import "GleapSessionHelper.h"

static NSString * const kGleapMultipartBoundary = @"BBBOUNDARY";
static NSTimeInterval const kGleapDefaultRetryDelay = 2.0;
static NSTimeInterval const kGleapMaxRetryDelay = 5.0;

@implementation GleapAPIClient

#pragma mark - Sessions

// One session per purpose, created on first use and kept for the app's lifetime, so requests
// share connections. The configuration is the same default configuration each request used to
// get from a session of its own; callbacks still arrive on the main queue.
+ (NSURLSession *)apiSession {
    static NSURLSession *session = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        session = [NSURLSession sessionWithConfiguration: [NSURLSessionConfiguration defaultSessionConfiguration]
                                                delegate: nil
                                           delegateQueue: [NSOperationQueue mainQueue]];
    });
    return session;
}

+ (NSURLSession *)uploadSession {
    static NSURLSession *session = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        session = [NSURLSession sessionWithConfiguration: [NSURLSessionConfiguration defaultSessionConfiguration]
                                                delegate: nil
                                           delegateQueue: [NSOperationQueue mainQueue]];
    });
    return session;
}

#pragma mark - Requests

+ (NSMutableURLRequest *)requestWithMethod:(NSString *)method path:(NSString *)path identity:(GleapRequestIdentity)identity {
    NSMutableURLRequest *request = [NSMutableURLRequest new];
    request.HTTPMethod = method;
    [request setURL: [NSURL URLWithString: [NSString stringWithFormat: @"%@%@", Gleap.sharedInstance.apiUrl, path]]];

    switch (identity) {
        case GleapRequestIdentityNone:
            break;
        case GleapRequestIdentityStoredIfComplete: {
            [request setValue: Gleap.sharedInstance.token forHTTPHeaderField: @"Api-Token"];
            NSString *gleapId = [[NSUserDefaults standardUserDefaults] stringForKey: @"gleapId"];
            NSString *gleapHash = [[NSUserDefaults standardUserDefaults] stringForKey: @"gleapHash"];
            if (gleapId != nil && gleapId.length > 0 && gleapHash != nil && gleapHash.length > 0) {
                [request setValue: gleapId forHTTPHeaderField: @"Gleap-Id"];
                [request setValue: gleapHash forHTTPHeaderField: @"Gleap-Hash"];
            }
            break;
        }
        case GleapRequestIdentityStored:
            [request setValue: Gleap.sharedInstance.token forHTTPHeaderField: @"Api-Token"];
            [request setValue: [[NSUserDefaults standardUserDefaults] stringForKey: @"gleapId"] forHTTPHeaderField: @"Gleap-Id"];
            [request setValue: [[NSUserDefaults standardUserDefaults] stringForKey: @"gleapHash"] forHTTPHeaderField: @"Gleap-Hash"];
            break;
        case GleapRequestIdentityCurrentSession:
            [GleapSessionHelper injectSessionInRequest: request];
            break;
    }
    return request;
}

+ (NSMutableURLRequest *)JSONRequestWithMethod:(NSString *)method path:(NSString *)path identity:(GleapRequestIdentity)identity {
    NSMutableURLRequest *request = [self requestWithMethod: method path: path identity: identity];
    [request setValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
    [request setValue: @"application/json" forHTTPHeaderField: @"Accept"];
    return request;
}

+ (NSMutableURLRequest *)uploadRequestWithPath:(NSString *)path files:(NSArray<NSDictionary *> *)files {
    NSMutableURLRequest *request = [self requestWithMethod: @"POST" path: path identity: GleapRequestIdentityCurrentSession];
    [request setCachePolicy: NSURLRequestReloadIgnoringLocalCacheData];
    [request setHTTPShouldHandleCookies: NO];
    [request setTimeoutInterval: 60];
    [request setValue: [NSString stringWithFormat: @"multipart/form-data; boundary=%@", kGleapMultipartBoundary] forHTTPHeaderField: @"Content-Type"];

    NSMutableData *body = [NSMutableData data];
    for (NSDictionary *file in files) {
        NSData *fileData = [file objectForKey: @"data"];
        NSString *fileName = [file objectForKey: @"name"];
        NSString *fileContentType = [file objectForKey: @"type"];
        if (fileData == nil || fileName == nil) {
            continue;
        }
        [body appendData: [[NSString stringWithFormat: @"--%@\r\n", kGleapMultipartBoundary] dataUsingEncoding: NSUTF8StringEncoding]];
        [body appendData: [[NSString stringWithFormat: @"Content-Disposition: form-data; name=%@; filename=%@\r\n", @"file", fileName] dataUsingEncoding: NSUTF8StringEncoding]];
        [body appendData: [[NSString stringWithFormat: @"Content-Type: %@\r\n\r\n", fileContentType] dataUsingEncoding: NSUTF8StringEncoding]];
        [body appendData: fileData];
        [body appendData: [@"\r\n" dataUsingEncoding: NSUTF8StringEncoding]];
    }
    [body appendData: [[NSString stringWithFormat: @"--%@--\r\n", kGleapMultipartBoundary] dataUsingEncoding: NSUTF8StringEncoding]];

    [request setHTTPBody: body];
    [request setValue: [NSString stringWithFormat: @"%lu", (unsigned long)[body length]] forHTTPHeaderField: @"Content-Length"];
    return request;
}

#pragma mark - Sending

+ (void)sendRequest:(NSURLRequest *)request completion:(GleapAPICompletion)completion {
    [[[self apiSession] dataTaskWithRequest: request completionHandler: completion] resume];
}

+ (void)sendReportRequest:(NSURLRequest *)request completion:(GleapAPICompletion)completion {
    [self sendRequest: request onSession: [self apiSession] retryOnOverload: YES completion: completion];
}

+ (void)sendUploadRequest:(NSURLRequest *)request completion:(GleapAPICompletion)completion {
    [self sendRequest: request onSession: [self uploadSession] retryOnOverload: YES completion: completion];
}

// The server answers 503 when it is momentarily overloaded and says when to come back
// (Retry-After). Reports and uploads are worth one more try; the second answer is final.
+ (void)sendRequest:(NSURLRequest *)request onSession:(NSURLSession *)session retryOnOverload:(BOOL)retryOnOverload completion:(GleapAPICompletion)completion {
    [[session dataTaskWithRequest: request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (retryOnOverload && error == nil && [self statusCodeOfResponse: response] == 503) {
            NSTimeInterval delay = [self retryDelayForResponse: (NSHTTPURLResponse *)response];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self sendRequest: request onSession: session retryOnOverload: NO completion: completion];
            });
            return;
        }
        completion(data, response, error);
    }] resume];
}

+ (NSTimeInterval)retryDelayForResponse:(NSHTTPURLResponse *)response {
    NSString *retryAfter = nil;
    for (id key in response.allHeaderFields) {
        if ([key isKindOfClass: [NSString class]] && [(NSString *)key caseInsensitiveCompare: @"Retry-After"] == NSOrderedSame) {
            retryAfter = [[response.allHeaderFields objectForKey: key] description];
        }
    }
    NSScanner *scanner = retryAfter != nil ? [NSScanner scannerWithString: retryAfter] : nil;
    double seconds = 0;
    if (scanner == nil || ![scanner scanDouble: &seconds] || !scanner.isAtEnd || seconds < 0) {
        seconds = kGleapDefaultRetryDelay;
    }
    return MIN(seconds, kGleapMaxRetryDelay);
}

+ (NSInteger)statusCodeOfResponse:(NSURLResponse *)response {
    return [response isKindOfClass: [NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
}

+ (BOOL)isSuccessResponse:(NSURLResponse *)response {
    NSInteger status = [self statusCodeOfResponse: response];
    return status >= 200 && status < 300;
}

@end
