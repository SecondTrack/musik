#import "MMArtPlayer.h"
#import <QuartzCore/QuartzCore.h>
#import "SpotTheme.h"
#import "MMAudio.h"
#import "MMSpotify.h"
#import "MMRootController.h"
#import "MMCovers.h"
#import "MMSheet.h"
#import "MeshL10n.h"

#define NPTS 64

static UIFont *thin(CGFloat s){ return [UIFont fontWithName:@"HelveticaNeue-UltraLight" size:s]?:[UIFont fontWithName:@"HelveticaNeue-Light" size:s]?:[UIFont systemFontOfSize:s]; }
static UIFont *light(CGFloat s){ return [UIFont fontWithName:@"HelveticaNeue-Light" size:s]?:[UIFont systemFontOfSize:s]; }
static NSString *fmt(double s){ if(s<0)s=0; int m=(int)s/60, sec=(int)s%60; return [NSString stringWithFormat:@"%d:%02d",m,sec]; }
static CGFloat lum(UIColor*c){ CGFloat r=0,g=0,b=0,a=0; [c getRed:&r green:&g blue:&b alpha:&a]; return 0.299*r+0.587*g+0.114*b; }
static UIColor *scale(UIColor*c,CGFloat f){ CGFloat r=0,g=0,b=0,a=0; [c getRed:&r green:&g blue:&b alpha:&a]; return [UIColor colorWithRed:MIN(1,r*f) green:MIN(1,g*f) blue:MIN(1,b*f) alpha:1]; }

// Farben aus dem Cover: [Akzent (kräftig, hell genug), Mittelton, dunkle Variante, Leinwand]
static NSArray *palette(UIImage *img){
    const int N=12; unsigned char px[N*N*4]; memset(px,0,sizeof(px));
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(px,N,N,8,N*4,cs,(CGBitmapInfo)kCGImageAlphaPremultipliedLast); CGColorSpaceRelease(cs);
    if(!ctx) return nil;
    CGContextDrawImage(ctx,CGRectMake(0,0,N,N),img.CGImage); CGContextRelease(ctx);
    double ar=0,ag=0,ab=0; CGFloat bestS=-1; UIColor*vivid=nil;
    for(int i=0;i<N*N;i++){
        CGFloat r=px[i*4]/255.0,g=px[i*4+1]/255.0,b=px[i*4+2]/255.0; ar+=r; ag+=g; ab+=b;
        CGFloat mx=MAX(r,MAX(g,b)), mn=MIN(r,MIN(g,b)), s=mx>0?(mx-mn)/mx:0, score=s*mx;
        if(mx>0.25 && score>bestS){ bestS=score; vivid=[UIColor colorWithRed:r green:g blue:b alpha:1]; }
    }
    UIColor*avg=[UIColor colorWithRed:ar/(N*N) green:ag/(N*N) blue:ab/(N*N) alpha:1];
    CGFloat h=0,s=0,v=0,a=0;
    if(!vivid || ![vivid getHue:&h saturation:&s brightness:&v alpha:&a] || s<0.18) vivid=[SpotTheme green];   // graues Cover -> Grün
    else vivid=[UIColor colorWithHue:h saturation:MAX(s,0.45) brightness:MAX(v,0.8) alpha:1];
    return @[vivid, avg, scale(vivid,0.45), scale(avg,0.28)];
}

@interface MMArtPlayer () <UIGestureRecognizerDelegate>
@end

@implementation MMArtPlayer {
    NSString *_style;
    CADisplayLink *_link;
    UIColor *_acc, *_mid, *_dark, *_canvas;
    UILabel *_title, *_artist, *_time, *_hint;
    UIActivityIndicatorView *_spin;
    float _lvl, _bass, _wave[NPTS];
    BOOL _seeking, _seekMode; double _seekFrac;
    CGFloat W, H;
    // Orbit
    UIImageView *_disc; CAShapeLayer *_ring, *_arc, *_halo; CALayer *_dot; CGPoint _c; CGFloat _R, _rot;
    // Farbfeld
    CALayer *_f[3], *_hair; CGFloat _top, _bot;
    // Linie
    CAShapeLayer *_lineA, *_lineB; CALayer *_head; CGFloat _midY;
}

