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

- (NSDictionary *)widgetDictionary {
    NSMutableDictionary *data = [[self toDictionary] mutableCopy];
    if ([self hasFileAccess]) {
        NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        [data setObject: self.fileAccessToken forKey: @"fileAccessToken"];
        [data setObject: [formatter stringFromDate: self.fileAccessExpiresAt] forKey: @"fileAccessExpiresAt"];
    }
    return data;
}

- (BOOL)hasFileAccess {
    return self.fileAccessToken.length > 0 && self.fileAccessExpiresAt != nil && [self.fileAccessExpiresAt timeIntervalSinceNow] > 0;
}

@end
