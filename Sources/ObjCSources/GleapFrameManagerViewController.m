//
//  GleapWidgetViewController.m
//  Gleap
//
//  Created by Lukas on 13.01.19.
//  Copyright © 2019 Gleap. All rights reserved.
//

#import "GleapFrameManagerViewController.h"
#import "GleapCore.h"
#import "GleapReplayHelper.h"
#import "GleapSessionHelper.h"
#import "GleapTranslationHelper.h"
#import "GleapConfigHelper.h"
#import <SafariServices/SafariServices.h>
#import <math.h>
#import "GleapFeedback.h"
#import "GleapWidgetManager.h"
#import "GleapScreenshotManager.h"
#import "GleapPreFillHelper.h"

@interface GleapFrameManagerViewController ()

@property (retain, nonatomic) WKWebView *webView;
@property (retain, nonatomic) UIView *loadingView;
@property (retain, nonatomic) UIActivityIndicatorView *loadingActivityView;

@end

@implementation GleapFrameManagerViewController

- (instancetype)init
{
   self = [super initWithNibName: nil bundle:nil];
   if (self != nil)
   {
       self.connected = NO;
       self.view.backgroundColor = [UIColor colorWithRed: 0.0 green: 0.0 blue: 0.0 alpha: 0.7];
   }
   return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self createWebView];
    [self setupLoadingView];
}

- (void)setupLoadingView {
    UIView *loadingView = [UIView new];
    loadingView.backgroundColor = UIColor.clearColor;
    UIActivityIndicatorView *loadingActivityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle: UIActivityIndicatorViewStyleWhiteLarge];
    [loadingActivityView startAnimating];
    loadingActivityView.color = UIColor.whiteColor;
    
    // Loading view
    [self.view addSubview: loadingView];
    loadingView.translatesAutoresizingMaskIntoConstraints = NO;
    [self pinEdgesFrom: loadingView to: self.view];
    
    // Loading activity
    loadingActivityView.translatesAutoresizingMaskIntoConstraints = NO;
    [loadingView addSubview: loadingActivityView];
    [[loadingActivityView.centerXAnchor constraintEqualToAnchor: loadingView.centerXAnchor] setActive:YES];
    [[loadingActivityView.centerYAnchor constraintEqualToAnchor: loadingView.centerYAnchor] setActive:YES];
    
    self.loadingView = loadingView;
    self.loadingActivityView = loadingActivityView;
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return nil;
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

