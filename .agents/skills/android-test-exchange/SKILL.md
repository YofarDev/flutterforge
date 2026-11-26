---
name: android-test-exchange
description: Get Google Play closed-testing testers for the user's app by doing "test for test" on r/AndroidClosedTesting with the user's Android phone over adb - read new posts, join each dev's Google Group, opt in, install, use the app ~2 min, screenshot it, and post a proof comment with the user's own tester links. Use when the user asks to find testers, get Reddit testers, do tester exchanges, or test other people's apps on r/AndroidClosedTesting.
---

# Reddit tester exchange (r/AndroidClosedTesting)

Devs need 12 testers for 14 days to publish. The deal on this sub: you install their app, post a proof comment with your own links, they install yours back.
You drive the user's phone **only through the scripts below** (adb). Never use computer-use or scrcpy; scrcpy is just the user's mirror.

## Setup (once per session)

```
S=~/.claude/skills/android-test-exchange/scripts
P="uv run python -I $S/phone.py"
F="uv run python -I $S/feed.py"
SHOTS=<your scratchpad dir>
```
Then run `$P status` (one call: wakes the phone, shows your app, the pending queue, last log lines). `LOCKED` → ask the user to unlock the phone, stop until they say so. Do not go looking for config files: `status` shows what you need.

Files live in `~/.config/android-test-exchange/` (override: `ANDROID_TEST_EXCHANGE_HOME`), never in the skill folder (it is shared via FlutterForge). First use on a machine: copy `config.example.json` there as `config.json` and fill it in. Files: `config.json` (user's app: name, one-line `pitch`, links; the comment template; reddit user), `tested.tsv` (every package already handled, incl. skips), `pending.tsv` (opted in, not installed yet), `optin_wait.tsv` (opt-in said "App not available": waiting for Play, retried automatically), `fix_links.tsv` (old comments still needing a link fix). For a different app of the user, edit `my_app` in `config.json` first.

## Rules

- **Pre-authorized, do not ask:** joining groups, opting in, installing, posting the proof comment on the post you are testing back. Keep going until the user interrupts or the target count is reached.
- **Stop and ask the user** only for: locked phone, a page asking for a password/credentials/payment, a post wanting email/DM/APK sideload, a script crashing twice in a row, `feed.py` printing `LOGGED-OUT`. Any other feed error is NOT a sign-in problem: never ask the user to sign in to Reddit unless `feed.py` printed `LOGGED-OUT`.
- **"Not available" means WAIT, never skip.** Right after joining a group, Play's opt-in page says "App not available" for 10 min to a few hours. The scripts queue those apps in `optin_wait.tsv` and every `install_all` retries them; after 48 h the script logs them itself. Never log an app as skipped for "not available" yourself, and never remove rows from `optin_wait.tsv`.
- **Never:** create accounts, sign in, accept tracking consent, rate/review on Play, reply to anyone else, comment on a post whose app you did not open, write a comment by hand (always `draft`).
- **Batch, don't interleave:** Play takes 5-30 min to show an app after opt-in, so opt in to the whole batch FIRST, then install everything Play offers, then test the installed apps one at a time. Re-run `install_all` between apps to pick up late arrivals.
- **Park, don't push:** an app `not-visible` 45+ min after opt-in (`install_all` flags it) → `log <pkg> <post> "skipped: never visible on Play"` and drop its row. A control dead after 3 attempts (Post/image button) = park that app and log it. Never idle-wait: test an installed app, or prep more, while Play propagates.
- **Proof early:** screenshot as soon as a real action is on screen; reshoot only if it's unusable.
- **Manual browsing:** read the post body BEFORE joining/opting in. Wants a Play review/rating → skip (log `skipped: wants Play review`); `feed.py` also auto-flags these posts as `skip:wants-review`.
- **Speed budget:** ~12 tool calls per app (prep, install, 4-6 in the app, proof, comment, log). Same step failed 3 times → stop that approach: skip the app (log why) or, for Reddit errors, move on and retry later. Never loop on one button.
- **Look cheaply:** use `$P look $SHOTS/l` (small image + labels with tap coords) instead of `shot`. Tap with `$P act "<label>"` or `$P act <x> <y>`: it waits for the screen to change and prints the new labels, so you usually don't need to look again. No `sleep` in your commands. Speed: each UI dump costs ~2.3 s, screen changes are detected by an on-phone hash (0.25 s), and the last dump is cached per screen hash, so `act "<label>"` / `texts` right after a command printed labels on a still screen skip the dump. Prefer label taps from the latest printed list over extra `look`s.
- **Never** send ESC (keycode 111): in a browser it leaves the page. Hide the keyboard with `$P back` only inside the Reddit app editor.

## Loop

Three phases. Batch size = target count + ~30% (some get skipped), e.g. target 10 → prep 13.

1. **Opt in to the whole batch:** `$F --prep <N>` (~25 s per app; run with a 600000 ms timeout, or in two halves for N > 15)
   Prints one line per post: `pkg  group-result  optin-result  post_url`, then the pending and waiting counts.
   - optin `tester` → queued in `pending.tsv` (with opt-in time).
   - optin `not-available...` → queued in `optin_wait.tsv` by the script (NOT skipped). Nothing to do: `install_all` retries them.
   - Nothing printed → `$F --limit 80` to see more; if 0 `todo`, run `$P retry_optins` (waiting apps), test what installs, retry the feed 10 min later.
   - Feed errors (the script already reloaded reddit.com in the phone's Chrome twice before printing one):
     | output starts with | what to do |
     |---|---|
     | `LOGGED-OUT` | the only case where you ask the user to sign in to reddit.com in Chrome on the phone (never sign in yourself) |
     | `BLOCKED` | Reddit rate limit, user still signed in. Do NOT ask the user. Test installed apps / `$P install_all`, retry `feed.py` in 10 min. Tell the user only after 3 more failures (30+ min) |
     | `FEED-ERROR` | `$P status` (locked? unplugged?), retry `feed.py` once |
   - Feed source (since 2026-11): Reddit refuses `.rss` (404) and `.json` (403), and blocks anonymous requests from the home network. `feed.py` loads the subreddit **HTML** inside the phone's Chrome (signed in as the user) over adb + DevTools, ~5 s for 40 posts. A fetch from a stale tab can get 403 while the user is signed in; a real page load clears it, so the script reloads the page itself. The Reddit app's feed is invisible to uiautomator, so don't try to read posts there.
2. **Install the batch:** `$P install_all` (one pass, ~5 s per not-visible app; Play downloads several at once). It first retries up to 5 apps from `optin_wait.tsv` (`optin-retry  tester ... -> pending.tsv` = it caught up and is installed in the same pass). Then it prints one line per pending app:
   | status | meaning |
   |---|---|
   | `installed` | ready: test it (step 3) |
   | `started` / `downloading` | will land soon; next `install_all` shows it installed |
   | `not-visible` | Play hasn't propagated the opt-in yet; retried on the next pass |
   | `play-error` | Play hiccup; retried on the next pass |
   | `incompatible` | already logged as skipped and dropped by the script |
   If nothing is installed yet: `$P install_all --wait 8` (repeats passes every ~60 s for up to 8 min; 600000 ms timeout). Otherwise start testing and run `install_all` again after each tested app.
   Single app: `$P install <pkg>` still exists (waits for the download).
   **File new installs:** after each `install_all` that installed something, `$P to_folder <pkg> <pkg>...` (all newly installed pkgs in one call, ~40 s). It adds them to a Nova app-drawer folder named after today (`21 Nov`), creating it if missing, so the user can track each session's apps. Works through Nova Settings > App drawer > Drawer groups > folder ⋮ > Select apps; idempotent. Prints `added` / `already in folder` per app and the folder's content line. `not in the Select apps list` → the app is already in another drawer folder (Nova hides those): leave it. `FAILED: no label` → app not installed yet. `--folder NAME` / `--remove` exist for fixes; `test_folder` in config.json forces a fixed folder name.
3. **Test each installed app, one at a time** (steps 3-6 per app; take pkg + post URL from `pending.tsv`).
   **Use the app ~2 min:** `$P launch <pkg>`, then `$P skip_intro` (taps through onboarding, permissions, tips; prints the screen labels).
   - Read the labels; tap with `$P act "<label>"` (add `--exact` for short words) or `$P act <x> <y>`. Only `look` + Read the image when labels are empty/unclear (games, canvas).
   - Ads/consent → close or "Manage options", never "Accept". A wall that won't dismiss in 2 taps → `$P launch <pkg>` again (fresh launches usually skip it); still stuck → `$P log <pkg> <post_url> "skipped: ad/consent wall"`, next app.
   - Do 2-3 real actions: create an item, play a round, add a task.
   - Login wall with no guest mode → `$P log <pkg> <post_url> "skipped: sign-in required"`, next app.
   - Write down ONE concrete thing: something that works well, or a bug (wrong language, broken flow, misparsed input).
4. **Proof:** `$P shot $SHOTS/<pkg>_proof.png` (full-size PNG, needed for the comment). Read it. It must show the app *in use* (not splash, not loading, not onboarding, not the Play Store). Otherwise do one more action and reshoot.
5. **Comment:**
   ```
   $P draft "<App Name>" "<one or two sentences of specific feedback>" $SHOTS/<pkg>.txt
   $P comment <post_url> $SHOTS/<pkg>.txt $SHOTS/<pkg>_proof.png --post
   ```
   - `draft` fills the user's template from `config.json`: your feedback, then "Could you test mine back?" with the app's pitch, the 3 numbered steps (join group, opt in, wait a few minutes then install), and how to send private feedback on Play. You only write the feedback; never edit the rest of the text.
   - Feedback = 2 short sentences: one concrete thing that works well, one concrete improvement or bug. Example: "The filters (nearest, least busy, open now) and the 50 km expand button are clear. The location prompt appears before any search, so asking later would feel smoother."
   - `posted+verified, links render` → go on. `TYPING-UNVERIFIED` → the composer text didn't match the draft (IME drops): `$P look`, tap just before each wrong char, DEL + retype, tap Post yourself. `GROUP LINK NOT SEEN` → verify with `$P look`, fix via `edit`. `posted? NOT verified` → `$P look`, check the comment shows with the image.
   - `FAILED: Reddit says 'Something went wrong'` → Reddit is having issues, not you. `$P act Close`, `$P act Discard`, keep the txt/png, add the post to your "retry" list, continue with the next app; retry `comment` 10+ min later. After 2 failed retries, tell the user.
   - Never post from a web browser (no image upload there, typing drops characters).
   - `REFUSED: ...` → fix the text with `draft`, never hand-edit links.
6. **Log:** `$P log <pkg> <post_url> commented` (also removes its `pending.tsv` row; same for any `skipped: ...` log).
7. `$P install_all` (picks up apps Play has published since, and retries waiting opt-ins), then the next installed app. When `pending.tsv` has no installed apps left and the target isn't reached: run `$P retry_optins` (all waiting apps, ~20 s each), then `$P install_all`, then prep another batch if still short.

Every ~5 apps: check replies with `$P open https://www.reddit.com/notifications --pkg com.reddit.frontpage` then `$P texts`. If a dev says the screenshot/link is wrong, tell the user in your report (do not reply).

## Clean up: uninstall apps after 14 days

Only when the user asks. `$P uninstall_expired` is a dry run: it lists installed apps whose first `commented` log is 14+ days old, and the apps still kept with the date each one is free. Show the user that list, then run it again with `--apply` only after they say yes. `--skipped` also removes installed apps that were only ever skipped (no promise made); `--days N` changes the delay. It only touches packages in `tested.tsv`, never the user's own app.

## Open task: fix old links

`fix_links.tsv` lists comments posted with a broken group link (`groups.google.com/u/1/g/...`). Do these when the user asks, or before the loop if they say "fix the links". For each row (`pkg  app_name  post`):
1. `$P launch <pkg>`, use it briefly, `$P shot $SHOTS/<pkg>_proof.png`, Read it (same rule as step 4).
2. `$P fix_link "<app_name>" $SHOTS/<pkg>_proof.png --save` → prints the new text, rewrites the comment with it + the new image, removes the row from `fix_links.tsv`.
3. `$P swipe_up`, `$P shot $SHOTS/check.png`, Read it: the comment shows your group link (`my_app.group` in config.json) and an image. If not, tell the user which one failed.
First row only: run without `--save` (stops in the editor), shot + Read to confirm, then `$P tap_text Save --exact` and delete that row from `fix_links.tsv` yourself.

## Report to the user (at the end, or when stopped)

Short list: apps commented (name), apps skipped (name + reason), anything a dev said, anything that failed. Nothing else.

## When stuck

Read `REFERENCE.md` in this folder (gotchas: coordinates, Play errors, Reddit app quirks, games). If the same step fails twice, skip that app and log `skipped: <why>`.
