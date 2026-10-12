#import "SpotTheme.h"
static UIColor* rgb(int r,int g,int b){ return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1]; }
@implementation SpotTheme
+ (UIColor *)bg    { return rgb(18,18,18); }
+ (UIColor *)bar   { return rgb(24,24,24); }
+ (UIColor *)card  { return rgb(40,40,40); }
+ (UIColor *)green { return rgb(29,185,84); }
+ (UIColor *)ink   { return [UIColor whiteColor]; }
+ (UIColor *)muted { return rgb(179,179,179); }
+ (UIColor *)faint { return rgb(114,114,114); }
+ (UIColor *)line  { return rgb(42,42,42); }
+ (UIFont *)h1  { return [UIFont boldSystemFontOfSize:22]; }
+ (UIFont *)h2  { return [UIFont boldSystemFontOfSize:17]; }
+ (UIFont *)body{ return [UIFont systemFontOfSize:15]; }
+ (UIFont *)sub { return [UIFont systemFontOfSize:13]; }
+ (UIFont *)tab { return [UIFont systemFontOfSize:10]; }

// Echtes Spotify-Logo: grüner Kreis + drei schwarze Schallwellen (nach oben gewölbt).
// Eigenes Zeichen der App: grüner Kreis mit Puls-Linie (kein Spotify-Logo – Markenrecht).
+ (UIImage *)logo:(CGFloat)s {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s,s),NO,0);
    [[self green] setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0,0,s,s)] fill];
    UIBezierPath*p=[UIBezierPath bezierPath]; p.lineWidth=s*0.075; p.lineCapStyle=kCGLineCapRound; p.lineJoinStyle=kCGLineJoinRound;
    CGFloat y=s/2, pts[7][2]={{0.06,0},{0.33,0},{0.41,-0.18},{0.52,0.21},{0.6,-0.08},{0.65,0},{0.94,0}};
    [p moveToPoint:CGPointMake(s*pts[0][0],y)];
    for(int i=1;i<7;i++) [p addLineToPoint:CGPointMake(s*pts[i][0],y+s*pts[i][1])];
    [[UIColor colorWithRed:0.055 green:0.055 blue:0.063 alpha:1] setStroke]; [p stroke];
    UIImage*img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img;
}
@end
