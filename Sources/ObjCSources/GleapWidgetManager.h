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
- (void)closeWidget: (void (^)())completion;
- (void)showWidget;
- (void)sendMessageWithData:(NSDictionary *)data;

@property (nonatomic, retain, nullable) GleapFrameManagerViewController *gleapWidget;
@property (nonatomic, retain, nullable) NSMutableArray *messageQueue;

@end

NS_ASSUME_NONNULL_END
