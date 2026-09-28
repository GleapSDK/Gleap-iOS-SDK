//
//  GleapFrameManagerViewController.m
//  Gleap
//
//  Created by Lukas on 13.01.19.
//  Copyright © 2019 Gleap. All rights reserved.
//

#import "GleapFrameManagerViewController.h"
#import "GleapInternal.h"
#import "GleapWebViewSupport.h"
#import "GleapWidgetLoadingView.h"
#import "GleapCore.h"
#import "GleapReplayHelper.h"
#import "GleapSessionHelper.h"
#import "GleapTranslationHelper.h"
#import "GleapConfigHelper.h"
#import "GleapFeedback.h"
#import "GleapWidgetManager.h"
#import "GleapScreenshotManager.h"
#import "GleapUIHelper.h"
#import "GleapPreFillHelper.h"
#import "GleapAgentToolHelper.h"

// How long we may take to answer the widget's `collect-ticket-data` request.
// The widget drops the whole payload once its own timeout elapses, so this stays
// comfortably below it (see CommunicationManager.sendMessageWithResolver in the
// messenger).
static NSTimeInterval const kGleapCollectTicketDataDeadline = 0.4;

@interface GleapFrameManagerViewController ()

@property (retain, nonatomic) WKWebView *webView;
@property (retain, nonatomic) UIView *loadingView;
@property (retain, nonatomic) UIActivityIndicatorView *loadingActivityView;

@end

@implementation GleapFrameManagerViewController

- (id)initWithFormat:(NSString *)format
{
   self = [super initWithNibName: nil bundle:nil];
   if (self != nil)
   {
       self.connected = NO;
       self.isCardSurvey = [format isEqualToString: @"survey"];
       
       // Apply preview only if not simple survey.
       if (!self.isCardSurvey) {
           self.view.backgroundColor = [UIColor colorWithRed: 0.0 green: 0.0 blue: 0.0 alpha: 0.7];
           
           NSDictionary *config = GleapConfigHelper.sharedInstance.config;
           if (config != nil) {
               NSString *backgroundColor = [config objectForKey: @"backgroundColor"];
               if (backgroundColor != nil && backgroundColor.length > 0) {
                   self.view.backgroundColor = [GleapUIHelper colorFromHexString: backgroundColor];
               } else {
                   self.view.backgroundColor = [UIColor systemBackgroundColor];
               }
           }
       }
   }
   return self;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.userInteractionEnabled = NO;
    [self createWebView];
    [self setupLoadingView];
}

- (void)setupLoadingView {
    if (self.isCardSurvey) {
        UIView *loadingView = [UIView new];
        self.loadingView = loadingView;

        // Card surveys keep the centered spinner over a dimmed backdrop.
        UIActivityIndicatorView *loadingActivityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        [loadingActivityView startAnimating];
        loadingView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
        loadingActivityView.color = UIColor.whiteColor;

        [self.view addSubview: loadingView];
        loadingView.translatesAutoresizingMaskIntoConstraints = NO;
        [self pinEdgesFrom: loadingView to: self.view];

        loadingActivityView.translatesAutoresizingMaskIntoConstraints = NO;
        [loadingView addSubview: loadingActivityView];
        [[loadingActivityView.centerXAnchor constraintEqualToAnchor: loadingView.centerXAnchor] setActive:YES];
        [[loadingActivityView.centerYAnchor constraintEqualToAnchor: loadingView.centerYAnchor] setActive:YES];
        self.loadingActivityView = loadingActivityView;
        return;
    }

    // Add the loading view to the hierarchy FIRST so it has resolved bounds
    // before we build the background onto it.
    GleapWidgetLoadingView *loadingView = [GleapWidgetLoadingView new];
    self.loadingView = loadingView;
    [self.view addSubview: loadingView];
    loadingView.translatesAutoresizingMaskIntoConstraints = NO;
    [self pinEdgesFrom: loadingView to: self.view];

    // Widget loader: mirror the messenger's home background so the reveal is
    // seamless. No spinner — the background itself is the loading indicator
    // (matches the web SDK). Actual home entrance animations run inside the
    // webview once it boots.
    [loadingView setUpFromConfig: GleapConfigHelper.sharedInstance.config];
}