+ (NSArray *)styles { return @[@"standard",@"orbit",@"field",@"line"]; }
+ (NSString *)style { NSString*s=[[NSUserDefaults standardUserDefaults] stringForKey:@"playerStyle"]; return [[self styles] containsObject:s]?s:@"standard"; }
+ (void)setStyle:(NSString *)style { [[NSUserDefaults standardUserDefaults] setObject:style forKey:@"playerStyle"]; [[NSUserDefaults standardUserDefaults] synchronize]; }
+ (NSString *)nameOf:(NSString *)s {
    if([s isEqualToString:@"orbit"]) return L(@"Orbit");
    if([s isEqualToString:@"field"]) return L(@"Color field");
    if([s isEqualToString:@"line"])  return L(@"Line");
    return L(@"Standard");
}

#pragma mark - Aufbau

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor=[UIColor blackColor]; self.view.clipsToBounds=YES;
    W=self.view.bounds.size.width; H=self.view.bounds.size.height;
    _style=[MMArtPlayer style];
    _acc=[SpotTheme green]; _mid=[UIColor colorWithWhite:0.35 alpha:1]; _dark=[UIColor colorWithWhite:0.18 alpha:1]; _canvas=[UIColor colorWithWhite:0.07 alpha:1];

    if([_style isEqualToString:@"orbit"]) [self buildOrbit];
    else if([_style isEqualToString:@"field"]) [self buildField];
    else [self buildLine];

    // Schließen-Hinweis oben (dezent), Ladeanzeige, Bedien-Hinweis
    UIButton*down=[UIButton buttonWithType:UIButtonTypeCustom]; down.frame=CGRectMake(W/2-30,0,60,30);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(60,30),NO,0);
    UIBezierPath*ch=[UIBezierPath bezierPath]; ch.lineWidth=1.5; ch.lineCapStyle=kCGLineCapRound;
    [ch moveToPoint:CGPointMake(22,11)]; [ch addLineToPoint:CGPointMake(30,16)]; [ch addLineToPoint:CGPointMake(38,11)];
    [[UIColor colorWithWhite:1 alpha:0.45] setStroke]; [ch stroke];
    [down setImage:UIGraphicsGetImageFromCurrentImageContext() forState:UIControlStateNormal]; UIGraphicsEndImageContext();
    [down addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:down];

    _spin=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spin.hidesWhenStopped=YES; _spin.center=CGPointMake(W/2,H-58); [self.view addSubview:_spin];

    NSUserDefaults*u=[NSUserDefaults standardUserDefaults]; NSInteger seen=[u integerForKey:@"artHint"];
    if(seen<3){
        [u setInteger:seen+1 forKey:@"artHint"];
        _hint=[[UILabel alloc] initWithFrame:CGRectMake(10,H-26,W-20,16)]; _hint.backgroundColor=[UIColor clearColor];
        _hint.text=L(@"Tap: pause · Swipe: skip · Hold: menu"); _hint.font=light(11); _hint.textAlignment=NSTextAlignmentCenter;
        _hint.textColor=[UIColor colorWithWhite:1 alpha:0.6]; _hint.shadowColor=[UIColor colorWithWhite:0 alpha:0.5]; _hint.shadowOffset=CGSizeMake(0,1);
        [self.view addSubview:_hint];
    }

    UITapGestureRecognizer*tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
    UIPanGestureRecognizer*pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
    UILongPressGestureRecognizer*lp=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)]; lp.minimumPressDuration=0.5;
    for(UIGestureRecognizer*g in @[tap,pan,lp]){ g.delegate=self; [self.view addGestureRecognizer:g]; }

    [self updateTitle:self.trackTitle artist:self.trackArtist cover:self.coverURL];
}

