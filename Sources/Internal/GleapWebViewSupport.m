//
//  GleapWebViewSupport.m
//  Gleap
//

#import "GleapWebViewSupport.h"
#import <SafariServices/SafariServices.h>

@implementation GleapWebViewSupport

+ (WKWebViewConfiguration *)configurationWithMessageHandler:(id<WKScriptMessageHandler>)handler
                                                       name:(NSString *)name
                                  allowsInlineMediaPlayback:(BOOL)allowsInlineMediaPlayback {
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *userController = [[WKUserContentController alloc] init];
    [userController addScriptMessageHandler: handler name: name];
    configuration.userContentController = userController;
    if (allowsInlineMediaPlayback) {
        configuration.allowsInlineMediaPlayback = YES;
    }
    configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    return configuration;
}

+ (void)disableScrollingInWebView:(WKWebView *)webView {
    webView.scrollView.scrollEnabled = NO;
    webView.scrollView.bounces = NO;
    webView.scrollView.alwaysBounceVertical = NO;
    webView.scrollView.alwaysBounceHorizontal = NO;
    webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
}

+ (void)makeWebViewTransparent:(WKWebView *)webView {
    webView.opaque = NO;
    webView.backgroundColor = UIColor.clearColor;
    webView.scrollView.backgroundColor = UIColor.clearColor;
}

+ (void)sendMessage:(NSDictionary *)data toFunction:(NSString *)function inWebView:(WKWebView *)webView {
    @try {
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject: data options: 0 error: &error];
        if (!jsonData) {
            NSLog(@"[GLEAP_SDK] Error sending message: %@", error);
            return;
        }
        NSString *script = [NSString stringWithFormat: @"%@(%@)", function, [[NSString alloc] initWithData: jsonData encoding: NSUTF8StringEncoding]];
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                [webView evaluateJavaScript: script completionHandler: nil];
            }
            @catch(id exception) {}
        });
    }
    @catch(id exception) {}
}

+ (void)presentURLInSafari:(NSURL *)url from:(UIViewController *)presenter {
    if (url == nil) {
        return;
    }
    @try {
        SFSafariViewController *viewController = [[SFSafariViewController alloc] initWithURL: url];
        viewController.modalPresentationStyle = UIModalPresentationFormSheet;
        viewController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
        [presenter presentViewController: viewController animated: YES completion: nil];
    } @catch (NSException *exception) {
        NSLog(@"[GLEAP_SDK] Could not open URL: %@", exception);
    }
}

+ (void)openTappedLink:(NSURL *)url from:(UIViewController *)presenter {
    if ([url.absoluteString hasPrefix: @"mailto:"]) {
        if ([[UIApplication sharedApplication] canOpenURL: url]) {
            [[UIApplication sharedApplication] openURL: url options: @{} completionHandler: nil];
        }
    } else {
        [self presentURLInSafari: url from: presenter];
    }
}

@end
