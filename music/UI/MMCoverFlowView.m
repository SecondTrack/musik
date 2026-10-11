#import "MMCoverFlowView.h"
#import "MMRootController.h"
#import "MMSpotify.h"
#import "MMCovers.h"
#import "MMAudio.h"
#import "MeshL10n.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat REF=0.36;      // Höhe der Spiegelung relativ zum Cover
static const NSInteger SPAN=5;      // so viele Cover links/rechts der Mitte werden gezeichnet

// ---------------------------------------------------------------------------------------------
// Schnell auf dem iPod 4: Cover werden EINMAL im Hintergrund auf Zielgröße gebracht und die Spiegelung
// (gekippt + nach unten ins Schwarz ausgeblendet) fest ins Bild gebacken. Beim Wischen gibt es dann
// keine Masken, kein Dekodieren und keine Transparenz -> der Grafikchip schiebt nur fertige Bilder.
// ---------------------------------------------------------------------------------------------
static NSArray* bake(UIImage*src,CGFloat px){
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    size_t w=(size_t)px, rh=(size_t)(px*REF);
    // Cover: auf Zielgröße, deckend (kein Alpha = billiger zu zeichnen)
    CGContextRef c1=CGBitmapContextCreate(NULL,w,w,8,w*4,cs,kCGImageAlphaNoneSkipFirst|kCGBitmapByteOrder32Little);
    CGContextSetInterpolationQuality(c1,kCGInterpolationMedium);
    CGContextDrawImage(c1,CGRectMake(0,0,w,w),src.CGImage);
    CGImageRef cover=CGBitmapContextCreateImage(c1); CGContextRelease(c1);
    // Spiegelung: unteres Stück gekippt, darüber ein Verlauf ins Schwarz
    CGContextRef c2=CGBitmapContextCreate(NULL,w,rh,8,w*4,cs,kCGImageAlphaNoneSkipFirst|kCGBitmapByteOrder32Little);
    CGContextSaveGState(c2);
    CGContextTranslateCTM(c2,0,rh); CGContextScaleCTM(c2,1,-1);                 // kippen
    CGContextDrawImage(c2,CGRectMake(0,0,w,w),cover);                          // Unterkante des Covers liegt jetzt oben im Streifen
    CGContextRestoreGState(c2);
    CGFloat cols[8]={0,0,0,0.55, 0,0,0,1};
    CGGradientRef g=CGGradientCreateWithColorComponents(cs,cols,NULL,2);
    CGContextDrawLinearGradient(c2,g,CGPointMake(0,rh),CGPointMake(0,0),0); CGGradientRelease(g);
    CGImageRef ref=CGBitmapContextCreateImage(c2); CGContextRelease(c2);
    CGColorSpaceRelease(cs);
    NSArray*out=@[[UIImage imageWithCGImage:cover],[UIImage imageWithCGImage:ref]];
    CGImageRelease(cover); CGImageRelease(ref);
    return out;
}

// Platzhalter: dunkler Verlauf mit Zeichen (♫ ohne Cover, ♥ für Lieblingssongs in Spotify-Farben)
static UIImage* tile(CGFloat s,NSString*glyph,BOOL liked){
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s,s),YES,1);
    CGContextRef cx=UIGraphicsGetCurrentContext();
    CGFloat dark[8]={0.30,0.30,0.33,1, 0.13,0.13,0.15,1}, lk[8]={0.27,0.15,0.85,1, 0.55,0.75,0.88,1};
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB(); CGGradientRef g=CGGradientCreateWithColorComponents(cs,liked?lk:dark,NULL,2);
    CGContextDrawLinearGradient(cx,g,CGPointZero,liked?CGPointMake(s,s):CGPointMake(0,s),0); CGGradientRelease(g); CGColorSpaceRelease(cs);
    UIFont*f=[UIFont systemFontOfSize:s*0.42]; CGSize ts=[glyph sizeWithFont:f];
    [(liked?[UIColor whiteColor]:[UIColor colorWithWhite:0.55 alpha:1]) set]; [glyph drawAtPoint:CGPointMake((s-ts.width)/2,(s-ts.height)/2) withFont:f];
    UIImage*img=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img;
}

