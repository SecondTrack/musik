#import <UIKit/UIKit.h>
@interface MMPlayerController : UIViewController
@property (nonatomic, copy) NSString *trackTitle;
@property (nonatomic, copy) NSString *trackArtist;
@property (nonatomic, copy) NSString *coverURL;   // https://i.scdn.co/image/...
- (void)updateTitle:(NSString *)title artist:(NSString *)artist cover:(NSString *)cover;
@end
