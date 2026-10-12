#import "MMOrbitMode.h"
#import <QuartzCore/QuartzCore.h>
#import "MMRootController.h"
#import "MMAudio.h"
#import "MMSpotify.h"
#import "MMCovers.h"
#import "SpotTheme.h"
#import "MeshL10n.h"

#define NPLAN 11            // sichtbare Planeten (gewählter ± 5)
#define STEP (M_PI/6)       // 30° zwischen zwei Planeten

static UIFont *light(CGFloat s){ return [UIFont fontWithName:@"HelveticaNeue-Light" size:s]?:[UIFont systemFontOfSize:s]; }
static UIFont *thin(CGFloat s){ return [UIFont fontWithName:@"HelveticaNeue-UltraLight" size:s]?:light(s); }

@implementation MMOrbitMode {
    CGFloat W, H, _R, _dr; CGPoint _c;
    double _pos, _target;            // Position auf der Umlaufbahn (Index, stetig)
    BOOL _dragging, _onRing, _onDisc, _moved; double _lastAng; CGPoint _start;
    NSInteger _lastIdx;
    UIView *_plan[NPLAN]; UIImageView *_planImg[NPLAN]; UILabel *_planLbl[NPLAN]; NSInteger _planFor[NPLAN];
    UIImageView *_disc; CAShapeLayer *_halo, *_prog, *_track, *_orbit;
    UILabel *_selTitle, *_selSub, *_crumb, *_npTitle, *_npTime, *_dl;
    UIActivityIndicatorView *_spin;
    CADisplayLink *_link; double _rot; float _lvl;
    NSTimer *_holdTimer;
}

- (void)loadView {
    [super loadView];
    W=self.view.bounds.size.width; H=self.view.bounds.size.height;
    _c=CGPointMake(W/2,H*0.54); _R=128; _dr=70;

    _orbit=[CAShapeLayer layer]; _orbit.fillColor=nil; _orbit.lineWidth=1; _orbit.strokeColor=[UIColor colorWithWhite:1 alpha:0.09].CGColor;
    _orbit.path=[UIBezierPath bezierPathWithArcCenter:_c radius:_R startAngle:0 endAngle:2*M_PI clockwise:YES].CGPath;
    _orbit.lineDashPattern=@[@1,@5]; [self.view.layer addSublayer:_orbit];

    _halo=[CAShapeLayer layer]; _halo.frame=CGRectMake(_c.x-_dr,_c.y-_dr,_dr*2,_dr*2);
    _halo.path=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0,0,_dr*2,_dr*2)].CGPath; [self.view.layer addSublayer:_halo];
    _disc=[[UIImageView alloc] initWithFrame:CGRectMake(_c.x-_dr,_c.y-_dr,_dr*2,_dr*2)]; _disc.backgroundColor=[UIColor colorWithWhite:0.12 alpha:1];
    _disc.contentMode=UIViewContentModeScaleAspectFill; _disc.layer.cornerRadius=_dr; _disc.layer.masksToBounds=YES; [self.view addSubview:_disc];
    CAShapeLayer*hole=[CAShapeLayer layer]; hole.path=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(_c.x-5,_c.y-5,10,10)].CGPath;
    hole.fillColor=[UIColor blackColor].CGColor; hole.strokeColor=[UIColor colorWithWhite:1 alpha:0.2].CGColor; [self.view.layer addSublayer:hole];
    UIBezierPath*pr=[UIBezierPath bezierPathWithArcCenter:_c radius:_dr+9 startAngle:-M_PI_2 endAngle:1.5*M_PI clockwise:YES];
    _track=[CAShapeLayer layer]; _track.path=pr.CGPath; _track.fillColor=nil; _track.lineWidth=1; _track.strokeColor=[UIColor colorWithWhite:1 alpha:0.12].CGColor; [self.view.layer addSublayer:_track];
    _prog=[CAShapeLayer layer]; _prog.path=pr.CGPath; _prog.fillColor=nil; _prog.lineWidth=2; _prog.lineCap=kCALineCapRound; _prog.strokeEnd=0; [self.view.layer addSublayer:_prog];

    for(int i=0;i<NPLAN;i++){
        UIView*p=[[UIView alloc] initWithFrame:CGRectMake(0,0,44,44)]; p.layer.cornerRadius=22; p.backgroundColor=[UIColor colorWithWhite:0.1 alpha:1];
        p.layer.borderWidth=1; p.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.25].CGColor; p.clipsToBounds=YES; p.userInteractionEnabled=NO;
        UILabel*l=[[UILabel alloc] initWithFrame:p.bounds]; l.backgroundColor=[UIColor clearColor]; l.textAlignment=NSTextAlignmentCenter; l.font=thin(22); l.textColor=[UIColor whiteColor];
        UIImageView*iv=[[UIImageView alloc] initWithFrame:p.bounds]; iv.contentMode=UIViewContentModeScaleAspectFill;
        [p addSubview:l]; [p addSubview:iv]; [self.view addSubview:p];
        _plan[i]=p; _planImg[i]=iv; _planLbl[i]=l; _planFor[i]=-1; p.hidden=YES;
    }

    _crumb=[self label:CGRectMake(12,8,W-24,16) font:light(11) color:[UIColor colorWithWhite:1 alpha:0.45] align:NSTextAlignmentLeft];
    _selTitle=[self label:CGRectMake(20,34,W-40,34) font:thin(28) color:[UIColor whiteColor] align:NSTextAlignmentCenter];
    _selSub=[self label:CGRectMake(20,70,W-40,16) font:light(11) color:[UIColor colorWithWhite:1 alpha:0.5] align:NSTextAlignmentCenter];
    _npTitle=[self label:CGRectMake(20,H-46,W-40,16) font:light(12) color:[UIColor colorWithWhite:1 alpha:0.75] align:NSTextAlignmentCenter];
    _npTime=[self label:CGRectMake(20,H-27,W-40,14) font:light(10) color:[UIColor colorWithWhite:1 alpha:0.35] align:NSTextAlignmentCenter];
    _dl=[self label:CGRectMake(12,8,W-24,16) font:light(11) color:[SpotTheme green] align:NSTextAlignmentRight];
    _spin=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite]; _spin.hidesWhenStopped=YES;
    _spin.center=_c; [self.view addSubview:_spin];
    [self nowPlayingChanged];
}
- (UILabel *)label:(CGRect)r font:(UIFont *)f color:(UIColor *)c align:(NSTextAlignment)a {
    UILabel*l=[[UILabel alloc] initWithFrame:r]; l.backgroundColor=[UIColor clearColor]; l.font=f; l.textColor=c; l.textAlignment=a; l.userInteractionEnabled=NO;
    [self.view addSubview:l]; return l;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _link=[CADisplayLink displayLinkWithTarget:self selector:@selector(frame:)]; _link.frameInterval=2;   // 30 fps
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}
- (void)stop { [_link invalidate]; _link=nil; [super stop]; }

