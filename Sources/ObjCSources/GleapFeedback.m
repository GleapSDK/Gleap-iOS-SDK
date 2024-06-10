//
//  GleapFeedback.m
//  
//
//  Created by Lukas Boehler on 25.05.22.
//

#import "GleapFeedback.h"
#import "GleapConsoleLogHelper.h"
#import "GleapCustomDataHelper.h"
#import "GleapMetaDataHelper.h"
#import "GleapAttachmentHelper.h"
#import "GleapUploadManager.h"
#import "GleapEventLogHelper.h"
#import "GleapReplayHelper.h"
#import "GleapHttpTrafficRecorder.h"
#import "GleapCore.h"
#import "GleapSessionHelper.h"
#import "GleapExternalDataHelper.h"
#import "GleapTagHelper.h"

@implementation GleapFeedback

- (id)init {
    self = [super init];
    if (self) {
        self.excludeData = [[NSDictionary alloc] init];
        self.data = [[NSMutableDictionary alloc] initWithDictionary: @{
            @"type": @"BUG"
        }];
    }
    return self;
}

/**
 Appends data to the bug report.
 */
- (void)appendData:(NSDictionary *)data {
    [self.data addEntriesFromDictionary: data];
}

/*
 Sends a bugreport to our backend.
 */
- (void)send: (void (^)(bool success, NSDictionary *data))completion {
    [self optionallyUploadReplaySteps:^(bool success) {
        [self optionallyUploadAttachments:^(bool success) {
            [self optionallyUploadScreenshot:^(bool success) {
                [self prepareDataAndSend:^(bool success, NSDictionary *data) {
                    // Handle Gleap delegate.
                    if (success) {
                        if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(feedbackSent:)]) {
                            [Gleap.sharedInstance.delegate feedbackSent: [self getFormData]];
                        }
                    } else {
                        if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(feedbackSendingFailed:)]) {
                            [Gleap.sharedInstance.delegate feedbackSendingFailed: data];
                        }
                    }
                    
                    // Notify completion.
                    completion(success, data);
                }];
            }];
        }];
    }];
}

/*
 Optionally upload attachments (if any exist)
 */
- (void)optionallyUploadAttachments: (void (^)(bool success))completion {
    if ([self.excludeData objectForKey: @"attachments"] != nil && [[self.excludeData objectForKey: @"attachments"] boolValue] == YES) {
        completion(YES);
    } else {
        NSArray * customAttachments = [GleapAttachmentHelper sharedInstance].customAttachments;
        if (customAttachments.count > 0) {
            [GleapUploadManager uploadFiles: customAttachments forEndpoint: @"attachments" andCompletion:^(bool success, NSArray *fileUrls) {
                if (success) {
                    // Attach attachments
                    NSMutableArray *attachmentsArray = [[NSMutableArray alloc] init];
                    
                    for (int i = 0; i < customAttachments.count; i++) {
                        NSMutableDictionary *currentAttachment = [[customAttachments objectAtIndex: i] mutableCopy];
                        NSString *currentAttachmentURL = [fileUrls objectAtIndex: i];
                        [currentAttachment setObject: currentAttachmentURL forKey: @"url"];
                        [currentAttachment removeObjectForKey: @"data"];
                        [attachmentsArray addObject: currentAttachment];
                    }
                    
                    [self attachData: @{ @"attachments": attachmentsArray }];
                }
                
                completion(success);
            }];
        } else {
            completion(YES);
        }
    }
}

/*
 Optionally upload replays steps (if any exist)
 */
- (void)optionallyUploadReplaySteps: (void (^)(bool success))completion {
    if ([self.excludeData objectForKey: @"replays"] != nil && [[self.excludeData objectForKey: @"replays"] boolValue] == YES) {
        completion(YES);
    } else {
        NSArray *replaySteps = [GleapReplayHelper sharedInstance].replaySteps;
        if (replaySteps != nil && replaySteps.count > 0) {
            NSNumber *replayInterval = [NSNumber numberWithInt: GleapReplayHelper.sharedInstance.timerInterval * 1000];
            [GleapUploadManager uploadStepImages: replaySteps andCompletion:^(bool success, NSArray * _Nonnull fileUrls) {
                if (success) {
                    // Attach replay
                    [self attachData: @{ @"replay": @{
                        @"interval": replayInterval,
                        @"frames": fileUrls
                    } }];
                }
                
                completion(success);
            }];
        } else {
            completion(YES);
        }
    }
}

