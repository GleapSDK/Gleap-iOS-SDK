//
//  GleapNetworkLogger.m
//  Gleap
//
//  Created by Lukas Boehler on 28.03.21.
//

#import "GleapHttpTrafficRecorder.h"
#import "GleapCore.h"
#import "GleapUIHelper.h"
#import "GleapWidgetManager.h"

NSString * const GleapHTTPTrafficRecordingProgressRequestKey   = @"REQUEST_KEY";
NSString * const GleapHTTPTrafficRecordingProgressResponseKey  = @"RESPONSE_KEY";
NSString * const GleapHTTPTrafficRecordingProgressBodyDataKey  = @"BODY_DATA_KEY";
NSString * const GleapHTTPTrafficRecordingProgressStartDateKey  = @"REQUEST_START_DATE_KEY";
NSString * const GleapHTTPTrafficRecordingProgressErrorKey     = @"ERROR_KEY";

@interface GleapHttpTrafficRecorder()
@property(nonatomic, assign, readwrite) BOOL isRecording;
@property(nonatomic, strong) NSString *recordingPath;
@property(nonatomic, strong) NSURLSessionConfiguration *sessionConfig;
@property(nonatomic, strong) NSMutableArray *requests;
@property(nonatomic, assign) int maxRequestsInQueue;
@end

@interface GleapRecordingProtocol : NSURLProtocol @end

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

