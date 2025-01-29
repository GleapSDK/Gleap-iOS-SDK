//
//  GleapNetworkLogger.m
//  Gleap
//
//  Created by Lukas Boehler on 28.03.21.
//

#import <objc/runtime.h>
#import <objc/message.h>
#import "GleapHttpTrafficRecorder.h"
#import "GleapCore.h"
#import "GleapUIHelper.h"
#import "GleapWidgetManager.h"

NSString * const GleapHTTPTrafficRecordingProgressRequestKey    = @"REQUEST_KEY";
NSString * const GleapHTTPTrafficRecordingProgressResponseKey   = @"RESPONSE_KEY";
NSString * const GleapHTTPTrafficRecordingProgressBodyDataKey   = @"BODY_DATA_KEY";
NSString * const GleapHTTPTrafficRecordingProgressStartDateKey  = @"REQUEST_START_DATE_KEY";
NSString * const GleapHTTPTrafficRecordingProgressErrorKey      = @"ERROR_KEY";

#pragma mark - Private Category on NSURLSession

@interface NSURLSession (GleapSwizzling)
- (NSURLSessionDataTask *)gleap_dataTaskWithRequest:(NSURLRequest *)request
                                  completionHandler:(void (^)(NSData *data,
                                                               NSURLResponse *response,
                                                               NSError *error))completionHandler;
@end

@interface GleapHttpTrafficRecorder ()
@property (nonatomic, assign, readwrite) BOOL isRecording;
@property (nonatomic, strong) NSMutableArray *requests;
@property (nonatomic, assign) int maxRequestsInQueue;
// Remove sessionConfig or protocol-related properties, because we're not using them anymore.
@end

@implementation GleapHttpTrafficRecorder

+ (instancetype)sharedRecorder
{
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

- (BOOL)startRecordingForSessionConfiguration:(NSURLSessionConfiguration *)sessionConfig {
    return [self startRecording];
}

- (BOOL)startRecording {
    if (self.isRecording) {
        return YES; // Already recording
    }
    self.isRecording = YES;
    
    // Trigger the swizzling (see below)
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
    NSMutableArray* processedNetworkLogs = [[NSMutableArray alloc] init];
    
    // Filter networklog properties.
    for (int i = 0; i < [networkLogs count]; i++) {
        NSMutableDictionary * log =  [[NSMutableDictionary alloc] initWithDictionary: [networkLogs objectAtIndex: i]];
        
        @try {
            NSArray *localNetworkLogPropsToIgnore = [self.networkLogPropsToIgnore arrayByAddingObjectsFromArray: [Gleap sharedInstance].networkLogPropsToIgnore];
            
            if (localNetworkLogPropsToIgnore != nil && localNetworkLogPropsToIgnore.count >= 0) {
                if ([log objectForKey: @"request"] != nil) {
                    NSMutableDictionary *request = [[NSMutableDictionary alloc] initWithDictionary: [log objectForKey: @"request"]];
                    if (request != nil && [request objectForKey: @"headers"]) {
                        if ([request objectForKey: @"headers"] != nil && [[request objectForKey: @"headers"] isKindOfClass:[NSDictionary class]]) {
                            NSMutableDictionary *mutableHeaders = [[NSMutableDictionary alloc] initWithDictionary: [request objectForKey: @"headers"]];
                            [mutableHeaders removeObjectsForKeys: localNetworkLogPropsToIgnore];
                            [request setObject: mutableHeaders forKey: @"headers"];
                        }
                    }
                    
                    if (request != nil && [request objectForKey: @"payload"]) {
                        if ([request objectForKey: @"payload"] != nil) {
                            NSError *jsonError;
                            NSMutableDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:[[request objectForKey: @"payload"] dataUsingEncoding:NSUTF8StringEncoding]  options: NSJSONReadingMutableContainers error:&jsonError];
                            if (jsonError == nil && jsonObject != nil) {
                                if ([jsonObject isKindOfClass:[NSDictionary class]]) {
                                    [jsonObject removeObjectsForKeys: localNetworkLogPropsToIgnore];
                                }
                                
                                NSError *jsonDataError;
                                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonObject
                                                                                   options:0
                                                                                     error:&jsonDataError];
                                if (jsonData != nil) {
                                    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                                    if (jsonString != nil) {
                                        [request setObject: jsonString forKey: @"payload"];
                                    }
                                }
                            }
                        }
                    }
                    if (request != nil) {
                        [log setObject: request forKey: @"request"];
                    }
                }
                
                if ([log objectForKey: @"response"] != nil) {
                    NSMutableDictionary *response = [[NSMutableDictionary alloc] initWithDictionary: [log objectForKey: @"response"]];
                    if (response != nil && [response objectForKey: @"responseText"] != nil) {
                        NSError *jsonError;
                        id jsonObject = [NSJSONSerialization JSONObjectWithData:[[response objectForKey: @"responseText"] dataUsingEncoding:NSUTF8StringEncoding]  options: NSJSONReadingMutableContainers error:&jsonError];
                        if (jsonError == nil && jsonObject != nil) {
                            if ([jsonObject isKindOfClass:[NSDictionary class]]) {
                                [jsonObject removeObjectsForKeys: localNetworkLogPropsToIgnore];
                            }
                            
                            NSError *jsonDataError;
                            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonObject
                                                                               options:0
                                                                                 error:&jsonDataError];
                            if (jsonData != nil) {
                                NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                                if (jsonString != nil) {
                                    [response setObject: jsonString forKey: @"responseText"];
                                }
                            }
                        }
                        
                        [log setObject: response forKey: @"response"];
                    }
                }
            }
        }
        @catch (NSException *exception) {}
        
        // Network log blacklist.
        NSArray *blacklistItems = [self.blacklist arrayByAddingObjectsFromArray: [Gleap sharedInstance].blacklist];
        
        NSString *logUrl = [log objectForKey: @"url"];
        BOOL shouldAddLog = YES;
        if (logUrl != nil) {
            for (int i = 0; i < blacklistItems.count; i++) {
                NSString *currentBlacklistItem = [blacklistItems objectAtIndex: i];
                if (currentBlacklistItem != nil && [logUrl containsString: currentBlacklistItem]) {
                    shouldAddLog = NO;
                }
            }
        }
        
        if (shouldAddLog) {
            [processedNetworkLogs addObject: log];
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
    if ([contentType containsString:@"text/"]) {
        return true;
    }
    if ([contentType containsString:@"application/javascript"]) {
        return true;
    }
    if ([contentType containsString:@"application/xhtml+xml"]) {
        return true;
    }
    if ([contentType containsString:@"application/json"]) {
        return true;
    }
    if ([contentType containsString:@"application/xml"]) {
        return true;
    }
    if ([contentType containsString:@"application/x-www-form-urlencoded"]) {
        return true;
    }
    if ([contentType containsString:@"multipart/"]) {
        return true;
    }
    return false;
}