static NSArray* tracksFrom(NSArray*items){
    NSMutableArray*out=[NSMutableArray array];
    if(![items isKindOfClass:[NSArray class]]) return out;
    for(id it in items){
        if(![it isKindOfClass:[NSDictionary class]]) continue;
        id tw=it[@"track"]; NSDictionary*t=[tw isKindOfClass:[NSDictionary class]]?tw:it;
        NSString*tid=[t[@"id"] isKindOfClass:[NSString class]]?t[@"id"]:nil; if(!tid) continue;
        NSString*an=@""; id arts=t[@"artists"];
        if([arts isKindOfClass:[NSArray class]] && [arts count]){ id a0=arts[0]; if([a0 isKindOfClass:[NSDictionary class]] && [a0[@"name"] isKindOfClass:[NSString class]]) an=a0[@"name"]; }
        NSString*cov=@""; id alb=t[@"album"]; if([alb isKindOfClass:[NSDictionary class]]) cov=[MMCovers bestURL:alb[@"images"]]?:@"";
        [out addObject:@{@"id":tid,@"title":[t[@"name"] isKindOfClass:[NSString class]]?t[@"name"]:@"",@"artist":an,@"cover":cov}];
    }
    return out;
}
static NSString* cachePath(NSString*path){ return [NSString stringWithFormat:@"/var/mobile/.spotcache/list_%lu.plist",(unsigned long)path.hash]; }
#define LIKED_PATH @"me/tracks?market=from_token&limit=50"
// Über das Schließen hinaus merken: aus welcher Playlist zuletzt gespielt wurde und wo man stand
static NSDictionary *gLastPlaylist; static CGFloat gLastPlPos=-1;

@implementation MMCoverFlowView {
    // Ebene: Playlists oder (nach Antippen) die Songs einer Playlist
    NSArray *_items;                 // Playlists: {name,path,cover,total,liked,pid,mosaic}  Songs: {id,title,artist,cover}
    BOOL _songs;
    NSArray *_playlists; CGFloat _plPos;   // zum Zurückkehren
    NSDictionary *_openPl;           // gerade geöffnete Playlist (Song-Ebene)
    NSMutableDictionary *_live; NSMutableArray *_pool;   // Index -> Ebene, nur um die Mitte herum
    CALayer *_stage;
    CGFloat _s, _px, _cy, _pos, _panStart;
    NSInteger _shownSel;             // Titel nur bei Wechsel neu setzen (Text-Layout kostet)
    UILabel *_title, *_sub, *_hint;
    UIButton *_back;
    UIActivityIndicatorView *_spin;
    CADisplayLink *_link; CGFloat _vel, _target; BOOL _settling;
    NSArray *_ph, *_likedImg;        // fertig gebackene Platzhalter {cover, spiegelung}
    NSCache *_baked;                 // URL -> {cover, spiegelung}
    NSMutableSet *_baking;           // gerade in Arbeit
    NSMutableOrderedSet *_wanted;    // noch zu backen; die Warteschlange nimmt immer das Cover nächst der Mitte
    NSInteger _busy;                 // laufende Back-Aufträge (höchstens 2: einer rechnet, einer lädt)
    NSInteger _aheadFor;             // für welche Position zuletzt vorausgebacken wurde
    dispatch_queue_t _bakeQ;
    NSInteger _loadRun;
    NSUInteger _likedCount;
    // Öffnen: erst Cover um die Mitte vorbereiten (Lade-Rad), dann aus der Mitte auffächern
    CGFloat _spread;                 // 0 = alle Cover gestapelt in der Mitte, 1 = normal verteilt
    BOOL _revealing; NSTimer *_readyTimer; NSTimeInterval _readyDeadline;
    CADisplayLink *_intro; CFTimeInterval _introT0;
    UIActivityIndicatorView *_trackSpin; NSTimer *_playTimer; NSString *_playingTitle; NSTimeInterval _playT0;   // angetippter Song lädt
}

