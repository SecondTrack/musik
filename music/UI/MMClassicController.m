#import "MMClassicController.h"
#import "MMRootController.h"
#import "MMArtPlayer.h"
#import "MMSpotify.h"
#import "MMAudio.h"
#import "MMCovers.h"
#import "MMKeepAlive.h"
#import "MMAboutView.h"
#import "MeshL10n.h"
#import <QuartzCore/QuartzCore.h>
#import <AudioToolbox/AudioToolbox.h>
#import <MediaPlayer/MediaPlayer.h>

static UIColor* RGB(int r,int g,int b){ return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1]; }
static CAGradientLayer* grad(CGRect f,UIColor*a,UIColor*b){ CAGradientLayer*g=[CAGradientLayer layer]; g.frame=f; g.colors=@[(id)a.CGColor,(id)b.CGColor]; return g; }
static BOOL isBlack(void){ return [[[NSUserDefaults standardUserDefaults] stringForKey:@"ipodColor"] isEqualToString:@"black"]; }
// Stil: modern (Standard, flach + Helvetica Neue) oder klassisch (wie das Original von 2007)
// Im iPod-Modus gibt es nur die abstrakten Player (der Standard-Player passt nicht dazu) -> Vorgabe Orbit
static NSString *artStyle(void){ NSString*s=[MMArtPlayer style]; return [s isEqualToString:@"standard"]?@"orbit":s; }
static BOOL isModern(void){ return ![[[NSUserDefaults standardUserDefaults] stringForKey:@"ipodStyle"] isEqualToString:@"classic"]; }
// Schrift: w 0 = leicht, 1 = normal, 2 = betont
static UIFont* F(CGFloat size,int w){
    if(isModern()) return [UIFont fontWithName:(w==0?@"HelveticaNeue-Light":(w==1?@"HelveticaNeue":@"HelveticaNeue-Medium")) size:size];
    return [UIFont fontWithName:(w==2?@"Helvetica-Bold":@"Helvetica") size:size];
}
static UIColor* ACCENT(void){ return isModern()?RGB(30,185,84):RGB(35,115,215); }      // Spotify-Grün / iPod-Blau

// ======================================================================
// Click Wheel: im Kreis wischen = Schritte, Tippen = MENU / ⏮ / ⏭ / ⏯ / Mitte
// ======================================================================
typedef NS_ENUM(NSInteger, MMWheelButton) { MMWheelCenter, MMWheelMenu, MMWheelPrev, MMWheelNext, MMWheelPlay };

@interface MMClickWheel : UIView
@property (nonatomic, copy) void (^onStep)(NSInteger dir);          // +1 im Uhrzeigersinn
@property (nonatomic, copy) void (^onButton)(MMWheelButton b);
- (id)initWithFrame:(CGRect)f black:(BOOL)black;
@end

@implementation MMClickWheel {
    CGFloat _rOut, _rIn, _lastAng, _acc, _moved;
    BOOL _inWheel, _inCenter;
    UIView *_centerBtn;
}
- (id)initWithFrame:(CGRect)f black:(BOOL)black {
    if(!(self=[super initWithFrame:f])) return nil;
    self.backgroundColor=[UIColor clearColor]; self.multipleTouchEnabled=NO;
    BOOL modern=isModern();
    CGFloat s=MIN(f.size.width,f.size.height); _rOut=s/2-(modern?6:0); _rIn=s*0.19;
    CGPoint c=CGPointMake(f.size.width/2,f.size.height/2);
    UIView*wheel=[[UIView alloc] initWithFrame:CGRectMake(c.x-_rOut,c.y-_rOut,2*_rOut,2*_rOut)];
    wheel.layer.cornerRadius=_rOut; wheel.userInteractionEnabled=NO;
    if(modern){   // flach, weicher Schatten statt Rand
        wheel.backgroundColor=black?RGB(46,46,50):[UIColor whiteColor];
        wheel.layer.shadowColor=[UIColor blackColor].CGColor; wheel.layer.shadowOpacity=black?0.5:0.12; wheel.layer.shadowRadius=10; wheel.layer.shadowOffset=CGSizeMake(0,3);
        wheel.layer.shadowPath=[UIBezierPath bezierPathWithOvalInRect:wheel.bounds].CGPath;
    } else {
        wheel.clipsToBounds=YES;
        wheel.layer.borderColor=(black?RGB(70,70,76):RGB(190,190,190)).CGColor; wheel.layer.borderWidth=1;
        [wheel.layer addSublayer:black?grad(wheel.bounds,RGB(44,44,48),RGB(16,16,18)):grad(wheel.bounds,RGB(252,252,252),RGB(228,228,228))];
    }
    [self addSubview:wheel];
    UIColor*lab=modern?(black?RGB(150,150,156):RGB(160,160,166)):(black?RGB(185,185,190):RGB(165,165,170));
    UILabel*menu=[[UILabel alloc] initWithFrame:CGRectMake(c.x-60,c.y-_rOut+(modern?16:12),120,20)];
    menu.textAlignment=NSTextAlignmentCenter; menu.backgroundColor=[UIColor clearColor]; menu.userInteractionEnabled=NO;
    if(modern) menu.attributedText=[[NSAttributedString alloc] initWithString:@"MENU" attributes:@{NSFontAttributeName:F(12,2),NSForegroundColorAttributeName:lab,NSKernAttributeName:@2.5}];
    else { menu.text=@"MENU"; menu.font=[UIFont fontWithName:@"Helvetica-Bold" size:15]; menu.textColor=lab; }
    [self addSubview:menu];
    CGFloat gi=modern?34:30;
    [self addSubview:[self glyph:@"prev" at:CGPointMake(c.x-_rOut+gi,c.y) color:lab]];
    [self addSubview:[self glyph:@"next" at:CGPointMake(c.x+_rOut-gi,c.y) color:lab]];
    [self addSubview:[self glyph:@"play" at:CGPointMake(c.x,c.y+_rOut-(modern?28:24)) color:lab]];
    _centerBtn=[[UIView alloc] initWithFrame:CGRectMake(c.x-_rIn,c.y-_rIn,2*_rIn,2*_rIn)];
    _centerBtn.layer.cornerRadius=_rIn; _centerBtn.clipsToBounds=YES; _centerBtn.userInteractionEnabled=NO;
    if(modern){
        _centerBtn.backgroundColor=black?RGB(30,30,33):RGB(240,240,244);
        _centerBtn.layer.borderColor=(black?RGB(64,64,70):RGB(222,222,228)).CGColor; _centerBtn.layer.borderWidth=1;
    } else {
        _centerBtn.layer.borderColor=(black?RGB(78,78,84):RGB(185,185,188)).CGColor; _centerBtn.layer.borderWidth=1;
        [_centerBtn.layer addSublayer:black?grad(_centerBtn.bounds,RGB(24,24,27),RGB(54,54,58)):grad(_centerBtn.bounds,RGB(214,214,218),RGB(240,240,243))];
    }
    [self addSubview:_centerBtn];
    return self;
}
- (UIImageView *)glyph:(NSString *)kind at:(CGPoint)c color:(UIColor *)col {
    CGFloat w=34,h=isModern()?13:16;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(w,h),NO,0); [col setFill];
    void (^tri)(CGFloat,CGFloat,BOOL)=^(CGFloat x,CGFloat tw,BOOL right){
        UIBezierPath*p=[UIBezierPath bezierPath];
        if(right){ [p moveToPoint:CGPointMake(x,2)]; [p addLineToPoint:CGPointMake(x+tw,h/2)]; [p addLineToPoint:CGPointMake(x,h-2)]; }
        else { [p moveToPoint:CGPointMake(x+tw,2)]; [p addLineToPoint:CGPointMake(x,h/2)]; [p addLineToPoint:CGPointMake(x+tw,h-2)]; }
        [p closePath]; [p fill]; };
    if([kind isEqualToString:@"next"]){ tri(5,9,YES); tri(14,9,YES); UIRectFill(CGRectMake(24,2,2.5,h-4)); }
    else if([kind isEqualToString:@"prev"]){ UIRectFill(CGRectMake(7.5,2,2.5,h-4)); tri(10,9,NO); tri(19,9,NO); }
    else { tri(6,10,YES); UIRectFill(CGRectMake(20,2.5,3,h-5)); UIRectFill(CGRectMake(25.5,2.5,3,h-5)); }
    UIImageView*iv=[[UIImageView alloc] initWithImage:UIGraphicsGetImageFromCurrentImageContext()]; UIGraphicsEndImageContext();
    iv.center=c; iv.userInteractionEnabled=NO; return iv;
}
- (CGPoint)ctr { return CGPointMake(self.bounds.size.width/2,self.bounds.size.height/2); }
- (CGFloat)distOf:(CGPoint)p { CGPoint c=[self ctr]; return hypot(p.x-c.x,p.y-c.y); }
- (CGFloat)angOf:(CGPoint)p { CGPoint c=[self ctr]; return atan2(p.y-c.y,p.x-c.x); }   // y nach unten -> wächst im Uhrzeigersinn
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e { return [self distOf:p]<=_rOut+6; }

