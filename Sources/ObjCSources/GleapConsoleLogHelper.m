//
//  GleapConsoleLogHelper.m
//
//
//  Created by Lukas Boehler on 25.05.22.
//
//  Console logs come from three places:
//  - stdout and stderr, redirected through pipes that a background queue drains. This
//    catches print(), NSLog (which writes its message to stderr) and anything else written
//    to the standard streams. Every byte is forwarded to the original descriptor, so the
//    Xcode console and other readers keep working.
//  - the unified log (os_log / Logger, e.g. React Native's JavaScript console), read from
//    OSLogStore when a report is built. Its NSLog entries only hold "<private>", so they
//    are skipped; stderr already has them in clear text.
//  - Gleap.log(...) calls.
//

#import "GleapConsoleLogHelper.h"
#import "GleapUIHelper.h"
#import "GleapWidgetManager.h"
#import <OSLog/OSLog.h>
#import <os/lock.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static NSUInteger const kGleapMaxConsoleEntries = 500;
static NSUInteger const kGleapMaxOSLogEntries = 300;
static NSTimeInterval const kGleapOSLogLookback = 180;
static NSTimeInterval const kGleapOSLogMaxWallClock = 0.3;
static NSUInteger const kGleapMaxLogLength = 1000;
static NSUInteger const kGleapMaxErrorLogLength = 5000;
static NSUInteger const kGleapMaxPendingLineBytes = 16384;

static os_unfair_lock gleapConsoleLock = OS_UNFAIR_LOCK_INIT;

@interface GleapConsoleLogHelper ()
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *capturedLines;
@property (nonatomic, strong) dispatch_queue_t captureQueue;
@property (nonatomic, strong) NSMutableArray *captureSources;
@property (atomic, assign) BOOL streamCaptureActive;
@property (nonatomic, strong) id osLogStore;
@end

static void GleapWriteAll(int fd, const char *buffer, size_t length) {
    while (length > 0) {
        ssize_t written = write(fd, buffer, length);
        if (written < 0) {
            if (errno == EINTR) {
                continue;
            }
            return;
        }
        buffer += written;
        length -= (size_t)written;
    }
}

// Set by Xcode when it launches the app: os_log then also writes every message to stderr
// (whatever the variable's value).
static BOOL GleapOSLogMirroredToStderr(void) {
    return getenv("OS_ACTIVITY_DT_MODE") != NULL;
}

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
        self.capturedLines = [[NSMutableArray alloc] init];
        self.captureSources = [[NSMutableArray alloc] init];
        self.captureQueue = dispatch_queue_create("io.gleap.consolelog", DISPATCH_QUEUE_SERIAL);
        self.sessionStartDate = [NSDate date];
    }
    return self;
}

- (void)start {
    if (self.consoleLogDisabled) {
        return;
    }
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BOOL stdoutCaptured = [self captureFileDescriptor: STDOUT_FILENO];
        BOOL stderrCaptured = [self captureFileDescriptor: STDERR_FILENO];
        self.streamCaptureActive = stdoutCaptured || stderrCaptured;
    });
}

#pragma mark - Entries

+ (NSString *)priorityForLogLevel:(GleapLogLevel)logLevel {
    if (logLevel == WARNING) {
        return @"WARNING";
    }
    if (logLevel == ERROR) {
        return @"ERROR";
    }
    return @"INFO";
}

+ (NSDictionary *)entryWithMessage:(NSString *)message priority:(NSString *)priority date:(NSDate *)date {
    NSUInteger maxLength = [priority isEqualToString: @"ERROR"] ? kGleapMaxErrorLogLength : kGleapMaxLogLength;
    if (message.length > maxLength) {
        // Cut before the character that crosses the limit, never inside an emoji or surrogate pair.
        NSUInteger cut = [message rangeOfComposedCharacterSequenceAtIndex: maxLength].location;
        message = [[message substringToIndex: cut] stringByAppendingString: @"… [truncated]"];
    }
    return @{
        @"date": [GleapUIHelper getJSStringForNSDate: date],
        @"log": message ?: @"",
        @"priority": priority
    };
}

