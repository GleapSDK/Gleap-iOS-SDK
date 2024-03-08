//
//  GleapAiToolParameter.h
//  
//
//  Created by Lukas Boehler on 08.03.24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapAiToolParameter : NSObject

@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *parameterDescription;
@property (nonatomic, strong) NSString *type; // "string", "number", or "boolean"
@property (nonatomic, assign) BOOL required;
@property (nonatomic, strong) NSArray<NSString *> *enums; // Optional, might not always be set

- (instancetype)initWithName:(NSString *)name
          parameterDescription:(NSString *)description
                         type:(NSString *)type
                    required:(BOOL)required;

- (instancetype)initWithName:(NSString *)name
          parameterDescription:(NSString *)description
                         type:(NSString *)type
                     required:(BOOL)required
                        enums:(NSArray<NSString *> *)enums;

- (NSDictionary *)toDictionary;

@end

NS_ASSUME_NONNULL_END