- (void)touchesBegan:(NSSet *)t withEvent:(UIEvent *)e {
    CGPoint p=[[t anyObject] locationInView:self]; CGFloat d=[self distOf:p];
    _inCenter=(d<_rIn); _inWheel=!_inCenter; _lastAng=[self angOf:p]; _acc=0; _moved=0;
    if(_inCenter) _centerBtn.alpha=0.75;
}
- (void)touchesMoved:(NSSet *)t withEvent:(UIEvent *)e {
    CGPoint p=[[t anyObject] locationInView:self]; CGFloat d=[self distOf:p];
    if(_inCenter){ if(d<_rIn+8) return; _inCenter=NO; _inWheel=YES; _centerBtn.alpha=1; _lastAng=[self angOf:p]; return; }
    if(!_inWheel || d<_rIn*0.6) return;                    // zu nah an der Mitte: Winkel springt
    CGFloat a=[self angOf:p], da=a-_lastAng;
    if(da>M_PI) da-=2*M_PI; else if(da<-M_PI) da+=2*M_PI;
    _lastAng=a; _acc+=da; _moved+=fabs(da);
    const CGFloat STEP=M_PI/10;                             // 20 Klicks pro Umdrehung
    while(_acc>=STEP){ _acc-=STEP; if(self.onStep) self.onStep(1); }
    while(_acc<=-STEP){ _acc+=STEP; if(self.onStep) self.onStep(-1); }
}
- (void)touchesEnded:(NSSet *)t withEvent:(UIEvent *)e {
    CGPoint p=[[t anyObject] locationInView:self];
    _centerBtn.alpha=1;
    if(_inCenter){ if(self.onButton) self.onButton(MMWheelCenter); }
    else if(_inWheel && _moved<0.25){                       // kaum gedreht = Tippen auf einen Bereich
        CGFloat a=[self angOf:p];
        MMWheelButton b;
        if(fabs(a+M_PI_2)<M_PI_4) b=MMWheelMenu;
        else if(fabs(a-M_PI_2)<M_PI_4) b=MMWheelPlay;
        else if(fabs(a)<M_PI_4) b=MMWheelNext;
        else b=MMWheelPrev;
        if(self.onButton) self.onButton(b);
    }
    _inCenter=_inWheel=NO;
}
- (void)touchesCancelled:(NSSet *)t withEvent:(UIEvent *)e { _inCenter=_inWheel=NO; _centerBtn.alpha=1; }
@end

// ======================================================================
// Menü-Modell: ein Bildschirm = NSMutableDictionary
//   title, items, sel, top          normale Liste
//   np=YES                          "Sie hören"
//   search=YES, q, li               Suche mit Buchstaben-Rad
// Eintrag: title, arrow (Untermenü), value (rechts, z.B. "Ein"), action-Block
// ======================================================================
static NSArray* searchLetters(void){
    static NSArray*a; static dispatch_once_t o;
    dispatch_once(&o, ^{
        NSMutableArray*m=[NSMutableArray array];
        for(char c='A';c<='Z';c++) [m addObject:[NSString stringWithFormat:@"%c",c]];
        for(char c='0';c<='9';c++) [m addObject:[NSString stringWithFormat:@"%c",c]];
        [m addObject:@"_"]; [m addObject:@"←"]; [m addObject:@"OK"];   // Leerzeichen, Löschen, Suchen
        a=m; });
    return a;
}

@interface MMClassicController ()
@end

@implementation MMClassicController {
    UIView *_screen, *_listView, *_npView, *_volView, *_searchView, *_dlStrip;
    UILabel *_hdrTitle; UIImageView *_hdrPlay, *_hdrBatt;
    NSMutableArray *_rows;            // sichtbare Zeilen (UIView mit Verlauf + Labels)
    NSInteger _visible; CGFloat _rowH;
    UIView *_scrollBar, *_scrollKnob;
    NSMutableArray *_stack;
    MMClickWheel *_wheel;
    SystemSoundID _click;
    NSTimer *_timer;
    // Sie hören
    UIImageView *_npCover; UILabel *_npCount, *_npTitle, *_npArtist, *_npT1, *_npT2;
    UIActivityIndicatorView *_hdrSpin, *_npSpin;   // Song lädt
    UIView *_npBar, *_npFill; NSString *_npCoverURL;
    UIView *_volFill; NSTimeInterval _volUntil;
    // Suche
    UILabel *_sQuery; NSMutableArray *_sCells;
    // Download-Zeile
    UILabel *_dlLbl; UIView *_dlFill; BOOL _dlOn;
    UIColor *_fg, *_fg2, *_bg;        // Text, Nebentext, Display-Hintergrund
}

#pragma mark - Aufbau

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    [self makeClickSound];
    [UIDevice currentDevice].batteryMonitoringEnabled=YES;
    _stack=[NSMutableArray array];
    [self buildUI];
    [self pushMenu:[self mainMenu]];
}

