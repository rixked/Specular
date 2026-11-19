# Specular — Product & Technical Specification

> Status: approved plan for v0.1 · Last updated: 2026-11-16

## 1. Overview

Specular is a "send it to myself" app. It moves links, short notes and (later) files between a user's own devices through their **self-hosted Nextcloud**, without messengers (WhatsApp, Discord, …) as middlemen.

Everything sent is **temporary by default** and expires after 7 days. The user can **Keep** an item, which turns it into a permanent note in Nextcloud.

### Goals

- **As easy as humanly possible.** Sending is one action. No folders, tags or setup beyond logging in once.
- **Share from any app on Android** (TikTok, Instagram, YouTube, browser, …) via the system Share menu.
- **Runs on Arch Linux, Windows and Android** from one codebase.
- **No extra server.** Nextcloud (WebDAV) is the only backend; v0.1 requires zero server-side changes.
- **Extendable** through clear interfaces (item types, storage backends, change notification).
- **Feels like an experience.** Light-and-reflection visual language, without ever slowing the user down.
- **Updates itself** from the public GitHub releases, so no app store is needed (§3.6).

### Non-goals (for now)

- Sharing with other people. Specular is single-user, multi-device.
- Rich note editing (folders, tags, formatting toolbar).
- iOS / macOS (possible later, since Flutter supports them).
- Downloading the actual video behind a TikTok link. The link is enough.

## 2. Core concepts

| Concept | Meaning |
|---|---|
| **Item** | One thing that was sent: a link, a text snippet, or (v0.2+) an image or file. |
| **Inbox** | The single feed of all unkept items, newest first, identical on every device. |
| **Keep** | Turns an item into a permanent Markdown note in `/Notes/Specular/`. Kept items are no longer subject to expiry. |
| **Kept** | A separate view next to the inbox listing everything kept, i.e. every note in `/Notes/Specular/`. |
| **Expiry** | Unkept items are deleted 7 days after creation (configurable later). |
| **Device** | An installation of Specular. It has a random device ID and a human-readable name ("Arch PC", "Pixel"). |

## 3. User flows

### 3.1 First launch / login

1. The user enters their Nextcloud URL (for example `https://cloud.example.com`).
2. They click **Log in**. The app starts **Nextcloud Login Flow v2**:
   - `POST {server}/index.php/login/v2` returns `login` (a URL) and `poll` (`token`, `endpoint`).
   - The app opens `login` in the system browser, where the user approves.
   - The app polls `poll.endpoint` with `token` until it receives `server`, `loginName` and `appPassword`.
3. The credentials are stored in OS secure storage. The user never types or copies a password.
4. The app creates `/Specular/` on first use if it doesn't exist.

The user can revoke access at any time in Nextcloud → Settings → Security.

### 3.2 Sending

- **Android:** Share from any app → **Specular** → a brief "Sent" confirmation appears (~1 s). The main app UI does **not** open.
- **Android, in app:** a text field at the bottom of the inbox.
- **Desktop:** a text field at the bottom of the window, **Ctrl+V** anywhere in the window, or drag and drop.
- **Desktop tray:** the tray icon opens a compact popup window. "Send clipboard" is a tray menu action.
- Links are detected automatically. A message containing only a URL becomes a `link` item; anything else becomes `text`.
- **Offline:** outgoing items are queued locally and uploaded once the device is back online. They are shown as "pending" in the UI.

### 3.3 Receiving

