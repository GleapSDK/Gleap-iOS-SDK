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

@protocol GleapFrameManagerDelegate <NSObject>
@optional
- (void) connected;
- (void) failedToConnect;
@required
@end

@interface GleapFrameManagerViewController : UIViewController <WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate>

- (void)sendMessageWithData:(NSDictionary *)data;
- (void)sendSessionUpdate;
- (void)sendConfigUpdate;
- (id)initWithFormat:(NSString *)format;

@property (nonatomic, retain, nullable) NSTimer* timeoutTimer;
@property (nonatomic, assign) bool isCardSurvey;
@property (nonatomic, assign) bool connected;
@property (nonatomic, weak) id <GleapFrameManagerDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
