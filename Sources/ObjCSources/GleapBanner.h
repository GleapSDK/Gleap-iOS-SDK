//
//  GleapBanner.h
//  
//
//  Created by Lukas Boehler on 09.09.22.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
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
