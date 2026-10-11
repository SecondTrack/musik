// Globaler Fix: Auf diesem iOS-6-Build bekommt jedes UILabel per Default einen
// weißen (opaken) Hintergrund -> weißer Text wird unsichtbar. Diese Kategorie
// swizzelt den designierten Initializer, sodass JEDES Label automatisch einen
// transparenten Hintergrund hat. +load wird vom ObjC-Runtime beim App-Start
// aufgerufen (Datei ist direkt ins App-Binary gelinkt, wird nicht gestrippt).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@implementation UILabel (MMClearBG)

- (instancetype)mm_initWithFrame:(CGRect)frame {
    UILabel *l = [self mm_initWithFrame:frame];   // ruft Original (nach Tausch)
    if (l) l.backgroundColor = [UIColor clearColor];
    return l;
}

+ (void)load {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method orig = class_getInstanceMethod(self, @selector(initWithFrame:));
        Method repl = class_getInstanceMethod(self, @selector(mm_initWithFrame:));
        if (orig && repl) method_exchangeImplementations(orig, repl);
    });
}

@end
