// MMKeySetupController.h — Anleitung + Eingabe für den eigenen Spotify-Entwickler-Schlüssel (schaltet die Suche frei).
#import <UIKit/UIKit.h>
@interface MMKeySetupController : UIViewController
@property (nonatomic, assign) BOOL skippable;          // nach dem Pairing: "Später" anbieten; aus der Suche: "Zurück"
@property (nonatomic, copy) void (^onDone)(BOOL saved);
@end
