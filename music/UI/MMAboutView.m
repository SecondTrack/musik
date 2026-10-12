#import "MMAboutView.h"
#import "MeshL10n.h"
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>

#define ST_REBOOT @"https://github.com/SecondTrack/reboot/releases/latest"   // bis es eine Cydia-Quelle gibt
#define REBOOT_ID @"de.mesh.shop"
static BOOL rebootInstalled(void){ return [[NSFileManager defaultManager] fileExistsAtPath:@"/Applications/Shop.app/Info.plist"]; }

static UIColor* RGB(int r,int g,int b){ return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1]; }

@implementation MMAboutView {
    UIScrollView *_sc; CGFloat _y, _W;
}

+ (void)showIn:(UIView *)host {
    MMAboutView*v=[[MMAboutView alloc] initWithFrame:host.bounds];
    v.frame=CGRectOffset(host.bounds,0,host.bounds.size.height); [host addSubview:v];
    [UIView animateWithDuration:0.3 animations:^{ v.frame=host.bounds; }];
}
- (void)close {
    [UIView animateWithDuration:0.25 animations:^{ self.frame=CGRectOffset(self.frame,0,self.frame.size.height); } completion:^(BOOL f){ [self removeFromSuperview]; }];
}

- (UILabel *)text:(NSString *)t size:(CGFloat)s bold:(BOOL)b color:(UIColor *)c x:(CGFloat)x w:(CGFloat)w center:(BOOL)ctr in:(UIView *)v {
    UILabel*l=[[UILabel alloc] initWithFrame:CGRectMake(x,_y,w,20)];
    l.text=t; l.font=b?[UIFont boldSystemFontOfSize:s]:[UIFont systemFontOfSize:s]; l.textColor=c; l.numberOfLines=0;
    l.backgroundColor=[UIColor clearColor]; l.textAlignment=ctr?NSTextAlignmentCenter:NSTextAlignmentLeft;
    [l sizeToFit]; l.frame=CGRectMake(x,_y,w,l.frame.size.height); [v addSubview:l]; return l;
}
- (UIButton *)button:(NSString *)t filled:(BOOL)filled action:(SEL)sel in:(UIView *)v x:(CGFloat)x w:(CGFloat)w {
    UIButton*b=[UIButton buttonWithType:UIButtonTypeCustom]; b.frame=CGRectMake(x,_y,w,44); b.layer.cornerRadius=22;
    b.titleLabel.font=[UIFont boldSystemFontOfSize:15]; [b setTitle:t forState:UIControlStateNormal];
    if(filled){ b.backgroundColor=RGB(229,37,42); [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal]; }
    else { b.layer.borderColor=RGB(90,90,96).CGColor; b.layer.borderWidth=1; [b setTitleColor:RGB(245,245,247) forState:UIControlStateNormal]; }
    [b setTitleColor:[UIColor colorWithWhite:1 alpha:0.5] forState:UIControlStateHighlighted];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside]; [v addSubview:b]; _y+=44; return b;
}

