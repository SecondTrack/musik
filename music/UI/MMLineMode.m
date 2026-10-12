#import "MMLineMode.h"
#import <QuartzCore/QuartzCore.h>
#import "MMRootController.h"
#import "MMAudio.h"
#import "MMSpotify.h"
#import "SpotTheme.h"
#import "MeshL10n.h"

#define NLBL 9              // sichtbare Zeilen
#define NPTS 64
#define ROW 40.0            // Abstand der Zeilen über der Linie

static UIFont *light(CGFloat s){ return [UIFont fontWithName:@"HelveticaNeue-Light" size:s]?:[UIFont systemFontOfSize:s]; }
static UIFont *thin(CGFloat s){ return [UIFont fontWithName:@"HelveticaNeue-UltraLight" size:s]?:light(s); }

@implementation MMLineMode {
    CGFloat W, H, _lineY;
    double _pos, _target, _vel;
    BOOL _dragging, _moved; CGPoint _start, _last; NSTimeInterval _lastT;
    NSInteger _lastIdx;
    UILabel *_lbl[NLBL]; NSInteger _lblFor[NLBL];
    UILabel *_sub, *_crumb, *_npTitle, *_npTime, *_dl;
    CAShapeLayer *_lineA, *_lineB; CALayer *_dot;
    UIActivityIndicatorView *_spin;
    CADisplayLink *_link; float _wave[NPTS];
    NSTimer *_holdTimer;
}

- (void)loadView {
    [super loadView];
    W=self.view.bounds.size.width; H=self.view.bounds.size.height; _lineY=floor(H*0.5);
    for(int i=0;i<NLBL;i++){
        UILabel*l=[[UILabel alloc] initWithFrame:CGRectMake(0,0,W-36,44)]; l.backgroundColor=[UIColor clearColor]; l.font=thin(36); l.textColor=[UIColor whiteColor];
        l.lineBreakMode=NSLineBreakByTruncatingTail; l.layer.anchorPoint=CGPointMake(0,1); l.userInteractionEnabled=NO; l.hidden=YES;
        [self.view addSubview:l]; _lbl[i]=l; _lblFor[i]=-1;
    }
    _lineB=[CAShapeLayer layer]; _lineB.fillColor=nil; _lineB.strokeColor=[UIColor colorWithWhite:1 alpha:0.3].CGColor; _lineB.lineWidth=1.2; _lineB.lineJoin=kCALineJoinRound;
    _lineA=[CAShapeLayer layer]; _lineA.fillColor=nil; _lineA.lineWidth=1.8; _lineA.lineJoin=kCALineJoinRound; _lineA.lineCap=kCALineCapRound;
    [self.view.layer addSublayer:_lineB]; [self.view.layer addSublayer:_lineA];
    _dot=[CALayer layer]; _dot.bounds=CGRectMake(0,0,6,6); _dot.cornerRadius=3; _dot.backgroundColor=[UIColor whiteColor].CGColor; [self.view.layer addSublayer:_dot];

    _sub=[self label:CGRectMake(20,_lineY+8,W-40,16) font:light(12) color:[SpotTheme green] align:NSTextAlignmentLeft];
    _crumb=[self label:CGRectMake(20,12,W-40,16) font:light(11) color:[UIColor colorWithWhite:1 alpha:0.4] align:NSTextAlignmentLeft];
    _dl=[self label:CGRectMake(20,12,W-40,16) font:light(11) color:[SpotTheme green] align:NSTextAlignmentRight];
    UIView*bar=[[UIView alloc] initWithFrame:CGRectMake(0,H-54,W,54)]; bar.userInteractionEnabled=NO;
    CAGradientLayer*g=[CAGradientLayer layer]; g.frame=bar.bounds; g.colors=@[(id)[UIColor colorWithWhite:0 alpha:0].CGColor,(id)[UIColor blackColor].CGColor];
    [bar.layer addSublayer:g]; [self.view addSubview:bar];
    _npTitle=[self label:CGRectMake(20,H-34,W-100,16) font:light(12) color:[UIColor colorWithWhite:1 alpha:0.8] align:NSTextAlignmentLeft];
    _npTime=[self label:CGRectMake(W-90,H-34,70,16) font:light(11) color:[UIColor colorWithWhite:1 alpha:0.4] align:NSTextAlignmentRight];
    _spin=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite]; _spin.hidesWhenStopped=YES;
    _spin.center=CGPointMake(W-30,_lineY-22); [self.view addSubview:_spin];
    [self nowPlayingChanged];
}
- (UILabel *)label:(CGRect)r font:(UIFont *)f color:(UIColor *)c align:(NSTextAlignment)a {
    UILabel*l=[[UILabel alloc] initWithFrame:r]; l.backgroundColor=[UIColor clearColor]; l.font=f; l.textColor=c; l.textAlignment=a; l.userInteractionEnabled=NO;
    [self.view addSubview:l]; return l;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    _link=[CADisplayLink displayLinkWithTarget:self selector:@selector(frame:)]; _link.frameInterval=2;
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}
- (void)stop { [_link invalidate]; _link=nil; [super stop]; }

