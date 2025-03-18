//
//  GleapHttpTrafficRecorder.m
//  Gleap
//
//  Created by Lukas Boehler on 28.03.21.
//  Extended for comprehensive logging by swizzling additional NSURLSession methods.
//  Now also ensures that each task is only logged once.
//

#import <objc/runtime.h>
#import <objc/message.h>
#import "GleapHttpTrafficRecorder.h"
#import "GleapCore.h"
#import "GleapUIHelper.h"
#import "GleapWidgetManager.h"

// Keys used for logging dictionary.
NSString * const GleapHTTPTrafficRecordingProgressRequestKey    = @"REQUEST_KEY";
NSString * const GleapHTTPTrafficRecordingProgressResponseKey   = @"RESPONSE_KEY";
NSString * const GleapHTTPTrafficRecordingProgressBodyDataKey   = @"BODY_DATA_KEY";
NSString * const GleapHTTPTrafficRecordingProgressStartDateKey  = @"REQUEST_START_DATE_KEY";
NSString * const GleapHTTPTrafficRecordingProgressErrorKey      = @"ERROR_KEY";

// A static key for marking tasks as already logged.
static char GleapLoggingRecordedKey;
// A static key for accumulating response data in delegate-based sessions.
static char GleapAccumulatedDataKey;

#pragma mark - Private Category on NSURLSession

@interface NSURLSession (GleapSwizzling)
- (NSURLSessionDataTask *)gleap_dataTaskWithRequest:(NSURLRequest *)request
                                  completionHandler:(void (^)(NSData *data,
                                                               NSURLResponse *response,
                                                               NSError *error))completionHandler;
- (NSURLSessionDataTask *)gleap_dataTaskWithURL:(NSURL *)url
                              completionHandler:(void (^)(NSData *data,
                                                           NSURLResponse *response,
                                                           NSError *error))completionHandler;
- (NSURLSessionUploadTask *)gleap_uploadTaskWithRequest:(NSURLRequest *)request
                                               fromData:(NSData *)bodyData
                                      completionHandler:(void (^)(NSData *data,
                                                                   NSURLResponse *response,
                                                                   NSError *error))completionHandler;
- (NSURLSessionDownloadTask *)gleap_downloadTaskWithURL:(NSURL *)url
                                      completionHandler:(void (^)(NSURL *location,
                                                                  NSURLResponse *response,
                                                                  NSError *error))completionHandler;
- (NSURLSessionDownloadTask *)gleap_downloadTaskWithRequest:(NSURLRequest *)request
                                        completionHandler:(void (^)(NSURL *location,
                                                                    NSURLResponse *response,
                                                                    NSError *error))completionHandler;
@end

#pragma mark - GleapHttpTrafficRecorder Interface

@interface GleapHttpTrafficRecorder ()
@property (nonatomic, assign, readwrite) BOOL isRecording;
@property (nonatomic, strong) NSMutableArray *requests;
@property (nonatomic, assign) int maxRequestsInQueue;
@end

@implementation GleapHttpTrafficRecorder

+ (instancetype)sharedRecorder {
    static GleapHttpTrafficRecorder *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = self.new;
        shared.isRecording = NO;
        shared.maxRequestsInQueue = 10;
        shared.requests = [[NSMutableArray alloc] init];
        shared.networkLogPropsToIgnore = [[NSArray alloc] init];
        shared.blacklist = [[NSArray alloc] init];
    });
    return shared;
}

#pragma mark - Extended Start Recording

- (BOOL)startRecordingForSessionConfiguration:(NSURLSessionConfiguration *)sessionConfig {
    BOOL result = [self startRecording];
    [GleapHttpTrafficRecorder swizzleSessionCreationForConfiguration:sessionConfig];
    return result;
}

- (BOOL)startRecording {
    if (self.isRecording) {
        return YES;
    }
    self.isRecording = YES;
    [GleapHttpTrafficRecorder swizzleURLSessionIfNeeded];
    return YES;
}

- (void)stopRecording {
    self.isRecording = NO;
}

- (void)setMaxRequests:(int)maxRequests {
    self.maxRequestsInQueue = maxRequests;
}