// Baut Gehäuse, Display und Rad in Farbe + Stil (wird beim Wechsel neu aufgerufen)
- (void)buildUI {
    for(UIView*v in [self.view.subviews copy]) [v removeFromSuperview];
    for(CALayer*l in [self.view.layer.sublayers copy]) [l removeFromSuperlayer];
    _npCoverURL=nil;
    BOOL black=isBlack(), modern=isModern();
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;
    _bg=(modern&&black)?RGB(16,16,18):[UIColor whiteColor];
    _fg=(modern&&black)?RGB(245,245,247):(modern?RGB(22,22,24):[UIColor blackColor]);
    _fg2=modern?(black?RGB(142,142,148):RGB(138,138,144)):RGB(90,90,95);
    // Gehäuse
    if(modern){ self.view.backgroundColor=black?RGB(26,26,28):RGB(243,243,246); }
    else [self.view.layer addSublayer:black?grad(self.view.bounds,RGB(62,62,66),RGB(20,20,23)):grad(self.view.bounds,RGB(236,236,238),RGB(196,196,200))];

    // Display (4:3)
    CGFloat sw=W-32, sh=round(sw*0.75);
    if(modern){
        _screen=[[UIView alloc] initWithFrame:CGRectMake(16,18,sw,sh)]; _screen.layer.cornerRadius=12;
        _screen.layer.borderColor=(black?RGB(52,52,56):RGB(222,222,228)).CGColor; _screen.layer.borderWidth=1;
    } else {
        UIView*bezel=[[UIView alloc] initWithFrame:CGRectMake(12,14,sw+8,sh+8)]; bezel.backgroundColor=RGB(8,8,10); bezel.layer.cornerRadius=6;
        if(black){ bezel.layer.borderColor=RGB(80,80,86).CGColor; bezel.layer.borderWidth=1; }
        [self.view addSubview:bezel];
        _screen=[[UIView alloc] initWithFrame:CGRectMake(16,18,sw,sh)]; _screen.layer.cornerRadius=2;
    }
    _screen.backgroundColor=_bg; _screen.clipsToBounds=YES; [self.view addSubview:_screen];

    // Kopfzeile: Play-Status links, Titel Mitte, Batterie rechts
    CGFloat hh=modern?26:20;
    UIView*hdr=[[UIView alloc] initWithFrame:CGRectMake(0,0,sw,hh)];
    if(modern){ UIView*hl=[[UIView alloc] initWithFrame:CGRectMake(12,hh-1,sw-24,0.5)]; hl.backgroundColor=[_fg colorWithAlphaComponent:0.12]; [hdr addSubview:hl]; }
    else { [hdr.layer addSublayer:grad(hdr.bounds,RGB(250,250,250),RGB(200,203,208))];
           UIView*hl=[[UIView alloc] initWithFrame:CGRectMake(0,hh-1,sw,1)]; hl.backgroundColor=RGB(140,144,150); [hdr addSubview:hl]; }
    _hdrTitle=[[UILabel alloc] initWithFrame:CGRectMake(40,0,sw-80,hh)]; _hdrTitle.font=modern?F(13,2):[UIFont fontWithName:@"Helvetica-Bold" size:13];
    _hdrTitle.textAlignment=NSTextAlignmentCenter; _hdrTitle.textColor=modern?_fg:[UIColor blackColor]; _hdrTitle.backgroundColor=[UIColor clearColor]; [hdr addSubview:_hdrTitle];
    _hdrPlay=[[UIImageView alloc] initWithFrame:CGRectMake(modern?12:6,(hh-12)/2,12,12)]; [hdr addSubview:_hdrPlay];
    _hdrSpin=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:(modern&&black)?UIActivityIndicatorViewStyleWhite:UIActivityIndicatorViewStyleGray];
    _hdrSpin.transform=CGAffineTransformMakeScale(0.6,0.6); _hdrSpin.center=CGPointMake(_hdrPlay.center.x,hh/2); _hdrSpin.hidesWhenStopped=YES; [hdr addSubview:_hdrSpin];
    _hdrBatt=[[UIImageView alloc] initWithFrame:CGRectMake(sw-(modern?36:30),(hh-11)/2,24,11)]; [hdr addSubview:_hdrBatt];
    [_screen addSubview:hdr];

    // Liste
    CGRect body=CGRectMake(0,hh,sw,sh-hh);
    _listView=[[UIView alloc] initWithFrame:body]; _listView.backgroundColor=_bg; [_screen addSubview:_listView];
    _rowH=modern?30:24; _visible=(NSInteger)floor((sh-hh-(modern?6:0))/_rowH);
    _rows=[NSMutableArray array];
    for(NSInteger i=0;i<_visible;i++){
        UIView*r=[[UIView alloc] initWithFrame:CGRectMake(0,i*_rowH,sw-6,_rowH)];
        CALayer*g;
        if(modern){ g=[CALayer layer]; g.backgroundColor=ACCENT().CGColor; g.cornerRadius=8; }
        else g=grad(r.bounds,RGB(110,170,240),RGB(30,110,215));
        g.hidden=YES; g.name=@"sel"; [r.layer addSublayer:g];
        UILabel*t=[[UILabel alloc] initWithFrame:CGRectMake(8,0,sw-60,_rowH)]; t.tag=1; t.font=modern?F(16,1):F(15,2); t.backgroundColor=[UIColor clearColor];
        UILabel*v=[[UILabel alloc] initWithFrame:CGRectMake(sw-90,0,72,_rowH)]; v.tag=2; v.font=F(14,1); v.textAlignment=NSTextAlignmentRight; v.backgroundColor=[UIColor clearColor];
        UILabel*a=[[UILabel alloc] initWithFrame:CGRectMake(sw-22,0,12,_rowH)]; a.tag=3; a.text=@"›"; a.font=modern?F(22,0):[UIFont fontWithName:@"Helvetica-Bold" size:20]; a.backgroundColor=[UIColor clearColor];
        [r addSubview:t]; [r addSubview:v]; [r addSubview:a]; [_listView addSubview:r]; [_rows addObject:r];
    }
    _scrollBar=[[UIView alloc] initWithFrame:CGRectMake(sw-6,0,6,sh-hh)]; _scrollBar.backgroundColor=modern?[UIColor clearColor]:RGB(225,228,232);
    _scrollKnob=[[UIView alloc] initWithFrame:CGRectMake(modern?2:1,0,modern?3:4,20)]; _scrollKnob.backgroundColor=modern?[_fg2 colorWithAlphaComponent:0.6]:RGB(90,140,215); _scrollKnob.layer.cornerRadius=modern?1.5:2;
    [_scrollBar addSubview:_scrollKnob]; [_listView addSubview:_scrollBar];

    [self buildNowPlaying:body];
    [self buildSearch:body];

    // Download-Zeile unten im Display (nur in Listen sichtbar)
    _dlStrip=[[UIView alloc] initWithFrame:CGRectMake(0,sh-16,sw,16)]; _dlStrip.backgroundColor=modern?_bg:RGB(238,240,244); _dlStrip.hidden=YES;
    UIView*dl=[[UIView alloc] initWithFrame:CGRectMake(0,0,sw,modern?0.5:1)]; dl.backgroundColor=modern?[_fg colorWithAlphaComponent:0.12]:RGB(170,175,182); [_dlStrip addSubview:dl];
    _dlLbl=[[UILabel alloc] initWithFrame:CGRectMake(8,1,sw*0.55,15)]; _dlLbl.font=F(10,2); _dlLbl.textColor=modern?_fg2:RGB(60,60,66); _dlLbl.backgroundColor=[UIColor clearColor];
    [_dlStrip addSubview:_dlLbl];
    UIView*dbar=[[UIView alloc] initWithFrame:CGRectMake(sw*0.58,modern?6.5:5,sw*0.42-12,modern?3:6)]; dbar.clipsToBounds=YES; dbar.tag=6;
    if(modern){ dbar.backgroundColor=[_fg colorWithAlphaComponent:0.12]; dbar.layer.cornerRadius=1.5; } else { dbar.layer.borderColor=RGB(120,125,135).CGColor; dbar.layer.borderWidth=1; }
    _dlFill=[[UIView alloc] initWithFrame:CGRectMake(0,0,0,dbar.bounds.size.height)]; _dlFill.backgroundColor=ACCENT(); [dbar addSubview:_dlFill]; [_dlStrip addSubview:dbar];
    [_screen addSubview:_dlStrip];

    // Click Wheel unter dem Display
    CGFloat top=18+sh+10, avail=H-top-10, d=MIN(W-60,avail);
    _wheel=[[MMClickWheel alloc] initWithFrame:CGRectMake((W-d)/2,top+(avail-d)/2,d,d) black:black];
    __weak MMClassicController*ws=self;
    _wheel.onStep=^(NSInteger dir){ [ws wheelStep:dir]; };
    _wheel.onButton=^(MMWheelButton b){ [ws wheelButton:b]; };
    [self.view addSubview:_wheel];
}