- (void)log:(NSString *)msg andLogLevel:(GleapLogLevel)logLevel {
    if (![msg isKindOfClass: [NSString class]] || msg.length == 0) {
        return;
    }
    NSDictionary *entry = [GleapConsoleLogHelper entryWithMessage: msg priority: [GleapConsoleLogHelper priorityForLogLevel: logLevel] date: [NSDate date]];
    os_unfair_lock_lock(&gleapConsoleLock);
    [self.consoleLog addObject: entry];
    while (self.consoleLog.count > kGleapMaxConsoleEntries) {
        [self.consoleLog removeObjectAtIndex: 0];
    }
    os_unfair_lock_unlock(&gleapConsoleLock);
}

- (NSArray *)getBufferedConsoleLogs {
    os_unfair_lock_lock(&gleapConsoleLock);
    NSMutableArray *logs = [NSMutableArray arrayWithArray: self.consoleLog];
    if (!self.consoleLogDisabled) {
        [logs addObjectsFromArray: self.capturedLines];
    }
    os_unfair_lock_unlock(&gleapConsoleLock);
    return [GleapConsoleLogHelper newestEntries: logs];
}

- (NSArray *)getConsoleLogs {
    if (self.consoleLogDisabled) {
        return [self getBufferedConsoleLogs];
    }

    os_unfair_lock_lock(&gleapConsoleLock);
    NSArray *customLogs = [self.consoleLog copy];
    NSArray *capturedLines = [self.capturedLines copy];
    os_unfair_lock_unlock(&gleapConsoleLock);

    NSMutableArray *logs = [NSMutableArray arrayWithArray: customLogs];
    NSArray *osLogEntries = @[];
    @try {
        osLogEntries = [self readOSLogEntries];
    } @catch (NSException *exception) {}

    // A message can arrive both ways, e.g. under the Xcode debugger os_log mirrors every
    // message to stderr ("[category] message"). The unified log entry wins: it carries
    // the level and the exact time.
    NSMutableIndexSet *duplicateLines = [NSMutableIndexSet indexSet];
    if (osLogEntries.count > 0 && capturedLines.count > 0) {
        NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *linesByText = [NSMutableDictionary dictionary];
        [capturedLines enumerateObjectsUsingBlock: ^(NSDictionary *line, NSUInteger index, BOOL *stop) {
            NSString *text = line[@"log"] ?: @"";
            if (linesByText[text] == nil) {
                linesByText[text] = [NSMutableArray array];
            }
            [linesByText[text] addObject: @(index)];
        }];
        BOOL mirroredToStderr = GleapOSLogMirroredToStderr();
        for (NSDictionary *entry in osLogEntries) {
            NSString *text = entry[@"log"] ?: @"";
            NSUInteger match = NSNotFound;
            for (NSNumber *index in linesByText[text]) {
                if (![duplicateLines containsIndex: index.unsignedIntegerValue]) {
                    match = index.unsignedIntegerValue;
                    break;
                }
            }
            if (match == NSNotFound && mirroredToStderr && text.length >= 8) {
                match = [capturedLines indexOfObjectPassingTest: ^BOOL(NSDictionary *line, NSUInteger index, BOOL *stop) {
                    NSString *lineText = line[@"log"];
                    return ![duplicateLines containsIndex: index] && [lineText isKindOfClass: [NSString class]] && [lineText hasSuffix: text];
                }];
            }
            if (match != NSNotFound) {
                [duplicateLines addIndex: match];
            }
        }
    }
    [capturedLines enumerateObjectsUsingBlock: ^(NSDictionary *line, NSUInteger index, BOOL *stop) {
        if (![duplicateLines containsIndex: index]) {
            [logs addObject: line];
        }
    }];
    [logs addObjectsFromArray: osLogEntries];

    return [GleapConsoleLogHelper newestEntries: logs];
}

// Chronological (ISO UTC dates sort as strings), newest kGleapMaxConsoleEntries.
+ (NSArray *)newestEntries:(NSMutableArray *)logs {
    [logs sortWithOptions: NSSortStable usingComparator: ^NSComparisonResult(NSDictionary *first, NSDictionary *second) {
        NSString *firstDate = [first[@"date"] isKindOfClass: [NSString class]] ? first[@"date"] : @"";
        NSString *secondDate = [second[@"date"] isKindOfClass: [NSString class]] ? second[@"date"] : @"";
        return [firstDate compare: secondDate];
    }];
    if (logs.count > kGleapMaxConsoleEntries) {
        return [logs subarrayWithRange: NSMakeRange(logs.count - kGleapMaxConsoleEntries, kGleapMaxConsoleEntries)];
    }
    return [logs copy];
}