- New items appear at the top of the inbox with the "glint" animation (see §9).
- **Desktop:** a system notification. Clicking it opens the link, or shows the item for text.
- **Android:** a notification when new items are found by a background check.
- **Tapping an item:** links open in the default browser; text is shown in full with a Copy action.
- **Long content is never cut off for good:** a collapsed card shows one line ending in "…"; every card can be expanded to show its full text (and a link's full URL) and collapsed again.

### 3.4 Item actions

| Action | Effect |
|---|---|
| Open | Link → browser. Text → detail view. |
| Copy | Copies the URL or text to the clipboard. |
| Expand / Collapse | Shows the full text in place, or folds it back to one line. |
| Keep | Creates a note in `/Notes/Specular/` (see §5.3), then moves the item from the inbox to the Kept view. |
| Delete | One tap on the card's trash icon, or swipe the card sideways. The item disappears at once and "Deleted · Undo" shows for ~4 s; only then is it removed from the inbox on all devices. |

### 3.4.1 Kept view

- The app has two views, **Inbox** and **Kept**, switched at the top.
- Kept lists every note in `/Notes/Specular/`, newest first, so it is the same on every device and also shows notes kept before this device was set up. No separate index is stored: the folder is the source of truth.
- Kept cards offer Open, Copy, Expand / Collapse and Delete. Delete works like in the inbox (trash icon or swipe, "Deleted · Undo" for ~4 s) and then deletes the note from `/Notes/Specular/`; Nextcloud keeps it in its trash bin. Editing kept notes happens in the Nextcloud Notes app.
- Kept notes are separated from the user's other notes: in the Notes app they appear as their own category, **Specular**.

### 3.5 Expiry

On every sync, a device deletes inbox items whose **server-side** creation time (`getlastmodified` from WebDAV, not the device clock) is older than 7 days. Deleting an already-deleted item (HTTP 404) counts as success.

### 3.6 Updating the app

The repository (`github.com/rixked/Specular`) is public, and every release is published as a **GitHub Release**. The app updates itself from there.

- **Checking:** on every app start (without delaying it), and every 24 hours while the app keeps running, the app requests `GET https://api.github.com/repos/rixked/Specular/releases/latest`. Drafts and pre-releases are ignored. Settings also has a manual **Check for updates** button.
- **Opt-out:** the automatic check is **on by default** and can be switched off in Settings. The manual check always works.
- **Privacy:** the request is anonymous. It sends no device ID, no Nextcloud URL and no other user data. The User-Agent is `Specular/<version>`.
- **Notifying:** when a newer version exists, a small, dismissible banner shows "Update available · v0.3.0" with the release notes. It never blocks the app and never interrupts sending.
- **Installing:** nothing is ever installed without the user's tap. What happens depends on the platform:

| Platform | Update behavior |
|---|---|
| Android | Downloads the release APK, verifies its SHA-256, and hands it to the system installer. The user allows "Install unknown apps" for Specular once. Android itself refuses an APK signed with a different key. |
| Windows | Downloads the release installer, verifies its SHA-256, starts it and quits the app. The installer replaces the old version. |
| Linux | **Notify only**, with a link to the release page. The app is usually installed by a package manager (AUR), so it must not overwrite those files. The update is done with `pacman`/`yay`. |

#### Versions and release assets

- Release tags are `vX.Y.Z` and match `version` in `pubspec.yaml`. Versions are compared as semantic versions, so `v0.10.0` is newer than `v0.9.0`.
- Each release carries these assets, with fixed names so the app can find them:
  - `specular-X.Y.Z-android.apk`
  - `specular-X.Y.Z-windows-setup.exe`
  - `specular-X.Y.Z-linux-x64.tar.gz`
  - `SHA256SUMS`, which lists the checksums of all the files above
- A download whose checksum doesn't match `SHA256SUMS` is deleted and never installed.

#### Release pipeline

- A GitHub Actions workflow runs when a `v*` tag is pushed. It builds all three platforms (`windows-latest` for Windows), signs the APK, writes `SHA256SUMS`, and publishes the GitHub Release.
- **Android signing key:** the release keystore lives only in GitHub Actions secrets and in an offline backup, never in the repository. It must never change. With a new key, Android rejects updates, and users would have to uninstall the app and log in again.


## 4. Platforms & tech stack

**Flutter (Dart)**, with one codebase targeting Linux, Windows and Android.

### Why Flutter

- It produces native apps on all three target platforms from one codebase.
- It has mature support for being an **Android share target**, which is the #1 feature.
- iOS and macOS can be added later without a rewrite.

### Known trade-offs

- Dart is a less common language.
- Binaries are larger (~20–40 MB).
- Desktop tray and notification plugins are less polished than their mobile counterparts.
- **Windows builds must be produced on Windows** (Flutter can't cross-compile from Linux), or in CI with a Windows runner such as GitHub Actions.

### Alternatives considered and rejected

| Option | Reason rejected |
|---|---|
| Python desktop + Kotlin Android | Two codebases, so double the work and double the bugs. |
| Tauri (Rust + web UI) | Android support is still young; the share target needs extra plugins. |
| Kotlin Multiplatform / Compose | Excellent on Android, but less mature on Linux desktop. |
| PWA / web app | Weak tray and notification support on desktop; Nextcloud blocks cross-origin browser requests (CORS) without server changes. |

### Application ID

`de.rixk.specular` on all platforms (Android `applicationId` and `namespace`, Linux `APPLICATION_ID`). It must not change once the app is installed anywhere, because Android treats a different ID as a different app.

### Suggested packages

Verify maintenance status and current versions on pub.dev before adding.

| Concern | Candidates |
|---|---|
| HTTP / WebDAV | `http` or `dio`, plus `xml` for parsing PROPFIND responses |
| Android share target | `receive_sharing_intent` or `share_handler` |
| Secure credential storage | `flutter_secure_storage` (libsecret on Linux, Credential Manager on Windows, Keystore on Android) |
| Local cache / offline queue | `drift` (SQLite) |
| Android background checks | `workmanager` |
| Notifications | `flutter_local_notifications` (+ `local_notifier` on desktop if needed) |
| Tray & window (desktop) | `tray_manager`, `window_manager` |
| Opening links | `url_launcher` |
| State management | `riverpod` |
| App updates | `package_info_plus` (current version), `crypto` (SHA-256), `pub_semver` (version comparison), and a small platform channel or `open_filex` for handing the APK to the Android installer |

## 5. Nextcloud storage layout

All paths are relative to the user's WebDAV root: `{server}/remote.php/dav/files/{loginName}/`.

```
/Specular/
  inbox/            one JSON file per unkept item
    <itemId>.json
  files/            attachments (v0.2+)
    <itemId>/<originalFileName>
  devices/          one JSON file per device (name, platform, last seen)
    <deviceId>.json
/Notes/
  Specular/         kept items as Markdown; the Notes app shows this as the
                    category "Specular", apart from the user's other notes
```

### 5.1 Key design rule: items are immutable

Devices only **create** and **delete** inbox files; they never edit an existing one. No two devices ever write the same file, so sync conflicts cannot occur by design.

### 5.2 Item file format (`/Specular/inbox/<itemId>.json`)

```json
{
  "schema": 1,
  "id": "20261116T103512Z-a1b2c3-7f9e2d",
  "type": "link",
  "content": "https://www.tiktok.com/@user/video/123",
  "title": null,
  "createdAt": "2026-11-16T10:35:12Z",
  "sourceDevice": "a1b2c3",
  "attachment": null
}
```

- **`id`:** `<UTC timestamp>-<deviceId>-<random>`. It is sortable by time and unique without coordination.
- **`type`:** `link` | `text` in v0.1. `image` | `file` come in v0.2. Unknown types must be shown as a generic item, not crash the app, so the format stays forward-compatible.
- **`schema`:** the format version. Readers must ignore unknown fields.
- **`attachment`** (v0.2+): `{ "path": "files/<itemId>/<name>", "mime": "...", "size": 1234 }`.

### 5.3 Kept note format (`/Notes/Specular/<title>.md`)

- **Title:** a link uses its page title if available, otherwise its domain plus date; text uses its first line (truncated to ~60 characters). Characters invalid in file names are stripped. On a name clash, append ` (2)`, ` (3)`, ….
- **Body:** the content, plus a footer line: `Sent from <device name> · <date>`.
- **Nextcloud Notes app compatibility:** the Notes app lists files in its notes folder (default `Notes`) and treats subfolders as categories, so `/Notes/Specular/` shows up as the category "Specular". Its file suffix setting should be `.md`.
- Attachments of kept items (v0.2+) are stored next to the note and linked relatively. The exact layout will be decided in v0.2.

## 6. Sync

- **Change detection:** `PROPFIND` (Depth 1) on `/Specular/inbox/`. The folder's ETag is compared first; the listing is only processed if it changed.
- **Desktop:** checks every ~15 s while running, and immediately on window focus.
- **Android:** checks immediately when the app opens or resumes; otherwise a `workmanager` background task runs about every 15 minutes (the OS minimum).
  - Consequence: phone → PC is near-instant, while PC → phone is delayed while the app is closed. This is accepted for v0.1.
- **Local cache:** the inbox is mirrored in a local SQLite database, so the UI is instant and works offline.
- **Outgoing queue:** items are written to the local DB first with status `pending`, then uploaded (`PUT`), then marked `synced`. Failed uploads retry with backoff.
- **Future:** instant updates via Nextcloud **`notify_push`**. The user self-hosts, so this is possible, but it requires Redis, a background service and a reverse-proxy rule on the server. It sits behind the `ChangeNotifier` interface (§7) so it can be added without a rewrite.

## 7. Architecture

The core logic is independent of the UI and platform, so it can be tested without a device.

```
lib/
  core/
    models/           Item, Device, ItemType (pure Dart, no Flutter imports)
    sync/             SyncEngine: polling, diffing, outgoing queue, expiry
    item_types/       ItemTypeRegistry + one handler per type
  backends/
    storage_backend.dart        abstract interface
    nextcloud/                  WebDAV implementation + Login Flow v2
  notifiers/
    change_notifier.dart        abstract: "something changed, sync now"
    polling_notifier.dart       v0.1
    updates/          version parsing, release selection, checksum check
  platform/
    share_intent/               Android share target
    tray/                       desktop tray and popup
    notifications/
    updater/                    per-platform download and install (§3.6)
  data/
    local_db/                   drift schema, cache and queue
  ui/
    theme/                      colors, glass surfaces, motion tokens
    inbox/
    item_detail/
    login/
    settings/
  main.dart
```

### Extension points

1. **`ItemTypeHandler`:** each type declares how to detect it, how to render it, which actions it offers and how to convert it to a note. New types (an image gallery, a code snippet, "download video") plug into the registry without touching the core.
2. **`StorageBackend`:** list, put, get, delete and move. Nextcloud WebDAV is the first implementation; others (another WebDAV server, LAN transfer, S3) can be added later.
3. **`ChangeNotifier`:** polling now, `notify_push` later.

## 8. Security

- **HTTPS is required.** A self-signed certificate can be allowed explicitly per server, by pinning its fingerprint after the user confirms. It is never accepted silently.
- App passwords live only in OS secure storage, never in plain files or logs.
- No telemetry and no third-party services. User data flows only between the devices and the user's Nextcloud.
- **The one exception is the update check** (§3.6). It is an anonymous request to the GitHub Releases API that carries no user data, and it can be switched off. Update downloads use HTTPS and are verified against `SHA256SUMS` before installing. On Android, the OS also enforces the same signing key.

## 9. Design vision: "light on a reflective surface"

The name defines the visual language: specular highlights, the way light catches glass.

**Chosen direction: Soft Glass** (mockups: "Specular Visual Directions" canvas, artboards "A · Soft Glass" and "A · Soft Glass · Kept").

- **Look:** a dark, deep background (near-black with a slight blue tint, `#0A0E16`), one soft light source in the top-left corner, frosted-glass item cards (rounded ~20 px, translucent white fill, hairline border, thin top highlight) and **one** spectral accent (default sky blue `#7DD3FC`). Type: Inter.
- **Readability first:** text on any card, including kept ones, meets WCAG AA contrast. Translucent cards over a colored edge get an opaque dark underlay so the edge never shows through the text.
- **Sending:** the item leaves as a streak of light, with a light haptic tick on Android. The confirmation reads "Sent" with a check mark in the accent color; no star or sparkle icon.
- **Receiving:** the new item slides in and a glint sweeps across its surface.
- **Kept items:** a thin, permanent prism-colored edge, shown in the Kept view.
- **Aging:** unkept items gradually lose their sheen over the 7 days, so age is visible without reading numbers.
- **Living light:** highlights shift subtly with device tilt on Android (gyroscope) and follow the mouse on desktop. This can be switched off.

### Rules

- Every animation is **under 300 ms** and never blocks input.
- The OS "reduce motion" setting is respected, and all effects can be disabled.
- Speed beats spectacle. The experience is seasoning, never a delay.


## 10. Roadmap

### v0.1: core loop

- Login via Login Flow v2; secure credential storage.
- Send and receive `link` and `text` items.
- Inbox with Open, Copy, Expand / Collapse, Keep and Delete.
- Keep → Markdown note in `/Notes/Specular/`; Kept view.
- Soft Glass UI (§9).
- 7-day expiry.
- Android share target with the "Sent" confirmation.
- Polling sync: desktop ~15 s; Android on open plus background.
- Local cache and offline outgoing queue.
- Builds for Arch Linux, Windows and Android.
- Release pipeline on GitHub Actions: signed APK, Windows installer (Inno Setup, per-user), Linux tarball, `SHA256SUMS` (§3.6). Moved up from v0.2 so test devices update in place.
- In-app updates: update check, banner, and download and install on Android and Windows (§3.6).

### v0.2: files & polish

- `image` and `file` items, drag and drop on desktop.
- Notifications on all platforms.
- Tray icon and popup on desktop.
- Full motion design from §9.

### Later

- Instant sync via `notify_push`.
- Optional video download for links (for example via yt-dlp on desktop).
- Clipboard sync.
- Configurable expiry; light theme.
- iOS / macOS.
- Packaging: AUR package.

## 11. v0.1 acceptance criteria

- [ ] A fresh install can log in to a Nextcloud server using only its URL and the browser approval.
- [ ] Sharing a TikTok link from Android shows "Sent" and the link appears on the Linux desktop within ~20 s.
- [ ] Text typed on desktop appears on Android when the app is opened.
- [ ] Keep creates a readable `.md` note in `/Notes/Specular/` that shows up in the Nextcloud Notes app under the category "Specular", and in the app's Kept view.
- [ ] Any item's full text can be read by expanding its card.
- [ ] Items older than 7 days disappear from all devices.
- [ ] Sending while offline queues the item, and it uploads automatically when the device reconnects.
- [ ] No credentials appear in logs or plain-text files.
- [ ] Core sync logic is covered by unit tests against a fake `StorageBackend`.

## 12. Development environment (Arch Linux)

- **Flutter SDK:** from the AUR (`flutter`), or via `fvm` for pinned versions.
- **Linux desktop build dependencies:** `clang cmake ninja gtk3 libsecret libayatana-appindicator`
- **Android:** the Android SDK (via Android Studio or the command-line tools) and a phone with USB debugging enabled.
- **Windows builds:** on a Windows machine, or in CI (for example GitHub Actions with a `windows-latest` runner).
- **Check the setup:** run `flutter doctor` and resolve everything it reports.

## 13. Open decisions

- **License** for the repository.