- (void)buildNowPlaying:(CGRect)f {
    BOOL modern=isModern();
    _npView=[[UIView alloc] initWithFrame:f]; _npView.backgroundColor=_bg; _npView.hidden=YES; [_screen addSubview:_npView];
    CGFloat w=f.size.width, h=f.size.height;
    _npCount=[self label:CGRectMake(12,modern?6:4,w-24,16) size:12 bold:NO in:_npView]; _npCount.textColor=_fg2;
    CGFloat cs=MIN(h-(modern?62:70),w*0.4), cy0=modern?26:24;
    _npCover=[[UIImageView alloc] initWithFrame:CGRectMake(modern?12:10,cy0,cs,cs)]; _npCover.backgroundColor=modern?[_fg colorWithAlphaComponent:0.08]:RGB(225,225,228);
    _npCover.contentMode=UIViewContentModeScaleAspectFill; _npCover.clipsToBounds=YES; if(modern) _npCover.layer.cornerRadius=6;
    [_npView addSubview:_npCover];
    _npSpin=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _npSpin.center=_npCover.center; _npSpin.hidesWhenStopped=YES; [_npView addSubview:_npSpin];
    CGFloat tx=CGRectGetMaxX(_npCover.frame)+12, tw=w-tx-10;
    _npTitle=[self label:CGRectMake(tx,cy0+8,tw,40) size:modern?16:15 bold:YES in:_npView]; _npTitle.numberOfLines=2;
    _npArtist=[self label:CGRectMake(tx,cy0+50,tw,18) size:13 bold:NO in:_npView]; _npArtist.textColor=_fg2;
    CGFloat by=h-(modern?30:34), bh=modern?3:9;
    _npBar=[[UIView alloc] initWithFrame:CGRectMake(14,by,w-28,bh)]; _npBar.clipsToBounds=YES;
    if(modern){ _npBar.backgroundColor=[_fg colorWithAlphaComponent:0.12]; _npBar.layer.cornerRadius=1.5; }
    else { _npBar.layer.borderColor=RGB(120,125,135).CGColor; _npBar.layer.borderWidth=1; [_npBar.layer addSublayer:grad(_npBar.bounds,RGB(245,245,247),RGB(215,217,222))]; }
    _npFill=[[UIView alloc] initWithFrame:CGRectMake(0,0,0,bh)]; _npFill.clipsToBounds=YES;
    if(modern) _npFill.backgroundColor=ACCENT(); else [_npFill.layer addSublayer:grad(CGRectMake(0,0,w,bh),RGB(120,175,240),RGB(35,110,210))];
    [_npBar addSubview:_npFill]; [_npView addSubview:_npBar];
    _npT1=[self label:CGRectMake(14,by+bh+3,80,14) size:11 bold:NO in:_npView]; _npT1.textColor=modern?_fg2:_fg;
    _npT2=[self label:CGRectMake(w-94,by+bh+3,80,14) size:11 bold:NO in:_npView]; _npT2.textAlignment=NSTextAlignmentRight; _npT2.textColor=_npT1.textColor;
    // Lautstärke-Anzeige (beim Drehen in "Sie hören")
    _volView=[[UIView alloc] initWithFrame:CGRectMake(14,by-8,w-28,24)]; _volView.backgroundColor=_bg; _volView.hidden=YES; [_npView addSubview:_volView];
    UIView*vb=[[UIView alloc] initWithFrame:CGRectMake(22,(24-bh)/2,w-28-44,bh)]; vb.clipsToBounds=YES; vb.tag=5;
    if(modern){ vb.backgroundColor=[_fg colorWithAlphaComponent:0.12]; vb.layer.cornerRadius=1.5; } else { vb.layer.borderColor=RGB(120,125,135).CGColor; vb.layer.borderWidth=1; }
    _volFill=[[UIView alloc] initWithFrame:CGRectMake(0,0,0,bh)]; _volFill.clipsToBounds=YES;
    if(modern) _volFill.backgroundColor=ACCENT(); else [_volFill.layer addSublayer:grad(CGRectMake(0,0,w,bh),RGB(120,175,240),RGB(35,110,210))];
    [vb addSubview:_volFill]; [_volView addSubview:vb];
    UILabel*lo=[self label:CGRectMake(0,3,20,16) size:11 bold:YES in:_volView]; lo.text=@"–"; lo.textAlignment=NSTextAlignmentCenter;
    UILabel*hi=[self label:CGRectMake(w-28-20,3,20,16) size:13 bold:YES in:_volView]; hi.text=@"+"; hi.textAlignment=NSTextAlignmentCenter;
}

- (void)buildSearch:(CGRect)f {
    BOOL modern=isModern();
    _searchView=[[UIView alloc] initWithFrame:f]; _searchView.backgroundColor=_bg; _searchView.hidden=YES; [_screen addSubview:_searchView];
    CGFloat w=f.size.width, h=f.size.height;
    UIView*box=[[UIView alloc] initWithFrame:CGRectMake(10,12,w-20,30)]; box.layer.cornerRadius=modern?8:4; box.clipsToBounds=YES;
    if(modern) box.backgroundColor=[_fg colorWithAlphaComponent:0.07];
    else { box.layer.borderColor=RGB(120,125,135).CGColor; box.layer.borderWidth=1; [box.layer addSublayer:grad(box.bounds,RGB(255,255,255),RGB(238,240,244))]; }
    [_searchView addSubview:box];
    _sQuery=[self label:CGRectMake(8,0,w-36,30) size:16 bold:YES in:box]; _sQuery.lineBreakMode=NSLineBreakByTruncatingHead;
    UILabel*hint=[self label:CGRectMake(10,48,w-20,30) size:11 bold:NO in:_searchView]; hint.numberOfLines=2; hint.textColor=_fg2;
    hint.text=L(@"Turn the wheel to pick a letter, press the center to add it. OK searches.");
    // Buchstabenleiste unten
    _sCells=[NSMutableArray array];
    CGFloat cw=30; NSInteger n=(NSInteger)(w/cw); if(n%2==0) n--;
    CGFloat x0=(w-n*cw)/2;
    UIView*strip=[[UIView alloc] initWithFrame:CGRectMake(0,h-46,w,40)]; [_searchView addSubview:strip];
    for(NSInteger i=0;i<n;i++){
        UILabel*c=[self label:CGRectMake(x0+i*cw,4,cw,32) size:16 bold:YES in:strip]; c.textAlignment=NSTextAlignmentCenter; c.adjustsFontSizeToFitWidth=YES;
        c.layer.cornerRadius=modern?8:4; [_sCells addObject:c];
    }
}

