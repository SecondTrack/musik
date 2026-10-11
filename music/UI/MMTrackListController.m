#import "MMTrackListController.h"
#import "SpotTheme.h"
#import "MMSpotify.h"
#import "MMRootController.h"
#import "MMCovers.h"
#import "MeshL10n.h"

@interface MMTrackListController () <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate>
@end

@implementation MMTrackListController {
    NSString *_title, *_path;
    UITableView *_table;
    UILabel *_hint;
    NSMutableArray *_tracks;   // @[ {id,title,artist,cover} ] — wächst beim Scrollen
    NSCache *_imgCache;
    UIButton *_offBar; UIView *_offProg; UIColor *_grn;
    NSString *_nextPath;       // relativer Pfad der nächsten Seite (nil = fertig)
    BOOL _loadingPage, _firstDone;
    BOOL _showingCache;        // gerade wird die gespeicherte Liste gezeigt, erste frische Seite steht noch aus
    NSArray *_allIds;          // vollständige ID-Liste (für Download der GANZEN Playlist)
    UIActivityIndicatorView *_spin;
}

- (id)initWithTitle:(NSString *)title path:(NSString *)path {
    if((self=[super init])){ _title=title; _path=path; _imgCache=[[NSCache alloc] init]; }
    return self;
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor=[SpotTheme bg];
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;

    UIButton*back=[UIButton buttonWithType:UIButtonTypeCustom]; back.frame=CGRectMake(8,8,60,34);
    [back setTitle:L(@"‹ Back") forState:UIControlStateNormal]; [back setTitleColor:[SpotTheme ink] forState:UIControlStateNormal];
    back.titleLabel.font=[UIFont systemFontOfSize:14]; back.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
    [back addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:back];

    UILabel*nav=[[UILabel alloc] initWithFrame:CGRectMake(70,8,W-140,34)];
    nav.text=_title; nav.font=[UIFont boldSystemFontOfSize:16]; nav.textColor=[SpotTheme ink]; nav.textAlignment=NSTextAlignmentCenter; nav.adjustsFontSizeToFitWidth=YES; [self.view addSubview:nav];

    // --- Offline-Leiste (volle Breite, deutlich sichtbar) ---
    _grn=[UIColor colorWithRed:0.11 green:0.73 blue:0.33 alpha:1];
    _offBar=[UIButton buttonWithType:UIButtonTypeCustom]; _offBar.frame=CGRectMake(0,46,W,44);
    _offBar.backgroundColor=[SpotTheme card]; _offBar.titleLabel.font=[UIFont boldSystemFontOfSize:14];
    _offBar.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft; _offBar.contentEdgeInsets=UIEdgeInsetsMake(0,16,0,16);
    _offBar.hidden=YES; [_offBar addTarget:self action:@selector(toggleDownload) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:_offBar];
    _offProg=[[UIView alloc] initWithFrame:CGRectMake(0,88,0,2)]; _offProg.backgroundColor=_grn; _offProg.hidden=YES; [self.view addSubview:_offProg];

    _table=[[UITableView alloc] initWithFrame:CGRectMake(0,92,W,H-92) style:UITableViewStylePlain];
    _table.backgroundColor=[SpotTheme bg]; _table.separatorStyle=UITableViewCellSeparatorStyleNone;
    _table.dataSource=self; _table.delegate=self; _table.rowHeight=66; _table.contentInset=UIEdgeInsetsMake(0,0,90,0);
    _table.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth; [self.view addSubview:_table];

    _hint=[[UILabel alloc] initWithFrame:CGRectMake(20,150,W-40,40)]; _hint.textColor=[SpotTheme faint]; _hint.font=[SpotTheme sub]; _hint.textAlignment=NSTextAlignmentCenter; [self.view addSubview:_hint];
    _spin=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spin.center=CGPointMake(W/2,130); _spin.hidesWhenStopped=YES; [_spin startAnimating]; [self.view addSubview:_spin];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dlRefresh) name:@"MMDownloadDone" object:nil];
    [self load];
}

- (NSString *)listPath { return [NSString stringWithFormat:@"/var/mobile/.spotcache/list_%lu.plist", (unsigned long)_path.hash]; }

