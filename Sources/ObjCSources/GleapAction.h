//
//  GleapSession.h
//  Gleap
//
//  Created by Lukas Boehler on 23.09.21.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapAction : NSObject

@property (nonatomic, retain) NSString* outbound;
@property (nonatomic, retain) NSString* actionType;

@end

NS_ASSUME_NONNULL_END
