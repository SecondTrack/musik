// MMRootController.h — Container im Spotify-Look: Inhaltsbereich + Now-Playing-Leiste + Tab-Leiste.
#import <UIKit/UIKit.h>
@interface MMRootController : UIViewController
+ (instancetype)shared;
- (void)showNowPlayingTitle:(NSString *)title artist:(NSString *)artist;  // Now-Playing-Leiste füllen
// Spielt einen echten Track ab (Titel/Artist provisorisch; echte Metadaten + Cover werden nachgeladen).
- (void)playTrackId:(NSString *)trackId title:(NSString *)title artist:(NSString *)artist cover:(NSString *)cover;
// Spielt eine Liste (Dicts mit id/title/artist) ab Index idx -> Weiter/Zurück innerhalb der Liste.
- (void)playList:(NSArray *)list index:(NSInteger)idx;
- (void)playNext;
// Zufallswiedergabe: mischt die Warteschlange (aktueller Titel bleibt), aus = ursprüngliche Reihenfolge
@property (nonatomic, readonly) BOOL shuffle;
- (void)setShuffle:(BOOL)on;
// Wiederholen: 0 = aus, 1 = ganze Liste, 2 = aktueller Titel
@property (nonatomic, assign) NSInteger repeatMode;
- (void)playPrev;
- (void)openPlayer;
// Für den iPod-Modus: aktueller Titel {title,artist,cover,index,count} (nil = nichts geladen), Play/Pause, Modus an/aus
- (NSDictionary *)nowPlaying;
- (void)togglePlayPause;
- (void)setClassicMode:(BOOL)on;
+ (NSString *)nameOfUIMode:(NSString *)mode;
- (NSString *)uiMode;                        // @"spotify", @"ipod", @"orbit", @"line"
- (void)setUIMode:(NSString *)mode;
- (void)openPlayerWithStyle:(NSString *)style;   // abstrakter Player in festem Stil
// Cover Flow im Vollbild-Querformat (öffnet auch automatisch, wenn der iPod quer gedreht wird)
- (void)showCoverFlow;
// Ansicht im Inhaltsbereich öffnen/schließen (bleibt über Tab-/Now-Playing-/Download-Leiste)
- (void)pushContent:(UIViewController *)vc;
- (void)popContent;
// globale Offline-Download-Leiste (immer sichtbar wenn aktiv)
- (void)showDownloadProgress:(NSInteger)done total:(NSInteger)total;
- (void)showDownloadMessage:(NSString *)msg;
@end
