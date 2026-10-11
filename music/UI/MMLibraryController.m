#import "MMLibraryController.h"
#import "SpotTheme.h"
#import "MMSpotify.h"
#import "MMTrackListController.h"
#import "MMRootController.h"
#import "MMCovers.h"
#import "MeshL10n.h"
#import "MMKeySetupController.h"
#import "MMSheet.h"
#import "MMKeepAlive.h"
#import "MMAboutView.h"

@interface MMLibraryController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation MMLibraryController {
    UITableView *_table;
    UILabel *_hint;
    NSArray *_playlists;   // @[ {name,id} ]
    BOOL _loaded;
    UILabel *_hud;                 // untere Status-/Fortschrittsleiste
    NSArray *_pressedIds;          // Track-IDs der langgedrückten Zeile
    NSString *_pressedName;
    NSInteger _pressedRow;
    UIControl *_sheetOverlay;      // Spotify-Style Bottom-Sheet
    UIView *_sheetPanel;
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor=[SpotTheme bg];
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;

    UILabel*nav=[[UILabel alloc] initWithFrame:CGRectMake(0,8,W,34)];
    nav.text=L(@"Library"); nav.font=[UIFont boldSystemFontOfSize:16]; nav.textColor=[SpotTheme ink]; nav.textAlignment=NSTextAlignmentCenter; [self.view addSubview:nav];

    // Zahnrad oben rechts: Einstellungen
    UIButton*gear=[UIButton buttonWithType:UIButtonTypeCustom]; gear.frame=CGRectMake(W-48,6,44,38);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(22,22),NO,0); [[SpotTheme ink] setFill];
    UIBezierPath*gp=[UIBezierPath bezierPath];
    for(int i=0;i<16;i++){ CGFloat a=i*M_PI/8-M_PI/16, r=(i%2)?8:10.5; CGPoint q=CGPointMake(11+r*cos(a),11+r*sin(a)); if(i==0)[gp moveToPoint:q]; else [gp addLineToPoint:q]; }
    [gp closePath]; [gp appendPath:[UIBezierPath bezierPathWithArcCenter:CGPointMake(11,11) radius:3.5 startAngle:0 endAngle:2*M_PI clockwise:NO]];
    gp.usesEvenOddFillRule=YES; [gp fill];
    [gear setImage:UIGraphicsGetImageFromCurrentImageContext() forState:UIControlStateNormal]; UIGraphicsEndImageContext();
    [gear addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:gear];

    _table=[[UITableView alloc] initWithFrame:CGRectMake(0,48,W,H-48) style:UITableViewStylePlain];
    _table.backgroundColor=[SpotTheme bg]; _table.separatorColor=[SpotTheme line];
    _table.dataSource=self; _table.delegate=self; _table.rowHeight=60; _table.contentInset=UIEdgeInsetsMake(0,0,84,0);   // Platz für untere Leisten
    _table.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [self.view addSubview:_table];

    _hint=[[UILabel alloc] initWithFrame:CGRectMake(20,120,W-40,60)]; _hint.numberOfLines=0; _hint.textColor=[SpotTheme faint]; _hint.font=[SpotTheme sub]; _hint.textAlignment=NSTextAlignmentCenter; [self.view addSubview:_hint];

    // untere Status-/Fortschrittsleiste (für Offline-Downloads via Long-Press)
    _hud=[[UILabel alloc] initWithFrame:CGRectMake(0,H-96,W,36)]; _hud.backgroundColor=[SpotTheme card]; _hud.textColor=[SpotTheme ink];
    _hud.font=[UIFont boldSystemFontOfSize:13]; _hud.textAlignment=NSTextAlignmentCenter; _hud.hidden=YES;
    _hud.autoresizingMask=UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleWidth; [self.view addSubview:_hud];

    // gedrückt halten → Offline-Download / Verwaltung
    UILongPressGestureRecognizer*lp=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPress:)];
    lp.minimumPressDuration=0.45; [_table addGestureRecognizer:lp];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dlRefresh) name:@"MMDownloadDone" object:nil];
}
- (void)dlRefresh { [_table reloadData]; }   // ✓-Badges nach Download-Ende aktualisieren
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

