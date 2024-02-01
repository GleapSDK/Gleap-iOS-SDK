//
//  GleapConsoleLogHelper.m
//  
//
//  Created by Lukas Boehler on 25.05.22.
//

#import "GleapConsoleLogHelper.h"
#import "GleapUIHelper.h"
#import "GleapWidgetManager.h"

@implementation GleapConsoleLogHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapConsoleLogHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapConsoleLogHelper alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        self.debugConsoleLogDisabled = YES;
        self.consoleLogDisabled = NO;
        self.consoleLog = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)start {
    if (self.consoleLogDisabled != YES) {
        [self openConsoleLog];
    }
}

- (NSArray *)getConsoleLogs {
    return [_consoleLog copy];
}

/**
 Returns the application type.
 */
- (NSString *)getLogLevelAsString:(GleapLogLevel)logLevel {
    NSString *logLevelString = @"INFO";
    if (logLevel == WARNING) {
        logLevelString = @"WARNING";
    } else if (logLevel == ERROR) {
        logLevelString = @"ERROR";
    }
    return logLevelString;
}

- (void)addLogWith:(NSString *)description andPriority:(NSString *)priority {
    NSString *dateString = [GleapUIHelper getJSStringForNSDate: [[NSDate alloc] init]];
    NSDictionary *log = @{ @"date": dateString, @"log": description, @"priority": priority };
    if (_consoleLog.count > 1000) {
        [_consoleLog removeObjectAtIndex: 0];
    }
    [_consoleLog addObject: log];
}

- (void)log:(NSString *)msg andLogLevel:(GleapLogLevel)logLevel {
    [self addLogWith: msg andPriority: [self getLogLevelAsString: logLevel]];
}

/*
 Starts reading the console output.
 */
- (void)openConsoleLog {
    @try
    {
        #ifdef DEBUG
        if (self.debugConsoleLogDisabled != YES) {
            _inputPipe = [[NSPipe alloc] init];
            _outputPipe = [[NSPipe alloc] init];
            
            dup2(STDOUT_FILENO, _outputPipe.fileHandleForWriting.fileDescriptor);
            dup2(_inputPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO);
            dup2(_inputPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO);
            
            [NSNotificationCenter.defaultCenter addObserver: self selector: @selector(receiveLogNotification:)  name: NSFileHandleReadCompletionNotification object: _inputPipe.fileHandleForReading];
            
            [_inputPipe.fileHandleForReading readInBackgroundAndNotify];
        }
        #else
        _inputPipe = [[NSPipe alloc] init];
        
        dup2([[_inputPipe fileHandleForWriting] fileDescriptor], STDERR_FILENO);
        
        [NSNotificationCenter.defaultCenter addObserver: self selector: @selector(receiveLogNotification:)  name: NSFileHandleReadCompletionNotification object: _inputPipe.fileHandleForReading];
        
        [_inputPipe.fileHandleForReading readInBackgroundAndNotify];
        #endif
    }
    @catch(id anException) {}
}

/*
 This callback receives all console output notifications and saves them for further use.
 */
- (void)receiveLogNotification:(NSNotification *) notification
{
    @try {
        [_inputPipe.fileHandleForReading readInBackgroundAndNotify];
        NSData *data = notification.userInfo[NSFileHandleNotificationDataItem];
        
        // Write data to output pipe
        if (_outputPipe != nil) {
            [[_outputPipe fileHandleForWriting] writeData: data];
        }
        
        // Don't process the logs when the widget is opened.
        if ([[GleapWidgetManager sharedInstance] isOpened]) {
            return;
        }
        
        NSString *consoleLogLines = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
        if (consoleLogLines != NULL) {
            
            NSError *error = nil;
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\d+-\\d+-\\d+ \\d+:\\d+:\\d+.\\d+\\+\\d+ .+\\[.+:.+\\] " options:NSRegularExpressionCaseInsensitive error:&error];
            consoleLogLines = [regex stringByReplacingMatchesInString: consoleLogLines options: 0 range:NSMakeRange(0, [consoleLogLines length]) withTemplate:@"#BBNL#"];
            
            NSArray *lines = [consoleLogLines componentsSeparatedByString: @"#BBNL#"];
            for (int i = 0; i < lines.count; i++) {
                NSString *line = [lines objectAtIndex: i];
                if (line != NULL && ![line isEqualToString: @""]) {
                    [self addLogWith: line andPriority: @"INFO"];
                }
            }
        }
    } @catch (id exp) {}
}

@end
