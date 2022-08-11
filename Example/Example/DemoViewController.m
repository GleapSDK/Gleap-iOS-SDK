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



- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.button.layer.cornerRadius = 25;
    
    [Gleap log: @"This is a test log."];
    [Gleap log: @"This is a test error." withLogLevel: ERROR];
    [Gleap log: @"This is a test info." withLogLevel: INFO];
    [Gleap log: @"This is a test warning." withLogLevel: WARNING];
    
    double delayInSeconds = 8.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void) {
        [Gleap close];
    });
}

- (IBAction)sendData:(id)sender {
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:[NSURL URLWithString:@"https://www.physics.leidenuniv.nl/json/news.php"]];
    
    __block NSDictionary *json;
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               json = [NSJSONSerialization JSONObjectWithData:data
                                                                      options:0
                                                                        error:nil];
                               NSLog(@"Async JSON: %@", json);
                           }];
}

@end
