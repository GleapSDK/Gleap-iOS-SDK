//
//  GleapScreenshotManager.h
//  
//
//  Created by Lukas Boehler on 28.05.22.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapScreenshotManager : NSObject

+ (instancetype)sharedInstance;
+ (UIImage *)getScreenshot;
+ (void)takeScreenshot;

@property (strong, nonatomic, nullable) UIImage *screenshot;

@end

NS_ASSUME_NONNULL_END