- (void)clearLogs {
    [self.requests removeAllObjects];
}

- (NSArray *)networkLogs {
    return [self.requests copy];
}

- (NSArray *)filterNetworkLogs:(NSArray *)networkLogs {
    NSMutableArray *processedNetworkLogs = [[NSMutableArray alloc] init];
    
    for (NSDictionary *originalLog in networkLogs) {
        NSMutableDictionary *log = [NSMutableDictionary dictionaryWithDictionary:originalLog];
        @try {
            NSArray *localNetworkLogPropsToIgnore = [self.networkLogPropsToIgnore arrayByAddingObjectsFromArray:[Gleap sharedInstance].networkLogPropsToIgnore];
            
            if (localNetworkLogPropsToIgnore.count >= 0) {
                if (log[@"request"]) {
                    NSMutableDictionary *request = [NSMutableDictionary dictionaryWithDictionary:log[@"request"]];
                    if (request[@"headers"] && [request[@"headers"] isKindOfClass:[NSDictionary class]]) {
                        NSMutableDictionary *mutableHeaders = [NSMutableDictionary dictionaryWithDictionary:request[@"headers"]];
                        [mutableHeaders removeObjectsForKeys:localNetworkLogPropsToIgnore];
                        request[@"headers"] = mutableHeaders;
                    }
                    if (request[@"payload"]) {
                        NSError *jsonError;
                        NSMutableDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:[request[@"payload"] dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:&jsonError];
                        if (!jsonError && jsonObject) {
                            if ([jsonObject isKindOfClass:[NSDictionary class]]) {
                                [jsonObject removeObjectsForKeys:localNetworkLogPropsToIgnore];
                            }
                            NSError *jsonDataError;
                            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonObject options:0 error:&jsonDataError];
                            if (jsonData) {
                                NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                                if (jsonString) {
                                    request[@"payload"] = jsonString;
                                }
                            }
                        }
                    }
                    log[@"request"] = request;
                }
                
                if (log[@"response"]) {
                    NSMutableDictionary *response = [NSMutableDictionary dictionaryWithDictionary:log[@"response"]];
                    if (response[@"responseText"]) {
                        NSError *jsonError;
                        id jsonObject = [NSJSONSerialization JSONObjectWithData:[response[@"responseText"] dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:&jsonError];
                        if (!jsonError && jsonObject) {
                            if ([jsonObject isKindOfClass:[NSDictionary class]]) {
                                [jsonObject removeObjectsForKeys:localNetworkLogPropsToIgnore];
                            }
                            NSError *jsonDataError;
                            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonObject options:0 error:&jsonDataError];
                            if (jsonData) {
                                NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                                if (jsonString) {
                                    response[@"responseText"] = jsonString;
                                }
                            }
                        }
                    }
                    log[@"response"] = response;
                }
            }
        } @catch (NSException *exception) {
            // Exception caught; logging can be added here if needed.
        }
        
        // Blacklist filtering.
        NSArray *blacklistItems = [self.blacklist arrayByAddingObjectsFromArray:[Gleap sharedInstance].blacklist];
        NSString *logUrl = log[@"url"];
        BOOL shouldAddLog = YES;
        if (logUrl) {
            for (NSString *currentBlacklistItem in blacklistItems) {
                if (currentBlacklistItem && [logUrl containsString:currentBlacklistItem]) {
                    shouldAddLog = NO;
                    break;
                }
            }
        }
        if (shouldAddLog) {
            [processedNetworkLogs addObject:log];
        }
    }
    
    return [processedNetworkLogs copy];
}

