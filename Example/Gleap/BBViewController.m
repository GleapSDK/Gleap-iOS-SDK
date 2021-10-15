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

- (IBAction)performAuth:(id)sender {
    GleapUserProperty *userSession = [[GleapUserProperty alloc] init];
    userSession.name = @"Lukas";
    userSession.email = @"lukas@boehlerbrothers.com";
    [Gleap identifyUserWith: @"1234" andData: userSession];
}

- (IBAction)sendSilentBugReport:(id)sender {
    [Gleap sendSilentBugReportWith: @"Sneaky bug report..." andSeverity: LOW];
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

    [Gleap logEvent: @"Demo opened"];
    
    [Gleap logEvent: @"Sample event with data" withData: @{
        @"userId": @"1242",
        @"name": @"Isabella",
        @"skillLevel": @"🤩"
    }];
    
    NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent: [NSString stringWithFormat: @"%.0f.%@", [NSDate timeIntervalSinceReferenceDate] * 1000.0, @"txt"]];
    [@"XOXO" writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [Gleap addAttachmentWithPath: filePath];
    
    [Gleap addAttachmentWithData: [@"Sample data" dataUsingEncoding:NSASCIIStringEncoding] andName: @"file.txt"];
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
