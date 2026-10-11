#import "MMSearchController.h"
#import "SpotTheme.h"
#import "MMSpotify.h"
#import "MMRootController.h"
#import "MMKeySetupController.h"
#import "MeshL10n.h"

@interface MMSearchController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@end

@implementation MMSearchController {
    UITextField *_field;
    UITableView *_table;
    UILabel *_hint;
    UIButton *_unlock;   // "Suche freischalten" ohne eigenen Schlüssel
    NSArray *_results;   // @[ {id,title,artist,cover} ]
    NSCache *_imgCache;
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor=[SpotTheme bg];
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;
    _imgCache=[[NSCache alloc] init];

    UILabel*nav=[[UILabel alloc] initWithFrame:CGRectMake(0,8,W,34)];
    nav.text=L(@"Search"); nav.font=[UIFont boldSystemFontOfSize:16]; nav.textColor=[SpotTheme ink]; nav.textAlignment=NSTextAlignmentCenter; [self.view addSubview:nav];

    // Suchfeld
    UIView*box=[[UIView alloc] initWithFrame:CGRectMake(16,46,W-32,42)]; box.backgroundColor=[UIColor whiteColor]; box.layer.cornerRadius=8; [self.view addSubview:box];
    _field=[[UITextField alloc] initWithFrame:CGRectMake(12,0,W-32-24,42)];
    _field.placeholder=L(@"Artists, songs …"); _field.font=[UIFont systemFontOfSize:15]; _field.textColor=[UIColor blackColor];
    _field.returnKeyType=UIReturnKeySearch; _field.delegate=self; _field.autocorrectionType=UITextAutocorrectionTypeNo;
    _field.clearButtonMode=UITextFieldViewModeWhileEditing; _field.contentVerticalAlignment=UIControlContentVerticalAlignmentCenter; [box addSubview:_field];

    _table=[[UITableView alloc] initWithFrame:CGRectMake(0,98,W,H-98) style:UITableViewStylePlain];
    _table.backgroundColor=[SpotTheme bg]; _table.separatorStyle=UITableViewCellSeparatorStyleNone;
    _table.dataSource=self; _table.delegate=self; _table.rowHeight=66; _table.contentInset=UIEdgeInsetsMake(0,0,60,0); [self.view addSubview:_table];

    _hint=[[UILabel alloc] initWithFrame:CGRectMake(20,140,W-40,40)]; _hint.text=L(@"Find millions of songs."); _hint.textColor=[SpotTheme faint]; _hint.font=[SpotTheme sub]; _hint.textAlignment=NSTextAlignmentCenter; _hint.numberOfLines=0; [self.view addSubview:_hint];

    _unlock=[UIButton buttonWithType:UIButtonTypeCustom]; _unlock.frame=CGRectMake(50,196,W-100,44);
    _unlock.backgroundColor=[SpotTheme green]; _unlock.layer.cornerRadius=22; _unlock.titleLabel.font=[UIFont boldSystemFontOfSize:14];
    [_unlock setTitle:L(@"UNLOCK SEARCH") forState:UIControlStateNormal]; [_unlock setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_unlock addTarget:self action:@selector(openKeySetup) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:_unlock];
    // Schlüssel ändern/entfernen: lange auf "Suche" drücken
    nav.userInteractionEnabled=YES;
    [nav addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(navLongPress:)]];
}

- (void)viewDidLoad { [super viewDidLoad]; [self refreshKeyState]; }
- (void)refreshKeyState {
    BOOL has=[MMSpotify hasSearchKey];
    _unlock.hidden=has; _field.enabled=has; _field.superview.alpha=has?1:0.4;
    if(!has){ _results=nil; [_table reloadData]; _hint.hidden=NO;
        _hint.frame=CGRectMake(20,120,self.view.bounds.size.width-40,64);
        _hint.text=L(@"Search needs your own free Spotify key. Set it up once in about 3 minutes."); }
    else if(!_results.count){ _hint.frame=CGRectMake(20,140,self.view.bounds.size.width-40,40); _hint.text=L(@"Find millions of songs."); }
}
- (void)navLongPress:(UILongPressGestureRecognizer *)g { if(g.state==UIGestureRecognizerStateBegan) [self openKeySetup]; }
- (void)openKeySetup {
    [self.view endEditing:YES];
    MMKeySetupController*k=[[MMKeySetupController alloc] init]; k.skippable=NO;
    __weak MMSearchController*ws=self;
    k.onDone=^(BOOL saved){ [[MMRootController shared] popContent]; [ws refreshKeyState]; };
    [[MMRootController shared] pushContent:k];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; [self doSearch:tf.text]; return YES; }

