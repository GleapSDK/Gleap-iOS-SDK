//
//  GleapConsoleLogHelper.h
//
//
//  Created by Lukas Boehler on 25.05.22.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <Foundation/Foundation.h>
#import "GleapCore.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapConsoleLogHelper : NSObject

+ (instancetype)sharedInstance;

/*
 Starts capturing the app's stdout and stderr (print, NSLog, ...). No-op when the console
 log is disabled.
 */
- (void)start;
- (void)log:(NSString *)msg andLogLevel:(GleapLogLevel)logLevel;

/*
 Custom logs, captured stdout/stderr lines and the app's recent os_log / Logger messages,
 oldest first. Reads the unified log, which can take a moment: call it off the main thread.
 */
- (NSArray *)getConsoleLogs;

/*
 Custom logs and captured stdout/stderr lines only. Returns immediately.
 */
- (NSArray *)getBufferedConsoleLogs;

@property (nonatomic, assign) bool consoleLogDisabled;
// Deprecated: console output is captured in every build configuration.
@property (nonatomic, assign) bool debugConsoleLogDisabled;
@property (retain, nonatomic) NSMutableArray *consoleLog;
@property (nonatomic, strong) NSDate *sessionStartDate;

@end

NS_ASSUME_NONNULL_END
