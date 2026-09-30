//
//  GleapHttpTrafficRecorder.m
//  Gleap
//
//  Created by Lukas Boehler on 28.03.21.
//
//  Logs the app's NSURLSession traffic. Every task is picked up when it is resumed and
//  finished when NSURLSessionTask reports the completed state, so completion handler,
//  delegate (Alamofire, Apollo, Moya, ...) and Swift async/await requests are all logged
//  with method, URL, headers, status, timing and errors. Response bodies are collected
//  from completion handlers and from session delegates' didReceiveData callbacks; Swift
//  async/await hands its data to the caller internally, so those requests are logged
//  without a response body.
//
//  Logging never changes a request or a callback: every hook calls the original
//  implementation and all bookkeeping is guarded.
//

#import <objc/runtime.h>
#import <objc/message.h>
#import <os/lock.h>
#import "GleapHttpTrafficRecorder.h"
#import "GleapCore.h"
#import "GleapUIHelper.h"
#import "GleapNetworkLogSanitizer.h"

// Per body (request payload and response text).
static NSUInteger const kGleapNetworkBodyLimit = 150000;
static int const kGleapDefaultMaxRequests = 30;

static NSString * const kGleapBodyBinary = @"[binary body omitted]";
static NSString * const kGleapBodyStreaming = @"[streaming body omitted]";
static NSString * const kGleapBodyNotCaptured = @"[body not captured]";

static char GleapNetworkRecordKey;
static char GleapUploadPayloadKey;

typedef NS_ENUM(NSInteger, GleapBodyState) {
    GleapBodyStateUnknown = 0,
    GleapBodyStateCapturing,
    GleapBodyStateCaptured,
    GleapBodyStateBinary,
    GleapBodyStateStreaming,
};

#pragma mark - Record

@interface GleapNetworkRecord : NSObject
@property (nonatomic, strong) NSDate *startDate;
@property (nonatomic, strong) NSDate *endDate;
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSDictionary *requestHeaders;
@property (nonatomic, copy) NSString *requestPayload;
@property (nonatomic, assign) BOOL completed;
@property (nonatomic, assign) NSInteger status;
@property (nonatomic, copy) NSDictionary *responseHeaders;
@property (nonatomic, copy) NSString *responseContentType;
@property (nonatomic, copy) NSString *errorText;
@property (nonatomic, assign) GleapBodyState bodyState;
@property (nonatomic, strong) NSMutableData *responseBody;
@property (nonatomic, assign) unsigned long long responseBytes;
@property (nonatomic, assign) BOOL isDownload;
@property (nonatomic, weak) NSURLSessionTask *task;
@end

@implementation GleapNetworkRecord
@end

#pragma mark - Recorder

@interface GleapHttpTrafficRecorder ()
@property (nonatomic, assign, readwrite) BOOL isRecording;
@property (nonatomic, assign, readwrite) BOOL stoppedByApp;
@property (nonatomic, strong) NSMutableArray<GleapNetworkRecord *> *records;
@property (nonatomic, assign) int maxRequestsInQueue;
@property (nonatomic, strong) NSArray<NSString *> *internalHosts;
@end

static os_unfair_lock gleapRecordsLock = OS_UNFAIR_LOCK_INIT;

// Set while a delegate's didReceiveData runs through one of our hooks, so a hooked
// subclass calling a hooked superclass doesn't record the same bytes twice.
static __thread BOOL gleapInsideDataHook = NO;

static NSDictionary *GleapStringHeaders(NSDictionary *headers);
static NSString *GleapHeaderValue(NSDictionary *headers, NSString *name);
static BOOL GleapIsStreamingContentType(NSString *contentType);
static BOOL GleapIsTextContentType(NSString *contentType);
static NSString *GleapBodyString(NSData *data, NSString *contentType, unsigned long long totalBytes);
static NSString *GleapErrorText(NSError *error);
static NSString *GleapStatusText(NSInteger status);
static NSDate *GleapParseLogDate(id value);
static void GleapObserveSessionDelegate(NSURLSession *session);

@implementation GleapHttpTrafficRecorder

+ (instancetype)sharedRecorder {
    static GleapHttpTrafficRecorder *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = self.new;
        shared.isRecording = NO;
        shared.maxRequestsInQueue = kGleapDefaultMaxRequests;
        shared.records = [[NSMutableArray alloc] init];
        shared.networkLogPropsToIgnore = [[NSArray alloc] init];
        shared.blacklist = [[NSArray alloc] init];
        shared.internalHosts = @[];
    });
    return shared;
}

#pragma mark - Public

- (BOOL)startRecordingForSessionConfiguration:(NSURLSessionConfiguration *)sessionConfig {
    return [self startRecording];
}

// Start, stop and the app's stop flag change under one lock, so a config applied while the app
// stops recording on another thread can't start it again after the stop.
- (BOOL)startRecording {
    @synchronized (self) {
        [self updateInternalHosts];
        if (self.isRecording) {
            return YES;
        }
        @try {
            [GleapHttpTrafficRecorder installHooks];
        } @catch (NSException *exception) {
            return NO;
        }
        self.isRecording = YES;
        return YES;
    }
}

- (void)stopRecording {
    @synchronized (self) {
        self.isRecording = NO;
    }
}