- (UILabel *)label:(CGRect)r font:(UIFont *)f color:(UIColor *)c align:(NSTextAlignment)al {
    UILabel*l=[[UILabel alloc] initWithFrame:r]; l.backgroundColor=[UIColor clearColor]; l.font=f; l.textColor=c; l.textAlignment=al;
    [self.view addSubview:l]; return l;
}

// Orbit: drehende Cover-Scheibe, Ring = Fortschritt, Lichthof atmet mit dem Pegel
- (void)buildOrbit {
    _c=CGPointMake(W/2,H*0.42); _R=122; CGFloat dr=100;
    _halo=[CAShapeLayer layer]; _halo.frame=CGRectMake(_c.x-dr,_c.y-dr,dr*2,dr*2);
    _halo.path=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0,0,dr*2,dr*2)].CGPath; _halo.fillColor=[_acc colorWithAlphaComponent:0.22].CGColor;
    [self.view.layer addSublayer:_halo];
    _disc=[[UIImageView alloc] initWithFrame:CGRectMake(_c.x-dr,_c.y-dr,dr*2,dr*2)]; _disc.backgroundColor=[SpotTheme card];
    _disc.contentMode=UIViewContentModeScaleAspectFill; _disc.layer.cornerRadius=dr; _disc.layer.masksToBounds=YES; [self.view addSubview:_disc];
    CAShapeLayer*hole=[CAShapeLayer layer]; hole.path=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(_c.x-7,_c.y-7,14,14)].CGPath;
    hole.fillColor=[UIColor blackColor].CGColor; hole.strokeColor=[UIColor colorWithWhite:1 alpha:0.25].CGColor; hole.lineWidth=1; [self.view.layer addSublayer:hole];
    UIBezierPath*circ=[UIBezierPath bezierPathWithArcCenter:_c radius:_R startAngle:-M_PI_2 endAngle:1.5*M_PI clockwise:YES];
    _ring=[CAShapeLayer layer]; _ring.path=circ.CGPath; _ring.fillColor=nil; _ring.strokeColor=[UIColor colorWithWhite:1 alpha:0.14].CGColor; _ring.lineWidth=1;
    [self.view.layer addSublayer:_ring];
    _arc=[CAShapeLayer layer]; _arc.path=circ.CGPath; _arc.fillColor=nil; _arc.strokeColor=_acc.CGColor; _arc.lineWidth=2.5; _arc.lineCap=kCALineCapRound; _arc.strokeEnd=0;
    [self.view.layer addSublayer:_arc];
    _dot=[CALayer layer]; _dot.bounds=CGRectMake(0,0,10,10); _dot.cornerRadius=5; _dot.backgroundColor=[UIColor whiteColor].CGColor; [self.view.layer addSublayer:_dot];
    CGFloat ty=_c.y+_R+30;
    _title=[self label:CGRectMake(24,ty,W-48,26) font:light(20) color:[UIColor whiteColor] align:NSTextAlignmentCenter];
    _artist=[self label:CGRectMake(24,ty+28,W-48,16) font:light(11) color:[UIColor colorWithWhite:1 alpha:0.5] align:NSTextAlignmentCenter];
    _time=[self label:CGRectMake(24,ty+54,W-48,14) font:light(10) color:[UIColor colorWithWhite:1 alpha:0.35] align:NSTextAlignmentCenter];
}