- (void)optionallyUploadScreenshot: (void (^)(bool success))completion {
    if (self.screenshot == nil || ([self.excludeData objectForKey: @"screenshot"] != nil && [[self.excludeData objectForKey: @"screenshot"] boolValue] == YES)) {
        completion(YES);
    } else {
        // Process with image upload
        [GleapUploadManager uploadImage: self.screenshot andCompletion:^(bool success, NSString *fileUrl) {
            if (!success) {
                return completion(false);
            }
            
            // Set screenshot url.
            NSMutableDictionary *dataToAppend = [[NSMutableDictionary alloc] init];
            [dataToAppend setValue: fileUrl forKey: @"screenshotUrl"];
            [self attachData: dataToAppend];
            
            return completion(YES);
        }];
    }
}

- (void)prepareData {
    // Fetch additional metadata.
    [self attachData: @{ @"metaData": [[GleapMetaDataHelper sharedInstance] getMetaData] }];
    
    // Attach and merge console log.
    NSMutableArray *consoleLogs = [[NSMutableArray alloc] initWithArray: [[GleapConsoleLogHelper sharedInstance] getConsoleLogs]];
    if ([[GleapExternalDataHelper sharedInstance].data objectForKey: @"consoleLog"] != nil) {
        NSArray *existingConsoleLogs = [[GleapExternalDataHelper sharedInstance].data objectForKey: @"consoleLog"];
        if (existingConsoleLogs != nil && existingConsoleLogs.count > 0) {
            [consoleLogs addObjectsFromArray: existingConsoleLogs];
        }
    }
    [self attachData: @{ @"consoleLog": consoleLogs }];
    
    // Attach custom data.
    [self attachData: @{ @"customData": [GleapCustomDataHelper getCustomData] }];
    
    // Attach ticket attributes.
    NSDictionary * existingFormData = [self.data objectForKey: @"formData"];
    if (existingFormData != nil) {
        NSMutableDictionary * formDataDict = [[GleapCustomDataHelper getTicketAttributes] mutableCopy];
        [formDataDict addEntriesFromDictionary: existingFormData];
        [self attachData: @{ @"formData": formDataDict }];
    } else {
        [self attachData: @{ @"formData": [GleapCustomDataHelper getTicketAttributes] }];
    }
    
    // Attach custom event log.
    [self attachData: @{ @"customEventLog": [[GleapEventLogHelper sharedInstance] getLogs] }];
    
    // Attach and merge network logs.
    NSMutableArray *networkLogs = [[NSMutableArray alloc] initWithArray: [[GleapHttpTrafficRecorder sharedRecorder] networkLogs]];
    if ([[GleapExternalDataHelper sharedInstance].data objectForKey: @"networkLogs"] != nil) {
        NSArray *existingNetworkLogs = [[GleapExternalDataHelper sharedInstance].data objectForKey: @"networkLogs"];
        if (existingNetworkLogs != nil && existingNetworkLogs.count > 0) {
            [networkLogs addObjectsFromArray: existingNetworkLogs];
        }
    }
    if ([networkLogs count] > 0 && [GleapHttpTrafficRecorder sharedRecorder].isRecording) {
        [self attachData: @{ @"networkLogs": [[GleapHttpTrafficRecorder sharedRecorder] filterNetworkLogs: networkLogs] }];
    }
    
    // Add outbound ID if set.
    if (self.outboundId != nil) {
        [self attachData: @{ @"outbound": self.outboundId }];
    }
    
    // Add tags.
    NSArray *tags = [GleapTagHelper getTags];
    if (tags != nil && tags.count > 0) {
        [self attachData: @{ @"tags": tags }];
    }
    
    // Set the feedback type.
    if (self.feedbackType != nil) {
        [self attachData: @{ @"type": self.feedbackType }];
    }
    
    // Exclude data that should not be sent.
    [self excludeExcludedData];
}

- (void)prepareDataAndSend: (void (^)(bool success, NSDictionary *data))completion {
    [self prepareData];
    
    // Sending report to server.
    return [self sendReportToServer:^(bool success, NSDictionary *data) {
        completion(success, data);
    }];
}

- (void)excludeExcludedData {
    if (self.excludeData == nil) {
        return;
    }
    
    for (int i = 0; i < self.excludeData.allKeys.count; i++) {
        NSString *key = [self.excludeData.allKeys objectAtIndex: i];
        if ([[self.excludeData objectForKey: key] boolValue] == YES) {
            [self.data removeObjectForKey: key];
        }
    }
}

/*
 Sends a bugreport to our backend.
 */
