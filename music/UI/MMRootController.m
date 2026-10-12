#import "MMRootController.h"
#import "SpotTheme.h"
#import "MMStartController.h"
#import "MMSearchController.h"
#import "MMBrowseController.h"
#import "MMRadioController.h"
#import "MMLibraryController.h"
#import "MMPlayerController.h"
#import "MMArtPlayer.h"
#import "MMOrbitMode.h"
#import "MMLineMode.h"
#import "MMSpotify.h"
#import "MMClassicController.h"
#import "MMSheet.h"
#import "MMCoverFlowView.h"
#import "MMKeepAlive.h"
#import "MMAboutView.h"
#import "MMAudio.h"
#import "MMCovers.h"
#import "MeshL10n.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

// ---- Tab-Icons (schlichte Linien-Icons wie Spotify) ----
static UIImage *MMTabIcon(NSString *name, UIColor *c, CGFloat s) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    [c setStroke]; [c setFill];
    UIBezierPath *p = [UIBezierPath bezierPath]; p.lineWidth = s*0.075f; p.lineJoinStyle = kCGLineJoinRound; p.lineCapStyle = kCGLineCapRound;
    if ([name isEqualToString:@"home"]) {
        [p moveToPoint:CGPointMake(s*0.5,s*0.16)]; [p addLineToPoint:CGPointMake(s*0.85,s*0.46)];
        [p moveToPoint:CGPointMake(s*0.5,s*0.16)]; [p addLineToPoint:CGPointMake(s*0.15,s*0.46)];
        UIBezierPath *b=[UIBezierPath bezierPathWithRect:CGRectMake(s*0.26,s*0.44,s*0.48,s*0.4)]; [p appendPath:b]; [p stroke];
    } else if ([name isEqualToString:@"browse"]) {
        CGFloat g=s*0.1, w=s*0.3;
        for(int i=0;i<2;i++)for(int j=0;j<2;j++){ [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(s*0.2+j*(w+g),s*0.2+i*(w+g),w,w) cornerRadius:s*0.03] stroke]; }
    } else if ([name isEqualToString:@"search"]) {
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(s*0.22,s*0.22,s*0.4,s*0.4)] stroke];
        [p moveToPoint:CGPointMake(s*0.6,s*0.6)]; [p addLineToPoint:CGPointMake(s*0.8,s*0.8)]; [p stroke];
    } else if ([name isEqualToString:@"radio"]) {
        // zentriertes Broadcast-Symbol: Punkt in der Mitte + symmetrische Bögen links UND rechts
        // (vorher nur oben-rechts -> Schwerpunkt saß schief/höher als die anderen Icons)
        CGContextAddEllipseInRect(ctx, CGRectMake(s*0.44,s*0.44,s*0.12,s*0.12)); CGContextFillPath(ctx);
        for(int i=1;i<=2;i++){
            CGFloat r=s*0.14*i+s*0.03;
            UIBezierPath*rt=[UIBezierPath bezierPathWithArcCenter:CGPointMake(s*0.5,s*0.5) radius:r startAngle:-M_PI/4 endAngle:M_PI/4 clockwise:YES]; rt.lineWidth=s*0.07; rt.lineCapStyle=kCGLineCapRound; [rt stroke];
            UIBezierPath*lf=[UIBezierPath bezierPathWithArcCenter:CGPointMake(s*0.5,s*0.5) radius:r startAngle:M_PI-M_PI/4 endAngle:M_PI+M_PI/4 clockwise:YES]; lf.lineWidth=s*0.07; lf.lineCapStyle=kCGLineCapRound; [lf stroke];
        }
    } else { // library
        [p moveToPoint:CGPointMake(s*0.3,s*0.2)];[p addLineToPoint:CGPointMake(s*0.3,s*0.8)];
        [p moveToPoint:CGPointMake(s*0.45,s*0.2)];[p addLineToPoint:CGPointMake(s*0.45,s*0.8)];
        [p stroke];
        UIBezierPath*bar=[UIBezierPath bezierPathWithRect:CGRectMake(s*0.58,s*0.22,s*0.14,s*0.58)]; [[UIColor clearColor] setFill];
        CGContextSaveGState(ctx); CGContextTranslateCTM(ctx,s*0.66,s*0.5); CGContextRotateCTM(ctx,0.26); CGContextTranslateCTM(ctx,-s*0.66,-s*0.5);
        [bar stroke]; CGContextRestoreGState(ctx);
    }
    UIImage *img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img;
}

static MMRootController *gRoot;