// Farbfeld: drei weiche Farbflächen aus dem Cover (à la Rothko), Haarlinie wandert = Fortschritt
- (void)buildField {
    _top=22; _bot=H-74;
    for(int i=0;i<3;i++){
        _f[i]=[CALayer layer]; _f[i].shadowOpacity=0.9; _f[i].shadowRadius=7; _f[i].shadowOffset=CGSizeZero; _f[i].cornerRadius=2;
        [self.view.layer addSublayer:_f[i]];
    }
    _hair=[CALayer layer]; _hair.backgroundColor=[UIColor colorWithWhite:0 alpha:0.6].CGColor; [self.view.layer addSublayer:_hair];
    _title=[self label:CGRectMake(20,_bot+14,W-90,20) font:[UIFont boldSystemFontOfSize:15] color:[UIColor whiteColor] align:NSTextAlignmentLeft];
    _artist=[self label:CGRectMake(20,_bot+34,W-90,16) font:light(12) color:[UIColor colorWithWhite:1 alpha:0.6] align:NSTextAlignmentLeft];
    _time=[self label:CGRectMake(W-80,_bot+16,60,16) font:light(11) color:[UIColor colorWithWhite:1 alpha:0.5] align:NSTextAlignmentRight];
    [self colorize:NO];
}

// Linie: eine einzige Linie = Live-Wellenform; gespielter Teil in Farbe
- (void)buildLine {
    _midY=H*0.58;
    _title=[self label:CGRectMake(20,44,W-40,132) font:thin(36) color:[UIColor whiteColor] align:NSTextAlignmentLeft];
    _title.numberOfLines=3; _title.lineBreakMode=NSLineBreakByTruncatingTail;
    _artist=[self label:CGRectMake(22,180,W-44,18) font:light(13) color:_acc align:NSTextAlignmentLeft];
    _lineB=[CAShapeLayer layer]; _lineB.fillColor=nil; _lineB.strokeColor=[UIColor colorWithWhite:1 alpha:0.35].CGColor; _lineB.lineWidth=1.5; _lineB.lineJoin=kCALineJoinRound;
    _lineA=[CAShapeLayer layer]; _lineA.fillColor=nil; _lineA.strokeColor=_acc.CGColor; _lineA.lineWidth=2; _lineA.lineJoin=kCALineJoinRound; _lineA.lineCap=kCALineCapRound;
    [self.view.layer addSublayer:_lineB]; [self.view.layer addSublayer:_lineA];
    _head=[CALayer layer]; _head.bounds=CGRectMake(0,0,7,7); _head.cornerRadius=3.5; _head.backgroundColor=[UIColor whiteColor].CGColor; [self.view.layer addSublayer:_head];
    _time=[self label:CGRectMake(20,H-90,W-40,14) font:light(11) color:[UIColor colorWithWhite:1 alpha:0.4] align:NSTextAlignmentLeft];
}

#pragma mark - Inhalt

- (void)updateTitle:(NSString *)title artist:(NSString *)artist cover:(NSString *)cover {
    self.trackTitle=title; self.trackArtist=artist; self.coverURL=cover;
    NSString*t=title.length?title:@"—";
    if([_style isEqualToString:@"line"]) t=[t lowercaseString];
    _title.text=t;
    if([_style isEqualToString:@"orbit"]){
        NSString*a=[artist?:@"" uppercaseString];
        _artist.attributedText=[[NSAttributedString alloc] initWithString:a attributes:@{NSKernAttributeName:@2.5,NSFontAttributeName:light(11),NSForegroundColorAttributeName:[UIColor colorWithWhite:1 alpha:0.5]}];
        _artist.textAlignment=NSTextAlignmentCenter;
    } else _artist.text=artist?:@"";
    if([_style isEqualToString:@"line"]){   // Titelhöhe anpassen, Künstler direkt darunter
        CGSize s=[_title.text sizeWithFont:_title.font constrainedToSize:CGSizeMake(W-40,132) lineBreakMode:NSLineBreakByTruncatingTail];
        _title.frame=CGRectMake(20,44,W-40,s.height); _artist.frame=CGRectMake(22,44+s.height+6,W-44,18);
    }
    [self loadCover];
}

- (void)loadCover {
    NSString*u=self.coverURL; if(!u.length) return;
    UIImage*img=[MMCovers cached:u];
    if(img){ [self applyCover:img animated:NO]; return; }
    [MMCovers load:u completion:^(UIImage*im){ if(im && [u isEqualToString:self.coverURL]) [self applyCover:im animated:YES]; }];
}