- (id)initWithLandscapeSize:(CGSize)size {
    if(!(self=[super initWithFrame:CGRectMake(0,0,size.width,size.height)])) return nil;
    self.backgroundColor=[UIColor blackColor]; self.clipsToBounds=YES; self.opaque=YES;
    CGFloat W=size.width, H=size.height;
    _s=floor(MIN(H*0.52,W*0.36)); _cy=H*0.08+_s/2+6;
    _px=MIN(240,round(_s*[UIScreen mainScreen].scale));     // 240 px: kaum sichtbar kleiner, braucht 1/3 weniger Speicher
    _baked=[[NSCache alloc] init]; _baked.countLimit=64; _baking=[NSMutableSet set]; _spread=1;
    _wanted=[NSMutableOrderedSet orderedSet]; _aheadFor=NSIntegerMin;
    _bakeQ=dispatch_queue_create("mesh.coverflow.bake",DISPATCH_QUEUE_SERIAL);
    _ph=bake(tile(_px,@"♫",NO),_px); _likedImg=bake(tile(_px,@"♥",YES),_px);
    _live=[NSMutableDictionary dictionary]; _pool=[NSMutableArray array]; _shownSel=-1;

    _stage=[CALayer layer]; _stage.frame=self.bounds;
    CATransform3D p=CATransform3DIdentity; p.m34=-1.0/600; _stage.sublayerTransform=p;
    [self.layer addSublayer:_stage];

    _title=[self label:CGRectMake(20,_cy+_s/2+_s*REF-2,W-40,22) size:17 bold:YES color:[UIColor whiteColor]];
    _sub=[self label:CGRectMake(20,CGRectGetMaxY(_title.frame),W-40,18) size:13 bold:NO color:[UIColor colorWithWhite:0.6 alpha:1]];
    _hint=[self label:CGRectMake(20,H/2-10,W-40,20) size:14 bold:NO color:[UIColor colorWithWhite:0.6 alpha:1]];
    _hint.backgroundColor=[UIColor clearColor]; _hint.opaque=NO;
    _spin=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spin.center=CGPointMake(W/2,H/2-30); _spin.hidesWhenStopped=YES; [self addSubview:_spin];
    _trackSpin=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _trackSpin.center=CGPointMake(W/2,_cy); _trackSpin.hidesWhenStopped=YES; [self addSubview:_trackSpin];

    UIButton*done=[self pill:L(@"Done") frame:CGRectMake(W-84,8,76,30)]; [done addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    _back=[self pill:L(@"‹ Playlists") frame:CGRectMake(8,8,96,30)]; [_back addTarget:self action:@selector(backToPlaylists) forControlEvents:UIControlEventTouchUpInside]; _back.hidden=YES;

    [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)]];
    [self loadPlaylists];
    return self;
}
- (UIButton *)pill:(NSString *)t frame:(CGRect)f {
    UIButton*b=[UIButton buttonWithType:UIButtonTypeCustom]; b.frame=f;
    [b setTitle:t forState:UIControlStateNormal]; b.titleLabel.font=[UIFont boldSystemFontOfSize:13];
    [b setTitleColor:[UIColor colorWithWhite:0.85 alpha:1] forState:UIControlStateNormal];
    b.layer.borderColor=[UIColor colorWithWhite:0.4 alpha:1].CGColor; b.layer.borderWidth=1; b.layer.cornerRadius=6;
    [self addSubview:b]; return b;
}
- (UILabel *)label:(CGRect)f size:(CGFloat)s bold:(BOOL)b color:(UIColor *)c {
    UILabel*l=[[UILabel alloc] initWithFrame:f]; l.font=b?[UIFont boldSystemFontOfSize:s]:[UIFont systemFontOfSize:s];
    l.textColor=c; l.backgroundColor=[UIColor blackColor]; l.opaque=YES; l.textAlignment=NSTextAlignmentCenter; [self addSubview:l]; return l;
}
- (void)stopTimers { [_link invalidate]; _link=nil; [_intro invalidate]; _intro=nil; [_readyTimer invalidate]; _readyTimer=nil; [_playTimer invalidate]; _playTimer=nil; }
- (void)rememberPos { gLastPlPos=_songs?_plPos:_pos; }
- (void)close { [self rememberPos]; [self stopTimers]; if(self.onClose) self.onClose(); }
- (void)removeFromSuperview { [self rememberPos]; [self stopTimers]; [super removeFromSuperview]; }

#pragma mark - Daten

