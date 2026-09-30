//
//  GleapFeedback+Widget.m
//  Gleap
//

#import "GleapFeedback+Widget.h"
#import "GleapInternal.h"
#import "GleapScreenshotManager.h"

@implementation GleapFeedback (Widget)

+ (GleapFeedback *)feedbackFromWidgetMessage:(NSDictionary *)messageData {
    NSDictionary *formData = [messageData objectForKey: @"formData"];
    NSDictionary *action = [messageData objectForKey: @"action"];
    NSString *outboundId = [messageData objectForKey: @"outboundId"];
    
    GleapFeedback *feedback = [[GleapFeedback alloc] init];
    [feedback appendData: @{
        @"formData": formData,
    }];
    
    NSString *spamToken = [messageData objectForKey: @"spamToken"];
    if (spamToken != nil) {
        [feedback appendData: @{
            @"spamToken": spamToken,
        }];
    }
    
    // Attach exclude data.
    if (action != nil && [action objectForKey: @"excludeData"] != nil) {
        feedback.excludeData = [action objectForKey: @"excludeData"];
    }
    
    UIImage *screenshot = [GleapScreenshotManager getScreenshotToAttach];
    if (screenshot != nil) {
        feedback.screenshot = screenshot;
    }
    
    if (outboundId != nil) {
        feedback.outboundId = outboundId;
    }
    
    if (action != nil && [action objectForKey: @"feedbackType"] != nil) {
        feedback.feedbackType = [action objectForKey: @"feedbackType"];
    }
    return feedback;
}

- (NSDictionary *)widgetTicketData {
    return @{
        @"customData": GleapObjectOrNull([self.data objectForKey: @"customData"]),
        @"formData": GleapObjectOrNull([self.data objectForKey: @"formData"]),
        @"metaData": GleapObjectOrNull([self.data objectForKey: @"metaData"]),
        @"consoleLog": GleapObjectOrNull([self.data objectForKey: @"consoleLog"]),
        @"networkLogs": GleapObjectOrNull([self.data objectForKey: @"networkLogs"]),
        @"customEventLog": GleapObjectOrNull([self.data objectForKey: @"customEventLog"]),
        @"tags": GleapObjectOrNull([self.data objectForKey: @"tags"])
    };
}

@end