#pragma mark - Inhalt

- (void)levelChanged {
    NSMutableDictionary*m=[self top];
    _pos=_target=[m[@"sel"] doubleValue]; _lastIdx=(NSInteger)_pos;
    for(int i=0;i<NPLAN;i++) _planFor[i]=-1;
    NSArray*cr=[self crumbs]; _crumb.text=cr.count?[@"‹  " stringByAppendingString:[[cr componentsJoinedByString:@"  ·  "] lowercaseString]]:@"orbit";
    [self updateSelection];
}
- (void)updateSelection {
    NSMutableDictionary*m=[self top]; NSArray*it=m[@"items"];
    if([m[@"loading"] boolValue]){ _selTitle.text=L(@"Loading…"); _selSub.text=@""; return; }
    NSInteger s=MAX(0,MIN((NSInteger)it.count-1,(NSInteger)lround(_pos)));
    if(!it.count){ _selTitle.text=@""; _selSub.text=@""; return; }
    _selTitle.text=it[s][@"title"];
    NSString*sub=it[s][@"sub"]?:@"";
    _selSub.attributedText=[[NSAttributedString alloc] initWithString:[sub uppercaseString] attributes:@{NSKernAttributeName:@2,NSFontAttributeName:light(10),NSForegroundColorAttributeName:[UIColor colorWithWhite:1 alpha:0.5]}];
    _selSub.textAlignment=NSTextAlignmentCenter;
}
- (void)nowPlayingChanged {
    NSDictionary*np=[[MMRootController shared] nowPlaying];
    _npTitle.text=np?[NSString stringWithFormat:@"%@  —  %@",np[@"title"],np[@"artist"]]:@"";
    if(self.nowCover && _disc.image!=self.nowCover)
        [UIView transitionWithView:_disc duration:0.4 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{ _disc.image=self.nowCover; } completion:nil];
    _prog.strokeColor=self.accent.CGColor; _halo.fillColor=[self.accent colorWithAlphaComponent:0.2].CGColor;
    for(int i=0;i<NPLAN;i++) _planFor[i]=-1;   // „spielt gerade“-Markierung neu setzen
}
- (void)setDownloadText:(NSString *)t { _dl.text=t; _crumb.hidden=t.length>0; }