- (BOOL)startRecordingByApp {
    @synchronized (self) {
        self.stoppedByApp = NO;
        return [self startRecording];
    }
}

- (void)stopRecordingByApp {
    @synchronized (self) {
        self.stoppedByApp = YES;
        [self stopRecording];
    }
}

- (BOOL)startRecordingUnlessStoppedByApp {
    @synchronized (self) {
        if (self.stoppedByApp) {
            return NO;
        }
        return [self startRecording];
    }
}

- (void)setMaxRequests:(int)maxRequests {
    os_unfair_lock_lock(&gleapRecordsLock);
    self.maxRequestsInQueue = MAX(1, maxRequests);
    [self trimRecords];
    os_unfair_lock_unlock(&gleapRecordsLock);
}

- (void)clearLogs {
    os_unfair_lock_lock(&gleapRecordsLock);
    [self.records removeAllObjects];
    os_unfair_lock_unlock(&gleapRecordsLock);
}

- (NSArray *)networkLogs {
    NSMutableArray *result = [NSMutableArray array];
    os_unfair_lock_lock(&gleapRecordsLock);
    NSArray<GleapNetworkRecord *> *records = [self.records copy];
    os_unfair_lock_unlock(&gleapRecordsLock);

    for (GleapNetworkRecord *record in records) {
        @try {
            // Fallback when the completed state was missed: read it from the live task.
            NSURLSessionTask *task = record.task;
            if (task != nil && task.state == NSURLSessionTaskStateCompleted) {
                NSURLResponse *response = task.response;
                NSError *error = task.error;
                os_unfair_lock_lock(&gleapRecordsLock);
                if (!record.completed) {
                    [GleapHttpTrafficRecorder applyCompletionToRecord: record response: response error: error];
                }
                os_unfair_lock_unlock(&gleapRecordsLock);
            }

            os_unfair_lock_lock(&gleapRecordsLock);
            NSDictionary *log = [GleapHttpTrafficRecorder dictionaryForRecord: record];
            os_unfair_lock_unlock(&gleapRecordsLock);
            if (log != nil) {
                [result addObject: log];
            }
        } @catch (NSException *exception) {}
    }
    return result;
}

- (NSArray *)filterNetworkLogs:(NSArray *)networkLogs {
    NSMutableArray *propsToIgnore = [NSMutableArray array];
    NSMutableArray *blacklist = [NSMutableArray array];
    @try {
        if ([self.networkLogPropsToIgnore isKindOfClass: [NSArray class]]) {
            [propsToIgnore addObjectsFromArray: self.networkLogPropsToIgnore];
        }
        if ([[Gleap sharedInstance].networkLogPropsToIgnore isKindOfClass: [NSArray class]]) {
            [propsToIgnore addObjectsFromArray: [Gleap sharedInstance].networkLogPropsToIgnore];
        }
        if ([self.blacklist isKindOfClass: [NSArray class]]) {
            [blacklist addObjectsFromArray: self.blacklist];
        }
        if ([[Gleap sharedInstance].blacklist isKindOfClass: [NSArray class]]) {
            [blacklist addObjectsFromArray: [Gleap sharedInstance].blacklist];
        }
    } @catch (NSException *exception) {}
    return [GleapNetworkLogSanitizer sanitizeNetworkLogs: networkLogs propsToIgnore: propsToIgnore blacklist: blacklist];
}

+ (NSArray *)mergeNetworkLogs:(NSArray *)networkLogs withExternalNetworkLogs:(NSArray *)externalNetworkLogs {
    NSMutableArray *merged = [NSMutableArray arrayWithArray: [networkLogs isKindOfClass: [NSArray class]] ? networkLogs : @[]];
    if (![externalNetworkLogs isKindOfClass: [NSArray class]] || externalNetworkLogs.count == 0) {
        return merged;
    }

    NSMutableArray<NSDictionary *> *spans = [NSMutableArray array];
    for (NSDictionary *log in merged) {
        if (![log isKindOfClass: [NSDictionary class]]) {
            continue;
        }
        NSDate *start = GleapParseLogDate(log[@"date"]);
        if (start == nil || ![log[@"url"] isKindOfClass: [NSString class]]) {
            continue;
        }
        NSTimeInterval duration = [log[@"duration"] isKindOfClass: [NSNumber class]] ? [log[@"duration"] doubleValue] / 1000.0 : -[start timeIntervalSinceNow];
        [spans addObject: @{
            @"key": [NSString stringWithFormat: @"%@ %@", [[log[@"type"] description] uppercaseString], log[@"url"]],
            @"start": @(start.timeIntervalSince1970 - 1),
            @"end": @(start.timeIntervalSince1970 + MAX(duration, 0) + 2)
        }];
    }

    for (id external in externalNetworkLogs) {
        if ([external isKindOfClass: [NSDictionary class]] && spans.count > 0) {
            NSDictionary *log = (NSDictionary *)external;
            NSDate *date = GleapParseLogDate(log[@"date"]);
            if (date != nil && [log[@"url"] isKindOfClass: [NSString class]]) {
                NSString *key = [NSString stringWithFormat: @"%@ %@", [[log[@"type"] description] uppercaseString], log[@"url"]];
                NSTimeInterval time = date.timeIntervalSince1970;
                BOOL alreadyLogged = NO;
                for (NSDictionary *span in spans) {
                    if ([span[@"key"] isEqualToString: key] && time >= [span[@"start"] doubleValue] && time <= [span[@"end"] doubleValue]) {
                        alreadyLogged = YES;
                        break;
                    }
                }
                if (alreadyLogged) {
                    continue;
                }
            }
        }
        [merged addObject: external];
    }
    return merged;
}

