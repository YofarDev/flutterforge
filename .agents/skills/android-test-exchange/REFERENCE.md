# Reference: gotchas (read only when stuck)

## Phone / adb
- Screen 1220x2712 portrait. Screenshot scaling differs by command: `look` JPEGs ~2.7x smaller, full `shot` PNGs ~1.36x — always use the factor printed by `look`, or the `texts` coords (already physical).
- Landscape games: frame becomes 2712x1220, same scaling.
- Device pinning: phone.py auto-picks one device and caches it in `.device_serial` (in ~/.config/android-test-exchange, next to config.json); `ANDROID_SERIAL` overrides; delete the file to re-pin. An emulator appearing mid-session used to hijack plain `adb` → stale screenshots, "more than one device" errors, taps going nowhere.
- `wake` prints `NO DEVICE` when adb sees no phone (false "awake" readings before were failed shell calls).
- `wake` locks portrait; Groups and image viewers otherwise flip to landscape.
- `texts` (uiautomator) can lag on animated Flutter/Compose/game screens or show nothing for games: use `shot` + Read instead, tap by coords.
- In zsh, `"x y"` in one variable is not split: call `$P tap 610 1500` or `adb shell input tap 610 1500` with separate args.
- Swipe / hold: `adb shell input swipe x1 y1 x2 y2 ms` (same point + long ms = hold).
- Share text into an app (list/notes apps): `adb shell "am start -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT 'milk, eggs' -p <pkg>"`.
- Typing: ASCII only (`draft` cleans it). `type` turns newlines into Enter.

## Google Groups / opt-in
- "no Join button (member-or-open)" is fine: already a member or open group.
- Opt-in "App not available" right after joining = Play hasn't seen the group join yet (10 min to hours). NOT a skip: it goes to `optin_wait.tsv`, `install_all` / `retry_optins` retry it (re-joining the group too), and the script itself logs it after 48 h. 2026-11-25: apps first logged as "not available" became testers on a retry an hour later. (Truly private / email-list tests just expire after 48 h.)
- Group links in OUR comments must be `https://groups.google.com/g/<name>`. `/u/1/g/` is the user's own account index and breaks for others.

## Play Store install
- Right after opt-in: "Item not found", "Something went wrong", "Can't download" = propagation (5-15 min). Not a failure. Can exceed 30 min (Star Hop sat 40+): park in pending.tsv after 3 tries, retry at session end, never serial-sleep.
- Page exists with "not available in your country" or no Install button = geo/device locked, skip (`install` prints `incompatible`).
- "Cancel" button visible = already downloading; `install` waits for it.
- Always open Play via `market://details?id=<pkg>` with `-p com.android.vending` (the scripts do), otherwise a Xiaomi store chooser appears.

## Reddit app
- Open posts by URL with `--pkg com.reddit.frontpage` (scripts do). Tapping images in the feed opens a landscape viewer.
- Find a post fast (manual path): open `https://www.reddit.com/r/AndroidClosedTesting/search/?q=<App+Name>&restrict_sr=1&sort=new` — far more reliable than scrolling the feed and hoping to land the tap.
- Composer (2026-11 redesign): bottom bar "Join the conversation" (~254,2495) opens it; header "Add comment", Post top-right (~1116,204). Old label "Add a comment" is gone; `comment` tries all three.
- Comment image (2026-11): "Add an image" → "Photo Library" → first tile (~202,1486) → "Done". No editor "Next" step anymore. (Old flow kept as fallback in `attach_image`: thumbnail 612,598 → "Add" → "Next".)
- The composer IME drops chars when `input text` chunks arrive back-to-back (seen: leading T→I, lost "v" in "movie", stray leading comma — deterministic, same spots every run). `type_text` chunks with pauses and `comment` verifies + retries once. Manual fix: tap just left of the bad char, DEL, retype it. Cursor keys (MOVE_HOME/DPAD_RIGHT) do nothing in that editor; select-all is `ctrl+a` (`input keycombination 113 29`) and works.
- Single newlines are collapsed: the template uses blank lines.
- One image per comment. In edit mode, select-all + delete also deletes the image (so `edit`/`fix_link` re-attach one).
- Verify from the profile: `https://www.reddit.com/user/<name>/comments/` shows your comments + image thumbnails.
- Feed 403 while signed in (2026-11-25, several times): a background `fetch()` from a stale reddit tab is refused until a real page load refreshes Reddit's cookies. `feed.py` reloads `/r/<sub>/new/` in the phone's Chrome twice before failing, and reads `<shreddit-app user-logged-in>` to tell `LOGGED-OUT` (ask the user) from `BLOCKED` (rate limit: wait 10 min, don't ask).

## Skips seen before
Wear OS / watch faces, iOS-only, "send me your email", sign-in walls (Nightflare, Bajka), geo-locked (PuttPace, Payment Projections, WannaChat, whereto.cloud), email-list tests (HomeFit, Nexora), wants-a-Play-review (Grange: Horror Escape), ad-gated-forever-on-first-launch (BadCell free time 0:00).

## Good feedback examples (specific, short)
- "After choosing English, the in-world label still says 'YXA NIVA' in Swedish."
- "Shared 'can you buy 2 liters of milk' and 'can' got attached as a tag, 2 liters not parsed as quantity."
- "Opens with a browser URL bar and 'Powered by Netlify': TWA is falling back to a Custom Tab, check assetlinks.json SHA-256."
- "Swipe controls feel responsive, got 3 on first run, game over screen is clear."

## Nova Launcher folders (to_folder)
- Launcher is Nova (`com.teslacoilsw.launcher`). Drawer folders are managed in Nova Settings > App drawer > Drawer groups (`+` next to "Folders" = new folder; row ⋮ = Edit / Select apps / Delete).
- New folders: "Keep apps in main app tab" left unchecked (apps show only inside the folder).
- The Select apps list hides apps already in another drawer folder, and leaving it with "Navigate up" saves the selection.
- Swipes in that list must be slow (≥700 ms): a 300 ms swipe flings past rows. Rows at y > 2400 sit under the nav bar: nudge before tapping.
- Label for a package = launchable-activity label from `aapt dump badging` on the pulled base.apk (SDK build-tools).