static NSString *fmt(double s){ if(s<0||isnan(s))s=0; int m=(int)s/60, x=(int)s%60; return [NSString stringWithFormat:@"%d:%02d",m,x]; }

- (void)frame:(CADisplayLink *)l {
    NSMutableDictionary*m=[self top]; NSArray*it=m[@"items"]; NSInteger n=[m[@"loading"] boolValue]?0:it.count;
    if(!_dragging && fabs(_target-_pos)>0.001) _pos+=(_target-_pos)*0.3; else if(!_dragging) _pos=_target;
    NSInteger idx=(NSInteger)lround(_pos);
    if(n && idx!=_lastIdx && idx>=0 && idx<n){ _lastIdx=idx; [self click]; m[@"sel"]=@(idx); [self updateSelection]; }

    [CATransaction begin]; [CATransaction setDisableActions:YES];
    NSInteger base=(NSInteger)lround(_pos);
    for(int k=0;k<NPLAN;k++){
        NSInteger i=base+k-NPLAN/2; UIView*p=_plan[k];
        if(i<0 || i>=n){ p.hidden=YES; continue; }
        double d=i-_pos, ang=-M_PI_2+d*STEP, ad=fabs(d);
        if(ad>5.4){ p.hidden=YES; continue; }
        p.hidden=NO;
        if(_planFor[k]!=i) [self assign:k index:i item:it[i]];
        CGFloat sc=(ad<1?1.3-0.3*ad:1.0)*(1-MIN(ad,5)*0.07);
        p.center=CGPointMake(_c.x+_R*cos(ang),_c.y+_R*sin(ang));
        p.transform=CGAffineTransformMakeScale(sc,sc);
        p.alpha=MAX(0.08,1-ad*0.19);
        p.layer.borderColor=(ad<0.5?self.accent:[UIColor colorWithWhite:1 alpha:0.25]).CGColor;
    }
    double cur=[MMAudio currentTime], dur=[MMAudio duration]; BOOL loading=[MMSpotify isLoading];
    float lv=0; if(![MMAudio visual:&lv bass:NULL wave:NULL]) lv=0;
    _lvl+=(lv*2.2f-_lvl)*0.3f; if(_lvl>1)_lvl=1;
    if([MMAudio isPlaying]) _rot+=2*M_PI/(24.0*30.0);
    _disc.transform=CGAffineTransformMakeRotation(_rot);
    CGFloat hs=1.0+_lvl*0.3; _halo.transform=CATransform3DMakeScale(hs,hs,1);
    _prog.strokeEnd=(dur>0&&!loading)?cur/dur:0;
    [CATransaction commit];
    if(loading){ if(!_spin.isAnimating)[_spin startAnimating]; } else [_spin stopAnimating];
    _npTime.text=(dur>0&&!loading)?[NSString stringWithFormat:@"%@  /  %@",fmt(cur),fmt(dur)]:@"";
    if([m[@"loading"] boolValue]) _selTitle.alpha=0.45+0.35*sin(CACurrentMediaTime()*4); else _selTitle.alpha=1;
}

- (void)assign:(int)k index:(NSInteger)i item:(NSDictionary *)e {
    _planFor[k]=i; UIImageView*iv=_planImg[k]; iv.image=nil;
    NSString*t=e[@"title"]?:@""; _planLbl[k].text=t.length?[[t substringToIndex:1] lowercaseString]:@"";
    BOOL playing=[e[@"tid"] length] && [e[@"tid"] isEqualToString:[self currentTrackId]];
    _plan[k].backgroundColor=playing?[self.accent colorWithAlphaComponent:0.5]:[UIColor colorWithWhite:0.1 alpha:1];
    NSString*u=e[@"cover"]; if(!u.length) return;
    UIImage*c=[MMCovers cached:u]; if(c){ iv.image=c; return; }
    __weak MMOrbitMode*ws=self;
    [MMCovers load:u completion:^(UIImage*img){ MMOrbitMode*ss=ws; if(ss && ss->_planFor[k]==i && img) iv.image=img; }];
}