#pragma mark - Records

// Hosts of a custom API or frame URL: the SDK's own traffic is never logged.
- (void)updateInternalHosts {
    NSMutableArray *hosts = [NSMutableArray array];
    @try {
        NSArray *urls = @[[Gleap sharedInstance].apiUrl ?: @"", [Gleap sharedInstance].frameUrl ?: @"", [Gleap sharedInstance].wsApiUrl ?: @""];
        for (NSString *urlString in urls) {
            NSString *host = [[NSURL URLWithString: urlString].host lowercaseString];
            if (host.length > 0 && ![hosts containsObject: host]) {
                [hosts addObject: host];
            }
        }
    } @catch (NSException *exception) {}
    os_unfair_lock_lock(&gleapRecordsLock);
    self.internalHosts = hosts;
    os_unfair_lock_unlock(&gleapRecordsLock);
}

- (BOOL)isInternalURL:(NSURL *)url {
    NSString *host = [url.host lowercaseString];
    if (host.length == 0) {
        return NO;
    }
    for (NSString *defaultHost in [GleapNetworkLogSanitizer defaultBlacklist]) {
        if ([host containsString: defaultHost]) {
            return YES;
        }
    }
    os_unfair_lock_lock(&gleapRecordsLock);
    BOOL isInternal = [self.internalHosts containsObject: host];
    os_unfair_lock_unlock(&gleapRecordsLock);
    return isInternal;
}

// Callers hold gleapRecordsLock.
- (void)trimRecords {
    while (self.records.count > (NSUInteger)self.maxRequestsInQueue) {
        [self.records removeObjectAtIndex: 0];
    }
}

- (void)taskWillResume:(NSURLSessionTask *)task {
    if (!self.isRecording || task == nil) {
        return;
    }
    if (![task isKindOfClass: [NSURLSessionDataTask class]] && ![task isKindOfClass: [NSURLSessionDownloadTask class]]) {
        // Stream and WebSocket tasks are not HTTP requests.
        return;
    }
    if (objc_getAssociatedObject(task, &GleapNetworkRecordKey) != nil) {
        // Resumed again after a suspend.
        return;
    }

    NSURLRequest *request = task.originalRequest ?: task.currentRequest;
    NSURL *url = request.URL;
    NSString *scheme = [url.scheme lowercaseString];
    if (url == nil || !([scheme isEqualToString: @"http"] || [scheme isEqualToString: @"https"])) {
        return;
    }
    if ([self isInternalURL: url]) {
        return;
    }

    GleapNetworkRecord *record = [[GleapNetworkRecord alloc] init];
    record.startDate = [NSDate date];
    record.method = [(request.HTTPMethod ?: @"GET") uppercaseString];
    record.url = url.absoluteString ?: @"";
    record.requestHeaders = GleapStringHeaders(request.allHTTPHeaderFields);
    record.isDownload = [task isKindOfClass: [NSURLSessionDownloadTask class]];
    record.task = task;

    NSString *uploadPayload = objc_getAssociatedObject(task, &GleapUploadPayloadKey);
    if (uploadPayload != nil) {
        record.requestPayload = uploadPayload;
    } else if (request.HTTPBody != nil) {
        record.requestPayload = GleapBodyString(request.HTTPBody, GleapHeaderValue(record.requestHeaders, @"Content-Type"), request.HTTPBody.length);
    } else if (request.HTTPBodyStream != nil) {
        record.requestPayload = kGleapBodyStreaming;
    } else if ([task isKindOfClass: [NSURLSessionUploadTask class]]) {
        // Swift async upload(for:from:) passes the body out of reach.
        record.requestPayload = kGleapBodyNotCaptured;
    } else {
        record.requestPayload = @"";
    }

    objc_setAssociatedObject(task, &GleapNetworkRecordKey, record, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    os_unfair_lock_lock(&gleapRecordsLock);
    [self.records addObject: record];
    [self trimRecords];
    os_unfair_lock_unlock(&gleapRecordsLock);
}

- (void)taskDidComplete:(NSURLSessionTask *)task {
    GleapNetworkRecord *record = objc_getAssociatedObject(task, &GleapNetworkRecordKey);
    if (record == nil) {
        return;
    }
    NSURLResponse *response = task.response;
    NSError *error = task.error;
    os_unfair_lock_lock(&gleapRecordsLock);
    if (!record.completed) {
        [GleapHttpTrafficRecorder applyCompletionToRecord: record response: response error: error];
    }
    os_unfair_lock_unlock(&gleapRecordsLock);
}

- (void)task:(NSURLSessionTask *)task didFinishWithData:(NSData *)data response:(NSURLResponse *)response error:(NSError *)error {
    GleapNetworkRecord *record = task != nil ? objc_getAssociatedObject(task, &GleapNetworkRecordKey) : nil;
    if (record == nil) {
        return;
    }
    os_unfair_lock_lock(&gleapRecordsLock);
    if (!record.completed) {
        [GleapHttpTrafficRecorder applyCompletionToRecord: record response: response error: error];
    }
    if (data != nil && record.bodyState != GleapBodyStateBinary && record.bodyState != GleapBodyStateStreaming) {
        NSUInteger captured = MIN(data.length, kGleapNetworkBodyLimit);
        record.responseBody = [[data subdataWithRange: NSMakeRange(0, captured)] mutableCopy];
        record.responseBytes = data.length;
        record.bodyState = GleapBodyStateCaptured;
    }
    os_unfair_lock_unlock(&gleapRecordsLock);
}

- (void)dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (data.length == 0) {
        return;
    }
    GleapNetworkRecord *record = objc_getAssociatedObject(task, &GleapNetworkRecordKey);
    if (record == nil) {
        return;
    }
    NSURLResponse *response = task.response;
    os_unfair_lock_lock(&gleapRecordsLock);
    if (record.bodyState == GleapBodyStateUnknown) {
        NSString *contentType = [response isKindOfClass: [NSHTTPURLResponse class]] ? GleapHeaderValue(((NSHTTPURLResponse *)response).allHeaderFields, @"Content-Type") : nil;
        if (GleapIsStreamingContentType(contentType)) {
            record.bodyState = GleapBodyStateStreaming;
        } else if (contentType.length > 0 && !GleapIsTextContentType(contentType)) {
            record.bodyState = GleapBodyStateBinary;
        } else {
            record.bodyState = GleapBodyStateCapturing;
            record.responseBody = [NSMutableData data];
        }
    }
    if (record.bodyState == GleapBodyStateCapturing && record.responseBody.length < kGleapNetworkBodyLimit) {
        NSUInteger remaining = kGleapNetworkBodyLimit - record.responseBody.length;
        [record.responseBody appendData: data.length <= remaining ? data : [data subdataWithRange: NSMakeRange(0, remaining)]];
    }
    record.responseBytes += data.length;
    os_unfair_lock_unlock(&gleapRecordsLock);
}

