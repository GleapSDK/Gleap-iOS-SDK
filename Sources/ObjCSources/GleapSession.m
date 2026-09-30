//
//  GleapSession.m
//  Gleap
//
//  Created by Lukas Boehler on 23.09.21.
//

#import "GleapSession.h"
#import "GleapInternal.h"
#import "GleapCore.h"

@implementation GleapSession

- (NSDictionary *)toDictionary {
    return @{
        @"gleapId": GleapObjectOrNull(self.gleapId),
        @"gleapHash": GleapObjectOrNull(self.gleapHash),
        @"userId": GleapObjectOrNull(self.userId),
        @"name": GleapObjectOrNull(self.name),
        @"email": GleapObjectOrNull(self.email),
        @"value": GleapObjectOrNull(self.value),
        @"sla": GleapObjectOrNull(self.sla),
        @"phone": GleapObjectOrNull(self.phone),
        @"companyId": GleapObjectOrNull(self.companyId),
        @"companyName": GleapObjectOrNull(self.companyName),
        @"avatar": GleapObjectOrNull(self.avatar),
        @"plan": GleapObjectOrNull(self.plan),
        @"customData": GleapObjectOrNull(self.customData)
    };
}

@end
