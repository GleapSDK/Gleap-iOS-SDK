//
//  GleapCustomDataHelper.h
//  
//
//  Created by Lukas Boehler on 27.05.22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapCustomDataHelper : NSObject

/**
 * Attaches custom data, which can be viewed in the Gleap dashboard. New data will be merged with existing custom data.
 * @author Gleap
 *
 * @param customData The data to attach to a bug report.
 */
+ (void)attachCustomData: (NSDictionary *)customData;

/**
 * Attach one key value pair to existing custom data.
 * @author Gleap
 *
 * @param value The value you want to add
 * @param key The key of the attribute
 */
+ (void)setCustomData: (NSString *)value forKey: (NSString *)key;

/**
 * Removes one key from existing custom data.
 * @author Gleap
 *
 * @param key The key of the attribute
 */
+ (void)removeCustomDataForKey: (NSString *)key;

/**
 * Clears all custom data.
 * @author Gleap
 */
+ (void)clearCustomData;

+ (void)setTicketAttributeWithKey:(NSString *)key value:(id)value;
+ (void)unsetTicketAttributeWithKey:(NSString *)key;
+ (void)clearTicketAttributes;

/**
 * Returns the custom data
 * @author Gleap
 */
+ (NSDictionary *)getCustomData;
+ (NSDictionary *)getTicketAttributes;

@property (retain, nonatomic) NSMutableDictionary *customData;
@property (retain, nonatomic) NSMutableDictionary *ticketAttributeData;

@end

NS_ASSUME_NONNULL_END
