# Riff

**A music player for your Spotify account on the iPod touch 4 with iOS 6 – no web player, no proxy server.**

The official Spotify app dropped iOS 6 years ago. This one talks to Spotify directly from the iPod: it opens its own connection to a Spotify access point, fetches your library and playlists, downloads the encrypted audio from Spotify's CDN, decrypts it and decodes the Ogg Vorbis on the device.

## What it can do

- **Your library:** your playlists and liked songs, with covers – also as a cover mosaic for playlists without their own image.
- **Gapless playback:** the next tracks are downloaded and decrypted in advance, so there is no pause between songs.
- **Offline playlists:** download whole playlists, even ones with hundreds of tracks, and play them without Wi-Fi. Downloads queue up, resume after a restart and can keep running in the background (optional, in settings).
- **Remote controls:** headphone remote, lock screen, Bluetooth and car steering-wheel buttons.
- **iPod mode:** an optional click-wheel interface modelled on the iPod classic, in silver or black, classic or modern style.
- **Cover Flow:** turn the iPod sideways for a Cover Flow of your playlists, then of their songs.
- **Covers are kept** for 14 days after you last saw them; identical covers are stored only once.
- German and English.

## Signing in

There is no password field. You pair the iPod like a TV: the app shows a code, you confirm it on your phone or computer at spotify.com/pair, done. The login stays on the device and renews itself.

**Search** needs a free Spotify developer key (Client ID + Secret), because Spotify only allows search through its Web API. The app walks you through creating one in a few steps; without it everything except search works.

## Under the hood

- Spotify access-point protocol with the Shannon stream cipher (`music/Spot/shannon.c`), Mercury requests for metadata, audio keys over the same channel.
- Audio from the CDN is decrypted with AES-CTR and decoded with [stb_vorbis](https://github.com/nothings/stb) into an AudioQueue.
- Only one thread ever touches the access-point socket; big CDN downloads run on separate queues so playback never waits for a download.
- Spotify rotates the refresh token on every renewal, so renewals are strictly serialized – otherwise two parallel renewals would log you out.
- Modern TLS via the bundled [mbedTLS](https://github.com/Mbed-TLS/mbedtls).

## Runs on

iOS 6.1.6 · jailbroken iPod touch 4 · Spotify Premium account

## Install

Easiest via the **[Reboot App Store](https://github.com/SecondTrack/reboot)** right on the iPod. By hand: `.deb` from the [latest release](https://github.com/SecondTrack/musik/releases/latest), `dpkg -i`, then `uicache`.

Build it yourself with [Theos](https://theos.dev): `make package`.

## License

GPL-3.0 – see [LICENSE](LICENSE). Libraries under `vendor/` keep their own licenses.
Not affiliated with Spotify or Apple. Spotify is a trademark of Spotify AB, iPod is a trademark of Apple Inc.