- (void)invalidateTimeout {
    if (self.timeoutTimer) {
        [self.timeoutTimer invalidate];
        self.timeoutTimer = nil;
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [self invalidateTimeout];
}

- (void)closeWidget: (void (^)(void))completion {
    self.connected = NO;
    
    [[GleapWidgetManager sharedInstance] closeWidgetWithAnimation: !self.isCardSurvey andCompletion:^{
        if (completion != nil) {
            completion();
        }
    }];
}

- (void)sendSessionUpdate {
    NSDictionary *currentSession = @{};
    if (GleapSessionHelper.sharedInstance.currentSession != nil) {
        currentSession = [GleapSessionHelper.sharedInstance.currentSession toDictionary];
    }
    
    NSMutableDictionary *sessionUpdateData = [[NSMutableDictionary alloc] initWithDictionary: @{
        @"sessionData": currentSession,
        @"apiUrl": Gleap.sharedInstance.apiUrl,
        @"sdkKey": Gleap.sharedInstance.token
    }];
    
    // Pass the realtime host (region) to the widget.
    NSString *realtimeHost = Gleap.sharedInstance.realtimeHost;
    if (realtimeHost != nil && realtimeHost.length > 0) {
        [sessionUpdateData setObject: realtimeHost forKey: @"realtimeHost"];
    }
    
    [self sendMessageWithData: @{
        @"name": @"session-update",
        @"data": sessionUpdateData
    }];
}

- (void)sendConfigUpdate {
    if (GleapConfigHelper.sharedInstance.config == nil || GleapConfigHelper.sharedInstance.projectActions == nil) {
        return;
    }
    
    [self sendMessageWithData: @{
        @"name": @"config-update",
        @"data": @{
            @"config": GleapConfigHelper.sharedInstance.config,
            @"actions": GleapConfigHelper.sharedInstance.projectActions,
            @"overrideLanguage": GleapTranslationHelper.sharedInstance.language,
            @"isApp": @(YES),
        }
    }];
}

// Full-screen presentations (iPad) extend the web view under the status bar
// and home indicator. env(safe-area-inset-*) is only available to the shell
// page, not to the messenger's iframe, and WebKit populates it late — so the
// insets the view controller knows for certain are sent explicitly. The
// messenger pads its headers with the top inset (--safe-area-top). Sent on
// connect and whenever UIKit reports a change (rotation, multitasking).
- (void)sendSafeAreaInsets {
    UIEdgeInsets insets = self.view.safeAreaInsets;
    [self sendMessageWithData: @{
        @"name": @"safe-area-update",
        @"data": @{
            @"top": @(MAX(0, insets.top)),
            @"right": @(MAX(0, insets.right)),
            @"bottom": @(MAX(0, insets.bottom)),
            @"left": @(MAX(0, insets.left)),
        }
    }];
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    if (self.connected) {
        [self sendSafeAreaInsets];
    }
}

- (void)sendPreFillData {
    [self sendMessageWithData: @{
        @"name": @"prefill-form-data",
        @"data": [GleapPreFillHelper sharedInstance].preFillData
    }];
}

- (void)sendMessageWithData:(NSDictionary *)data {
    [GleapWebViewSupport sendMessage: data toFunction: @"sendMessage" inWebView: self.webView];
}

- (void)stopLoading {
    self.view.userInteractionEnabled = YES;

    // Cross-fade: the loading background (showing the same colors/image) fades
    // out as the webview fades in, so the hand-off reads as continuous. The
    // messenger's own home entrance animations then play inside the webview.
    if (self.loadingView != nil && !self.loadingView.hidden) {
        UIView *loadingView = self.loadingView;
        [UIView animateWithDuration: 0.3 delay: 0.0 options: UIViewAnimationOptionCurveEaseInOut animations:^{
            self.webView.alpha = 1.0;
            loadingView.alpha = 0.0;
        } completion:^(BOOL finished) {
            [loadingView setHidden: YES];
        }];
    } else {
        self.webView.alpha = 1.0;
    }
}

- (void)sendWidgetStatusUpdate {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try
        {
            [self sendMessageWithData: @{
                @"name": @"widget-status-update",
                @"data": @{
                    @"isWidgetOpen": @(YES)
                }
            }];
        }
        @catch(id exception) {}
    });
}