@implementation MMRootController {
    UIView *_content, *_tabBar, *_npBar, *_npCover;
    UILabel *_npTitle, *_npArtist;
    UIButton *_npPlay;
    UIActivityIndicatorView *_npSpinner;
    NSArray *_tabs; NSMutableArray *_tabBtns, *_vcs;
    NSInteger _sel;
    NSString *_curId, *_curTitle, *_curArtist, *_curCover;
    __weak MMPlayerController *_player;
    NSArray *_queue; NSInteger _queueIdx;
    NSArray *_origQueue;   // Reihenfolge vor dem Mischen
    BOOL _shuffle;
    NSInteger _repeatMode;
    MMClassicController *_classic;
    MMModeBase *_mode;              // Orbit/Linie: ersetzt die ganze Oberfläche
    MMCoverFlowView *_cflow; BOOL _cflowManual;   // Cover Flow (quer); manual = über Menü geöffnet   // iPod-Modus (liegt über allem, Wiedergabe läuft hier weiter)
    double _resumePos, _pendingSeek; BOOL _needsResume;
    NSTimeInterval _playStartTS;   // wann die aktuelle Wiedergabe tatsächlich startete (gegen Finish-Kaskade)
    UIView *_dlBar, *_dlProg; UILabel *_dlLbl;   // globale Offline-Download-Leiste
    NSTimeInterval _dlSince; BOOL _dlCompact;      // nach ein paar Sekunden nur noch dünne Linie
    UIViewController *_pushed;                    // im Inhaltsbereich geöffnete Ansicht (z.B. Titelliste)
    CGFloat _tabH, _npH;
}
+ (instancetype)shared { return gRoot; }

- (void)loadView {
    gRoot = self;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(trackFinished) name:@"MMAudioDidFinish" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveState) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveState) name:UIApplicationWillTerminateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dlProgress:) name:@"MMDownloadProgress" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dlDone:) name:@"MMDownloadDone" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dlFull:) name:@"MMDownloadFull" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dlError:) name:@"MMDownloadError" object:nil];
    // Auto/Bluetooth: Fernsteuer-Tasten + Unterbrechungen (sonst „streitet" es mit der Stock-Musik-App)
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioInterruption:) name:AVAudioSessionInterruptionNotification object:nil];
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = [SpotTheme bg];
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;
    _tabH=49; _npH=52; CGFloat tabH=_tabH, npH=_npH;

    _content = [[UIView alloc] initWithFrame:CGRectMake(0,0,W,H-tabH)];
    [self.view addSubview:_content];

    // Child-VCs
    _tabs = @[@"home",@"browse",@"search",@"radio",@"library"];
    NSArray *titles=@[L(@"Home"),L(@"Browse"),L(@"Search"),L(@"Radio"),L(@"Library")];
    _vcs=[NSMutableArray array];
    for(int i=0;i<5;i++){
        if(i==0){ [_vcs addObject:[[MMStartController alloc] init]]; continue; }
        if(i==1){ [_vcs addObject:[[MMBrowseController alloc] init]]; continue; }
        if(i==2){ [_vcs addObject:[[MMSearchController alloc] init]]; continue; }
        if(i==3){ [_vcs addObject:[[MMRadioController alloc] init]]; continue; }
        [_vcs addObject:[[MMLibraryController alloc] init]]; }

    // Now-Playing-Leiste
    _npBar=[[UIView alloc] initWithFrame:CGRectMake(0,H-tabH-npH,W,npH)];
    _npBar.backgroundColor=[UIColor colorWithRed:0.14 green:0.14 blue:0.16 alpha:1];
    UIView*npl=[[UIView alloc] initWithFrame:CGRectMake(0,0,W,0.5f)]; npl.backgroundColor=[SpotTheme bg]; [_npBar addSubview:npl];
    _npCover=[[UIView alloc] initWithFrame:CGRectMake(8,8,36,36)]; _npCover.backgroundColor=[SpotTheme card]; _npCover.layer.cornerRadius=3; _npCover.clipsToBounds=YES; [_npBar addSubview:_npCover];
    _npTitle=[[UILabel alloc] initWithFrame:CGRectMake(54,9,W-54-50,18)]; _npTitle.font=[UIFont boldSystemFontOfSize:13]; _npTitle.textColor=[SpotTheme ink]; [_npBar addSubview:_npTitle];
    _npArtist=[[UILabel alloc] initWithFrame:CGRectMake(54,27,W-54-50,16)]; _npArtist.font=[SpotTheme sub]; _npArtist.textColor=[SpotTheme muted]; [_npBar addSubview:_npArtist];
    UIButton*npTap=[UIButton buttonWithType:UIButtonTypeCustom]; npTap.frame=_npBar.bounds; [npTap addTarget:self action:@selector(openPlayer) forControlEvents:UIControlEventTouchUpInside]; [_npBar addSubview:npTap];
    _npPlay=[UIButton buttonWithType:UIButtonTypeCustom]; _npPlay.frame=CGRectMake(W-44,8,36,36);
    [self drawNpPlay];
    [_npPlay addTarget:self action:@selector(npTogglePlay) forControlEvents:UIControlEventTouchUpInside];
    [_npBar addSubview:_npPlay];
    _npSpinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _npSpinner.frame=CGRectMake(W-44,8,36,36); _npSpinner.hidesWhenStopped=YES; [_npBar addSubview:_npSpinner];
    _npBar.hidden=YES;
    [self.view addSubview:_npBar];

    // globale Offline-Download-Leiste — immer sichtbar wenn aktiv, direkt über der Now-Playing-Leiste
    _dlBar=[[UIView alloc] initWithFrame:CGRectMake(0,H-tabH-npH-24,W,24)];
    _dlBar.backgroundColor=[UIColor colorWithRed:0.10 green:0.10 blue:0.11 alpha:1];
    _dlLbl=[[UILabel alloc] initWithFrame:CGRectMake(12,0,W-24,22)]; _dlLbl.font=[UIFont boldSystemFontOfSize:11]; _dlLbl.textColor=[SpotTheme ink]; _dlLbl.textAlignment=NSTextAlignmentCenter; [_dlBar addSubview:_dlLbl];
    _dlProg=[[UIView alloc] initWithFrame:CGRectMake(0,22,0,2)]; _dlProg.backgroundColor=[SpotTheme green]; [_dlBar addSubview:_dlProg];
    _dlBar.hidden=YES; [self.view addSubview:_dlBar];

    // Tab-Leiste
    _tabBar=[[UIView alloc] initWithFrame:CGRectMake(0,H-tabH,W,tabH)];
    _tabBar.backgroundColor=[SpotTheme bar];
    UIView*tl=[[UIView alloc] initWithFrame:CGRectMake(0,0,W,0.5f)]; tl.backgroundColor=[SpotTheme line]; [_tabBar addSubview:tl];
    _tabBtns=[NSMutableArray array]; CGFloat tw=W/5;
    for(int i=0;i<5;i++){
        UIButton*b=[UIButton buttonWithType:UIButtonTypeCustom]; b.frame=CGRectMake(i*tw,0,tw,tabH); b.tag=i;
        [b addTarget:self action:@selector(tapTab:) forControlEvents:UIControlEventTouchUpInside];
        UIImageView*iv=[[UIImageView alloc] initWithFrame:CGRectMake((tw-24)/2,8,24,24)]; iv.tag=99; [b addSubview:iv];
        UILabel*l=[[UILabel alloc] initWithFrame:CGRectMake(0,33,tw,12)]; l.text=titles[i]; l.font=[SpotTheme tab]; l.textAlignment=NSTextAlignmentCenter; l.tag=98; [b addSubview:l];
        [_tabBar addSubview:b]; [_tabBtns addObject:b];
    }
    [self.view addSubview:_tabBar];
    [self selectTab:0];
    [self restoreState];
    [MMSpotify startNetworkWatch];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkChanged:) name:@"MMNetworkChanged" object:nil];
    [MMKeepAlive start];   // Offline-Downloads laufen im Hintergrund weiter (auch bei gesperrtem Bildschirm)
    // iPod quer drehen -> Cover Flow
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationChanged) name:UIDeviceOrientationDidChangeNotification object:nil];
    NSString*um=[self uiMode];   // sofort, kein Aufblitzen der normalen Ansicht
    if([um isEqualToString:@"ipod"]) [self showClassic:NO]; else if(![um isEqualToString:@"spotify"]) [self showMode:um animated:NO];
    // Offline-Playlists, deren Download unterbrochen wurde, automatisch weiterladen
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(4.0*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [MMSpotify resumeOfflineDownloads]; });
    // Cover aller Playlists im Hintergrund auf die Platte (Cover Flow + Listen sofort, auch offline)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(8.0*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [MMCovers precacheLibrary]; });
}