- (UILabel *)label:(CGRect)f size:(CGFloat)s bold:(BOOL)b in:(UIView *)v {
    UILabel*l=[[UILabel alloc] initWithFrame:f]; l.font=F(s,b?2:1);
    l.textColor=_fg?:[UIColor blackColor]; l.backgroundColor=[UIColor clearColor]; [v addSubview:l]; return l;
}

// Kurzes Klicken wie beim echten Rad (selbst erzeugt, 3 ms)
- (void)makeClickSound {
    int rate=44100, n=rate*3/1000; NSMutableData*pcm=[NSMutableData dataWithLength:n*2]; int16_t*s=pcm.mutableBytes;
    for(int i=0;i<n;i++){ double env=exp(-i/(double)(n/5)); s[i]=(int16_t)(((i%2)?1:-1)*9000*env); }
    NSMutableData*wav=[NSMutableData data];
    void (^u32)(uint32_t)=^(uint32_t v){ [wav appendBytes:&v length:4]; }; void (^u16)(uint16_t)=^(uint16_t v){ [wav appendBytes:&v length:2]; };
    [wav appendBytes:"RIFF" length:4]; u32(36+(uint32_t)pcm.length); [wav appendBytes:"WAVEfmt " length:8];
    u32(16); u16(1); u16(1); u32(rate); u32(rate*2); u16(2); u16(16); [wav appendBytes:"data" length:4]; u32((uint32_t)pcm.length); [wav appendData:pcm];
    NSString*path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"mm-click.wav"];
    [wav writeToFile:path atomically:YES];
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)[NSURL fileURLWithPath:path], &_click);
}
- (void)tick { if(_click) AudioServicesPlaySystemSound(_click); }

- (void)viewDidLoad {
    [super viewDidLoad];
    _timer=[NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}
- (void)dealloc { if(_click) AudioServicesDisposeSystemSoundID(_click); }

#pragma mark - Download-Anzeige

- (void)showDownload:(NSString *)text progress:(CGFloat)progress {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideDownload) object:nil];
    _dlOn=YES; _dlLbl.text=text;
    UIView*bar=[_dlStrip viewWithTag:6];
    bar.hidden=(progress<0);
    if(progress>=0) _dlFill.frame=CGRectMake(0,0,bar.bounds.size.width*MIN(1,progress),bar.bounds.size.height);
    else { _dlLbl.frame=CGRectMake(8,1,_dlStrip.bounds.size.width-16,15); [self performSelector:@selector(hideDownload) withObject:nil afterDelay:2.5]; }
    if(progress>=0) _dlLbl.frame=CGRectMake(8,1,_dlStrip.bounds.size.width*0.55,15);
    [self render];
}
- (void)hideDownload { _dlOn=NO; [self render]; }

#pragma mark - Menüs

- (NSMutableDictionary *)menu:(NSString *)title items:(NSArray *)items {
    return [@{@"title":title,@"items":items?:@[],@"sel":@0,@"top":@0} mutableCopy];
}
- (NSDictionary *)item:(NSString *)t arrow:(BOOL)a action:(void(^)(void))act {
    NSMutableDictionary*d=[@{@"title":t?:@"",@"arrow":@(a)} mutableCopy]; if(act) d[@"action"]=[act copy]; return d;
}
- (NSDictionary *)item:(NSString *)t value:(NSString *)v action:(void(^)(void))act {
    NSMutableDictionary*d=[[self item:t arrow:NO action:act] mutableCopy]; if(v) d[@"value"]=v; return d;
}

- (NSMutableDictionary *)mainMenu {
    __weak MMClassicController*ws=self;
    NSMutableArray*it=[NSMutableArray array];
    [it addObject:[self item:L(@"Music") arrow:YES action:^{ [ws pushMenu:[ws musicMenu]]; }]];
    [it addObject:[self item:@"Cover Flow" arrow:YES action:^{ [[MMRootController shared] showCoverFlow]; }]];
    [it addObject:[self item:L(@"Shuffle Songs") arrow:NO action:^{ [ws shuffleSongs]; }]];
    [it addObject:[self item:L(@"Search") arrow:YES action:^{ [ws openSearch]; }]];
    [it addObject:[self item:L(@"Settings") arrow:YES action:^{ [ws pushMenu:[ws settingsMenu]]; }]];
    if([[MMRootController shared] nowPlaying]){
        [it addObject:[self item:L(@"Now Playing") arrow:YES action:^{ [ws pushNowPlaying]; }]];
        // abstrakter Player (Orbit/Farbfeld/Linie) als Vollbild über dem iPod-Modus
        [it addObject:[self item:LF(@"Player: %@",[MMArtPlayer nameOf:artStyle()]) arrow:YES action:^{
            if([[MMArtPlayer style] isEqualToString:@"standard"]) [MMArtPlayer setStyle:artStyle()];
            [[MMRootController shared] openPlayer]; }]];
    }
    return [self menu:@"iPod" items:it];
}
- (NSMutableDictionary *)musicMenu {
    __weak MMClassicController*ws=self;
    return [self menu:L(@"Music") items:@[
        [self item:L(@"Playlists") arrow:YES action:^{ [ws openPlaylists]; }],
        [self item:L(@"Liked Songs") arrow:YES action:^{ [ws openTracks:L(@"Liked Songs") path:@"me/tracks?market=from_token&limit=50"]; }],
        [self item:L(@"Recently Played") arrow:YES action:^{ [ws openRecent]; }],
    ]];
}
- (NSMutableDictionary *)settingsMenu {
    __weak MMClassicController*ws=self;
    MMRootController*r=[MMRootController shared];
    NSArray*rep=@[L(@"Off"),L(@"All"),L(@"One")];
    return [self menu:L(@"Settings") items:@[
        [self item:L(@"Shuffle") value:(r.shuffle?L(@"On"):L(@"Off")) action:^{ [r setShuffle:!r.shuffle]; [ws replaceTop:[ws settingsMenu]]; }],
        [self item:L(@"Repeat") value:rep[r.repeatMode] action:^{ r.repeatMode=(r.repeatMode+1)%3; [ws replaceTop:[ws settingsMenu]]; }],
        [self item:L(@"Color") value:(isBlack()?L(@"Black"):L(@"Silver")) action:^{ [ws toggleColor]; }],
        [self item:L(@"Style") value:(isModern()?L(@"Modern"):L(@"Classic")) action:^{ [ws toggleStyle]; }],
        [self item:L(@"Player") value:[MMArtPlayer nameOf:artStyle()] action:^{
            NSArray*st=@[@"orbit",@"line"]; NSUInteger k=[st indexOfObject:artStyle()];
            [MMArtPlayer setStyle:st[(k+1)%st.count]]; [ws replaceTop:[ws settingsMenu]]; }],
        [self item:L(@"Background DL") value:([MMKeepAlive enabled]?L(@"On"):L(@"Off")) action:^{ [MMKeepAlive setEnabled:![MMKeepAlive enabled]]; [ws replaceTop:[ws settingsMenu]]; }],
        [self item:L(@"About") arrow:YES action:^{ [MMAboutView showIn:[MMRootController shared].view]; }],
        [self item:L(@"Orbit mode") arrow:NO action:^{ [[MMRootController shared] setUIMode:@"orbit"]; }],
        [self item:L(@"Line mode") arrow:NO action:^{ [[MMRootController shared] setUIMode:@"line"]; }],
        [self item:L(@"Exit iPod mode") arrow:NO action:^{ [[MMRootController shared] setClassicMode:NO]; }],
    ]];
}
// Farbe wechseln: alles neu aufbauen, Menüstapel und Auswahl bleiben
- (void)toggleColor {
    [[NSUserDefaults standardUserDefaults] setObject:(isBlack()?@"silver":@"black") forKey:@"ipodColor"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self buildUI];
    [self replaceTop:[self settingsMenu]];
}
- (void)toggleStyle {
    [[NSUserDefaults standardUserDefaults] setObject:(isModern()?@"classic":@"modern") forKey:@"ipodStyle"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self buildUI];
    [self replaceTop:[self settingsMenu]];
}
// Einstellungen ändern den Wert in der Zeile -> Menü neu aufbauen, Auswahl behalten
- (void)replaceTop:(NSMutableDictionary *)m {
    NSMutableDictionary*old=[_stack lastObject]; m[@"sel"]=old[@"sel"]; m[@"top"]=old[@"top"];
    [_stack removeLastObject]; [_stack addObject:m]; [self render];
}

