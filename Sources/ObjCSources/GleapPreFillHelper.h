//
//  GleapPreFillHelper.h
//  
//
//  Created by Lukas Boehler on 01.06.22.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapPreFillHelper : NSObject

+ (instancetype)sharedInstance;

@property (nonatomic, retain) NSMutableDictionary* preFillData;

@end

NS_ASSUME_NONNULL_END
