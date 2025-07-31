// GleapModal.m

#import "GleapModal.h"
#import "GleapConfigHelper.h"
#import "GleapUIHelper.h"
#import "GleapUIOverlayHelper.h"
#import "GleapUIOverlayViewController.h"
#import "Gleap.h"
#import <SafariServices/SafariServices.h>
#import <WebKit/WebKit.h>

@interface GleapModal ()
// Redeclare as readwrite to match the public readonly in the header
@property (nonatomic, strong, readwrite) NSLayoutConstraint *heightConstraint;
@property (nonatomic, strong, readwrite) NSLayoutConstraint *maxWidthConstraint;
@end

@implementation GleapModal

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.alpha = 0;
        self.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return self;
}

- (void)setupWithData:(NSDictionary *)modalData {
    self.modalData = modalData;

    // 1) Backdrop
    self.backdropView = [[UIView alloc] initWithFrame:self.bounds];
    self.backdropView.translatesAutoresizingMaskIntoConstraints = NO;
    self.backdropView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    [self addSubview:self.backdropView];
    [NSLayoutConstraint activateConstraints:@[
        [self.backdropView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.backdropView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.backdropView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.backdropView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
    UITapGestureRecognizer *tapRec = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleBackdropTap)];
    [self.backdropView addGestureRecognizer:tapRec];

    // 2) Container
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.layer.cornerRadius = 20.0;
    container.layer.masksToBounds = YES;
    container.backgroundColor = [GleapUIHelper colorFromHexString:
        [modalData valueForKeyPath:@"config.backgroundColor"] ?: @"#FFFFFF"];
    [self addSubview:container];

    // compute initial cap based on screen size
    CGFloat screenW = CGRectGetWidth(self.bounds);
    CGFloat screenH = CGRectGetHeight(self.bounds);
    BOOL isLandscape = (screenW > screenH);
    
    // In landscape, make the modal significantly smaller
    CGFloat maxWidth = isLandscape ? 400.0 : 600.0;
    CGFloat widthMultiplier = isLandscape ? 0.7 : 0.9;
    
    // Use priority to make sure max width constraint doesn't conflict with percentage constraint
    NSLayoutConstraint *widthPercentConstraint = [container.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:widthMultiplier];
    widthPercentConstraint.priority = UILayoutPriorityRequired - 1; // Just below required
    
    // Create the max width constraint with higher priority in landscape mode
    self.maxWidthConstraint = [container.widthAnchor constraintLessThanOrEqualToConstant:maxWidth];
    self.maxWidthConstraint.priority = isLandscape ? (UILayoutPriorityRequired - 1) : (UILayoutPriorityRequired - 2); // Higher priority in landscape
    
    // Set up container constraints - center it and apply width/height constraints
    [NSLayoutConstraint activateConstraints:@[
        [container.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [container.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        widthPercentConstraint,
        self.maxWidthConstraint
    ]];
    
    // Height constraint - use inequality to avoid conflicts
    NSLayoutConstraint *heightConstraint = [container.heightAnchor constraintLessThanOrEqualToAnchor:self.heightAnchor multiplier:0.9];
    heightConstraint.priority = UILayoutPriorityRequired - 1;
    heightConstraint.active = YES;

    // 3) WKWebView config
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *userController = [[WKUserContentController alloc] init];
    [userController addScriptMessageHandler:self name:@"gleapModalCallback"];
    config.userContentController = userController;
    config.allowsInlineMediaPlayback = YES;
    config.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];

    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.scrollView.pinchGestureRecognizer.enabled = NO;
    self.webView.layer.cornerRadius = 20.0;
    self.webView.layer.masksToBounds = YES;
    self.webView.scrollView.bounces = NO;
    self.webView.scrollView.scrollEnabled = NO;
    self.webView.scrollView.alwaysBounceHorizontal = NO;
    self.webView.scrollView.alwaysBounceVertical = NO;
    if (@available(iOS 11.0, *)) {
        self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }

    [container addSubview:self.webView];
    [NSLayoutConstraint activateConstraints:@[
        [self.webView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.webView.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor]
    ]];

    // 4) Height constraint for webView with lower priority - will be adjusted by JS messages
    self.heightConstraint = [self.webView.heightAnchor constraintEqualToConstant:0];
    self.heightConstraint.priority = UILayoutPriorityDefaultHigh; // Lower priority to avoid conflicts
    self.heightConstraint.active = YES;
    
    // Add a minimum height constraint to ensure the webView has reasonable size
    NSLayoutConstraint *minHeightConstraint = [self.webView.heightAnchor constraintGreaterThanOrEqualToConstant:100];
    minHeightConstraint.priority = UILayoutPriorityDefaultLow;
    minHeightConstraint.active = YES;

    // 5) Load
    NSURLRequest *request = [NSURLRequest requestWithURL:
        [NSURL URLWithString:Gleap.sharedInstance.modalUrl]];
    [self.webView loadRequest:request];
}

- (void)handleBackdropTap {
    BOOL showClose = self.modalData[@"config"][@"showCloseButton"]
        ? [self.modalData[@"config"][@"showCloseButton"] boolValue]
        : YES;
    if (showClose) {
        [self hideModal];
    }
}

- (void)sendMessageWithData:(NSDictionary *)data {
    @try {
        NSError *err;
        NSData *json = [NSJSONSerialization dataWithJSONObject:data options:0 error:&err];
        if (!json) {
            NSLog(@"[Gleap] JSON Error: %@", err);
            return;
        }
        NSString *js = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.webView evaluateJavaScript:
                [NSString stringWithFormat:@"appMessage(%@)", js]
                             completionHandler:nil];
        });
    } @catch (NSException *ex) {
        NSLog(@"[Gleap] Exception sending message: %@", ex);
    }
}

