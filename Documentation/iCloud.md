# iCloud setup and verification

Pokelts uses CloudKit's private database, not the public database or a shared group account. Synchronization is for one person's devices signed into the same Apple Account.

## Signing and container

1. Open `PocketIELTS.xcodeproj` in Xcode 27.2 and choose the app target.
2. In **Signing & Capabilities**, select a paid Apple Developer team with permission to manage identifiers and iCloud containers. Automatic signing is configured in the project.
3. Enable **iCloud → CloudKit**, and register/select `iCloud.app.pocketielts.study` for the bundle identifier `app.pocketielts.study`.
4. If you use another bundle/container identifier, update `Resources/PocketIELTS.entitlements` and `StudyCloudSync.containerIdentifier` together. The existing identifier may be owned by another team.
5. Let Xcode refresh the provisioning profile, then install on two devices signed into the same Apple Account with iCloud available.

The entitlement file enables CloudKit. It does not, by itself, create a container in the Apple Developer portal or grant provisioning access.

The existing team’s signed iOS Debug build was verified with both the CloudKit container and `Development` environment entitlements. A live two-device sync has not been verified.

## Schema

The app creates a custom private record zone, `PocketIELTSStudy`. It stores one `StudyItem` record per vocabulary entry, completed result or saved paper:

| Field | CloudKit type | Purpose |
| --- | --- | --- |
| `payload` | Bytes | Versioned JSON envelope: stable key, kind, encoded item, modified date, revision and optional recording filename |
| `audio` | Asset | Optional archived `.m4a` recording |

Record IDs are deterministic hashes of the local item IDs. Sync reads paginated record-zone changes rather than querying by a custom field, so no custom query index is required. Audio is downloaded only when the local archived file is missing.

In the **development** environment, saving representative records creates the schema. Before TestFlight or App Store distribution, deploy the schema to **production** in CloudKit Console. Be sure to include a Speaking result with an audio asset so the `audio` field exists. Development and production data are separate. The Debug configuration explicitly selects `Development`; Release selects `Production` through `ICLOUD_CONTAINER_ENVIRONMENT`.

## Behavior and conflict handling

- Local study data remains in the existing app storage. A durable record-level journal tracks revisions without migrating or clearing the original data.
- Launch/foreground activation and a 30-second foreground interval trigger synchronization. Users can retry from Settings. Background push synchronization is not implemented.
- Independent records are unioned. For conflicting edits to one record, the later local timestamp wins; equal timestamps use the revision identifier as a deterministic tie-breaker. Device clocks should be set automatically.
- Remote changes are merged with local changes made during the download. Uploads use `ifServerRecordUnchanged`, so a concurrent server edit fails instead of being silently overwritten; the next sync fetches and resolves it.
- Offline or failed uploads remain in the journal. A failure never clears the local vocabulary/history.
- Signing out of iCloud pauses synchronization. Switching Apple Accounts also pauses it; the journal is bound to the first account used, preventing automatic mixing of accounts.
- There is no in-app deletion operation at present. Deletion from CloudKit Console is not an app-level delete and can be re-uploaded from the journal.
- Unfinished drafts/sessions and ChatGPT tokens are device-local. Historical plain-text entries from the earliest app version remain local; current structured practice records are synchronized.

## Two-device acceptance check

1. On iPhone A, save a word and its meaning, save a complete exercise, and finish a Writing response. Finish a Speaking attempt with an archived recording.
2. Use **Sync now** and confirm a successful status and timestamp.
3. Open iPad B, use **Sync now**, and verify vocabulary, source exercise, Writing response and recording playback.
4. Disconnect both devices. Add a different word on each, and edit the same meaning on both at different times.
5. Reconnect, sync A → B → A, and verify that both additions remain and the newer meaning converges on both devices.
6. Relaunch both apps and verify persistence. Disable sync and confirm that local practice still saves.
7. Sign out of iCloud; verify that the app retains local data and shows a useful status. Switch accounts and verify that sync pauses rather than uploading the previous account's history.

The automated suite tests merging, deterministic conflict resolution, journal persistence, recording references, account isolation policy and unsafe file-path rejection. Live provisioning, server schema and two-device audio transfer require the above account-backed check.

## Apple references

- [Configuring iCloud services](https://developer.apple.com/documentation/xcode/configuring-icloud-services)
- [Designing with CloudKit](https://developer.apple.com/icloud/cloudkit/designing/)
- [Managing iCloud containers](https://developer.apple.com/documentation/cloudkit/managing-icloud-containers-with-cloudkit-database-app)
