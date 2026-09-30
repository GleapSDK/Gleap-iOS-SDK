//
//  GleapExternalDataHelper.h
//  
//
//  Created by Lukas Boehler on 31.05.22.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapExternalDataHelper : NSObject

@property (nonatomic, retain) NSMutableDictionary* data;

+ (instancetype)sharedInstance;

/*
 Thread-safe access: wrapper SDKs attach data from their bridge threads while a report reads it
 on a background queue.
 */
- (void)addEntries:(NSDictionary *)entries;
- (nullable id)objectForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