- (void)userContentController:(WKUserContentController *)uC didReceiveScriptMessage:(WKScriptMessage *)message {
    @try {
        if (![message.name isEqualToString:@"gleapModalCallback"]) return;
        NSDictionary *body = message.body;
        NSString *name = body[@"name"];
        NSDictionary *data = body[@"data"];
        
        if ([name isEqualToString:@"modal-loaded"]) {
            NSDictionary *flowConfig = [GleapConfigHelper sharedInstance].config;
            NSString *primaryColor = flowConfig[@"color"] ?: @"#485BFF";
            NSString *backgroundColor = flowConfig[@"backgroundColor"] ?: @"#FFFFFF";
            NSMutableDictionary *payload = [[self.modalData objectForKey:@"config"] mutableCopy];
            payload[@"primaryColor"] = primaryColor;
            payload[@"backgroundColor"] = backgroundColor;
            [self sendMessageWithData:@{@"name":@"modal-data",@"data":payload}];
        }
        else if ([name isEqualToString:@"modal-height"]) {
            NSNumber *h = data[@"height"];
            if (h) {
                // Get the current bounds to calculate max height
                CGFloat maxHeight = CGRectGetHeight(self.bounds) * 0.9;
                CGFloat newHeight = MIN([h floatValue], maxHeight);
                
                // Update the height constraint on the main thread
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.heightConstraint.constant = newHeight;
                    [UIView animateWithDuration:0.25 animations:^{
                        [self layoutIfNeeded];
                    }];
                });
            }
        }
        else if ([name isEqualToString:@"modal-close"]) {
            [self hideModal];
        }
        else if ([name isEqualToString:@"start-conversation"]) {
            [self hideModal];
            [Gleap startBot:data[@"botId"] showBackButton:YES];
        } else if ([name isEqualToString:@"start-custom-action"]) {
            [self hideModal];
            if ([Gleap.sharedInstance.delegate respondsToSelector:
                 @selector(customActionCalled:withShareToken:)]) {
                [Gleap.sharedInstance.delegate
                 customActionCalled:data[@"action"] withShareToken:nil];
            } else if ([Gleap.sharedInstance.delegate respondsToSelector:
                        @selector(customActionCalled:)]) {
                [Gleap.sharedInstance.delegate
                 customActionCalled:data[@"action"]];
            }
        } else if ([name isEqualToString:@"open-url"]) {
            [self hideModal];
            [Gleap handleURL: (NSString *)data];
        } else if ([name isEqualToString:@"show-form"]) {
            [self hideModal];
            [Gleap startFeedbackFlow:data[@"formId"] showBackButton:YES];
        } else if ([name isEqualToString:@"show-survey"]) {
            GleapSurveyFormat format = SURVEY;
            if ([data[@"surveyFormat"] isEqualToString:@"survey_full"]) {
                format = SURVEY_FULL;
            }
            
            [self hideModal];
            [Gleap showSurvey:data[@"formId"] andFormat:format];
        } else if ([name isEqualToString:@"show-news-article"]) {
            [self hideModal];
            [Gleap openNewsArticle:data[@"articleId"] andShowBackButton:NO];
        } else if ([name isEqualToString:@"show-help-article"]) {
            [self hideModal];
            [Gleap openHelpCenterArticle:data[@"articleId"] andShowBackButton:NO];
        } else if ([name isEqualToString:@"show-checklist"]) {
            [self hideModal];
            [Gleap startChecklist:data[@"checklistId"] andShowBackButton:NO];
        }
    } @catch (NSException * e) {
        NSLog(@"Modal action error, %@", e);
    }
}

