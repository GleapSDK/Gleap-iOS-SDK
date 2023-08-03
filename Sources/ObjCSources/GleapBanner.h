//
//  GleapFeedbackButton.h
//  
//
//  Created by Lukas Boehler on 09.09.22.
//

@class GleapUIOverlayViewController;

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapBanner : UIView <WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate>

- (void)setupWithData:(NSDictionary *)bannerData;

@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
@property (nonatomic, retain) WKWebView *webView;
@property (nonatomic, retain) NSDictionary *bannerData;
@property (nonatomic, weak) GleapUIOverlayViewController *uiOverlayViewController;

@end

NS_ASSUME_NONNULL_END