#pragma mark - Internal Logging

/**
 Wraps the "updateRecorderProgressDelegate" logic into a single method we can call
 from our swizzled completion block.
 */
+ (void)recordRequest:(NSURLRequest *)request
             response:(NSURLResponse *)response
                data:(NSData *)data
               error:(NSError *)error
           startTime:(NSDate *)startTime
{
    if (!request) {
        return;
    }
    
    NSMutableURLRequest *mutableRequest = [request isKindOfClass:[NSMutableURLRequest class]]
        ? (NSMutableURLRequest *)request
        : [request mutableCopy]; // We need mutable to pass into existing logging.

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
}

/**
 This is your existing logic from GleapRecordingProtocol's +updateRecorderProgressDelegate:
 */
+ (void)updateRecorderProgressDelegate:(BOOL)success userInfo:(NSDictionary *)info {
    NSMutableURLRequest *urlRequest = info[GleapHTTPTrafficRecordingProgressRequestKey];
    if (![urlRequest isKindOfClass:[NSMutableURLRequest class]]) {
        return; // Safety check
    }
    
    NSMutableDictionary *requestLog = [NSMutableDictionary dictionary];
    [requestLog setValue:urlRequest.HTTPMethod forKey:@"type"];
    [requestLog setValue:urlRequest.URL.absoluteString forKey:@"url"];
    [requestLog setValue:[GleapUIHelper getJSStringForNSDate:[NSDate date]] forKey:@"date"];
    
    NSDate *startLoadingDate = info[GleapHTTPTrafficRecordingProgressStartDateKey];
    if (startLoadingDate) {
        int duration = (int)([startLoadingDate timeIntervalSinceNow] * -1000);
        [requestLog setValue:@(duration) forKey:@"duration"];
    }
    
    if (success) {
        NSHTTPURLResponse *response = info[GleapHTTPTrafficRecordingProgressResponseKey];
        NSData *data = info[GleapHTTPTrafficRecordingProgressBodyDataKey];
        NSString *contentType = @"";
        
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            contentType = [((NSHTTPURLResponse *)response) allHeaderFields][@"Content-Type"] ?: @"";
        }
        
        requestLog[@"success"] = @(YES);
        
        // Request details
        NSMutableDictionary *reqObj = [NSMutableDictionary dictionary];
        if (urlRequest.HTTPBody) {
            reqObj[@"payload"] = [GleapHttpTrafficRecorder stringFrom:urlRequest.HTTPBody];
        } else {
            reqObj[@"payload"] = @"";
        }
        if (urlRequest.allHTTPHeaderFields) {
            reqObj[@"headers"] = urlRequest.allHTTPHeaderFields;
        }
        requestLog[@"request"] = reqObj;
        
        // Response details
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            NSMutableDictionary *respObj = [NSMutableDictionary dictionary];
            respObj[@"status"] = @(httpResp.statusCode);
            respObj[@"headers"] = httpResp.allHeaderFields ?: @{};
            respObj[@"contentType"] = contentType;
            
            // Only store text-based content and only if under 0.5MB
            int maxBodySize = 1024 * 500;
            if ([GleapHttpTrafficRecorder isTextBasedContentType:contentType] && data.length < maxBodySize) {
                respObj[@"responseText"] = [GleapHttpTrafficRecorder stringFrom:data];
            } else {
                respObj[@"responseText"] = @"<response_too_large>";
            }
            
            requestLog[@"response"] = respObj;
        }
        
    } else {
        // Failure
        requestLog[@"success"] = @(NO);
        NSError *error = info[GleapHTTPTrafficRecordingProgressErrorKey];
        NSMutableDictionary *respObj = [NSMutableDictionary dictionary];
        if (error) {
            respObj[@"errorText"] = error.localizedDescription ?: @"";
        }
        requestLog[@"response"] = respObj;
    }
    
    // If widget is open, skip
    if ([[GleapWidgetManager sharedInstance] isOpened]) {
        return;
    }
    
    // Add to queue
    GleapHttpTrafficRecorder *recorder = [GleapHttpTrafficRecorder sharedRecorder];
    @synchronized (recorder.requests) {
        if (recorder.requests.count >= recorder.maxRequestsInQueue) {
            [recorder.requests removeObjectAtIndex:0];
        }
        [recorder.requests addObject:[requestLog copy]];
    }
}