// ---- Resume: letzten Zustand speichern/wiederherstellen ----
- (void)saveState {
    NSUserDefaults*u=[NSUserDefaults standardUserDefaults];
    if(_queue.count){
        NSMutableArray*q=[NSMutableArray array];
        for(NSDictionary*t in _queue) [q addObject:@{@"id":t[@"id"]?:@"",@"title":t[@"title"]?:@"",@"artist":t[@"artist"]?:@"",@"cover":t[@"cover"]?:@""}];   // Cover mitspeichern
        [u setObject:q forKey:@"spQueue"]; [u setInteger:_queueIdx forKey:@"spIdx"];
    } else [u removeObjectForKey:@"spQueue"];
    if(_shuffle && _origQueue.count){
        NSMutableArray*o=[NSMutableArray array];
        for(NSDictionary*t in _origQueue) [o addObject:@{@"id":t[@"id"]?:@"",@"title":t[@"title"]?:@"",@"artist":t[@"artist"]?:@"",@"cover":t[@"cover"]?:@""}];
        [u setObject:o forKey:@"spOrigQueue"];
    } else [u removeObjectForKey:@"spOrigQueue"];
    [u setBool:_shuffle forKey:@"spShuffle"]; [u setInteger:_repeatMode forKey:@"spRepeat"];
    NSString*cov=_curCover;
    if(!cov.length && _queue.count && _queueIdx>=0 && _queueIdx<(NSInteger)_queue.count) cov=_queue[_queueIdx][@"cover"];   // Fallback: aus Queue-Eintrag
    [u setObject:_curId?:@"" forKey:@"spId"]; [u setObject:_curTitle?:@"" forKey:@"spTitle"];
    [u setObject:_curArtist?:@"" forKey:@"spArtist"]; [u setObject:cov?:@"" forKey:@"spCover"];
    double pos=[MMAudio currentTime]; [u setDouble:(pos>0?pos:0) forKey:@"spPos"];
    [u synchronize];
}
- (void)restoreState {
    NSUserDefaults*u=[NSUserDefaults standardUserDefaults];
    _shuffle=[u boolForKey:@"spShuffle"]; _repeatMode=[u integerForKey:@"spRepeat"];
    NSString*cid=[u stringForKey:@"spId"]; if(!cid.length) return;
    _queue=[u objectForKey:@"spQueue"]?:@[]; _queueIdx=[u integerForKey:@"spIdx"];
    _origQueue=[u objectForKey:@"spOrigQueue"];
    _curId=cid; _curTitle=[u stringForKey:@"spTitle"]; _curArtist=[u stringForKey:@"spArtist"]; _curCover=[u stringForKey:@"spCover"];
    if(!_curCover.length && _queue.count && _queueIdx>=0 && _queueIdx<(NSInteger)_queue.count) _curCover=_queue[_queueIdx][@"cover"];   // Fallback aus Queue
    _resumePos=[u doubleForKey:@"spPos"]; _needsResume=YES;
    _npTitle.text=_curTitle; _npArtist.text=_curArtist; _npBar.hidden=NO; [self drawNpPlay];
    if(_curCover.length)[self loadNpCover:_curCover];
    else [MMSpotify fetchTrack:_curId completion:^(NSDictionary*info,NSString*e){   // Cover fürs Anzeigen nachladen (auch ohne Abspielen)
        if([info[@"cover"] isKindOfClass:[NSString class]] && [info[@"cover"] length]){ _curCover=info[@"cover"]; [self loadNpCover:_curCover]; }
    }];
    [self prefetchNext];   // nächsten Track schon vorladen
}
- (void)resumePlayback {
    _needsResume=NO; _pendingSeek=_resumePos;
    if(_queue.count && _queueIdx>=0 && _queueIdx<(NSInteger)_queue.count) [self playCurrentInQueue];
    else [self playTrackId:_curId title:_curTitle artist:_curArtist cover:_curCover];
}

