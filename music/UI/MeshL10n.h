// MeshL10n.h — gemeinsames Lokalisierungs-Kit für alle Mesh/Resale-Apps (iOS 6, Theos)
//
// Mechanik: reines Standard-iOS — NSLocalizedString + <lang>.lproj/Localizable.strings.
//   * Der SCHLÜSSEL ist der englische Basistext.  ->  Englisch ist damit automatisch
//     der Fallback für JEDE Sprache, für die es (noch) keine Übersetzung gibt:
//     fehlt der Schlüssel in einer Tabelle, liefert iOS den Schlüssel selbst zurück = Englisch.
//   * Deutsch liegt in  de.lproj/Localizable.strings  ("English key" = "Deutscher Wert";).
//   * Englisch liegt in  en.lproj/Localizable.strings  (Identität; erlaubt spätere Copy-Änderung ohne Code).
//
// NEUE SPRACHE später hinzufügen  ->  einfach  <lang>.lproj/Localizable.strings  mit denselben
//   englischen Schlüsseln anlegen (z.B. fr.lproj). KEIN Code-Change, kein Rebuild der Logik nötig.
//
// Sprachauswahl: automatisch nach iOS-Systemsprache (Einstellungen > Allgemein > Landeseinstellungen).
//   Dafür in der Info.plist:  CFBundleDevelopmentRegion = en  (Fallback)  +  CFBundleLocalizations = (en, de).
//
// Benutzung im Code:
//   #import "MeshL10n.h"
//   label.text = L(@"Settings");                         // einfacher Text
//   label.text = LF(@"%ld of %ld downloaded", a, b);     // Text mit Formatargumenten
#import <Foundation/Foundation.h>

#ifndef MESH_L10N_H
#define MESH_L10N_H

#define L(k)        NSLocalizedString((k), nil)
#define LF(k, ...)  [NSString stringWithFormat:NSLocalizedString((k), nil), __VA_ARGS__]

#endif
