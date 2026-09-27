//
//  GleapNetworkLogSanitizer.m
//  Gleap
//
//  Removes sensitive data from network logs before they leave the device.
//

#import "GleapNetworkLogSanitizer.h"

static NSString * const kGleapRedactedValue = @"[REDACTED]";
static NSInteger const kGleapMaxRedactionDepth = 64;

@implementation GleapNetworkLogSanitizer

+ (NSArray<NSString *> *)defaultBlacklist {
    return @[@"gleap.io", @"gleap.ai"];
}

// Credential headers are masked even when no prop is configured: a support tool should
// never show a customer's bearer token or session cookie.
+ (NSSet<NSString *> *)maskedHeaders {
    static NSSet *maskedHeaders = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        maskedHeaders = [NSSet setWithArray: @[@"authorization", @"proxy-authorization", @"cookie", @"set-cookie"]];
    });
    return maskedHeaders;
}

+ (NSArray<NSString *> *)normalizedStrings:(NSArray *)input {
    NSMutableArray *result = [NSMutableArray array];
    if (![input isKindOfClass: [NSArray class]]) {
        return result;
    }
    for (id item in input) {
        if (![item isKindOfClass: [NSString class]]) {
            continue;
        }
        NSString *trimmed = [(NSString *)item stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0 && ![result containsObject: trimmed]) {
            [result addObject: trimmed];
        }
    }
    return result;
}