- (void)closeWidget: (void (^)())completion {
    self.connected = false;
    
    [[GleapWidgetManager sharedInstance] closeWidget:^{
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
    
    [self sendMessageWithData: @{
        @"name": @"session-update",
        @"data": @{
            @"sessionData": currentSession,
            @"apiUrl": Gleap.sharedInstance.apiUrl,
            @"sdkKey": Gleap.sharedInstance.token
        }
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

- (void)sendPreFillData {
    [self sendMessageWithData: @{
        @"name": @"prefill-form-data",
        @"data": [GleapPreFillHelper sharedInstance].preFillData
    }];
}

- (void)sendMessageWithData:(NSDictionary *)data {
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject: data
                                                       options: 0
                                                         error:&error];
    if (!jsonData) {
        NSLog(@"[GLEAP_SDK] Error sending message: %@", error);
    } else {
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        [self.webView evaluateJavaScript: [NSString stringWithFormat: @"sendMessage(%@)", jsonString] completionHandler: nil];
    }
}

- (void)stopLoading {
    [self.loadingView setHidden: YES];
    self.webView.alpha = 1.0;
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
            
            if (self.delegate != nil && [self.delegate respondsToSelector:@selector(connected)]) {
                [self.delegate connected];
            }
            
            [self sendConfigUpdate];
            [self sendSessionUpdate];
            [self sendPreFillData];
            [self sendScreenshotUpdate];
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
            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(customActionCalled:)]) {
                [Gleap.sharedInstance.delegate customActionCalled: (NSString *)messageData];
            }
        }
        
        if ([name isEqualToString: @"open-url"] && messageData != nil) {
            UIViewController *presentingViewController = self.presentingViewController;
            [self closeWidget:^{
                [self openURLExternally: [NSURL URLWithString: (NSString *)messageData] fromViewController: presentingViewController];
            }];
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
            
            [feedback send:^(bool success) {
                if (success) {
                    [self sendMessageWithData: @{
                        @"name": @"feedback-sent"
                    }];
                } else {
                    [self sendMessageWithData: @{
                        @"name": @"feedback-sending-failed",
                        @"data": @"Something went wrong, please try again.",
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
    NSURL *url = navigationAction.request.URL;
    [self openURLExternally: url fromViewController: self];
    return nil;
}

- (void)createWebView {
    WKWebViewConfiguration *webConfig = [[WKWebViewConfiguration alloc] init];
    WKUserContentController* userController = [[WKUserContentController alloc] init];
    [userController addScriptMessageHandler: self name: @"gleapCallback"];
    webConfig.userContentController = userController;
    
    self.webView = [[WKWebView alloc] initWithFrame:self.view.frame configuration: webConfig];
    self.webView.opaque = false;
    self.webView.backgroundColor = UIColor.clearColor;
    self.webView.scrollView.backgroundColor = UIColor.clearColor;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.alpha = 0;
    
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

- (void)addFullConstraintsFrom:(UIView *)view toOtherView:(UIView *)otherView {
    [otherView addConstraint:[NSLayoutConstraint constraintWithItem: view attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem: otherView attribute:NSLayoutAttributeCenterY multiplier:1.0 constant:0]];
    [otherView addConstraint:[NSLayoutConstraint constraintWithItem: view attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:otherView attribute:NSLayoutAttributeCenterX multiplier:1.0 constant:0]];
    [otherView addConstraint:[NSLayoutConstraint constraintWithItem: view attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem: otherView attribute:NSLayoutAttributeHeight multiplier:1.0 constant:0]];
    [otherView addConstraint:[NSLayoutConstraint constraintWithItem: view attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem: otherView attribute:NSLayoutAttributeWidth multiplier:1.0 constant:0]];
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

- (void)showSuccessMessage {
    @try
    {
        [self.webView evaluateJavaScript: @"Gleap.getInstance().showSuccessAndClose()" completionHandler: nil];
    }
    @catch(id exception) {}
}

- (NSString *)hexStringForColor:(UIColor *)color {
      const CGFloat *components = CGColorGetComponents(color.CGColor);
      CGFloat r = components[0];
      CGFloat g = components[1];
      CGFloat b = components[2];
      NSString *hexString=[NSString stringWithFormat:@"%02X%02X%02X", (int)(r * 255), (int)(g * 255), (int)(b * 255)];
      return hexString;
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

- (void)openURLExternally:(NSURL *)url fromViewController:(UIViewController *)presentingViewController {
    if ([SFSafariViewController class]) {
        SFSafariViewController *viewController = [[SFSafariViewController alloc] initWithURL: url];
        viewController.modalPresentationStyle = UIModalPresentationFormSheet;
        viewController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
        [presentingViewController presentViewController:viewController animated:YES completion:nil];
    } else {
        if ([[UIApplication sharedApplication] canOpenURL: url]) {
            [[UIApplication sharedApplication] openURL: url];
        }
    }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated) {
        NSURL *url = navigationAction.request.URL;
        if ([url.absoluteString hasPrefix: @"mailto:"]) {
            if ([[UIApplication sharedApplication] canOpenURL: url]) {
                [[UIApplication sharedApplication] openURL: url];
            }
        } else {
            [self openURLExternally: url fromViewController: self];
        }
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
    
    if (@available(iOS 11.0, *)) {
        NSLayoutConstraint *bottom =[NSLayoutConstraint
                                     constraintWithItem: subView
                                     attribute: NSLayoutAttributeBottom
                                     relatedBy: NSLayoutRelationEqual
                                     toItem: parent.safeAreaLayoutGuide
                                     attribute: NSLayoutAttributeBottom
                                     multiplier: 1.0f
                                     constant: 0.f];
        NSLayoutConstraint *top =[NSLayoutConstraint
                                  constraintWithItem: subView
                                  attribute: NSLayoutAttributeTop
                                  relatedBy: NSLayoutRelationEqual
                                  toItem: parent.safeAreaLayoutGuide
                                  attribute: NSLayoutAttributeTop
                                  multiplier: 1.0f
                                  constant: 0.f];
        [parent addConstraint: top];
        [parent addConstraint: bottom];
    } else {
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
}

@end
