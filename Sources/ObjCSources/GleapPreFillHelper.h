//
//  GleapPreFillHelper.h
//  
//
//  Created by Lukas Boehler on 01.06.22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapPreFillHelper : NSObject

+ (instancetype)sharedInstance;

@property (nonatomic, retain) NSMutableDictionary* preFillData;

@end

NS_ASSUME_NONNULL_END