// Callers hold gleapRecordsLock.
+ (void)applyCompletionToRecord:(GleapNetworkRecord *)record response:(NSURLResponse *)response error:(NSError *)error {
    record.completed = YES;
    record.endDate = [NSDate date];
    if ([response isKindOfClass: [NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        record.status = httpResponse.statusCode;
        record.responseHeaders = GleapStringHeaders(httpResponse.allHeaderFields);
        record.responseContentType = GleapHeaderValue(record.responseHeaders, @"Content-Type");
    }
    if (error != nil) {
        record.errorText = GleapErrorText(error);
    }
    if (record.bodyState == GleapBodyStateUnknown) {
        if (GleapIsStreamingContentType(record.responseContentType)) {
            record.bodyState = GleapBodyStateStreaming;
        } else if (record.responseContentType.length > 0 && !GleapIsTextContentType(record.responseContentType)) {
            record.bodyState = GleapBodyStateBinary;
        }
    }
}

// Callers hold gleapRecordsLock.
+ (NSDictionary *)dictionaryForRecord:(GleapNetworkRecord *)record {
    NSMutableDictionary *log = [NSMutableDictionary dictionary];
    log[@"date"] = [GleapUIHelper getJSStringForNSDate: record.startDate];
    log[@"type"] = record.method ?: @"GET";
    log[@"url"] = record.url ?: @"";
    log[@"request"] = @{
        @"headers": record.requestHeaders ?: @{},
        @"payload": record.requestPayload ?: @""
    };

    if (!record.completed) {
        // Still in flight: no outcome yet.
        return log;
    }

    log[@"duration"] = @((NSInteger)llround([record.endDate timeIntervalSinceDate: record.startDate] * 1000.0));
    log[@"success"] = [NSNumber numberWithBool: record.errorText == nil];

    NSMutableDictionary *response = [NSMutableDictionary dictionary];
    if (record.status > 0) {
        response[@"status"] = @(record.status);
        response[@"statusText"] = GleapStatusText(record.status);
        response[@"headers"] = record.responseHeaders ?: @{};
        response[@"responseText"] = [self responseTextForRecord: record];
    }
    if (record.errorText != nil) {
        response[@"errorText"] = record.errorText;
    }
    log[@"response"] = response;
    return log;
}

+ (NSString *)responseTextForRecord:(GleapNetworkRecord *)record {
    switch (record.bodyState) {
        case GleapBodyStateBinary:
            return kGleapBodyBinary;
        case GleapBodyStateStreaming:
            return kGleapBodyStreaming;
        case GleapBodyStateCapturing:
        case GleapBodyStateCaptured:
            return GleapBodyString(record.responseBody, record.responseContentType, record.responseBytes);
        case GleapBodyStateUnknown:
        default:
            return kGleapBodyNotCaptured;
    }
}

#pragma mark - Hooks

+ (void)installHooks {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self installTaskHooks];
        [self installSessionHooks];
    });
}

