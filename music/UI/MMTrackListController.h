#import <UIKit/UIKit.h>
// Zeigt eine Track-Liste (aus einem Web-API-Pfad wie "me/tracks" oder "playlists/{id}/tracks").
@interface MMTrackListController : UIViewController
- (id)initWithTitle:(NSString *)title path:(NSString *)path;
+ (NSString *)fmtBytes:(long long)b;   // "1.3 GB" / "640 MB"
@end
