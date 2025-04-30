//
//  GleapFeedbackButton.h
//  
//
//  Created by Lukas Boehler on 29.04.25.
//

@class GleapUIOverlayViewController;

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapModal : UIView <WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate>

/// Configure the modal with given data
- (void)setupWithData:(NSDictionary *)modalData;

@property (nonatomic, strong) UIView *backdropView;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSDictionary *modalData;
@property (nonatomic, weak) GleapUIOverlayViewController *uiOverlayViewController;

@end

NS_ASSUME_NONNULL_END
