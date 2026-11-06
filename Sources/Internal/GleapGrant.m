//
//  GleapGrant.m
//  Gleap
//

#import "GleapGrant.h"
#import "GleapUserJwt.h"

static NSString * const kGleapGrantKey = @"gleapGrant";
static NSString * const kGleapGrantIdKey = @"gleapGrantId";
static NSString * const kGleapGrantExpKey = @"gleapGrantExp";

@interface GleapGrant ()
@property (nonatomic, copy, nullable) NSString *grant;
@property (nonatomic, copy, nullable) NSString *gleapId;
@property (nonatomic, strong, nullable) NSDate *expiry;
@end

@implementation GleapGrant

+ (instancetype)sharedInstance {
    static GleapGrant *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapGrant alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *grant = [defaults stringForKey: kGleapGrantKey];
        NSString *gleapId = [defaults stringForKey: kGleapGrantIdKey];
        if (grant.length > 0 && gleapId.length > 0) {
            _grant = grant;
            _gleapId = gleapId;
            id exp = [defaults objectForKey: kGleapGrantExpKey];
            if ([exp isKindOfClass: [NSNumber class]]) {
                _expiry = [NSDate dateWithTimeIntervalSince1970: [exp doubleValue]];
            }
        }
    }
    return self;
}

- (nullable NSString *)grantForGleapId:(nullable NSString *)gleapId {
    @synchronized (self) {
        if (self.grant == nil || gleapId.length == 0 || ![self.gleapId isEqualToString: gleapId]) {
            return nil;
        }
        return self.grant;
    }
}

- (nullable NSDate *)expiresAt {
    @synchronized (self) {
        return self.grant != nil ? self.expiry : nil;
    }
}

- (BOOL)needsRenewalForGleapId:(nullable NSString *)gleapId within:(NSTimeInterval)window {
    @synchronized (self) {
        if ([self grantForGleapId: gleapId] == nil) {
            return NO;
        }
        return self.expiry != nil && [self.expiry timeIntervalSinceNow] < window;
    }
}

- (BOOL)applySessionAnswer:(NSDictionary *)data {
    id identity = [data objectForKey: @"identity"];
    if (![identity isKindOfClass: [NSDictionary class]]) {
        return NO;
    }
    id grant = [identity objectForKey: @"grant"];
    id gleapId = [data objectForKey: @"gleapId"];
    if (![grant isKindOfClass: [NSString class]] || [grant length] == 0 || ![gleapId isKindOfClass: [NSString class]]) {
        // A signed identify is the only source of a grant: an unsigned one ends the signed session.
        return [self setGrant: nil forGleapId: nil];
    }
    return [self setGrant: grant forGleapId: gleapId];
}

- (BOOL)setGrant:(nullable NSString *)grant forGleapId:(nullable NSString *)gleapId {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    @synchronized (self) {
        if (grant.length == 0 || gleapId.length == 0) {
            BOOL changed = self.grant != nil;
            self.grant = nil;
            self.gleapId = nil;
            self.expiry = nil;
            [defaults removeObjectForKey: kGleapGrantKey];
            [defaults removeObjectForKey: kGleapGrantIdKey];
            [defaults removeObjectForKey: kGleapGrantExpKey];
            return changed;
        }
        if ([self.grant isEqualToString: grant] && [self.gleapId isEqualToString: gleapId]) {
            return NO;
        }
        NSNumber *exp = [GleapUserJwt expirationOf: grant];
        self.grant = grant;
        self.gleapId = gleapId;
        self.expiry = exp != nil ? [NSDate dateWithTimeIntervalSince1970: [exp doubleValue]] : nil;
        [defaults setObject: grant forKey: kGleapGrantKey];
        [defaults setObject: gleapId forKey: kGleapGrantIdKey];
        if (exp != nil) {
            [defaults setObject: exp forKey: kGleapGrantExpKey];
        } else {
            [defaults removeObjectForKey: kGleapGrantExpKey];
        }
        return YES;
    }
}

- (void)clear {
    [self setGrant: nil forGleapId: nil];
}

- (void)applyToRequest:(NSMutableURLRequest *)request {
    NSString *grant = [self grantForGleapId: [request valueForHTTPHeaderField: @"Gleap-Id"]];
    if (grant != nil) {
        [request setValue: grant forHTTPHeaderField: @"Gleap-Grant"];
    }
}

@end
