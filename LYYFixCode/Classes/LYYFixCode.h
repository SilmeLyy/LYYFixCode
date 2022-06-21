//
//  LYYFixCode.h
//  LYYFixCodeDemo
//
//  Created by 未央生 on 2022/6/21.
//

#import <Foundation/Foundation.h>
#import <Aspects/Aspects.h>
#import <objc/runtime.h>
#import <JavaScriptCore/JavaScriptCore.h>

NS_ASSUME_NONNULL_BEGIN

@interface LYYFixCode : NSObject

+ (void)start;

+ (void)evaluateScript:(NSString *)javascriptString;

+ (BOOL)cleanAll;

@end

NS_ASSUME_NONNULL_END
