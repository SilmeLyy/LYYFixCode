//
//  LYYFixCode.m
//  LYYFixCodeDemo
//
//  Created by 未央生 on 2022/6/21.
//

#import "LYYFixCode.h"
#if __has_include (<Aspects/Aspects.h>)
#import <Aspects/Aspects.h>
#else
#import "Aspects.h"
#endif
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, LYYFixValueType) {
    LYYFixValueTypeUnknown = 0,
    LYYFixValueTypeVoid,
    LYYFixValueTypeObject,
    LYYFixValueTypeStruct,
    LYYFixValueTypeChar,             // char
    LYYFixValueTypeUnsignedChar,     // unsigned char
    LYYFixValueTypeShort,            // short
    LYYFixValueTypeUnsignedShort,    // unsigned short
    LYYFixValueTypeInt,              // int
    LYYFixValueTypeUnsignedInt,      // unsigned int
    LYYFixValueTypeLong,             // long
    LYYFixValueTypeUnsignedLong,     // unsigned long
    LYYFixValueTypeLongLong,         // long long
    LYYFixValueTypeUnsignedLongLong, // unsigned long long
    LYYFixValueTypeFloat,            // float
    LYYFixValueTypeDouble,           // double
    LYYFixValueTypeBOOL,             // BOOL
    LYYFixValueTypeSelector,         // Selector
};

static NSObject *_nilObj;

static NSString *extractStructName(NSString *typeEncodeString)
{
    NSArray *array = [typeEncodeString componentsSeparatedByString:@"="];
    NSString *typeString = array[0];
    int firstValidIndex = 0;
    for (int i = 0; i< typeString.length; i++) {
        char c = [typeString characterAtIndex:i];
        if (c == '{' || c=='_') {
            firstValidIndex++;
        }else {
            break;
        }
    }
    return [typeString substringFromIndex:firstValidIndex];
}

static id formatJSToOC(JSValue *jsval)
{
    id obj = [jsval toObject];
    if (!obj || [obj isKindOfClass:[NSNull class]]) return _nilObj;
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *newArr = [[NSMutableArray alloc] init];
        for (int i = 0; i < [(NSArray*)obj count]; i ++) {
            [newArr addObject:formatJSToOC(jsval[i])];
        }
        return newArr;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        if (obj[@"__obj"]) {
            id ocObj = [obj objectForKey:@"__obj"];
            return ocObj;
        }
        NSMutableDictionary *newDict = [[NSMutableDictionary alloc] init];
        for (NSString *key in [obj allKeys]) {
            [newDict setObject:formatJSToOC(jsval[key]) forKey:key];
        }
        return newDict;
    }
    return obj;
}

@interface LYYFixCode()

@property (nonatomic, strong) NSMutableArray<AspectToken> *aspectTokens;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *aspectInstance;

@end

@implementation LYYFixCode

- (instancetype)init
{
    self = [super init];
    if (self) {
        _aspectTokens = [[NSMutableArray<AspectToken> alloc] init];
        _aspectInstance = [[NSMutableDictionary alloc] init];
    }
    return self;
}

+ (LYYFixCode *)sharedInstance
{
    static LYYFixCode *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    
    return sharedInstance;
}

+ (JSContext *)context
{
    static JSContext *_context;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _context = [[JSContext alloc] init];
        [_context setExceptionHandler:^(JSContext *context, JSValue *value) {
            NSLog(@"Oops FixKit Error: %@", value);
        }];
    });
    return _context;
}

+ (void)evaluateScript:(NSString *)javascriptString
{
    [[self context] evaluateScript:javascriptString];
}

+ (BOOL)cleanAll
{
    for (id<AspectToken> token in [LYYFixCode sharedInstance].aspectTokens) {
        if ([token conformsToProtocol:@protocol(AspectToken)]) {
            BOOL isRemove = [token remove];
            // 如果有一个没有移除就停止移除操作
            if (!isRemove) {
                return NO;
            }
        }
    }
    // 清除存储的数组
    [[LYYFixCode sharedInstance].aspectTokens removeAllObjects];
    [[LYYFixCode sharedInstance].aspectInstance removeAllObjects];
    return YES;
}

+ (void)_fixWithMethod:(BOOL)isClassMethod aspectionOptions:(AspectOptions)option instanceName:(NSString *)instanceName selectorName:(NSString *)selectorName fixImpl:(JSValue *)fixImpl {
    Class klass = NSClassFromString(instanceName);
    if (isClassMethod) {
        klass = object_getClass(klass);
    }
    SEL sel = NSSelectorFromString(selectorName);
    NSError *error = nil;
    id<AspectToken> token = [klass aspect_hookSelector:sel withOptions:option usingBlock:^(id<AspectInfo> aspectInfo){
        NSString *instanceKey = [NSString stringWithFormat:@"%@_%@", instanceName, selectorName];
        [[LYYFixCode sharedInstance].aspectInstance setObject:aspectInfo.instance forKey:instanceKey];
        
        [fixImpl callWithArguments:@[instanceKey, aspectInfo.originalInvocation, aspectInfo.arguments]];
        
        [[LYYFixCode sharedInstance].aspectInstance removeObjectForKey:instanceKey];
    } error:&error];
    
    //储存token
    if (token && !error) {
        [[LYYFixCode sharedInstance].aspectTokens addObject:token];
    }
}

