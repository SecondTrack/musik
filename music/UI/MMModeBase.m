#import "MMModeBase.h"
#import <AudioToolbox/AudioToolbox.h>
#import "MMRootController.h"
#import "MMSpotify.h"
#import "MMCovers.h"
#import "MMArtPlayer.h"
#import "MMKeepAlive.h"
#import "MMAboutView.h"
#import "SpotTheme.h"
#import "MeshL10n.h"

@implementation MMModeBase {
    NSMutableArray *_stack;
    SystemSoundID _clickId;
    NSTimer *_timer;
    NSString *_npCoverURL, *_npId;
}
@synthesize stack=_stack;

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor=[UIColor blackColor];
    _accent=[SpotTheme green];
    _stack=[NSMutableArray array];
    [self makeClickSound];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [self push:[self rootLevel]];
    _timer=[NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(pollNowPlaying) userInfo:nil repeats:YES];
    [self pollNowPlaying];
}
- (void)dealloc { [_timer invalidate]; if(_clickId) AudioServicesDisposeSystemSoundID(_clickId); }
- (void)stop { [_timer invalidate]; _timer=nil; }

#pragma mark - Klick

- (void)makeClickSound {
    NSString*path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"mm-tick.wav"];
    if(![[NSFileManager defaultManager] fileExistsAtPath:path]){
        int rate=44100, n=rate*4/1000; NSMutableData*pcm=[NSMutableData dataWithLength:n*2]; int16_t*s=pcm.mutableBytes;
        for(int i=0;i<n;i++){ double env=exp(-i/(double)(n/6)); s[i]=(int16_t)(sin(i*2*M_PI*2400.0/rate)*7000*env); }   // weicher, kurzer Ton
        NSMutableData*w=[NSMutableData data];
        void (^u32)(uint32_t)=^(uint32_t v){ [w appendBytes:&v length:4]; }; void (^u16)(uint16_t)=^(uint16_t v){ [w appendBytes:&v length:2]; };
        [w appendBytes:"RIFF" length:4]; u32(36+(uint32_t)pcm.length); [w appendBytes:"WAVEfmt " length:8];
        u32(16); u16(1); u16(1); u32(rate); u32(rate*2); u16(2); u16(16); [w appendBytes:"data" length:4]; u32((uint32_t)pcm.length); [w appendData:pcm];
        [w writeToFile:path atomically:YES];
    }
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)[NSURL fileURLWithPath:path], &_clickId);
}
- (void)click { if(_clickId) AudioServicesPlaySystemSound(_clickId); }

#pragma mark - Stapel

- (NSMutableDictionary *)top { return [_stack lastObject]; }
- (NSArray *)crumbs { NSMutableArray*a=[NSMutableArray array]; for(NSUInteger i=1;i<_stack.count;i++) [a addObject:_stack[i][@"title"]?:@""]; return a; }
- (void)push:(NSMutableDictionary *)l { [_stack addObject:l]; [self levelChanged]; }
- (void)pop { if(_stack.count>1){ [_stack removeLastObject]; [self levelChanged]; } }
- (void)levelChanged {}
- (void)nowPlayingChanged {}
- (void)setDownloadText:(NSString *)text {}

- (NSMutableDictionary *)level:(NSString *)title items:(NSArray *)items {
    return [@{@"title":title?:@"",@"items":items?:@[],@"sel":@0} mutableCopy];
}
- (NSDictionary *)item:(NSString *)t sub:(NSString *)sub action:(void(^)(void))act {
    NSMutableDictionary*d=[@{@"title":t?:@""} mutableCopy]; if(sub.length) d[@"sub"]=sub; if(act) d[@"action"]=[act copy]; return d;
}
- (NSMutableDictionary *)pushLoading:(NSString *)title {
    NSMutableDictionary*m=[self level:title items:nil]; m[@"loading"]=@YES; [self push:m]; return m;
}
- (void)fill:(NSMutableDictionary *)m items:(NSArray *)items {
    if(![_stack containsObject:m]) return;
    m[@"items"]=items.count?items:@[[self item:L(@"Empty") sub:nil action:nil]]; [m removeObjectForKey:@"loading"];
    if([m[@"sel"] integerValue]>=(NSInteger)[m[@"items"] count]) m[@"sel"]=@0;
    if([_stack lastObject]==m) [self levelChanged];
}
- (void)activateSelected {
    NSMutableDictionary*m=[self top]; NSArray*it=m[@"items"]; NSInteger s=[m[@"sel"] integerValue];
    if(s<0 || s>=(NSInteger)it.count) return;
    void (^a)(void)=it[s][@"action"]; if(a) a();
}

