//
//  GleapLogsBundle.m
//  Gleap
//

#import "GleapLogsBundle.h"
#import "GleapCaptureAPI.h"
#import "GleapConsoleLogHelper.h"
#import "GleapCustomDataHelper.h"
#import "GleapEventLogHelper.h"
#import "GleapExternalDataHelper.h"
#import "GleapHttpTrafficRecorder.h"
#import "GleapMetaDataHelper.h"
#import "GleapReplayHelper.h"
#import "GleapUIHelper.h"
#import "GleapUploadManager.h"
#import <zlib.h>
#import <math.h>

static NSUInteger const kGleapMaxJSONDepth = 64;
// Reading the unified log can take seconds on some devices; after this long the console log goes without it, so
// the logs arrive while the requester still waits for them.
static NSTimeInterval const kGleapUnifiedLogDeadline = 5.0;

@implementation GleapLogsBundle

#pragma mark - Include

+ (NSDictionary<NSString *, NSNumber *> *)normalizedInclude:(id)include {
    NSDictionary *source = [include isKindOfClass: [NSDictionary class]] ? include : @{};
    NSDictionary<NSString *, NSNumber *> *defaults = @{
        @"consoleLog": @YES,
        @"networkLogs": @YES,
        @"customData": @YES,
        @"metaData": @YES,
        @"customEventLog": @YES,
        @"replays": @NO,
    };
    NSMutableDictionary<NSString *, NSNumber *> *result = [NSMutableDictionary dictionary];
    [defaults enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *fallback, BOOL *stop) {
        id value = source[key];
        result[key] = [value isKindOfClass: [NSNumber class]] ? @([value boolValue]) : fallback;
    }];
    return result;
}

#pragma mark - Collecting

+ (void)collectWithInclude:(id)include windowStart:(NSDate *)windowStart windowEnd:(NSDate *)windowEnd completion:(void (^)(NSDictionary *))completion {
    NSDictionary<NSString *, NSNumber *> *collect = [self normalizedInclude: include];
    NSMutableDictionary *bundle = [NSMutableDictionary dictionary];

    // Environment data reads UIKit: main queue. Disabled env data is not collected at all, as for reports.
    @try {
        if (collect[@"metaData"].boolValue && ![GleapMetaDataHelper sharedInstance].envDataDisabled) {
            NSDictionary *metaData = [[GleapMetaDataHelper sharedInstance] getMetaData];
            if (metaData.count > 0) {
                bundle[@"metaData"] = metaData;
            }
        }
    } @catch (NSException *exception) {}

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableDictionary *collected = [NSMutableDictionary dictionary];
        @try {
            if (collect[@"consoleLog"].boolValue) {
                collected[@"consoleLog"] = [self consoleLogWithDeadline: kGleapUnifiedLogDeadline];
            }
            if (collect[@"networkLogs"].boolValue) {
                NSArray *networkLogs = [self networkLogs];
                if (networkLogs != nil) {
                    collected[@"networkLogs"] = networkLogs;
                }
            }
            if (collect[@"customData"].boolValue) {
                collected[@"customData"] = [GleapCustomDataHelper getCustomData] ?: @{};
            }
            if (collect[@"customEventLog"].boolValue) {
                collected[@"customEventLog"] = [self customEventLog];
            }
        } @catch (NSException *exception) {
            NSLog(@"[GLEAP_SDK] Collecting logs failed: %@", exception.reason);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [bundle addEntriesFromDictionary: collected];
            [self addReplay: collect[@"replays"].boolValue to: bundle completion:^{
                NSDate *now = [NSDate date];
                bundle[@"capturedAt"] = [GleapUIHelper getJSStringForNSDate: now];
                if (windowStart != nil) {
                    bundle[@"windowStart"] = [GleapUIHelper getJSStringForNSDate: windowStart];
                }
                if (windowEnd != nil) {
                    bundle[@"windowEnd"] = [GleapUIHelper getJSStringForNSDate: windowEnd];
                }
                bundle[@"platform"] = @"ios";
                bundle[@"sdkType"] = [GleapCaptureAPI sdkType];
                bundle[@"sdkVersion"] = SDK_VERSION;
                bundle[@"deviceId"] = [GleapCaptureAPI deviceId];
                completion(bundle);
            }];
        });
    });
}

// The console log of a report: custom logs, captured stdout / stderr, the unified log, and what a wrapper SDK
// attached. Off the main queue; without the unified log when that is not read within `deadline`.
+ (NSArray *)consoleLogWithDeadline:(NSTimeInterval)deadline {
    __block NSArray *fullLog = nil;
    NSObject *lock = [[NSObject alloc] init];
    dispatch_semaphore_t read = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray *logs = nil;
        @try {
            logs = [[GleapConsoleLogHelper sharedInstance] getConsoleLogs];
        } @catch (NSException *exception) {}
        @synchronized (lock) {
            fullLog = logs;
        }
        dispatch_semaphore_signal(read);
    });
    NSArray *logs = nil;
    if (dispatch_semaphore_wait(read, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(deadline * NSEC_PER_SEC))) == 0) {
        @synchronized (lock) {
            logs = fullLog;
        }
    }
    if (logs == nil) {
        logs = [[GleapConsoleLogHelper sharedInstance] getBufferedConsoleLogs];
    }
    NSMutableArray *result = [NSMutableArray arrayWithArray: logs ?: @[]];
    NSArray *external = [[GleapExternalDataHelper sharedInstance] objectForKey: @"consoleLog"];
    if ([external isKindOfClass: [NSArray class]] && external.count > 0) {
        [result addObjectsFromArray: external];
    }
    return result;
}

