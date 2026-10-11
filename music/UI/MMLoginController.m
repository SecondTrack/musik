#import "MMLoginController.h"
#import "SpotTheme.h"
#import "MMSpotify.h"
#import "MMRootController.h"
#import "MMKeySetupController.h"
#import "MeshL10n.h"

@interface MMLoginController ()
@end

@implementation MMLoginController {
    UILabel *_status;
    BOOL _triedStored;
    // Login mit Code über ein anderes Gerät
    UIView *_pairBox;
    UILabel *_pairHint, *_pairCode, *_pairURL;
    UIButton *_pairBtn;
    BOOL _pairCancelled;
    NSUInteger _pairRun;
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor=[SpotTheme bg];
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;

    UIImageView*logo=[[UIImageView alloc] initWithFrame:CGRectMake(W/2-40,H*0.10,80,80)];
    logo.image=[SpotTheme logo:80]; [self.view addSubview:logo];

    UILabel*t=[[UILabel alloc] initWithFrame:CGRectMake(20,H*0.10+92,W-40,32)];
    t.text=@"Spotify"; t.font=[UIFont boldSystemFontOfSize:28]; t.textColor=[SpotTheme ink]; t.textAlignment=NSTextAlignmentCenter; t.backgroundColor=[UIColor clearColor]; [self.view addSubview:t];

    UILabel*sub=[[UILabel alloc] initWithFrame:CGRectMake(20,H*0.10+128,W-40,18)];
    sub.text=L(@"Log in with your Spotify account"); sub.font=[SpotTheme sub]; sub.textColor=[SpotTheme muted]; sub.textAlignment=NSTextAlignmentCenter; sub.backgroundColor=[UIColor clearColor]; [self.view addSubview:sub];

    CGFloat fy=H*0.10+170;
    _status=[[UILabel alloc] initWithFrame:CGRectMake(20,fy+182,W-40,80)];
    _status.font=[SpotTheme sub]; _status.textColor=[SpotTheme muted]; _status.textAlignment=NSTextAlignmentCenter; _status.numberOfLines=0; _status.backgroundColor=[UIColor clearColor];
    [self.view addSubview:_status];

    // ---- Login mit Code (spotify.com/pair) ----
    _pairBox=[[UIView alloc] initWithFrame:CGRectMake(20,fy-8,W-40,170)];
    _pairBox.backgroundColor=[UIColor clearColor]; [self.view addSubview:_pairBox];
    _pairHint=[[UILabel alloc] initWithFrame:CGRectMake(0,0,W-40,40)];
    _pairHint.text=L(@"On your phone or computer open"); _pairHint.numberOfLines=2;
    _pairHint.font=[SpotTheme sub]; _pairHint.textColor=[SpotTheme muted]; _pairHint.textAlignment=NSTextAlignmentCenter; _pairHint.backgroundColor=[UIColor clearColor];
    _pairURL=[[UILabel alloc] initWithFrame:CGRectMake(0,38,W-40,26)];
    _pairURL.text=@"spotify.com/pair"; _pairURL.font=[UIFont boldSystemFontOfSize:20]; _pairURL.textColor=[SpotTheme green];
    _pairURL.textAlignment=NSTextAlignmentCenter; _pairURL.backgroundColor=[UIColor clearColor];
    UILabel*and=[[UILabel alloc] initWithFrame:CGRectMake(0,66,W-40,18)];
    and.text=L(@"and enter this code:"); and.font=[SpotTheme sub]; and.textColor=[SpotTheme muted]; and.textAlignment=NSTextAlignmentCenter; and.backgroundColor=[UIColor clearColor];
    _pairCode=[[UILabel alloc] initWithFrame:CGRectMake(0,88,W-40,52)];
    _pairCode.text=@"…"; _pairCode.font=[UIFont fontWithName:@"Courier-Bold" size:38]; _pairCode.textColor=[SpotTheme ink];
    _pairCode.textAlignment=NSTextAlignmentCenter; _pairCode.backgroundColor=[UIColor clearColor]; _pairCode.adjustsFontSizeToFitWidth=YES;
    for(UIView*x in @[_pairHint,_pairURL,and,_pairCode]) [_pairBox addSubview:x];

    _pairBtn=[UIButton buttonWithType:UIButtonTypeCustom];
    _pairBtn.frame=CGRectMake(40,fy+118,W-80,50); _pairBtn.backgroundColor=[SpotTheme green]; _pairBtn.layer.cornerRadius=25;
    _pairBtn.titleLabel.font=[UIFont boldSystemFontOfSize:16];
    [_pairBtn setTitle:L(@"LOG IN WITH PHONE") forState:UIControlStateNormal]; [_pairBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_pairBtn addTarget:self action:@selector(startPairing) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_pairBtn];

    [self showPairing:NO];
    // Wenn gespeicherte Zugangsdaten existieren: erst mal nur Status (kein Geflacker)
    if([MMSpotify hasStoredCreds]) _status.text=L(@"Connecting …");
}

