//
//  GleapScreenshotListener.h
//  
//
//  Created by Lukas Boehler on 27.05.22.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapScreenshotListener : NSObject

+ (instancetype)sharedInstance;

- (void)start;

@end

NS_ASSUME_NONNULL_END
