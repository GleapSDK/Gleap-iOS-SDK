//
//  GleapBanner.m
//  
//
//  Created by Lukas Boehler on 09.09.22.
//

#import "GleapBanner.h"
#import "GleapConfigHelper.h"
#import "GleapUIOverlayHelper.h"
#import "GleapUIHelper.h"
#import "GleapUIOverlayViewController.h"
#import "Gleap.h"
#import <SafariServices/SafariServices.h>
#import <math.h>

@implementation GleapBanner

- (id)initWithFrame:(CGRect)aRect
{
    if ((self = [super initWithFrame:aRect])) {
        self.alpha = 0;
        self.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return self;
}

- (void)setupWithData:(NSDictionary *)bannerData {
    self.bannerData = bannerData;
    
    self.layer.shadowRadius  = 6.0;
    self.layer.shadowColor   = [UIColor blackColor].CGColor;
    self.layer.shadowOffset  = CGSizeMake(0.0f, 0.0f);
    self.layer.shadowOpacity = 0.2;
    self.layer.masksToBounds = NO;
    self.clipsToBounds = NO;
    
    [self createWebView];
    
    NSString *format = [self.bannerData valueForKeyPath: @"format"];
    if ([format isEqualToString: @"floating"]) {
        self.backgroundColor = [UIColor clearColor];
        
        // Set rounded corners
        self.webView.layer.cornerRadius = 10.0f;
        self.webView.layer.masksToBounds = YES;
    } else {
        NSString *bannerColor = [bannerData valueForKeyPath: @"config.bannerColor"];
        if (bannerColor != nil && bannerColor.length > 0) {
            self.backgroundColor = [GleapUIHelper colorFromHexString: bannerColor];
        }
    }
}

- (void)createWebView {
    WKWebViewConfiguration *webConfig = [[WKWebViewConfiguration alloc] init];
    WKUserContentController* userController = [[WKUserContentController alloc] init];
    [userController addScriptMessageHandler: self name: @"gleapBannerCallback"];
    webConfig.userContentController = userController;
    webConfig.allowsInlineMediaPlayback = YES;
    
    self.webView = [[WKWebView alloc] initWithFrame:self.frame configuration: webConfig];
    self.webView.opaque = false;
    self.webView.backgroundColor = UIColor.clearColor;
    self.webView.scrollView.backgroundColor = UIColor.clearColor;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.scrollView.scrollEnabled = NO;
    self.webView.scrollView.bounces = NO;
    self.webView.scrollView.alwaysBounceVertical = NO;
    self.webView.scrollView.alwaysBounceHorizontal = NO;
    self.webView.allowsBackForwardNavigationGestures = NO;
    if (@available(iOS 11.0, *)) {
        [self.webView.scrollView setContentInsetAdjustmentBehavior: UIScrollViewContentInsetAdjustmentNever];
    }

    [self addSubview: self.webView];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    [self pinEdgesFrom: self.webView to: self];
    
    NSURLRequest * request = [NSURLRequest requestWithURL: [NSURL URLWithString: Gleap.sharedInstance.bannerUrl]];
    [self.webView loadRequest: request];
}

- (void)webView:(WKWebView *)webView
     requestMediaCapturePermissionForOrigin:(WKSecurityOrigin *)origin
     initiatedByFrame:(WKFrameInfo *)frame type:(WKMediaCaptureType)type
     decisionHandler:(void (^)(WKPermissionDecision decision))decisionHandler
     API_AVAILABLE(ios(15.0))
{
    decisionHandler(WKPermissionDecisionGrant);
}

- (void)sendMessageWithData:(NSDictionary *)data {
    @try {
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject: data
                                                           options: 0
                                                             error:&error];
        if (!jsonData) {
            NSLog(@"[GLEAP_SDK] Error sending message: %@", error);
        } else {
            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    [self.webView evaluateJavaScript: [NSString stringWithFormat: @"appMessage(%@)", jsonString] completionHandler: nil];
                }
                @catch(id exception) {}
            });
        }
    }
    @catch(id exception) {}
}

