// MMSheet.h — Auswahlmenü im Spotify-Look (dunkles Panel von unten, statt UIActionSheet).
#import <UIKit/UIKit.h>
#define MMSheetTag 0x5EE7   // offenes Panel bleibt über allem (z.B. Download-Leiste)
@interface MMSheet : NSObject
// options: Titel der Zeilen; done(index) beim Antippen, done(-1) beim Schließen ohne Auswahl
+ (void)showIn:(UIView *)view title:(NSString *)title subtitle:(NSString *)sub options:(NSArray *)options done:(void(^)(NSInteger idx))done;
@end
