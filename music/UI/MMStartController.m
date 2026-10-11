#import "MMStartController.h"
#import "SpotTheme.h"
#import "MMRootController.h"
#import "MMSpotify.h"
#import "MMCovers.h"
#import "MMTrackListController.h"
#import "MeshL10n.h"

@implementation MMStartController {
    UIScrollView *_sc;
    UIView *_content;             // alle Inhalte (beim Neuzeichnen geleert; Scrollbalken bleiben)
    CGFloat _y, _W;
    NSArray *_recent, *_top;      // @[ {id,title,artist,cover} ]
    NSArray *_quick;              // @[ {name,path,cover} ]
    UILabel *_greet;
    UIView *_skel;                // Platzhalter beim allerersten Laden (noch kein Cache)
}

- (NSString *)greeting {
    NSInteger h=[[[NSCalendar currentCalendar] components:NSHourCalendarUnit fromDate:[NSDate date]] hour];
    if(h<11) return L(@"Good morning");
    if(h<18) return L(@"Good afternoon");
    return L(@"Good evening");
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor=[SpotTheme bg];
    _W=self.view.bounds.size.width;

    _greet=[[UILabel alloc] initWithFrame:CGRectMake(16,10,_W-32,30)];
    _greet.text=[self greeting]; _greet.font=[UIFont boldSystemFontOfSize:22]; _greet.textColor=[SpotTheme ink]; [self.view addSubview:_greet];

    _sc=[[UIScrollView alloc] initWithFrame:CGRectMake(0,46,_W,self.view.bounds.size.height-46)];
    _sc.contentInset=UIEdgeInsetsMake(0,0,84,0); _sc.alwaysBounceVertical=YES;   // Platz für Now-Playing + Download-Leiste
    _sc.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [self.view addSubview:_sc];
    _content=[[UIView alloc] initWithFrame:CGRectMake(0,0,_W,0)]; [_sc addSubview:_content];
    _y=8;

    [self showSkeleton];
    [self loadAll];
    // offline gestartet und Netz kommt zurück -> frische Daten holen
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(netBack:) name:@"MMNetworkChanged" object:nil];
}
- (void)netBack:(NSNotification *)n { if([n.userInfo[@"reachable"] boolValue]) [self loadAll]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)finish { _content.frame=CGRectMake(0,0,_W,_y+20); _sc.contentSize=CGSizeMake(_W,_y+20); }

// Alle drei Bereiche laden parallel; jeder zeigt sofort die letzten Daten und wird bei Änderung neu gezeichnet.
- (void)loadAll {
    [MMSpotify apiUserCached:@"me/playlists?limit=6" completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        NSMutableArray*q=[NSMutableArray array];
        // feste Kachel "Lieblingssongs"
        [q addObject:@{@"name":L(@"Liked Songs"),@"path":@"me/tracks?market=from_token&limit=50",@"liked":@1}];
        NSArray*items=j[@"items"];
        if([items isKindOfClass:[NSArray class]]) for(NSDictionary*p in items){
            if(![p isKindOfClass:[NSDictionary class]]||![p[@"id"] isKindOfClass:[NSString class]]) continue;
            NSString*cov=[MMCovers bestURL:p[@"images"]];
            [q addObject:@{@"name":p[@"name"]?:L(@"Playlist"),@"path":[NSString stringWithFormat:@"playlists/%@?market=from_token",p[@"id"]],@"cover":cov}];
            if(q.count>=6) break;
        }
        _quick=q; [self render];
    }];
    [MMSpotify apiUserCached:@"me/player/recently-played?limit=30" completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        _recent=[self parseTracks:j[@"items"] dedupe:YES]; [self render];
    }];
    [MMSpotify apiUserCached:@"me/top/tracks?limit=20&time_range=short_term" completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        _top=[self parseTracks:j[@"items"] dedupe:NO]; [self render];
    }];
}