#pragma mark - Unified log

/*
 The newest os_log entries of this process from the last few minutes. OSLogStore ignores
 the reverse option, so the enumeration runs forward from a recent position and keeps the
 last entries it sees.
 */
- (NSArray *)readOSLogEntries {
    if (@available(iOS 15.0, *)) {
        NSError *error = nil;
        OSLogStore *store = self.osLogStore;
        if (store == nil) {
            store = [OSLogStore storeWithScope: OSLogStoreCurrentProcessIdentifier error: &error];
            if (store == nil || error != nil) {
                return @[];
            }
            self.osLogStore = store;
        }

        NSDate *from = [NSDate dateWithTimeIntervalSinceNow: -kGleapOSLogLookback];
        if ([from compare: self.sessionStartDate] == NSOrderedAscending) {
            from = self.sessionStartDate;
        }
        OSLogPosition *position = [store positionWithDate: from];
        NSPredicate *predicate = [NSPredicate predicateWithFormat: @"(subsystem == NULL) OR NOT (subsystem BEGINSWITH 'com.apple.')"];
        OSLogEnumerator *enumerator = [store entriesEnumeratorWithOptions: 0 position: position predicate: predicate error: &error];
        if (enumerator == nil || error != nil) {
            return @[];
        }

        BOOL skipNSLog = self.streamCaptureActive;
        NSDate *startTime = [NSDate date];
        NSMutableArray *entries = [NSMutableArray arrayWithCapacity: kGleapMaxOSLogEntries + 1];
        for (OSLogEntry *entry in enumerator) {
            if (-[startTime timeIntervalSinceNow] > kGleapOSLogMaxWallClock) {
                break;
            }
            if (![entry isKindOfClass: [OSLogEntryLog class]]) {
                continue;
            }
            OSLogEntryLog *logEntry = (OSLogEntryLog *)entry;
            NSString *message = logEntry.composedMessage;
            if (message.length == 0 || [message isEqualToString: @"<private>"]) {
                continue;
            }
            if (skipNSLog && [logEntry.sender isEqualToString: @"Foundation"] && [logEntry.formatString isEqualToString: @"%s"]) {
                continue;
            }
            NSString *priority = (logEntry.level == OSLogEntryLogLevelError || logEntry.level == OSLogEntryLogLevelFault) ? @"ERROR" : @"INFO";
            [entries addObject: [GleapConsoleLogHelper entryWithMessage: message priority: priority date: logEntry.date]];
            if (entries.count > kGleapMaxOSLogEntries) {
                [entries removeObjectAtIndex: 0];
            }
        }
        return entries;
    }
    return @[];
}

#pragma mark - stdout / stderr

- (BOOL)captureFileDescriptor:(int)targetFd {
    int originalFd = dup(targetFd);
    if (originalFd < 0) {
        return NO;
    }
    int pipeFds[2];
    if (pipe(pipeFds) != 0) {
        close(originalFd);
        return NO;
    }
    int readFd = pipeFds[0];
    int writeFd = pipeFds[1];
    fcntl(readFd, F_SETFL, fcntl(readFd, F_GETFL) | O_NONBLOCK);
    fcntl(readFd, F_SETFD, FD_CLOEXEC);
    fcntl(writeFd, F_SETFD, FD_CLOEXEC);
    fcntl(originalFd, F_SETFD, FD_CLOEXEC);

    fflush(targetFd == STDOUT_FILENO ? stdout : stderr);
    if (dup2(writeFd, targetFd) < 0) {
        close(readFd);
        close(writeFd);
        close(originalFd);
        return NO;
    }
    close(writeFd);
    if (targetFd == STDOUT_FILENO) {
        // A pipe makes stdout fully buffered: print() lines would sit in the buffer.
        setvbuf(stdout, NULL, _IOLBF, 0);
    }

    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)readFd, 0, self.captureQueue);
    if (source == nil) {
        // Put the original descriptor back rather than leave the stream unread.
        dup2(originalFd, targetFd);
        close(readFd);
        close(originalFd);
        return NO;
    }
    NSMutableData *pendingLine = [NSMutableData data];
    __weak GleapConsoleLogHelper *weakSelf = self;
    __weak dispatch_source_t weakSource = source;
    dispatch_source_set_event_handler(source, ^{
        char buffer[16384];
        while (YES) {
            ssize_t count = read(readFd, buffer, sizeof(buffer));
            if (count > 0) {
                GleapWriteAll(originalFd, buffer, (size_t)count);
                @try {
                    [weakSelf consumeBytes: buffer length: (NSUInteger)count pendingLine: pendingLine];
                } @catch (NSException *exception) {}
            } else if (count < 0 && errno == EINTR) {
                continue;
            } else {
                if (count == 0 && weakSource != nil) {
                    // Every writer is gone (the app closed the stream): stop polling.
                    dispatch_source_cancel(weakSource);
                }
                break;
            }
        }
    });
    dispatch_resume(source);
    [self.captureSources addObject: source];
    return YES;
}