- (void)tapTab:(UIButton *)b { [self selectTab:b.tag]; }
- (void)selectTab:(NSInteger)idx {
    [self popContentImmediate];   // offene Playlist schließen beim Tab-Wechsel
    [[_vcs[_sel] view] removeFromSuperview];
    _sel=idx;
    UIViewController*vc=_vcs[idx]; vc.view.frame=_content.bounds; [_content addSubview:vc.view];
    for(int i=0;i<5;i++){ UIButton*b=_tabBtns[i]; UIColor*c=(i==idx)?[SpotTheme ink]:[SpotTheme faint];
        ((UIImageView*)[b viewWithTag:99]).image=MMTabIcon(_tabs[i],c,24);
        ((UILabel*)[b viewWithTag:98]).textColor=c; }
}

- (void)showNowPlayingTitle:(NSString *)title artist:(NSString *)artist {
    _npTitle.text=title; _npArtist.text=artist; _npBar.hidden=NO;
}

// ---- Auto / Bluetooth / Lockscreen-Fernsteuerung ----
- (BOOL)canBecomeFirstResponder { return YES; }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [self becomeFirstResponder]; }
- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    if(event.type!=UIEventTypeRemoteControl) return;
    switch(event.subtype){
        case UIEventSubtypeRemoteControlTogglePlayPause: [self npTogglePlay]; break;
        case UIEventSubtypeRemoteControlPlay:  if(_needsResume){ [self resumePlayback]; } else { [MMAudio setPaused:NO]; } [self drawNpPlay]; [self updateNowPlaying]; break;
        case UIEventSubtypeRemoteControlPause: [MMAudio setPaused:YES]; [self drawNpPlay]; [self updateNowPlaying]; break;
        case UIEventSubtypeRemoteControlNextTrack: [self playNext]; break;
        case UIEventSubtypeRemoteControlPreviousTrack: [self playPrev]; break;
        default: break;
    }
}
- (void)audioInterruption:(NSNotification *)n {
    NSInteger type=[n.userInfo[AVAudioSessionInterruptionTypeKey] integerValue];
    if(type==AVAudioSessionInterruptionTypeBegan){ [MMAudio setPaused:YES]; [self drawNpPlay]; [self updateNowPlaying]; }
    else { NSInteger opt=[n.userInfo[AVAudioSessionInterruptionOptionKey] integerValue];
        if(opt & AVAudioSessionInterruptionOptionShouldResume){ [MMAudio setPaused:NO]; [self drawNpPlay]; [self updateNowPlaying]; } }
}
- (void)updateNowPlaying {
    Class c=NSClassFromString(@"MPNowPlayingInfoCenter"); if(!c) return;
    NSMutableDictionary*info=[NSMutableDictionary dictionary];
    if(_curTitle) info[MPMediaItemPropertyTitle]=_curTitle;
    if(_curArtist) info[MPMediaItemPropertyArtist]=_curArtist;
    double dur=[MMAudio duration], cur=[MMAudio currentTime];
    if(dur>0) info[MPMediaItemPropertyPlaybackDuration]=@(dur);
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime]=@(cur>0?cur:0);
    info[MPNowPlayingInfoPropertyPlaybackRate]=@([MMAudio isPlaying]?1.0:0.0);
    UIImage*art=[MMCovers cached:_curCover];
    if(art){ Class ac=NSClassFromString(@"MPMediaItemArtwork"); if(ac){ MPMediaItemArtwork*a=[[ac alloc] initWithImage:art]; if(a) info[MPMediaItemPropertyArtwork]=a; } }
    else if(_curCover.length){
        // Cover noch nicht im Cache (z.B. direkt nach Track-Wechsel) -> async nachladen und dann
        // erneut setzen; sonst zeigt der Sperrbildschirm wieder das normale Hintergrundbild.
        NSString*want=_curCover;
        [MMCovers load:_curCover completion:^(UIImage*img){
            if(img && [want isEqualToString:_curCover]) [self updateNowPlaying];   // jetzt gecacht -> Artwork setzen
        }];
    }
    [[c defaultCenter] setNowPlayingInfo:info];
}