// Zeichnet den ganzen Inhalt neu; vertikale und horizontale Scroll-Position bleiben erhalten.
// Graue, pulsierende Umrisse genau dort, wo gleich Kacheln und Cover erscheinen.
- (void)showSkeleton {
    _skel=[[UIView alloc] initWithFrame:CGRectMake(0,0,_W,700)]; _skel.userInteractionEnabled=NO;
    UIColor*c=[SpotTheme card];
    UIView*(^box)(CGRect,CGFloat)=^UIView*(CGRect r,CGFloat rad){ UIView*v=[[UIView alloc] initWithFrame:r]; v.backgroundColor=c; v.layer.cornerRadius=rad; [_skel addSubview:v]; return v; };
    CGFloat gap=10, tileW=(_W-16*2-gap)/2, tileH=56, y=8;
    for(int i=0;i<6;i++) box(CGRectMake(16+(i%2)*(tileW+gap), y+(i/2)*(tileH+gap), tileW, tileH), 4);
    y+=3*(tileH+gap)+10;
    box(CGRectMake(16,y+4,150,18),4); y+=32;                       // Überschrift
    for(int i=0;i<3;i++){ CGFloat x=16+i*(128+14);                 // Karussell: Cover + zwei Textzeilen
        box(CGRectMake(x,y,128,128),4); box(CGRectMake(x,y+136,100,11),3); box(CGRectMake(x,y+153,64,9),3); }
    [_sc addSubview:_skel];
    _skel.alpha=1;
    [UIView animateWithDuration:0.8 delay:0 options:UIViewAnimationOptionAutoreverse|UIViewAnimationOptionRepeat|UIViewAnimationOptionCurveEaseInOut
                     animations:^{ _skel.alpha=0.35; } completion:nil];
}

- (void)render {
    if(!_quick && !_recent && !_top) return;
    if(_skel){
        if(!_quick || !_recent) return;   // erstes Laden: erst umschalten, wenn Kacheln UND „Zuletzt gehört“ da sind -> kein Springen
        UIView*sk=_skel; _skel=nil; [sk.layer removeAllAnimations];
        _content.alpha=0;
        [UIView animateWithDuration:0.3 animations:^{ sk.alpha=0; _content.alpha=1; } completion:^(BOOL f){ [sk removeFromSuperview]; }];
    }
    NSMutableDictionary*rowX=[NSMutableDictionary dictionary];
    for(UIView*v in _content.subviews){ if(v.tag>=1 && v.tag<=2 && [v isKindOfClass:[UIScrollView class]]) rowX[@(v.tag)]=@(((UIScrollView*)v).contentOffset.x); }
    for(UIView*v in [_content.subviews copy]) [v removeFromSuperview];
    _y=8;
    if(_quick.count) [self buildGrid];
    if(_recent.count) [self addCarousel:L(@"Recently played") tracks:_recent section:1 offset:[rowX[@1] floatValue]];
    if(_top.count) [self addCarousel:L(@"Your top tracks") tracks:_top section:2 offset:[rowX[@2] floatValue]];
    [self finish];
}

// ---------- 1) Schnellzugriff-Grid (deine Playlists + Lieblingssongs) ----------
- (void)buildGrid {
    CGFloat gap=10, tileW=(_W-16*2-gap)/2, tileH=56;
    for(int i=0;i<(int)_quick.count;i++){
        NSDictionary*it=_quick[i];
        CGFloat col=i%2, rowY=_y+(i/2)*(tileH+gap);
        UIView*tile=[[UIView alloc] initWithFrame:CGRectMake(16+col*(tileW+gap),rowY,tileW,tileH)];
        tile.backgroundColor=[SpotTheme card]; tile.layer.cornerRadius=4; tile.clipsToBounds=YES;
        UIImageView*cov=[[UIImageView alloc] initWithFrame:CGRectMake(0,0,tileH,tileH)]; cov.contentMode=UIViewContentModeScaleAspectFill; cov.clipsToBounds=YES; cov.backgroundColor=[SpotTheme line]; [tile addSubview:cov];
        if(it[@"liked"]){ cov.backgroundColor=[UIColor colorWithRed:0.29 green:0.16 blue:0.78 alpha:1];
            UILabel*hl=[[UILabel alloc] initWithFrame:cov.bounds]; hl.text=@"♥"; hl.textAlignment=NSTextAlignmentCenter; hl.font=[UIFont systemFontOfSize:24]; hl.textColor=[UIColor whiteColor]; [cov addSubview:hl];
        } else [MMCovers load:it[@"cover"] into:cov];
        UILabel*nm=[[UILabel alloc] initWithFrame:CGRectMake(tileH+6,0,tileW-tileH-8,tileH)]; nm.text=it[@"name"]; nm.numberOfLines=2; nm.font=[UIFont boldSystemFontOfSize:12.5]; nm.textColor=[SpotTheme ink]; [tile addSubview:nm];
        UIButton*tap=[UIButton buttonWithType:UIButtonTypeCustom]; tap.frame=tile.bounds; tap.tag=i; [tap addTarget:self action:@selector(openQuick:) forControlEvents:UIControlEventTouchUpInside]; [tile addSubview:tap];
        [_content addSubview:tile];
    }
    int rows=((int)_quick.count+1)/2; _y+=rows*(tileH+gap)+10;
}
- (void)openQuick:(UIButton *)b {
    if(b.tag>=(int)_quick.count) return;
    NSDictionary*it=_quick[b.tag];
    MMTrackListController*tl=[[MMTrackListController alloc] initWithTitle:it[@"name"] path:it[@"path"]];
    [[MMRootController shared] pushContent:tl];   // im Inhaltsbereich -> untere Leisten bleiben sichtbar
}