- (void)applyCover:(UIImage *)img animated:(BOOL)anim {
    NSArray*p=palette(img);
    if(p){ _acc=p[0]; _mid=p[1]; _dark=p[2]; _canvas=p[3]; }
    if(_disc){
        if(anim) [UIView transitionWithView:_disc duration:0.4 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{ _disc.image=img; } completion:nil];
        else _disc.image=img;
    }
    [self colorize:anim];
}

- (void)colorize:(BOOL)anim {
    [CATransaction begin]; [CATransaction setAnimationDuration:anim?0.8:0]; [CATransaction setDisableActions:!anim];
    _arc.strokeColor=_acc.CGColor; _halo.fillColor=[_acc colorWithAlphaComponent:0.22].CGColor;
    _lineA.strokeColor=_acc.CGColor;
    if(_f[0]){
        NSArray*cols=@[_acc,_mid,_dark];
        for(int i=0;i<3;i++){ _f[i].backgroundColor=[cols[i] CGColor]; _f[i].shadowColor=[cols[i] CGColor]; }
        self.view.backgroundColor=_canvas;
        BOOL lightCanvas=lum(_canvas)>0.55;
        _title.textColor=lightCanvas?[UIColor blackColor]:[UIColor whiteColor];
        _artist.textColor=[_title.textColor colorWithAlphaComponent:0.6]; _time.textColor=[_title.textColor colorWithAlphaComponent:0.5];
    }
    [CATransaction commit];
    if(_lineA) _artist.textColor=_acc;
}

#pragma mark - Laufende Anzeige

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _link=[CADisplayLink displayLinkWithTarget:self selector:@selector(frame:)]; _link.frameInterval=2;   // 30 fps reicht und schont den A4
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    if(_hint) [UIView animateWithDuration:0.8 delay:3.5 options:0 animations:^{ _hint.alpha=0; } completion:nil];
}
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [_link invalidate]; _link=nil; }
- (void)tick {}   // Timer des Standard-Players hier ungenutzt

