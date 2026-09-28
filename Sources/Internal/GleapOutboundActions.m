//
//  GleapOutboundActions.m
//  Gleap
//

#import "GleapOutboundActions.h"
#import "GleapCore.h"

@implementation GleapOutboundActions

+ (BOOL)handlesAction:(NSString *)name {
    static NSSet *names = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = [NSSet setWithArray: @[@"start-conversation", @"open-url", @"show-form", @"show-survey",
                                       @"show-news-article", @"show-help-article", @"show-checklist"]];
    });
    return name != nil && [names containsObject: name];
}

+ (void)performAction:(NSString *)name data:(id)data {
    if ([name isEqualToString: @"start-conversation"]) {
        [Gleap startBot: [data objectForKey: @"botId"] showBackButton: YES];
    } else if ([name isEqualToString: @"open-url"]) {
        [Gleap handleURL: (NSString *)data];
    } else if ([name isEqualToString: @"show-form"]) {
        [Gleap startFeedbackFlow: [data objectForKey: @"formId"] showBackButton: YES];
    } else if ([name isEqualToString: @"show-survey"]) {
        GleapSurveyFormat format = SURVEY;
        if ([[data objectForKey: @"surveyFormat"] isEqualToString: @"survey_full"]) {
            format = SURVEY_FULL;
        }
        [Gleap showSurvey: [data objectForKey: @"formId"] andFormat: format];
    } else if ([name isEqualToString: @"show-news-article"]) {
        [Gleap openNewsArticle: [data objectForKey: @"articleId"] andShowBackButton: NO];
    } else if ([name isEqualToString: @"show-help-article"]) {
        [Gleap openHelpCenterArticle: [data objectForKey: @"articleId"] andShowBackButton: NO];
    } else if ([name isEqualToString: @"show-checklist"]) {
        [Gleap startChecklist: [data objectForKey: @"checklistId"] andShowBackButton: NO];
    }
}

+ (void)notifyCustomAction:(id)action {
    if (action != nil && ![action isKindOfClass: [NSString class]]) {
        return;
    }
    id<GleapDelegate> delegate = Gleap.sharedInstance.delegate;
    if ([delegate respondsToSelector: @selector(customActionCalled:withShareToken:)]) {
        [delegate customActionCalled: action withShareToken: nil];
    } else if ([delegate respondsToSelector: @selector(customActionCalled:)]) {
        [delegate customActionCalled: action];
    }
}

@end
