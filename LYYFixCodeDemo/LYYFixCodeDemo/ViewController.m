//
//  ViewController.m
//  LYYFixCodeDemo
//
//  Created by 未央生 on 2022/6/21.
//

#import "ViewController.h"
#import "LYYFixCode.h"
#import "test.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSString *script = @"fixInstanceMethodReplace('test','run', function(instance, originInvocation, originArguments){var a = '你好';var item = runInstanceWith1Paramter(instance, 'valueForKey:', '_name');console.log(a + item);});";
    
    [LYYFixCode start];
    [LYYFixCode evaluateScript:script];
    
    
    test *t = [[test alloc] init];
    t.name = @"test001";
    [t run];
}


@end
