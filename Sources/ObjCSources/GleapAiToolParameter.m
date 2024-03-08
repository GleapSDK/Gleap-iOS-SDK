//
//  GleapAiToolParameter.m
//  
//
//  Created by Lukas Boehler on 08.03.24.
//

#import "GleapAiToolParameter.h"

@implementation GleapAiToolParameter

- (instancetype)initWithName:(NSString *)name
          parameterDescription:(NSString *)description
                         type:(NSString *)type
                     required:(BOOL)required {
    if (self = [super init]) {
        _name = name;
        _parameterDescription = description;
        _type = type;
        _required = required;
    }
    return self;
}

- (instancetype)initWithName:(NSString *)name
          parameterDescription:(NSString *)description
                         type:(NSString *)type
                     required:(BOOL)required
                        enums:(NSArray<NSString *> *)enums {
    if (self = [super init]) {
        _name = name;
        _parameterDescription = description;
        _type = type;
        _required = required;
        _enums = enums;
    }
    return self;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [@{@"name": self.name,
                                   @"description": self.parameterDescription,
                                   @"type": self.type,
                                   @"required": @(self.required)} mutableCopy];
    if (self.enums && self.enums.count > 0) {
        dict[@"enums"] = self.enums;
    }
    return [dict copy];
}

@end
