//
//  GleapScreenCaptureHelper.h
//  
//
//  Created by Lukas Boehler on 25.05.22.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapScreenCaptureHelper : NSObject

+ (UIImage *)captureScreen;

@end

NS_ASSUME_NONNULL_END
