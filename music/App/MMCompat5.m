// MMCompat5.m — iOS 5: Kurzschreibweise für Listen/Wörterbücher (dict[@"k"], arr[0]) nachrüsten.
// Der Compiler übersetzt sie in Methoden, die es erst ab iOS 6 gibt; fehlen sie, werden sie beim Start ergänzt.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static id dictGet(NSDictionary *self, SEL _cmd, id key) { return [self objectForKey:key]; }
static void dictSet(NSMutableDictionary *self, SEL _cmd, id obj, id key) { if (obj) [self setObject:obj forKey:key]; else [self removeObjectForKey:key]; }
static id arrayGet(NSArray *self, SEL _cmd, NSUInteger i) { return [self objectAtIndex:i]; }
static void arraySet(NSMutableArray *self, SEL _cmd, id obj, NSUInteger i) { if (i == self.count) [self addObject:obj]; else [self replaceObjectAtIndex:i withObject:obj]; }
static void addIfMissing(Class c, SEL sel, IMP imp, const char *types) { if (![c instancesRespondToSelector:sel]) class_addMethod(c, sel, imp, types); }

@interface MMCompat5 : NSObject
@end
@implementation MMCompat5
+ (void)load {
    addIfMissing([NSDictionary class], @selector(objectForKeyedSubscript:), (IMP)dictGet, "@@:@");
    addIfMissing([NSMutableDictionary class], @selector(setObject:forKeyedSubscript:), (IMP)dictSet, "v@:@@");
    addIfMissing([NSArray class], @selector(objectAtIndexedSubscript:), (IMP)arrayGet, "@@:I");
    addIfMissing([NSMutableArray class], @selector(setObject:atIndexedSubscript:), (IMP)arraySet, "v@:@I");
}
@end