+ (BOOL)isURLBlacklisted:(NSString *)url blacklist:(NSArray *)blacklist {
    if (![url isKindOfClass: [NSString class]] || url.length == 0) {
        return NO;
    }
    NSArray *entries = [[self defaultBlacklist] arrayByAddingObjectsFromArray: [self normalizedStrings: blacklist]];
    for (NSString *entry in entries) {
        if ([url rangeOfString: entry options: NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

+ (NSArray<NSDictionary *> *)sanitizeNetworkLogs:(NSArray *)networkLogs
                                    propsToIgnore:(NSArray *)propsToIgnore
                                        blacklist:(NSArray *)blacklist {
    NSMutableArray *result = [NSMutableArray array];
    if (![networkLogs isKindOfClass: [NSArray class]]) {
        return result;
    }

    NSMutableSet<NSString *> *keys = [NSMutableSet set];
    NSMutableArray<NSArray<NSString *> *> *paths = [NSMutableArray array];
    for (NSString *prop in [self normalizedStrings: propsToIgnore]) {
        NSString *lowercaseProp = [prop lowercaseString];
        [keys addObject: lowercaseProp];
        if ([lowercaseProp containsString: @"."]) {
            NSArray *segments = [lowercaseProp componentsSeparatedByString: @"."];
            if (![segments containsObject: @""]) {
                [paths addObject: segments];
            }
        }
    }

    for (id entry in networkLogs) {
        if (![entry isKindOfClass: [NSDictionary class]]) {
            continue;
        }
        @try {
            NSMutableDictionary *log = [(NSDictionary *)entry mutableCopy];
            NSString *url = [log[@"url"] isKindOfClass: [NSString class]] ? log[@"url"] : nil;
            if ([self isURLBlacklisted: url blacklist: blacklist]) {
                continue;
            }
            if (url != nil && keys.count > 0) {
                log[@"url"] = [self redactQueryOfURL: url keys: keys];
            }

            if ([log[@"request"] isKindOfClass: [NSDictionary class]]) {
                NSMutableDictionary *request = [log[@"request"] mutableCopy];
                NSString *contentType = [self headerValue: @"content-type" inHeaders: request[@"headers"]];
                if ([request[@"headers"] isKindOfClass: [NSDictionary class]]) {
                    request[@"headers"] = [self redactHeaders: request[@"headers"] keys: keys];
                }
                if (request[@"payload"] != nil) {
                    request[@"payload"] = [self redactBody: request[@"payload"] contentType: contentType keys: keys paths: paths];
                }
                log[@"request"] = request;
            }

            if ([log[@"response"] isKindOfClass: [NSDictionary class]]) {
                NSMutableDictionary *response = [log[@"response"] mutableCopy];
                NSString *contentType = [self headerValue: @"content-type" inHeaders: response[@"headers"]];
                if (contentType == nil && [response[@"contentType"] isKindOfClass: [NSString class]]) {
                    contentType = response[@"contentType"];
                }
                if ([response[@"headers"] isKindOfClass: [NSDictionary class]]) {
                    response[@"headers"] = [self redactHeaders: response[@"headers"] keys: keys];
                }
                if (response[@"responseText"] != nil) {
                    response[@"responseText"] = [self redactBody: response[@"responseText"] contentType: contentType keys: keys paths: paths];
                }
                log[@"response"] = response;
            }

            [result addObject: log];
        } @catch (NSException *exception) {
            // An entry that cannot be sanitized is dropped rather than sent unredacted.
        }
    }

    return result;
}

#pragma mark - Headers

+ (NSString *)headerValue:(NSString *)name inHeaders:(id)headers {
    if (![headers isKindOfClass: [NSDictionary class]]) {
        return nil;
    }
    for (id key in (NSDictionary *)headers) {
        if ([key isKindOfClass: [NSString class]] && [(NSString *)key caseInsensitiveCompare: name] == NSOrderedSame) {
            id value = ((NSDictionary *)headers)[key];
            if ([value isKindOfClass: [NSString class]]) {
                return value;
            }
            if ([value isKindOfClass: [NSArray class]] && [[(NSArray *)value firstObject] isKindOfClass: [NSString class]]) {
                return [(NSArray *)value firstObject];
            }
        }
    }
    return nil;
}

+ (NSDictionary *)redactHeaders:(NSDictionary *)headers keys:(NSSet<NSString *> *)keys {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (id key in headers) {
        if (![key isKindOfClass: [NSString class]]) {
            continue;
        }
        NSString *lowercaseKey = [(NSString *)key lowercaseString];
        if ([keys containsObject: lowercaseKey]) {
            continue;
        }
        result[key] = [[self maskedHeaders] containsObject: lowercaseKey] ? kGleapRedactedValue : headers[key];
    }
    return result;
}

#pragma mark - Bodies

+ (id)redactBody:(id)body contentType:(NSString *)contentType keys:(NSSet<NSString *> *)keys paths:(NSArray<NSArray<NSString *> *> *)paths {
    if (keys.count == 0 || body == nil) {
        return body;
    }

    if ([body isKindOfClass: [NSDictionary class]] || [body isKindOfClass: [NSArray class]]) {
        // Wrapper SDKs may hand over already parsed bodies.
        if (![NSJSONSerialization isValidJSONObject: body]) {
            return body;
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject: body options: 0 error: nil];
        id copy = data ? [NSJSONSerialization JSONObjectWithData: data options: NSJSONReadingMutableContainers error: nil] : nil;
        if (copy == nil) {
            return body;
        }
        [self removeKeys: keys paths: paths fromJSONObject: copy];
        return copy;
    }

    if (![body isKindOfClass: [NSString class]]) {
        return body;
    }

    NSString *text = (NSString *)body;
    NSString *trimmed = [text stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed hasPrefix: @"{"] || [trimmed hasPrefix: @"["]) {
        NSData *data = [trimmed dataUsingEncoding: NSUTF8StringEncoding];
        id json = data ? [NSJSONSerialization JSONObjectWithData: data options: NSJSONReadingMutableContainers error: nil] : nil;
        if (json == nil) {
            // Not JSON after all (e.g. truncated): leave it as it is.
            return text;
        }
        if (![self removeKeys: keys paths: paths fromJSONObject: json]) {
            return text;
        }
        NSData *output = [NSJSONSerialization dataWithJSONObject: json options: NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes error: nil];
        NSString *outputString = output ? [[NSString alloc] initWithData: output encoding: NSUTF8StringEncoding] : nil;
        return outputString ?: text;
    }

    BOOL isFormContentType = [contentType isKindOfClass: [NSString class]] && [[contentType lowercaseString] containsString: @"x-www-form-urlencoded"];
    if (isFormContentType || [self looksLikeFormBody: text]) {
        return [self redactFormString: text keys: keys];
    }

    return text;
}

// Removes ignored keys at any depth and along dotted paths. Returns YES when something was removed.
+ (BOOL)removeKeys:(NSSet<NSString *> *)keys paths:(NSArray<NSArray<NSString *> *> *)paths fromJSONObject:(id)json {
    BOOL changed = [self removeKeys: keys fromJSONObject: json depth: 0];
    for (NSArray<NSString *> *path in paths) {
        changed = [self removePath: path index: 0 fromJSONObject: json depth: 0] || changed;
    }
    return changed;
}

+ (BOOL)removeKeys:(NSSet<NSString *> *)keys fromJSONObject:(id)json depth:(NSInteger)depth {
    if (depth > kGleapMaxRedactionDepth) {
        return NO;
    }
    BOOL changed = NO;
    if ([json isKindOfClass: [NSMutableDictionary class]]) {
        NSMutableDictionary *dictionary = (NSMutableDictionary *)json;
        for (id key in [dictionary allKeys]) {
            if ([key isKindOfClass: [NSString class]] && [keys containsObject: [(NSString *)key lowercaseString]]) {
                [dictionary removeObjectForKey: key];
                changed = YES;
            } else {
                changed = [self removeKeys: keys fromJSONObject: dictionary[key] depth: depth + 1] || changed;
            }
        }
    } else if ([json isKindOfClass: [NSMutableArray class]]) {
        for (id item in (NSMutableArray *)json) {
            changed = [self removeKeys: keys fromJSONObject: item depth: depth + 1] || changed;
        }
    }
    return changed;
}

+ (BOOL)removePath:(NSArray<NSString *> *)path index:(NSUInteger)index fromJSONObject:(id)json depth:(NSInteger)depth {
    if (index >= path.count || depth > kGleapMaxRedactionDepth) {
        return NO;
    }
    BOOL changed = NO;
    if ([json isKindOfClass: [NSMutableArray class]]) {
        // Arrays are transparent: "items.token" applies to every item.
        for (id item in (NSMutableArray *)json) {
            changed = [self removePath: path index: index fromJSONObject: item depth: depth + 1] || changed;
        }
    } else if ([json isKindOfClass: [NSMutableDictionary class]]) {
        NSMutableDictionary *dictionary = (NSMutableDictionary *)json;
        NSString *segment = path[index];
        for (id key in [dictionary allKeys]) {
            if (![key isKindOfClass: [NSString class]] || ![[(NSString *)key lowercaseString] isEqualToString: segment]) {
                continue;
            }
            if (index == path.count - 1) {
                [dictionary removeObjectForKey: key];
                changed = YES;
            } else {
                changed = [self removePath: path index: index + 1 fromJSONObject: dictionary[key] depth: depth + 1] || changed;
            }
        }
    }
    return changed;
}

+ (BOOL)looksLikeFormBody:(NSString *)text {
    if (text.length == 0 || text.length > 200000) {
        return NO;
    }
    static NSRegularExpression *formExpression = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formExpression = [NSRegularExpression regularExpressionWithPattern: @"^[^=&\\s]+=[^&\\s]*(&[^=&\\s]+=[^&\\s]*)*$" options: 0 error: nil];
    });
    return [formExpression numberOfMatchesInString: text options: 0 range: NSMakeRange(0, text.length)] > 0;
}

+ (NSString *)redactFormString:(NSString *)text keys:(NSSet<NSString *> *)keys {
    NSArray *pairs = [text componentsSeparatedByString: @"&"];
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity: pairs.count];
    BOOL changed = NO;
    for (NSString *pair in pairs) {
        NSString *name = [[pair componentsSeparatedByString: @"="] firstObject] ?: @"";
        NSString *decodedName = [[name stringByReplacingOccurrencesOfString: @"+" withString: @" "] stringByRemovingPercentEncoding] ?: name;
        if (name.length > 0 && [keys containsObject: [decodedName lowercaseString]]) {
            changed = YES;
            continue;
        }
        [kept addObject: pair];
    }
    return changed ? [kept componentsJoinedByString: @"&"] : text;
}

+ (NSString *)redactQueryOfURL:(NSString *)url keys:(NSSet<NSString *> *)keys {
    NSRange queryStart = [url rangeOfString: @"?"];
    if (queryStart.location == NSNotFound) {
        return url;
    }
    NSString *base = [url substringToIndex: queryStart.location];
    NSString *rest = [url substringFromIndex: queryStart.location + 1];
    NSString *fragment = @"";
    NSRange fragmentStart = [rest rangeOfString: @"#"];
    if (fragmentStart.location != NSNotFound) {
        fragment = [rest substringFromIndex: fragmentStart.location];
        rest = [rest substringToIndex: fragmentStart.location];
    }
    NSString *query = [self redactFormString: rest keys: keys];
    if ([query isEqualToString: rest]) {
        return url;
    }
    return [NSString stringWithFormat: @"%@%@%@%@", base, query.length > 0 ? @"?" : @"", query, fragment];
}

@end
