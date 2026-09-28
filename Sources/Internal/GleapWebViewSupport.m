//
//  GleapWebViewSupport.m
//  Gleap
//

#import "GleapWebViewSupport.h"
#import <SafariServices/SafariServices.h>

// WKUserContentController keeps its message handlers strongly, and the owner of a web view keeps
// the web view and with it the controller. Registering the owner itself made a cycle that kept
// every closed widget, banner and modal (and its web view) alive; this proxy forwards the
// messages without keeping the owner.
GLEAP_INTERNAL
@interface GleapWeakScriptMessageHandler : NSObject <WKScriptMessageHandler>
@property (nonatomic, weak, nullable) id<WKScriptMessageHandler> handler;
@end

@implementation GleapWeakScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    [self.handler userContentController: userContentController didReceiveScriptMessage: message];
}

@end

@implementation GleapWebViewSupport

+ (WKWebViewConfiguration *)configurationWithMessageHandler:(id<WKScriptMessageHandler>)handler
                                                       name:(NSString *)name
                                  allowsInlineMediaPlayback:(BOOL)allowsInlineMediaPlayback {
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *userController = [[WKUserContentController alloc] init];
    GleapWeakScriptMessageHandler *proxy = [[GleapWeakScriptMessageHandler alloc] init];
    proxy.handler = handler;
    [userController addScriptMessageHandler: proxy name: name];
    configuration.userContentController = userController;
    if (allowsInlineMediaPlayback) {
        configuration.allowsInlineMediaPlayback = YES;
    }
    configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    return configuration;
}

+ (void)removeMessageHandlerNamed:(NSString *)name fromWebView:(WKWebView *)webView {
    [webView.configuration.userContentController removeScriptMessageHandlerForName: name];
}

+ (BOOL)isTrustedMessage:(WKScriptMessage *)message forPageURL:(NSString *)pageURL {
    WKFrameInfo *frame = message.frameInfo;
    if ([self acceptsMessageFromMainFrame: frame.isMainFrame host: frame.securityOrigin.host forPageURL: pageURL]) {
        return YES;
    }
    NSLog(@"[GLEAP_SDK] Ignored the message %@ from %@ (%@).", message.name, frame.securityOrigin.host, frame.isMainFrame ? @"main frame" : @"subframe");
    return NO;
}

+ (BOOL)acceptsMessageFromMainFrame:(BOOL)isMainFrame host:(NSString *)host forPageURL:(NSString *)pageURL {
    return isMainFrame && [self isHost: host ofPageURL: pageURL];
}

+ (BOOL)isHost:(NSString *)host ofPageURL:(NSString *)pageURL {
    NSString *pageHost = pageURL != nil ? [NSURL URLWithString: pageURL].host : nil;
    return host.length > 0 && pageHost.length > 0 && [host caseInsensitiveCompare: pageHost] == NSOrderedSame;
}

+ (WKPermissionDecision)mediaCaptureDecisionForHost:(NSString *)host pageURL:(NSString *)pageURL {
    return [self isHost: host ofPageURL: pageURL] ? WKPermissionDecisionGrant : WKPermissionDecisionPrompt;
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
