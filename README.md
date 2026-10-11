# Musik

**Deine Spotify-Playlists auf dem iPod**

Suche, Bibliothek, Playlists und Wiedergabe mit nahtlosem Übergang dank Vorladen. Playlists lassen sich für unterwegs offline speichern, Lenkrad- und Bluetooth-Tasten im Auto funktionieren.

## Das kann die App

- Suche, Bibliothek und Playlists
- Offline-Download ganzer Playlists
- Nahtloser Übergang dank Vorladen
- Steuerung über Kopfhörer, Bluetooth und Auto

## Läuft auf

iOS 6.1.6 · gejailbreakter iPod touch

Braucht: Spotify-Konto

## Installieren

Am einfachsten über den **[Reboot Appstore](https://github.com/SecondTrack/reboot)** direkt auf dem iPod.
Von Hand: das `.deb` aus dem [neuesten Release](https://github.com/SecondTrack/musik/releases/latest) laden und mit `dpkg -i` installieren, danach `uicache`.

## Selbst bauen

Mit [Theos](https://theos.dev) (iOS-SDK mit armv7):

```sh
make package
```

## Teil von Reboot

Diese App gehört zu **Reboot** von [Second Track](https://secondtrack.de) – neue Apps für alte iPods.
Alle Apps: [SecondTrack](https://github.com/SecondTrack).

## Lizenz

GPL-3.0 – siehe [LICENSE](LICENSE). Mitgelieferte Bibliotheken unter `vendor/` behalten ihre eigenen Lizenzen.
Nicht mit Apple verbunden. iPod ist eine Marke von Apple Inc.

Nicht mit Spotify verbunden. Spotify ist eine Marke der Spotify AB. Braucht ein Spotify-Premium-Konto.
