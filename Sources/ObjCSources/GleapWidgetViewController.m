//
//  GleapWidgetViewController.m
//  Gleap
//
//  Created by Lukas on 13.01.19.
//  Copyright © 2019 Gleap. All rights reserved.
//

#import "GleapWidgetViewController.h"
#import "GleapCore.h"
#import "GleapReplayHelper.h"
#import "GleapSessionHelper.h"
#import "GleapTranslationHelper.h"
#import <SafariServices/SafariServices.h>
#import <math.h>

@interface GleapWidgetViewController ()
@property (retain, nonatomic) WKWebView *webView;
@property (retain, nonatomic) UIView *loadingView;
@property (retain, nonatomic) UIActivityIndicatorView *loadingActivityView;
@property (retain, nonatomic) UIImage *screenshotImage;

@end

@implementation GleapWidgetViewController

- (instancetype)init
{
   self = [super initWithNibName: nil bundle:nil];
   if (self != nil)
   {
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
    [Gleap afterBugReportCleanup];
}

- (void)closeReporting:(id)sender {
    [self dismissViewControllerAnimated: YES completion:^{}];
}

- (void)userContentController:(WKUserContentController*)userContentController didReceiveScriptMessage:(WKScriptMessage*)message
{
    if ([message.name isEqualToString: @"customActionCalled"]) {
        if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(customActionCalled:)]) {
            [Gleap.sharedInstance.delegate customActionCalled: [message.body objectForKey: @"name"]];
        }
        [self closeReporting: nil];
    }
    
    if ([message.name isEqualToString: @"openExternalURL"]) {
        UIViewController *presentingViewController = self.presentingViewController;
        [self dismissViewControllerAnimated: YES completion:^{
            [self openURLExternally: [NSURL URLWithString: [message.body objectForKey: @"url"]] fromViewController: presentingViewController];
        }];
    }
    
    if ([message.name isEqualToString: @"closeGleap"]) {
        [self closeReporting: nil];
    }
    
    if ([message.name isEqualToString: @"sessionReady"]) {
        [self invalidateTimeout];
        [self->_loadingView setHidden: YES];
    }
    
    if ([message.name isEqualToString: @"requestScreenshot"]) {
        [self injectScreenshot];
    }
    
    if ([message.name isEqualToString: @"sendFeedback"]) {
        NSDictionary *formData = [message.body objectForKey: @"formData"];
        NSString *feedbackType = [message.body objectForKey: @"type"];
        NSDictionary *excludeData = [message.body objectForKey: @"excludeData"];
        if (excludeData != nil) {
            Gleap.sharedInstance.excludeData = excludeData;
        } else {
            Gleap.sharedInstance.excludeData = [[NSDictionary alloc] init];
        }
        
        NSMutableDictionary *dataToAppend = [[NSMutableDictionary alloc] init];
        [dataToAppend setValue: @"MEDIUM" forKey: @"priority"];
        [dataToAppend setValue: formData forKey: @"formData"];
        [dataToAppend setValue: feedbackType forKey: @"type"];
        [Gleap attachData: dataToAppend];
        
        @try
        {
            NSString *screenshotBase64String = [message.body objectForKey: @"screenshot"];
            if (screenshotBase64String != nil) {
                screenshotBase64String = [screenshotBase64String stringByReplacingOccurrencesOfString: @"data:image/png;base64," withString: @""];
                NSData *dataEncoded = [[NSData alloc] initWithBase64EncodedString: screenshotBase64String options:0];
                if (dataEncoded != nil) {
                    self.screenshotImage = [UIImage imageWithData:dataEncoded];
                    [Gleap attachScreenshot: self.screenshotImage];
                }
            }
        }
        @catch(id exception) {}
        
        [self sendBugReport];
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
    [userController addScriptMessageHandler: self name: @"requestScreenshot"];
    [userController addScriptMessageHandler: self name: @"sendFeedback"];
    [userController addScriptMessageHandler: self name: @"customActionCalled"];
    [userController addScriptMessageHandler: self name: @"openExternalURL"];
    [userController addScriptMessageHandler: self name: @"closeGleap"];
    [userController addScriptMessageHandler: self name: @"sessionReady"];
    webConfig.userContentController = userController;
    
    self.webView = [[WKWebView alloc] initWithFrame:self.view.frame configuration: webConfig];
    self.webView.opaque = false;
    self.webView.backgroundColor = UIColor.clearColor;
    self.webView.scrollView.backgroundColor = UIColor.clearColor;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    
    [self.view addSubview: self.webView];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    [self pinEdgesFrom: self.webView to: self.view];
    
    self.timeoutTimer = [NSTimer scheduledTimerWithTimeInterval: 15
                                         target: self
                                       selector: @selector(requestTimedOut:)
                                       userInfo: nil
                                        repeats: NO];
    
    NSURL * url = [NSURL URLWithString: [NSString stringWithFormat: @"%@/appwidget/%@?lang=%@&gleapId=%@&gleapHash=%@&startFlow=%@", Gleap.sharedInstance.widgetUrl, Gleap.sharedInstance.token, [Gleap.sharedInstance.language stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]], GleapSessionHelper.sharedInstance.currentSession.gleapId, GleapSessionHelper.sharedInstance.currentSession.gleapHash, Gleap.sharedInstance.startFlow]];
    NSURLRequest * request = [NSURLRequest requestWithURL: url];
    [self.webView loadRequest: request];
}