- (void)loadPlaylists {
    [_spin startAnimating];
    _likedCount=[[NSArray arrayWithContentsOfFile:cachePath(LIKED_PATH)] count];
    __weak MMCoverFlowView*ws=self;
    [MMSpotify apiUserCached:@"me/playlists?limit=50" completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        MMCoverFlowView*ss=ws; if(!ss) return;
        NSArray*pl=j[@"items"];
        if(![pl isKindOfClass:[NSArray class]]){ if(fresh){ [ss->_spin stopAnimating]; ss->_hint.text=L(@"Could not load (offline?)"); } return; }
        NSMutableArray*out=[NSMutableArray array];
        [out addObject:@{@"name":L(@"Liked Songs"),@"path":LIKED_PATH,@"cover":@"",@"liked":@YES}];   // vorne, wie in der Bibliothek
        for(NSDictionary*p in pl){
            if(![p isKindOfClass:[NSDictionary class]] || ![p[@"id"] isKindOfClass:[NSString class]]) continue;
            id tr=p[@"tracks"]; id tot=[tr isKindOfClass:[NSDictionary class]]?tr[@"total"]:nil;
            [out addObject:@{@"name":[p[@"name"] isKindOfClass:[NSString class]]?p[@"name"]:@"",
                             @"path":[NSString stringWithFormat:@"playlists/%@?market=from_token",p[@"id"]],
                             @"cover":[MMCovers bestURL:p[@"images"]]?:@"", @"total":tot?:@0, @"pid":p[@"id"]}];
        }
        BOOL first=(ss->_playlists==nil);
        if(!first && [[out valueForKey:@"path"] isEqualToArray:[ss->_playlists valueForKey:@"path"]]) return;   // unverändert
        ss->_playlists=out; [ss->_spin stopAnimating]; ss->_hint.text=nil;
        if(first && gLastPlaylist && [ss songIsPlayingFrom:gLastPlaylist]){   // zurück in die Playlist des laufenden Songs
            ss->_pos=gLastPlPos>=0?gLastPlPos:floor((out.count-1)/2.0);
            [ss openSongs:gLastPlaylist]; return;
        }
        if(!ss->_songs) [ss showItems:out songs:NO pos:first?(gLastPlPos>=0?MIN(gLastPlPos,(CGFloat)out.count-1):floor((out.count-1)/2.0)):ss->_pos reveal:first];   // erstes Mal: zuletzt oder Mitte
    }];
}

// Songs einer Playlist (oder der Lieblingssongs) als Cover: gespeicherte Liste sofort, frische danach
// Läuft gerade ein Song aus dieser Playlist? (aus der gespeicherten Liste)
- (BOOL)songIsPlayingFrom:(NSDictionary *)pl {
    NSString*cur=[[MMRootController shared] nowPlaying][@"title"]; if(!cur.length) return NO;
    NSArray*list=[NSArray arrayWithContentsOfFile:cachePath(pl[@"path"])];
    for(NSDictionary*t in list) if([t isKindOfClass:[NSDictionary class]] && [t[@"title"] isEqualToString:cur]) return YES;
    return NO;
}
- (void)openSongs:(NSDictionary *)pl {
    _plPos=_pos; _openPl=pl;
    NSString*path=pl[@"path"];
    NSArray*cached=[NSArray arrayWithContentsOfFile:cachePath(path)];
    NSInteger run=++_loadRun;
    if([cached isKindOfClass:[NSArray class]] && cached.count) [self showItems:cached songs:YES pos:[self startPosFor:cached]];
    else { [self showItems:@[] songs:YES pos:0]; [_spin startAnimating]; }
    __weak MMCoverFlowView*ws=self;
    [MMSpotify apiUserAllItems:path completion:^(NSArray*items,NSInteger st){
        MMCoverFlowView*ss=ws; if(!ss || run!=ss->_loadRun || !ss->_songs) return;
        [ss->_spin stopAnimating];
        NSArray*t=tracksFrom(items);
        if(!t.count){ if(!ss->_items.count) ss->_hint.text=L(@"Could not load (offline?)"); return; }
        [t writeToFile:cachePath(path) atomically:YES];
        if([pl[@"liked"] boolValue]) ss->_likedCount=t.count;
        if([[t valueForKey:@"id"] isEqualToArray:[ss->_items valueForKey:@"id"]]) return;
        BOOL wasEmpty=(ss->_items.count==0);
        [ss showItems:t songs:YES pos:wasEmpty?[ss startPosFor:t]:MIN(ss->_pos,(CGFloat)t.count-1) reveal:wasEmpty];
    }];
}
// Start: beim gerade laufenden Song, sonst in der Mitte (nicht ganz links)
- (CGFloat)startPosFor:(NSArray *)tracks {
    NSString*cur=[[MMRootController shared] nowPlaying][@"title"];
    if(cur.length) for(NSUInteger i=0;i<tracks.count;i++) if([tracks[i][@"title"] isEqualToString:cur]) return i;
    return floor((tracks.count-1)/2.0);
}
- (void)backToPlaylists {
    _openPl=nil; _loadRun++; [_spin stopAnimating]; _hint.text=nil;
    [self showItems:_playlists songs:NO pos:_plPos];
}

