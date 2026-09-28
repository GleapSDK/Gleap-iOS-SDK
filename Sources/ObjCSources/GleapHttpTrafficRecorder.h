//
//  GleapHttpTrafficRecorder.h
//  Gleap
//
//  Created by Lukas Boehler on 28.03.21.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
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
 The recorded logs plus the external ones (attached by a wrapper SDK or a plugin) that don't
 describe a request the recorder logged itself: same method and URL, dated within that
 request's time span.
 */
+ (NSArray *)mergeNetworkLogs:(NSArray *)networkLogs withExternalNetworkLogs:(NSArray *)externalNetworkLogs;

/*
 Drops blacklisted requests and removes ignored props and credentials (see GleapNetworkLogSanitizer).
 */
- (NSArray *)filterNetworkLogs:(NSArray *)networkLogs;

@property(nonatomic, readonly, assign) BOOL isRecording;
@property (retain, nonatomic) NSArray *networkLogPropsToIgnore;
@property (retain, nonatomic) NSArray *blacklist;

@end