+ (NSString *)stringFrom:(NSData *)data {
    if (!data) {
        return @"";
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

+ (BOOL)isTextBasedContentType:(NSString *)contentType {
    if ([contentType containsString:@"text/"]) return YES;
    if ([contentType containsString:@"application/javascript"]) return YES;
    if ([contentType containsString:@"application/xhtml+xml"]) return YES;
    if ([contentType containsString:@"application/json"]) return YES;
    if ([contentType containsString:@"application/xml"]) return YES;
    if ([contentType containsString:@"application/x-www-form-urlencoded"]) return YES;
    if ([contentType containsString:@"multipart/"]) return YES;
    return NO;
}

#pragma mark - Internal Logging

+ (void)recordRequest:(NSURLRequest *)request
             response:(NSURLResponse *)response
                 data:(NSData *)data
                error:(NSError *)error
            startTime:(NSDate *)startTime {
    if (!request) {
        return;
    }
    
    @try {
        NSMutableURLRequest *mutableRequest = [request isKindOfClass:[NSMutableURLRequest class]]
            ? (NSMutableURLRequest *)request
            : [request mutableCopy];

        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        info[GleapHTTPTrafficRecordingProgressRequestKey] = mutableRequest;
        info[GleapHTTPTrafficRecordingProgressStartDateKey] = (startTime ?: [NSDate date]);
        
        if (error) {
            info[GleapHTTPTrafficRecordingProgressErrorKey] = error;
            [self updateRecorderProgressDelegate:NO userInfo:info];
        } else {
            if (response) {
                info[GleapHTTPTrafficRecordingProgressResponseKey] = response;
            }
            info[GleapHTTPTrafficRecordingProgressBodyDataKey] = (data ?: [NSData data]);
            [self updateRecorderProgressDelegate:YES userInfo:info];
        }
    } @catch (NSException *exception) {
        // Exception caught during recordRequest; fail gracefully.
    }
}

+ (void)updateRecorderProgressDelegate:(BOOL)success userInfo:(NSDictionary *)info {
    NSMutableURLRequest *urlRequest = info[GleapHTTPTrafficRecordingProgressRequestKey];
    if (![urlRequest isKindOfClass:[NSMutableURLRequest class]]) {
        return;
    }
    
    @try {
        NSMutableDictionary *requestLog = [NSMutableDictionary dictionary];
        requestLog[@"type"] = urlRequest.HTTPMethod;
        requestLog[@"url"] = urlRequest.URL.absoluteString;
        requestLog[@"date"] = [GleapUIHelper getJSStringForNSDate:[NSDate date]];
        
        NSDate *startLoadingDate = info[GleapHTTPTrafficRecordingProgressStartDateKey];
        if (startLoadingDate) {
            int duration = (int)([startLoadingDate timeIntervalSinceNow] * -1000);
            requestLog[@"duration"] = @(duration);
        }
        
        if (success) {
            NSHTTPURLResponse *response = info[GleapHTTPTrafficRecordingProgressResponseKey];
            NSData *data = info[GleapHTTPTrafficRecordingProgressBodyDataKey];
            NSString *contentType = @"";
            
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                contentType = [((NSHTTPURLResponse *)response) allHeaderFields][@"Content-Type"] ?: @"";
            }
            
            requestLog[@"success"] = @(YES);
            
            NSMutableDictionary *reqObj = [NSMutableDictionary dictionary];
            reqObj[@"payload"] = urlRequest.HTTPBody ? [GleapHttpTrafficRecorder stringFrom:urlRequest.HTTPBody] : @"";
            reqObj[@"headers"] = urlRequest.allHTTPHeaderFields ?: @{};
            requestLog[@"request"] = reqObj;
            
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
                NSMutableDictionary *respObj = [NSMutableDictionary dictionary];
                respObj[@"status"] = @(httpResp.statusCode);
                respObj[@"headers"] = httpResp.allHeaderFields ?: @{};
                respObj[@"contentType"] = contentType;
                
                int maxBodySize = 1024 * 500;
                if ([GleapHttpTrafficRecorder isTextBasedContentType:contentType] && data.length < maxBodySize) {
                    respObj[@"responseText"] = [GleapHttpTrafficRecorder stringFrom:data];
                } else {
                    respObj[@"responseText"] = @"<response_too_large>";
                }
                
                requestLog[@"response"] = respObj;
            }
            
        } else {
            requestLog[@"success"] = @(NO);
            NSError *error = info[GleapHTTPTrafficRecordingProgressErrorKey];
            NSMutableDictionary *respObj = [NSMutableDictionary dictionary];
            respObj[@"errorText"] = error.localizedDescription ?: @"";
            requestLog[@"response"] = respObj;
        }
        
        if ([[GleapWidgetManager sharedInstance] isOpened]) {
            return;
        }
        
        GleapHttpTrafficRecorder *recorder = [GleapHttpTrafficRecorder sharedRecorder];
        @synchronized (recorder.requests) {
            if (recorder.requests.count >= recorder.maxRequestsInQueue) {
                [recorder.requests removeObjectAtIndex:0];
            }
            [recorder.requests addObject:[requestLog copy]];
        }
    } @catch (NSException *exception) {
        // Exception caught during updating recorder progress.
    }
}