- (void)load {
    _tracks=[NSMutableArray array];
    NSArray*cached=[NSArray arrayWithContentsOfFile:[self listPath]];   // zuletzt komplett geladene Liste sofort zeigen
    if(cached.count){ _tracks=[cached mutableCopy]; _allIds=[cached valueForKey:@"id"]; _showingCache=YES;
        [_spin stopAnimating]; _hint.hidden=YES; [self updateDlState]; [_table reloadData]; }
    [self loadNextPage];
}

- (NSArray *)parseItems:(NSArray *)items {
    NSMutableArray*out=[NSMutableArray array];
    for(NSDictionary*it in items){
        if(![it isKindOfClass:[NSDictionary class]]) continue;
        id tw=it[@"track"]; NSDictionary*t=[tw isKindOfClass:[NSDictionary class]]?tw:([it isKindOfClass:[NSDictionary class]]?it:nil);
        NSString*tid=[t[@"id"] isKindOfClass:[NSString class]]?t[@"id"]:nil;
        if(!tid) continue;   // NSNull/removed/local tracks überspringen
        NSString*nm=[t[@"name"] isKindOfClass:[NSString class]]?t[@"name"]:@"";
        id arts=t[@"artists"]; NSString*an=@"";
        if([arts isKindOfClass:[NSArray class]] && [arts count]){ id a0=[arts objectAtIndex:0]; if([a0 isKindOfClass:[NSDictionary class]] && [a0[@"name"] isKindOfClass:[NSString class]]) an=a0[@"name"]; }
        id alb=t[@"album"]; NSString*cov=@"";
        if([alb isKindOfClass:[NSDictionary class]]) cov=[MMCovers bestURL:alb[@"images"]];   // scharfes (mittleres) Cover
        [out addObject:@{@"id":tid,@"title":nm,@"artist":an,@"cover":cov}];
    }
    return out;
}

