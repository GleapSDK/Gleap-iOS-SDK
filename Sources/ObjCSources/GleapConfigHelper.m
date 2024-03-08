//
//  GleapConfigHelper.m
//  
//
//  Created by Lukas Boehler on 25.05.22.
//

#import "GleapConfigHelper.h"
#import "GleapCore.h"
#import "GleapActivationMethodHelper.h"
#import "GleapHttpTrafficRecorder.h"
#import "GleapReplayHelper.h"
#import "GleapWidgetManager.h"
#import "GleapUIOverlayHelper.h"
#import "GleapTranslationHelper.h"

@implementation GleapConfigHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapConfigHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapConfigHelper alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    
    self.aiTools = [[NSArray alloc] init];
    
    return self;
}

- (void)setAiTools:(NSArray<GleapAiTool *> *)aiTools {
    NSMutableArray * toolsToAdd = [[NSMutableArray alloc] init];
    
    for (int i = 0; i < aiTools.count; i++) {
        GleapAiTool * currentTool = [aiTools objectAtIndex: i];
        [toolsToAdd addObject: [currentTool toDictionary]];
    }
    
    self.internalAiTools = [toolsToAdd mutableCopy];
}

- (void)run {
    NSString *widgetConfigURL = [NSString stringWithFormat: @"%@/config/%@?lang=%@", Gleap.sharedInstance.apiUrl, Gleap.sharedInstance.token, GleapTranslationHelper.sharedInstance.language];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setHTTPMethod:@"GET"];
    [request setURL: [NSURL URLWithString: widgetConfigURL]];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:
      ^(NSData * _Nullable data,
        NSURLResponse * _Nullable response,
        NSError * _Nullable error) {
        if (error == nil) {
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSError *e = nil;
            NSData *jsonData = [responseString dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *configData = [NSJSONSerialization JSONObjectWithData:jsonData options: NSJSONReadingMutableContainers error: &e];
            if (e == nil && configData != nil) {
                [self configureGleapWithConfig: configData];
                return;
            }
        }
        
        NSLog(@"[GLEAP_SDK] Gleap auto-configuration failed. Please check your API key and internet connection.");
    }] resume];
}

- (void)configureGleapWithConfig: (NSDictionary *)data {
    NSDictionary *config = [data objectForKey: @"flowConfig"];
    NSDictionary *projectActions = [data objectForKey: @"projectActions"];
    
    if (config == nil || projectActions == nil) {
        return;
    }
    
    self.config = config;
    self.projectActions = projectActions;
    
    // Network config
    if ([config objectForKey: @"networkLogPropsToIgnore"] != nil && [[config objectForKey: @"networkLogPropsToIgnore"] isKindOfClass:[NSArray class]]) {
        GleapHttpTrafficRecorder.sharedRecorder.networkLogPropsToIgnore = [config objectForKey: @"networkLogPropsToIgnore"];
    }
    
    if ([config objectForKey: @"networkLogBlacklist"] != nil && [[config objectForKey: @"networkLogBlacklist"] isKindOfClass:[NSArray class]]) {
        GleapHttpTrafficRecorder.sharedRecorder.blacklist = [config objectForKey: @"networkLogBlacklist"];
    }
    
    if ([config objectForKey: @"enableNetworkLogs"] != nil && [[config objectForKey: @"enableNetworkLogs"] boolValue] == YES) {
        [Gleap startNetworkRecording];
    }
    
    // Replay config
    if ([config objectForKey: @"replaysInterval"] != nil) {
        int interval = [[config objectForKey: @"replaysInterval"] intValue];
        if (interval > 0) {
            [GleapReplayHelper sharedInstance].timerInterval = interval;
        }
    }
    
    if ([config objectForKey: @"enableReplays"] != nil && [[config objectForKey: @"enableReplays"] boolValue]) {
        [[GleapReplayHelper sharedInstance] start];
    } else {
        [[GleapReplayHelper sharedInstance] stop];
    }
    
    // Activation methods.
    if ([GleapActivationMethodHelper useAutoActivationMethods]) {
        NSMutableArray * activationMethods = [[NSMutableArray alloc] init];
        if ([config objectForKey: @"activationMethodShake"] != nil && [[config objectForKey: @"activationMethodShake"] boolValue] == YES) {
            [activationMethods addObject: @(SHAKE)];
        }
        if ([config objectForKey: @"activationMethodScreenshotGesture"] != nil && [[config objectForKey: @"activationMethodScreenshotGesture"] boolValue] == YES) {
            [activationMethods addObject: @(SCREENSHOT)];
        }
        [GleapActivationMethodHelper setActivationMethods: activationMethods];
    }
    
    // Update widget config
    [[GleapWidgetManager sharedInstance] sendConfigUpdate];
    
    // Set the initial feedback button status.
    if ([GleapUIOverlayHelper sharedInstance].showButtonExternalOverwrite == NO) {
        NSString *feedbackButtonPosition = [config objectForKey: @"feedbackButtonPosition"];
        if ([feedbackButtonPosition isEqualToString: @"BUTTON_NONE"]) {
            [GleapUIOverlayHelper sharedInstance].showButton = NO;
        } else {
            [GleapUIOverlayHelper sharedInstance].showButton = YES;
        }
    }
    
    // Update notification UI components.
    [GleapUIOverlayHelper updateUI];
    
    // Config loaded delegate
    if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(configLoaded:)]) {
        [Gleap.sharedInstance.delegate configLoaded: config];
    }
    
    // Send initialization done callback.
    if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(initialized)]) {
        [Gleap.sharedInstance.delegate initialized];
    }
}

- (int)getButtonX {
    if (_config != nil && [_config objectForKey: @"buttonX"] != nil) {
        return [[_config objectForKey: @"buttonX"] intValue];
    }
    
    return 20;
}

- (int)getButtonY {
    if (_config != nil && [_config objectForKey: @"buttonY"] != nil) {
        return [[_config objectForKey: @"buttonY"] intValue];
    }
    
    return 20;
}

@end
