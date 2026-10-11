#import <UIKit/UIKit.h>
// Gemeinsamer Cover-Cache: RAM (NSCache) + Platte (/var/mobile/.spotcache/img).
// Verhindert, dass dasselbe Cover auf jedem Screen neu aus dem Netz geladen wird.
@interface MMCovers : NSObject
+ (NSString *)bestURL:(id)images;                                // wählt ein scharfes (mittleres) Cover statt des kleinsten
+ (UIImage *)cached:(NSString *)url;                              // sofort aus RAM, sonst nil
+ (void)load:(NSString *)url into:(UIImageView *)iv;             // RAM->Platte->Netz, setzt Bild auf Main
+ (void)load:(NSString *)url completion:(void(^)(UIImage *img))done;
+ (void)prefetch:(NSString *)url;
+ (BOOL)onDisk:(NSString *)url;                                  // liegt das Cover schon auf der Platte?
// Cover aller Playlists + Lieblingssongs nach und nach auf die Platte holen (ohne Dopplungen)
+ (void)precacheLibrary;
// Playlist ohne eigenes Bild: 2x2-Mosaik aus den ersten Album-Covern (wie die Spotify-App), gemerkt auf der Platte.
// done(url) mit einer Bild-URL für load:, oder nil wenn keine Titel/Cover da sind.
+ (void)playlistCover:(NSString *)playlistId completion:(void(^)(NSString *url))done;                                // Cover schonend (seriell) auf die Platte holen (Offline)
@end