// ---- Ansicht im Inhaltsbereich öffnen (über Tab/Now-Playing/Download-Leiste) ----
- (void)pushContent:(UIViewController *)vc {
    [self popContentImmediate];
    _pushed=vc; vc.view.frame=_content.bounds; vc.view.clipsToBounds=YES; [_content addSubview:vc.view];
    CGRect f=vc.view.frame; vc.view.frame=CGRectOffset(f,0,f.size.height);
    [UIView animateWithDuration:0.25 animations:^{ vc.view.frame=f; }];   // von unten reinschieben
    // untere Leisten immer oben halten, damit sie nie von der Playlist verdeckt werden
    [self.view bringSubviewToFront:_dlBar]; [self.view bringSubviewToFront:_npBar]; [self.view bringSubviewToFront:_tabBar];
    [self keepOverlaysOnTop];
}
// Alles, was die ganze App überdeckt (Panels, About-Seite, Cover Flow), bleibt vor den Leisten
- (void)keepOverlaysOnTop {
    for(UIView*v in [self.view.subviews copy])
        if(v.tag==MMSheetTag || [v isKindOfClass:[MMAboutView class]] || v==(UIView*)_cflow) [self.view bringSubviewToFront:v];
}
- (void)popContent {
    UIViewController*vc=_pushed; _pushed=nil; if(!vc)return;
    [UIView animateWithDuration:0.2 animations:^{ vc.view.frame=CGRectOffset(vc.view.frame,0,vc.view.frame.size.height); }
                     completion:^(BOOL x){ [vc.view removeFromSuperview]; }];
}
- (void)popContentImmediate { if(_pushed){ [_pushed.view removeFromSuperview]; _pushed=nil; } }

// ---- globale Offline-Download-Leiste ----
- (void)layoutDlBar {
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;
    CGFloat top = _npBar.hidden ? (H-_tabH) : _npBar.frame.origin.y;   // direkt über Now-Playing (oder Tab-Leiste)
    CGFloat h=_dlCompact?2:24;
    _dlBar.frame=CGRectMake(0, top-h, W, h); _dlLbl.hidden=_dlCompact;
    CGRect pf=_dlProg.frame; pf.origin.y=h-2; _dlProg.frame=pf;
    [self.view bringSubviewToFront:_dlBar];
    [self keepOverlaysOnTop];
}
- (void)showDownloadProgress:(NSInteger)done total:(NSInteger)total {
    if(_cflow) return;                    // Cover Flow (quer) nicht überdecken – Download läuft weiter
    if(_classic){ [_classic showDownload:LF(@"Download %ld/%ld",(long)done,(long)total) progress:(total>0?(CGFloat)done/total:0)]; return; }
    if(_mode){ [_mode showDownload:LF(@"↓ %ld of %ld",(long)done,(long)total) progress:(total>0?(CGFloat)done/total:0)]; return; }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideDownloadBar) object:nil];
    NSTimeInterval now=[NSDate timeIntervalSinceReferenceDate];
    if(_dlBar.hidden) _dlSince=now;
    _dlCompact=(now-_dlSince>6);                       // Text nur am Anfang, dann dezente Linie
    _dlLbl.text=LF(@"↓  Saving … %ld of %ld",(long)done,(long)total);
    _dlProg.frame=CGRectMake(0,0, self.view.bounds.size.width*(total>0?(CGFloat)done/total:0), 2);
    [self layoutDlBar]; _dlBar.hidden=NO;
}
- (void)showDownloadMessage:(NSString *)msg {
    if(_cflow) return;
    if(_classic){ [_classic showDownload:msg progress:-1]; return; }
    if(_mode){ [_mode showDownload:msg progress:-1]; return; }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideDownloadBar) object:nil];
    _dlCompact=NO; _dlLbl.text=msg;
    _dlProg.frame=CGRectMake(0,0, self.view.bounds.size.width, 2);
    [self layoutDlBar]; _dlBar.hidden=NO;
    [self performSelector:@selector(hideDownloadBar) withObject:nil afterDelay:2.5];
}
- (void)hideDownloadBar { _dlBar.hidden=YES; _dlCompact=NO; }
- (void)dlProgress:(NSNotification *)n { NSInteger t=[n.userInfo[@"total"] integerValue]; if(t>0) [self showDownloadProgress:[n.userInfo[@"done"] integerValue] total:t]; }
- (void)dlDone:(NSNotification *)n { [self showDownloadMessage:LF(@"✓  %ld tracks saved offline",(long)[n.userInfo[@"ok"] integerValue])]; }
- (void)dlFull:(NSNotification *)n { [self showDownloadMessage:L(@"Storage full — download stopped")]; }
- (void)dlError:(NSNotification *)n { [self showDownloadMessage:L(@"Connection error — download stopped, please restart")]; }