// Lädt EINE Seite (50–100 Titel). Beim Scrollen ans Ende wird die nächste nachgeladen.
- (void)loadNextPage {
    if(_loadingPage) return;
    if(_firstDone && !_nextPath) return;   // alles da
    _loadingPage=YES;
    NSString*p = _nextPath ?: _path;       // erste Seite = _path
    [MMSpotify apiUser:@"GET" path:p body:nil completion:^(NSDictionary*j,NSInteger st){
        _loadingPage=YES;   // bleibt gesperrt bis fertig verarbeitet
        NSDictionary*page=[j isKindOfClass:[NSDictionary class]]?j:nil;
        if(page && ![page[@"items"] isKindOfClass:[NSArray class]] && [page[@"tracks"] isKindOfClass:[NSDictionary class]]) page=page[@"tracks"];  // Playlist: items unter .tracks
        NSArray*items=page[@"items"];
        if(![items isKindOfClass:[NSArray class]]){
            _loadingPage=NO; _firstDone=YES; [_spin stopAnimating];
            if(_showingCache){ _showingCache=NO; _nextPath=nil; return; }   // offline -> gespeicherte Liste bleibt stehen
            if(!_tracks.count){
                NSArray*cached=[NSArray arrayWithContentsOfFile:[self listPath]];   // Offline-Fallback
                if(cached.count){ _tracks=[cached mutableCopy]; _nextPath=nil; _hint.hidden=YES; [self updateDlState]; [_table reloadData]; return; }
                _hint.text=(st==401)?L(@"Session expired."):L(@"Couldn't load (offline?).");
            }
            return;
        }
        NSArray*fresh=[self parseItems:items];
        if(_showingCache){
            // Erste frische Seite gegen die gezeigte Liste prüfen: gleiche Länge + gleicher Anfang -> unverändert lassen
            _showingCache=NO;
            id tot=page[@"total"]; NSUInteger total=[tot respondsToSelector:@selector(unsignedIntegerValue)]?[tot unsignedIntegerValue]:0;
            if(total>=items.count-fresh.count) total-=items.count-fresh.count;   // übersprungene (lokale/gelöschte) Titel der ersten Seite nicht mitzählen
            NSArray*head=(_tracks.count>=fresh.count)?[_tracks subarrayWithRange:NSMakeRange(0,fresh.count)]:nil;
            if(total==_tracks.count && [head isEqualToArray:fresh]){ _firstDone=YES; _nextPath=nil; _loadingPage=NO; return; }
            _tracks=[NSMutableArray array]; _allIds=nil;   // geändert -> frisch aufbauen
        }
        [_tracks addObjectsFromArray:fresh];
        // next-URL -> relativer Pfad merken
        id next=page[@"next"]; _nextPath=nil;
        if([next isKindOfClass:[NSString class]] && [next length]){ NSRange r=[next rangeOfString:@"/v1/"]; _nextPath=(r.location!=NSNotFound)?[next substringFromIndex:r.location+4]:next; }
        _firstDone=YES; _loadingPage=NO; [_spin stopAnimating];
        _hint.hidden=(_tracks.count>0); if(!_tracks.count)_hint.text=L(@"Empty.");
        // komplette Liste erst cachen wenn alle Seiten da sind
        if(!_nextPath && _tracks.count){ [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/.spotcache" withIntermediateDirectories:YES attributes:nil error:NULL]; [_tracks writeToFile:[self listPath] atomically:YES]; _allIds=[_tracks valueForKey:@"id"]; }
        [self updateDlState]; [_table reloadData];
    }];
}

+ (NSString *)fmtBytes:(long long)b {
    if(b>=1024LL*1024*1024) return [NSString stringWithFormat:@"%.1f GB",b/1073741824.0];
    return [NSString stringWithFormat:@"%.0f MB",b/1048576.0];
}
- (void)updateDlState {
    if(!_tracks.count){ _offBar.hidden=YES; _offProg.hidden=YES; return; }
    _offBar.hidden=NO; _offBar.enabled=YES; _offProg.hidden=YES;
    NSArray*ids=_allIds?:[_tracks valueForKey:@"id"];   // _allIds = vollständig (nach letzter Seite)
    NSString*freeS=[MMTrackListController fmtBytes:[MMSpotify freeDiskBytes]];
    if(_allIds && [MMSpotify allDownloaded:ids]){
        [_offBar setTitle:L(@"✓  Available offline — tap to remove") forState:UIControlStateNormal];
        [_offBar setTitleColor:_grn forState:UIControlStateNormal];
    } else {
        NSString*cnt = _allIds ? LF(@"%lu tracks",(unsigned long)_allIds.count)
                               : (_nextPath?LF(@"%lu+ tracks",(unsigned long)_tracks.count):LF(@"%lu tracks",(unsigned long)_tracks.count));
        [_offBar setTitle:LF(@"↓  Save offline  ·  %@  ·  %@ free",cnt,freeS) forState:UIControlStateNormal];
        [_offBar setTitleColor:[SpotTheme ink] forState:UIControlStateNormal];
    }
}
- (void)toggleDownload {
    if(!_tracks.count) return;
    NSArray*ids=_allIds?:[_tracks valueForKey:@"id"];
    if(_allIds && [MMSpotify allDownloaded:ids]){
        [[[UIAlertView alloc] initWithTitle:L(@"Remove offline?") message:L(@"Delete the downloaded tracks of this playlist.") delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Remove"),nil] show];
        return;
    }
    // Noch nicht alle Seiten da? -> erst vollständige ID-Liste holen (klein), dann GANZE Playlist laden.
    if(!_allIds){
        _offBar.enabled=NO; [_offBar setTitle:L(@"Fetching track list …") forState:UIControlStateNormal];
        [MMSpotify apiUserAllItems:_path completion:^(NSArray*items,NSInteger st){
            NSMutableArray*out=[NSMutableArray array];
            for(id it in items){
                if(![it isKindOfClass:[NSDictionary class]])continue;
                id tw=((NSDictionary*)it)[@"track"]; NSDictionary*t=[tw isKindOfClass:[NSDictionary class]]?tw:(NSDictionary*)it;
                id tid=t[@"id"]; if([tid isKindOfClass:[NSString class]])[out addObject:tid];
                id alb=t[@"album"]; if([alb isKindOfClass:[NSDictionary class]]){ NSString*cu=[MMCovers bestURL:alb[@"images"]]; if(cu.length)[MMCovers prefetch:cu]; }  // Cover offline mit runterladen
            }
            if(!out.count){ [self updateDlState]; return; }
            _allIds=out; [self startDownload:out];
        }];
        return;
    }
    [self startDownload:ids];
}
- (void)startDownload:(NSArray *)ids {
    for(NSDictionary*t in _tracks){ NSString*cu=t[@"cover"]; if([cu isKindOfClass:[NSString class]]&&cu.length)[MMCovers prefetch:cu]; }  // geladene Cover offline sichern
    [MMSpotify markOffline:_title trackIds:ids];   // dauerhaft als Offline-Playlist merken -> Auto-Resume nach Neustart
    [MMSpotify queueDownloadTracks:ids];   // globale Warteschlange; Status läuft über die globale Leiste (Notifications)
    [self updateDlState];
}
- (void)alertView:(UIAlertView *)av clickedButtonAtIndex:(NSInteger)idx {
    if(idx==1){ NSArray*ids=_allIds?:[_tracks valueForKey:@"id"]; [MMSpotify unmarkOffline:ids]; [MMSpotify removeDownloads:ids]; [self updateDlState]; [_table reloadData]; }
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return _tracks.count; }
- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip {
    if(_nextPath && !_loadingPage && ip.row >= (NSInteger)_tracks.count-8) [self loadNextPage];   // nahe Ende -> nächste Seite
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    CGFloat W=tv.bounds.size.width;
    UITableViewCell*c=[tv dequeueReusableCellWithIdentifier:@"r"];
    if(!c){ c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"r"];
        c.backgroundColor=[SpotTheme bg]; c.selectionStyle=UITableViewCellSelectionStyleNone;
        UIImageView*cov=[[UIImageView alloc] initWithFrame:CGRectMake(16,9,48,48)]; cov.tag=1; cov.backgroundColor=[SpotTheme card]; cov.layer.cornerRadius=4; cov.clipsToBounds=YES; cov.contentMode=UIViewContentModeScaleAspectFill; [c.contentView addSubview:cov];
        UILabel*ti=[[UILabel alloc] initWithFrame:CGRectMake(78,14,W-78-40,20)]; ti.tag=2; ti.font=[UIFont boldSystemFontOfSize:15]; ti.textColor=[SpotTheme ink]; [c.contentView addSubview:ti];
        UILabel*ar=[[UILabel alloc] initWithFrame:CGRectMake(78,36,W-78-40,18)]; ar.tag=3; ar.font=[SpotTheme sub]; ar.textColor=[SpotTheme muted]; [c.contentView addSubview:ar];
        UILabel*dl=[[UILabel alloc] initWithFrame:CGRectMake(W-34,0,26,66)]; dl.tag=4; dl.font=[UIFont boldSystemFontOfSize:15]; dl.textColor=_grn; dl.textAlignment=NSTextAlignmentCenter; dl.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin; [c.contentView addSubview:dl]; }
    NSDictionary*t=_tracks[ip.row];
    ((UILabel*)[c.contentView viewWithTag:2]).text=t[@"title"];
    ((UILabel*)[c.contentView viewWithTag:3]).text=t[@"artist"];
    ((UILabel*)[c.contentView viewWithTag:4]).text=[MMSpotify isDownloaded:t[@"id"]]?@"✓":@"";
    UIImageView*cov=(UIImageView*)[c.contentView viewWithTag:1]; cov.image=nil;
    [MMCovers load:t[@"cover"] into:cov];   // gemeinsamer RAM+Platte-Cache (reuse-sicher)
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [[MMRootController shared] playList:_tracks index:ip.row];
    [[MMRootController shared] openPlayer];   // Player als Vollbild; Titelliste bleibt darunter im Inhaltsbereich
}
- (void)close { [[MMRootController shared] popContent]; }
- (void)dlRefresh { [self updateDlState]; [_table reloadData]; }   // nach Download-Ende ✓-Marken aktualisieren
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
