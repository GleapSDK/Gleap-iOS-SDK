//
//  GleapUserSession.m
//  Gleap
//
//  Created by Lukas Boehler on 23.09.21.
//

#import "GleapUserProperty.h"
#import "GleapTranslationHelper.h"

@implementation GleapUserProperty

- (NSDictionary *)dataDictToSendWith:(NSString * _Nullable)userId and:(NSString * _Nullable)userHash {
    NSMutableDictionary *sessionRequestData = [[NSMutableDictionary alloc] init];
    if (userId != nil) {
        [sessionRequestData setValue: userId forKey: @"userId"];
    }
    if (self != nil && self.name != nil) {
        [sessionRequestData setValue: self.name forKey: @"name"];
    }
    if (self != nil && self.email != nil) {
        [sessionRequestData setValue: self.email forKey: @"email"];
    }
    if (self != nil && self.phone != nil) {
        [sessionRequestData setValue: self.phone forKey: @"phone"];
    }
    if (self != nil && self.plan != nil) {
        [sessionRequestData setValue: self.plan forKey: @"plan"];
    }
    if (self != nil && self.companyId != nil) {
        [sessionRequestData setValue: self.companyId forKey: @"companyId"];
    }
    if (self != nil && self.companyName != nil) {
        [sessionRequestData setValue: self.companyName forKey: @"companyName"];
    }
    if (self != nil && self.avatar != nil) {
        [sessionRequestData setValue: self.avatar forKey: @"avatar"];
    }
    if (self != nil && self.value != nil) {
        [sessionRequestData setValue: self.value forKey: @"value"];
    }
    if (self != nil && self.sla != nil) {
        [sessionRequestData setValue: self.sla forKey: @"sla"];
    }
    if (userHash != nil) {
        [sessionRequestData setValue: userHash forKey: @"userHash"];
    }
    
    NSString *lang = [GleapTranslationHelper sharedInstance].language;
    if (lang != nil) {
        [sessionRequestData setValue: lang forKey: @"lang"];
    }
    
    @try {
        if (self.customData != nil && [[self.customData allKeys] count] > 0) {
            [sessionRequestData addEntriesFromDictionary: self.customData];
        }
    } @catch (id exp) {}
    
    return sessionRequestData;
}

@end
