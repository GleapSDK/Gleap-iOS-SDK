//
//  GleapAgentToolHelper.m
//
//
//  Created by Lukas Boehler on 03.07.26.
//

#import "GleapAgentToolHelper.h"

@interface GleapAgentToolHelper ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, GleapAgentToolHandler> *registeredAgentTools;
@property (nonatomic, strong) NSMutableSet<NSString *> *runningToolCallIds;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *completedToolResults;

@end

@implementation GleapAgentToolHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapAgentToolHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapAgentToolHelper alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        self.registeredAgentTools = [[NSMutableDictionary alloc] init];
        self.runningToolCallIds = [[NSMutableSet alloc] init];
        self.completedToolResults = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)registerAgentTool:(NSString *)name handler:(GleapAgentToolHandler)handler {
    if (name == nil || name.length == 0 || handler == nil) {
        return;
    }

    @synchronized (self) {
        [self.registeredAgentTools setObject: handler forKey: name];
    }
}

- (void)executeToolWithData:(NSDictionary *)data completion:(void (^)(NSDictionary *resultData))completion {
    if (completion == nil || data == nil) {
        return;
    }

    NSString *toolCallId = [[data objectForKey: @"toolCallId"] isKindOfClass: [NSString class]] ? [data objectForKey: @"toolCallId"] : nil;
    NSString *name = [[data objectForKey: @"name"] isKindOfClass: [NSString class]] ? [data objectForKey: @"name"] : nil;
    NSDictionary *params = [[data objectForKey: @"params"] isKindOfClass: [NSDictionary class]] ? [data objectForKey: @"params"] : @{};
    if (name == nil || name.length == 0) {
        return;
    }

    GleapAgentToolHandler handler = nil;
    NSDictionary *storedResult = nil;

    @synchronized (self) {
        if (toolCallId != nil) {
            storedResult = [self.completedToolResults objectForKey: toolCallId];
            if (storedResult == nil) {
                if ([self.runningToolCallIds containsObject: toolCallId]) {
                    // Already in-flight — the running execution will deliver the result.
                    return;
                }
                [self.runningToolCallIds addObject: toolCallId];
            }
        }
        handler = [self.registeredAgentTools objectForKey: name];
    }

    if (storedResult != nil) {
        completion(storedResult);
        return;
    }

    if (handler == nil) {
        NSString *result = [NSString stringWithFormat: @"No handler registered for tool '%@' in the app. Register one via Gleap.registerAgentTool('%@', handler).", name, name];
        [self finishToolCallWithId: toolCallId name: name result: result completion: completion];
        return;
    }

    __block BOOL completed = NO;
    GleapAgentToolCompletion handlerCompletion = ^(id _Nullable handlerResult) {
        @synchronized (self) {
            if (completed) {
                return;
            }
            completed = YES;
        }
        [self finishToolCallWithId: toolCallId name: name result: [GleapAgentToolHelper stringFromToolResult: handlerResult] completion: completion];
    };

    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            handler(params, handlerCompletion);
        }
        @catch (NSException *exception) {
            NSString *reason = exception.reason != nil ? exception.reason : @"unknown error";
            handlerCompletion([NSString stringWithFormat: @"Tool execution failed: %@", reason]);
        }
    });
}

- (void)finishToolCallWithId:(NSString *)toolCallId name:(NSString *)name result:(NSString *)result completion:(void (^)(NSDictionary *resultData))completion {
    NSDictionary *resultData = @{
        @"toolCallId": toolCallId != nil ? toolCallId : @"",
        @"name": name,
        @"result": result
    };

    @synchronized (self) {
        if (toolCallId != nil) {
            [self.runningToolCallIds removeObject: toolCallId];
            [self.completedToolResults setObject: resultData forKey: toolCallId];
        }
    }

    completion(resultData);
}

+ (NSString *)stringFromToolResult:(id)result {
    NSString *stringResult = nil;

    if ([result isKindOfClass: [NSString class]]) {
        stringResult = result;
    } else if (result != nil && ![result isKindOfClass: [NSNull class]]) {
        if ([NSJSONSerialization isValidJSONObject: result]) {
            NSError *error;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject: result options: 0 error: &error];
            if (jsonData != nil) {
                stringResult = [[NSString alloc] initWithData: jsonData encoding: NSUTF8StringEncoding];
            }
        }
        if (stringResult == nil) {
            stringResult = [result description];
        }
    }

    if (stringResult == nil || stringResult.length == 0) {
        return @"The action completed without returning a result.";
    }

    return stringResult;
}

- (void)clearExecutionState {
    @synchronized (self) {
        [self.runningToolCallIds removeAllObjects];
        [self.completedToolResults removeAllObjects];
    }
}

@end
