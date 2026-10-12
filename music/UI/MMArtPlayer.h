// MMArtPlayer.h — abstrakte Player-Ansichten (Orbit, Linie) statt des Standard-Players.
// Bedienung überall gleich: Tippen = Pause, Wischen links/rechts = Weiter/Zurück, runter = Schließen,
// lange drücken = Menü (Shuffle, Wiederholen, Stil). Spulen je nach Stil direkt an der Fortschrittsanzeige.
#import "MMPlayerController.h"

@interface MMArtPlayer : MMPlayerController
@property (nonatomic, copy) NSString *styleOverride;   // fester Stil (Orbit-/Linien-Modus), sonst Einstellung
+ (NSArray *)paletteFor:(UIImage *)img;   // [Akzent, Mittelton, dunkel, Leinwand]
+ (NSString *)style;                  // @"standard", @"orbit", @"line"
+ (void)setStyle:(NSString *)style;
+ (NSArray *)styles;
+ (NSString *)nameOf:(NSString *)style;
@end
