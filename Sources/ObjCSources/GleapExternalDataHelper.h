//
//  GleapExternalDataHelper.h
//  
//
//  Created by Lukas Boehler on 31.05.22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapExternalDataHelper : NSObject

@property (nonatomic, retain) NSMutableDictionary* data;

+ (instancetype)sharedInstance;

@end

NS_ASSUME_NONNULL_END