#pragma mark - Inhalt

- (void)levelChanged {
    NSMutableDictionary*m=[self top];
    _pos=_target=[m[@"sel"] doubleValue]; _vel=0; _lastIdx=(NSInteger)_pos;
    for(int i=0;i<NLBL;i++) _lblFor[i]=-1;
    NSArray*cr=[self crumbs];
    _crumb.text=cr.count?[@"‹  " stringByAppendingString:[[cr componentsJoinedByString:@" / "] lowercaseString]]:@"linie";
    [self updateSub];
}
- (void)updateSub {
    NSMutableDictionary*m=[self top]; NSArray*it=m[@"items"];
    if([m[@"loading"] boolValue]||!it.count){ _sub.text=[m[@"loading"] boolValue]?L(@"Loading…"):@""; return; }
    NSInteger s=MAX(0,MIN((NSInteger)it.count-1,(NSInteger)lround(_pos)));
    _sub.text=[it[s][@"sub"] lowercaseString]?:@"";
}
- (void)nowPlayingChanged {
    NSDictionary*np=[[MMRootController shared] nowPlaying];
    _npTitle.text=np?[[NSString stringWithFormat:@"%@ — %@",np[@"title"],np[@"artist"]] lowercaseString]:@"";
    _lineA.strokeColor=self.accent.CGColor; _sub.textColor=self.accent;
    for(int i=0;i<NLBL;i++) _lblFor[i]=-1;
}
- (void)setDownloadText:(NSString *)t { _dl.text=[t lowercaseString]; _crumb.hidden=t.length>0; }

static NSString *fmt(double s){ if(s<0||isnan(s))s=0; int m=(int)s/60, x=(int)s%60; return [NSString stringWithFormat:@"%d:%02d",m,x]; }

// Senkrechte Lage einer Zeile mit Abstand d zur gewählten (d<0 darüber, d>0 unter der Linie)
- (CGFloat)baseline:(double)d { return d<=0 ? _lineY-10+d*ROW : _lineY-10+d*66; }

- (void)frame:(CADisplayLink *)l {
    NSMutableDictionary*m=[self top]; NSArray*it=m[@"items"]; BOOL loadingLevel=[m[@"loading"] boolValue];
    NSInteger n=loadingLevel?0:it.count;
    if(!_dragging){
        if(fabs(_vel)>0.01){ _pos+=_vel; _vel*=0.88; if(_pos<0||_pos>n-1){ _vel=0; } }
        else { _vel=0; _target=MAX(0,MIN(n-1,lround(_pos))); _pos+=(_target-_pos)*0.3; }
        if(_pos<-0.5)_pos=-0.5; if(n && _pos>n-0.5)_pos=n-0.5;
    }
    NSInteger idx=(NSInteger)lround(_pos);
    if(n && idx!=_lastIdx && idx>=0 && idx<n){ _lastIdx=idx; [self click]; m[@"sel"]=@(idx); [self updateSub]; }

    [CATransaction begin]; [CATransaction setDisableActions:YES];
    NSInteger base=(NSInteger)lround(_pos);
    for(int k=0;k<NLBL;k++){
        NSInteger i=base+k-6; UILabel*lb=_lbl[k];          // 6 darüber, 2 darunter
        double d=i-_pos, ad=fabs(d);
        if(i<0||i>=n||d<-6.5||d>2.6){ lb.hidden=YES; continue; }
        if(_lblFor[k]!=i){
            _lblFor[k]=i; NSString*t=[it[i][@"title"] lowercaseString]?:@"";
            BOOL playing=[it[i][@"tid"] length] && [it[i][@"tid"] isEqualToString:[self currentTrackId]];
            lb.text=t; lb.textColor=playing?self.accent:[UIColor whiteColor];
        }
        lb.hidden=NO;
        CGFloat sc=ad<1?1-0.42*ad:0.58;
        lb.transform=CGAffineTransformMakeScale(sc,sc);
        lb.layer.position=CGPointMake(20,[self baseline:d]+8);
        lb.alpha=d<=0?MAX(0,1-ad*0.2):MAX(0,(1-d*0.55)*(d<1?1:0.8));
    }
    // Linie = Wellenform; gespielter Teil in Farbe
    double cur=[MMAudio currentTime], dur=[MMAudio duration]; BOOL loading=[MMSpotify isLoading];
    float wv[NPTS]; memset(wv,0,sizeof(wv)); BOOL live=[MMAudio visual:NULL bass:NULL wave:wv];
    for(int i=0;i<NPTS;i++) _wave[i]+=(wv[i]-_wave[i])*(live?0.5f:0.15f);
    double frac=(dur>0&&!loading)?cur/dur:0; if(frac>1)frac=1;
    CGFloat x0=0, x1=W, px=x0+(x1-x0)*frac, amp=34;
    UIBezierPath*a=[UIBezierPath bezierPath], *b=[UIBezierPath bezierPath]; BOOL split=NO; CGPoint prev=CGPointZero, head=CGPointMake(px,_lineY);
    for(int i=0;i<NPTS;i++){
        float v=MAX(-1,MIN(1,_wave[i])); CGFloat env=sin(M_PI*i/(NPTS-1));
        CGPoint p=CGPointMake(x0+(x1-x0)*i/(NPTS-1),_lineY-v*amp*env);
        if(i==0){ if(px>p.x)[a moveToPoint:p]; else { [b moveToPoint:p]; split=YES; } }
        else if(!split && p.x>px){ CGFloat t=(px-prev.x)/(p.x-prev.x); head=CGPointMake(px,prev.y+(p.y-prev.y)*t);
            [a addLineToPoint:head]; [b moveToPoint:head]; [b addLineToPoint:p]; split=YES; }
        else [(split?b:a) addLineToPoint:p];
        prev=p;
    }
    _lineA.path=a.CGPath; _lineB.path=b.CGPath; _dot.position=head; _dot.hidden=(dur<=0||loading);
    [CATransaction commit];
    if(loading){ if(!_spin.isAnimating)[_spin startAnimating]; } else [_spin stopAnimating];
    _npTime.text=(dur>0&&!loading)?[NSString stringWithFormat:@"%@ / %@",fmt(cur),fmt(dur)]:@"";
    _npTitle.alpha=[MMAudio isPlaying]||loading?1:0.45;
}

