//
//  GleapURLHandler.m
//  Gleap
//

#import "GleapURLHandler.h"
#import "GleapCore.h"
#import "GleapUIHelper.h"
#import <SafariServices/SafariServices.h>

@implementation GleapURLHandler

+ (void)handleURL:(NSString *)url {
    if (url == nil || url.length == 0) {
        return;
    }
    
    if ([url containsString:@"gleap:"]) {
        [self handleGleapLink: url];
        return;
    }
    
    if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(openExternalLink:)]) {
        [Gleap.sharedInstance.delegate openExternalLink: [NSURL URLWithString: url]];
    } else {
        [self openURLExternally: [NSURL URLWithString: url] fromViewController: [GleapUIHelper getTopMostViewController]];
    }
}

+ (void)handleGleapLink:(NSString *)href {
    @try {
        NSArray *urlParts = [href componentsSeparatedByString:@"/"];
        NSString *type = urlParts[2];

        if ([type isEqualToString:@"article"]) {
            NSString *identifier = urlParts[3];
            [Gleap openHelpCenterArticle: identifier andShowBackButton: YES];
        } else if ([type isEqualToString:@"collection"]) {
            NSString *identifier = urlParts[3];
            [Gleap openHelpCenterCollection: identifier andShowBackButton: YES];
        } else if ([type isEqualToString:@"survey"]) {
            NSString *identifier = urlParts[3];
            [Gleap showSurvey: identifier];
        } else if ([type isEqualToString:@"bot"]) {
            NSString *identifier = urlParts[3];
            [Gleap startBot: identifier showBackButton: YES];
        } else if ([type isEqualToString:@"flow"]) {
            NSString *identifier = urlParts[3];
            [Gleap startFeedbackFlow: identifier showBackButton: YES];
        } else if ([type isEqualToString:@"news"]) {
            NSString *identifier = urlParts[3];
            [Gleap openNewsArticle: identifier andShowBackButton: YES];
        } else if ([type isEqualToString:@"checklist"]) {
            NSString *identifier = urlParts[3];
            [Gleap startChecklist: identifier andShowBackButton: YES];
        } else if ([type isEqualToString:@"tour"]) {
            NSLog(@"Product tours are not available for the iOS SDK.");
        } else {
            NSLog(@"Invalid type provided in href: %@", href);
        }
    } @catch (NSException *exception) {
        NSLog(@"Failed to handle Gleap link: %@, with exception: %@", href, exception);
    }
}

+ (void)openURLExternally:(NSURL *)url fromViewController:(UIViewController *)presentingViewController {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            if ([url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"]) {
                SFSafariViewController *viewController = [[SFSafariViewController alloc] initWithURL: url];
                viewController.modalPresentationStyle = UIModalPresentationFormSheet;
                viewController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
                [presentingViewController presentViewController:viewController animated:YES completion:nil];
            } else {
                if (![url.scheme isEqualToString:@"tel"] && ![url.scheme isEqualToString:@"mailto"]) {
                    // Close Gleap when it's a deep link.
                    [Gleap close];
                }
                
                // Open deep link.
                if ([[UIApplication sharedApplication] canOpenURL: url]) {
                    [[UIApplication sharedApplication] openURL: url options:@{} completionHandler:nil];
                }
            }
        } @catch (id exp) {
            
        }
    });
}

@end