- (void)showPairing:(BOOL)show { _pairBox.hidden=!show; _pairBtn.hidden=YES; }

- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; _pairCancelled=YES; }

// Code bei Spotify holen, anzeigen und auf Bestätigung am anderen Gerät warten
- (void)startPairing {
    _pairCancelled=NO; NSUInteger run=++_pairRun;
    [self showPairing:YES]; _pairCode.text=@"…"; _status.text=L(@"Requesting code from Spotify …");
    [MMSpotify deviceLoginStart:^(NSDictionary*info,NSString*err){
        if(run!=_pairRun) return;
        if(!info){ [self showPairing:NO]; _pairBtn.hidden=NO; [_pairBtn setTitle:L(@"TRY AGAIN") forState:UIControlStateNormal];
                   _status.text=[NSString stringWithFormat:@"❌ %@",err?:L(@"Login failed")]; return; }
        _pairCode.text=info[@"user_code"];
        _status.text=L(@"Waiting for confirmation …");
        [UIApplication sharedApplication].idleTimerDisabled=YES;     // Display an lassen, bis bestätigt
        __weak MMLoginController*ws=self;
        [MMSpotify deviceLoginPoll:info cancelled:^BOOL{ MMLoginController*s=ws; return !s||s->_pairCancelled||run!=s->_pairRun; }
                        completion:^(NSString*token,NSString*perr){
            [UIApplication sharedApplication].idleTimerDisabled=NO;
            MMLoginController*s=ws; if(!s||run!=s->_pairRun||s->_pairCancelled) return;
            if(!token){ [s showPairing:NO]; s->_pairBtn.hidden=NO; [s->_pairBtn setTitle:L(@"NEW CODE") forState:UIControlStateNormal];
                        s->_status.text=[NSString stringWithFormat:@"❌ %@",perr?:L(@"Login failed")]; return; }
            s->_status.text=L(@"Confirmed – logging in …");
            [MMSpotify loginWithToken:token completion:^(BOOL ok,NSString*u,NSString*e){
                if(ok){ s->_status.text=LF(@"✅ %@ — remembered permanently",u); [s enterApp]; }
                else { [s showPairing:NO]; s->_pairBtn.hidden=NO; [s->_pairBtn setTitle:L(@"TRY AGAIN") forState:UIControlStateNormal];
                       s->_status.text=[NSString stringWithFormat:@"❌ %@",e?:L(@"Login failed")]; }
            }];
        }];
    }];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if(_triedStored) return;
    _triedStored=YES;
    if(self.forcePairing){
        _status.text=L(@"Your Spotify login expired. Confirm once on your phone:");
        [self startPairing];
    } else if([MMSpotify hasStoredCreds]){
        [MMSpotify startNetworkWatch];
        if(![MMSpotify networkReachable]){ [self waitForNetwork:0]; return; }
        [self loginStored];
    } else {
        [self startPairing];                   // noch nie angemeldet -> Code-Login
    }
}

// WLAN kommt nach dem Aufwachen oft erst nach ein paar Sekunden -> bis 8 s warten, sonst offline starten
- (void)waitForNetwork:(int)tries {
    if([MMSpotify networkReachable]){ [self loginStored]; return; }
    if(tries>=16){ _status.text=L(@"No connection – starting offline …"); [self enterApp]; return; }
    _status.text=L(@"Waiting for Wi-Fi …");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ [self waitForNetwork:tries+1]; });
}
- (void)loginStored {
    _status.text=L(@"Logging in …");
    [MMSpotify loginStoredWithCompletion:^(BOOL ok,NSString*u,NSString*e){
        if(ok) [self enterApp];
        else if([MMSpotify lastLoginRejected]){ _status.text=L(@"Saved login invalid — please sign in again."); [self startPairing]; }
        else { _status.text=L(@"No connection – starting offline …"); [self enterApp]; }   // kein Netz: Login bleibt, Wiedergabe verbindet später neu
    }];
}

- (void)enterApp {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.8*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        UIWindow*w=self.view.window;
        // Einmalig nach dem ersten Pairing: Anleitung für den eigenen Such-Schlüssel (überspringbar)
        NSUserDefaults*u=[NSUserDefaults standardUserDefaults];
        if(![MMSpotify hasSearchKey] && ![u boolForKey:@"keySetupShown"]){
            [u setBool:YES forKey:@"keySetupShown"]; [u synchronize];
            MMKeySetupController*k=[[MMKeySetupController alloc] init]; k.skippable=YES;
            k.onDone=^(BOOL saved){ w.rootViewController=[[MMRootController alloc] init]; };
            w.rootViewController=k; return;
        }
        w.rootViewController=[[MMRootController alloc] init];
    });
}
@end