// Fisher-Yates; der Titel an idx kommt nach vorn
static NSArray* shuffledFrom(NSArray*list,NSInteger idx){
    NSMutableArray*m=[list mutableCopy]; id first=m[idx]; [m removeObjectAtIndex:idx];
    for(NSUInteger i=m.count;i>1;i--) [m exchangeObjectAtIndex:i-1 withObjectAtIndex:arc4random_uniform((u_int32_t)i)];
    [m insertObject:first atIndex:0]; return m;
}
- (void)playList:(NSArray *)list index:(NSInteger)idx {
    _origQueue=list;
    if(_shuffle && idx>=0 && idx<(NSInteger)list.count){ _queue=shuffledFrom(list,idx); _queueIdx=0; }
    else { _queue=list; _queueIdx=idx; }
    [self playCurrentInQueue];
}
- (BOOL)shuffle { return _shuffle; }
- (NSInteger)repeatMode { return _repeatMode; }
- (void)setRepeatMode:(NSInteger)m { _repeatMode=(m<0||m>2)?0:m; [self prefetchNext]; [self saveState]; }
- (void)setShuffle:(BOOL)on {
    if(on==_shuffle) return;
    _shuffle=on;
    if(_queue.count && _queueIdx>=0 && _queueIdx<(NSInteger)_queue.count){
        if(on){ _origQueue=_queue; _queue=shuffledFrom(_queue,_queueIdx); _queueIdx=0; }
        else if(_origQueue.count){
            NSUInteger k=[_origQueue indexOfObject:_queue[_queueIdx]];
            _queue=_origQueue; _queueIdx=(k==NSNotFound)?0:(NSInteger)k;
        }
        [self prefetchNext];   // der nächste Titel ist jetzt ein anderer
    }
    [self saveState];
}
- (void)playCurrentInQueue {
    if(_queueIdx<0 || _queueIdx>=(NSInteger)_queue.count) return;
    NSDictionary*t=_queue[_queueIdx];
    [self playTrackId:t[@"id"] title:t[@"title"] artist:t[@"artist"] cover:t[@"cover"]];
}
- (void)playNext {
    if(!_queue.count) return;
    if(_queueIdx+1<(NSInteger)_queue.count){ _queueIdx++; [self playCurrentInQueue]; }
    else if(_repeatMode==1){ _queueIdx=0; [self playCurrentInQueue]; }   // Liste wiederholen: von vorn
}
- (void)playPrev { if(_queue.count && _queueIdx>0){ _queueIdx--; [self playCurrentInQueue]; } }

// Track zu Ende -> automatisch weiter (nahtlos dank Prefetch)
- (void)trackFinished {
    // Schutz gegen Finish-Kaskade: meldet ein Track <2s nach Start "fertig", sind die Audiodaten
    // leer/kaputt (kein echtes Ende). Dann NICHT weiterspringen, sonst rasen wir durch die ganze Liste.
    if(_playStartTS>0 && ([NSDate timeIntervalSinceReferenceDate]-_playStartTS) < 2.0){
        _playStartTS=0; [MMAudio stop]; [self drawNpPlay];
        return;
    }
    if(_repeatMode==2 && _queue.count){ [self playCurrentInQueue]; return; }   // Titel wiederholen
    if(_queue.count && (_queueIdx+1<(NSInteger)_queue.count || _repeatMode==1)) [self playNext];
    else [self drawNpPlay];   // Ende der Liste: Button zeigt wieder "Play"
}
// nächsten Track im Hintergrund vorladen
- (void)prefetchNext {
    NSInteger j=_queueIdx+1;   // einen Track voraus vorladen (spart RAM/Socket, v.a. während Downloads)
    if(_repeatMode==2) return;                                   // gleicher Titel kommt nochmal, liegt schon im Cache
    if(_repeatMode==1 && j>=(NSInteger)_queue.count) j=0;        // nach dem letzten kommt der erste
    if(_queue.count && j<(NSInteger)_queue.count){ NSDictionary*n=_queue[j]; if(n[@"id"]) [MMSpotify prefetchTrack:n[@"id"]];
        [MMCovers load:n[@"cover"] completion:nil]; }              // Cover des nächsten Titels schon in den Speicher -> Wechsel sofort
    if(_queueIdx>0 && _queueIdx-1<(NSInteger)_queue.count) [MMCovers load:_queue[_queueIdx-1][@"cover"] completion:nil];   // und zurück
}