- (void)frame:(CADisplayLink *)l {
    double cur=[MMAudio currentTime], dur=[MMAudio duration];
    BOOL loading=[MMSpotify isLoading];
    if(loading){ cur=0; if(!_spin.isAnimating)[_spin startAnimating]; } else [_spin stopAnimating];
    double frac=_seeking?_seekFrac:(dur>0?cur/dur:0); if(frac<0)frac=0; if(frac>1)frac=1;
    if(_seeking) cur=frac*dur;

    float lv=0,bs=0,wv[NPTS]; memset(wv,0,sizeof(wv));
    BOOL live=[MMAudio visual:&lv bass:&bs wave:wv];
    float k=live?0.35f:0.12f;
    _lvl+=(lv*2.2f-_lvl)*k; _bass+=(bs*3.0f-_bass)*k;
    if(_lvl>1)_lvl=1; if(_bass>1)_bass=1;
    for(int i=0;i<NPTS;i++) _wave[i]+=(wv[i]-_wave[i])*(live?0.5f:0.15f);

    [CATransaction begin]; [CATransaction setDisableActions:YES];
    if(_disc){
        if([MMAudio isPlaying]) _rot+=2*M_PI/(24.0*30.0);   // eine Umdrehung in 24 s
        _disc.transform=CGAffineTransformMakeRotation(_rot);
        CGFloat hs=1.0+_lvl*0.28; _halo.transform=CATransform3DMakeScale(hs,hs,1);
        _arc.strokeEnd=frac;
        CGFloat ang=-M_PI_2+frac*2*M_PI; _dot.position=CGPointMake(_c.x+_R*cos(ang),_c.y+_R*sin(ang));
        _time.text=dur>0?[NSString stringWithFormat:@"%@  /  %@",fmt(cur),fmt(dur)]:@"";
    } else if(_f[0]){
        CGFloat h=_bot-_top, g=10, b=_bass*26;
        CGFloat h0=h*0.44+b, h1=h*0.31-b*0.6, h2=h-h0-h1-2*g;
        CGFloat ys[3]={_top,_top+h0+g,_top+h0+h1+2*g}, hs[3]={h0,h1,h2};
        for(int i=0;i<3;i++){ CGRect r=CGRectMake(18,ys[i],W-36,hs[i]); _f[i].frame=r; _f[i].shadowPath=[UIBezierPath bezierPathWithRect:CGRectMake(0,0,r.size.width,r.size.height)].CGPath; }
        CGFloat hy=_top+frac*h; _hair.frame=CGRectMake(10,floor(hy),W-20,_seeking?2:1);
        _time.text=dur>0?fmt(cur):@"";
    } else if(_lineA){
        CGFloat x0=18, x1=W-18, px=x0+(x1-x0)*frac, amp=110;
        UIBezierPath*a=[UIBezierPath bezierPath], *bp=[UIBezierPath bezierPath];
        CGPoint prev=CGPointZero; BOOL split=NO;
        for(int i=0;i<NPTS;i++){
            float v=_wave[i]; if(v>1)v=1; if(v<-1)v=-1;
            CGFloat env=sin(M_PI*i/(NPTS-1));          // Enden ruhig, Mitte bewegt
            CGPoint p=CGPointMake(x0+(x1-x0)*i/(NPTS-1), _midY-v*amp*env);
            if(i==0){ [(px>p.x?a:bp) moveToPoint:p]; if(px<=p.x) split=YES; }
            else if(!split && p.x>px){                   // Übergang: Punkt auf der Linie bei px
                CGFloat t=(px-prev.x)/(p.x-prev.x); CGPoint m=CGPointMake(px,prev.y+(p.y-prev.y)*t);
                [a addLineToPoint:m]; [bp moveToPoint:m]; [bp addLineToPoint:p]; split=YES; _head.position=m;
            } else [(split?bp:a) addLineToPoint:p];
            prev=p;
        }
        if(!split) _head.position=prev; else if(px<=x0) _head.position=CGPointMake(x0,_midY);
        _lineA.path=a.CGPath; _lineB.path=bp.CGPath;
        _time.text=dur>0?[NSString stringWithFormat:@"%@ / %@",fmt(cur),fmt(dur)]:@"";
    }
    [CATransaction commit];
    _title.alpha=loading?(0.45+0.35*sin(CACurrentMediaTime()*4)):1;
}

#pragma mark - Bedienung

// Berührungen im Menü-Panel oder auf Knöpfen gehören nicht dem Player
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {
    for(UIView*v=t.view; v && v!=self.view; v=v.superview) if(v.tag==MMSheetTag || [v isKindOfClass:[UIControl class]]) return NO;
    return YES;
}

- (void)tapped:(UITapGestureRecognizer *)g {
    if([MMSpotify isLoading]) return;
    [[MMRootController shared] togglePlayPause];   // auch "Fortsetzen" nach App-Start
    // kleines Feedback: kurzes Aufblitzen des Akzents
    UIView*f=[[UIView alloc] initWithFrame:self.view.bounds]; f.backgroundColor=[UIColor colorWithWhite:1 alpha:0.06]; f.userInteractionEnabled=NO; [self.view addSubview:f];
    [UIView animateWithDuration:0.35 animations:^{ f.alpha=0; } completion:^(BOOL d){ [f removeFromSuperview]; }];
}