- (void)userContentController:(WKUserContentController*)userContentController didReceiveScriptMessage:(WKScriptMessage*)message
{
    if ([message.name isEqualToString: @"gleapBannerCallback"]) {
        NSString *name = [message.body objectForKey: @"name"];
        NSDictionary *messageData = [message.body objectForKey: @"data"];
        
        if ([name isEqualToString: @"banner-loaded"]) {
            [self sendMessageWithData: @{
                @"name": @"banner-data",
                @"data": self.bannerData
            }];
        }
        
        if ([name isEqualToString: @"banner-data-set"]) {
            // Show banner.
            [UIView animateWithDuration:0.3f animations:^{
                self.alpha = 1.0;
            } completion:^(BOOL finished) {}];
        }
        
        if ([name isEqualToString: @"banner-height"]) {
            // Update banner height.
            if (self.heightConstraint != nil) {
                self.heightConstraint.constant = [[messageData objectForKey: @"height"] floatValue];
                [self layoutIfNeeded];
            }
        }
        
        if ([name isEqualToString: @"banner-close"]) {
            [UIView animateWithDuration:0.3f animations:^{
                self.alpha = 0.0;
            } completion:^(BOOL finished) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self removeFromSuperview];
                    self.uiOverlayViewController.banner = nil;
                });
            }];
        }
        
        if ([name isEqualToString: @"start-conversation"]) {
            [Gleap startBot: [messageData objectForKey: @"botId"] showBackButton: YES];
        }
        
        if ([name isEqualToString: @"start-custom-action"]) {
            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(customActionCalled:)]) {
                [Gleap.sharedInstance.delegate customActionCalled: (NSString *)[messageData objectForKey: @"action"] withShareToken: nil];
            }
            
            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(customActionCalled:)]) {
                [Gleap.sharedInstance.delegate customActionCalled: (NSString *)messageData];
            }
        }
        
        if ([name isEqualToString: @"open-url"]) {
            [Gleap handleURL: (NSString *)messageData];
        }
        
        if ([name isEqualToString: @"show-form"]) {
            [Gleap startFeedbackFlow: [messageData objectForKey: @"formId"] showBackButton: YES];
        }
        
        if ([name isEqualToString: @"show-survey"]) {
            GleapSurveyFormat format = SURVEY;
            if ([[messageData objectForKey: @"surveyFormat"] isEqualToString: @"survey_full"]) {
                format = SURVEY_FULL;
            }
            [Gleap showSurvey: [messageData objectForKey: @"formId"] andFormat: format];
        }
        
        if ([name isEqualToString: @"show-news-article"]) {
            [Gleap openNewsArticle: [messageData objectForKey: @"articleId"] andShowBackButton: NO];
        }
        
        if ([name isEqualToString: @"show-help-article"]) {
            [Gleap openHelpCenterArticle: [messageData objectForKey: @"articleId"] andShowBackButton: NO];
        }
        
        if ([name isEqualToString: @"show-checklist"]) {
            [Gleap startChecklist: [messageData objectForKey: @"checklistId"] andShowBackButton: NO];
        }
    }
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    NSURL *url = navigationAction.request.URL;
    [self openURLExternally: url fromViewController: [GleapUIHelper getTopMostViewController]];
    return nil;
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self loadingFailed: error];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self loadingFailed: error];
}

- (void)loadingFailed:(NSError *)error {
    //[self.uiOverlayViewController removeBanner];
}