- (void)hideModal {
    [UIView animateWithDuration:0.3 animations:^{
        self.alpha = 0.0;
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        self.uiOverlayViewController.modal = nil;
    }];
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    if (navAction.navigationType == WKNavigationTypeLinkActivated) {
        NSURL *url = navAction.request.URL;
        if ([url.scheme isEqualToString:@"mailto"]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        } else {
            [self openURLExternally:url];
        }
        decisionHandler(WKNavigationActionPolicyCancel);
    } else {
        decisionHandler(WKNavigationActionPolicyAllow);
    }
}

- (void)openURLExternally:(NSURL *)url {
    UIViewController *vc = [GleapUIHelper getTopMostViewController];
    if ([SFSafariViewController class]) {
        SFSafariViewController *svc = [[SFSafariViewController alloc] initWithURL:url];
        svc.modalPresentationStyle = UIModalPresentationFormSheet;
        [vc presentViewController:svc animated:YES completion:nil];
    } else {
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }
}

// 5) Re-clamp on size/orientation changes
- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat screenW = CGRectGetWidth(self.bounds);
    CGFloat screenH = CGRectGetHeight(self.bounds);
    BOOL isLandscape = (screenW > screenH);

    // update width cap - make it smaller in landscape mode
    self.maxWidthConstraint.constant = isLandscape ? 450.0 : 600.0;
    
    // In landscape, give the max width constraint higher priority
    self.maxWidthConstraint.priority = isLandscape ? (UILayoutPriorityRequired - 1) : (UILayoutPriorityRequired - 2);
    
    // Dynamically adjust container width multiplier based on orientation
    for (NSLayoutConstraint *constraint in self.constraints) {
        if (constraint.firstAttribute == NSLayoutAttributeWidth &&
            constraint.multiplier > 0 &&
            constraint.firstItem != self &&
            [constraint.firstItem isKindOfClass:[UIView class]]) {
            // This is likely our width percentage constraint
            CGFloat newMultiplier = isLandscape ? 0.7 : 0.9;
            
            // We can't modify multiplier directly, so recreate the constraint if needed
            if (fabs(constraint.multiplier - newMultiplier) > 0.01) {
                NSLayoutConstraint *newConstraint = [NSLayoutConstraint
                    constraintWithItem:constraint.firstItem
                    attribute:constraint.firstAttribute
                    relatedBy:constraint.relation
                    toItem:constraint.secondItem
                    attribute:constraint.secondAttribute
                    multiplier:newMultiplier
                    constant:constraint.constant];
                
                newConstraint.priority = constraint.priority;
                
                constraint.active = NO;
                newConstraint.active = YES;
            }
        }
    }

    // update height cap if there's a current height constraint
    if (self.heightConstraint.constant > 0) {
        // Use a smaller height percentage in landscape orientation
        CGFloat heightMultiplier = isLandscape ? 0.8 : 0.9;
        CGFloat capH = screenH * heightMultiplier;
        self.heightConstraint.constant = MIN(self.heightConstraint.constant, capH);
    }
}

@end