#pragma mark - Swizzling

+ (void)swizzleURLSessionIfNeeded {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class sessionClass = [NSURLSession class];
        
        // Original selector
        SEL originalSEL = @selector(dataTaskWithRequest:completionHandler:);
        Method originalMethod = class_getInstanceMethod(sessionClass, originalSEL);
        if (!originalMethod) {
            return;
        }
        
        // Our swizzled selector
        SEL swizzledSEL = @selector(gleap_dataTaskWithRequest:completionHandler:);
        Method swizzledMethod = class_getInstanceMethod(sessionClass, swizzledSEL);
        if (!swizzledMethod) {
            // We’ll create it dynamically below
            IMP swizzledImpl = (IMP)gleap_dataTaskWithRequest;
            const char *typeEncoding = method_getTypeEncoding(originalMethod);
            class_addMethod(sessionClass, swizzledSEL, swizzledImpl, typeEncoding);
            swizzledMethod = class_getInstanceMethod(sessionClass, swizzledSEL);
            if (!swizzledMethod) {
                return;
            }
        }
        
        // Exchange the implementations
        method_exchangeImplementations(originalMethod, swizzledMethod);
    });
}

/**
 Our custom C function that re-implements `dataTaskWithRequest:completionHandler:`.
 
 We must cast `self` and arguments properly, then call the *swizzled* method to get
 the actual NSURLSessionDataTask from the system, while wrapping the completion block
 so we can capture the response/error.
 */
NSURLSessionDataTask * gleap_dataTaskWithRequest(id self,
                                                 SEL _cmd,
                                                 NSURLRequest *request,
                                                 void (^completionHandler)(NSData *, NSURLResponse *, NSError *))
{
    // Cast `self` to NSURLSession
    NSURLSession *session = (NSURLSession *)self;
    if (!request) {
        // Just call the original if request is nil
        return [session gleap_dataTaskWithRequest:request completionHandler:completionHandler];
    }
    
    __block NSDate *startTime = [NSDate date];
    
    // Wrap the original completion so we can log the result
    void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) =
    ^(NSData *data, NSURLResponse *response, NSError *error) {
        
        // Log via Gleap
        [GleapHttpTrafficRecorder recordRequest:request
                                       response:response
                                          data:data
                                         error:error
                                     startTime:startTime];
        
        // Call the original completion
        if (completionHandler) {
            completionHandler(data, response, error);
        }
    };
    
    return [session gleap_dataTaskWithRequest:request completionHandler:wrappedCompletion];
}

@end
