//
//  GleapAPIClient.m
//  Gleap
//

#import "GleapAPIClient.h"
#import "GleapCore.h"
#import "GleapSessionHelper.h"

static NSString * const kGleapMultipartBoundary = @"BBBOUNDARY";

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

+ (void)sendUploadRequest:(NSURLRequest *)request completion:(GleapAPICompletion)completion {
    [[[self uploadSession] dataTaskWithRequest: request completionHandler: completion] resume];
}

@end
