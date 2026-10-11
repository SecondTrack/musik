#import "MMRadioController.h"
#import "SpotTheme.h"
#import "MMRootController.h"
#import "MMSpotify.h"
#import "MMCovers.h"
#import "MMTrackListController.h"
#import "MeshL10n.h"

// URL-kodiert einen Query-Wert (Leerzeichen -> %20, " -> %22, & -> %26) für die Spotify-Suche.
static NSString *mmEnc(NSString *s){
    if(![s isKindOfClass:[NSString class]]) return @"";
    NSString *e=[s stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]?:@"";
    e=[e stringByReplacingOccurrencesOfString:@"&" withString:@"%26"];
    e=[e stringByReplacingOccurrencesOfString:@"\"" withString:@"%22"];
    return e;
}

@implementation MMRadioController {
    UIScrollView *_sc; CGFloat _W, _y;
    NSArray *_mixes;            // @[ {name,sub,c,path} ]
    NSMutableArray *_stations;  // @[ {name,cover,path} ]
    UIActivityIndicatorView *_spin;
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor=[SpotTheme bg];
    _W=self.view.bounds.size.width;

    UILabel*t=[[UILabel alloc] initWithFrame:CGRectMake(16,10,_W-32,30)];
    t.text=L(@"Radio"); t.font=[UIFont boldSystemFontOfSize:22]; t.textColor=[SpotTheme ink]; [self.view addSubview:t];

    _sc=[[UIScrollView alloc] initWithFrame:CGRectMake(0,46,_W,self.view.bounds.size.height-46)];
    _sc.contentInset=UIEdgeInsetsMake(8,0,84,0); _sc.alwaysBounceVertical=YES;
    _sc.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [self.view addSubview:_sc];
    _y=4;

    _mixes=@[
      @{@"name":L(@"Recent Mix"),  @"sub":L(@"Your last few weeks"), @"c":@[@0.11,@0.55,@0.38], @"path":@"me/top/tracks?limit=50&time_range=short_term"},
      @{@"name":L(@"Monthly Mix"), @"sub":L(@"Your last months"),     @"c":@[@0.20,@0.35,@0.70], @"path":@"me/top/tracks?limit=50&time_range=medium_term"},
      @{@"name":L(@"All-Time Mix"),@"sub":L(@"Your all-time favourites"),@"c":@[@0.50,@0.20,@0.60],@"path":@"me/top/tracks?limit=50&time_range=long_term"},
    ];
    [self buildMixes];

    _spin=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spin.center=CGPointMake(_W/2,_y+40); _spin.hidesWhenStopped=YES; [_spin startAnimating]; [_sc addSubview:_spin];
    [self loadStations];
}

- (void)section:(NSString *)title {
    UILabel*h=[[UILabel alloc] initWithFrame:CGRectMake(16,_y,_W-32,26)]; h.text=title; h.font=[UIFont boldSystemFontOfSize:18]; h.textColor=[SpotTheme ink]; [_sc addSubview:h]; _y+=34;
}

// ---------- Deine Mixes (3 breite Farbkarten) ----------
- (void)buildMixes {
    [self section:L(@"Your mixes")];
    CGFloat h=64, gap=10;
    for(int i=0;i<(int)_mixes.count;i++){
        NSDictionary*m=_mixes[i]; NSArray*c=m[@"c"];
        UIView*card=[[UIView alloc] initWithFrame:CGRectMake(16,_y+i*(h+gap),_W-32,h)];
        card.backgroundColor=[UIColor colorWithRed:[c[0] floatValue] green:[c[1] floatValue] blue:[c[2] floatValue] alpha:1];
        card.layer.cornerRadius=6; card.clipsToBounds=YES;
        UILabel*nm=[[UILabel alloc] initWithFrame:CGRectMake(14,12,_W-32-28,22)]; nm.text=m[@"name"]; nm.font=[UIFont boldSystemFontOfSize:17]; nm.textColor=[UIColor whiteColor]; [card addSubview:nm];
        UILabel*sb=[[UILabel alloc] initWithFrame:CGRectMake(14,34,_W-32-28,18)]; sb.text=m[@"sub"]; sb.font=[UIFont systemFontOfSize:12]; sb.textColor=[UIColor colorWithWhite:1 alpha:0.85]; [card addSubview:sb];
        UIButton*tap=[UIButton buttonWithType:UIButtonTypeCustom]; tap.frame=card.bounds; tap.tag=i; [tap addTarget:self action:@selector(openMix:) forControlEvents:UIControlEventTouchUpInside]; [card addSubview:tap];
        [_sc addSubview:card];
    }
    _y+=(int)_mixes.count*(h+gap)+8;
    _sc.contentSize=CGSizeMake(_W,_y+20);
}
- (void)openMix:(UIButton *)b {
    if(b.tag>=(int)_mixes.count) return;
    NSDictionary*m=_mixes[b.tag];
    MMTrackListController*tl=[[MMTrackListController alloc] initWithTitle:m[@"name"] path:m[@"path"]];
    [[MMRootController shared] pushContent:tl];
}