- (void)doSearch:(NSString *)q {
    if(!q.length) return;
    _hint.text=L(@"Searching…"); _hint.hidden=NO;
    NSString*enc=[q stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    [MMSpotify webGet:[NSString stringWithFormat:@"search?q=%@&type=track&limit=10",enc] completion:^(NSDictionary*j,NSInteger st){
        if(st==429){ _hint.text=L(@"Too many requests – wait a moment and retry."); _hint.hidden=NO; return; }
        NSArray*items=[[j objectForKey:@"tracks"] objectForKey:@"items"];
        if(![items isKindOfClass:[NSArray class]] || !items.count){ _results=nil; [_table reloadData]; _hint.text=(st==401)?L(@"Your search key no longer works. Long-press \"Search\" at the top to change it."):L(@"Nothing found."); _hint.hidden=NO; return; }
        NSMutableArray*out=[NSMutableArray array];
        for(NSDictionary*t in items){
            NSArray*arts=t[@"artist"]?:t[@"artists"]; NSString*an=@"";
            if([arts isKindOfClass:[NSArray class]] && arts.count) an=[arts[0] objectForKey:@"name"]?:@"";
            NSArray*imgs=[[t objectForKey:@"album"] objectForKey:@"images"]; NSString*cov=@"";
            if([imgs isKindOfClass:[NSArray class]] && imgs.count) cov=[[imgs lastObject] objectForKey:@"url"]?:@"";
            [out addObject:@{@"id":t[@"id"]?:@"",@"title":t[@"name"]?:@"",@"artist":an,@"cover":cov}];
        }
        _results=out; _hint.hidden=YES; [_table reloadData];
    }];
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return _results.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    CGFloat W=tv.bounds.size.width;
    UITableViewCell*c=[tv dequeueReusableCellWithIdentifier:@"r"];
    if(!c){ c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"r"];
        c.backgroundColor=[SpotTheme bg]; c.selectionStyle=UITableViewCellSelectionStyleNone;
        UIImageView*cov=[[UIImageView alloc] initWithFrame:CGRectMake(16,9,48,48)]; cov.tag=1; cov.backgroundColor=[SpotTheme card]; cov.layer.cornerRadius=4; cov.clipsToBounds=YES; cov.contentMode=UIViewContentModeScaleAspectFill; [c.contentView addSubview:cov];
        UILabel*ti=[[UILabel alloc] initWithFrame:CGRectMake(78,14,W-78-16,20)]; ti.tag=2; ti.font=[UIFont boldSystemFontOfSize:15]; ti.textColor=[SpotTheme ink]; [c.contentView addSubview:ti];
        UILabel*ar=[[UILabel alloc] initWithFrame:CGRectMake(78,36,W-78-16,18)]; ar.tag=3; ar.font=[SpotTheme sub]; ar.textColor=[SpotTheme muted]; [c.contentView addSubview:ar]; }
    NSDictionary*t=_results[ip.row];
    UIImageView*cov=(UIImageView*)[c.contentView viewWithTag:1];
    ((UILabel*)[c.contentView viewWithTag:2]).text=t[@"title"];
    ((UILabel*)[c.contentView viewWithTag:3]).text=t[@"artist"];
    cov.image=nil;
    NSString*url=t[@"cover"];
    if(url.length){
        UIImage*ci=[_imgCache objectForKey:url];
        if(ci){ cov.image=ci; }
        else dispatch_async(dispatch_get_global_queue(0,0), ^{
            NSData*d=[NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
            UIImage*img=d?[UIImage imageWithData:d]:nil;
            if(img){ [_imgCache setObject:img forKey:url];
                dispatch_async(dispatch_get_main_queue(), ^{
                    UITableViewCell*cc=[tv cellForRowAtIndexPath:ip]; if(cc){ ((UIImageView*)[cc.contentView viewWithTag:1]).image=img; } });
            }
        });
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [[MMRootController shared] playList:_results index:ip.row];   // ganze Trefferliste = Queue
    [[MMRootController shared] openPlayer];
}
@end
