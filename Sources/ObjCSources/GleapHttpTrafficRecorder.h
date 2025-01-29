//
//  GleapNetworkLogger.h
//  Gleap
//
//  Created by Lukas Boehler on 28.03.21.
//

#import <Foundation/Foundation.h>

@interface GleapHttpTrafficRecorder : NSObject

+ (instancetype)sharedRecorder;

- (BOOL)startRecording;
- (BOOL)startRecordingForSessionConfiguration:(NSURLSessionConfiguration *)sessionConfig;
- (void)stopRecording;
- (NSArray *)networkLogs;
- (void)clearLogs;
- (void)setMaxRequests:(int)maxRequests;
- (NSArray *)filterNetworkLogs:(NSArray *)networkLogs;

@property(nonatomic, readonly, assign) BOOL isRecording;
@property (retain, nonatomic) NSArray *networkLogPropsToIgnore;
@property (retain, nonatomic) NSArray *blacklist;

@end
