# Splice

A heart-rate app for iPhone that reads live heart rate from a WHOOP 5.0 band over Bluetooth, with no subscription or WHOOP app. It records workouts with GPS and heart rate and uploads them to Strava automatically when you finish.

Splice is an independent project and is not affiliated with WHOOP or Strava.

## Features

- Finds and reconnects to the band automatically, and restarts the heart-rate stream if it stalls.
- Live Activity on the Lock Screen and Dynamic Island: heart rate, zone, timer and distance.
- Workouts with GPS and 1 Hz heart rate, saved every 15 seconds so a crash doesn't lose a workout.
- Automatic Strava upload as a TCX file, with time in each zone in the description. Splice retries until Strava accepts the upload.

## Layout

```text
SpliceCore/      Swift package: band protocol, zones, TCX writer, models (tested on macOS)
Splice/          iPhone app: Bluetooth, recording, Strava, UI
SpliceWidgets/   Live Activity widget extension
Shared/          Code used by both the app and the widget
Config/          Build settings; Strava keys go in Secrets.xcconfig
Scripts/         Icon generator
```

## Build

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
2. Create a Strava API application at <https://www.strava.com/settings/api> and set **Authorization Callback Domain** to `localhost`.
3. Run `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig` and fill in the Client ID and Client Secret.
4. Run `xcodegen generate` and open `Splice.xcodeproj`, or build from the command line:

   ```sh
   xcodebuild -project Splice.xcodeproj -scheme Splice -destination 'generic/platform=iOS' build
   ```

To run the core tests on a Mac (no simulator needed):

```sh
cd SpliceCore && swift test
```

## How the band is read

The band streams heart rate on its private service after it receives command `3` with payload `[1]` (`TOGGLE_REALTIME_HR`). Each 1 Hz packet carries a Unix timestamp, the bpm value, and beat-to-beat (RR) intervals. See `SpliceCore/Sources/SpliceCore/BandProtocol.swift`.
