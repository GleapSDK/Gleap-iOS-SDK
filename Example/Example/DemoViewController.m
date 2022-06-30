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

@end

@implementation DemoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    [Gleap log: @"This is a test log."];
    [Gleap log: @"This is a test error." withLogLevel: ERROR];
    [Gleap log: @"This is a test info." withLogLevel: INFO];
    [Gleap log: @"This is a test warning." withLogLevel: WARNING];
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