#pragma mark - Swizzling

+ (void)swizzleURLSessionIfNeeded {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class sessionClass = [NSURLSession class];
        
        // dataTaskWithRequest:completionHandler:
        SEL originalDataTaskRequestSEL = @selector(dataTaskWithRequest:completionHandler:);
        Method originalDataTaskRequestMethod = class_getInstanceMethod(sessionClass, originalDataTaskRequestSEL);
        SEL swizzledDataTaskRequestSEL = @selector(gleap_dataTaskWithRequest:completionHandler:);
        Method swizzledDataTaskRequestMethod = class_getInstanceMethod(sessionClass, swizzledDataTaskRequestSEL);
        if (!swizzledDataTaskRequestMethod) {
            IMP swizzledDataTaskRequestImpl = (IMP)gleap_dataTaskWithRequest;
            const char *typeEncoding = method_getTypeEncoding(originalDataTaskRequestMethod);
            class_addMethod(sessionClass, swizzledDataTaskRequestSEL, swizzledDataTaskRequestImpl, typeEncoding);
            swizzledDataTaskRequestMethod = class_getInstanceMethod(sessionClass, swizzledDataTaskRequestSEL);
        }
        method_exchangeImplementations(originalDataTaskRequestMethod, swizzledDataTaskRequestMethod);
        
        // dataTaskWithURL:completionHandler:
        SEL originalDataTaskURLSEL = @selector(dataTaskWithURL:completionHandler:);
        Method originalDataTaskURLMethod = class_getInstanceMethod(sessionClass, originalDataTaskURLSEL);
        SEL swizzledDataTaskURLSEL = @selector(gleap_dataTaskWithURL:completionHandler:);
        Method swizzledDataTaskURLMethod = class_getInstanceMethod(sessionClass, swizzledDataTaskURLSEL);
        if (!swizzledDataTaskURLMethod) {
            IMP swizzledDataTaskURLImpl = (IMP)gleap_dataTaskWithURL;
            const char *urlTypeEncoding = method_getTypeEncoding(originalDataTaskURLMethod);
            class_addMethod(sessionClass, swizzledDataTaskURLSEL, swizzledDataTaskURLImpl, urlTypeEncoding);
            swizzledDataTaskURLMethod = class_getInstanceMethod(sessionClass, swizzledDataTaskURLSEL);
        }
        method_exchangeImplementations(originalDataTaskURLMethod, swizzledDataTaskURLMethod);
        
        // uploadTaskWithRequest:fromData:completionHandler:
        SEL originalUploadDataSEL = @selector(uploadTaskWithRequest:fromData:completionHandler:);
        Method originalUploadDataMethod = class_getInstanceMethod(sessionClass, originalUploadDataSEL);
        SEL swizzledUploadDataSEL = @selector(gleap_uploadTaskWithRequest:fromData:completionHandler:);
        Method swizzledUploadDataMethod = class_getInstanceMethod(sessionClass, swizzledUploadDataSEL);
        if (!swizzledUploadDataMethod) {
            IMP swizzledUploadDataImpl = (IMP)gleap_uploadTaskWithRequestFromData;
            const char *uploadDataTypeEncoding = method_getTypeEncoding(originalUploadDataMethod);
            class_addMethod(sessionClass, swizzledUploadDataSEL, swizzledUploadDataImpl, uploadDataTypeEncoding);
            swizzledUploadDataMethod = class_getInstanceMethod(sessionClass, swizzledUploadDataSEL);
        }
        method_exchangeImplementations(originalUploadDataMethod, swizzledUploadDataMethod);
        
        // downloadTaskWithURL:completionHandler:
        SEL originalDownloadURLSEL = @selector(downloadTaskWithURL:completionHandler:);
        Method originalDownloadURLMethod = class_getInstanceMethod(sessionClass, originalDownloadURLSEL);
        SEL swizzledDownloadURLSEL = @selector(gleap_downloadTaskWithURL:completionHandler:);
        Method swizzledDownloadURLMethod = class_getInstanceMethod(sessionClass, swizzledDownloadURLSEL);
        if (!swizzledDownloadURLMethod) {
            IMP swizzledDownloadURLImpl = (IMP)gleap_downloadTaskWithURL;
            const char *downloadURLTypeEncoding = method_getTypeEncoding(originalDownloadURLMethod);
            class_addMethod(sessionClass, swizzledDownloadURLSEL, swizzledDownloadURLImpl, downloadURLTypeEncoding);
            swizzledDownloadURLMethod = class_getInstanceMethod(sessionClass, swizzledDownloadURLSEL);
        }
        method_exchangeImplementations(originalDownloadURLMethod, swizzledDownloadURLMethod);
        
        // downloadTaskWithRequest:completionHandler:
        SEL originalDownloadRequestSEL = @selector(downloadTaskWithRequest:completionHandler:);
        Method originalDownloadRequestMethod = class_getInstanceMethod(sessionClass, originalDownloadRequestSEL);
        SEL swizzledDownloadRequestSEL = @selector(gleap_downloadTaskWithRequest:completionHandler:);
        Method swizzledDownloadRequestMethod = class_getInstanceMethod(sessionClass, swizzledDownloadRequestSEL);
        if (!swizzledDownloadRequestMethod) {
            IMP swizzledDownloadRequestImpl = (IMP)gleap_downloadTaskWithRequest;
            const char *downloadRequestTypeEncoding = method_getTypeEncoding(originalDownloadRequestMethod);
            class_addMethod(sessionClass, swizzledDownloadRequestSEL, swizzledDownloadRequestImpl, downloadRequestTypeEncoding);
            swizzledDownloadRequestMethod = class_getInstanceMethod(sessionClass, swizzledDownloadRequestSEL);
        }
        method_exchangeImplementations(originalDownloadRequestMethod, swizzledDownloadRequestMethod);
    });
}