- (id)initWithFrame:(CGRect)f {
    if(!(self=[super initWithFrame:f])) return nil;
    self.backgroundColor=[UIColor blackColor];
    _W=f.size.width; CGFloat W=_W, H=f.size.height;
    _sc=[[UIScrollView alloc] initWithFrame:self.bounds]; _sc.alwaysBounceVertical=YES; [self addSubview:_sc];
    UIColor*ink=RGB(245,245,247), *mut=RGB(150,150,156);

    // Kopf: Fertig
    UIButton*done=[UIButton buttonWithType:UIButtonTypeCustom]; done.frame=CGRectMake(W-84,10,76,32);
    [done setTitle:L(@"Done") forState:UIControlStateNormal]; done.titleLabel.font=[UIFont boldSystemFontOfSize:15];
    [done setTitleColor:ink forState:UIControlStateNormal]; [done addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:done];

    // Second-Track-Logo (Adler + Graffiti, aus dem Shop gerendert)
    _y=44;
    UIImageView*logo=[[UIImageView alloc] initWithImage:[UIImage imageNamed:@"secondtrack"]];
    CGFloat lw=MIN(240,W-60), lh=lw*150/260.0; logo.frame=CGRectMake((W-lw)/2,_y,lw,lh); [_sc addSubview:logo];
    _y+=lh+14;
    NSString*ver=[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]?:@"";
    [self text:LF(@"Music for iPod touch · Version %@",ver) size:13 bold:NO color:mut x:20 w:W-40 center:YES in:_sc]; _y+=24;
    UILabel*t=[self text:L(@"A Second Track app. We give old iPods a second life: used devices, lovingly refurbished – and new apps that make them useful again today.") size:15 bold:NO color:ink x:24 w:W-48 center:YES in:_sc];
    _y+=t.frame.size.height+18;

    // Karte: Reboot Appstore
    UIView*card=[[UIView alloc] initWithFrame:CGRectMake(14,_y,W-28,10)]; card.backgroundColor=RGB(22,22,24); card.layer.cornerRadius=14;
    card.layer.borderColor=RGB(48,48,52).CGColor; card.layer.borderWidth=1; [_sc addSubview:card];
    CGFloat cy0=_y; _y=16;
    UIImageView*ic=[[UIImageView alloc] initWithFrame:CGRectMake(16,_y,64,64)]; ic.image=[UIImage imageNamed:@"reboot-icon"]; ic.layer.cornerRadius=14; ic.clipsToBounds=YES; [card addSubview:ic];
    CGFloat tx=94, tw=card.bounds.size.width-tx-14;
    UILabel*lab=[self text:L(@"MORE APPS FOR YOUR iPOD") size:11 bold:YES color:RGB(229,37,42) x:tx w:tw center:NO in:card]; _y+=lab.frame.size.height+2;
    UILabel*nm=[self text:@"Reboot Appstore" size:19 bold:YES color:ink x:tx w:tw center:NO in:card]; _y+=nm.frame.size.height+1;
    [self text:L(@"The App Store on your iPod") size:13 bold:NO color:mut x:tx w:tw center:NO in:card];
    _y=MAX(_y+20,16+64)+12;
    UILabel*d=[self text:L(@"Messenger, videos, browser, files and more – apps built for iPod touch 2G to 4G. Browse them all with icons, descriptions and screenshots, and open installed apps with one tap.") size:14 bold:NO color:ink x:16 w:card.bounds.size.width-32 center:NO in:card];
    _y+=d.frame.size.height+14;
    BOOL have=rebootInstalled();
    [self button:(have?L(@"Open Reboot"):L(@"Download Reboot")) filled:YES action:@selector(openReboot) in:card x:16 w:card.bounds.size.width-32]; _y+=8;
    [self text:(have?L(@"Install and update all apps right on your iPod."):L(@"Free · for jailbroken iPod touch")) size:12 bold:NO color:mut x:16 w:card.bounds.size.width-32 center:YES in:card]; _y+=30;
    card.frame=CGRectMake(14,cy0,W-28,_y); _y=cy0+_y+22;

    // Kleingedrucktes
    UILabel*fine=[self text:L(@"Not affiliated with Spotify or Apple. Spotify is a trademark of Spotify AB. iPod is a trademark of Apple Inc.") size:11 bold:NO color:RGB(110,110,116) x:24 w:W-48 center:YES in:_sc];
    _y+=fine.frame.size.height+30;
    _sc.contentSize=CGSizeMake(W,MAX(_y,H+1));
    return self;
}
// Installiert: Store direkt starten. Sonst: Download-Seite.
- (void)openReboot {
    if(rebootInstalled()){
        void*h=dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",RTLD_LAZY);
        int (*f)(CFStringRef,Boolean)=h?dlsym(h,"SBSLaunchApplicationWithIdentifier"):NULL;
        if(f && f((__bridge CFStringRef)REBOOT_ID,false)==0) return;
    }
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:ST_REBOOT]];
}
@end
