// MMAudio.h — spielt ein (bereits entschlüsseltes) Spotify-Ogg per AudioQueue ab.
// Dekodiert Ogg/Vorbis streamend mit stb_vorbis; iOS 6 kann Vorbis nicht nativ.
#import <Foundation/Foundation.h>

@interface MMAudio : NSObject
// ogg = komplette entschlüsselte Datei (inkl. 167-Byte-Spotify-Vorspann). Startet Wiedergabe.
+ (void)playOgg:(NSData *)ogg;
+ (void)stop;
+ (void)setPaused:(BOOL)paused;
+ (BOOL)isPlaying;
+ (double)duration;      // Sekunden
+ (double)currentTime;   // Sekunden (echte Abspielposition)
+ (void)seekTo:(double)seconds;   // an Position springen
@end
