//
//  GleapFeedback+Widget.h
//  Gleap
//
//  How reports are built from the widget's messages and what the widget gets back.
//

#import "GleapFeedback.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapFeedback (Widget)

/// A report from the widget's send-feedback message: form data, spam token, excluded data,
/// the screenshot to attach, outbound id and feedback type.
+ (GleapFeedback *)feedbackFromWidgetMessage:(NSDictionary *)messageData;

/// The prepared data the widget asks for with collect-ticket-data.
- (NSDictionary *)widgetTicketData;

@end

NS_ASSUME_NONNULL_END