- (void)playTrackId:(NSString *)trackId title:(NSString *)title artist:(NSString *)artist cover:(NSString *)cover {
    _curId=trackId; _curTitle=title; _curArtist=artist; _curCover=cover;
    _npTitle.text=title; _npArtist.text=artist; _npBar.hidden=NO;
    for(UIView*v in _npCover.subviews)[v removeFromSuperview];
    if(cover.length)[self loadNpCover:cover];
    if(_player)[_player updateTitle:title artist:artist cover:cover];   // SOFORT mit bekannten Daten (nicht erst nach fetchTrack)
    [self updateNowPlaying];
    // echte Metadaten + Cover nachladen — feilt nach, nur wenn noch derselbe Track aktuell ist
    [MMSpotify fetchTrack:trackId completion:^(NSDictionary*info,NSString*e){
        if(info && [trackId isEqualToString:_curId]){   // Schutz gegen veraltete Antwort bei schnellem Skippen
            // Cover aus der Liste behalten: Spotify liefert hier oft eine andere Adresse fürs gleiche Bild -> sonst Flackern + doppeltes Laden
            _curTitle=info[@"title"]?:title; _curArtist=info[@"artist"]?:artist; _curCover=cover.length?cover:(info[@"cover"]?:cover);
            _npTitle.text=_curTitle; _npArtist.text=_curArtist;
            [self loadNpCover:_curCover];
            if(_player)[_player updateTitle:_curTitle artist:_curArtist cover:_curCover];
            [self updateNowPlaying];
        }
    }];
    // echten Ton starten -> Spinner während des Ladens
    _npPlay.hidden=YES; [_npSpinner startAnimating];
    _playStartTS=0;
    [MMSpotify playTrack:trackId completion:^(BOOL ok,NSString*e){
        [_npSpinner stopAnimating]; _npPlay.hidden=NO;
        if(ok){ _playStartTS=[NSDate timeIntervalSinceReferenceDate]; if(_pendingSeek>0){ [MMAudio seekTo:_pendingSeek]; _pendingSeek=0; } [self prefetchNext]; [self saveState]; }
        [self drawNpPlay]; [self updateNowPlaying];
    }];
}

- (void)loadNpCover:(NSString *)url {
    if(!url.length) return;
    [MMCovers load:url completion:^(UIImage*img){
        if(!img) return;
        for(UIView*v in _npCover.subviews)[v removeFromSuperview];
        UIImageView*iv=[[UIImageView alloc] initWithFrame:_npCover.bounds];
        iv.image=img; iv.contentMode=UIViewContentModeScaleAspectFill; [_npCover addSubview:iv];
    }];
}

- (void)drawNpPlay {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(20,20),NO,0);
    [[SpotTheme ink] setFill];
    if([MMAudio isPlaying]){ // Pause
        [[UIBezierPath bezierPathWithRect:CGRectMake(5,4,3.5,12)] fill];
        [[UIBezierPath bezierPathWithRect:CGRectMake(11.5,4,3.5,12)] fill];
    } else { // Play
        UIBezierPath*t=[UIBezierPath bezierPath]; [t moveToPoint:CGPointMake(6,4)];[t addLineToPoint:CGPointMake(6,16)];[t addLineToPoint:CGPointMake(16,10)];[t closePath]; [t fill];
    }
    UIImage*img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    [_npPlay setImage:img forState:UIControlStateNormal];
}
- (void)npTogglePlay {
    if(_needsResume){ [self resumePlayback]; return; }   // nach Neustart: dort weiter wo du warst
    [MMAudio setPaused:[MMAudio isPlaying]]; [self drawNpPlay]; [self updateNowPlaying];
}