#pragma mark - Menüs

- (NSMutableDictionary *)rootLevel {
    __weak MMModeBase*ws=self;
    NSMutableArray*it=[NSMutableArray array];
    [it addObject:[self item:L(@"Playlists") sub:nil action:^{ [ws openPlaylists]; }]];
    [it addObject:[self item:L(@"Liked Songs") sub:nil action:^{ [ws openTracks:L(@"Liked Songs") path:@"me/tracks?market=from_token&limit=50"]; }]];
    [it addObject:[self item:L(@"Shuffle Songs") sub:nil action:^{ [ws shuffleSongs]; }]];
    [it addObject:[self item:L(@"Recently Played") sub:nil action:^{ [ws openRecent]; }]];
    [it addObject:[self item:@"Cover Flow" sub:nil action:^{ [[MMRootController shared] showCoverFlow]; }]];
    [it addObject:[self item:L(@"Settings") sub:nil action:^{ [ws push:[ws settingsLevel]]; }]];
    return [self level:@"" items:it];
}
- (NSMutableDictionary *)settingsLevel {
    __weak MMModeBase*ws=self; MMRootController*r=[MMRootController shared];
    NSArray*rep=@[L(@"Off"),L(@"All"),L(@"One")];
    NSString*mine=[r uiMode];
    NSMutableArray*it=[NSMutableArray array];
    [it addObject:[self item:L(@"Shuffle") sub:(r.shuffle?L(@"On"):L(@"Off")) action:^{ [r setShuffle:!r.shuffle]; [ws refreshSettings]; }]];
    [it addObject:[self item:L(@"Repeat") sub:rep[r.repeatMode%3] action:^{ r.repeatMode=(r.repeatMode+1)%3; [ws refreshSettings]; }]];
    [it addObject:[self item:L(@"Background download") sub:([MMKeepAlive enabled]?L(@"On"):L(@"Off")) action:^{ [MMKeepAlive setEnabled:![MMKeepAlive enabled]]; [ws refreshSettings]; }]];
    for(NSString*m in @[@"orbit",@"line",@"ipod",@"spotify"]){
        if([m isEqualToString:mine]) continue;
        [it addObject:[self item:[MMRootController nameOfUIMode:m] sub:L(@"Switch look") action:^{ [[MMRootController shared] setUIMode:m]; }]];
    }
    [it addObject:[self item:L(@"About") sub:nil action:^{ [MMAboutView showIn:[MMRootController shared].view]; }]];
    return [self level:L(@"Settings") items:it];
}
- (void)refreshSettings {   // Wert in der Zeile ändern, Auswahl behalten
    NSMutableDictionary*m=[self top]; NSInteger sel=[m[@"sel"] integerValue];
    NSMutableDictionary*n=[self settingsLevel]; n[@"sel"]=@(sel);
    [_stack replaceObjectAtIndex:_stack.count-1 withObject:n]; [self levelChanged];
}