- (void)pushMenu:(NSMutableDictionary *)m { [_stack addObject:m]; [self render]; }
- (void)pushNowPlaying {
    if(![[MMRootController shared] nowPlaying]) return;
    NSDictionary*top=[_stack lastObject]; if([top[@"np"] boolValue]){ [self render]; return; }
    NSMutableDictionary*m=[self menu:L(@"Now Playing") items:nil]; m[@"np"]=@YES; [self pushMenu:m];
}
- (void)pop {
    if(_stack.count<=1) return;
    [_stack removeLastObject];
    if(_stack.count==1){ [_stack removeAllObjects]; [_stack addObject:[self mainMenu]]; }   // "Sie hören" ein-/ausblenden
    [self render];
}

// Liste, die erst geladen wird: zeigt "Laden …" und füllt sich, wenn noch aktuell
- (NSMutableDictionary *)pushLoading:(NSString *)title {
    NSMutableDictionary*m=[self menu:title items:@[[self item:L(@"Loading …") arrow:NO action:nil]]]; m[@"loading"]=@YES;
    [self pushMenu:m]; return m;
}
- (void)fill:(NSMutableDictionary *)m items:(NSArray *)items {
    if(![_stack containsObject:m]) return;
    m[@"items"]=items.count?items:@[[self item:L(@"Empty") arrow:NO action:nil]]; [m removeObjectForKey:@"loading"];
    if([m[@"sel"] integerValue]>=(NSInteger)[m[@"items"] count]){ m[@"sel"]=@0; m[@"top"]=@0; }
    if([_stack lastObject]==m) [self render];
}

#pragma mark - Daten