// The network logs of a report, sanitized; nil when none are recorded (recording off and nothing attached).
+ (NSArray *)networkLogs {
    GleapHttpTrafficRecorder *recorder = [GleapHttpTrafficRecorder sharedRecorder];
    BOOL recording = recorder.isRecording;
    NSArray *recorded = recording ? [recorder networkLogs] : @[];
    NSArray *external = [[GleapExternalDataHelper sharedInstance] objectForKey: @"networkLogs"];
    NSArray *merged = [GleapHttpTrafficRecorder mergeNetworkLogs: recorded withExternalNetworkLogs: external];
    if (merged.count == 0 && !recording) {
        return nil;
    }
    return [recorder filterNetworkLogs: merged] ?: @[];
}

+ (NSArray *)customEventLog {
    GleapEventLogHelper *helper = [GleapEventLogHelper sharedInstance];
    // The helper adds events under its own lock; copy under it.
    @synchronized (helper) {
        return [[helper getLogs] copy] ?: @[];
    }
}

// Main queue. The native replay only when asked for and replays run (the project enabled them).
+ (void)addReplay:(BOOL)requested to:(NSMutableDictionary *)bundle completion:(void (^)(void))completion {
    GleapReplayHelper *replays = [GleapReplayHelper sharedInstance];
    NSArray *steps = [replays.replaySteps copy];
    if (!requested || !replays.running || steps.count == 0) {
        completion();
        return;
    }
    NSNumber *interval = @(replays.timerInterval * 1000);
    [GleapUploadManager uploadStepImages: steps andCompletion:^(bool success, NSArray * _Nonnull fileUrls) {
        if (success && fileUrls.count > 0) {
            bundle[@"replay"] = @{ @"interval": interval, @"frames": fileUrls };
        }
        completion();
    }];
}

#pragma mark - Encoding

+ (NSData *)gzippedJSONForBundle:(NSDictionary *)bundle maxBytes:(NSUInteger)maxBytes {
    NSMutableDictionary *current = [bundle mutableCopy];
    NSArray<NSString *> *dropOrder = @[@"networkLogs", @"consoleLog", @"customEventLog"];
    NSUInteger dropped = 0;
    while (YES) {
        NSData *json = nil;
        @try {
            json = [NSJSONSerialization dataWithJSONObject: [self JSONSafeObject: current] options: 0 error: nil];
        } @catch (NSException *exception) {}
        if (json == nil) {
            return nil;
        }
        NSData *gzipped = [self gzipData: json];
        if (gzipped == nil) {
            return nil;
        }
        if (gzipped.length <= maxBytes) {
            return gzipped;
        }
        if (dropped >= dropOrder.count) {
            return nil;
        }
        [current removeObjectForKey: dropOrder[dropped]];
        dropped += 1;
    }
}

+ (id)JSONSafeObject:(id)object {
    return [self JSONSafeObject: object depth: 0];
}

+ (id)JSONSafeObject:(id)object depth:(NSUInteger)depth {
    if (object == nil || object == (id)kCFNull || depth > kGleapMaxJSONDepth) {
        return [NSNull null];
    }
    if ([object isKindOfClass: [NSString class]]) {
        return object;
    }
    if ([object isKindOfClass: [NSNumber class]]) {
        double value = [object doubleValue];
        return (isnan(value) || isinf(value)) ? [NSNull null] : object;
    }
    if ([object isKindOfClass: [NSDictionary class]]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity: [object count]];
        [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            // Like reports: entries with non-string keys are left out.
            if ([key isKindOfClass: [NSString class]]) {
                result[key] = [self JSONSafeObject: value depth: depth + 1];
            }
        }];
        return result;
    }
    if ([object isKindOfClass: [NSArray class]]) {
        NSMutableArray *result = [NSMutableArray arrayWithCapacity: [object count]];
        for (id value in (NSArray *)object) {
            [result addObject: [self JSONSafeObject: value depth: depth + 1]];
        }
        return result;
    }
    if ([object isKindOfClass: [NSDate class]]) {
        return [GleapUIHelper getJSStringForNSDate: object];
    }
    if ([object isKindOfClass: [NSURL class]]) {
        return [(NSURL *)object absoluteString] ?: [NSNull null];
    }
    if ([object isKindOfClass: [NSData class]]) {
        return [NSString stringWithFormat: @"<%lu bytes>", (unsigned long)[(NSData *)object length]];
    }
    NSString *description = [object description];
    return description != nil ? description : [NSNull null];
}

+ (NSData *)gzipData:(NSData *)data {
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    // windowBits 15 + 16: a gzip header and trailer instead of zlib's.
    if (deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        return nil;
    }
    NSMutableData *output = [NSMutableData dataWithCapacity: data.length / 4 + 64];
    uint8_t chunk[16384];
    stream.next_in = (Bytef *)data.bytes;
    stream.avail_in = (uInt)data.length;
    int status = Z_OK;
    do {
        stream.next_out = chunk;
        stream.avail_out = sizeof(chunk);
        status = deflate(&stream, Z_FINISH);
        if (status == Z_STREAM_ERROR) {
            deflateEnd(&stream);
            return nil;
        }
        [output appendBytes: chunk length: sizeof(chunk) - stream.avail_out];
    } while (stream.avail_out == 0);
    deflateEnd(&stream);
    return status == Z_STREAM_END ? output : nil;
}

@end