#pragma mark - Bedienung

- (void)touchesBegan:(NSSet *)ts withEvent:(UIEvent *)e {
    CGPoint p=[[ts anyObject] locationInView:self.view]; _start=_last=p; _lastT=CACurrentMediaTime(); _moved=NO; _dragging=YES; _vel=0;
    [_holdTimer invalidate]; _holdTimer=[NSTimer scheduledTimerWithTimeInterval:0.55 target:self selector:@selector(held) userInfo:nil repeats:NO];
}
- (void)touchesMoved:(NSSet *)ts withEvent:(UIEvent *)e {
    CGPoint p=[[ts anyObject] locationInView:self.view];
    if(!_moved && hypot(p.x-_start.x,p.y-_start.y)>8){ _moved=YES; [_holdTimer invalidate]; _holdTimer=nil; }
    if(!_moved) return;
    CGFloat dx=p.x-_start.x, dy=p.y-_start.y;
    if(fabs(dy)>=fabs(dx)*0.8){                         // senkrecht: Liste über die Linie schieben
        NSTimeInterval now=CACurrentMediaTime(); double step=-(p.y-_last.y)/ROW;
        _pos+=step; if(now>_lastT) _vel=step/((now-_lastT)*30.0);
        NSInteger n=[[self top][@"items"] count]; if(_pos<-0.5)_pos=-0.5; if(_pos>n-0.5)_pos=MAX(-0.5,n-0.5);
        _lastT=now;
    }
    _last=p;
}
- (void)touchesEnded:(NSSet *)ts withEvent:(UIEvent *)e {
    CGPoint p=[[ts anyObject] locationInView:self.view];
    BOOL wasHeld=(_holdTimer==nil && !_moved); [_holdTimer invalidate]; _holdTimer=nil; _dragging=NO;
    if(_moved){
        CGFloat dx=p.x-_start.x, dy=p.y-_start.y;
        if(dx>70 && fabs(dx)>fabs(dy)*1.5){ _vel=0; [self click]; [self pop]; }    // nach rechts = zurück
        if(fabs(_vel)>1.2) _vel=_vel>0?1.2:-1.2;
        return;
    }
    if(wasHeld) return;
    if(p.y<36 && [self stack].count>1){ [self click]; [self pop]; return; }
    if(p.y>H-56){ [[MMRootController shared] togglePlayPause]; return; }
    [self activateSelected];
}
- (void)touchesCancelled:(NSSet *)ts withEvent:(UIEvent *)e { [_holdTimer invalidate]; _holdTimer=nil; _dragging=NO; }
- (void)held { _holdTimer=nil; if(!_moved) [[MMRootController shared] openPlayerWithStyle:@"line"]; }
@end
