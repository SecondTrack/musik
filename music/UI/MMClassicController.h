// MMClassicController.h — iPod-Modus im Stil des iPod classic: Display mit Menülisten oben, Click Wheel unten.
// Liegt als Overlay über dem MMRootController; die Wiedergabe (Queue, Sperrbildschirm, Fernbedienung) bleibt dort.
#import <UIKit/UIKit.h>
@interface MMClassicController : UIViewController
// Offline-Download im Display anzeigen (progress 0..1; <0 = kurze Meldung, blendet sich aus)
- (void)showDownload:(NSString *)text progress:(CGFloat)progress;
@end