#pragma mark - Bedienung

- (BOOL)onRing:(CGPoint)p { CGFloat d=hypot(p.x-_c.x,p.y-_c.y); return d>_dr+14 && d<_R+40; }
- (BOOL)onDisc:(CGPoint)p { return hypot(p.x-_c.x,p.y-_c.y)<=_dr+12; }
- (double)angOf:(CGPoint)p { return atan2(p.y-_c.y,p.x-_c.x); }

- (void)touchesBegan:(NSSet *)ts withEvent:(UIEvent *)e {
    CGPoint p=[[ts anyObject] locationInView:self.view]; _start=p; _moved=NO;
    _onRing=[self onRing:p]; _onDisc=[self onDisc:p];
    if(_onRing){ _dragging=YES; _lastAng=[self angOf:p]; }
    if(_onDisc){ [_holdTimer invalidate]; _holdTimer=[NSTimer scheduledTimerWithTimeInterval:0.55 target:self selector:@selector(held) userInfo:nil repeats:NO]; }
}
- (void)touchesMoved:(NSSet *)ts withEvent:(UIEvent *)e {
    CGPoint p=[[ts anyObject] locationInView:self.view];
    if(hypot(p.x-_start.x,p.y-_start.y)>8){ _moved=YES; [_holdTimer invalidate]; _holdTimer=nil; }
    if(!_onRing) return;
    double a=[self angOf:p], d=a-_lastAng; if(d>M_PI)d-=2*M_PI; if(d<-M_PI)d+=2*M_PI; _lastAng=a;
    NSInteger n=[[self top][@"items"] count];
    _pos-=d/STEP;
    if(_pos<-0.4)_pos=-0.4; if(_pos>n-0.6)_pos=MAX(-0.4,n-0.6);   // weiches Ende
}
- (void)touchesEnded:(NSSet *)ts withEvent:(UIEvent *)e {
    CGPoint p=[[ts anyObject] locationInView:self.view];
    BOOL held=(_onDisc && !_moved && _holdTimer==nil); [_holdTimer invalidate]; _holdTimer=nil;
    NSInteger n=[[self top][@"items"] count];
    if(_dragging){ _dragging=NO; _target=MAX(0,MIN(n-1,lround(_pos))); }
    if(_moved){
        CGFloat dx=p.x-_start.x, dy=p.y-_start.y;
        if(!_onRing && dx>70 && fabs(dx)>fabs(dy)*1.5){ [self click]; [self pop]; }   // nach rechts wischen = zurück
        return;
    }
    if(held) return;
    if(p.y<28 && [self stack].count>1){ [self click]; [self pop]; return; }        // Brotkrumen oben = zurück
    if(_onDisc){ [[MMRootController shared] togglePlayPause]; return; }
    // Planet getroffen? gewählter -> öffnen, anderer -> hindrehen
    for(int k=0;k<NPLAN;k++){
        UIView*pl=_plan[k]; if(pl.hidden||_planFor[k]<0) continue;
        if(hypot(p.x-pl.center.x,p.y-pl.center.y)<28){
            NSInteger i=_planFor[k];
            if(i==lround(_pos)) [self openSelected]; else _target=i;
            return;
        }
    }
}
- (void)touchesCancelled:(NSSet *)ts withEvent:(UIEvent *)e { [_holdTimer invalidate]; _holdTimer=nil; if(_dragging){ _dragging=NO; _target=MAX(0,lround(_pos)); } }
- (void)held { _holdTimer=nil; if(_onDisc && !_moved) [[MMRootController shared] openPlayerWithStyle:@"orbit"]; }
- (void)openSelected {
    // kleiner „Sprung“ des Planeten, dann öffnen
    for(int k=0;k<NPLAN;k++) if(_planFor[k]==lround(_pos)){ UIView*p=_plan[k];
        [UIView animateWithDuration:0.12 animations:^{ p.alpha=0.3; } completion:^(BOOL f){ p.alpha=1; }]; }
    [self activateSelected];
}
@end
