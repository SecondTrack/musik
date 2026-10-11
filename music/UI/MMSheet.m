#import "MMSheet.h"
#import "SpotTheme.h"
#import <QuartzCore/QuartzCore.h>

@interface MMSheetView : UIControl
@property (nonatomic, copy) void (^done)(NSInteger idx);
@property (nonatomic, strong) UIView *panel;
@end
@implementation MMSheetView
- (void)close:(NSInteger)idx {
    CGFloat H=self.bounds.size.height; void (^d)(NSInteger)=self.done; self.done=nil;
    [UIView animateWithDuration:0.22 animations:^{
        self.backgroundColor=[UIColor colorWithWhite:0 alpha:0];
        self.panel.frame=CGRectMake(0,H,self.panel.frame.size.width,self.panel.frame.size.height);
    } completion:^(BOOL f){ [self removeFromSuperview]; if(d) d(idx); }];
}
- (void)tapOutside { [self close:-1]; }
- (void)tapRow:(UIControl *)row { [self close:row.tag]; }
- (void)rowDown:(UIControl *)row { row.backgroundColor=[UIColor colorWithWhite:1 alpha:0.08]; }
- (void)rowUp:(UIControl *)row { row.backgroundColor=[UIColor clearColor]; }
@end

@implementation MMSheet
+ (void)showIn:(UIView *)view title:(NSString *)title subtitle:(NSString *)sub options:(NSArray *)options done:(void(^)(NSInteger))done {
    CGFloat W=view.bounds.size.width, H=view.bounds.size.height;
    MMSheetView*ov=[[MMSheetView alloc] initWithFrame:view.bounds]; ov.done=done; ov.tag=MMSheetTag;
    ov.backgroundColor=[UIColor colorWithWhite:0 alpha:0];
    [ov addTarget:ov action:@selector(tapOutside) forControlEvents:UIControlEventTouchUpInside];
    CGFloat head=sub.length?72:56, rowH=52, ph=head+options.count*rowH+16;
    UIControl*p=[[UIControl alloc] initWithFrame:CGRectMake(0,H,W,ph+20)];   // UIControl: Tippen aufs Panel schließt es nicht
    p.backgroundColor=[UIColor colorWithWhite:0.13 alpha:1]; p.layer.cornerRadius=16; p.clipsToBounds=YES;
    UIView*grip=[[UIView alloc] initWithFrame:CGRectMake(W/2-18,8,36,4)]; grip.backgroundColor=[UIColor colorWithWhite:1 alpha:0.25]; grip.layer.cornerRadius=2; [p addSubview:grip];
    UILabel*t=[[UILabel alloc] initWithFrame:CGRectMake(20,20,W-40,22)]; t.text=title; t.font=[UIFont boldSystemFontOfSize:17]; t.textColor=[UIColor whiteColor]; t.backgroundColor=[UIColor clearColor]; [p addSubview:t];
    if(sub.length){ UILabel*s=[[UILabel alloc] initWithFrame:CGRectMake(20,44,W-40,18)]; s.text=sub; s.font=[UIFont systemFontOfSize:13]; s.textColor=[UIColor colorWithWhite:0.58 alpha:1]; s.backgroundColor=[UIColor clearColor]; [p addSubview:s]; }
    UIView*ln=[[UIView alloc] initWithFrame:CGRectMake(0,head,W,0.5)]; ln.backgroundColor=[UIColor colorWithWhite:1 alpha:0.12]; [p addSubview:ln];
    for(NSUInteger i=0;i<options.count;i++){
        UIControl*row=[[UIControl alloc] initWithFrame:CGRectMake(0,head+8+i*rowH,W,rowH)]; row.tag=i;
        UILabel*l=[[UILabel alloc] initWithFrame:CGRectMake(20,0,W-60,rowH)]; l.text=options[i]; l.font=[UIFont systemFontOfSize:16]; l.textColor=[UIColor whiteColor]; l.backgroundColor=[UIColor clearColor];
        l.userInteractionEnabled=NO; [row addSubview:l];
        UILabel*chev=[[UILabel alloc] initWithFrame:CGRectMake(W-34,0,20,rowH)]; chev.text=@"›"; chev.font=[UIFont systemFontOfSize:24]; chev.textColor=[UIColor colorWithWhite:0.45 alpha:1]; chev.backgroundColor=[UIColor clearColor];
        chev.userInteractionEnabled=NO; [row addSubview:chev];
        [row addTarget:ov action:@selector(tapRow:) forControlEvents:UIControlEventTouchUpInside];
        [row addTarget:ov action:@selector(rowDown:) forControlEvents:UIControlEventTouchDown|UIControlEventTouchDragEnter];
        [row addTarget:ov action:@selector(rowUp:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchDragExit|UIControlEventTouchCancel];
        [p addSubview:row];
    }
    ov.panel=p; [ov addSubview:p]; [view addSubview:ov];
    [UIView animateWithDuration:0.25 animations:^{
        ov.backgroundColor=[UIColor colorWithWhite:0 alpha:0.55];
        p.frame=CGRectMake(0,H-ph,W,ph+20);
    }];
}
@end