// Resume and setState: are implemented on NSURLSessionTask, but a private subclass may
// override them: hook the implementation each concrete task class actually uses.
+ (NSArray<Class> *)taskClasses {
    NSMutableArray<Class> *classes = [NSMutableArray arrayWithObject: [NSURLSessionTask class]];
    @try {
        NSURLSession *probeSession = [NSURLSession sessionWithConfiguration: [NSURLSessionConfiguration ephemeralSessionConfiguration]];
        NSURL *probeURL = [NSURL URLWithString: @"https://127.0.0.1/"];
        NSArray *tasks = @[
            [probeSession dataTaskWithURL: probeURL],
            [probeSession uploadTaskWithRequest: [NSURLRequest requestWithURL: probeURL] fromData: [NSData data]],
            [probeSession downloadTaskWithURL: probeURL]
        ];
        for (NSURLSessionTask *task in tasks) {
            if (![classes containsObject: [task class]]) {
                [classes addObject: [task class]];
            }
        }
        [probeSession invalidateAndCancel];
    } @catch (NSException *exception) {}
    return classes;
}

+ (void)installTaskHooks {
    NSMutableSet<NSValue *> *hookedMethods = [NSMutableSet set];
    SEL resumeSelector = @selector(resume);
    SEL setStateSelector = NSSelectorFromString(@"setState:");

    for (Class taskClass in [self taskClasses]) {
        Method resumeMethod = class_getInstanceMethod(taskClass, resumeSelector);
        if (resumeMethod != NULL && ![hookedMethods containsObject: [NSValue valueWithPointer: resumeMethod]]) {
            [hookedMethods addObject: [NSValue valueWithPointer: resumeMethod]];
            IMP originalResume = method_getImplementation(resumeMethod);
            IMP resumeHook = imp_implementationWithBlock(^(NSURLSessionTask *task) {
                @try {
                    [[GleapHttpTrafficRecorder sharedRecorder] taskWillResume: task];
                } @catch (NSException *exception) {}
                ((void (*)(id, SEL))originalResume)(task, resumeSelector);
            });
            method_setImplementation(resumeMethod, resumeHook);
        }

        Method setStateMethod = class_getInstanceMethod(taskClass, setStateSelector);
        if (setStateMethod != NULL && ![hookedMethods containsObject: [NSValue valueWithPointer: setStateMethod]]) {
            [hookedMethods addObject: [NSValue valueWithPointer: setStateMethod]];
            IMP originalSetState = method_getImplementation(setStateMethod);
            IMP setStateHook = imp_implementationWithBlock(^(NSURLSessionTask *task, NSURLSessionTaskState state) {
                ((void (*)(id, SEL, NSURLSessionTaskState))originalSetState)(task, setStateSelector, state);
                if (state == NSURLSessionTaskStateCompleted) {
                    @try {
                        [[GleapHttpTrafficRecorder sharedRecorder] taskDidComplete: task];
                    } @catch (NSException *exception) {}
                }
            });
            method_setImplementation(setStateMethod, setStateHook);
        }
    }
}

+ (void)installSessionHooks {
    NSMutableArray<Class> *sessionClasses = [NSMutableArray arrayWithObject: [NSURLSession class]];
    @try {
        Class sharedSessionClass = [[NSURLSession sharedSession] class];
        if (sharedSessionClass != nil && ![sessionClasses containsObject: sharedSessionClass]) {
            [sessionClasses addObject: sharedSessionClass];
        }
    } @catch (NSException *exception) {}

    NSMutableSet<NSValue *> *hookedMethods = [NSMutableSet set];
    for (Class sessionClass in sessionClasses) {
        [self hookDataTaskWithCompletion: sessionClass selector: @selector(dataTaskWithRequest:completionHandler:) hooked: hookedMethods];
        [self hookDataTaskWithCompletion: sessionClass selector: @selector(dataTaskWithURL:completionHandler:) hooked: hookedMethods];
        [self hookUploadTaskWithCompletion: sessionClass selector: @selector(uploadTaskWithRequest:fromData:completionHandler:) hooked: hookedMethods];
        [self hookUploadTaskWithCompletion: sessionClass selector: @selector(uploadTaskWithRequest:fromFile:completionHandler:) hooked: hookedMethods];
        [self hookTaskFactory: sessionClass selector: @selector(dataTaskWithRequest:) hooked: hookedMethods];
        [self hookTaskFactory: sessionClass selector: @selector(dataTaskWithURL:) hooked: hookedMethods];
        [self hookTaskFactory: sessionClass selector: @selector(uploadTaskWithStreamedRequest:) hooked: hookedMethods];
        [self hookUploadTaskFactory: sessionClass selector: @selector(uploadTaskWithRequest:fromData:) hooked: hookedMethods];
        [self hookUploadTaskFactory: sessionClass selector: @selector(uploadTaskWithRequest:fromFile:) hooked: hookedMethods];
    }
}

+ (Method)unhookedMethod:(Class)cls selector:(SEL)selector hooked:(NSMutableSet<NSValue *> *)hooked {
    Method method = class_getInstanceMethod(cls, selector);
    if (method == NULL || [hooked containsObject: [NSValue valueWithPointer: method]]) {
        return NULL;
    }
    [hooked addObject: [NSValue valueWithPointer: method]];
    return method;
}