- (void)addFullConstraintsFrom:(UIView *)view toOtherView:(UIView *)otherView {
    [otherView addConstraint:[NSLayoutConstraint constraintWithItem: view attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem: otherView attribute:NSLayoutAttributeCenterY multiplier:1.0 constant:0]];
    [otherView addConstraint:[NSLayoutConstraint constraintWithItem: view attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:otherView attribute:NSLayoutAttributeCenterX multiplier:1.0 constant:0]];
    [otherView addConstraint:[NSLayoutConstraint constraintWithItem: view attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem: otherView attribute:NSLayoutAttributeHeight multiplier:1.0 constant:0]];
    [otherView addConstraint:[NSLayoutConstraint constraintWithItem: view attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem: otherView attribute:NSLayoutAttributeWidth multiplier:1.0 constant:0]];
}

- (void)injectScreenshot {
    if (self.screenshotImage == nil) {
        return;
    }
    
    @try
    {
        NSData *data = UIImagePNGRepresentation(self.screenshotImage);
        NSString *base64Data = [data base64EncodedStringWithOptions: 0];
        [self.webView evaluateJavaScript: [NSString stringWithFormat: @"Gleap.setScreenshot('data:image/png;base64,%@', true)", base64Data] completionHandler: nil];
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

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [_loadingView setHidden: false];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self loadingFailed: error];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self loadingFailed: error];
}

- (void)requestTimedOut:(id)sender {
    [self closeReporting: nil];
}

- (void)loadingFailed:(NSError *)error {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle: error.localizedDescription
                                                                             message: nil
                                                                      preferredStyle: UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK"
                                                        style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction *action) {
        [self closeReporting: nil];
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

- (void)sendBugReport {
    self.navigationItem.leftBarButtonItem = false;
    self.navigationItem.rightBarButtonItem = false;
    
    [Gleap.sharedInstance sendReport:^(bool success) {
        if (success) {
            [self showSuccessMessage];
            
            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(feedbackSent:)]) {
                [Gleap.sharedInstance.delegate feedbackSent: [Gleap.sharedInstance getFormData]];
            }
        } else {
            [[self navigationController] setNavigationBarHidden: NO animated: NO];
            UIAlertController * alert = [UIAlertController
                                         alertControllerWithTitle: [GleapTranslationHelper localizedString: @"report_failed_title"]
                                         message: [GleapTranslationHelper localizedString: @"report_failed"]
                                         preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction* yesButton = [UIAlertAction
                                        actionWithTitle: [GleapTranslationHelper localizedString: @"ok"]
                                        style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction * action) {
                                            [self dismissViewControllerAnimated: true completion:^{}];
                                        }];
            [alert addAction:yesButton];
            [self presentViewController:alert animated:YES completion:nil];
            
            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(feedbackSendingFailed)]) {
                [Gleap.sharedInstance.delegate feedbackSendingFailed];
            }
        }
    }];
}

- (void)setScreenshot:(UIImage *)image {
    self.screenshotImage = image;
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
