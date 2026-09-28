//
//  GleapInternal.h
//  Gleap
//
//  Helpers shared by the SDK's implementation files. Everything in Sources/Internal lies
//  outside the public header directory (Sources/ObjCSources), so neither Swift Package
//  Manager nor CocoaPods exposes it to apps. Never add a subfolder to Sources/ObjCSources:
//  SPM rejects a public header directory that contains directories next to Gleap.h.
//

#import <Foundation/Foundation.h>

// Internal classes and functions are not exported from the SDK binary.
#define GLEAP_INTERNAL __attribute__((visibility("hidden")))

NS_ASSUME_NONNULL_BEGIN

// NSNull for nil, so optional values can go into dictionary literals.
static inline id GleapObjectOrNull(id _Nullable object) {
    return object ?: [NSNull null];
}

NS_ASSUME_NONNULL_END