#pragma mark - Swizzled Method Implementations

// dataTaskWithRequest:completionHandler:
NSURLSessionDataTask * gleap_dataTaskWithRequest(id self,
                                                 SEL _cmd,
                                                 NSURLRequest *request,
                                                 void (^completionHandler)(NSData *, NSURLResponse *, NSError *)) {
    NSURLSession *session = (NSURLSession *)self;
    if (!request) {
        return [session gleap_dataTaskWithRequest:request completionHandler:completionHandler];
    }
    
    __block NSDate *startTime = [NSDate date];
    __block NSURLSessionDataTask *task = nil;
    
    void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        @try {
            if (!objc_getAssociatedObject(task, &GleapLoggingRecordedKey)) {
                objc_setAssociatedObject(task, &GleapLoggingRecordedKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [GleapHttpTrafficRecorder recordRequest:request response:response data:data error:error startTime:startTime];
            }
        } @catch (NSException *exception) {
            // Handle exception silently.
        }
        if (completionHandler) {
            completionHandler(data, response, error);
        }
    };
    
    task = [session gleap_dataTaskWithRequest:request completionHandler:wrappedCompletion];
    return task;
}

// dataTaskWithURL:completionHandler:
NSURLSessionDataTask * gleap_dataTaskWithURL(id self,
                                             SEL _cmd,
                                             NSURL *url,
                                             void (^completionHandler)(NSData *, NSURLResponse *, NSError *)) {
    NSURLSession *session = (NSURLSession *)self;
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    __block NSDate *startTime = [NSDate date];
    __block NSURLSessionDataTask *task = nil;
    
    void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        @try {
            if (!objc_getAssociatedObject(task, &GleapLoggingRecordedKey)) {
                objc_setAssociatedObject(task, &GleapLoggingRecordedKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [GleapHttpTrafficRecorder recordRequest:request response:response data:data error:error startTime:startTime];
            }
        } @catch (NSException *exception) {}
        if (completionHandler) {
            completionHandler(data, response, error);
        }
    };
    
    task = [session gleap_dataTaskWithURL:url completionHandler:wrappedCompletion];
    return task;
}