// dataTaskWithRequest:completionHandler: and dataTaskWithURL:completionHandler: — the first
// argument is an NSURLRequest or an NSURL, both passed through untouched.
+ (void)hookDataTaskWithCompletion:(Class)cls selector:(SEL)selector hooked:(NSMutableSet<NSValue *> *)hooked {
    Method method = [self unhookedMethod: cls selector: selector hooked: hooked];
    if (method == NULL) {
        return;
    }
    typedef NSURLSessionDataTask *(*GleapDataTaskFn)(id, SEL, id, id);
    GleapDataTaskFn original = (GleapDataTaskFn)method_getImplementation(method);
    IMP hook = imp_implementationWithBlock(^NSURLSessionDataTask *(NSURLSession *session, id requestOrURL, void (^completionHandler)(NSData *, NSURLResponse *, NSError *)) {
        GleapHttpTrafficRecorder *recorder = [GleapHttpTrafficRecorder sharedRecorder];
        if (!recorder.isRecording) {
            return original(session, selector, requestOrURL, completionHandler);
        }
        if (completionHandler == nil) {
            // Without a handler the data goes to the session delegate.
            NSURLSessionDataTask *task = original(session, selector, requestOrURL, completionHandler);
            GleapObserveSessionDelegate(session);
            return task;
        }
        __block __weak NSURLSessionTask *weakTask = nil;
        void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            @try {
                [recorder task: weakTask didFinishWithData: data response: response error: error];
            } @catch (NSException *exception) {}
            completionHandler(data, response, error);
        };
        NSURLSessionDataTask *task = original(session, selector, requestOrURL, wrappedHandler);
        weakTask = task;
        return task;
    });
    method_setImplementation(method, hook);
}

// uploadTaskWithRequest:fromData:completionHandler: and uploadTaskWithRequest:fromFile:completionHandler:
+ (void)hookUploadTaskWithCompletion:(Class)cls selector:(SEL)selector hooked:(NSMutableSet<NSValue *> *)hooked {
    Method method = [self unhookedMethod: cls selector: selector hooked: hooked];
    if (method == NULL) {
        return;
    }
    typedef NSURLSessionUploadTask *(*GleapUploadTaskFn)(id, SEL, NSURLRequest *, id, id);
    GleapUploadTaskFn original = (GleapUploadTaskFn)method_getImplementation(method);
    IMP hook = imp_implementationWithBlock(^NSURLSessionUploadTask *(NSURLSession *session, NSURLRequest *request, id bodyDataOrFile, void (^completionHandler)(NSData *, NSURLResponse *, NSError *)) {
        GleapHttpTrafficRecorder *recorder = [GleapHttpTrafficRecorder sharedRecorder];
        if (!recorder.isRecording) {
            return original(session, selector, request, bodyDataOrFile, completionHandler);
        }
        if (completionHandler == nil) {
            NSURLSessionUploadTask *task = original(session, selector, request, bodyDataOrFile, completionHandler);
            [GleapHttpTrafficRecorder rememberUploadBody: bodyDataOrFile request: request task: task];
            GleapObserveSessionDelegate(session);
            return task;
        }
        __block __weak NSURLSessionTask *weakTask = nil;
        void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            @try {
                [recorder task: weakTask didFinishWithData: data response: response error: error];
            } @catch (NSException *exception) {}
            completionHandler(data, response, error);
        };
        NSURLSessionUploadTask *task = original(session, selector, request, bodyDataOrFile, wrappedHandler);
        weakTask = task;
        [GleapHttpTrafficRecorder rememberUploadBody: bodyDataOrFile request: request task: task];
        return task;
    });
    method_setImplementation(method, hook);
}

// dataTaskWithRequest:, dataTaskWithURL:, uploadTaskWithStreamedRequest: — delegate-based tasks.
+ (void)hookTaskFactory:(Class)cls selector:(SEL)selector hooked:(NSMutableSet<NSValue *> *)hooked {
    Method method = [self unhookedMethod: cls selector: selector hooked: hooked];
    if (method == NULL) {
        return;
    }
    typedef NSURLSessionTask *(*GleapTaskFactoryFn)(id, SEL, id);
    GleapTaskFactoryFn original = (GleapTaskFactoryFn)method_getImplementation(method);
    IMP hook = imp_implementationWithBlock(^NSURLSessionTask *(NSURLSession *session, id requestOrURL) {
        NSURLSessionTask *task = original(session, selector, requestOrURL);
        if ([GleapHttpTrafficRecorder sharedRecorder].isRecording) {
            GleapObserveSessionDelegate(session);
        }
        return task;
    });
    method_setImplementation(method, hook);
}

// uploadTaskWithRequest:fromData: and uploadTaskWithRequest:fromFile: — delegate-based uploads.
+ (void)hookUploadTaskFactory:(Class)cls selector:(SEL)selector hooked:(NSMutableSet<NSValue *> *)hooked {
    Method method = [self unhookedMethod: cls selector: selector hooked: hooked];
    if (method == NULL) {
        return;
    }
    typedef NSURLSessionUploadTask *(*GleapUploadFactoryFn)(id, SEL, NSURLRequest *, id);
    GleapUploadFactoryFn original = (GleapUploadFactoryFn)method_getImplementation(method);
    IMP hook = imp_implementationWithBlock(^NSURLSessionUploadTask *(NSURLSession *session, NSURLRequest *request, id bodyDataOrFile) {
        NSURLSessionUploadTask *task = original(session, selector, request, bodyDataOrFile);
        if ([GleapHttpTrafficRecorder sharedRecorder].isRecording) {
            [GleapHttpTrafficRecorder rememberUploadBody: bodyDataOrFile request: request task: task];
            GleapObserveSessionDelegate(session);
        }
        return task;
    });
    method_setImplementation(method, hook);
}

