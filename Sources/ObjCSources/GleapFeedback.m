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
#import "GleapLogHelper.h"

@implementation GleapFeedback

- (void)init {
    self.excludeData = [[NSDictionary alloc] init];
    self.data = [[NSMutableDictionary alloc] init];
}

/*
 Sends a bugreport to our backend.
 */
- (void)send: (void (^)(bool success))completion {
    [self optionallyUploadReplaySteps:^(bool success) {
        [self optionallyUploadAttachments:^(bool success) {
            [self uploadScreenshotAndSendBugReport:^(bool success) {
                [self prepareScreenshotDataAndSend:^(bool success) {
                    completion(success);
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
        NSNumber *replayInterval = [NSNumber numberWithInt: self.replayInterval * 1000];
        if (self.replaysEnabled) {
            [[Gleap sharedInstance] uploadStepImages: [GleapReplayHelper sharedInstance].replaySteps andCompletion:^(bool success, NSArray * _Nonnull fileUrls) {
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

- (void)uploadScreenshotAndSendBugReport: (void (^)(bool success))completion {
    if ([self.excludeData objectForKey: @"replays"] != nil && [[self.excludeData objectForKey: @"replays"] boolValue] == YES) {
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

- (void)prepareScreenshotDataAndSend: (void (^)(bool success))completion {
    // Fetch additional metadata.
    [self attachData: @{ @"metaData": [[GleapMetaDataHelper sharedInstance] getMetaData] }];
    
    // Attach and merge console log.
    NSMutableArray *consoleLogs = [[NSMutableArray alloc] initWithArray: [[GleapConsoleLogHelper sharedInstance] getConsoleLogs]];
    if ([Gleap.sharedInstance.data objectForKey: @"consoleLog"] != nil) {
        NSArray *existingConsoleLogs = [Gleap.sharedInstance.data objectForKey: @"consoleLog"];
        if (existingConsoleLogs != nil && existingConsoleLogs.count > 0) {
            [consoleLogs addObjectsFromArray: existingConsoleLogs];
        }
    }
    [self attachData: @{ @"consoleLog": consoleLogs }];
    
    // Attach custom data.
    [self attachData: @{ @"customData": [GleapCustomDataHelper getCustomData] }];
    
    // Attach custom event log.
    [self attachData: @{ @"customEventLog": [[GleapLogHelper sharedInstance] getLogs] }];
    
    // Attach and merge network logs.
    NSMutableArray *networkLogs = [[NSMutableArray alloc] initWithArray: [[GleapHttpTrafficRecorder sharedRecorder] networkLogs]];
    if ([Gleap.sharedInstance.data objectForKey: @"networkLogs"] != nil) {
        NSArray *existingNetworkLogs = [self.data objectForKey: @"networkLogs"];
        if (existingNetworkLogs != nil && existingNetworkLogs.count > 0) {
            [networkLogs addObjectsFromArray: existingNetworkLogs];
        }
    }
    if ([networkLogs count] > 0) {
        [self attachData: @{ @"networkLogs": [self filterNetworkLogs: networkLogs] }];
    }
    
    // Add outbound
    if (Gleap.sharedInstance.action != nil) {
        [self attachData: @{ @"outbound": Gleap.sharedInstance.action.outbound }];
    }
    
    [self excludeExcludedData];
    
    // Sending report to server.
    return [self sendReportToServer:^(bool success) {
        completion(success);
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
- (void)sendReportToServer: (void (^)(bool success))completion {
    if (_token == NULL || [_token isEqualToString: @""]) {
        return completion(false);
    }
    
    NSError *error;
    NSData *jsonBodyData = [NSJSONSerialization dataWithJSONObject: _data options:kNilOptions error: &error];
    
    // Check for parsing error.
    if (error != nil) {
        return completion(false);
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest new];
    request.HTTPMethod = @"POST";
    [request setURL: [NSURL URLWithString: [NSString stringWithFormat: @"%@/bugs", _apiUrl]]];
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
                                                    return completion(false);
                                                }
                                                return completion(true);
                                            }];
    [task resume];
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

@end
