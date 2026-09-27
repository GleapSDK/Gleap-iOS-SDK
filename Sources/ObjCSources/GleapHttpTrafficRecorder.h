//
//  GleapNetworkLogger.h
//  Gleap
//
//  Created by Lukas Boehler on 28.03.21.
//

#import <Foundation/Foundation.h>

@interface GleapHttpTrafficRecorder : NSObject

+ (instancetype)sharedRecorder;

/*
 Starts logging the app's HTTP(S) requests made with NSURLSession: completion handler,
 delegate (Alamofire, Apollo, ...) and Swift async/await APIs alike.
 */
- (BOOL)startRecording;

/*
 Deprecated: every NSURLSession is logged once recording runs; the configuration is ignored.
 */
- (BOOL)startRecordingForSessionConfiguration:(NSURLSessionConfiguration *)sessionConfig;
- (void)stopRecording;

/*
 The logged requests, oldest first, not yet sanitized.
 */
- (NSArray *)networkLogs;
- (void)clearLogs;
- (void)setMaxRequests:(int)maxRequests;

/*
 Drops blacklisted requests and removes ignored props and credentials (see GleapNetworkLogSanitizer).
 */
- (NSArray *)filterNetworkLogs:(NSArray *)networkLogs;

@property(nonatomic, readonly, assign) BOOL isRecording;
@property (retain, nonatomic) NSArray *networkLogPropsToIgnore;
@property (retain, nonatomic) NSArray *blacklist;

@end
