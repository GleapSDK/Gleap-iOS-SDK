//
//  DemoViewController.m
//  Example
//
//  Created by Lukas Boehler on 15.12.21.
//

#import "DemoViewController.h"
@import Gleap;

@interface DemoViewController ()

@end

@implementation DemoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (IBAction)doIt:(id)sender {
    GleapUserProperty *userData = [[GleapUserProperty alloc] init];
    userData.name = @"Lukas";
    userData.email = @"lukas@gleap.io";
    [Gleap identifyUserWith: @"193828282" andData: userData];
}

- (IBAction)killAll:(id)sender {
    [Gleap startFeedbackFlow: @"bugreporting" showBackButton: NO];
}

@end