+ (id)_realInstance:(id)instance
{
    id realInstance = [[LYYFixCode sharedInstance].aspectInstance objectForKey:instance];
    if (realInstance == nil) {
        realInstance = instance;
    }
    return realInstance;
}

+ (LYYFixValueType)convertValueType:(const char *)valueType
{
    //如果没有返回值，也就是消息声明为void，那么returnValue=nil
    // 参照js * patch
    if(!strcmp(valueType, @encode(void))){
        return LYYFixValueTypeVoid;
    }
    
    switch (valueType[0] == 'r' ? valueType[1] : valueType[0]) {
            // id
        case '@':
            return LYYFixValueTypeObject;
            break;
            // struct
        case '{':
            return LYYFixValueTypeStruct;
            break;
            // 基础数据类型
        case 'c':
            return LYYFixValueTypeChar;
            break;
        case 'C':
            return LYYFixValueTypeUnsignedChar;
            break;
        case 's':
            return LYYFixValueTypeShort;
            break;
        case 'S':
            return LYYFixValueTypeUnsignedShort;
            break;
        case 'i':
            return LYYFixValueTypeInt;
            break;
        case 'I':
            return LYYFixValueTypeUnsignedInt;
            break;
        case 'l':
            return LYYFixValueTypeLong;
            break;
        case 'L':
            return LYYFixValueTypeUnsignedLong;
            break;
        case 'q':
            return LYYFixValueTypeLongLong;
            break;
        case 'Q':
            return LYYFixValueTypeUnsignedLongLong;
            break;
        case 'f':
            return LYYFixValueTypeFloat;
            break;
        case 'd':
            return LYYFixValueTypeDouble;
            break;
        case 'B':
            return LYYFixValueTypeBOOL;
            break;
        case ':':
            return LYYFixValueTypeSelector;
            break;
        default:
            return LYYFixValueTypeUnknown;
            break;
    }
}