// ---------- Stationen aus deinen Top-Artists ----------
- (void)loadStations {
    [MMSpotify apiUser:@"GET" path:@"me/top/artists?limit=12&time_range=medium_term" body:nil completion:^(NSDictionary*j,NSInteger st){
        [_spin stopAnimating];
        NSMutableArray*arr=[NSMutableArray array]; NSArray*items=j[@"items"];
        if([items isKindOfClass:[NSArray class]]) for(NSDictionary*a in items){
            if(![a isKindOfClass:[NSDictionary class]]) continue;
            NSString*nm=[a[@"name"] isKindOfClass:[NSString class]]?a[@"name"]:nil; if(!nm.length) continue;
            NSString*cov=[a[@"images"] isKindOfClass:[NSArray class]]?[MMCovers bestURL:a[@"images"]]:@"";
            // Station = Genre des Artists (fällt auf den Artist-Namen zurück, wenn kein Genre da ist)
            NSString*genre=nil; id gs=a[@"genres"]; if([gs isKindOfClass:[NSArray class]]&&[gs count]&&[gs[0] isKindOfClass:[NSString class]]) genre=gs[0];
            NSString*q = genre.length ? [NSString stringWithFormat:@"genre:%%22%@%%22",mmEnc(genre)] : mmEnc(nm);
            NSString*path=[NSString stringWithFormat:@"search?q=%@&type=track&market=from_token&limit=50",q];
            [arr addObject:@{@"name":LF(@"%@ Radio",nm),@"cover":cov?:@"",@"path":path}];
        }
        _stations=arr;
        if(arr.count) [self buildStations];
        else _sc.contentSize=CGSizeMake(_W,_y+20);
    }];
}
- (void)buildStations {
    [self section:L(@"Stations for you")];
    CGFloat gap=12, tileW=(_W-16*2-gap)/2, imgH=tileW, labelH=34, tileH=imgH+labelH;
    for(int i=0;i<(int)_stations.count;i++){
        NSDictionary*s=_stations[i];
        CGFloat col=i%2, rowY=_y+(i/2)*(tileH+gap);
        UIView*tile=[[UIView alloc] initWithFrame:CGRectMake(16+col*(tileW+gap),rowY,tileW,tileH)];
        UIImageView*cov=[[UIImageView alloc] initWithFrame:CGRectMake((tileW-imgH*0.82)/2,0,imgH*0.82,imgH*0.82)];
        cov.contentMode=UIViewContentModeScaleAspectFill; cov.clipsToBounds=YES; cov.backgroundColor=[SpotTheme card];
        cov.layer.cornerRadius=imgH*0.41;   // rund (Artist)
        [MMCovers load:s[@"cover"] into:cov]; [tile addSubview:cov];
        UILabel*nm=[[UILabel alloc] initWithFrame:CGRectMake(0,imgH*0.82+6,tileW,labelH)]; nm.text=s[@"name"]; nm.numberOfLines=2; nm.textAlignment=NSTextAlignmentCenter; nm.font=[UIFont boldSystemFontOfSize:12.5]; nm.textColor=[SpotTheme ink]; [tile addSubview:nm];
        UIButton*tap=[UIButton buttonWithType:UIButtonTypeCustom]; tap.frame=tile.bounds; tap.tag=i; [tap addTarget:self action:@selector(openStation:) forControlEvents:UIControlEventTouchUpInside]; [tile addSubview:tap];
        [_sc addSubview:tile];
    }
    int rows=((int)_stations.count+1)/2; _y+=rows*(tileH+gap)+10;
    _sc.contentSize=CGSizeMake(_W,_y+20);
}
- (void)openStation:(UIButton *)b {
    if(b.tag>=(int)_stations.count) return;
    NSDictionary*s=_stations[b.tag];
    MMTrackListController*tl=[[MMTrackListController alloc] initWithTitle:s[@"name"] path:s[@"path"]];
    [[MMRootController shared] pushContent:tl];
}
@end
