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

## Run

```sh
swift run                 # quick iteration
swift test                # 22 tests: payout table, outline geometry, credit arithmetic
./Scripts/make_app.sh     # build DesktopCasino.app, then: open DesktopCasino.app

# Render the UI offscreen to a PNG — handy because capturing the window with
# screencapture needs Screen Recording permission.
swift run DesktopCasino --snapshot /tmp/casino.png

# Render every reel symbol at once, which a single spin cannot show.
swift run DesktopCasino --faces /tmp/faces.png

# Render the three-of-a-kind marquee without waiting for a 1-in-21 spin.
swift run DesktopCasino --win /tmp/win.png
```

Handy environment variables: `DESKTOPCASINO_MODE=normal|floating|widget` forces a placement (the
escape hatch if widget mode ever leaves the panel unreachable), `DESKTOPCASINO_DEBUG=1` traces
placement and mouse events, and `DESKTOPCASINO_NO_SKYLIGHT=1` disables the private-API paths.

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
| `.canJoinAllSpaces` **only when floating**; the others use SkyLight (below) | A window that joins all Spaces is not part of any Space's persistent z-order, so the window server composites it at the *front* of its level on every Space switch, and reordering afterwards is the same one-frame flash as raise-on-click. Floating, arriving on top is correct |
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

### All Spaces without the flash, via SkyLight

`.canJoinAllSpaces` is the only *public* way to be on every Space, and it is exactly what causes
the flash. The private window-server API offers the missing distinction:

- `.canJoinAllSpaces` makes the window an all-Spaces **floater**, belonging to no individual
  Space's z-order — so it is composited at the front of its level on arrival.
- `SLSAddWindowsToSpaces` makes it a **member** of each Space, with a z-order slot in every one.
  There is no arrival, so there is nothing to flash.

`SkyLight.swift` binds its symbols by `dlsym` rather than linking, since SkyLight exists only in
the dyld shared cache and a missing symbol should degrade to "unavailable" rather than break
launch: `SLSMainConnectionID`, `SLSCopyManagedDisplaySpaces`, `SLSAddWindowsToSpaces`,
`SLSCopySpacesForWindows`, `SLSSetWindowLevel`, `SLSSetWindowEventMask`, `SLSGetWindowEventMask`.

Membership is re-asserted on `activeSpaceDidChangeNotification`, because Spaces can be created at
any time and a brand new one will not contain the window. Only Spaces of `type == 0` are joined —
fullscreen and tiled Spaces are skipped, matching what `.canJoinAllSpaces` does.

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
  Palette.swift               Colours, card backdrop, SymbolFace
  SlotMachine.swift           @Observable game state, spin scheduling, payouts
  RoundedRectOutline.swift    Analytic arc-length walk of a rounded rect

Sources/DesktopCasino/        The widget
  main.swift                  NSApplication bootstrap, .accessory activation policy
  AppDelegate.swift           Panel lifetime, screen and Space changes, persistence
  DesktopPanel.swift          Placement modes, SkyLight level and Space membership
  SkyLight.swift              dlsym bindings to the private window-server API
  CasinoView.swift            SwiftUI UI, the Animatable reel, the win marquee
  Snapshot.swift              --snapshot / --faces / --win offscreen renderers

Sources/IconDesigner/         The icon tool
  main.swift                  Window bootstrap, --render headless path
  IconArtwork.swift           Ring layout and the artwork itself
  IconExport.swift            PNG and .icns writing
  DesignerView.swift          Sliders and preview

Tests/CasinoKitTests/         swift test
  PayoutTests.swift           Pins RTP 48/49 and the outcome rates exhaustively
  OutlineTests.swift          Closure, unit normals, continuity across corner seams
  SlotMachineTests.swift      Debit/refund, persistence, resting-stop invariant
```

`SlotMachine` takes its `UserDefaults` by injection, so tests run against a scratch domain
instead of the real one. Note that `swift run` and the `.app` bundle write to different domains
(executable name vs. bundle identifier), so the bank does not carry between the two.
