# Splice

A heart-rate app for iPhone. It turns a WHOOP 5.0 band into a standard Bluetooth heart-rate sensor, with no subscription or WHOOP app, so Strava (and any other fitness app) can record your heart rate the same way it would from a chest strap.

Splice is an independent project and is not affiliated with WHOOP or Strava.

## What it does

- One switch: **Stream heart rate**. When it's on, Splice tells the band to broadcast standard Bluetooth heart rate and keeps it that way. It finds the band, reconnects after drops or a relaunch, and restarts the stream if it stalls.
- Shows live heart rate, your current zone, and the last five minutes as a graph.
- Puts a Live Activity with heart rate and zone on the Lock Screen and in the Dynamic Island.

## Using it with Strava

1. Turn on **Stream heart rate** in Splice.
2. In Strava, tap **Record**, then the sensor icon, then **Heart Rate**, and pick your WHOOP.
3. Record activities in Strava as usual. Heart rate and zones are recorded by Strava itself.

Set the same max heart rate in Splice's settings as in Strava so the zones match.

## Layout

```text
SpliceCore/      Swift package: band protocol and zones (tested on macOS)
Splice/          iPhone app: Bluetooth client, Live Activity, screens
SpliceWidgets/   Live Activity widget extension
Shared/          Code used by both the app and the widget
Scripts/         Icon preparation script
```

## Build

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
2. Run `xcodegen generate` and open `Splice.xcodeproj`, or build from the command line:

   ```sh
   xcodebuild -project Splice.xcodeproj -scheme Splice -destination 'generic/platform=iOS' build
   ```

To run the core tests on a Mac (no simulator needed):

```sh
cd SpliceCore && swift test
```

## How the band is controlled

Commands go to the band's private service as framed packets (see `SpliceCore/Sources/SpliceCore/BandProtocol.swift`):

| Command | Payload | Effect |
| --- | --- | --- |
| `14` | `[1]` / `[0]` | Turns the standard Bluetooth heart-rate broadcast (`0x180D` / `0x2A37`) on or off. This is what Strava pairs with. |
| `3` | `[1]` / `[0]` | Starts or stops a private 1 Hz stream with bpm, beat-to-beat intervals, and a timestamp. Splice uses it for its own display. |
