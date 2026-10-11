// MMCoverFlowView.h — Cover Flow im Vollbild-Querformat (wie beim iPhone/iPod touch 2007):
// Playlist-Cover wischen, mittleres antippen = umdrehen, Rückseite zeigt die Titel.
#import <UIKit/UIKit.h>
@interface MMCoverFlowView : UIView
@property (nonatomic, copy) void (^onClose)(void);   // "Fertig" gedrückt
- (id)initWithLandscapeSize:(CGSize)size;
@end