- (void)userContentController:(WKUserContentController*)userContentController didReceiveScriptMessage:(WKScriptMessage*)message
{
    if ([message.name isEqualToString: @"gleapCallback"]) {
        NSString *name = [message.body objectForKey: @"name"];
        NSDictionary *messageData = [message.body objectForKey: @"data"];
        
        if ([name isEqualToString: @"ping"]) {
            [self invalidateTimeout];
            self.connected = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [self stopLoading];
            });
            
            [self sendWidgetStatusUpdate];
            [self sendConfigUpdate];
            [self sendSafeAreaInsets];
            [self sendSessionUpdate];
            [self sendPreFillData];
            [self sendScreenshotUpdate];
            
            if (self.delegate != nil && [self.delegate respondsToSelector:@selector(connected)]) {
                [self.delegate connected];
            }
        }
        
        if ([name isEqualToString: @"tool-execution"]) {
            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(onToolExecution:)]) {
                [Gleap.sharedInstance.delegate onToolExecution: messageData];
            }
        }

        if ([name isEqualToString: @"frontend-tool-execute"] && messageData != nil) {
            __weak typeof(self) weakSelf = self;
            [[GleapAgentToolHelper sharedInstance] executeToolWithData: messageData completion:^(NSDictionary *resultData) {
                [weakSelf sendMessageWithData: @{
                    @"name": @"frontend-tool-result",
                    @"data": resultData
                }];
            }];
        }
        
        if ([name isEqualToString: @"collect-ticket-data"]) {
            // The widget waits a fixed, short time for this reply and silently
            // creates the ticket with NO data at all when it is late — not just
            // without console logs, but without environment data, custom data and
            // tags too. So nothing here may block on slow collection: everything
            // except the console log is read from memory and is instant, and the
            // logs (OSLogStore, regularly slower than the widget will wait) are
            // collected under a deadline and dropped when they miss it.
            GleapFeedback *feedback = [[GleapFeedback alloc] init];
            __weak typeof(self) weakSelf = self;
            [feedback prepareDataWithDeadline: kGleapCollectTicketDataDeadline completion:^{
                [weakSelf sendMessageWithData: @{
                    @"name": @"collect-ticket-data",
                    @"data": @{
                        @"customData": GleapObjectOrNull([feedback.data objectForKey: @"customData"]),
                        @"formData": GleapObjectOrNull([feedback.data objectForKey: @"formData"]),
                        @"metaData": GleapObjectOrNull([feedback.data objectForKey: @"metaData"]),
                        @"consoleLog": GleapObjectOrNull([feedback.data objectForKey: @"consoleLog"]),
                        @"networkLogs": GleapObjectOrNull([feedback.data objectForKey: @"networkLogs"]),
                        @"customEventLog": GleapObjectOrNull([feedback.data objectForKey: @"customEventLog"]),
                        @"tags": GleapObjectOrNull([feedback.data objectForKey: @"tags"])
                    }
                }];
            }];
        }
        
        if ([name isEqualToString: @"cleanup-drawings"]) {
            [GleapScreenshotManager sharedInstance].updatedScreenshot = nil;
        }
        
        if ([name isEqualToString: @"close-widget"]) {
            [self closeWidget: nil];
        }
        
        if ([name isEqualToString: @"screenshot-updated"] && messageData != nil) {
            @try
            {
                NSString *screenshotBase64String = (NSString *)messageData;
                if (screenshotBase64String != nil) {
                    screenshotBase64String = [screenshotBase64String stringByReplacingOccurrencesOfString: @"data:image/png;base64," withString: @""];
                    NSData *dataEncoded = [[NSData alloc] initWithBase64EncodedString: screenshotBase64String options:0];
                    if (dataEncoded != nil) {
                        [GleapScreenshotManager sharedInstance].updatedScreenshot = [UIImage imageWithData:dataEncoded];
                    }
                }
            }
            @catch(id exception) {}
        }
        
        if ([name isEqualToString: @"run-custom-action"] && messageData != nil) {
            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(customActionCalled:withShareToken:)]) {
                NSString *shareToken = [message.body objectForKey: @"shareToken"];
                
                [Gleap.sharedInstance.delegate customActionCalled: (NSString *)messageData withShareToken: shareToken];
            }
            
            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(customActionCalled:)]) {
                [Gleap.sharedInstance.delegate customActionCalled: (NSString *)messageData];
            }
        }
        
        if ([name isEqualToString: @"open-url"] && messageData != nil) {
            if (Gleap.sharedInstance.closeWidgetOnExternalLinkOpen == YES) {
                [self closeWidget:^{
                    [Gleap handleURL: (NSString *)messageData];
                }];
            } else {
                [Gleap handleURL: (NSString *)messageData];
            }
        }
        
        if ([name isEqualToString: @"notify-event"] && messageData != nil) {
            NSString *eventType = [messageData objectForKey: @"type"];
            NSDictionary *eventData = [messageData objectForKey: @"data"];
            
            if ([eventType isEqualToString: @"flow-started"]) {
                [GleapScreenshotManager sharedInstance].updatedScreenshot = nil;
                
                if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(feedbackFlowStarted:)]) {
                    [Gleap.sharedInstance.delegate feedbackFlowStarted: eventData];
                }
            }
        }
        
        if ([name isEqualToString: @"send-feedback"] && messageData != nil) {
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
            
            [feedback send:^(bool success, NSDictionary* data) {
                if (success) {
                    [self sendMessageWithData: @{
                        @"name": @"feedback-sent",
                        @"data": data
                    }];
                    
                    @try {
                        if (outboundId != nil) {
                            [Gleap trackEvent: [NSString stringWithFormat: @"outbound-%@-submitted", outboundId] withData: formData];
                            
                            // Notify about outbound sent event.
                            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(outboundSent:)]) {
                                [Gleap.sharedInstance.delegate outboundSent: @{
                                    @"outboundId": GleapObjectOrNull(outboundId),
                                    @"outbound": GleapObjectOrNull(action),
                                    @"formData": GleapObjectOrNull(formData),
                                }];
                            }
                        }
                    } @catch (id exp) {}
                } else {
                    NSError *error;
                    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data options:0 error:&error];
                    
                    NSString *jsonString;
                    if (!jsonData) {
                        NSLog(@"Error converting data to JSON: %@", error);
                        jsonString = @"{\"error\": \"Conversion to JSON failed\"}";
                    } else {
                        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                    }

                    [self sendMessageWithData: @{
                        @"name": @"feedback-sending-failed",
                        @"data": jsonString
                    }];
                }
            }];
        }
    }
}

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler
{
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:message
                                                                             message:nil
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK"
                                                        style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction *action) {
                                                          completionHandler();
                                                      }]];
    [self presentViewController:alertController animated:YES completion:^{}];
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    [GleapWebViewSupport presentURLInSafari: navigationAction.request.URL from: self];
    return nil;
}

