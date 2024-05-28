//
//  GleapWindowChecker.h
//  
//
//  Created by Lukas Boehler on 28.05.24.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^GleapWindowReadyCompletion)(void);

@interface GleapWindowChecker : NSObject

- (void)waitForKeyWindowToBeReadyWithCompletion:(GleapWindowReadyCompletion)completion;

@end

NS_ASSUME_NONNULL_END