- (NSArray *)parseTracks:(id)items dedupe:(BOOL)dd {
    if(![items isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray*out=[NSMutableArray array]; NSMutableSet*seen=[NSMutableSet set];
    for(id it in items){
        if(![it isKindOfClass:[NSDictionary class]]) continue;
        id tw=((NSDictionary*)it)[@"track"]; NSDictionary*t=[tw isKindOfClass:[NSDictionary class]]?tw:(NSDictionary*)it;
        NSString*tid=[t[@"id"] isKindOfClass:[NSString class]]?t[@"id"]:nil; if(!tid) continue;
        if(dd){ if([seen containsObject:tid]) continue; [seen addObject:tid]; }
        NSString*nm=[t[@"name"] isKindOfClass:[NSString class]]?t[@"name"]:@"";
        id arts=t[@"artists"]; NSString*an=@""; if([arts isKindOfClass:[NSArray class]]&&[arts count]){ id a0=arts[0]; if([a0 isKindOfClass:[NSDictionary class]]&&[a0[@"name"] isKindOfClass:[NSString class]]) an=a0[@"name"]; }
        id alb=t[@"album"]; NSString*cov=[alb isKindOfClass:[NSDictionary class]]?[MMCovers bestURL:alb[@"images"]]:@"";
        [out addObject:@{@"id":tid,@"title":nm,@"artist":an,@"cover":cov}];
    }
    return out;
}

- (void)addCarousel:(NSString *)title tracks:(NSArray *)tracks section:(int)sec offset:(CGFloat)ox {
    UILabel*h=[[UILabel alloc] initWithFrame:CGRectMake(16,_y,_W-32,26)]; h.text=title; h.font=[UIFont boldSystemFontOfSize:18]; h.textColor=[SpotTheme ink]; [_content addSubview:h]; _y+=32;
    CGFloat cw=128, pad=14, tileH=cw+40;
    UIScrollView*row=[[UIScrollView alloc] initWithFrame:CGRectMake(0,_y,_W,tileH)]; row.showsHorizontalScrollIndicator=NO; row.tag=sec; [_content addSubview:row];
    CGFloat x=16;
    for(int i=0;i<(int)tracks.count;i++){
        NSDictionary*t=tracks[i];
        UIView*tile=[[UIView alloc] initWithFrame:CGRectMake(x,0,cw,tileH)];
        UIImageView*cov=[[UIImageView alloc] initWithFrame:CGRectMake(0,0,cw,cw)]; cov.contentMode=UIViewContentModeScaleAspectFill; cov.clipsToBounds=YES; cov.backgroundColor=[SpotTheme card]; cov.layer.cornerRadius=4; [tile addSubview:cov];
        [MMCovers load:t[@"cover"] into:cov];
        UILabel*ti=[[UILabel alloc] initWithFrame:CGRectMake(0,cw+4,cw,16)]; ti.text=t[@"title"]; ti.font=[UIFont boldSystemFontOfSize:12.5]; ti.textColor=[SpotTheme ink]; [tile addSubview:ti];
        UILabel*ar=[[UILabel alloc] initWithFrame:CGRectMake(0,cw+20,cw,15)]; ar.text=t[@"artist"]; ar.font=[UIFont systemFontOfSize:11]; ar.textColor=[SpotTheme muted]; [tile addSubview:ar];
        UIButton*tap=[UIButton buttonWithType:UIButtonTypeCustom]; tap.frame=tile.bounds; tap.tag=sec*1000+i; [tap addTarget:self action:@selector(playTile:) forControlEvents:UIControlEventTouchUpInside]; [tile addSubview:tap];
        [row addSubview:tile]; x+=cw+pad;
    }
    row.contentSize=CGSizeMake(x,tileH);
    row.contentOffset=CGPointMake(MAX(0,MIN(ox,x-_W)),0);
    _y+=tileH+18;
}
- (void)playTile:(UIButton *)b {
    int sec=b.tag/1000, idx=b.tag%1000;
    NSArray*list=(sec==1)?_recent:_top;
    if(idx>=(int)list.count) return;
    [[MMRootController shared] playList:list index:idx];
    [[MMRootController shared] openPlayer];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; _greet.text=[self greeting]; }
@end