- (void)consumeBytes:(const char *)bytes length:(NSUInteger)length pendingLine:(NSMutableData *)pendingLine {
    [pendingLine appendBytes: bytes length: length];
    const char *data = pendingLine.bytes;
    NSUInteger total = pendingLine.length;
    NSUInteger lineStart = 0;
    NSMutableArray<NSData *> *lines = [NSMutableArray array];
    for (NSUInteger i = 0; i < total; i++) {
        if (data[i] == '\n') {
            [lines addObject: [NSData dataWithBytes: data + lineStart length: i - lineStart]];
            lineStart = i + 1;
        }
    }
    if (lineStart > 0) {
        [pendingLine replaceBytesInRange: NSMakeRange(0, lineStart) withBytes: NULL length: 0];
    }
    if (pendingLine.length > kGleapMaxPendingLineBytes) {
        [lines addObject: [pendingLine copy]];
        [pendingLine setLength: 0];
    }
    for (NSData *line in lines) {
        [self addCapturedLine: line];
    }
}

- (void)addCapturedLine:(NSData *)lineData {
    NSString *line = [[NSString alloc] initWithData: lineData encoding: NSUTF8StringEncoding];
    if (line == nil) {
        line = [[NSString alloc] initWithData: lineData encoding: NSISOLatin1StringEncoding];
    }
    line = [GleapConsoleLogHelper stripLogPrefix: line];
    if (line.length == 0 || [[line stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) {
        return;
    }

    // The SDK's own output while the widget is open is not part of the app's story.
    if ([[GleapWidgetManager sharedInstance] isOpened]) {
        return;
    }

    NSDictionary *entry = [GleapConsoleLogHelper entryWithMessage: line priority: @"INFO" date: [NSDate date]];
    os_unfair_lock_lock(&gleapConsoleLock);
    [self.capturedLines addObject: entry];
    while (self.capturedLines.count > kGleapMaxConsoleEntries) {
        [self.capturedLines removeObjectAtIndex: 0];
    }
    os_unfair_lock_unlock(&gleapConsoleLock);
}

/*
 Removes the "2026-09-27 10:00:00.123 App[123:4567] " prefix NSLog (and os_log mirrored
 to stderr) put in front of every message, and a trailing carriage return.
 */
+ (NSString *)stripLogPrefix:(NSString *)line {
    if ([line hasSuffix: @"\r"]) {
        line = [line substringToIndex: line.length - 1];
    }
    if (line.length < 24 || [line characterAtIndex: 0] < '0' || [line characterAtIndex: 0] > '9') {
        return line;
    }
    static NSRegularExpression *prefixExpression = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        prefixExpression = [NSRegularExpression regularExpressionWithPattern: @"^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}[.,]\\d+(?:[+-]\\d{2}:?\\d{2}|Z)? .+?\\[\\d+:[0-9a-fA-Fx]+\\] " options: 0 error: nil];
    });
    NSTextCheckingResult *match = [prefixExpression firstMatchInString: line options: 0 range: NSMakeRange(0, line.length)];
    if (match != nil && match.range.location == 0) {
        return [line substringFromIndex: match.range.length];
    }
    return line;
}

@end
