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
#import "GleapWebViewSupport.h"
#import "GleapOutboundActions.h"
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

- (void)dealloc {
    [GleapWebViewSupport removeMessageHandlerNamed: @"gleapBannerCallback" fromWebView: _webView];
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
    WKWebViewConfiguration *webConfig = [GleapWebViewSupport configurationWithMessageHandler: self name: @"gleapBannerCallback" allowsInlineMediaPlayback: YES];
    self.webView = [[WKWebView alloc] initWithFrame:self.frame configuration: webConfig];
    [GleapWebViewSupport makeWebViewTransparent: self.webView];
    [GleapWebViewSupport disableScrollingInWebView: self.webView];
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.allowsBackForwardNavigationGestures = NO;

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
{
    decisionHandler(WKPermissionDecisionGrant);
}

- (void)sendMessageWithData:(NSDictionary *)data {
    [GleapWebViewSupport sendMessage: data toFunction: @"appMessage" inWebView: self.webView];
}

- (void)userContentController:(WKUserContentController*)userContentController didReceiveScriptMessage:(WKScriptMessage*)message
{
    if ([message.name isEqualToString: @"gleapBannerCallback"] && [GleapWebViewSupport isTrustedMessage: message forPageURL: Gleap.sharedInstance.bannerUrl]) {
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
                    // Unless a newer banner has taken this one's place already.
                    if (self.uiOverlayViewController.banner == self) {
                        self.uiOverlayViewController.banner = nil;
                    }
                });
            }];
        }
        
        if ([name isEqualToString: @"start-custom-action"] && [messageData isKindOfClass: [NSDictionary class]]) {
            [GleapOutboundActions notifyCustomAction: [messageData objectForKey: @"action"]];
        }
        
        // Conversations, forms, surveys, articles, checklists and links.
        [GleapOutboundActions performAction: name data: messageData];
    }
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    [GleapWebViewSupport presentURLInSafari: navigationAction.request.URL from: [GleapUIHelper getTopMostViewController]];
    return nil;
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated) {
        [GleapWebViewSupport openTappedLink: navigationAction.request.URL from: [GleapUIHelper getTopMostViewController]];
        return decisionHandler(WKNavigationActionPolicyCancel);
    }
    
    return decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)pinEdgesFrom:(UIView *)subView to:(UIView *)parent {
    NSString *format = [self.bannerData valueForKeyPath: @"format"];
    CGFloat padding = [format isEqualToString: @"floating"] ? 10.0f : 0.f;
    
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
    
    NSLayoutConstraint *bottom =[NSLayoutConstraint
                                 constraintWithItem: subView
                                 attribute: NSLayoutAttributeBottom
                                 relatedBy: NSLayoutRelationEqual
                                 toItem: parent
                                 attribute: NSLayoutAttributeBottom
                                 multiplier: 1.0f
                                 constant: 0.f];
    [parent addConstraint: bottom];
    
    UILayoutGuide *superviewGuide = self.superview.safeAreaLayoutGuide;
    [subView.topAnchor constraintEqualToAnchor:superviewGuide.topAnchor constant:padding].active = YES;
    
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
