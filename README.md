# DesktopCasino

A slot machine that lives on the macOS desktop: present on every Space, drawn beneath every
application window, animated and still clickable.

**Status: 0.1.0, early.** It works and it is pleasant to use, but the version number is honest —
expect rough edges.

## What it does

Three reels, six symbols, 98% return to player. Click SPIN, watch the drums settle, and on a
three-of-a-kind the frame turns into a travelling barber-pole marquee. Credits and bet persist;
running dry offers a free refill.

The header's pin button cycles three **placements**, persisted across launches:

| Icon | Mode | Where it sits |
| --- | --- | --- |
| hollow pin | `normal` | Ordinary window — click it and it comes forward |
| filled pin | `floating` | Above every window, always |
| layers | `widget` | **Default.** Below every window, still clickable |

Widget mode is the interesting one, and most of this README is about why it is hard — see
[Widget mode](#widget-mode-below-everything-and-still-clickable).

The chart button in the top right opens **[statistics](#statistics)** — best day, a fortnight of
daily net, and what the machine has actually paid you — in an ordinary window.

## Run

```sh
swift run                 # quick iteration
swift test                # payout table, outline geometry, credit arithmetic, and pixel
                          # snapshots of the reels, the marquee and the whole window
./Scripts/make_app.sh     # build DesktopCasino.app, then: open DesktopCasino.app

# Render the UI offscreen to a PNG — handy because capturing the window with
# screencapture needs Screen Recording permission.
swift run DesktopCasino --snapshot /tmp/casino.png

# Render every reel symbol at once, which a single spin cannot show.
swift run DesktopCasino --faces /tmp/faces.png

# Render the three-of-a-kind marquee without waiting for a 1-in-21 spin.
swift run DesktopCasino --win /tmp/win.png

# Render the stats screen over a fixed fortnight of play, which a real ledger only
# reaches after a fortnight of playing.
swift run DesktopCasino --stats /tmp/stats.png
```

Handy environment variables: `DESKTOPCASINO_MODE=normal|floating|widget` forces a placement (the
escape hatch if widget mode ever leaves the panel unreachable), `DESKTOPCASINO_DEBUG=1` traces
placement and mouse events, `DESKTOPCASINO_SPACES=member` puts widget mode back on per-Space
membership instead of joining all Spaces (see [All Spaces](#all-spaces-floater-or-member)), and
`DESKTOPCASINO_NO_SKYLIGHT=1` disables the private-API paths.

## Icon designer

A separate binary, sharing symbols and palette with the widget through `CasinoKit`:

```sh
swift run IconDesigner                 # sliders + live preview, "Render icon" writes Icon/
swift run IconDesigner --render Icon   # headless, default settings
```

The artwork is a diamond over the widget's own backdrop with the other reel symbols arranged in
rings behind it, thinning out with distance. Sliders cover the rings (count, per ring, spread,
inner gap, spacing bias, twist), irregularity (angle jitter, radius jitter, rotation), the
satellites (size, size falloff, fade falloff), the centre (diamond size, glow radius and
strength), and the frame (corner radius, seed).

Three details worth knowing:

- **Placement is radial, not random.** Satellites sit on concentric rings at even angular steps,
  with `angleJitter` and `radiusJitter` adding controlled irregularity — set both to 0 for a
  perfectly regular lattice. `ringTwist` rotates each successive ring by a fraction of one step
  so the spokes interleave instead of stacking into visible radial lines.
- **Symbol types stay balanced.** Satellites are dealt from a reshuffled deck rather than picked
  independently at random, which keeps every symbol's count within one of every other's. With
  independent picks one symbol is visibly over-represented at these small counts. `--render`
  prints the tally.
- **Every `.icns` size is rendered from scratch** rather than downscaled from the 1024, so the
  small ones keep their contrast. The preview shows 128 down to 16 for the same reason — that is
  where a busy icon falls apart.

`Render icon` writes `Icon/AppIcon.png` and `Icon/AppIcon.icns`; `make_app.sh` picks the `.icns`
up automatically if it is there.

Quit by hovering the panel and clicking ✕, or `pkill DesktopCasino`. There is no Dock tile and
no menu bar, so there is no ⌘Q.

To start it at login: System Settings → General → Login Items → add `DesktopCasino.app`.

## Releasing

```sh
./Scripts/make_dmg.sh                        # dist/DesktopCasino-<version>.dmg + .sha256
git tag v$(cat VERSION) && git push --tags   # workflow builds, tests and publishes
```

Work for a release happens on a `release/<version>` branch; `main` stays the trunk.

`VERSION` is the single source of truth: `make_app.sh` stamps it into the bundle and the workflow
refuses to publish if the tag disagrees with it. The DMG stages the app beside a symlink to
`/Applications`, so mounting it gives the usual drag-to-install.

**The app is ad-hoc signed, not notarised.** It installs fine anywhere; what breaks is the first
launch on a Mac other than the one that built it:

1. Open the DMG and drag **DesktopCasino** to Applications. This part never complains.
2. Launch it. macOS blocks it: *"Apple could not verify 'DesktopCasino' is free of malware."*
   The only buttons are Move to Trash and Done — there is no Open button.
3. **System Settings -> Privacy & Security**, scroll to the bottom, click **Open Anyway**,
   confirm, and authenticate.
4. Subsequent launches are silent.

Control-click -> Open does **not** work. Apple removed that override in macOS 15 precisely because
malware installers were telling people to use it, so any guide still recommending it is stale.

Clearing the quarantine flag before first launch skips the prompt altogether:

```sh
xattr -dr com.apple.quarantine /Applications/DesktopCasino.app
```

Notarisation would remove the friction entirely but needs a paid Developer ID. The generated
release notes carry these steps so downloaders do not have to guess.

The workflow checks the toolchain before building, because the win marquee uses an isolated
conformance (`View, @MainActor Animatable`) that needs **Swift 6.2+**. If the GitHub runner ships
something older it fails immediately with a clear message rather than an opaque compile error —
pin a newer Xcode with `sudo xcode-select -s /Applications/Xcode_<version>.app` in that case.

## The window

`DesktopPanel` is the whole trick — it is an ordinary `NSPanel`, not a WidgetKit extension,
which is why it can animate freely and update in real time with no timeline or reload budget.

### Why there is no always-behind mode

Short version: macOS has no such window, and Apple's own Stickies does not have one either.

The first version pinned the panel to `CGWindowLevelForKey(.desktopIconWindow) - 1`. It looked
right and was completely dead — no clicks, no dragging.

Tracing `NSWindow.sendEvent` at a range of levels on macOS 26.5:

| Level | Mouse events delivered |
| --- | --- |
| `-2147483602` (`desktopIconWindow + 1`) | none |
| `-2147483000` | none |
| `-20` (`backstopMenu`) | none |
| `-1` | none |
| `0` (`.normal`) | yes |
| `3` (`.floating`) | yes |
| `25` (`.statusBar`) | yes |

**macOS does not route mouse events to any window below `.normal`.** A genuinely
desktop-level window can only ever be decorative. This is not the Finder-desktop-window theory
it first looks like: raising above Finder's full-screen `.desktopIconWindow` changed nothing,
and `-1` — with nothing above it — is just as inert.

Forcing a `.normal` window to stay at the back does not bridge the gap either. The window
manager re-fronts it on click, on Space change and in Mission Control, and every correction
lands *after* a frame has painted — a blink above the active window on each click, and a
flash-on-top when switching Spaces. All of these were tried and none suppress it:

- `orderBack(nil)` deferred with `DispatchQueue.main.async` — one clearly visible frame
- the same call made synchronous inside `sendEvent` — still a frame
- an `order(_:relativeTo:)` override rewriting `.above` into `.below` — the automatic raise
  does not route through it
- `canBecomeKey = false` and `canBecomeMain = false` — does not stop the re-front either (still
  set, but for focus hygiene rather than ordering)

### What Stickies does

Apple hit the same wall and sidestepped it. Inspecting the shipped
`/System/Applications/Stickies.app` on macOS 26.5:

- no `LSUIElement`, `NSPrincipalClass = NSApplication` — an ordinary app with a Dock icon and
  menu bar, not an agent or a desktop widget
- zero `NSPanel` references in the binary; notes are plain `NSWindow`s
- the only level control is `setLevel:`, behind the **"Float on Top"** menu item found in
  `MainMenu.loctable` (alongside **"Translucent"**)

Normal, or above everything. There is no always-behind sticky note.

### So this app does the same

Stickies' two choices became three: `normal`, `floating`, and `widget`, which goes further than
Stickies can by using private API. `widget` is the default.

| Setting | Effect |
| --- | --- |
| `level = .normal`, or `.floating` when pinned | AppKit's level, which is what it consults to route mouse events. Widget mode leaves this at `.normal` and moves only the *server* level |
| z-order left to the window manager | No `orderBack` fighting, so no click blink and no Space-change flash |
| `orderBack(nil)` once at launch | Starts behind your work instead of on top of it |
| `.canJoinAllSpaces` when **floating or widget**; `normal` joins each Space through SkyLight (below) | A window that joins all Spaces belongs to no Space's z-order, so it is composited outside a Space transition and stays on screen throughout one — the reason widget mode uses it. It arrives at the *front of its level*, which is on top for `floating` (correct) and still behind everything for `widget` (level `desktopIconWindow + 1`), but would be a flash on top for `normal` |
| `.stationary` | Stays put during Mission Control / Exposé |
| `.ignoresCycle` | Kept out of ⌘-Tab and the Window menu |
| `.nonactivatingPanel` + `canBecomeKey = false` | Clicking plays the machine without pulling the app forward or stealing keyboard focus from what you were doing — better than Stickies, which activates normally |
| `acceptsFirstMouse = true` | The app is never active, so otherwise the first click is eaten as an activation click |

`DESKTOPCASINO_NO_SKYLIGHT=1` falls back to plain AppKit, dropping widget mode and all-Spaces
presence.

### Widget mode: below everything, and still clickable

AppKit couples two things the window server keeps separate — how low a window sits, and whether
it receives mouse events. Set `NSWindow.level` below `.normal` and input dies. But
`SLSSetWindowLevel` changes only the *server* level, and AppKit keeps routing events based on the
`NSWindow.level` it still believes in.

So widget mode leaves `NSWindow.level = .normal` and pushes only the server level to
`desktopIconWindow + 1`, then re-asserts the mouse event mask with `SLSSetWindowEventMask` in case
lowering the level cleared it.

| Mode | AppKit level (routes events) | Server level (compositing) |
| --- | --- | --- |
| `normal` | 0 | 0 |
| `floating` | 3 | 3 |
| `widget` | **0** | **−2147483602** |

**AppKit re-declares its level on every ordering operation**, which undoes the divergence and
raises the panel back on the first click. So the server level is re-applied inside an
`order(_:relativeTo:)` override — in the same window-server round trip rather than a frame later —
and again at both ends of a click in `sendEvent`, since the click-raise does not always route
through `order`.

Two measurement traps met along the way:

- `kCGWindowLayer` from `CGWindowListCopyWindowInfo` reports the level the *owner declared*, not
  the compositing level. In widget mode it reads 0, which says nothing about where the window
  actually composites.
- `SLSGetWindowLevel` exists but the obvious `(cid, wid, out) -> err` signature reports the wrong
  value — it returned 0 while AppKit's level was −2147483602. It is deliberately not bound.

An honestly-low `NSWindow.level` is *not* an alternative. The event mask is already permissive
down there (default `3999072222`), so the level itself is what refuses input, not the mask.
Relatedly: `SkyLight.addEventMask` ORs into the existing mask. Assigning one outright strips
everything else the window relies on.

The pin button in the header cycles `normal → floating → widget`. If widget mode ever leaves the
panel unclickable and you cannot reach the button:

```sh
defaults write dev.timfedo.DesktopCasino windowMode normal
```

or launch with `DESKTOPCASINO_MODE=normal`.

### All Spaces: floater or member

There are two ways to be on every Space, and they differ only during a Space *transition*:

- `.canJoinAllSpaces` makes the window an all-Spaces **floater**, belonging to no individual
  Space's z-order — so it is composited independently of the two Spaces sliding past each other,
  and stays on screen throughout. The price is arriving at the front of its level.
- `SLSAddWindowsToSpaces` makes it a **member** of each Space, with a z-order slot in every one.
  There is no arrival — but a window can only travel in one sliding group, so it leaves with the
  outgoing Space and is not painted into the incoming one until the transition finishes.

Widget mode used membership first, and that is exactly why the panel popped in a beat late on
every Space switch: for half a second the new desktop had no slot machine on it. It is a floater
now, and the arrival cost turns out not to apply, because the *server* level is already down at
`desktopIconWindow + 1` — the front of that level is still behind every application window.

Measured, launching the panel in each strategy and reading its index in the window server's
front-to-back on-screen list across a Space change:

| Widget strategy | Depth before | Depth after |
| --- | --- | --- |
| floater (`.canJoinAllSpaces`) | 15 of 24 | 23 of 30 |
| member (`SLSAddWindowsToSpaces`) | 16 of 30 | 23 of 30 |

Same resting depth, so the floater does not come forward. `normal` mode stays a member on
purpose: its level *is* 0, where the front of the level is on top of whatever you were working
in, and that is a flash worth avoiding. `DESKTOPCASINO_SPACES=member` puts widget mode back on
the membership path without a rebuild, should a macOS update ever start compositing floaters
above a transition regardless of level.

Floating above the transition has one consequence worth spelling out, because it cost the card
its frosted backdrop. Settled on the desktop the panel sits *below* every window, so the only
thing behind it is the wallpaper. During a transition it is above the animation instead, and the
two Spaces' windows slide behind it — so an `.ultraThinMaterial` backdrop, which samples whatever
is behind the window, picked up any bright window passing underneath and lifted the whole card
for the length of the slide. The backdrop is now opaque: `Palette.cardBottom` under
`Palette.card()`, which is how the icon has always been composited, so the two finally resolve to
the same colour instead of merely sharing a gradient. The frost only ever showed when nothing was
moving, and it cost a visible flicker on every Space switch.

`SkyLight.swift` binds its symbols by `dlsym` rather than linking, since SkyLight exists only in
the dyld shared cache and a missing symbol should degrade to "unavailable" rather than break
launch: `SLSMainConnectionID`, `SLSCopyManagedDisplaySpaces`, `SLSAddWindowsToSpaces`,
`SLSRemoveWindowsFromSpaces`, `SLSCopySpacesForWindows`, `SLSSetWindowLevel`,
`SLSSetWindowEventMask`, `SLSGetWindowEventMask`.

The pin button reaches widget mode by way of `normal`, which joins each Space by hand, so
becoming a floater hands that membership back with `SLSRemoveWindowsFromSpaces` — otherwise the
panel is a floater *and* a member, and it is the membership that decides how it travels through a
transition. Measured: with `.canJoinAllSpaces` already in force, removing the membership leaves
the window exactly where it was, at the same depth, and it survives a Space change.

Membership, where it is still used, is re-asserted on `activeSpaceDidChangeNotification`, because
Spaces can be created at any time and a brand new one will not contain the window. Only Spaces of
`type == 0` are joined — fullscreen and tiled Spaces are skipped, matching what
`.canJoinAllSpaces` does, so neither strategy changes what happens inside a fullscreen app.

Verified by reading membership back rather than by switching Space by hand: with
`canJoinAllSpaces=false`, `SLSCopySpacesForWindows` reports the window in all 11 Spaces.

Caveats: the symbol *names* are confirmed present on macOS 26.5, but their signatures come from
community reverse engineering. Tahoe is visibly mid-migration here, shipping
`SLSBridged*Operation` Objective-C wrappers beside the C entry points, so expect this to break on
an update. `DESKTOPCASINO_NO_SKYLIGHT=1` falls back to plain AppKit, where the panel simply stays
on the Space it was placed on.

Remaining limits:

- **Invisible inside a fullscreen Space.** A fullscreen app owns its Space.
- **One screen.** `.canJoinAllSpaces` covers Spaces, not displays. `moveOnScreenIfNeeded()`
  rescues the panel when its display disappears; a machine per display would mean one window
  per `NSScreen`.

### Dragging

`isMovableByWindowBackground` does not work here: `NSHostingView` consumes the `mouseDown` it
relies on. `CasinoView` instead attaches a `DragGesture` to the card's *background* — so
foreground buttons win hit-testing — and positions the window from an **absolute anchor**:
the offset between window origin and pointer is measured once at grab time, then every update
sets `origin = NSEvent.mouseLocation + offset`.

Both relative approaches drift, for the same underlying reason:

- The gesture's own `translation` is reported relative to the window, and the drag is moving
  that window, so feeding it back runs away immediately.
- Summing per-frame `NSEvent.mouseLocation` deltas runs away more slowly. Each sample is taken
  when the callback fires rather than when the event occurred, so every frame contributes a
  small error, and integration never corrects it — the panel slides out from under the pointer.

An absolute anchor is self-correcting: a late sample simply lands in the right place next
update.

## Reels

`Reel.strip` is a physical strip: each symbol occupies `weight` stops, shuffled once with a
fixed seed so the running order is stable across launches. A spin lands on a uniformly random
stop, which reproduces the intended odds the same way a mechanical reel does.

| Symbol | Stops | ×3 | ×2 |
| --- | --- | --- | --- |
| 🍒 cherry | 6 | 5× | 1× |
| 🍋 lemon | 5 | 8× | 1× |
| 🔔 bell | 4 | 12× | 1× |
| ⭐️ star | 3 | 20× | 2× |
| **7** seven (red) | 2 | 50× | 2× |
| 💎 diamond | 1 | 100× | 2× |

21 stops per reel. Measured over 3M simulated spins:

| | |
| --- | --- |
| Return to player | **98.00%** |
| Triple | 4.77% of spins |
| Pair | 47.65% of spins |
| 💎 jackpot | 1 in ~9231 spins (21³ = 9261) |

So the bank drifts down slowly rather than draining. REFILL tops it back up when you hit zero.

A three-of-a-kind swaps the reel frame for `WinMarquee`: a barber-pole of slanted gold stripes on
red, travelling around the border, with the glow breathing. `--win` renders it without waiting for
a 1-in-21 spin.

Every stripe is placed by **distance along the outline** (`RoundedRectOutline`, an analytic
arc-length parameterisation), so the pattern flows continuously through the corners. Three earlier
approaches did not, and the failures are worth recording:

- *One pattern translated across the whole frame* makes the top and bottom edges travel the same
  direction — it reads as sliding, not spinning.
- *Each edge drawn in its own rotated space* travels correctly but meets at an angle in the
  corners rather than curving round them.
- *Four-point quads per stripe* cut chords across the corner arcs; stripes are subdivided ribbons
  instead.

Two constants are bounded by the corners rather than the straights. `stripeWidth` has to be fine
enough that more than one stripe spans an 18.9pt corner arc, or each corner collapses into a solid
red block plus a solid gold block. And `cornerTaper` narrows the band through the arcs: measured,
the band is already uniform, but a curve crosses the eye obliquely and reads about 1.4x heavier at
45°, so the taper cancels an illusion rather than a geometry error.

`TimelineView(.animation)` drives stripe travel and pulse off one clock so they cannot drift.
It asks for a frame at display refresh for as long as it is mounted, so the celebration is
**time-boxed to 60 seconds** — otherwise one lucky spin leaves an idle desktop widget animating
forever, which is the one thing that turns this from free into a battery cost. It is also skipped
entirely when Reduce Motion is on.

`ReelView` conforms to `Animatable` rather than animating an `.offset`. SwiftUI hands it the
interpolated scroll position every frame, so the body can choose *which* symbols are on
screen — an offset animation could only slide a fixed set of views and would jump whenever the
strip index rolled over. Motion blur is derived from how far the reel still has to travel,
which under the ease-out curve tracks drum speed closely enough.

Each symbol is positioned by its **absolute** strip index: symbol `slot` sits at
`(position - slot)` stop-heights. Deriving the offset from the fractional part of `position`
looks equivalent and is not — the centre symbol jumps two stops backwards at every integer
crossing. Motion blur hides that while the reel is fast, so it surfaced only as the final
symbol popping into place in one frame as the reel settled. Sweeping `position` across 30
stops: 30 discontinuities under the fractional formula, 0 under the absolute one, with the
resting symbol still equal to `strip[position mod stops]` so payouts match the visuals.

## Playing

Three behaviours worth stating, because each was a deliberate call:

**A push is not a win.** Cherry, lemon and bell pairs pay `pairMultiplier: 1` — your stake back,
net zero — and that is 39% of all spins. Celebrating those with the gold border, glow and scale
bump is the textbook "loss disguised as a win", so `isWin` requires `lastWin > lastStake` and a
push gets a muted line reading `±0`.

**The payout figure is net, not gross.** A 2x pair on a 25 bet pays 50 but *gains* 25, because
the stake left the balance when the spin started. It reads `+25`. Showing gross while a push
shows `±0` would put two different units in the same field.

**Quitting mid-spin refunds the stake.** Credits are debited when a spin starts and only credited
back when it resolves ~2.3s later. Quitting inside that window used to persist the debit with no
payout, so `applicationWillTerminate` refunds an unresolved spin before saving. Relatedly, the
resolution task catches cancellation rather than using `try?` — swallowing it would resolve the
spin instantly instead of aborting it.

**The celebration is time-boxed to 60 seconds.** `TimelineView(.animation)` asks for a frame at
display refresh for as long as it is mounted, so leaving the marquee up until the next spin meant
one lucky spin left an idle desktop widget animating forever. For an always-on widget that is the
difference between free and a battery cost. It is skipped entirely when Reduce Motion is on.

## Statistics

The chart button in the header opens the ledger. It shows, in this order:

- **Best day** — the highest net any single calendar day has produced, with its date and how many
  spins it took. The headline the rest of the screen is arranged around.
- **Today, session, all time** — the same figure over three horizons. Session is per launch and
  is not persisted; "this session" means this run of the app.
- **Last 14 days** — net per day as bars either side of a zero line, gold above and red below,
  scaled to the biggest swing in view rather than a fixed ceiling.
- **Bankroll** — credits now, the best balance ever held, how many times the bank ran dry, and
  the biggest single payout with the symbol that paid it.
- **Spins** — spins, staked, paid out, return rate, win rate, push rate.
- **Streaks** — the current run, the best winning run, and the longest cold one.
- **Landings** — three-of-a-kind counts per symbol, then pairs and blanks.

Four decisions in there worth stating:

**Days are bucketed when the spin resolves, in the local calendar.** That is what "today" and
"best day" have to mean for someone reading their own history. Storing instants and bucketing at
read time would silently re-file everything the first time the machine changed time zone.

**Win rate and push rate are separate figures.** A 1x pair pays the stake back and is 36% of all
spins; folding those into a single "win rate" would report about half the spins as wins. Same
reasoning as the muted `±0` on the machine itself — see [Playing](#playing).

**Best day is the highest net, not the best day you had.** A ledger of nothing but losing days
still reports one: its least bad. The alternative is a headline that reads `—` for anyone having
a bad fortnight, which is when they are most likely to open it.

**The stored ledger decodes key by key.** Every field is read with `decodeIfPresent` and falls
back to a default, so a ledger written by an older build — missing whatever has been added since
— loads rather than throwing. Throwing is indistinguishable from "no history" and would quietly
wipe a real record on upgrade. A blob that will not decode at all is discarded for the same
reason: losing a history nobody can read beats refusing to launch.

History is capped at 180 days, oldest dropped first; lifetime totals are not capped. Resetting
clears the record and leaves the bank alone — the ledger is a diary, not currency.

### Why the stats window is an ordinary window

Everything else in this app fights AppKit to sit *below* other windows. The stats window does the
opposite: `.titled`, closable, resizable, key. The machine is a widget you leave lying on the
desktop; the ledger is something you open, read and close, and it should behave like every other
window while it is up. The titlebar is transparent and untitled so the felt runs to the top and
the traffic lights sit on it, and the window background is set to the colour the content's own
gradient starts at, because the strip behind the titlebar is drawn by the window rather than by
the content view.

Three consequences, all handled:

- **A reused window keeps its Space.** The window outlives being closed and so does its Space
  assignment, so reopening a stale one from another Space switched *back* to the first Space and
  showed it there — measured, `active` going 6 -> 5 on the click. `open()` therefore discards a
  window that is not `isOnActiveSpace` and builds a fresh one, which opens on the Space you are
  looking at. Verified by the window id changing and `active` staying put.

  **Not** `.moveToActiveSpace`, which is the obvious flag and was tried first. It fixes reopening
  and breaks something worse: it relocates the window into whichever Space you return to, and an
  *arriving* window lands behind the ones already there, so coming back to the Space left the
  stats window behind every other window on it. A/B against a build with the single line removed:
  with the flag, returning put Safari in front of it; without, it kept its slot at the front. Same
  member-versus-arrival distinction as [All Spaces](#all-spaces-floater-or-member), biting the
  other way — a window *created* on a Space is a member of it and keeps its z-order there.
- **There is no menu bar to route ⌘W.** The app is an `.accessory`, so the window would otherwise
  only close from its button. A local key monitor, installed while the window is up, closes it.
- **Activation may re-declare the panel's level.** Showing the window activates the app, and
  AppKit re-declares its own level whenever it orders a window — the same hazard the panel already
  re-pins against in `order(_:relativeTo:)`. `DesktopPanel.reassertPlacement()` covers this path
  too, one runloop turn later so it lands after AppKit's own ordering. Precautionary rather than
  observed: sampling the panel's server level and front-to-back position every 20ms for three
  seconds across an activation showed no change, and the modern `NSApp.activate()` is more
  conservative than the deprecated `activate(ignoringOtherApps:)` it replaced.

## Snapshot tests

`swift test` includes pixel snapshots of the drawing that arithmetic cannot pin. Two layers of
them:

- **Components** — the reel at rest, mid-travel and settling; the marquee at several phases, both
  full-frame and cropped hard to a corner; the seven's numeral face; the daily-net chart, with a
  gain, a loss, a day that came out level and days that were not played at all.
- **The whole window** — the assembled card in each state a player can see it in: idle, mid-spin,
  a loss, a push, a 2x pair, a triple, the jackpot, an empty balance, and a balance too small for
  the larger chips. Plus a hard crop of each corner's controls, which are 13pt across and would
  otherwise be lost in the noise of a 264x372 card.
- **The stats screen** — the whole board over a fixed fortnight of play, and the empty state a
  fresh install opens on.

References live in `Tests/CasinoKitTests/__Snapshots__/`.

```sh
SNAPSHOT_RECORD=1 swift test   # re-record after a deliberate visual change, then eyeball the diff
```

Re-record every reference a change reaches, not only the ones that failed. A small control moves
well under the tolerance on a whole-card reference, so the card keeps passing while its image
still shows the old drawing — which is how the stats glyph stayed 8pt in `window-hovered` for a
commit after it had been changed to 6.5pt. Recording writes all of them; revert the ones your
change could not have touched, rather than keeping the ones that merely still pass.

What makes them worth having rather than a liability:

- **`MarqueeFrame` takes an explicit phase and pulse.** `WinMarquee` wraps it in
  `TimelineView(.animation)`; snapshotting the animated view would differ on every run.
- **Window states are staged, not played for.** `SlotMachine.stage(landings:credits:bet:)` parks
  the machine on an exact result through the same payout table a real spin resolves against, so
  the symbols on the reels always agree with the line printed underneath — and no snapshot waits
  two and a half seconds on a die roll. Staging is a rendering concern and is *not* recorded in
  the ledger; a snapshot run must not hand anyone free credits or a fabricated best day.
- **The stats screen takes its ledger, its "today" and its calendar as arguments.** Half of that
  screen is relative to the current date, so it renders against `Ledger.sample(endingOn:)` — a
  fixed fortnight played out through the real strip and the real paytable — pinned to a fixed day
  in UTC. The same sample backs `--stats`, so the picture a human eyeballs and the picture the
  test compares can never drift apart.
- **The board is not the scroll view.** `ImageRenderer` does not lay out a `ScrollView`'s
  content — every offscreen render of the stats screen came back as an empty gradient until the
  scrolling moved up into `StatsScreen` and `StatsView` became the bare board.
- **The window renders at its own height.** The card sizes itself from its content and the panel
  follows, so the snapshots are taken with no frame at all: a stack that grew fails as a size
  mismatch, naming both heights, rather than as a wall of moved pixels.
- **Comparison counts changed pixels, not mean difference.** A mean was tried first and was
  useless — the corner taper touches a few hundred pixels out of seventy thousand, so halving it
  moved the mean far less than the tolerance and every test still passed. Counting pixels that
  move more than 10% on any channel catches a localised change while ignoring antialiasing noise.
- **Small controls get their own cropped snapshot.** On the full frame a marquee corner
  regression moves under 1% of pixels, uncomfortably close to any workable tolerance; in a 34pt
  crop the same change is unmissable. The window controls get the same treatment for the same
  reason, with a paired assertion that hovered and unhovered actually differ — otherwise the day
  hover broke, both references would be re-recorded identical and both tests would pass for ever.

Verified by perturbing the real thing: `stripeWidth` 4.2 -> 4.0 moves 2.9% of pixels against a
0.2% tolerance, and even `cornerTaper` 0.45 -> 0.40 is caught.

## Contributing

`main` is protected: changes go through a pull request, including mine.

```sh
git config core.hooksPath .githooks   # once per clone: blocks direct pushes to main
git switch -c my-change
git push -u origin my-change
gh pr create --fill
```

CI runs on every PR — build, the test suite, and a packaging smoke check that the bundle assembles with
the version stamped and the icon in place. It is a required check, so a red PR cannot merge. No
approvals are required, so you can merge your own work once CI is green.

Two layers enforce this, because one of them does not work yet:

- **`.githooks/pre-push`** refuses a push whose target is `refs/heads/main`. Works today, but it
  only binds the clone that enables it and `--no-verify` walks straight past it.
- **`Scripts/protect_main.sh`** applies a real server-side ruleset — no direct pushes, no
  force-pushes, no deletion, CI required, and no bypass for admins. GitHub does not offer branch
  protection on free *private* repositories, so it returns 403 until the repo is public. Run it
  the moment you flip visibility.

## Licence

MIT — see [LICENSE](LICENSE).

One caveat if this ever travels further than a handful of people: `Icon/AppIcon.icns` is
rasterised Apple Color Emoji, which is not licensed for redistribution. The reels are fine, since
they render from the system font at runtime — it is only the baked icon. Redrawing those symbols
as vectors would clear it.

## Layout

Three targets: a library both binaries share, and one executable each.

```
Sources/CasinoKit/            Shared, and the only part under test
  Reel.swift                  Symbols, weighted strip, seeded RNG
  Palette.swift               Colours, card backdrop, felt, SymbolFace
  SlotMachine.swift           @Observable game state, spin scheduling, payouts
  Ledger.swift                Persistent play record, day buckets, sample data
  StatsView.swift             The stats board, the daily-net chart, number formatting
  RoundedRectOutline.swift    Analytic arc-length walk of a rounded rect

Sources/DesktopCasino/        The widget
  main.swift                  NSApplication bootstrap, .accessory activation policy
  AppDelegate.swift           Panel lifetime, screen and Space changes, persistence
  DesktopPanel.swift          Placement modes, SkyLight level and Space membership
  SkyLight.swift              dlsym bindings to the private window-server API
  CasinoView.swift            SwiftUI UI, the Animatable reel, the win marquee
  StatsWindow.swift           The ordinary window the stats screen opens in
  OffscreenRender.swift       --snapshot / --faces / --win / --stats renderers

Sources/IconDesigner/         The icon tool
  main.swift                  Window bootstrap, --render headless path
  IconArtwork.swift           Ring layout and the artwork itself
  IconExport.swift            PNG and .icns writing
  DesignerView.swift          Sliders and preview

Tests/CasinoKitTests/         swift test
  PayoutTests.swift           Pins RTP 48/49 and the outcome rates exhaustively
  OutlineTests.swift          Closure, unit normals, continuity across corner seams
  SlotMachineTests.swift      Debit/refund, persistence, resting-stop invariant, ledger
  LedgerTests.swift           Day buckets, best day, streaks, pruning, tolerant decoding
  SnapshotSupport.swift       Offscreen render and tolerance-based image comparison
  SnapshotTests.swift         Reels, marquee, the seven's face, the chart, the stats board
  WindowSnapshotTests.swift   The assembled card in every state, and its controls
  __Snapshots__/              Committed reference PNGs
```

`SlotMachine` takes its `UserDefaults` by injection, so tests run against a scratch domain
instead of the real one. Note that `swift run` and the `.app` bundle write to different domains
(executable name vs. bundle identifier), so the bank does not carry between the two.