- (void)openURLExternally:(NSURL *)url fromViewController:(UIViewController *)presentingViewController {
    if (url == nil) {
        return;
    }
    
    @try {
        if ([SFSafariViewController class]) {
            SFSafariViewController *viewController = [[SFSafariViewController alloc] initWithURL: url];
            viewController.modalPresentationStyle = UIModalPresentationFormSheet;
            viewController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
            [presentingViewController presentViewController:viewController animated:YES completion:nil];
        } else {
            if ([[UIApplication sharedApplication] canOpenURL: url]) {
                if (@available(iOS 10.0, *)) {
                    [[UIApplication sharedApplication] openURL: url options:@{} completionHandler:nil];
                }
            }
        }
    } @catch(NSException *exception) {
        NSLog(@"Exception while opening URL: %@", exception);
    }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated) {
        NSURL *url = navigationAction.request.URL;
        if ([url.absoluteString hasPrefix: @"mailto:"]) {
            if ([[UIApplication sharedApplication] canOpenURL: url]) {
                if (@available(iOS 10.0, *)) {
                    [[UIApplication sharedApplication] openURL: url options:@{} completionHandler:nil];
                }
            }
        } else {
            [self openURLExternally: url fromViewController: [GleapUIHelper getTopMostViewController]];
        }
        return decisionHandler(WKNavigationActionPolicyCancel);
    }
    
    return decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)pinEdgesFrom:(UIView *)subView to:(UIView *)parent {
    NSString *format = [self.bannerData valueForKeyPath: @"format"];
    CGFloat padding = [format isEqualToString: @"floating"] ? 10.0f : 0.f;
    
    if (@available(iOS 11.0, *)) {
        UILayoutGuide *guide = parent.safeAreaLayoutGuide;
        [NSLayoutConstraint constraintWithItem:subView
                                     attribute:NSLayoutAttributeLeading
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:guide
                                     attribute:NSLayoutAttributeLeading
                                    multiplier:1.0
                                      constant:padding].active = YES;
        
        [NSLayoutConstraint constraintWithItem:subView
                                     attribute:NSLayoutAttributeTrailing
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:guide
                                     attribute:NSLayoutAttributeTrailing
                                    multiplier:1.0
                                      constant:-padding].active = YES;
    } else {
        NSLayoutConstraint *leading = [NSLayoutConstraint
                                       constraintWithItem: subView
                                       attribute: NSLayoutAttributeLeading
                                       relatedBy: NSLayoutRelationEqual
                                       toItem: parent
                                       attribute: NSLayoutAttributeLeading
                                       multiplier: 1.0f
                                       constant: padding];
        
        NSLayoutConstraint *trailing = [NSLayoutConstraint
                                        constraintWithItem: subView
                                        attribute: NSLayoutAttributeTrailing
                                        relatedBy: NSLayoutRelationEqual
                                        toItem: parent
                                        attribute: NSLayoutAttributeTrailing
                                        multiplier: 1.0f
                                        constant: -padding];
        
        [parent addConstraint: leading];
        [parent addConstraint: trailing];
    }
    
    NSLayoutConstraint *bottom =[NSLayoutConstraint
                                 constraintWithItem: subView
                                 attribute: NSLayoutAttributeBottom
                                 relatedBy: NSLayoutRelationEqual
                                 toItem: parent
                                 attribute: NSLayoutAttributeBottom
                                 multiplier: 1.0f
                                 constant: 0.f];
    [parent addConstraint: bottom];
    
    if (@available(iOS 11.0, *)) {
        UILayoutGuide *guide = self.superview.safeAreaLayoutGuide;
        [subView.topAnchor constraintEqualToAnchor:guide.topAnchor constant:padding].active = YES;
    } else {
        NSLayoutConstraint *topPadding = [NSLayoutConstraint
                                       constraintWithItem: subView
                                       attribute: NSLayoutAttributeTop
                                       relatedBy: NSLayoutRelationEqual
                                       toItem: self
                                       attribute: NSLayoutAttributeTop
                                       multiplier: 1.0f
                                       constant: padding];
        [self addConstraint: topPadding];
    }
    
    NSLayoutConstraint *height = [NSLayoutConstraint
                                      constraintWithItem: subView
                                      attribute: NSLayoutAttributeHeight
                                      relatedBy: NSLayoutRelationEqual
                                      toItem: nil
                                      attribute: NSLayoutAttributeNotAnAttribute
                                      multiplier: 0
                                      constant: 70.f];
    [subView addConstraint: height];
    self.heightConstraint = height;
}


@end
