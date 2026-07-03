//
//  GleapAgentToolHelper.h
//
//
//  Created by Lukas Boehler on 03.07.26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^GleapAgentToolCompletion)(id _Nullable result);
typedef void (^GleapAgentToolHandler)(NSDictionary * _Nonnull params, GleapAgentToolCompletion _Nonnull completion);

@interface GleapAgentToolHelper : NSObject

+ (instancetype)sharedInstance;

/*
 Registers the handler for a dashboard-defined Frontend tool. The handler is
 invoked on the main queue with the tool parameters and must call the
 completion block exactly once with the result (NSString or a JSON object).
 */
- (void)registerAgentTool:(NSString *)name handler:(GleapAgentToolHandler)handler;

/*
 Executes a tool for a frontend-tool-execute message. Always calls the
 completion with a result payload for frontend-tool-result — missing handlers
 and thrown exceptions become error messages for the AI. Deduped by
 toolCallId: duplicate requests while running are dropped, requests for an
 already completed toolCallId replay the stored result.
 */
- (void)executeToolWithData:(NSDictionary *)data completion:(void (^)(NSDictionary *resultData))completion;

/*
 Clears in-flight and completed execution state. Called when the widget closes
 so stale results never leak into the next widget session.
 */
- (void)clearExecutionState;

@end

NS_ASSUME_NONNULL_END