static NSArray* tracksFromItems(NSArray*items){
    NSMutableArray*out=[NSMutableArray array];
    if(![items isKindOfClass:[NSArray class]]) return out;
    for(id it in items){
        if(![it isKindOfClass:[NSDictionary class]]) continue;
        id tw=it[@"track"]; NSDictionary*t=[tw isKindOfClass:[NSDictionary class]]?tw:it;
        NSString*tid=[t[@"id"] isKindOfClass:[NSString class]]?t[@"id"]:nil; if(!tid) continue;
        NSString*nm=[t[@"name"] isKindOfClass:[NSString class]]?t[@"name"]:@"";
        NSString*an=@""; id arts=t[@"artists"];
        if([arts isKindOfClass:[NSArray class]] && [arts count]){ id a0=arts[0]; if([a0 isKindOfClass:[NSDictionary class]] && [a0[@"name"] isKindOfClass:[NSString class]]) an=a0[@"name"]; }
        NSString*cov=@""; id alb=t[@"album"]; if([alb isKindOfClass:[NSDictionary class]]) cov=[MMCovers bestURL:alb[@"images"]]?:@"";
        [out addObject:@{@"id":tid,@"title":nm,@"artist":an,@"cover":cov}];
    }
    return out;
}
- (NSArray *)trackItems:(NSArray *)tracks {
    __weak MMClassicController*ws=self; NSMutableArray*out=[NSMutableArray array];
    for(NSUInteger i=0;i<tracks.count;i++){
        NSInteger idx=i;
        [out addObject:[self item:tracks[i][@"title"] arrow:NO action:^{
            [[MMRootController shared] playList:tracks index:idx]; [ws pushNowPlaying]; }]];
    }
    return out;
}
// Playlists als Einträge (für Liste und Cover Flow gleich)
- (void)loadPlaylists:(NSMutableDictionary *)m {
    __weak MMClassicController*ws=self;
    [MMSpotify apiUserCached:@"me/playlists?limit=50" completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        NSArray*pl=j[@"items"]; if(![pl isKindOfClass:[NSArray class]]){ if(fresh && [m[@"loading"] boolValue]) [ws fill:m items:nil]; return; }
        NSMutableArray*it=[NSMutableArray array];
        for(NSDictionary*p in pl){
            if(![p isKindOfClass:[NSDictionary class]] || ![p[@"id"] isKindOfClass:[NSString class]]) continue;
            NSString*name=[p[@"name"] isKindOfClass:[NSString class]]?p[@"name"]:@"";
            NSString*pid=p[@"id"];
            NSMutableDictionary*e=[[ws item:name arrow:YES action:^{ [ws openTracks:name path:[NSString stringWithFormat:@"playlists/%@?market=from_token",pid]]; }] mutableCopy];
            e[@"cover"]=[MMCovers bestURL:p[@"images"]]?:@"";
            id tr=p[@"tracks"]; if([tr isKindOfClass:[NSDictionary class]] && tr[@"total"]) e[@"sub"]=LF(@"%@ songs",tr[@"total"]);
            [it addObject:e];
        }
        [ws fill:m items:it];
    }];
}
- (void)openPlaylists { [self loadPlaylists:[self pushLoading:L(@"Playlists")]]; }
// Gleicher Pfad + gleiche Cache-Datei wie die normale Ansicht -> gespeicherte Liste sofort zeigen
- (void)openTracks:(NSString *)title path:(NSString *)path {
    NSMutableDictionary*m=[self pushLoading:title];
    NSString*cache=[NSString stringWithFormat:@"/var/mobile/.spotcache/list_%lu.plist",(unsigned long)path.hash];
    NSArray*cached=[NSArray arrayWithContentsOfFile:cache];
    if([cached isKindOfClass:[NSArray class]] && cached.count) [self fill:m items:[self trackItems:cached]];
    __weak MMClassicController*ws=self;
    [MMSpotify apiUserAllItems:path completion:^(NSArray*items,NSInteger st){
        NSArray*tracks=tracksFromItems(items);
        if(!tracks.count && cached.count) return;                         // offline -> gespeicherte Liste bleibt
        if(cached.count && [[cached valueForKey:@"id"] isEqualToArray:[tracks valueForKey:@"id"]]) return;   // unverändert
        if(tracks.count) [tracks writeToFile:cache atomically:YES];
        [ws fill:m items:[ws trackItems:tracks]];
    }];
}
- (void)openRecent {
    NSMutableDictionary*m=[self pushLoading:L(@"Recently Played")];
    __weak MMClassicController*ws=self;
    [MMSpotify apiUserCached:@"me/player/recently-played?limit=30" completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        NSArray*tracks=tracksFromItems(j[@"items"]);
        if(!tracks.count && !fresh) return;
        [ws fill:m items:[ws trackItems:tracks]];
    }];
}
// "Zufällige Titel": Lieblingssongs gemischt abspielen
- (void)shuffleSongs {
    NSString*path=@"me/tracks?market=from_token&limit=50";
    NSString*cache=[NSString stringWithFormat:@"/var/mobile/.spotcache/list_%lu.plist",(unsigned long)path.hash];
    __weak MMClassicController*ws=self;
    void (^go)(NSArray*)=^(NSArray*tracks){
        if(!tracks.count) return;
        NSMutableArray*m=[tracks mutableCopy];
        for(NSUInteger i=m.count;i>1;i--) [m exchangeObjectAtIndex:i-1 withObjectAtIndex:arc4random_uniform((u_int32_t)i)];
        [[MMRootController shared] playList:m index:0]; [ws pushNowPlaying];
    };
    NSArray*cached=[NSArray arrayWithContentsOfFile:cache];
    if([cached isKindOfClass:[NSArray class]] && cached.count){ go(cached); return; }
    NSMutableDictionary*m=[self pushLoading:L(@"Shuffle Songs")];
    [MMSpotify apiUserAllItems:path completion:^(NSArray*items,NSInteger st){
        NSArray*tracks=tracksFromItems(items);
        if(!tracks.count){ [ws fill:m items:nil]; return; }
        [tracks writeToFile:cache atomically:YES];
        MMClassicController*ss=ws; if(ss && [ss->_stack lastObject]==m) [ss->_stack removeLastObject];
        go(tracks);
    }];
}
// Suche wie beim iPod classic: Buchstaben mit dem Rad wählen
- (void)openSearch {
    if(![MMSpotify hasSearchKey]){
        [self pushMenu:[self menu:L(@"Search") items:@[[self item:L(@"Needs a search key –") arrow:NO action:nil],[self item:L(@"set it up in normal mode.") arrow:NO action:nil]]]];
        return;
    }
    NSMutableDictionary*m=[self menu:L(@"Search") items:nil]; m[@"search"]=@YES; m[@"q"]=[NSMutableString string]; m[@"li"]=@0;
    [self pushMenu:m];
}
- (void)searchPick:(NSMutableDictionary *)m {
    NSString*c=searchLetters()[[m[@"li"] integerValue]]; NSMutableString*q=m[@"q"];
    if([c isEqualToString:@"←"]){ if(q.length) [q deleteCharactersInRange:NSMakeRange(q.length-1,1)]; }
    else if([c isEqualToString:@"_"]){ if(q.length && ![q hasSuffix:@" "]) [q appendString:@" "]; }
    else if([c isEqualToString:@"OK"]){
        NSString*s=[q stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; if(!s.length) return;
        NSMutableDictionary*r=[self pushLoading:s];
        __weak MMClassicController*ws=self;
        NSString*enc=[s stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        [MMSpotify webGet:[NSString stringWithFormat:@"search?q=%@&type=track&limit=10",enc] completion:^(NSDictionary*j,NSInteger st){
            id tr=j[@"tracks"]; [ws fill:r items:[ws trackItems:tracksFromItems([tr isKindOfClass:[NSDictionary class]]?tr[@"items"]:nil)]];
        }];
        return;
    }
    else [q appendString:[c lowercaseString]];
    [self render];
}

#pragma mark - Rad

- (void)wheelStep:(NSInteger)dir {
    NSMutableDictionary*m=[_stack lastObject];
    if([m[@"np"] boolValue]){   // Sie hören: Lautstärke
        MPMusicPlayerController*mp=[MPMusicPlayerController applicationMusicPlayer];
        float v=mp.volume+dir*0.0625f; mp.volume=MAX(0,MIN(1,v));
        _volUntil=[NSDate timeIntervalSinceReferenceDate]+1.5; [self tick]; [self refresh]; return;
    }
    if([m[@"search"] boolValue]){
        NSInteger n=searchLetters().count, li=([m[@"li"] integerValue]+dir+n)%n;   // Buchstaben laufen im Kreis
        m[@"li"]=@(li); [self tick]; [self render]; return;
    }
    NSInteger n=[m[@"items"] count], sel=[m[@"sel"] integerValue]+dir;
    if(sel<0||sel>=n) return;
    m[@"sel"]=@(sel); [self tick]; [self render];
}
- (void)wheelButton:(MMWheelButton)b {
    [self tick];
    MMRootController*r=[MMRootController shared];
    switch(b){
        case MMWheelMenu: [self pop]; break;
        case MMWheelPlay: [r togglePlayPause]; break;
        case MMWheelNext: [r playNext]; break;
        case MMWheelPrev: if([MMAudio currentTime]>3) [MMAudio seekTo:0]; else [r playPrev]; break;
        case MMWheelCenter: {
            NSMutableDictionary*m=[_stack lastObject]; if([m[@"np"] boolValue]) break;
            if([m[@"search"] boolValue]){ [self searchPick:m]; break; }
            NSArray*items=m[@"items"]; NSInteger sel=[m[@"sel"] integerValue];
            if(sel<(NSInteger)items.count){ void(^act)(void)=items[sel][@"action"]; if(act) act(); }
        } break;
    }
    [self refresh];
}

#pragma mark - Darstellung

- (void)render {
    NSMutableDictionary*m=[_stack lastObject];
    _hdrTitle.text=m[@"title"];
    BOOL np=[m[@"np"] boolValue], se=[m[@"search"] boolValue], list=!(np||se);
    _npView.hidden=!np; _searchView.hidden=!se; _listView.hidden=!list;
    _dlStrip.hidden=!(_dlOn && list);
    [self refreshHeader];
    if(np){ [self refresh]; return; }
    if(se){ [self renderSearch:m]; return; }
    NSInteger vis=_visible-(_dlStrip.hidden?0:1);
    NSArray*items=m[@"items"]; NSInteger n=items.count, sel=[m[@"sel"] integerValue], top=[m[@"top"] integerValue];
    if(sel<top) top=sel;
    if(sel>=top+vis) top=sel-vis+1;
    if(top<0) top=0;
    m[@"top"]=@(top);
    BOOL bar=(n>vis);
    CGFloat rw=_listView.bounds.size.width-(bar?6:0);
    for(NSInteger i=0;i<_visible;i++){
        UIView*r=_rows[i]; NSInteger k=top+i; r.hidden=(k>=n||i>=vis); if(r.hidden) continue;
        NSDictionary*it=items[k]; BOOL s=(k==sel);
        BOOL modern=isModern(); CGFloat y0=modern?3:0, pad=modern?16:8;
        r.frame=CGRectMake(0,y0+i*_rowH,rw,_rowH);
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        for(CALayer*l in r.layer.sublayers) if([l.name isEqualToString:@"sel"]){ l.hidden=!s; l.frame=modern?CGRectInset(r.bounds,6,1):r.bounds; }
        [CATransaction commit];
        UILabel*t=(UILabel*)[r viewWithTag:1], *v=(UILabel*)[r viewWithTag:2], *a=(UILabel*)[r viewWithTag:3];
        UIColor*fg=s?[UIColor whiteColor]:_fg;
        t.text=it[@"title"]; t.textColor=fg; v.text=it[@"value"]; v.textColor=s?[UIColor whiteColor]:_fg2;
        if(modern) t.font=F(16,s?2:1);
        a.hidden=![it[@"arrow"] boolValue]; a.textColor=s?[UIColor whiteColor]:(modern?_fg2:fg);
        t.frame=CGRectMake(pad,0,rw-pad-(it[@"value"]?96:30),_rowH);
        v.frame=CGRectMake(rw-pad-82,0,80,_rowH); a.frame=CGRectMake(rw-pad-8,0,12,_rowH);
    }
    _scrollBar.hidden=!bar;
    if(bar){ BOOL md=isModern(); CGFloat H=vis*_rowH, kh=MAX(14,H*vis/n);
        _scrollBar.frame=CGRectMake(_listView.bounds.size.width-6,md?3:0,6,H);
        _scrollKnob.frame=CGRectMake(md?2:1,(H-kh)*top/(CGFloat)(n-vis),md?3:4,kh); }
}

- (void)renderSearch:(NSMutableDictionary *)m {
    NSString*q=m[@"q"]; _sQuery.text=[q stringByAppendingString:@"|"];
    NSArray*L=searchLetters(); NSInteger li=[m[@"li"] integerValue], n=_sCells.count, half=n/2;
    for(NSInteger i=0;i<n;i++){
        UILabel*c=_sCells[i]; NSInteger k=((li+i-half)%(NSInteger)L.count+(NSInteger)L.count)%(NSInteger)L.count;
        c.text=L[k]; BOOL s=(i==half);
        c.backgroundColor=s?ACCENT():[UIColor clearColor]; c.textColor=s?[UIColor whiteColor]:_fg2;
        c.font=F(s?18:14,2);
    }
}

- (void)refreshHeader {
    // Song lädt -> drehendes Rad statt Play/Pause
    BOOL loading=[MMSpotify isLoading];
    if(loading){ if(!_hdrSpin.isAnimating) [_hdrSpin startAnimating]; } else [_hdrSpin stopAnimating];
    _hdrPlay.hidden=loading;
    // Play/Pause-Symbol links
    BOOL playing=[MMAudio isPlaying];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(12,12),NO,0); [ACCENT() setFill];
    if(playing){ UIBezierPath*p=[UIBezierPath bezierPath]; [p moveToPoint:CGPointMake(2,1)]; [p addLineToPoint:CGPointMake(11,6)]; [p addLineToPoint:CGPointMake(2,11)]; [p closePath]; [p fill]; }
    else if([[MMRootController shared] nowPlaying]){ UIRectFill(CGRectMake(2,1,3,10)); UIRectFill(CGRectMake(7,1,3,10)); }
    _hdrPlay.image=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    // Batterie rechts (echter Ladestand)
    float lvl=[UIDevice currentDevice].batteryLevel; if(lvl<0) lvl=1;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(24,11),NO,0);
    UIColor*bc=isModern()?_fg2:RGB(60,60,65);
    [bc setStroke]; UIBezierPath*b=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5,0.5,20,10) cornerRadius:isModern()?3:2]; b.lineWidth=1; [b stroke];
    [bc setFill]; UIRectFill(CGRectMake(21,3.5,1.5,4));
    UIColor*fill=lvl<0.2?RGB(230,60,50):(isModern()?_fg:RGB(80,190,60));
    [fill setFill]; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(2,2,17*lvl,7) cornerRadius:isModern()?1.5:0] fill];
    _hdrBatt.image=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
}