- (void)showItems:(NSArray *)items songs:(BOOL)songs pos:(CGFloat)pos {
    [self showItems:items songs:songs pos:pos reveal:YES];
}
- (void)showItems:(NSArray *)items songs:(BOOL)songs pos:(CGFloat)pos reveal:(BOOL)reveal {
    [_link invalidate]; _link=nil;
    for(CALayer*l in [_live allValues]){ l.hidden=YES; [_pool addObject:l]; }
    [_live removeAllObjects];
    _items=items; _songs=songs; _back.hidden=!songs; _shownSel=-1; _aheadFor=NSIntegerMin;
    _pos=MAX(0,MIN(pos,(CGFloat)items.count-1));
    if(!reveal || !items.count){ [self layoutAnimated:NO]; return; }
    // Verdeckt aufbauen: Ebenen binden (stößt das Laden an), Lade-Rad zeigen, bis die Cover um die Mitte fertig sind
    [_intro invalidate]; _intro=nil; [_readyTimer invalidate];
    _revealing=YES; _spread=0; _stage.opacity=0; _title.alpha=0; _sub.alpha=0;
    [self layoutAnimated:NO];
    [_spin startAnimating];
    _readyDeadline=[NSDate timeIntervalSinceReferenceDate]+1.5;
    _readyTimer=[NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(checkReady) userInfo:nil repeats:YES];
    [self checkReady];
}
// Fertig, wenn alle sichtbaren Cover gebacken sind (oder spätestens nach 1,5 s mit Platzhaltern)
- (void)checkReady {
    BOOL ready=YES;
    for(NSNumber*k in _live){
        NSInteger i=k.integerValue; if(i>=(NSInteger)_items.count) continue;
        NSDictionary*it=_items[i]; if([it[@"liked"] boolValue]) continue;
        NSString*u=[self urlFor:i];
        if(u.length){ if(![_baked objectForKey:u] && ([_baking containsObject:u]||[_wanted containsObject:u])){ ready=NO; break; } }
        else if(it[@"pid"] && !it[@"mosaic"] && ![it[@"mosaicDone"] boolValue]){ ready=NO; break; }   // Mosaik noch unterwegs
    }
    if(!ready && [NSDate timeIntervalSinceReferenceDate]<_readyDeadline) return;
    [_readyTimer invalidate]; _readyTimer=nil;
    [_spin stopAnimating];
    [self startIntro];
}
// Auffächern: Cover gleiten aus der Mitte an ihre Plätze
- (void)startIntro {
    _stage.opacity=1; _spread=0; _introT0=CACurrentMediaTime();
    [UIView animateWithDuration:0.3 animations:^{ _title.alpha=1; _sub.alpha=1; }];
    [_intro invalidate];
    _intro=[CADisplayLink displayLinkWithTarget:self selector:@selector(introStep:)]; [_intro addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}
- (void)introStep:(CADisplayLink *)l {
    CGFloat t=MIN(1,(CACurrentMediaTime()-_introT0)/0.45);
    _spread=1-pow(1-t,3);                                     // sanft auslaufen
    [self layoutAnimated:NO];
    if(t>=1){ [_intro invalidate]; _intro=nil; _revealing=NO; _spread=1; [self preloadNextLevel]; }
}

#pragma mark - Ebenen

- (CALayer *)makeLayer {
    CALayer*c=[CALayer layer]; c.bounds=CGRectMake(0,0,_s,_s*(1+REF)); c.anchorPoint=CGPointMake(0.5,0.5/(1+REF));
    CALayer*img=[CALayer layer]; img.frame=CGRectMake(0,0,_s,_s); img.opaque=YES; img.contentsGravity=kCAGravityResize;
    CALayer*ref=[CALayer layer]; ref.frame=CGRectMake(0,_s,_s,_s*REF); ref.opaque=YES; ref.contentsGravity=kCAGravityResize;
    [c addSublayer:img]; [c addSublayer:ref]; [_stage addSublayer:c];
    return c;
}
static void setBaked(CALayer*c,NSArray*b){ ((CALayer*)c.sublayers[0]).contents=(__bridge id)[b[0] CGImage]; ((CALayer*)c.sublayers[1]).contents=(__bridge id)[b[1] CGImage]; }

// Bild-URL eines Eintrags; Playlists ohne eigenes Bild bekommen das Mosaik (sobald es da ist)
- (NSString *)urlFor:(NSInteger)i {
    NSDictionary*it=_items[i]; NSString*u=it[@"cover"];
    if(!u.length && it[@"mosaic"]) u=it[@"mosaic"];
    return u;
}
// Backen: Wunsch vormerken, die Pumpe arbeitet ihn ab (nächstes Cover zur Mitte zuerst)
- (void)bakeURL:(NSString *)u {
    if(!u.length || [_baked objectForKey:u] || [_baking containsObject:u]) return;
    [_wanted addObject:u]; [self pump];
}
// Index-Abstand eines Bildes zur aktuellen Position (nur im Umfeld gesucht); NSIntegerMax = weit weg
- (NSInteger)distanceOf:(NSString *)u {
    NSInteger c=(NSInteger)lround(_pos), best=NSIntegerMax, n=_items.count;
    for(NSInteger d=0; d<=24 && best==NSIntegerMax; d++){
        if(c-d>=0 && c-d<n && [[self urlFor:c-d] isEqualToString:u]) best=d;
        else if(c+d<n && [[self urlFor:c+d] isEqualToString:u]) best=d;
    }
    return best;
}
- (void)pump {
    while(_busy<2 && _wanted.count){
        NSString*pick=nil; NSInteger bd=NSIntegerMax; NSMutableArray*drop=[NSMutableArray array];
        for(NSString*u in _wanted){ NSInteger d=[self distanceOf:u]; if(d==NSIntegerMax){ [drop addObject:u]; continue; } if(d<bd){ bd=d; pick=u; } }
        [_wanted removeObjectsInArray:drop];                 // längst vorbeigewischt -> vergessen
        if(!pick) return;
        [_wanted removeObject:pick]; [_baking addObject:pick]; _busy++;
        __weak MMCoverFlowView*ws=self; CGFloat px=_px; dispatch_queue_t q=_bakeQ; NSString*u=pick;
        [MMCovers load:u completion:^(UIImage*img){
            MMCoverFlowView*s0=ws; if(!s0) return;
            if(!img){ [s0->_baking removeObject:u]; s0->_busy--; [s0 pump]; return; }
            dispatch_async(q, ^{
                NSArray*b=bake(img,px);
                dispatch_async(dispatch_get_main_queue(), ^{
                    MMCoverFlowView*ss=ws; if(!ss) return;
                    [ss->_baking removeObject:u]; ss->_busy--; [ss->_baked setObject:b forKey:u];
                    [CATransaction begin]; [CATransaction setDisableActions:YES];
                    for(NSNumber*k in ss->_live){ NSInteger i=k.integerValue; if(i<(NSInteger)ss->_items.count && [[ss urlFor:i] isEqualToString:u]) setBaked(ss->_live[k],b); }
                    [CATransaction commit];
                    [ss pump];
                });
            });
        }];
    }
}
// Vorausbacken: Playlists komplett, Songs 12 in jede Richtung
- (void)bakeAhead {
    NSInteger c=(NSInteger)lround(_pos); if(c==_aheadFor) return; _aheadFor=c;
    NSInteger n=_items.count, r=_songs?12:n;
    for(NSInteger d=0; d<=r; d++){
        NSInteger idx[2]={c-d,c+d};
        for(int k=0;k<(d?2:1);k++){ NSInteger i=idx[k]; if(i<0||i>=n) continue;
            NSDictionary*it=_items[i]; if([it[@"liked"] boolValue]) continue;
            NSString*u=[self urlFor:i];
            if(u.length) [self bakeURL:u];
            else if(it[@"pid"] && !it[@"mosaicTried"] && d<=6) [self fetchMosaic:i];   // Mosaik braucht Netz -> nur in der Nähe
        }
    }
}
- (CALayer *)layerFor:(NSInteger)i {
    CALayer*c=_live[@(i)]; if(c) return c;
    c=[_pool lastObject]; if(c) [_pool removeLastObject]; else c=[self makeLayer];
    _live[@(i)]=c; c.hidden=NO;
    NSDictionary*it=_items[i];
    if([it[@"liked"] boolValue]){ setBaked(c,_likedImg); return c; }
    NSString*u=[self urlFor:i]; NSArray*b=u.length?[_baked objectForKey:u]:nil;
    setBaked(c,b?:_ph);
    if(!b && u.length) [self bakeURL:u];
    else if(!u.length && it[@"pid"] && !it[@"mosaicTried"]) [self fetchMosaic:i];
    return c;
}
// Playlist ohne eigenes Bild: Mosaik holen, im Eintrag merken, backen
- (void)fetchMosaic:(NSInteger)i {
    NSMutableArray*m=[_items mutableCopy]; NSMutableDictionary*it=[m[i] mutableCopy]; it[@"mosaicTried"]=@YES; m[i]=it; _items=m; _playlists=m;
    NSString*pid=it[@"pid"]; __weak MMCoverFlowView*ws=self;
    [MMCovers playlistCover:pid completion:^(NSString*mu){
        MMCoverFlowView*ss=ws; if(!ss) return;
        NSMutableArray*pl=[ss->_playlists mutableCopy];
        for(NSUInteger k=0;k<pl.count;k++) if([pl[k][@"pid"] isEqualToString:pid]){ NSMutableDictionary*d=[pl[k] mutableCopy]; d[@"mosaicDone"]=@YES; if(mu) d[@"mosaic"]=mu; pl[k]=d; }
        ss->_playlists=pl; if(!ss->_songs) ss->_items=pl;
        if(mu) [ss bakeURL:mu];
    }];
}

// Kommazahl-Position: Cover gleiten stufenlos von der Seite in die Mitte
- (void)layoutAnimated:(BOOL)anim {
    CGFloat W=self.bounds.size.width, s=_s; NSInteger n=_items.count;
    NSInteger lo=MAX(0,(NSInteger)floor(_pos)-SPAN), hi=MIN(n-1,(NSInteger)ceil(_pos)+SPAN);
    [CATransaction begin];
    if(anim) [CATransaction setAnimationDuration:0.3]; else [CATransaction setDisableActions:YES];
    for(NSNumber*k in [_live allKeys]){                       // außer Sicht -> zurück in den Vorrat
        NSInteger i=k.integerValue; if(i>=lo && i<=hi) continue;
        CALayer*c=_live[k]; c.hidden=YES; [_pool addObject:c]; [_live removeObjectForKey:k];
    }
    for(NSInteger i=lo;i<=hi;i++){
        BOOL fresh=(_live[@(i)]==nil);
        CALayer*c=[self layerFor:i]; CGFloat d=i-_pos, a=fabs(d), sg=d<0?-1:1;
        CGFloat x, rot, z;
        if(a<1){ x=sg*a*s*0.72; rot=-sg*a*M_PI*0.35; z=-a*s*0.55; }      // Übergang Mitte <-> Seite
        else { x=sg*(s*0.72+(a-1)*s*0.26); rot=-sg*M_PI*0.35; z=-s*0.55; }
        x*=_spread; rot*=_spread; z*=_spread;                            // beim Öffnen aus der Mitte auffächern
        CATransform3D t=CATransform3DMakeTranslation(0,0,z); t=CATransform3DRotate(t,rot,0,1,0);
        if(fresh && anim){ [CATransaction begin]; [CATransaction setDisableActions:YES]; }
        c.position=CGPointMake(W/2+x,_cy); c.transform=t; c.zPosition=-a*10;
        if(fresh && anim) [CATransaction commit];
    }
    [CATransaction commit];
    [self bakeAhead];
    NSInteger sel=[self selIndex];
    if(sel==_shownSel) return;
    _shownSel=sel;
    if(sel>=0){
        NSDictionary*it=_items[sel];
        if(_songs){ _title.text=it[@"title"]; _sub.text=it[@"artist"]; }
        else { _title.text=it[@"name"];
               _sub.text=[it[@"liked"] boolValue]?(_likedCount?LF(@"%@ songs",@(_likedCount)):L(@"Playlist"))
                        :([it[@"total"] integerValue]?LF(@"%@ songs",it[@"total"]):L(@"Playlist")); }
    } else { _title.text=nil; _sub.text=nil; }
}
- (NSInteger)selIndex { if(!_items.count) return -1; NSInteger i=(NSInteger)lround(_pos); return MAX(0,MIN((NSInteger)_items.count-1,i)); }

#pragma mark - Wischen mit Schwung

- (void)pan:(UIPanGestureRecognizer *)g {
    if(!_items.count || _revealing) return;
    CGFloat step=_s*0.42;                              // so viele Punkte = ein Cover weiter
    if(g.state==UIGestureRecognizerStateBegan){ [_link invalidate]; _link=nil; _panStart=_pos;
        if(_playTimer){ [_playTimer invalidate]; _playTimer=nil; [_trackSpin stopAnimating]; for(CALayer*l in [_live allValues]) l.opacity=1; } }
    else if(g.state==UIGestureRecognizerStateChanged){
        CGFloat p=_panStart-[g translationInView:self].x/step, max=_items.count-1;
        if(p<0) p=p*0.3;
        if(p>max) p=max+(p-max)*0.3;                     // am Rand federn
        _pos=p; [self layoutAnimated:NO];
    } else if(g.state==UIGestureRecognizerStateEnded||g.state==UIGestureRecognizerStateCancelled){
        _vel=-[g velocityInView:self].x/step;            // Cover pro Sekunde
        _link=[CADisplayLink displayLinkWithTarget:self selector:@selector(glide:)]; [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        _settling=NO;
    }
}
// Ausrollen: Geschwindigkeit bremst ab, dann rastet das nächste Cover sauber in der Mitte ein
- (void)glide:(CADisplayLink *)l {
    CGFloat dt=MIN(l.duration,0.05), max=_items.count-1;
    if(!_settling){
        _pos+=_vel*dt; _vel*=pow(0.05,dt);              // Reibung
        if(_pos<0||_pos>max) _vel*=0.5;
        if(fabs(_vel)<1.5){ _settling=YES; _target=MAX(0,MIN(max,round(_pos+_vel*0.15))); }
    } else {
        CGFloat d=_target-_pos; _pos+=d*MIN(1,dt*14);
        if(fabs(d)<0.003){ _pos=_target; [_link invalidate]; _link=nil; [self preloadNextLevel]; }
    }
    [self layoutAnimated:NO];
}

#pragma mark - Antippen

- (void)tap:(UITapGestureRecognizer *)g {
    if(_revealing) return;
    CGPoint p=[g locationInView:self]; CGFloat W=self.bounds.size.width;
    NSInteger sel=[self selIndex]; if(sel<0) return;
    if(fabs(p.x-W/2)<_s/2 && fabs(p.y-_cy)<_s/2){
        if(_songs){ [[MMRootController shared] playList:_items index:sel]; [self flash]; gLastPlaylist=_openPl; gLastPlPos=_plPos; }   // Song antippen = abspielen
        else [self openSongs:_items[sel]];                                                     // Playlist = ihre Song-Cover
        return;
    }
    NSInteger to=sel+(p.x>W/2?1:-1);                    // Seiten-Cover angetippt -> dorthin
    if(to<0||to>=(NSInteger)_items.count) return;
    [_link invalidate]; _link=nil; _pos=to; [self layoutAnimated:YES];
    [self preloadNextLevel];
}
// Steht eine Playlist in der Mitte: Cover ihrer ersten Songs schon vorbereiten (aus der gespeicherten Liste)
- (void)preloadNextLevel {
    if(_songs) return;
    NSInteger sel=[self selIndex]; if(sel<0) return;
    NSArray*cached=[NSArray arrayWithContentsOfFile:cachePath(_items[sel][@"path"])];
    if(![cached isKindOfClass:[NSArray class]] || !cached.count) return;
    NSInteger c=(NSInteger)[self startPosFor:cached];
    for(NSInteger i=MAX(0,c-3);i<=MIN((NSInteger)cached.count-1,c+3);i++){
        NSString*u=cached[i][@"cover"]; if(u.length && ![_baked objectForKey:u]) [self bakeURL:u];
    }
}
// Song angetippt: Cover abdunkeln + Lade-Rad + "Laden …", bis er wirklich spielt
- (void)flash {
    NSInteger sel=[self selIndex]; CALayer*c=_live[@(sel)]; if(!c) return;
    _playingTitle=_items[sel][@"title"];
    c.opacity=0.45; [_trackSpin startAnimating]; _sub.text=L(@"Loading …"); _playT0=[NSDate timeIntervalSinceReferenceDate];
    [_playTimer invalidate];
    _playTimer=[NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(playCheck) userInfo:nil repeats:YES];
}
- (void)playCheck {
    BOOL started=![MMSpotify isLoading] && [MMAudio isPlaying];
    BOOL other=![[[MMRootController shared] nowPlaying][@"title"] isEqualToString:_playingTitle];   // inzwischen anderer Song
    BOOL timeout=[NSDate timeIntervalSinceReferenceDate]-_playT0>30;
    if(!started && !other && !timeout) return;                       // lädt noch -> weiter warten
    [_playTimer invalidate]; _playTimer=nil; [_trackSpin stopAnimating];
    for(CALayer*l in [_live allValues]) l.opacity=1;
    NSInteger sel=[self selIndex];
    if(_songs && sel>=0 && [_items[sel][@"title"] isEqualToString:_playingTitle] && started)
        _sub.text=[NSString stringWithFormat:@"▶  %@",_items[sel][@"artist"]];
}
@end
