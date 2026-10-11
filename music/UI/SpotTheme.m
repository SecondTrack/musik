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
// Original-Logo (Wikimedia "Spotify_logo_without_text.svg", viewBox 168x168), Pfad 1:1 übernommen.
// Die drei Wellen sind Aussparungen im grünen Kreis -> der Hintergrund scheint durch.
+ (UIImage *)logo:(CGFloat)s {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s,s),NO,0);
    CGFloat k=s/168.0;
    #define P(x,y) CGPointMake((x)*k,(y)*k)
    UIBezierPath*p=[UIBezierPath bezierPath];
    [p moveToPoint:P(83.996,0.277)];
    [p addCurveToPoint:P(0.253,84.019) controlPoint1:P(37.747,0.277) controlPoint2:P(0.253,37.770)];
    [p addCurveToPoint:P(83.996,167.760) controlPoint1:P(0.253,130.270) controlPoint2:P(37.747,167.760)];
    [p addCurveToPoint:P(167.740,84.019) controlPoint1:P(130.250,167.760) controlPoint2:P(167.740,130.270)];
    [p addCurveToPoint:P(83.995,0.281) controlPoint1:P(167.740,37.773) controlPoint2:P(130.250,0.281)];
    [p addLineToPoint:P(83.996,0.277)];
    [p closePath];
    [p moveToPoint:P(122.400,121.057)];
    [p addCurveToPoint:P(115.220,122.787) controlPoint1:P(120.900,123.517) controlPoint2:P(117.680,124.297)];
    [p addCurveToPoint:P(41.656,114.717) controlPoint1:P(95.558,110.777) controlPoint2:P(70.806,108.057)];
    [p addCurveToPoint:P(35.407,110.787) controlPoint1:P(38.847,115.357) controlPoint2:P(36.047,113.597)];
    [p addCurveToPoint:P(39.333,104.537) controlPoint1:P(34.764,107.977) controlPoint2:P(36.517,105.177)];
    [p addCurveToPoint:P(120.670,113.877) controlPoint1:P(71.233,97.246) controlPoint2:P(98.596,100.387)];
    [p addCurveToPoint:P(122.400,121.057) controlPoint1:P(123.130,115.387) controlPoint2:P(123.910,118.597)];
    [p closePath];
    [p moveToPoint:P(132.650,98.252)];
    [p addCurveToPoint:P(123.670,100.407) controlPoint1:P(130.760,101.327) controlPoint2:P(126.740,102.297)];
    [p addCurveToPoint:P(40.222,90.643) controlPoint1:P(101.160,86.568) controlPoint2:P(66.847,82.561)];
    [p addCurveToPoint:P(32.074,86.293) controlPoint1:P(36.769,91.686) controlPoint2:P(33.122,89.740)];
    [p addCurveToPoint:P(36.428,78.150) controlPoint1:P(31.034,82.840) controlPoint2:P(32.981,79.200)];
    [p addCurveToPoint:P(130.500,89.277) controlPoint1:P(66.841,68.922) controlPoint2:P(104.650,73.392)];
    [p addCurveToPoint:P(132.650,98.253) controlPoint1:P(133.570,91.167) controlPoint2:P(134.540,95.187)];
    [p addLineToPoint:P(132.650,98.252)];
    [p closePath];
    [p moveToPoint:P(133.530,74.508)];
    [p addCurveToPoint:P(36.241,64.824) controlPoint1:P(106.540,58.477) controlPoint2:P(62.010,57.003)];
    [p addCurveToPoint:P(26.473,59.605) controlPoint1:P(32.103,66.079) controlPoint2:P(27.727,63.743)];
    [p addCurveToPoint:P(31.694,49.834) controlPoint1:P(25.219,55.465) controlPoint2:P(27.553,51.092)];
    [p addCurveToPoint:P(141.524,61.036) controlPoint1:P(61.275,40.854) controlPoint2:P(110.450,42.589)];
    [p addCurveToPoint:P(144.264,71.769) controlPoint1:P(145.254,63.245) controlPoint2:P(146.474,68.052)];
    [p addCurveToPoint:P(133.534,74.508) controlPoint1:P(142.064,75.491) controlPoint2:P(137.244,76.718)];
    [p closePath];
    #undef P
    p.usesEvenOddFillRule=YES;
    [[UIColor colorWithRed:0x1E/255.0 green:0xD7/255.0 blue:0x60/255.0 alpha:1] setFill];
    [p fill];
    UIImage*img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    return img;
}
@end