- (void)sendReportToServer: (void (^)(bool success, NSDictionary * data))completion {
    if (Gleap.sharedInstance.token == NULL || [Gleap.sharedInstance.token isEqualToString: @""]) {
        NSDictionary *errorInfo = @{ @"error": @"Token is null or empty" };
        return completion(false, errorInfo);
    }
    
    @try {
        // Remove invalid keys from _data recursively
        NSDictionary *cleanedData = [self dictionaryByRemovingInvalidKeysRecursivelyFromDictionary:_data];
        
        NSError *error;
        NSData *jsonBodyData = [NSJSONSerialization dataWithJSONObject: cleanedData options: kNilOptions error: &error];
        
        // Check for parsing error.
        if (error != nil) {
            NSDictionary *errorInfo = @{ @"error": @"JSON serialization error", @"details": error.localizedDescription };
            return completion(false, errorInfo);
        }
        
        NSMutableURLRequest *request = [NSMutableURLRequest new];
        request.HTTPMethod = @"POST";
        [request setURL: [NSURL URLWithString: [NSString stringWithFormat: @"%@/bugs/v2", Gleap.sharedInstance.apiUrl]]];
        [GleapSessionHelper injectSessionInRequest: request];
        [request setValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
        [request setValue: @"application/json" forHTTPHeaderField: @"Accept"];
        [request setHTTPBody: jsonBodyData];
        
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        NSURLSession *session = [NSURLSession sessionWithConfiguration:config
                                                              delegate:nil
                                                         delegateQueue:[NSOperationQueue mainQueue]];
        NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData * _Nullable data,
                                                                    NSURLResponse * _Nullable response,
                                                                    NSError * _Nullable error) {
            if (error != nil) {
                NSDictionary *errorInfo = @{ @"error": @"Network error", @"details": error.localizedDescription };
                return completion(false, errorInfo);
            }
            
            NSError *parseError = nil;
            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData: data options: 0 error:&parseError];
            if (!parseError) {
                return completion(true, responseDict);
            } else {
                NSDictionary *errorInfo = @{ @"error": @"Response parsing error", @"details": parseError.localizedDescription };
                return completion(false, errorInfo);
            }
        }];
        [task resume];
    } @catch (NSException *exp) {
        NSLog(@"[GLEAP] Failed sending feedback: %@", NSThread.callStackSymbols);
        NSDictionary *errorInfo = @{ @"error": @"Exception occurred", @"details": exp.reason };
        return completion(false, errorInfo);
    }
}

- (NSDictionary *)getFormData {
    @try {
        return @{
            @"formData": [self.data objectForKey: @"formData"],
            @"type": [self.data objectForKey: @"type"]
        };
    }
    @catch (NSException *exception) {
        return @{};
    }
}

- (void)attachData: (NSDictionary *)data {
    [self.data addEntriesFromDictionary: data];
}

// Method to remove invalid keys recursively from a dictionary
- (NSDictionary *)dictionaryByRemovingInvalidKeysRecursivelyFromDictionary:(NSDictionary *)dictionary {
    NSMutableDictionary *validDictionary = [NSMutableDictionary new];
    
    for (id key in dictionary) {
        if ([key isKindOfClass:[NSString class]]) {
            id value = dictionary[key];
            if ([value isKindOfClass:[NSDictionary class]]) {
                // Recursively clean nested dictionary
                value = [self dictionaryByRemovingInvalidKeysRecursivelyFromDictionary:value];
            } else if ([value isKindOfClass:[NSArray class]]) {
                // Recursively clean nested arrays
                value = [self arrayByRemovingInvalidKeysRecursivelyFromArray:value];
            }
            validDictionary[key] = value;
        } else {
            NSLog(@"[GLEAP] Removed invalid key: %@", key);
        }
    }
    
    return [validDictionary copy];
}

// Method to remove invalid keys recursively from an array
- (NSArray *)arrayByRemovingInvalidKeysRecursivelyFromArray:(NSArray *)array {
    NSMutableArray *validArray = [NSMutableArray new];
    
    for (id element in array) {
        if ([element isKindOfClass:[NSDictionary class]]) {
            // Recursively clean nested dictionary
            [validArray addObject:[self dictionaryByRemovingInvalidKeysRecursivelyFromDictionary:element]];
        } else if ([element isKindOfClass:[NSArray class]]) {
            // Recursively clean nested array
            [validArray addObject:[self arrayByRemovingInvalidKeysRecursivelyFromArray:element]];
        } else {
            [validArray addObject:element];
        }
    }
    
    return [validArray copy];
}

@end
