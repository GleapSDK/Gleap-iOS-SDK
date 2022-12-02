//
//  DemoViewController.m
//  Example
//
//  Created by Lukas Boehler on 15.12.21.
//

#import "DemoViewController.h"
@import Gleap;

/*inline void NSLog(NSString *format, ...) {
    va_list arg_list;
    va_start(arg_list, format);
    [Gleap log: @"Test"];
    va_end(arg_list);
}*/

@interface DemoViewController ()
@property (weak, nonatomic) IBOutlet UIButton *button;

@end

@implementation DemoViewController

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.button.layer.cornerRadius = 25;
    
    [Gleap log: @"This is a test log."];
    [Gleap log: @"This is a test error." withLogLevel: ERROR];
    [Gleap log: @"This is a test info." withLogLevel: INFO];
    [Gleap log: @"This is a test warning." withLogLevel: WARNING];
}

- (IBAction)sendData:(id)sender {
    [Gleap openHelpCenterArticle: @"9"];
}

@end
