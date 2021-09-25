//
//  GleapWidgetViewController.m
//  AyAyObjectiveCPort
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
@property (strong, nonatomic) WKWebView *webView;
@property (weak, nonatomic) IBOutlet UIView *loadingView;
@property (weak, nonatomic) IBOutlet UIView *webViewContainer;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *loadingActivityView;
@property (nonatomic, retain) UIImage *screenshotImage;

@end

@implementation GleapWidgetViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [_loadingView setHidden: YES];
    
    [self createWebView];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return nil;
}

- (void)closeReporting:(id)sender {
    [self dismissViewControllerAnimated: YES completion:^{
        [self onDismissCleanup];
    }];
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
            [self onDismissCleanup];
            [self openURLExternally: [NSURL URLWithString: [message.body objectForKey: @"url"]] fromViewController: presentingViewController];
        }];
    }
    
    if ([message.name isEqualToString: @"closeGleap"]) {
        [self closeReporting: nil];
    }
    
    if ([message.name isEqualToString: @"sessionReady"]) {
        [self->_loadingView setHidden: true];
    }
    
    if ([message.name isEqualToString: @"requestScreenshot"]) {
        [self injectScreenshot];
    }
    
    if ([message.name isEqualToString: @"sendFeedback"]) {
        NSDictionary *formData = [message.body objectForKey: @"formData"];
        NSString *feedbackType = [message.body objectForKey: @"type"];
        
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
    
    [self.webViewContainer addSubview: self.webView];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self.webViewContainer addConstraint:[NSLayoutConstraint constraintWithItem:self.webView attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:self.webViewContainer attribute:NSLayoutAttributeCenterY multiplier:1.0 constant:0]];
    [self.webViewContainer addConstraint:[NSLayoutConstraint constraintWithItem:self.webView attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:self.webViewContainer attribute:NSLayoutAttributeCenterX multiplier:1.0 constant:0]];
    [self.webViewContainer addConstraint:[NSLayoutConstraint constraintWithItem:self.webView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:self.webViewContainer attribute:NSLayoutAttributeHeight multiplier:1.0 constant:0]];
    [self.webViewContainer addConstraint:[NSLayoutConstraint constraintWithItem:self.webView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:self.webViewContainer attribute:NSLayoutAttributeWidth multiplier:1.0 constant:0]];
    
    NSURL * url = [NSURL URLWithString: [NSString stringWithFormat: @"%@/appwidget/%@?lang=%@&sessionId=%@&sessionHash=%@", Gleap.sharedInstance.widgetUrl, Gleap.sharedInstance.token, [Gleap.sharedInstance.language stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]], GleapSessionHelper.sharedInstance.currentSession.userId, GleapSessionHelper.sharedInstance.currentSession.userHash]];
    NSURLRequest * request = [NSURLRequest requestWithURL: url];
    [self.webView loadRequest: request];
}

- (void)injectScreenshot {
    if (self.screenshotImage == nil) {
        return;
    }
    
    @try
    {
        NSData *data = UIImagePNGRepresentation(self.screenshotImage);
        NSString *base64Data = [data base64EncodedStringWithOptions: 0];
        [self.webView evaluateJavaScript: [NSString stringWithFormat: @"Gleap.default.setScreenshot('data:image/png;base64,%@', true)", base64Data] completionHandler: nil];
    }
    @catch(id exception) {}
}

- (void)showSuccessMessage {
    @try
    {
        [self.webView evaluateJavaScript: @"Gleap.default.getInstance().showSuccessAndClose()" completionHandler: nil];
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

- (void)loadingFailed:(NSError *)error {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle: error.localizedDescription
                                                                             message: nil
                                                                      preferredStyle: UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK"
                                                        style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction *action) {
        [self dismissViewControllerAnimated: YES completion:^{
            
        }];
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
            
            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(bugSent)]) {
                [Gleap.sharedInstance.delegate bugSent];
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
                                            [self dismissViewControllerAnimated: true completion:^{
                                                [self onDismissCleanup];
                                            }];
                                        }];
            [alert addAction:yesButton];
            [self presentViewController:alert animated:YES completion:nil];
            
            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(bugSendingFailed)]) {
                [Gleap.sharedInstance.delegate bugSendingFailed];
            }
        }
    }];
}

- (void)setScreenshot:(UIImage *)image {
    self.screenshotImage = image;
}

- (void)onDismissCleanup {
    [Gleap afterBugReportCleanup];
}

@end