// Upload bodies are passed next to the request: keep a text copy for the log.
+ (void)rememberUploadBody:(id)bodyDataOrFile request:(NSURLRequest *)request task:(NSURLSessionTask *)task {
    if (task == nil) {
        return;
    }
    @try {
        NSString *payload = kGleapBodyNotCaptured;
        if ([bodyDataOrFile isKindOfClass: [NSData class]]) {
            NSData *body = (NSData *)bodyDataOrFile;
            NSString *contentType = GleapHeaderValue(request.allHTTPHeaderFields, @"Content-Type");
            NSData *prefix = body.length > kGleapNetworkBodyLimit ? [body subdataWithRange: NSMakeRange(0, kGleapNetworkBodyLimit)] : body;
            payload = GleapBodyString(prefix, contentType, body.length);
        }
        objc_setAssociatedObject(task, &GleapUploadPayloadKey, payload, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (NSException *exception) {}
}

@end

#pragma mark - Session delegates

static NSMutableSet<Class> *gleapObservedDelegateClasses = nil;

static BOOL GleapClassDefinesMethod(Class cls, SEL selector) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == selector) {
            found = YES;
            break;
        }
    }
    free(methods);
    return found;
}

// Hooks URLSession:dataTask:didReceiveData: of the session delegate's class (once per
// class) to collect response bodies of delegate-based tasks, e.g. Alamofire's. Only
// classes that already implement the callback are touched, and the hook always calls
// the implementation that ran before.
static void GleapObserveSessionDelegate(NSURLSession *session) {
    @try {
        id delegate = session.delegate;
        if (delegate == nil) {
            return;
        }
        Class delegateClass = object_getClass(delegate);
        if (delegateClass == nil) {
            return;
        }

        os_unfair_lock_lock(&gleapRecordsLock);
        if (gleapObservedDelegateClasses == nil) {
            gleapObservedDelegateClasses = [NSMutableSet set];
        }
        BOOL alreadyObserved = [gleapObservedDelegateClasses containsObject: delegateClass];
        if (!alreadyObserved) {
            [gleapObservedDelegateClasses addObject: delegateClass];
        }
        os_unfair_lock_unlock(&gleapRecordsLock);
        if (alreadyObserved) {
            return;
        }

        SEL selector = @selector(URLSession:dataTask:didReceiveData:);
        Method method = class_getInstanceMethod(delegateClass, selector);
        if (method == NULL) {
            return;
        }

        typedef void (*GleapDidReceiveDataFn)(id, SEL, NSURLSession *, NSURLSessionDataTask *, NSData *);
        if (GleapClassDefinesMethod(delegateClass, selector)) {
            GleapDidReceiveDataFn original = (GleapDidReceiveDataFn)method_getImplementation(method);
            IMP hook = imp_implementationWithBlock(^(id receiver, NSURLSession *urlSession, NSURLSessionDataTask *dataTask, NSData *data) {
                BOOL outermost = !gleapInsideDataHook;
                if (outermost) {
                    gleapInsideDataHook = YES;
                    @try {
                        [[GleapHttpTrafficRecorder sharedRecorder] dataTask: dataTask didReceiveData: data];
                    } @catch (NSException *exception) {}
                }
                @try {
                    original(receiver, selector, urlSession, dataTask, data);
                } @finally {
                    if (outermost) {
                        gleapInsideDataHook = NO;
                    }
                }
            });
            method_setImplementation(method, hook);
        } else {
            // Inherited: add an override that forwards to the superclass implementation.
            Class superclass = class_getSuperclass(delegateClass);
            IMP hook = imp_implementationWithBlock(^(id receiver, NSURLSession *urlSession, NSURLSessionDataTask *dataTask, NSData *data) {
                BOOL outermost = !gleapInsideDataHook;
                if (outermost) {
                    gleapInsideDataHook = YES;
                    @try {
                        [[GleapHttpTrafficRecorder sharedRecorder] dataTask: dataTask didReceiveData: data];
                    } @catch (NSException *exception) {}
                }
                @try {
                    struct objc_super superInfo = { receiver, superclass };
                    ((void (*)(struct objc_super *, SEL, NSURLSession *, NSURLSessionDataTask *, NSData *))objc_msgSendSuper)(&superInfo, selector, urlSession, dataTask, data);
                } @finally {
                    if (outermost) {
                        gleapInsideDataHook = NO;
                    }
                }
            });
            class_addMethod(delegateClass, selector, hook, method_getTypeEncoding(method));
        }
    } @catch (NSException *exception) {}
}

#pragma mark - Helpers

static NSDictionary *GleapStringHeaders(NSDictionary *headers) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (![headers isKindOfClass: [NSDictionary class]]) {
        return result;
    }
    for (id key in headers) {
        id value = headers[key];
        if (![key isKindOfClass: [NSString class]]) {
            continue;
        }
        if ([value isKindOfClass: [NSString class]]) {
            result[key] = value;
        } else if ([value isKindOfClass: [NSArray class]]) {
            result[key] = [(NSArray *)value componentsJoinedByString: @", "];
        } else if (value != nil) {
            result[key] = [value description];
        }
    }
    return result;
}