#pragma mark - Daten (wie im iPod-Modus, gleiche Caches)

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
    NSMutableArray*out=[NSMutableArray array];
    for(NSUInteger i=0;i<tracks.count;i++){
        NSInteger idx=i;
        NSMutableDictionary*e=[[self item:tracks[i][@"title"] sub:tracks[i][@"artist"] action:^{ [[MMRootController shared] playList:tracks index:idx]; }] mutableCopy];
        e[@"cover"]=tracks[i][@"cover"]?:@""; e[@"tid"]=tracks[i][@"id"]?:@"";
        [out addObject:e];
    }
    return out;
}
- (void)openPlaylists {
    NSMutableDictionary*m=[self pushLoading:L(@"Playlists")];
    __weak MMModeBase*ws=self;
    [MMSpotify apiUserCached:@"me/playlists?limit=50" completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        NSArray*pl=j[@"items"]; if(![pl isKindOfClass:[NSArray class]]){ if(fresh && [m[@"loading"] boolValue]) [ws fill:m items:nil]; return; }
        NSMutableArray*it=[NSMutableArray array];
        for(NSDictionary*p in pl){
            if(![p isKindOfClass:[NSDictionary class]] || ![p[@"id"] isKindOfClass:[NSString class]]) continue;
            NSString*name=[p[@"name"] isKindOfClass:[NSString class]]?p[@"name"]:@""; NSString*pid=p[@"id"];
            id tr=p[@"tracks"]; NSString*sub=([tr isKindOfClass:[NSDictionary class]] && tr[@"total"])?LF(@"%@ songs",tr[@"total"]):nil;
            NSMutableDictionary*e=[[ws item:name sub:sub action:^{ [ws openTracks:name path:[NSString stringWithFormat:@"playlists/%@?market=from_token",pid]]; }] mutableCopy];
            e[@"cover"]=[MMCovers bestURL:p[@"images"]]?:@"";
            [it addObject:e];
        }
        [ws fill:m items:it];
    }];
}
- (void)openTracks:(NSString *)title path:(NSString *)path {
    NSMutableDictionary*m=[self pushLoading:title];
    NSString*cache=[NSString stringWithFormat:@"/var/mobile/.spotcache/list_%lu.plist",(unsigned long)path.hash];
    NSArray*cached=[NSArray arrayWithContentsOfFile:cache];
    if([cached isKindOfClass:[NSArray class]] && cached.count) [self fill:m items:[self trackItems:cached]];
    __weak MMModeBase*ws=self;
    [MMSpotify apiUserAllItems:path completion:^(NSArray*items,NSInteger st){
        NSArray*tracks=tracksFromItems(items);
        if(!tracks.count && cached.count) return;
        if(cached.count && [[cached valueForKey:@"id"] isEqualToArray:[tracks valueForKey:@"id"]]) return;
        if(tracks.count) [tracks writeToFile:cache atomically:YES];
        [ws fill:m items:[ws trackItems:tracks]];
    }];
}
- (void)openRecent {
    NSMutableDictionary*m=[self pushLoading:L(@"Recently Played")];
    __weak MMModeBase*ws=self;
    [MMSpotify apiUserCached:@"me/player/recently-played?limit=30" completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        NSArray*tracks=tracksFromItems(j[@"items"]);
        if(!tracks.count && !fresh) return;
        [ws fill:m items:[ws trackItems:tracks]];
    }];
}
- (void)shuffleSongs {
    NSString*path=@"me/tracks?market=from_token&limit=50";
    NSString*cache=[NSString stringWithFormat:@"/var/mobile/.spotcache/list_%lu.plist",(unsigned long)path.hash];
    void (^go)(NSArray*)=^(NSArray*tracks){
        if(!tracks.count) return;
        NSMutableArray*m=[tracks mutableCopy];
        for(NSUInteger i=m.count;i>1;i--) [m exchangeObjectAtIndex:i-1 withObjectAtIndex:arc4random_uniform((u_int32_t)i)];
        [[MMRootController shared] playList:m index:0];
    };
    NSArray*cached=[NSArray arrayWithContentsOfFile:cache];
    if([cached isKindOfClass:[NSArray class]] && cached.count){ go(cached); return; }
    [MMSpotify apiUserAllItems:path completion:^(NSArray*items,NSInteger st){
        NSArray*tracks=tracksFromItems(items); if(!tracks.count) return;
        [tracks writeToFile:cache atomically:YES]; go(tracks);
    }];
}

#pragma mark - Laufender Song

- (NSString *)currentTrackId { return _npId; }
- (void)pollNowPlaying {
    NSDictionary*np=[[MMRootController shared] nowPlaying];
    NSString*cov=np[@"cover"]; NSString*tid=[[NSUserDefaults standardUserDefaults] stringForKey:@"spId"];
    BOOL changed=NO;
    if(![tid?:@"" isEqualToString:_npId?:@""]){ _npId=tid; changed=YES; }
    if(cov.length && ![cov isEqualToString:_npCoverURL]){
        _npCoverURL=cov;
        __weak MMModeBase*ws=self;
        [MMCovers load:cov completion:^(UIImage*img){
            MMModeBase*ss=ws; if(!ss || !img || ![cov isEqualToString:ss->_npCoverURL]) return;
            ss->_nowCover=img; NSArray*p=[MMArtPlayer paletteFor:img]; if(p) ss->_accent=p[0];
            [ss nowPlayingChanged];
        }];
    }
    if(changed) [self nowPlayingChanged];
}

#pragma mark - Download

- (void)showDownload:(NSString *)text progress:(CGFloat)progress {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideDownload) object:nil];
    [self setDownloadText:text];
    if(progress<0) [self performSelector:@selector(hideDownload) withObject:nil afterDelay:2.5];
}
- (void)hideDownload { [self setDownloadText:nil]; }
@end