- (void)createWebView {
    WKWebViewConfiguration *webConfig = [GleapWebViewSupport configurationWithMessageHandler: self name: @"gleapCallback" allowsInlineMediaPlayback: NO];
    self.webView = [[WKWebView alloc] initWithFrame:self.view.frame configuration: webConfig];
    [GleapWebViewSupport makeWebViewTransparent: self.webView];
    [GleapWebViewSupport disableScrollingInWebView: self.webView];
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.allowsBackForwardNavigationGestures = NO;
    
    [self.view addSubview: self.webView];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    [self pinEdgesFrom: self.webView to: self.view];
    
    self.timeoutTimer = [NSTimer scheduledTimerWithTimeInterval: 15
                                         target: self
                                       selector: @selector(requestTimedOut:)
                                       userInfo: nil
                                        repeats: NO];
    NSURLRequest * request = [NSURLRequest requestWithURL: [NSURL URLWithString: Gleap.sharedInstance.frameUrl]];
    [self.webView loadRequest: request];
}

- (void)sendScreenshotUpdate {
    UIImage *screenshot = [GleapScreenshotManager getScreenshot];
    if (screenshot == nil) {
        return;
    }
    
    @try
    {
        NSData *data = UIImagePNGRepresentation(screenshot);
        NSString *base64Data = [data base64EncodedStringWithOptions: 0];
        [self sendMessageWithData: @{
            @"name": @"screenshot-update",
            @"data": [NSString stringWithFormat: @"data:image/png;base64,%@", base64Data]
        }];
    }
    @catch(id exception) {}
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self loadingFailed: error];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self loadingFailed: error];
}