static NSString *GleapHeaderValue(NSDictionary *headers, NSString *name) {
    if (![headers isKindOfClass: [NSDictionary class]]) {
        return nil;
    }
    for (id key in headers) {
        if ([key isKindOfClass: [NSString class]] && [(NSString *)key caseInsensitiveCompare: name] == NSOrderedSame) {
            id value = headers[key];
            return [value isKindOfClass: [NSString class]] ? value : nil;
        }
    }
    return nil;
}

static BOOL GleapIsStreamingContentType(NSString *contentType) {
    if (contentType.length == 0) {
        return NO;
    }
    NSString *type = [contentType lowercaseString];
    for (NSString *streamingType in @[@"text/event-stream", @"x-ndjson", @"stream+json", @"multipart/x-mixed-replace", @"grpc"]) {
        if ([type containsString: streamingType]) {
            return YES;
        }
    }
    return NO;
}

static BOOL GleapIsTextContentType(NSString *contentType) {
    if (contentType.length == 0) {
        return NO;
    }
    NSString *type = [contentType lowercaseString];
    for (NSString *textType in @[@"json", @"xml", @"text/", @"javascript", @"x-www-form-urlencoded", @"graphql"]) {
        if ([type containsString: textType]) {
            return YES;
        }
    }
    return NO;
}

// Text of a captured body (at most kGleapNetworkBodyLimit bytes of totalBytes) or a marker.
// Without a content type the body is kept only when it is valid UTF-8.
static NSString *GleapBodyString(NSData *data, NSString *contentType, unsigned long long totalBytes) {
    if (data == nil || data.length == 0) {
        return @"";
    }
    if (GleapIsStreamingContentType(contentType)) {
        return kGleapBodyStreaming;
    }
    BOOL knownText = GleapIsTextContentType(contentType);
    if (contentType.length > 0 && !knownText) {
        return kGleapBodyBinary;
    }

    NSData *bytes = data.length > kGleapNetworkBodyLimit ? [data subdataWithRange: NSMakeRange(0, kGleapNetworkBodyLimit)] : data;
    NSString *text = [[NSString alloc] initWithData: bytes encoding: NSUTF8StringEncoding];
    // A cut at the limit can split a multi-byte character.
    for (NSUInteger trim = 1; text == nil && trim <= 3 && bytes.length > trim && totalBytes > bytes.length; trim++) {
        text = [[NSString alloc] initWithData: [bytes subdataWithRange: NSMakeRange(0, bytes.length - trim)] encoding: NSUTF8StringEncoding];
    }
    if (text == nil && knownText) {
        text = [[NSString alloc] initWithData: bytes encoding: NSISOLatin1StringEncoding];
    }
    if (text == nil) {
        return kGleapBodyBinary;
    }
    if (totalBytes > bytes.length) {
        return [text stringByAppendingFormat: @"\n… [truncated, %llu bytes]", totalBytes];
    }
    return text;
}

static NSString *GleapErrorText(NSError *error) {
    if (error == nil) {
        return nil;
    }
    NSString *description = error.localizedDescription ?: @"Request failed";
    return [NSString stringWithFormat: @"%@ (%@ %ld)", description, error.domain ?: @"", (long)error.code];
}

// The server's reason phrase isn't exposed by NSHTTPURLResponse; use the standard one.
static NSString *GleapStatusText(NSInteger status) {
    static NSDictionary<NSNumber *, NSString *> *reasonPhrases = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        reasonPhrases = @{
            @200: @"OK", @201: @"Created", @202: @"Accepted", @204: @"No Content", @206: @"Partial Content",
            @301: @"Moved Permanently", @302: @"Found", @303: @"See Other", @304: @"Not Modified", @307: @"Temporary Redirect", @308: @"Permanent Redirect",
            @400: @"Bad Request", @401: @"Unauthorized", @402: @"Payment Required", @403: @"Forbidden", @404: @"Not Found", @405: @"Method Not Allowed",
            @406: @"Not Acceptable", @408: @"Request Timeout", @409: @"Conflict", @410: @"Gone", @412: @"Precondition Failed", @413: @"Content Too Large",
            @415: @"Unsupported Media Type", @422: @"Unprocessable Content", @429: @"Too Many Requests",
            @500: @"Internal Server Error", @501: @"Not Implemented", @502: @"Bad Gateway", @503: @"Service Unavailable", @504: @"Gateway Timeout"
        };
    });
    NSString *phrase = reasonPhrases[@(status)];
    if (phrase != nil) {
        return phrase;
    }
    return [[NSHTTPURLResponse localizedStringForStatusCode: status] capitalizedString] ?: @"";
}

// ISO 8601 with or without fractional seconds (other formats are not matched).
static NSDate *GleapParseLogDate(id value) {
    if (![value isKindOfClass: [NSString class]]) {
        return nil;
    }
    static NSISO8601DateFormatter *withFraction = nil;
    static NSISO8601DateFormatter *withoutFraction = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        withFraction = [[NSISO8601DateFormatter alloc] init];
        withFraction.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        withoutFraction = [[NSISO8601DateFormatter alloc] init];
        withoutFraction.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    });
    return [withFraction dateFromString: value] ?: [withoutFraction dateFromString: value];
}