// uploadTaskWithRequest:fromData:completionHandler:
NSURLSessionUploadTask * gleap_uploadTaskWithRequestFromData(id self,
                                                             SEL _cmd,
                                                             NSURLRequest *request,
                                                             NSData *bodyData,
                                                             void (^completionHandler)(NSData *, NSURLResponse *, NSError *)) {
    NSURLSession *session = (NSURLSession *)self;
    __block NSDate *startTime = [NSDate date];
    __block NSURLSessionUploadTask *task = nil;
    
    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    if (bodyData) {
        mutableRequest.HTTPBody = bodyData;
    }
    
    void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        @try {
            if (!objc_getAssociatedObject(task, &GleapLoggingRecordedKey)) {
                objc_setAssociatedObject(task, &GleapLoggingRecordedKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [GleapHttpTrafficRecorder recordRequest:request response:response data:data error:error startTime:startTime];
            }
        } @catch (NSException *exception) {}
        if (completionHandler) {
            completionHandler(data, response, error);
        }
    };
    
    task = [session gleap_uploadTaskWithRequest:request fromData:bodyData completionHandler:wrappedCompletion];
    return task;
}

// downloadTaskWithURL:completionHandler:
NSURLSessionDownloadTask * gleap_downloadTaskWithURL(id self,
                                                     SEL _cmd,
                                                     NSURL *url,
                                                     void (^completionHandler)(NSURL *, NSURLResponse *, NSError *)) {
    NSURLSession *session = (NSURLSession *)self;
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    __block NSDate *startTime = [NSDate date];
    __block NSURLSessionDownloadTask *task = nil;
    
    void (^wrappedCompletion)(NSURL *, NSURLResponse *, NSError *) = ^(NSURL *location, NSURLResponse *response, NSError *error) {
        @try {
            if (!objc_getAssociatedObject(task, &GleapLoggingRecordedKey)) {
                objc_setAssociatedObject(task, &GleapLoggingRecordedKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [GleapHttpTrafficRecorder recordRequest:request response:response data:nil error:error startTime:startTime];
            }
        } @catch (NSException *exception) {}
        if (completionHandler) {
            completionHandler(location, response, error);
        }
    };
    
    task = [session gleap_downloadTaskWithURL:url completionHandler:wrappedCompletion];
    return task;
}

// downloadTaskWithRequest:completionHandler:
NSURLSessionDownloadTask * gleap_downloadTaskWithRequest(id self,
                                                         SEL _cmd,
                                                         NSURLRequest *request,
                                                         void (^completionHandler)(NSURL *, NSURLResponse *, NSError *)) {
    NSURLSession *session = (NSURLSession *)self;
    __block NSDate *startTime = [NSDate date];
    __block NSURLSessionDownloadTask *task = nil;
    
    void (^wrappedCompletion)(NSURL *, NSURLResponse *, NSError *) = ^(NSURL *location, NSURLResponse *response, NSError *error) {
        @try {
            if (!objc_getAssociatedObject(task, &GleapLoggingRecordedKey)) {
                objc_setAssociatedObject(task, &GleapLoggingRecordedKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [GleapHttpTrafficRecorder recordRequest:request response:response data:nil error:error startTime:startTime];
            }
        } @catch (NSException *exception) {}
        if (completionHandler) {
            completionHandler(location, response, error);
        }
    };
    
    task = [session gleap_downloadTaskWithRequest:request completionHandler:wrappedCompletion];
    return task;
}

#pragma mark - Extended Swizzling for Custom Session Configurations

+ (void)swizzleSessionCreationForConfiguration:(NSURLSessionConfiguration *)configuration {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class sessionClass = object_getClass([NSURLSession class]);
        SEL originalSelector = @selector(sessionWithConfiguration:delegate:delegateQueue:);
        Method originalMethod = class_getClassMethod([NSURLSession class], originalSelector);
        IMP originalIMP = method_getImplementation(originalMethod);
        
        id swizzledBlock = ^NSURLSession *(Class _self, NSURLSessionConfiguration *config, id delegate, NSOperationQueue *queue) {
            NSURLSession *session = ((NSURLSession *(*)(id, SEL, NSURLSessionConfiguration *, id, NSOperationQueue *))originalIMP)(_self, originalSelector, config, delegate, queue);
            if ([config isEqual:configuration] && delegate) {
                [GleapHttpTrafficRecorder swizzleDelegateForSessionDelegate:delegate];
            }
            return session;
        };
        
        IMP swizzledIMP = imp_implementationWithBlock(swizzledBlock);
        class_replaceMethod(sessionClass, originalSelector, swizzledIMP, method_getTypeEncoding(originalMethod));
    });
}