- (NSArray *)filterNetworkLogs:(NSArray *)networkLogs {
    NSMutableArray* processedNetworkLogs = [[NSMutableArray alloc] init];
    
    // Filter networklog properties.
    for (int i = 0; i < [networkLogs count]; i++) {
        NSMutableDictionary * log =  [[NSMutableDictionary alloc] initWithDictionary: [networkLogs objectAtIndex: i]];
        
        @try {
            if (self.networkLogPropsToIgnore != nil && self.networkLogPropsToIgnore.count >= 0) {
                if ([log objectForKey: @"request"] != nil) {
                    NSMutableDictionary *request = [[NSMutableDictionary alloc] initWithDictionary: [log objectForKey: @"request"]];
                    if (request != nil && [request objectForKey: @"headers"]) {
                        if ([request objectForKey: @"headers"] != nil && [[request objectForKey: @"headers"] isKindOfClass:[NSDictionary class]]) {
                            NSMutableDictionary *mutableHeaders = [[NSMutableDictionary alloc] initWithDictionary: [request objectForKey: @"headers"]];
                            [mutableHeaders removeObjectsForKeys: self.networkLogPropsToIgnore];
                            [request setObject: mutableHeaders forKey: @"headers"];
                        }
                    }
                    
                    if (request != nil && [request objectForKey: @"payload"]) {
                        if ([request objectForKey: @"payload"] != nil) {
                            NSError *jsonError;
                            NSMutableDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:[[request objectForKey: @"payload"] dataUsingEncoding:NSUTF8StringEncoding]  options: NSJSONReadingMutableContainers error:&jsonError];
                            if (jsonError == nil && jsonObject != nil) {
                                if ([jsonObject isKindOfClass:[NSDictionary class]]) {
                                    [jsonObject removeObjectsForKeys: self.networkLogPropsToIgnore];
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
                                [jsonObject removeObjectsForKeys: self.networkLogPropsToIgnore];
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
        NSString *logUrl = [log objectForKey: @"url"];
        BOOL shouldAddLog = YES;
        if (logUrl != nil) {
            for (int i = 0; i < self.blacklist.count; i++) {
                NSString *currentBlacklistItem = [self.blacklist objectAtIndex: i];
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

- (void)setMaxRequests:(int)maxRequests {
    self.maxRequestsInQueue = maxRequests;
}

- (void)clearLogs {
    [self.requests removeAllObjects];
}

- (NSArray *)networkLogs {
    return [self.requests copy];
}

- (BOOL)startRecording{
    return [self startRecordingForSessionConfiguration: nil];
}

- (BOOL)startRecordingForSessionConfiguration:(NSURLSessionConfiguration *)sessionConfig {
    if (sessionConfig) {
        self.sessionConfig = sessionConfig;
        NSMutableOrderedSet *mutableProtocols = [[NSMutableOrderedSet alloc] initWithArray:sessionConfig.protocolClasses];
        [mutableProtocols insertObject:[GleapRecordingProtocol class] atIndex:0];
        sessionConfig.protocolClasses = [mutableProtocols array];
    } else {
        [NSURLProtocol registerClass: [GleapRecordingProtocol class]];
    }
    
    self.isRecording = YES;
    
    return YES;
}

- (void)stopRecording{
    if (self.isRecording){
        if (self.sessionConfig) {
            NSMutableArray *mutableProtocols = [[NSMutableArray alloc] initWithArray:self.sessionConfig.protocolClasses];
            [mutableProtocols removeObject:[GleapRecordingProtocol class]];
            self.sessionConfig.protocolClasses = mutableProtocols;
            self.sessionConfig = nil;
        } else {
            [NSURLProtocol unregisterClass:[GleapRecordingProtocol class]];
        }
    }
    
    self.isRecording = NO;
}

+ (NSString *)stringFromDictionary:(NSDictionary *)dictionary {
    if (dictionary == nil) {
        return @"{}";
    }
    
    @try {
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject: dictionary
                            options:NSJSONWritingPrettyPrinted
                            error:&error];
        NSString *jsonString;
        if (jsonData) {
            jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            return jsonString;
        } else {
            return @"{}";
        }
    }
    @catch (NSException *exception) {
        return @"{}";
    }
}

+ (NSString *)stringFrom:(NSData *)data {
    return [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
}

+ (BOOL)isTextBasedContentType:(NSString *)contentType {
    if ([contentType containsString: @"text/"]) {
        return true;
    }
    if ([contentType containsString: @"application/javascript"]) {
        return true;
    }
    if ([contentType containsString: @"application/xhtml+xml"]) {
        return true;
    }
    if ([contentType containsString: @"application/json"]) {
        return true;
    }
    if ([contentType containsString: @"application/xml"]) {
        return true;
    }
    if ([contentType containsString: @"application/x-www-form-urlencoded"]) {
        return true;
    }
    if ([contentType containsString: @"multipart/"]) {
        return true;
    }
    return false;
}

@end

#pragma mark - Private Protocol Class

static NSString * const GleapRecordingProtocolHandledKey = @"GleapRecordingProtocolHandledKey";

@interface GleapRecordingProtocol () <NSURLConnectionDelegate>

@property (nonatomic, strong) NSURLConnection *connection;
@property (nonatomic, strong) NSMutableData *mutableData;
@property (nonatomic, strong) NSURLResponse *response;
@property (nonatomic, strong) NSDate *startDate;

@end


@implementation GleapRecordingProtocol

#pragma mark - NSURLProtocol overrides

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    BOOL isHTTP = [request.URL.scheme isEqualToString:@"https"] || [request.URL.scheme isEqualToString:@"http"];
    if ([NSURLProtocol propertyForKey: GleapRecordingProtocolHandledKey inRequest:request] || !isHTTP) {
        return NO;
    }
    
    return YES;
}

+ (NSURLRequest *) canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void) startLoading {
    NSMutableURLRequest *newRequest = [self.request mutableCopy];
    [NSURLProtocol setProperty: @YES forKey: GleapRecordingProtocolHandledKey inRequest: newRequest];
    
    self.startDate = [NSDate date];
    self.connection = [NSURLConnection connectionWithRequest:newRequest delegate:self];
}

- (void) stopLoading {
    [self.connection cancel];
    self.mutableData = nil;
}

#pragma mark - NSURLConnectionDelegate

- (void) connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    [self.client URLProtocol: self didReceiveResponse:response cacheStoragePolicy: NSURLCacheStorageNotAllowed];
    
    self.response = response;
    self.mutableData = [[NSMutableData alloc] init];
}

- (void) connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.client URLProtocol:self didLoadData:data];
    
    [self.mutableData appendData:data];
}

- (void) connectionDidFinishLoading:(NSURLConnection *)connection {
    [self.client URLProtocolDidFinishLoading:self];
    [self.class updateRecorderProgressDelegate: true
                                      userInfo:@{GleapHTTPTrafficRecordingProgressRequestKey: self.request,
                                                 GleapHTTPTrafficRecordingProgressResponseKey: self.response,
                                                 GleapHTTPTrafficRecordingProgressBodyDataKey: self.mutableData,
                                                 GleapHTTPTrafficRecordingProgressStartDateKey: self.startDate
                                                 }];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [self.client URLProtocol:self didFailWithError:error];
    
    [self.class updateRecorderProgressDelegate: false
                                      userInfo:@{GleapHTTPTrafficRecordingProgressRequestKey: self.request,
                                                 GleapHTTPTrafficRecordingProgressErrorKey: error,
                                                 GleapHTTPTrafficRecordingProgressStartDateKey: self.startDate
                                                 }];
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    [self.client URLProtocol:self didReceiveAuthenticationChallenge:challenge];
}

- (void)connection:(NSURLConnection *)connection didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    [self.client URLProtocol:self didCancelAuthenticationChallenge:challenge];
}

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response {
    if (response != nil) {
        [[self client] URLProtocol:self wasRedirectedToRequest:request redirectResponse:response];
    }
    return request;
}

#pragma mark - Recording Progress

+ (void)updateRecorderProgressDelegate:(bool)success userInfo:(NSDictionary *)info {
    NSMutableURLRequest *urlRequest = [info objectForKey: GleapHTTPTrafficRecordingProgressRequestKey];
    NSMutableDictionary *request = [[NSMutableDictionary alloc] init];
    
    [request setValue: [urlRequest HTTPMethod] forKey: @"type"];
    [request setValue: [[urlRequest URL] absoluteString] forKey: @"url"];
    [request setValue: [GleapUIHelper getJSStringForNSDate: [[NSDate alloc] init]] forKey: @"date"];
    
    NSDate *startLoadingDate = [info objectForKey: GleapHTTPTrafficRecordingProgressStartDateKey];
    if (startLoadingDate != NULL) {
        int duration = (int)([startLoadingDate timeIntervalSinceNow] * 1000 * -1);
        [request setValue: [NSNumber numberWithDouble: duration] forKey: @"duration"];
    }
    
    if (success) {
        NSHTTPURLResponse *response = [info objectForKey: GleapHTTPTrafficRecordingProgressResponseKey];
        NSData *data = [info objectForKey: GleapHTTPTrafficRecordingProgressBodyDataKey];
        NSString *contentType = [[response allHeaderFields] objectForKey: @"Content-Type"];
        
        [request setValue: @YES forKey: @"success"];
        
        NSMutableDictionary *requestObj = [[NSMutableDictionary alloc] init];
        [requestObj setValue: [GleapHttpTrafficRecorder stringFrom: [urlRequest HTTPBody]] forKey: @"payload"];
        [requestObj setValue: [urlRequest allHTTPHeaderFields] forKey: @"headers"];
        [request setValue: requestObj forKey: @"request"];
        
        NSMutableDictionary *responseObj = [[NSMutableDictionary alloc] init];
        [responseObj setValue: [NSNumber numberWithInteger: [response statusCode]] forKey: @"status"];
        [responseObj setValue: [response allHeaderFields] forKey: @"headers"];
        [responseObj setValue: contentType forKey: @"contentType"];
        
        // Add the response body only if smaller than 0.5MB and Content-Type is valid.
        int maxBodySize = 1024 * 500;
        if ([GleapHttpTrafficRecorder isTextBasedContentType: contentType] && data.length < maxBodySize) {
            [responseObj setValue: [GleapHttpTrafficRecorder stringFrom: data] forKey: @"responseText"];
        } else {
            [responseObj setValue: @"<response_too_large>" forKey: @"responseText"];
        }
        
        [request setValue: responseObj forKey: @"response"];
    } else {
        [request setValue: @NO forKey: @"success"];
        
        NSError *error = [info objectForKey: GleapHTTPTrafficRecordingProgressErrorKey];
        
        NSMutableDictionary *responseObj = [[NSMutableDictionary alloc] init];
        [responseObj setValue: [error localizedDescription] forKey: @"errorText"];
        [request setValue: responseObj forKey: @"response"];
    }
    
    // Don't process the network logs when the widget is opened.
    if ([[GleapWidgetManager sharedInstance] isOpened]) {
        return;
    }
    
    GleapHttpTrafficRecorder *recorder = [GleapHttpTrafficRecorder sharedRecorder];
    if (recorder.requests.count >= recorder.maxRequestsInQueue) {
        [[recorder requests] removeObjectAtIndex: 0];
    }
    [[recorder requests] addObject: [request copy]];
}

@end
