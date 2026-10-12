// SpotTheme.h — Farben & Fonts im Spotify-Look (dunkel, grüner Akzent).
#import <UIKit/UIKit.h>
@interface SpotTheme : NSObject
+ (UIColor *)bg;        // 121212
+ (UIColor *)bar;       // 181818 (Leisten)
+ (UIColor *)card;      // 282828
+ (UIColor *)green;     // 1DB954
+ (UIColor *)ink;       // weiß
+ (UIColor *)muted;     // b3b3b3
+ (UIColor *)faint;     // 727272
+ (UIColor *)line;      // 2a2a2a
+ (UIFont *)h1;         // 22 bold
+ (UIFont *)h2;         // 17 semibold
+ (UIFont *)body;       // 15
+ (UIFont *)sub;        // 13 (muted)
+ (UIFont *)tab;        // 10
+ (UIImage *)logo:(CGFloat)size;
// Text mit Buchstabenabstand (iOS 6+); unter iOS 5 normaler Text in gleicher Schrift und Farbe
+ (void)spaced:(UILabel *)label text:(NSString *)text font:(UIFont *)font color:(UIColor *)color kern:(CGFloat)kern;   // eigenes Zeichen: grüner Kreis mit Puls-Linie
@end