+ (void)swizzleDelegateForSessionDelegate:(id)delegate {
    if (!delegate) {
        return;
    }
    Class delegateClass = object_getClass(delegate);
    
    // Swizzle URLSession:task:didCompleteWithError:
    SEL completeSelector = @selector(URLSession:task:didCompleteWithError:);
    Method completeMethod = class_getInstanceMethod(delegateClass, completeSelector);
    if (completeMethod) {
        IMP originalCompleteIMP = method_getImplementation(completeMethod);
        id swizzledCompleteBlock = ^(id self, NSURLSession *session, NSURLSessionTask *task, NSError *error) {
            @try {
                ((void (*)(id, SEL, NSURLSession *, NSURLSessionTask *, NSError *))originalCompleteIMP)(self, completeSelector, session, task, error);
                
                NSData *accumulatedData = nil;
                if ([task isKindOfClass:[NSURLSessionDataTask class]]) {
                    accumulatedData = objc_getAssociatedObject(task, &GleapAccumulatedDataKey);
                }
                
                NSURLRequest *request = task.originalRequest;
                NSURLResponse *response = task.response;
                NSDate *startTime = [NSDate date];
                [GleapHttpTrafficRecorder recordRequest:request response:response data:accumulatedData error:error startTime:startTime];
            } @catch (NSException *exception) {
                // Exception caught in didCompleteWithError; fail silently.
            }
        };
        IMP swizzledCompleteIMP = imp_implementationWithBlock(swizzledCompleteBlock);
        class_replaceMethod(delegateClass, completeSelector, swizzledCompleteIMP, method_getTypeEncoding(completeMethod));
    }
    
    // Swizzle URLSession:dataTask:didReceiveData:
    SEL receiveDataSelector = @selector(URLSession:dataTask:didReceiveData:);
    Method receiveDataMethod = class_getInstanceMethod(delegateClass, receiveDataSelector);
    if (receiveDataMethod) {
        IMP originalReceiveDataIMP = method_getImplementation(receiveDataMethod);
        id swizzledReceiveDataBlock = ^(id self, NSURLSession *session, NSURLSessionDataTask *dataTask, NSData *data) {
            @try {
                NSMutableData *accumulatedData = objc_getAssociatedObject(dataTask, &GleapAccumulatedDataKey);
                if (!accumulatedData) {
                    accumulatedData = [NSMutableData data];
                    objc_setAssociatedObject(dataTask, &GleapAccumulatedDataKey, accumulatedData, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                [accumulatedData appendData:data];
                
                ((void (*)(id, SEL, NSURLSession *, NSURLSessionDataTask *, NSData *))originalReceiveDataIMP)(self, receiveDataSelector, session, dataTask, data);
            } @catch (NSException *exception) {
                // Exception caught in didReceiveData; fail silently.
            }
        };
        IMP swizzledReceiveDataIMP = imp_implementationWithBlock(swizzledReceiveDataBlock);
        class_replaceMethod(delegateClass, receiveDataSelector, swizzledReceiveDataIMP, method_getTypeEncoding(receiveDataMethod));
    }
}

@end
