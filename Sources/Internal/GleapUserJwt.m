//
//  GleapUserJwt.m
//  Gleap
//

#import "GleapUserJwt.h"

static NSUInteger const kGleapUserJwtMaxLength = 4096;

@implementation GleapUserJwt

+ (BOOL)isUserJwt:(id)token {
    if (![token isKindOfClass: [NSString class]] || [token length] == 0 || [token length] > kGleapUserJwtMaxLength) {
        return NO;
    }
    NSArray<NSString *> *segments = [token componentsSeparatedByString: @"."];
    if (segments.count != 3) {
        return NO;
    }
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"] invertedSet];
    for (NSString *segment in segments) {
        if (segment.length == 0 || [segment rangeOfCharacterFromSet: invalid].location != NSNotFound) {
            return NO;
        }
    }
    return YES;
}

+ (nullable NSDictionary *)payloadOf:(id)token {
    return [self segment: 1 of: token];
}

// The decoded JSON object of the token's header (0) or payload (1).
+ (nullable NSDictionary *)segment:(NSUInteger)index of:(id)token {
    if (![self isUserJwt: token]) {
        return nil;
    }
    NSString *segment = [[token componentsSeparatedByString: @"."] objectAtIndex: index];
    NSMutableString *base64 = [[[segment stringByReplacingOccurrencesOfString: @"-" withString: @"+"]
                                stringByReplacingOccurrencesOfString: @"_" withString: @"/"] mutableCopy];
    while (base64.length % 4 != 0) {
        [base64 appendString: @"="];
    }
    NSData *data = [[NSData alloc] initWithBase64EncodedString: base64 options: 0];
    if (data == nil) {
        return nil;
    }
    id payload = [NSJSONSerialization JSONObjectWithData: data options: 0 error: nil];
    return [payload isKindOfClass: [NSDictionary class]] ? payload : nil;
}

+ (nullable NSString *)userIdOf:(id)token {
    NSDictionary *payload = [self payloadOf: token];
    id userId = [payload objectForKey: @"userId"];
    if (userId == nil || userId == [NSNull null]) {
        userId = [payload objectForKey: @"user_id"];
    }
    if ([userId isKindOfClass: [NSString class]]) {
        return [userId length] > 0 ? userId : nil;
    }
    // NSJSONSerialization reads true / false as NSNumber too; they are no user id.
    if ([userId isKindOfClass: [NSNumber class]] && CFGetTypeID((__bridge CFTypeRef)userId) != CFBooleanGetTypeID()) {
        double value = [userId doubleValue];
        if (isfinite(value)) {
            return [userId stringValue];
        }
    }
    return nil;
}

+ (nullable NSNumber *)expirationOf:(id)token {
    id exp = [[self payloadOf: token] objectForKey: @"exp"];
    if ([exp isKindOfClass: [NSNumber class]] && CFGetTypeID((__bridge CFTypeRef)exp) != CFBooleanGetTypeID()) {
        return exp;
    }
    return nil;
}

+ (BOOL)token:(id)token expiresWithin:(NSTimeInterval)window of:(NSDate *)now {
    NSNumber *exp = [self expirationOf: token];
    return exp != nil && [exp doubleValue] - [now timeIntervalSince1970] < window;
}

+ (nullable NSString *)identityFingerprintOf:(id)token {
    NSDictionary *payload = [self payloadOf: token];
    if (payload == nil) {
        return nil;
    }
    NSMutableDictionary *claims = [payload mutableCopy];
    [claims removeObjectsForKeys: @[@"iat", @"exp", @"nbf", @"jti"]];
    id kid = [[self segment: 0 of: token] objectForKey: @"kid"] ?: [NSNull null];
    NSData *data = [NSJSONSerialization dataWithJSONObject: @{ @"kid": kid, @"claims": claims }
                                                   options: NSJSONWritingSortedKeys
                                                     error: nil];
    return data != nil ? [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] : token;
}

+ (BOOL)isSignatureRequiredForStatus:(NSInteger)status body:(NSData *)body {
    if (status != 401 || body == nil) {
        return NO;
    }
    NSString *text = [[NSString alloc] initWithData: body encoding: NSUTF8StringEncoding];
    return [text containsString: @"signature_required"];
}

+ (nullable NSString *)refusalCodeForStatus:(NSInteger)status body:(NSData *)body {
    if (status != 401 || body == nil) {
        return nil;
    }
    NSString *text = [[NSString alloc] initWithData: body encoding: NSUTF8StringEncoding];
    if ([text containsString: @"token_expired"]) {
        return @"token_expired";
    }
    if ([text containsString: @"token_invalid"]) {
        return @"token_invalid";
    }
    return nil;
}

+ (BOOL)isIdentityMismatchForStatus:(NSInteger)status body:(NSData *)body {
    if (status != 400 || body == nil) {
        return NO;
    }
    NSString *text = [[NSString alloc] initWithData: body encoding: NSUTF8StringEncoding];
    return [text containsString: @"identity_mismatch"];
}

@end

@interface GleapUserJwtProviderGate ()
@property (nonatomic, assign, readwrite) NSTimeInterval failedAt;
@property (nonatomic, strong, nullable) NSMutableArray<void (^)(NSString * _Nullable)> *waiting;
@property (nonatomic, assign) NSUInteger call;
@end

@implementation GleapUserJwtProviderGate

- (instancetype)init {
    self = [super init];
    if (self) {
        _timeout = 10;
        _pauseAfterFailure = 30;
    }
    return self;
}

- (BOOL)inFlight {
    return self.waiting != nil;
}

- (void)setProvider:(GleapUserJwtProvider)provider {
    _provider = [provider copy];
    // A new provider is asked right away, even after the old one failed.
    self.failedAt = 0;
}

- (void)requestToken:(void (^)(NSString * _Nullable))completion {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self requestToken: completion];
        });
        return;
    }
    GleapUserJwtProvider provider = self.provider;
    if (provider == nil) {
        completion(nil);
        return;
    }
    if (self.waiting != nil) {
        [self.waiting addObject: [completion copy]];
        return;
    }
    NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
    if (self.failedAt > 0 && now - self.failedAt < self.pauseAfterFailure) {
        completion(nil);
        return;
    }

    self.waiting = [NSMutableArray arrayWithObject: [completion copy]];
    NSUInteger call = ++self.call;
    __weak GleapUserJwtProviderGate *weakSelf = self;
    void (^finish)(NSString *, NSString *) = ^(NSString *token, NSString *failure) {
        GleapUserJwtProviderGate *gate = weakSelf;
        if (gate == nil || call != gate.call || gate.waiting == nil) {
            return;
        }
        NSArray *waiting = gate.waiting;
        gate.waiting = nil;
        if (failure == nil && [GleapUserJwt userIdOf: token] == nil) {
            failure = @"it did not return a JWT with a userId";
        }
        if (failure != nil) {
            token = nil;
            gate.failedAt = [NSProcessInfo processInfo].systemUptime;
            NSLog(@"[GLEAP_SDK] The JWT provider failed (%@). Asking again in %.0f s at the earliest.", failure, gate.pauseAfterFailure);
        } else {
            gate.failedAt = 0;
        }
        for (void (^waiter)(NSString *) in waiting) {
            waiter(token);
        }
    };

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        finish(nil, [NSString stringWithFormat: @"timed out after %.0f s", self.timeout]);
    });
    @try {
        provider(^(NSString * _Nullable token) {
            dispatch_async(dispatch_get_main_queue(), ^{
                finish(token, token == nil ? @"it returned nil" : nil);
            });
        });
    } @catch (id exception) {
        finish(nil, @"it threw an exception");
    }
}

@end