+ (void)setInvocation:(NSInvocation *)invocation argument:(id)obj index:(NSInteger)index
{
    NSInteger argumentsCount = [invocation.methodSignature numberOfArguments];
    if (index >= argumentsCount) {
        return;
    }
    const char *argumentType = [invocation.methodSignature getArgumentTypeAtIndex:index];
    
    LYYFixValueType valueType = [self convertValueType:argumentType];
    
    if (valueType == LYYFixValueTypeObject) {
        __unsafe_unretained id argumentValue = obj;
        [invocation setArgument:&argumentValue atIndex:index];
    } else {
        id valObj = obj;
        switch (argumentType[0] == 'r' ? argumentType[1] : argumentType[0]) {
#define FK_CALL_ARG_CASE(_typeString, _type, _selector) \
case _typeString: {                              \
_type value = [valObj _selector];                     \
[invocation setArgument:&value atIndex:index];\
break; \
}
                
                FK_CALL_ARG_CASE('c', char, charValue)
                FK_CALL_ARG_CASE('C', unsigned char, unsignedCharValue)
                FK_CALL_ARG_CASE('s', short, shortValue)
                FK_CALL_ARG_CASE('S', unsigned short, unsignedShortValue)
                FK_CALL_ARG_CASE('i', int, intValue)
                FK_CALL_ARG_CASE('I', unsigned int, unsignedIntValue)
                FK_CALL_ARG_CASE('l', long, longValue)
                FK_CALL_ARG_CASE('L', unsigned long, unsignedLongValue)
                FK_CALL_ARG_CASE('q', long long, longLongValue)
                FK_CALL_ARG_CASE('Q', unsigned long long, unsignedLongLongValue)
                FK_CALL_ARG_CASE('f', float, floatValue)
                FK_CALL_ARG_CASE('d', double, doubleValue)
                FK_CALL_ARG_CASE('B', BOOL, boolValue)
            case ':': {
                if ([valObj isKindOfClass:NSString.class]) {
                    SEL selector = NSSelectorFromString(valObj);
                    [invocation setArgument:&selector atIndex:index];
                }
                break;
            }
            case '{': {
                NSString *typeString = extractStructName([NSString stringWithUTF8String:argumentType]);
                JSValue *val = [JSValue valueWithObject:obj inContext:[self context]];
#define FK_CALL_ARG_STRUCT(_type, _methodName) \
if ([typeString rangeOfString:@#_type].location != NSNotFound) {    \
_type value = [val _methodName];  \
[invocation setArgument:&value atIndex:index];  \
}
                FK_CALL_ARG_STRUCT(CGRect, toRect)
                FK_CALL_ARG_STRUCT(CGPoint, toPoint)
                FK_CALL_ARG_STRUCT(CGSize, toSize)
                FK_CALL_ARG_STRUCT(NSRange, toRange)
                break;
            }
            default: {
                if (valObj == _nilObj ||
                    ([valObj isKindOfClass:[NSNumber class]] && strcmp([valObj objCType], "c") == 0 && ![valObj boolValue])) {
                    valObj = nil;
                    [invocation setArgument:&valObj atIndex:index];
                    break;
                } else {
                    break;
                }
            }
        }
    }
}

// 最多只支持3个参数
+ (void)setInvocation:(NSInvocation *)invocation argumentsObj1:(id)obj1 obj2:(id)obj2 obj3:(id)obj3 obj4:(id)obj4 obj5:(id)obj5
{
    NSInteger argumentsCount = [invocation.methodSignature numberOfArguments];
    // 方法签名的 0是self 1是_cmd
    for (int i = 2; i < argumentsCount; i++) {
        id tempObject = nil;
        if (i == 2) {
            tempObject = obj1;
        } else if (i == 3) {
            tempObject = obj2;
        } else if (i == 4) {
            tempObject = obj3;
        } else if (i == 5) {
            tempObject = obj4;
        } else if (i == 6) {
            tempObject = obj5;
        }
        [self setInvocation:invocation argument:tempObject index:i];
    }
}

+ (id)getInvocationReturnVaule:(NSInvocation *)invocation
{
    __unsafe_unretained id returnValue = nil;
    const char *returnType = invocation.methodSignature.methodReturnType;
    LYYFixValueType valueType = [self convertValueType:returnType];
    if (valueType == LYYFixValueTypeVoid) {
        return returnValue;
    } else if (valueType == LYYFixValueTypeObject) {
        [invocation getReturnValue:&returnValue];
        return returnValue;
    } else {
        switch (returnType[0] == 'r' ? returnType[1] : returnType[0]) {
#define FK_CALL_RET_CASE(_typeString, _type) \
case _typeString: {                              \
_type tempResultSet; \
[invocation getReturnValue:&tempResultSet];\
returnValue = @(tempResultSet); \
break; \
}
                
                FK_CALL_RET_CASE('c', char)
                FK_CALL_RET_CASE('C', unsigned char)
                FK_CALL_RET_CASE('s', short)
                FK_CALL_RET_CASE('S', unsigned short)
                FK_CALL_RET_CASE('i', int)
                FK_CALL_RET_CASE('I', unsigned int)
                FK_CALL_RET_CASE('l', long)
                FK_CALL_RET_CASE('L', unsigned long)
                FK_CALL_RET_CASE('q', long long)
                FK_CALL_RET_CASE('Q', unsigned long long)
                FK_CALL_RET_CASE('f', float)
                FK_CALL_RET_CASE('d', double)
                FK_CALL_RET_CASE('B', BOOL)
            case '{': {
                NSString *typeString = extractStructName([NSString stringWithUTF8String:returnType]);
#define FK_CALL_RET_STRUCT(_type, _methodName) \
if ([typeString rangeOfString:@#_type].location != NSNotFound) {    \
_type result;   \
[invocation getReturnValue:&result];    \
return [JSValue _methodName:result inContext:[self context]];    \
}
                FK_CALL_RET_STRUCT(CGRect, valueWithRect)
                FK_CALL_RET_STRUCT(CGPoint, valueWithPoint)
                FK_CALL_RET_STRUCT(CGSize, valueWithSize)
                FK_CALL_RET_STRUCT(NSRange, valueWithRange)
                break;
            }
            default:
                break;
        }
        
        return returnValue;
    }
}

+ (void)setInvocation:(NSInvocation *)invocation returnValue:(JSValue *)jsval
{
    const char *returnType = invocation.methodSignature.methodReturnType;
    
    switch (returnType[0] == 'r' ? returnType[1] : returnType[0]) {
#define FK_FWD_RET_CASE_RET(_typeChar, _type, _retCode)   \
case _typeChar : { \
_retCode \
[invocation setReturnValue:&ret];\
break;  \
}
            
#define FK_FWD_RET_CASE(_typeChar, _type, _typeSelector)   \
FK_FWD_RET_CASE_RET(_typeChar, _type, _type ret = [[jsval toObject] _typeSelector];)   \

#define FK_FWD_RET_CODE_ID \
id __autoreleasing ret = formatJSToOC(jsval); \
if (ret == _nilObj ||   \
([ret isKindOfClass:[NSNumber class]] && strcmp([ret objCType], "c") == 0 && ![ret boolValue])) ret = nil;  \

            
            FK_FWD_RET_CASE_RET('@', id, FK_FWD_RET_CODE_ID)
            
            FK_FWD_RET_CASE('c', char, charValue)
            FK_FWD_RET_CASE('C', unsigned char, unsignedCharValue)
            FK_FWD_RET_CASE('s', short, shortValue)
            FK_FWD_RET_CASE('S', unsigned short, unsignedShortValue)
            FK_FWD_RET_CASE('i', int, intValue)
            FK_FWD_RET_CASE('I', unsigned int, unsignedIntValue)
            FK_FWD_RET_CASE('l', long, longValue)
            FK_FWD_RET_CASE('L', unsigned long, unsignedLongValue)
            FK_FWD_RET_CASE('q', long long, longLongValue)
            FK_FWD_RET_CASE('Q', unsigned long long, unsignedLongLongValue)
            FK_FWD_RET_CASE('f', float, floatValue)
            FK_FWD_RET_CASE('d', double, doubleValue)
            FK_FWD_RET_CASE('B', BOOL, boolValue)
        case '{': {
            NSString *typeString = extractStructName([NSString stringWithUTF8String:returnType]);
#define FK_FWD_RET_STRUCT(_type, _funcSuffix) \
if ([typeString rangeOfString:@#_type].location != NSNotFound) {    \
_type ret = [jsval _funcSuffix]; \
[invocation setReturnValue:&ret];\
break;  \
}
            FK_FWD_RET_STRUCT(CGRect, toRect)
            FK_FWD_RET_STRUCT(CGPoint, toPoint)
            FK_FWD_RET_STRUCT(CGSize, toSize)
            FK_FWD_RET_STRUCT(NSRange, toRange)
        }
        default: {
            break;
        }
    }
}

+ (id)_runClassWithClassName:(NSString *)className selector:(NSString *)selector  argumentsList:(NSArray *)argumentsList
{
    Class klass = NSClassFromString(className);
    SEL tSelector = NSSelectorFromString(selector);
    if (!klass || !tSelector) {
        return nil;
    }
    if (![klass respondsToSelector:tSelector]) {
        return nil;
    }
    NSMethodSignature *methodSignature = [klass methodSignatureForSelector:tSelector];
    if (!methodSignature) {
        return nil;
    }
    if (!methodSignature) {
        return nil;
    }
    // 实例invocation
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
    [invocation setTarget:klass];
    [invocation setSelector:tSelector];
    
    // 设置参数
    // 方法签名的 0是self 1是_cmd
    for (int i = 0; i < argumentsList.count; i++) {
        id tempObject = argumentsList[i];
        [self setInvocation:invocation argument:tempObject index:i + 2];
    }
    [invocation invoke];
    
    //获得返回值类型
    id returnValue = [self getInvocationReturnVaule:invocation];
    return returnValue;
}

+ (id)_runClassWithClassName:(NSString *)className selector:(NSString *)selector obj1:(id)obj1 obj2:(id)obj2 obj3:(id)obj3 obj4:(id)obj4 obj5:(id)obj5 {
    Class klass = NSClassFromString(className);
    SEL tSelector = NSSelectorFromString(selector);
    if (!klass || !tSelector) {
        return nil;
    }
    if (![klass respondsToSelector:tSelector]) {
        return nil;
    }
    
    NSMethodSignature *methodSignature = [klass methodSignatureForSelector:tSelector];
    if (methodSignature) {
        // 对参数retain
        NSMutableArray *argumentsList = [NSMutableArray array];
        if (obj1) {
            [argumentsList addObject:obj1];
        }
        if (obj2) {
            [argumentsList addObject:obj2];
        }
        if (obj3) {
            [argumentsList addObject:obj3];
        }
        if (obj4) {
            [argumentsList addObject:obj4];
        }
        if (obj5) {
            [argumentsList addObject:obj5];
        }
        
        // 实例invocation
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
        [invocation setTarget:klass];
        [invocation setSelector:tSelector];
        
        // 设置参数
        [self setInvocation:invocation argumentsObj1:obj1 obj2:obj2 obj3:obj3 obj4:obj4 obj5:obj5];
        [invocation invoke];
        
        // 释放参数retain
        [argumentsList removeAllObjects];
        argumentsList = nil;
        
        //获得返回值类型
        id returnValue = [self getInvocationReturnVaule:invocation];
        return returnValue;
    }
    return nil;
}

#pragma mark - instance

+ (id)_runInstanceWithInstance:(id)instance selector:(NSString *)selector argumentsList:(NSArray *)argumentsList
{
    SEL tSelector = NSSelectorFromString(selector);
    if (!tSelector) {
        return nil;
    }
    if (![instance respondsToSelector:tSelector]) {
        return nil;
    }
    NSMethodSignature *methodSignature = [instance methodSignatureForSelector:tSelector];
    if (!methodSignature) {
        return nil;
    }
    // 实例invocation
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
    [invocation setTarget:instance];
    [invocation setSelector:tSelector];
    
    // 设置参数
    // 方法签名的 0是self 1是_cmd
    for (int i = 0; i < argumentsList.count; i++) {
        id tempObject = argumentsList[i];
        [self setInvocation:invocation argument:tempObject index:i + 2];
    }
    [invocation invoke];
    
    //获得返回值类型
    id returnValue = [self getInvocationReturnVaule:invocation];
    return returnValue;
}

+ (id)_runInstanceWithInstance:(id)instance selector:(NSString *)selector obj1:(id)obj1 obj2:(id)obj2 obj3:(id)obj3 obj4:(id)obj4 obj5:(id)obj5 {
    SEL tSelector = NSSelectorFromString(selector);
    if (!tSelector) {
        return nil;
    }
    if (![instance respondsToSelector:tSelector]) {
        return nil;
    }
    NSMethodSignature *methodSignature = [instance methodSignatureForSelector:tSelector];
    if (methodSignature) {
        // 对参数retain
        NSMutableArray *argumentsList = [NSMutableArray array];
        if (obj1) {
            [argumentsList addObject:obj1];
        }
        if (obj2) {
            [argumentsList addObject:obj2];
        }
        if (obj3) {
            [argumentsList addObject:obj3];
        }
        if (obj4) {
            [argumentsList addObject:obj4];
        }
        if (obj5) {
            [argumentsList addObject:obj5];
        }
        
        // 实例invocation
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
        [invocation setTarget:instance];
        [invocation setSelector:tSelector];
        
        // 设置参数
        [self setInvocation:invocation argumentsObj1:obj1 obj2:obj2 obj3:obj3 obj4:obj4 obj5:obj5];
        [invocation invoke];
        
        // 释放参数retain
        [argumentsList removeAllObjects];
        argumentsList = nil;
        
        //获得返回值类型
        id returnValue = [self getInvocationReturnVaule:invocation];
        return returnValue;
    }
    return nil;
}

#pragma mark - public

+ (void)start
{
    _nilObj = [[NSObject alloc] init];
    [self context][@"fixInstanceMethodBefore"] = ^(NSString *instanceName, NSString *selectorName, JSValue *fixImpl) {
        [self _fixWithMethod:NO aspectionOptions:AspectPositionBefore instanceName:instanceName selectorName:selectorName fixImpl:fixImpl];
    };
    
    [self context][@"fixInstanceMethodReplace"] = ^(NSString *instanceName, NSString *selectorName, JSValue *fixImpl) {
        [self _fixWithMethod:NO aspectionOptions:AspectPositionInstead instanceName:instanceName selectorName:selectorName fixImpl:fixImpl];
    };
    
    [self context][@"fixInstanceMethodAfter"] = ^(NSString *instanceName, NSString *selectorName, JSValue *fixImpl) {
        [self _fixWithMethod:NO aspectionOptions:AspectPositionAfter instanceName:instanceName selectorName:selectorName fixImpl:fixImpl];
    };
    
    [self context][@"fixClassMethodBefore"] = ^(NSString *instanceName, NSString *selectorName, JSValue *fixImpl) {
        [self _fixWithMethod:YES aspectionOptions:AspectPositionBefore instanceName:instanceName selectorName:selectorName fixImpl:fixImpl];
    };
    
    [self context][@"fixClassMethodReplace"] = ^(NSString *instanceName, NSString *selectorName, JSValue *fixImpl) {
        [self _fixWithMethod:YES aspectionOptions:AspectPositionInstead instanceName:instanceName selectorName:selectorName fixImpl:fixImpl];
    };
    
    [self context][@"fixClassMethodAfter"] = ^(NSString *instanceName, NSString *selectorName, JSValue *fixImpl) {
        [self _fixWithMethod:YES aspectionOptions:AspectPositionAfter instanceName:instanceName selectorName:selectorName fixImpl:fixImpl];
    };
    
    [self context][@"runClassWithNoParamter"] = ^id(NSString *className, NSString *selectorName) {
        return [self _runClassWithClassName:className selector:selectorName obj1:nil obj2:nil obj3:nil obj4:nil obj5:nil];
    };
    
    [self context][@"runClassWith1Paramter"] = ^id(NSString *className, NSString *selectorName, id obj1) {
        return [self _runClassWithClassName:className selector:selectorName obj1:obj1 obj2:nil obj3:nil obj4:nil obj5:nil];
    };
    
    [self context][@"runClassWith2Paramters"] = ^id(NSString *className, NSString *selectorName, id obj1, id obj2) {
        return [self _runClassWithClassName:className selector:selectorName obj1:obj1 obj2:obj2 obj3:nil obj4:nil obj5:nil];
    };
    
    [self context][@"runClassWith3Paramters"] = ^id(NSString *className, NSString *selectorName, id obj1, id obj2, id obj3) {
        return [self _runClassWithClassName:className selector:selectorName obj1:obj1 obj2:obj2 obj3:obj3 obj4:nil obj5:nil];
    };
    
    [self context][@"runClassWith4Paramters"] = ^id(NSString *className, NSString *selectorName, id obj1, id obj2, id obj3, id obj4) {
        return [self _runClassWithClassName:className selector:selectorName obj1:obj1 obj2:obj2 obj3:obj3 obj4:obj4 obj5:nil];
    };
    
    [self context][@"runClassWith5Paramters"] = ^id(NSString *className, NSString *selectorName, id obj1, id obj2, id obj3, id obj4, id obj5) {
        return [self _runClassWithClassName:className selector:selectorName obj1:obj1 obj2:obj2 obj3:obj3 obj4:obj4 obj5:obj5];
    };
    
    [self context][@"runVoidClassWithNoParamter"] = ^(NSString *className, NSString *selectorName) {
        [self _runClassWithClassName:className selector:selectorName obj1:nil obj2:nil obj3:nil obj4:nil obj5:nil];
    };
    
    [self context][@"runVoidClassWith1Paramter"] = ^(NSString *className, NSString *selectorName, id obj1) {
        [self _runClassWithClassName:className selector:selectorName obj1:obj1 obj2:nil obj3:nil obj4:nil obj5:nil];
    };
    
    [self context][@"runVoidClassWith2Paramters"] = ^(NSString *className, NSString *selectorName, id obj1, id obj2) {
        [self _runClassWithClassName:className selector:selectorName obj1:obj1 obj2:obj2 obj3:nil obj4:nil obj5:nil];
    };
    
    [self context][@"runVoidClassWith3Paramters"] = ^(NSString *className, NSString *selectorName, id obj1, id obj2, id obj3) {
        [self _runClassWithClassName:className selector:selectorName obj1:obj1 obj2:obj2 obj3:obj3 obj4:nil obj5:nil];
    };
    
    [self context][@"runVoidClassWith4Paramters"] = ^(NSString *className, NSString *selectorName, id obj1, id obj2, id obj3, id obj4) {
        [self _runClassWithClassName:className selector:selectorName obj1:obj1 obj2:obj2 obj3:obj3 obj4:obj4 obj5:nil];
    };
    
    [self context][@"runVoidClassWith5Paramters"] = ^(NSString *className, NSString *selectorName, id obj1, id obj2, id obj3, id obj4, id obj5) {
        [self _runClassWithClassName:className selector:selectorName obj1:obj1 obj2:obj2 obj3:obj3 obj4:obj4 obj5:obj5];
    };
    
    [self context][@"runInstanceWithNoParamter"] = ^id(id instance, NSString *selectorName) {
        return [self _runInstanceWithInstance:[self _realInstance:instance] selector:selectorName obj1:nil obj2:nil obj3:nil obj4:nil obj5:nil];
    };
    
    [self context][@"runInstanceWith1Paramter"] = ^id(id instance, NSString *selectorName, id obj1) {
        return [self _runInstanceWithInstance:[self _realInstance:instance] selector:selectorName obj1:[self _realInstance:obj1] obj2:nil obj3:nil obj4:nil obj5:nil];
    };
    
    [self context][@"runInstanceWith2Paramters"] = ^id(id instance, NSString *selectorName, id obj1, id obj2) {
        return [self _runInstanceWithInstance:[self _realInstance:instance] selector:selectorName obj1:[self _realInstance:obj1] obj2:[self _realInstance:obj2] obj3:nil obj4:nil obj5:nil];
    };
    
    [self context][@"runInstanceWith3Paramters"] = ^id(id instance, NSString *selectorName, id obj1, id obj2, id obj3) {
        return [self _runInstanceWithInstance:[self _realInstance:instance] selector:selectorName obj1:[self _realInstance:obj1] obj2:[self _realInstance:obj2] obj3:[self _realInstance:obj3] obj4:nil obj5:nil];
    };
    
    [self context][@"runInstanceWith4Paramters"] = ^id(id instance, NSString *selectorName, id obj1, id obj2, id obj3, id obj4) {
        return [self _runInstanceWithInstance:[self _realInstance:instance] selector:selectorName obj1:[self _realInstance:obj1] obj2:[self _realInstance:obj2] obj3:[self _realInstance:obj3] obj4:[self _realInstance:obj4] obj5:nil];
    };
    
    [self context][@"runInstanceWith5Paramters"] = ^id(id instance, NSString *selectorName, id obj1, id obj2, id obj3, id obj4, id obj5) {
        return [self _runInstanceWithInstance:[self _realInstance:instance] selector:selectorName obj1:[self _realInstance:obj1] obj2:[self _realInstance:obj2] obj3:[self _realInstance:obj3] obj4:[self _realInstance:obj4] obj5:[self _realInstance:obj5]];
    };
    
    [self context][@"runVoidInstanceWithNoParamter"] = ^(id instance, NSString *selectorName) {
        [self _runInstanceWithInstance:[self _realInstance:instance] selector:selectorName obj1:nil obj2:nil obj3:nil obj4:nil obj5:nil];
    };
    
    [self context][@"runVoidInstanceWith1Paramter"] = ^(id instance, NSString *selectorName, id obj1) {
        [self _runInstanceWithInstance:[self _realInstance:instance] selector:selectorName obj1:[self _realInstance:obj1] obj2:nil obj3:nil obj4:nil obj5:nil];
    };
    
    [self context][@"runVoidInstanceWith2Paramters"] = ^(id instance, NSString *selectorName, id obj1, id obj2) {
        [self _runInstanceWithInstance:[self _realInstance:instance] selector:selectorName obj1:[self _realInstance:obj1] obj2:[self _realInstance:obj2] obj3:nil obj4:nil obj5:nil];
    };
    
    [self context][@"runVoidInstanceWith3Paramters"] = ^(id instance, NSString *selectorName, id obj1, id obj2, id obj3) {
        [self _runInstanceWithInstance:[self _realInstance:instance] selector:selectorName obj1:[self _realInstance:obj1] obj2:[self _realInstance:obj2] obj3:[self _realInstance:obj3] obj4:nil obj5:nil];
    };
    
    [self context][@"runVoidInstanceWith4Paramters"] = ^(id instance, NSString *selectorName, id obj1, id obj2, id obj3, id obj4) {
        [self _runInstanceWithInstance:[self _realInstance:instance] selector:selectorName obj1:[self _realInstance:obj1] obj2:[self _realInstance:obj2] obj3:[self _realInstance:obj3] obj4:[self _realInstance:obj4] obj5:nil];
    };
    
    [self context][@"runVoidInstanceWith5Paramters"] = ^(id instance, NSString *selectorName, id obj1, id obj2, id obj3, id obj4, id obj5) {
        [self _runInstanceWithInstance:[self _realInstance:instance] selector:selectorName obj1:[self _realInstance:obj1] obj2:[self _realInstance:obj2] obj3:[self _realInstance:obj3] obj4:[self _realInstance:obj4] obj5:[self _realInstance:obj5]];
    };
    
    [self context][@"runInvocation"] = ^(NSInvocation *invocation) {
        [invocation invoke];
    };
    
    // 新增runInvocationWithTagert和runInvocationSetArgumentAtIndex，方便调用原方法并对原方法的的的参数进行修改
    [self context][@"runInvocationWithTagert"] = ^(NSInvocation *invocation, id instance) {
        [invocation invokeWithTarget:[self _realInstance:instance]];
    };
    
    [self context][@"runInvocationSetArgumentAtIndex"] = ^(NSInvocation *invocation, id argument, id index) {
        if ([index isKindOfClass:[NSNumber class]]) {
            [self setInvocation:invocation argument:argument index:[(NSNumber *)index unsignedIntegerValue]];
            [invocation retainArguments];
        }
    };
    
    //新增runInvocationSetReturnValue方便调用原方法并对原方法的的的返回值进行修改
    
    [self context][@"runInvocationSetReturnValue"] = ^(NSInvocation *invocation, JSValue *jsval) {
        [self setInvocation:invocation returnValue:jsval];
        [invocation retainArguments];
    };
    
    [self context][@"runInvocationRetainArguments"] = ^(NSInvocation *invocation) {
        [invocation retainArguments];
    };
    
    // 实例一个Object
    [self context][@"runInitObjectWithClassName"] = ^id(NSString *className) {
        Class newClass = NSClassFromString(className);
        if (newClass) {
            return [[newClass alloc] init];
        }
        return nil;
    };
    
    //工具方法
    [self context][@"runSystemVersion"] = ^() {
        NSString *systemVersion = [UIDevice currentDevice].systemVersion;
        return systemVersion;
    };
    
//    [self context][@"runBigSystemVersion"] = ^() {
//        double bigSystemVersionValue = [UIDevice bigSystemVersion];
//        NSString *bigSystemVersion = [NSString stringWithFormat:@"%.1f", bigSystemVersionValue];
//        return bigSystemVersion;
//    };
    
//    [self context][@"runMachineModelName"] = ^() {
//        return [UIDevice currentDevice].machineModelName;
//    };
    
    [self context][@"runBundleShortVersion"] = ^() {
        return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    };
    
    [self context][@"runBundleVersion"] = ^() {
        return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    };
    
    //工具方法
    [self context][@"runIsKindOfClass"] = ^(id obj1, NSString *className) {
        return [[self _realInstance:obj1] isKindOfClass:NSClassFromString(className)];
    };
    
    [self context][@"runValueForKey"] = ^(id obj1, NSString *key) {
        return [[self _realInstance:obj1] valueForKey:[self _realInstance:key]];
    };
    
    [self context][@"runSetValueForKey"] = ^(id obj1, id value, NSString *key) {
        [[self _realInstance:obj1] setValue:[self _realInstance:value] forKey:[self _realInstance:key]];
    };
    
    // 获取真实instance的方法, 主要是针对self
    // 慎用，返回self将造成内存泄漏，除非重大crashBUG修复使用
    [self context][@"runReturnRealInstance"] = ^(id instance) {
        return [self _realInstance:instance];
    };
    
    //返回一个nil值
    [self context][@"runReturnNilValue"] = ^id() {
        return nil;
    };
    
    //是否实现sel方法
    [self context][@"responseToSelector"] = ^(id obj1, NSString *sel) {
        if ([self checkIsEmpty:sel]) {
            return NO;
        }
        return [[self _realInstance:obj1] respondsToSelector:NSSelectorFromString(sel)];
    };
    
    //实例对象调用方法，以数组形式支持多参
    [self context][@"runInstanceWithParamters"] = ^id(id instance, NSString *selectorName, NSArray *args) {
        return [self _runInstanceWithInstance:[self _realInstance:instance] selector:selectorName argumentsList:args];
    };
    
    // 类对象调用方法，以数组形式支持多参
    [self context][@"runClassWithParamters"] = ^id(NSString *className, NSString *selectorName, NSArray *args) {
        return [self _runClassWithClassName:className selector:selectorName argumentsList:args];
    };
    
    //以下方法将支持延迟执行和切换线程执行
    //delayTime延迟执行的时长 threadType: 0:不变 1:强制主线程 2:强制子线程
    [self context][@"runClassWith5ParamtersDelayWithThread"] = ^id(NSString *className, NSString *selectorName, NSString *delayTime, NSString *theardType, id obj1, id obj2, id obj3, id obj4, id obj5) {
        __block id result = nil;
        //延时执行
        CGFloat delayInSeconds = [delayTime floatValue];
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^{
            int type = [theardType intValue];
            switch (type) {
                case 0: { //不变
                    result = [self _runClassWithClassName:className selector:selectorName obj1:obj1 obj2:obj2 obj3:obj3 obj4:obj4 obj5:obj5];
                }
                    break;
                case 1: { //强制主线程
                    dispatch_async(dispatch_get_main_queue(), ^{
                        result = [self _runClassWithClassName:className selector:selectorName obj1:obj1 obj2:obj2 obj3:obj3 obj4:obj4 obj5:obj5];
                    });
                }
                    break;
                case 2: { //强制子线程
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        result = [self _runClassWithClassName:className selector:selectorName obj1:obj1 obj2:obj2 obj3:obj3 obj4:obj4 obj5:obj5];
                    });
                }
                    break;
                default:
                    break;
            }
        });
        return result;
    };
    
    [self context][@"runVoidClassWith5ParamtersDelayWithThread"] = ^(NSString *className, NSString *selectorName, NSString *delayTime, NSString *theardType, id obj1, id obj2, id obj3, id obj4, id obj5) {
        //延时执行
        CGFloat delayInSeconds = [delayTime floatValue];
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^{
            int type = [theardType intValue];
            switch (type) {
                case 0: { //不变
                    [self _runClassWithClassName:className selector:selectorName obj1:obj1 obj2:obj2 obj3:obj3 obj4:obj4 obj5:obj5];
                }
                    break;
                case 1: { //强制主线程
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self _runClassWithClassName:className selector:selectorName obj1:obj1 obj2:obj2 obj3:obj3 obj4:obj4 obj5:obj5];
                    });
                }
                    break;
                case 2: { //强制子线程
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        [self _runClassWithClassName:className selector:selectorName obj1:obj1 obj2:obj2 obj3:obj3 obj4:obj4 obj5:obj5];
                    });
                }
                    break;
                default:
                    break;
            }
        });
    };
    
    [self context][@"runInstanceWith5ParamtersDelayWithThread"] = ^id(id instance, NSString *selectorName, NSString *delayTime, NSString *theardType, id obj1, id obj2, id obj3, id obj4, id obj5) {
        //这里这么做，主要是防止内存泄漏和hook instance
        __weak id realInstance = [self _realInstance:instance];
        __weak id realObj1 = [self _realInstance:obj1];
        __weak id realObj2 = [self _realInstance:obj2];
        __weak id realObj3 = [self _realInstance:obj3];
        __weak id realObj4 = [self _realInstance:obj4];
        __weak id realObj5 = [self _realInstance:obj5];
        
        __block id result = nil;
        //延时执行
        CGFloat delayInSeconds = [delayTime floatValue];
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^{
            int type = [theardType intValue];
            switch (type) {
                case 0: { //不变
                    result = [self _runInstanceWithInstance:realInstance selector:selectorName obj1:realObj1 obj2:realObj2 obj3:realObj3 obj4:realObj4 obj5:realObj5];
                }
                    break;
                case 1: { //强制主线程
                    dispatch_async(dispatch_get_main_queue(), ^{
                        result = [self _runInstanceWithInstance:realInstance selector:selectorName obj1:realObj1 obj2:realObj2 obj3:realObj3 obj4:realObj4 obj5:realObj5];
                    });
                }
                    break;
                case 2: { //强制子线程
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        result = [self _runInstanceWithInstance:realInstance selector:selectorName obj1:realObj1 obj2:realObj2 obj3:realObj3 obj4:realObj4 obj5:realObj5];
                    });
                }
                    break;
                default:
                    break;
            }
        });
        return result;
    };
    
    [self context][@"runVoidInstanceWith5ParamtersDelayWithThread"] = ^(id instance, NSString *selectorName, NSString *delayTime, NSString *theardType, id obj1, id obj2, id obj3, id obj4, id obj5) {
        //这里这么做，主要是防止内存泄漏和hook instance
        __weak id realInstance = [self _realInstance:instance];
        __weak id realObj1 = [self _realInstance:obj1];
        __weak id realObj2 = [self _realInstance:obj2];
        __weak id realObj3 = [self _realInstance:obj3];
        __weak id realObj4 = [self _realInstance:obj4];
        __weak id realObj5 = [self _realInstance:obj5];
        
        //延时执行
        CGFloat delayInSeconds = [delayTime floatValue];
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^{
            int type = [theardType intValue];
            switch (type) {
                case 0: { //不变
                    [self _runInstanceWithInstance:realInstance selector:selectorName obj1:realObj1 obj2:realObj2 obj3:realObj3 obj4:realObj4 obj5:realObj5];
                }
                    break;
                case 1: { //强制主线程
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self _runInstanceWithInstance:realInstance selector:selectorName obj1:realObj1 obj2:realObj2 obj3:realObj3 obj4:realObj4 obj5:realObj5];
                    });
                }
                    break;
                case 2: { //强制子线程
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        [self _runInstanceWithInstance:realInstance selector:selectorName obj1:realObj1 obj2:realObj2 obj3:realObj3 obj4:realObj4 obj5:realObj5];
                    });
                }
                    break;
                default:
                    break;
            }
        });
    };
    
    // helper
    [[self context] evaluateScript:@"var console = {}"];
    [self context][@"console"][@"log"] = ^(id message) {
        NSLog(@"FixCode Javascript log: %@",message);
    };
}

+ (BOOL)checkIsEmpty:(id)value
{
    if (!value || value == [NSNull null]) {
        return YES;
    } else if ([value isKindOfClass:[NSString class]]) {
        NSString *tempStr = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([tempStr length] == 0 || [value isEqualToString:@"NULL"] || [value isEqualToString:@"null"] || [value isEqualToString:@"(null)"]) {
            return YES;
        }
    } else if ([value isKindOfClass:[NSData class]]) {
        return ([value respondsToSelector:@selector(length)] && [(NSData *)value length] == 0);
    } else if ([value isKindOfClass:[NSArray class]]) {
        return ([value respondsToSelector:@selector(count)] && [(NSArray *)value count] == 0);
    } else if ([value isKindOfClass:[NSDictionary class]]) {
        return ([value respondsToSelector:@selector(count)] && [(NSDictionary *)value count] == 0);
    }
    return NO;
}
@end