// --- Offline via Long-Press ---
- (NSString *)pathForRow:(NSInteger)row {
    if(row==0) return @"me/tracks?market=from_token&limit=50";
    return [NSString stringWithFormat:@"playlists/%@?market=from_token",_playlists[row-1][@"id"]];
}
- (NSString *)listPathForRow:(NSInteger)row { return [NSString stringWithFormat:@"/var/mobile/.spotcache/list_%lu.plist",(unsigned long)[self pathForRow:row].hash]; }
- (NSArray *)cachedIdsForRow:(NSInteger)row {
    NSArray*c=[NSArray arrayWithContentsOfFile:[self listPathForRow:row]];   // von MMTrackListController beim Öffnen gecacht
    return [c isKindOfClass:[NSArray class]]?[c valueForKey:@"id"]:nil;
}
- (NSArray *)idsFromItems:(NSArray *)items {
    if(![items isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray*out=[NSMutableArray array];
    for(id it in items){ if(![it isKindOfClass:[NSDictionary class]])continue; id tw=((NSDictionary*)it)[@"track"]; NSDictionary*t=[tw isKindOfClass:[NSDictionary class]]?tw:(NSDictionary*)it; id tid=t[@"id"]; if([tid isKindOfClass:[NSString class]])[out addObject:tid]; }
    return out;
}
- (void)showHud:(NSString *)msg { _hud.text=msg; _hud.hidden=NO; }
- (void)toast:(NSString *)msg {
    _hud.text=msg; _hud.hidden=NO;
    [self performSelector:@selector(hideHud) withObject:nil afterDelay:1.8];
}
- (void)hideHud { _hud.hidden=YES; }

- (void)onLongPress:(UILongPressGestureRecognizer *)g {
    if(g.state!=UIGestureRecognizerStateBegan) return;
    NSIndexPath*ip=[_table indexPathForRowAtPoint:[g locationInView:_table]];
    if(!ip || ip.row>=(NSInteger)(1+_playlists.count)) return;
    _pressedRow=ip.row;
    _pressedName=(ip.row==0)?L(@"Liked Songs"):_playlists[ip.row-1][@"name"];
    NSArray*cids=[self cachedIdsForRow:ip.row];
    if(cids.count){ _pressedIds=cids; [self showSheet]; return; }   // schnell & offline aus Cache
    [self showHud:L(@"Loading track list …")];
    [MMSpotify apiUserAllItems:[self pathForRow:ip.row] completion:^(NSArray*items,NSInteger st){   // alle Seiten
        _hud.hidden=YES;
        NSArray*ids=[self idsFromItems:items];
        if(!ids.count){ [self toast:L(@"Couldn't load tracks.")]; return; }
        for(id it in items){ if(![it isKindOfClass:[NSDictionary class]])continue; id tw=((NSDictionary*)it)[@"track"]; NSDictionary*t=[tw isKindOfClass:[NSDictionary class]]?tw:(NSDictionary*)it; id alb=t[@"album"]; if([alb isKindOfClass:[NSDictionary class]]){ NSString*cu=[MMCovers bestURL:alb[@"images"]]; if(cu.length)[MMCovers prefetch:cu]; } }  // Cover offline mit runterladen
        _pressedIds=ids; [self showSheet];
    }];
}
// --- Spotify-Style Bottom-Sheet ---
- (void)showSheet {
    [self dismissSheet];
    // über die ganze App legen (über Download-, Player- und Tab-Leiste), nicht nur über die Bibliothek
    UIView*host=[MMRootController shared].view;
    CGFloat W=host.bounds.size.width, H=host.bounds.size.height;
    BOOL have=[MMSpotify allDownloaded:_pressedIds];
    UIColor*grn=[UIColor colorWithRed:0.11 green:0.73 blue:0.33 alpha:1];
    CGFloat ph=170;

    _sheetOverlay=[[UIControl alloc] initWithFrame:host.bounds]; _sheetOverlay.tag=MMSheetTag;   // Download-Leiste bleibt darunter
    _sheetOverlay.backgroundColor=[UIColor colorWithWhite:0 alpha:0];
    [_sheetOverlay addTarget:self action:@selector(dismissSheet) forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:_sheetOverlay];

    _sheetPanel=[[UIControl alloc] initWithFrame:CGRectMake(0,H,W,ph+40)];   // UIControl: Tippen aufs Panel schließt es nicht
    _sheetPanel.backgroundColor=[UIColor colorWithWhite:0.13 alpha:1];   // Spotify-Dunkel
    _sheetPanel.layer.cornerRadius=16; _sheetPanel.clipsToBounds=YES;
    [_sheetOverlay addSubview:_sheetPanel];

    UILabel*nm=[[UILabel alloc] initWithFrame:CGRectMake(20,18,W-40,22)];
    nm.text=_pressedName; nm.font=[UIFont boldSystemFontOfSize:17]; nm.textColor=[UIColor whiteColor]; nm.adjustsFontSizeToFitWidth=YES; [_sheetPanel addSubview:nm];
    UILabel*sub=[[UILabel alloc] initWithFrame:CGRectMake(20,42,W-40,18)];
    sub.text=LF(@"Playlist · %lu tracks · %@ free",(unsigned long)_pressedIds.count,[MMTrackListController fmtBytes:[MMSpotify freeDiskBytes]]); sub.font=[UIFont systemFontOfSize:13]; sub.textColor=[UIColor colorWithWhite:0.58 alpha:1]; [_sheetPanel addSubview:sub];

    UIView*ln=[[UIView alloc] initWithFrame:CGRectMake(0,72,W,0.5)]; ln.backgroundColor=[UIColor colorWithWhite:1 alpha:0.12]; [_sheetPanel addSubview:ln];

    UIButton*row=[UIButton buttonWithType:UIButtonTypeCustom]; row.frame=CGRectMake(0,78,W,56);
    [row addTarget:self action:@selector(sheetToggle) forControlEvents:UIControlEventTouchUpInside]; [_sheetPanel addSubview:row];
    UIView*ic=[[UIView alloc] initWithFrame:CGRectMake(20,14,28,28)]; ic.layer.cornerRadius=14; ic.userInteractionEnabled=NO;
    UILabel*icl=[[UILabel alloc] initWithFrame:ic.bounds]; icl.textAlignment=NSTextAlignmentCenter; icl.font=[UIFont boldSystemFontOfSize:15]; icl.userInteractionEnabled=NO;
    if(have){ ic.backgroundColor=grn; icl.text=@"✓"; icl.textColor=[UIColor whiteColor]; }
    else { ic.layer.borderWidth=1.5; ic.layer.borderColor=[UIColor colorWithWhite:0.78 alpha:1].CGColor; icl.text=@"↓"; icl.textColor=[UIColor colorWithWhite:0.92 alpha:1]; icl.font=[UIFont boldSystemFontOfSize:17]; }
    [ic addSubview:icl]; [row addSubview:ic];
    UILabel*rl=[[UILabel alloc] initWithFrame:CGRectMake(62,0,W-80,56)]; rl.text=have?L(@"Remove from downloads"):L(@"Download to listen offline"); rl.textColor=[UIColor whiteColor]; rl.font=[UIFont systemFontOfSize:16]; rl.userInteractionEnabled=NO; [row addSubview:rl];

    [UIView animateWithDuration:0.25 animations:^{
        _sheetOverlay.backgroundColor=[UIColor colorWithWhite:0 alpha:0.55];
        _sheetPanel.frame=CGRectMake(0,H-ph,W,ph+40);
    }];
}
- (void)dismissSheet {
    if(!_sheetPanel) return;
    UIView*ov=_sheetOverlay, *pn=_sheetPanel; _sheetOverlay=nil; _sheetPanel=nil;
    CGFloat W=ov.bounds.size.width, H=ov.bounds.size.height;
    [UIView animateWithDuration:0.2 animations:^{ ov.backgroundColor=[UIColor clearColor]; pn.frame=CGRectMake(0,H,W,pn.frame.size.height); }
                     completion:^(BOOL f){ [ov removeFromSuperview]; }];
}
- (void)sheetToggle {
    NSArray*ids=_pressedIds; BOOL have=[MMSpotify allDownloaded:ids];
    [self dismissSheet];
    if(!ids.count) return;
    if(have){ [MMSpotify unmarkOffline:ids]; [MMSpotify removeDownloads:ids]; [self toast:L(@"Download removed")]; [_table reloadData]; return; }
    // Track-Cover offline mit runterladen (aus der gecachten Liste, falls vorhanden)
    NSArray*cached=[NSArray arrayWithContentsOfFile:[self listPathForRow:_pressedRow]];
    for(id t in cached){ if([t isKindOfClass:[NSDictionary class]]){ NSString*cu=((NSDictionary*)t)[@"cover"]; if([cu isKindOfClass:[NSString class]]&&cu.length)[MMCovers prefetch:cu]; } }
    [MMSpotify markOffline:_pressedName trackIds:ids];   // dauerhaft merken -> Auto-Resume nach Neustart
    [MMSpotify queueDownloadTracks:ids];   // globale Warteschlange; Status läuft über die globale Leiste (Notifications)
    [_table reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if(_loaded) return;
    if(![MMSpotify hasUserToken]){ _hint.text=L(@"Please log in again."); return; }
    _loaded=YES; _hint.text=L(@"Loading your playlists …");
    // erst die zuletzt geladenen Playlists zeigen, frische ersetzen sie still (nur bei Änderung)
    [MMSpotify apiUserCached:@"me/playlists?limit=50" completion:^(NSDictionary*j,NSInteger st,BOOL fresh){
        NSArray*items=j[@"items"];
        if(![items isKindOfClass:[NSArray class]]){ _hint.text=(st==401)?L(@"Session expired."):L(@"Couldn't load."); _loaded=NO; return; }
        NSMutableArray*out=[NSMutableArray array];
        for(NSDictionary*p in items){ if([p isKindOfClass:[NSDictionary class]]&&p[@"id"]) [out addObject:@{@"name":p[@"name"]?:L(@"Playlist"),@"id":p[@"id"],@"cover":[MMCovers bestURL:p[@"images"]]}]; }
        _playlists=out; _hint.hidden=YES; [_table reloadData];
    }];
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return 1 + _playlists.count; }  // +1 = gespeicherte Songs

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell*c=[tv dequeueReusableCellWithIdentifier:@"r"];
    if(!c){ c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"r"];
        c.backgroundColor=[SpotTheme bg]; c.selectionStyle=UITableViewCellSelectionStyleNone;
        UIImageView*th=[[UIImageView alloc] initWithFrame:CGRectMake(12,6,48,48)]; th.tag=10; th.contentMode=UIViewContentModeScaleAspectFill; th.clipsToBounds=YES; th.layer.cornerRadius=2; [c.contentView addSubview:th];
        UILabel*nm=[[UILabel alloc] initWithFrame:CGRectMake(72,0,tv.bounds.size.width-72-40,60)]; nm.tag=11; nm.font=[UIFont systemFontOfSize:16]; nm.textColor=[SpotTheme ink]; [c.contentView addSubview:nm];
        c.accessoryType=UITableViewCellAccessoryDisclosureIndicator; }
    UIImageView*th=(UIImageView*)[c.contentView viewWithTag:10];
    UILabel*nm=(UILabel*)[c.contentView viewWithTag:11];
    if(ip.row==0){
        nm.text=L(@"Liked Songs"); nm.textColor=[SpotTheme green];
        th.image=nil; th.backgroundColor=[UIColor colorWithRed:0.29 green:0.16 blue:0.78 alpha:1];
        for(UIView*v in th.subviews)[v removeFromSuperview];
        UILabel*hl=[[UILabel alloc] initWithFrame:th.bounds]; hl.text=@"♥"; hl.textAlignment=NSTextAlignmentCenter; hl.font=[UIFont systemFontOfSize:22]; hl.textColor=[UIColor whiteColor]; [th addSubview:hl];
    } else {
        for(UIView*v in th.subviews)[v removeFromSuperview];
        nm.text=_playlists[ip.row-1][@"name"]; nm.textColor=[SpotTheme ink];
        th.image=nil; th.backgroundColor=[SpotTheme card];
        NSString*cu=_playlists[ip.row-1][@"cover"], *pid=_playlists[ip.row-1][@"id"];
        th.accessibilityIdentifier=pid;                                   // Zelle wiederverwendet? -> Mosaik nur passend setzen
        if(cu.length) [MMCovers load:cu into:th];
        else [MMCovers playlistCover:pid completion:^(NSString*mu){       // kein eigenes Bild -> Mosaik wie in der Spotify-App
            if(mu && [th.accessibilityIdentifier isEqualToString:pid]) [MMCovers load:mu into:th]; }];
    }
    NSArray*cids=[self cachedIdsForRow:ip.row];
    if(cids.count && [MMSpotify allDownloaded:cids]){
        UILabel*chk=[[UILabel alloc] initWithFrame:CGRectMake(0,0,24,24)]; chk.text=@"✓"; chk.textColor=[SpotTheme green]; chk.font=[UIFont boldSystemFontOfSize:17]; chk.textAlignment=NSTextAlignmentCenter;
        c.accessoryView=chk;
    } else { c.accessoryView=nil; c.accessoryType=UITableViewCellAccessoryDisclosureIndicator; }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    MMTrackListController*tl;
    if(ip.row==0) tl=[[MMTrackListController alloc] initWithTitle:L(@"Liked Songs") path:@"me/tracks?market=from_token&limit=50"];
    else { NSDictionary*p=_playlists[ip.row-1]; tl=[[MMTrackListController alloc] initWithTitle:p[@"name"] path:[NSString stringWithFormat:@"playlists/%@?market=from_token",p[@"id"]]]; }
    [[MMRootController shared] pushContent:tl];   // im Inhaltsbereich -> untere Leisten bleiben sichtbar
}
// ---- Einstellungen ----
- (void)openSettings {
    // über die ganze App legen (auch über Tab- und Player-Leiste)
    UIView*host=[MMRootController shared].view;
    [MMSheet showIn:host title:L(@"Settings") subtitle:nil
            options:@[L(@"iPod mode (click wheel)"),([MMSpotify hasSearchKey]?L(@"Change search key"):L(@"Unlock search")),
                      ([MMKeepAlive enabled]?L(@"Background download: On"):L(@"Background download: Off")),L(@"About this app")]
               done:^(NSInteger i){ if(i>=0) [self settingsChoice:i]; }];
}
- (void)settingsChoice:(NSInteger)i {
    if(i==2){ [MMKeepAlive setEnabled:![MMKeepAlive enabled]]; [self openSettings]; return; }   // umschalten, Panel zeigt neuen Stand
    if(i==3){ [MMAboutView showIn:[MMRootController shared].view]; return; }
    if(i==0){ [[MMRootController shared] setClassicMode:YES]; return; }
    if(i==1){
        MMKeySetupController*k=[[MMKeySetupController alloc] init]; k.skippable=NO;
        k.onDone=^(BOOL saved){ [[MMRootController shared] popContent]; };
        [[MMRootController shared] pushContent:k];
    }
}
@end
