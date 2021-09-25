//
//  BBViewController.m
//  Gleap
//
//  Created by Lukas Böhler on 06/12/2019.
//  Copyright (c) 2019 Lukas Böhler. All rights reserved.
//

#import "BBViewController.h"
#import "BBAFURLSessionManager.h"

@interface BBViewController ()

@end

@implementation BBViewController

- (void)customActionCalled:(NSString *)customAction {
    NSLog(@"%@", customAction);
}

- (void)bugWillBeSent {
    NSLog(@"SENT BUG");
}

- (IBAction)performAuth:(id)sender {
    GleapUserSession *userSession = [[GleapUserSession alloc] init];
    userSession.userId = @"1";
    userSession.userHash = @"db5897fe20d33d8072babc477655eba5240e606cbde86deaa0c17e34eaef6201";
    userSession.name = @"Franz";
    userSession.email = @"lukas@boehlerbrothers.com";
    
    [Gleap updateUserSessionWithData: userSession];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    self.title = @"Home";
    
    Gleap.sharedInstance.delegate = self;
    
    [Gleap attachCustomData: @{ @"key" : @"value", @"key2" : @"value2"}];
    
    [Gleap removeCustomDataForKey: @"email"];
    
    [Gleap setCustomData: @"lukas@bugbattle.io" forKey: @"email"];

    [Gleap logEvent: @"User signed in"];
    
    [Gleap logEvent: @"User signed in" withData: @{
        @"userId": @"1242",
        @"name": @"Isabella",
        @"skillLevel": @"🤩"
    }];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self getDataFrom: @"https://run.mocky.io/v3/9cc59b27-14ed-4866-bd42-f8de47ac3d16"];
        [self getDataFrom: @"https://run.mocky.io/v3/9cc59b27-14ed-4866-bd42-f8de47ac3d12"];
        [self getDataFrom: @"https://run.mocky.io/v3/9cc59b27-14ed-4866-bd42-f8de47ac3d15"];
    });
}

- (NSString *) getDataFrom:(NSString *)url{
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setHTTPMethod:@"GET"];
    [request setURL:[NSURL URLWithString:url]];

    NSError *error = nil;
    NSHTTPURLResponse *responseCode = nil;

    NSData *oResponseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&responseCode error:&error];

    if([responseCode statusCode] != 200){
        NSLog(@"Error getting %@, HTTP status code %i", url, [responseCode statusCode]);
        return nil;
    }

    return [[NSString alloc] initWithData:oResponseData encoding:NSUTF8StringEncoding];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
