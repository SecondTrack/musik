// MMModeBase.h — Grundlage für eigene Oberflächen, die die ganze App ersetzen (Orbit, Linie).
// Hält den Menüstapel und lädt Playlists/Songs wie der iPod-Modus; Unterklassen zeichnen und steuern.
// Ebene = NSMutableDictionary {title, items, sel, loading}; Eintrag = {title, sub, cover, tid, action}.
#import <UIKit/UIKit.h>

@interface MMModeBase : UIViewController
@property (nonatomic, readonly) NSMutableArray *stack;
@property (nonatomic, readonly) UIColor *accent;        // aus dem Cover des laufenden Songs
@property (nonatomic, readonly) UIImage *nowCover;
- (NSMutableDictionary *)top;
- (NSArray *)crumbs;                                     // Titel der Ebenen ab der zweiten
- (void)push:(NSMutableDictionary *)level;
- (void)pop;
- (void)activateSelected;
- (void)click;                                           // leises Klicken wie beim Klickrad
- (void)showDownload:(NSString *)text progress:(CGFloat)progress;
- (NSString *)currentTrackId;
- (void)stop;                                             // vor dem Entfernen: Timer/Anzeige-Takt beenden
// Für Unterklassen
- (void)levelChanged;                                    // Ebene/Inhalt neu -> neu aufbauen
- (void)nowPlayingChanged;                               // Song/Cover/Akzent geändert
- (void)setDownloadText:(NSString *)text;                // Anzeige (nil = weg)
@end
