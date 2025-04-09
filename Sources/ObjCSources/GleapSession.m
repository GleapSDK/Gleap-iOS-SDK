//
//  GleapSession.m
//  Gleap
//
//  Created by Lukas Boehler on 23.09.21.
//

#import "GleapSession.h"
#import "GleapCore.h"

@implementation GleapSession

static id ObjectOrNull(id object)
{
  return object ?: [NSNull null];
}

- (NSDictionary *)toDictionary {
    return @{
        @"gleapId": ObjectOrNull(self.gleapId),
        @"gleapHash": ObjectOrNull(self.gleapHash),
        @"userId": ObjectOrNull(self.userId),
        @"name": ObjectOrNull(self.name),
        @"email": ObjectOrNull(self.email),
        @"value": ObjectOrNull(self.value),
        @"sla": ObjectOrNull(self.sla),
        @"phone": ObjectOrNull(self.phone),
        @"companyId": ObjectOrNull(self.companyId),
        @"companyName": ObjectOrNull(self.companyName),
        @"avatar": ObjectOrNull(self.avatar),
        @"plan": ObjectOrNull(self.plan),
        @"customData": ObjectOrNull(self.customData)
    };
}

@end
