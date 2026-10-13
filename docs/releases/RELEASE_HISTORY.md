# Release history

This history is reconstructed from the recorded Desktop delivery folder, build
metadata, checksums, and project handoff records. APKs and AABs should be
attached to GitHub Releases rather than committed to the source tree.

The public repository was initialized after these delivery milestones, so the
release assets and checksums are the authoritative version evidence; earlier
source commits were not preserved in the original workspace.

| Version | Build | Position in the project | Evidence |
| --- | ---: | --- | --- |
| 2.1.0 | 4 | First verified delivery milestone | Desktop release folder, APK/AAB checksums, 36 tests, clean analyzer |
| 2.2.0 | 5 | Shared alarm and locale transition milestone | `pubspec.yaml`, Android metadata, recorded APK rebuild |
| 2.2.5 | Internal | Polished UI and event presentation | `pubspec.yaml`, UI tests, release APK/AAB checksums, GitHub Release |
| 2.2.6 | 7 | Bulletproof sound, volume & Huawei EMUI fix | `pubspec.yaml`, unit tests, release APK/AAB checksums, GitHub Release |
| 3.0.0 | 9 | Multi-participant sectors, 4-state sync, background keepalive | `pubspec.yaml`, 57 tests, clean analyzer, GitHub Release |

## 2.1.0+4

The first verified delivery package established the usable product baseline:

- English and Arabic localization, including the church-specific `تنويه` /
  `التنويهات` wording.
- Multi-room QR/PIN joining with controller and participant roles.
- Firestore-authoritative schedules with local countdowns and offline warnings.
- Persistent round alarms and ongoing Android timer notification behavior.
- Firebase base-plan fallback path, with Cloud Functions documented as an
  optional Blaze-plan enhancement.
- Obfuscated split-ABI APKs, an App Bundle, external symbol files, and
  `SHA256SUMS.txt`.
- Verification recorded as 36 passing Flutter tests, clean `flutter analyze`,
  and successful APK/AAB builds.

## 2.2.0+5

The current release line extends that baseline rather than changing the core
room model:

- Round-boundary alarm scheduling moved into the shared active-run listener so
  controllers and participants receive the same alarm behavior.
- Schedule-key deduplication prevents repeated alarm scheduling across run
  updates.
- English/Arabic locale changes use a 500 ms app-level fade transition.
- Version metadata moved from `2.1.0+4` to `2.2.0+5`.
- Release APKs were rebuilt with split ABIs, obfuscation, external symbols,
  resource shrinking, and minimized output.

The recorded `2.2.0+5` APK and App Bundle rebuilds are verified. The current
App Bundle is 62.2 MB and was built on 2026-08-12.

## 2.2.5

This release keeps the same controller/participant architecture and focuses on
the event experience and release presentation:

- System feed entries use short summaries instead of repeating full backend
  command text.
- Round transitions are presented as a clear **Next round** state.
- The timer card now foregrounds time remaining and shows compact round
  progress.
- Widget coverage verifies the compact summaries and cooldown presentation.
- Android build metadata was incremented internally for this release.
- Obfuscated split-ABI APKs and an App Bundle were rebuilt with external symbol
  output and SHA-256 checksums.

The published `2.2.5` artifacts are the current release assets. The source
repository remains the place for code and documentation; binaries belong to the
GitHub Release.

## 2.2.6

This release ensures robust audible delivery across all Android OEM devices:

- Protected Huawei EMUI devices from auto-downgrading to vibration mode by boosting volume streams prior to ringer mode changes.
- Isolated stream volume maximization so permission restrictions on one stream do not abort others.
- Upgraded notification channels to `v4` with `Importance.max` and custom alarm audio.
- Added audible readiness detection and one-tap **Max Volume** controls in the participant UI and settings.
- Direct Do Not Disturb (DND) Access shortcut in Settings.

## 3.0.0

Major release introducing flexible sector grouping and connection resilience:

- **Multi-Participant Sectors**: Controllers create, rename (with Arabic support), and manage sectors live from a dedicated card. Participants choose from a real-time synchronized dropdown.
- **Grouped Sector Cards**: Dashboards and participant views group joined members into sector cards with participant counts.
- **4-State Sync Matrix**: Replaced fragile online/offline labels with revision sync tracking (Green: Synced+Online, Orange: Synced+Offline, Yellow: Out-of-sync+Online, Red: Out-of-sync+Offline).
- **Background Keepalive & WakeLock**: Android Foreground Service and partial WakeLock keep timer isolates running and network sockets alive during screen-off.
- **Sector-Targeted @Mentions**: Typing `@SectorName` alerts all members in that sector with priority push notifications; individual `@ParticipantName` is also supported.
- **Dynamic Settings Limits**: User-configurable max round duration, cooldown duration (up to 15 min), and step intervals.

## Difference at a glance

```text
2.1.0+4  ->  verified product baseline and first Desktop delivery
2.2.0+5  ->  shared controller alarms + duplicate-scheduling guard
              + 500 ms locale transition + refreshed release metadata/build
2.2.5    ->  shorter system summaries + clearer next-round timer state
              + compact timer card + refreshed release artifacts
2.2.6    ->  bulletproof volume enforcement + Huawei EMUI ringer protection
              + v4 notification channels + audible readiness banner
3.0.0    ->  multi-participant sectors + sector management card
              + 4-state sync matrix + background keepalive & WakeLock
              + sector-targeted @mentions + dynamic settings limits
```