- (void)requestTimedOut:(id)sender {
    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(failedToConnect)]) {
        [self.delegate failedToConnect];
    }
    [self closeWidget: nil];
}

- (void)loadingFailed:(NSError *)error {
    self.view.userInteractionEnabled = YES;
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle: error.localizedDescription
                                                                             message: nil
                                                                      preferredStyle: UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK"
                                                        style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction *action) {
        [self closeWidget: nil];
    }]];
    [self presentViewController:alertController animated:YES completion:^{}];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated) {
        [GleapWebViewSupport openTappedLink: navigationAction.request.URL from: self];
        return decisionHandler(WKNavigationActionPolicyCancel);
    }
    
    return decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)pinEdgesFrom:(UIView *)subView to:(UIView *)parent {
    NSLayoutConstraint *trailing = [NSLayoutConstraint
                                    constraintWithItem: subView
                                    attribute: NSLayoutAttributeTrailing
                                    relatedBy: NSLayoutRelationEqual
                                    toItem: parent
                                    attribute: NSLayoutAttributeTrailing
                                    multiplier: 1.0f
                                    constant: 0.f];
    NSLayoutConstraint *leading = [NSLayoutConstraint
                                       constraintWithItem: subView
                                       attribute: NSLayoutAttributeLeading
                                       relatedBy: NSLayoutRelationEqual
                                       toItem: parent
                                       attribute: NSLayoutAttributeLeading
                                       multiplier: 1.0f
                                       constant: 0.f];
    [parent addConstraint: leading];
    [parent addConstraint: trailing];
    
    NSLayoutConstraint *bottom =[NSLayoutConstraint
                                 constraintWithItem: subView
                                 attribute: NSLayoutAttributeBottom
                                 relatedBy: NSLayoutRelationEqual
                                 toItem: parent
                                 attribute: NSLayoutAttributeBottom
                                 multiplier: 1.0f
                                 constant: 0.f];
    NSLayoutConstraint *top =[NSLayoutConstraint
                              constraintWithItem: subView
                              attribute: NSLayoutAttributeTop
                              relatedBy: NSLayoutRelationEqual
                              toItem: parent
                              attribute: NSLayoutAttributeTop
                              multiplier: 1.0f
                              constant: 0.f];
    [parent addConstraint: top];
    [parent addConstraint: bottom];
}

@end