static NSString* fmt(double s){ if(s<0||isnan(s)) s=0; int m=(int)s/60, x=(int)s%60; return [NSString stringWithFormat:@"%d:%02d",m,x]; }

- (void)refresh {
    if(!self.view.superview){ [_timer invalidate]; _timer=nil; return; }   // Modus beendet: Timer gibt den Controller frei
    [self refreshHeader];
    NSMutableDictionary*m=[_stack lastObject];
    if(![m[@"np"] boolValue]) return;
    NSDictionary*np=[[MMRootController shared] nowPlaying];
    if(!np){ [self pop]; return; }
    NSInteger cnt=[np[@"count"] integerValue];
    _npCount.text=cnt>0?LF(@"%ld of %ld",(long)[np[@"index"] integerValue],(long)cnt):@"";
    _npTitle.text=np[@"title"]; _npArtist.text=np[@"artist"];
    NSString*cov=np[@"cover"];
    if(![cov isEqualToString:_npCoverURL]){
        _npCoverURL=cov;
        UIImage*hit=[MMCovers cached:cov];
        if(hit) _npCover.image=hit;                                   // kein Leeren -> kein Flackern
        else if(cov.length) [MMCovers load:cov completion:^(UIImage*img){ if(img && [cov isEqualToString:_npCoverURL]) _npCover.image=img; }];
    }
    BOOL vol=[NSDate timeIntervalSinceReferenceDate]<_volUntil;
    _volView.hidden=!vol; _npBar.hidden=vol; _npT1.hidden=vol; _npT2.hidden=vol;
    if(vol){ UIView*vb=[_volView viewWithTag:5]; float v=[MPMusicPlayerController applicationMusicPlayer].volume; _volFill.frame=CGRectMake(0,0,vb.bounds.size.width*v,vb.bounds.size.height); }
    BOOL loading=[MMSpotify isLoading];
    if(loading){ if(!_npSpin.isAnimating) [_npSpin startAnimating]; _npCover.alpha=0.45; } else { [_npSpin stopAnimating]; _npCover.alpha=1; }
    double cur=[MMAudio currentTime], dur=[MMAudio duration]; if(loading) cur=dur=0;
    _npFill.frame=CGRectMake(0,0,_npBar.bounds.size.width*(dur>0?MIN(1,cur/dur):0),_npBar.bounds.size.height);
    _npT1.text=loading?L(@"Loading …"):fmt(cur); _npT2.text=loading?@"":[@"-" stringByAppendingString:fmt(dur>cur?dur-cur:0)];
}
@end
