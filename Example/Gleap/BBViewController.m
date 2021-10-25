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
    
    [self getDataFrom: @"https://run.mocky.io/v3/80b451d5-97bc-401f-b33e-da43592eac3c"];
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

- (void) getDataFrom:(NSString *)url {
    NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString: url]];
    [urlRequest setHTTPMethod:@"GET"];
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:urlRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
      if (httpResponse.statusCode == 200) {
        NSError *parseError = nil;
        NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        NSLog(@"The response is - %@",responseDictionary);
      } else {
        NSLog(@"Error");
      }
    }];
    [dataTask resume];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
