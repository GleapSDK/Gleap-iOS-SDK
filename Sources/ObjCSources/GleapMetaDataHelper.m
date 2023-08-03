//
//  GleapMetaDataHelper.m
//  
//
//  Created by Lukas Boehler on 25.05.22.
//

#import "GleapMetaDataHelper.h"
#import <sys/utsname.h>
#import "GleapCore.h"
#import "GleapUIHelper.h"

@implementation GleapMetaDataHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapMetaDataHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapMetaDataHelper alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    return self;
}

- (void)startSession {
    self.sessionStart = [[NSDate alloc] init];
    self.lastScreenName = @"";
}

/*
 Returns all meta data as an NSDictionary.
 */
- (NSDictionary *)getMetaData {
    UIDevice *currentDevice = [UIDevice currentDevice];
    NSString *deviceName = currentDevice.name;
    NSString *deviceModel = [self getDeviceModelName];
    NSString *systemName = currentDevice.systemName;
    NSString *systemVersion = currentDevice.systemVersion;
    NSString *deviceIdentifier = [[currentDevice identifierForVendor] UUIDString];
    NSString *bundleId = NSBundle.mainBundle.bundleIdentifier;
    NSString *releaseVersionNumber = [NSBundle.mainBundle.infoDictionary objectForKey: @"CFBundleShortVersionString"];
    NSString *buildVersionNumber = [NSBundle.mainBundle.infoDictionary objectForKey: @"CFBundleVersion"];
    NSNumber *sessionDuration = [NSNumber numberWithDouble: [self sessionDuration]];
    NSString *preferredUserLocale = [[[NSBundle mainBundle] preferredLocalizations] firstObject];
    NSString *batteryLevel = @"Unknown";
    NSString * phoneChargingState = [self getPhoneChargingState];
    if (![phoneChargingState isEqualToString: @"Unknown"]) {
        batteryLevel = [NSString stringWithFormat:@"%.f", (float)[currentDevice batteryLevel] * 100];
    }
    NSString *lowPowerModeEnabled = [[NSProcessInfo processInfo] isLowPowerModeEnabled] ? @"true": @"false";
    NSDictionary *diskInfo = [self getDiskInfo];
    NSString *buildMode = @"RELEASE";
    #ifdef DEBUG
    buildMode = @"DEBUG";
    #endif
    
    float scaleFactor = [[UIScreen mainScreen] scale];
    CGRect screenRect = [[UIScreen mainScreen] bounds];
    CGFloat screenWidth = screenRect.size.width;
    CGFloat screenHeight = screenRect.size.height;
    
    return @{
        @"deviceName": deviceName,
        @"deviceModel": deviceModel,
        @"deviceIdentifier": deviceIdentifier,
        @"bundleID": bundleId,
        @"systemName": systemName,
        @"systemVersion": systemVersion,
        @"buildVersionNumber": buildVersionNumber,
        @"releaseVersionNumber": releaseVersionNumber,
        @"sessionDuration": sessionDuration,
        @"lastScreenName": _lastScreenName,
        @"preferredUserLocale": preferredUserLocale,
        @"sdkType": [self getApplicationTypeAsString],
        @"sdkVersion": SDK_VERSION,
        @"buildMode": buildMode,
        @"batteryLevel": batteryLevel,
        @"phoneChargingStatus": phoneChargingState,
        @"batterySaveMode": lowPowerModeEnabled,
        @"totalDiskSpace": [diskInfo objectForKey: @"totalSpace"],
        @"totalFreeDiskSpace": [diskInfo objectForKey: @"totalFreeSpace"],
        @"devicePixelRatio": @(scaleFactor),
        @"screenWidth": @(screenWidth),
        @"screenHeight": @(screenHeight)
    };
}

- (void)updateLastScreenName {
    _lastScreenName = [GleapUIHelper getTopMostViewControllerName];
}

/**
 Returns the application type.
 */
- (NSString *)getApplicationTypeAsString {
    NSString *applicationType = @"iOS";
    if (Gleap.sharedInstance.applicationType == FLUTTER) {
        applicationType = @"Flutter/iOS";
    } else if (Gleap.sharedInstance.applicationType == REACTNATIVE) {
        applicationType = @"ReactNative/iOS";
    } else if (Gleap.sharedInstance.applicationType == CORDOVA) {
        applicationType = @"Cordova/iOS";
    } else if (Gleap.sharedInstance.applicationType == CAPACITOR) {
        applicationType = @"Capacitor/iOS";
    }
    return applicationType;
}

/**
    Returns the device model name.
 */
- (NSString*)getDeviceModelName
{
    struct utsname systemInfo;
    uname(&systemInfo);
    return [NSString stringWithCString: systemInfo.machine
                              encoding:NSUTF8StringEncoding];
}

/*
 Returns the session's duration.
 */
- (double)sessionDuration {
    return [_sessionStart timeIntervalSinceNow] * -1.0;
}

/**
 Returns the charging status.
 */
- (NSString *)getPhoneChargingState {
    UIDevice *currentDevice = [UIDevice currentDevice];
    [currentDevice setBatteryMonitoringEnabled:YES];
    switch ([currentDevice batteryState]) {
        case UIDeviceBatteryStateCharging:
            return @"Charging";
        case UIDeviceBatteryStateFull:
            return @"Full";
        case UIDeviceBatteryStateUnplugged:
            return @"Unplugged";
        case UIDeviceBatteryStateUnknown:
            return @"Unknown";
    }
    
    return @"Unknown";
}

/**
 Returns the disc capacities.
 */
- (NSDictionary *)getDiskInfo {
    NSString* totalSpace = @"Unknown";
    NSString* totalFreeSpace = @"Unknown";
    NSError *error = nil;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSDictionary *dictionary = [[NSFileManager defaultManager] attributesOfFileSystemForPath:[paths lastObject] error: &error];
    if (dictionary) {
        NSNumber *fileSystemSizeInBytes = [dictionary objectForKey: NSFileSystemSize];
        NSNumber *freeFileSystemSizeInBytes = [dictionary objectForKey:NSFileSystemFreeSize];
        totalSpace = [NSString stringWithFormat: @"%llu", ([fileSystemSizeInBytes unsignedLongLongValue]/1000ll/1000ll/1000ll)];
        totalFreeSpace = [NSString stringWithFormat: @"%llu", ([freeFileSystemSizeInBytes unsignedLongLongValue]/1000ll/1000ll/1000ll)];
        
        if (@available(iOS 11.0, *)) {
            NSURL *homePathURL = [[NSURL alloc] initFileURLWithPath: NSHomeDirectory()];
            id resourceResults = [homePathURL resourceValuesForKeys:@[NSURLVolumeAvailableCapacityForImportantUsageKey] error:nil];
            if (resourceResults[NSURLVolumeAvailableCapacityForImportantUsageKey] != nil) {
                totalFreeSpace = [NSString stringWithFormat: @"%lld", ([resourceResults[NSURLVolumeAvailableCapacityForImportantUsageKey] longLongValue] / 1024ll / 1024ll / 1024ll)];
            }
        }
    }
    
    return @{
        @"totalSpace": totalSpace,
        @"totalFreeSpace": totalFreeSpace,
    };
}

@end
