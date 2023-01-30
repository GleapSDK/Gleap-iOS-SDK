//
//  GleapWidgetManager.h
//  
//
//  Created by Lukas Boehler on 28.05.22.
//

#import <Foundation/Foundation.h>
#import "GleapFrameManagerViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapWidgetManager : NSObject <GleapFrameManagerDelegate>

+ (instancetype)sharedInstance;

- (BOOL)isOpened;
- (void)closeWidgetWithAnimation:(Boolean)animated andCompletion:(void (^)(void))completion;
- (void)showWidget;
- (void)showWidgetFor:(NSString *)type;
- (void)sendMessageWithData:(NSDictionary *)data;
- (void)sendSessionUpdate;
- (void)sendConfigUpdate;

@property (nonatomic, assign) bool widgetOpened;
@property (nonatomic, retain, nullable) GleapFrameManagerViewController *gleapWidget;
@property (nonatomic, retain, nullable) NSMutableArray *messageQueue;

@end

NS_ASSUME_NONNULL_END