// Liegt der Startpunkt auf der Fortschrittsanzeige? Dann wird gespult, sonst gewischt.
- (BOOL)inSeekZone:(CGPoint)p {
    if(_disc){ CGFloat d=hypot(p.x-_c.x,p.y-_c.y); return d>_R-34 && d<_R+30; }
    if(_f[0]){ CGFloat hy=_top+(_bot-_top)*[self curFrac]; return fabs(p.y-hy)<30 && p.y>_top-10 && p.y<_bot+10; }
    return fabs(p.y-_midY)<60;
}
- (double)curFrac { double d=[MMAudio duration]; return d>0?[MMAudio currentTime]/d:0; }
- (double)fracAt:(CGPoint)p {
    double f;
    if(_disc){ double ang=atan2(p.y-_c.y,p.x-_c.x)+M_PI_2; if(ang<0)ang+=2*M_PI; f=ang/(2*M_PI); }
    else if(_f[0]) f=(p.y-_top)/(_bot-_top);
    else f=(p.x-18)/(W-36);
    return f<0?0:(f>1?1:f);
}

- (void)panned:(UIPanGestureRecognizer *)g {
    CGPoint p=[g locationInView:self.view];
    if(g.state==UIGestureRecognizerStateBegan){
        CGPoint t=[g translationInView:self.view]; CGPoint start=CGPointMake(p.x-t.x,p.y-t.y);
        _seekMode=[MMAudio duration]>0 && ![MMSpotify isLoading] && [self inSeekZone:start];
        if(_seekMode){ _seeking=YES; _seekFrac=[self fracAt:p]; }
        return;
    }
    if(_seekMode){
        _seekFrac=[self fracAt:p];
        if(g.state==UIGestureRecognizerStateEnded){ [MMAudio seekTo:_seekFrac*[MMAudio duration]]; _seeking=NO; }
        else if(g.state==UIGestureRecognizerStateCancelled||g.state==UIGestureRecognizerStateFailed) _seeking=NO;
        return;
    }
    if(g.state!=UIGestureRecognizerStateEnded) return;
    CGPoint t=[g translationInView:self.view], v=[g velocityInView:self.view];
    if(fabs(t.x)>fabs(t.y) && (fabs(t.x)>60 || fabs(v.x)>500)){
        if(t.x<0) [[MMRootController shared] playNext]; else [[MMRootController shared] playPrev];
        [self nudge:t.x<0?-1:1];
    } else if(t.y>80 || v.y>700) [self close];
}

// Wisch-Feedback: Inhalt rutscht kurz in Wischrichtung
- (void)nudge:(int)dir {
    [UIView animateWithDuration:0.12 animations:^{ _title.transform=CGAffineTransformMakeTranslation(dir*24,0); _title.alpha=0.2; }
                     completion:^(BOOL f){ _title.transform=CGAffineTransformMakeTranslation(-dir*24,0);
        [UIView animateWithDuration:0.2 animations:^{ _title.transform=CGAffineTransformIdentity; _title.alpha=1; }]; }];
}

- (void)held:(UILongPressGestureRecognizer *)g {
    if(g.state!=UIGestureRecognizerStateBegan) return;
    MMRootController*r=[MMRootController shared];
    NSArray*rep=@[L(@"Repeat: Off"),L(@"Repeat: All"),L(@"Repeat: One")];
    NSMutableArray*opts=[NSMutableArray arrayWithObjects:(r.shuffle?L(@"Shuffle: On"):L(@"Shuffle: Off")),rep[r.repeatMode%3],nil];
    for(NSString*s in [MMArtPlayer styles]) [opts addObject:[NSString stringWithFormat:@"%@%@",[s isEqualToString:_style]?@"✓  ":@"",[MMArtPlayer nameOf:s]]];
    [MMSheet showIn:self.view title:L(@"Player") subtitle:nil options:opts done:^(NSInteger i){
        if(i==0){ [r setShuffle:!r.shuffle]; return; }
        if(i==1){ r.repeatMode=(r.repeatMode+1)%3; return; }
        if(i>=2){
            NSString*s=[MMArtPlayer styles][i-2]; if([s isEqualToString:_style]) return;
            [MMArtPlayer setStyle:s];
            [self dismissViewControllerAnimated:NO completion:^{ [[MMRootController shared] openPlayer]; }];
        }
    }];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
@end
