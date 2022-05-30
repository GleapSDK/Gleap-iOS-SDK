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

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
