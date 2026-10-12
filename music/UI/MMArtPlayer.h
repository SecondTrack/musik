// MMArtPlayer.h — abstrakte Player-Ansichten (Orbit, Farbfeld, Linie) statt des Standard-Players.
// Bedienung überall gleich: Tippen = Pause, Wischen links/rechts = Weiter/Zurück, runter = Schließen,
// lange drücken = Menü (Shuffle, Wiederholen, Stil). Spulen je nach Stil direkt an der Fortschrittsanzeige.
#import "MMPlayerController.h"

@interface MMArtPlayer : MMPlayerController
+ (NSString *)style;                  // @"standard", @"orbit", @"field", @"line"
+ (void)setStyle:(NSString *)style;
+ (NSArray *)styles;
+ (NSString *)nameOf:(NSString *)style;
@end
