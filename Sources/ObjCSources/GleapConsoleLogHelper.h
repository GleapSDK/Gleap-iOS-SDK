//
//  GleapConsoleLogHelper.h
//  
//
//  Created by Lukas Boehler on 25.05.22.
//

#import <Foundation/Foundation.h>
#import "GleapCore.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapConsoleLogHelper : NSObject

+ (instancetype)sharedInstance;

- (void)start;
- (void)log:(NSString *)msg andLogLevel:(GleapLogLevel)logLevel;
- (NSArray *)getConsoleLogs;

@property (nonatomic, assign) bool consoleLogDisabled;
@property (nonatomic, assign) bool debugConsoleLogDisabled;
@property (retain, nonatomic) NSMutableArray *consoleLog;
@property (retain, nonatomic) NSPipe *inputPipe;
@property (retain, nonatomic) NSPipe *outputPipe;

@end

NS_ASSUME_NONNULL_END
