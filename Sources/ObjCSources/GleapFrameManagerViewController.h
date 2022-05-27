//
//  GleapWidgetViewController.h
//  Gleap
//
//  Created by Lukas on 13.01.19.
//  Copyright © 2019 Gleap. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapFrameManagerViewController : UIViewController <WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate>

- (void)setScreenshot:(UIImage *)image;
- (void)sendSessionUpdate;
- (void)sendConfigUpdate;

@property (nonatomic, retain, nullable) NSTimer* timeoutTimer;

@end

NS_ASSUME_NONNULL_END