- (void)networkChanged:(NSNotification *)n {
    BOOL ok=[n.userInfo[@"reachable"] boolValue];
    [self showDownloadMessage:ok?L(@"Back online"):L(@"Offline – downloaded songs still play")];
}
- (NSDictionary *)nowPlaying {
    if(!_curId.length) return nil;
    return @{@"title":_curTitle?:@"",@"artist":_curArtist?:@"",@"cover":_curCover?:@"",@"index":@(_queueIdx+1),@"count":@(_queue.count)};
}
- (void)togglePlayPause { [self npTogglePlay]; }
- (void)showClassic:(BOOL)animated {
    if(_classic) return;
    _dlBar.hidden=YES;
    _classic=[[MMClassicController alloc] init]; _classic.view.frame=self.view.bounds;
    [self.view addSubview:_classic.view];
    if(animated){ _classic.view.alpha=0; [UIView animateWithDuration:0.3 animations:^{ _classic.view.alpha=1; }]; }
}
// ---- Oberflächen: spotify (normal), ipod (Klickrad), orbit, line ----
+ (NSString *)nameOfUIMode:(NSString *)m {
    if([m isEqualToString:@"ipod"]) return L(@"iPod mode");
    if([m isEqualToString:@"orbit"]) return L(@"Orbit mode");
    if([m isEqualToString:@"line"]) return L(@"Line mode");
    return L(@"Normal view");
}
- (NSString *)uiMode {
    NSString*m=[[NSUserDefaults standardUserDefaults] stringForKey:@"uiMode"];
    if([@[@"spotify",@"ipod",@"orbit",@"line"] containsObject:m]) return m;
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"ipodMode"]?@"ipod":@"spotify";   // ältere Einstellung
}
- (void)showMode:(NSString *)m animated:(BOOL)animated {
    _dlBar.hidden=YES;
    _mode=[m isEqualToString:@"line"]?[[MMLineMode alloc] init]:[[MMOrbitMode alloc] init];
    _mode.view.frame=self.view.bounds; [self.view addSubview:_mode.view]; [self keepOverlaysOnTop];
    if(animated){ _mode.view.alpha=0; [UIView animateWithDuration:0.3 animations:^{ _mode.view.alpha=1; }]; }
}
- (void)hideMode {
    MMModeBase*md=_mode; _mode=nil; if(!md) return; [md stop];
    UIView*v=md.view; [UIView animateWithDuration:0.3 animations:^{ v.alpha=0; } completion:^(BOOL f){ [v removeFromSuperview]; }];
}
- (void)setUIMode:(NSString *)m {
    NSUserDefaults*u=[NSUserDefaults standardUserDefaults];
    [u setObject:m forKey:@"uiMode"]; [u setBool:[m isEqualToString:@"ipod"] forKey:@"ipodMode"]; [u synchronize];
    if(self.presentedViewController) [self dismissViewControllerAnimated:NO completion:nil];
    [self hideMode];
    if(_classic && ![m isEqualToString:@"ipod"]){ UIView*v=_classic.view; _classic=nil;
        [UIView animateWithDuration:0.3 animations:^{ v.alpha=0; } completion:^(BOOL f){ [v removeFromSuperview]; }]; }
    if([m isEqualToString:@"ipod"]) [self showClassic:YES];
    else if(![m isEqualToString:@"spotify"]) [self showMode:m animated:YES];
}
- (void)openPlayerWithStyle:(NSString *)style {
    if([self.presentedViewController isKindOfClass:[MMPlayerController class]]) return;
    MMArtPlayer*pc=[[MMArtPlayer alloc] init]; pc.styleOverride=style;
    pc.trackTitle=_curTitle; pc.trackArtist=_curArtist; pc.coverURL=_curCover;
    _player=pc; [self presentViewController:pc animated:YES completion:nil];
}
- (void)setClassicMode:(BOOL)on { [self setUIMode:on?@"ipod":@"spotify"]; }

// ---- Cover Flow: die App selbst bleibt hochkant, die Ansicht wird um 90° gedreht eingeblendet ----
- (void)orientationChanged {
    UIDeviceOrientation o=[UIDevice currentDevice].orientation;
    if(UIDeviceOrientationIsLandscape(o)){
        if(self.presentedViewController) return;             // Player offen -> nicht dazwischenfunken
        if(!_cflow) [self openCoverFlow:o]; else [self rotateCoverFlow:o animated:YES];
    } else if(o==UIDeviceOrientationPortrait && _cflow) [self closeCoverFlow];
}
- (void)showCoverFlow {
    UIDeviceOrientation o=[UIDevice currentDevice].orientation;
    _cflowManual=YES;
    if(!_cflow) [self openCoverFlow:UIDeviceOrientationIsLandscape(o)?o:UIDeviceOrientationLandscapeLeft];
}
- (void)openCoverFlow:(UIDeviceOrientation)o {
    CGSize sz=CGSizeMake(self.view.bounds.size.height,self.view.bounds.size.width);
    _cflow=[[MMCoverFlowView alloc] initWithLandscapeSize:sz];
    __weak MMRootController*ws=self; _cflow.onClose=^{ [ws closeCoverFlow]; };
    _cflow.center=CGPointMake(self.view.bounds.size.width/2,self.view.bounds.size.height/2);
    [self rotateCoverFlow:o animated:NO];
    _cflow.alpha=0; [self.view addSubview:_cflow]; _dlBar.hidden=YES;
    [UIView animateWithDuration:0.3 animations:^{ _cflow.alpha=1; }];
}
- (void)rotateCoverFlow:(UIDeviceOrientation)o animated:(BOOL)a {
    CGFloat ang=(o==UIDeviceOrientationLandscapeRight)?-M_PI_2:M_PI_2;   // Home-Taste rechts = LandscapeLeft
    [UIView animateWithDuration:a?0.3:0 animations:^{ _cflow.transform=CGAffineTransformMakeRotation(ang); }];
}
- (void)closeCoverFlow {
    UIView*v=_cflow; _cflow=nil; _cflowManual=NO;
    [UIView animateWithDuration:0.25 animations:^{ v.alpha=0; } completion:^(BOOL f){ [v removeFromSuperview]; }];
}

- (void)openPlayer {
    if([self.presentedViewController isKindOfClass:[MMPlayerController class]]) return;  // schon offen
    if(self.presentedViewController){ [self dismissViewControllerAnimated:NO completion:nil]; }
    MMPlayerController*pc=[[MMArtPlayer style] isEqualToString:@"standard"]?[[MMPlayerController alloc] init]:[[MMArtPlayer alloc] init];
    pc.trackTitle=_curTitle; pc.trackArtist=_curArtist; pc.coverURL=_curCover;
    pc.modalTransitionStyle=UIModalTransitionStyleCoverVertical;
    _player=pc;
    [self presentViewController:pc animated:YES completion:nil];
}
@end
