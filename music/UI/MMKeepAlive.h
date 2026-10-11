// MMKeepAlive.h — hält die App im Hintergrund wach, solange ein Offline-Download läuft und keine Musik spielt.
// iOS 6 friert Apps sonst nach ~10 Minuten ein; eine Audio-App mit laufender Wiedergabe darf weiterarbeiten.
// Dafür wird unhörbare Stille abgespielt (für den eigenen, gejailbreakten iPod gedacht – im App Store nicht erlaubt).
#import <Foundation/Foundation.h>
@interface MMKeepAlive : NSObject
+ (void)start;   // bei Bedarf (Download läuft, App im Hintergrund, genug Akku oder am Strom)
// Einstellung "Download im Hintergrund" (Standard: an)
+ (BOOL)enabled;
+ (void)setEnabled:(BOOL)on;
@end
