# Span wall

Adds a **layout mode** dropdown to the Wallpapers tab, on the far right of the
content filter row, modelled after the scheme selector on the same tab.

- **Per Screen** — Ambxst's default: the wallpaper is cropped to each screen,
  and the per-screen checkbox pins individual wallpapers to individual
  monitors.
- **Fill** — the current wallpaper is scaled uniformly over the bounding box
  of all monitors and every monitor shows its slice; this is the previous
  "Span" behavior. Rotation of a monitor is handled by the compositor, no
  configuration needed.
- **Fit** — the whole wallpaper stays visible across the desktop, centered,
  with empty bars on wide desktops.
- **Stretch** — the wallpaper is distorted to cover the whole desktop exactly.
- **Center** — the wallpaper is drawn at its original size, centered on the
  whole desktop; when it is larger, it is cropped at the desktop edges.
  Needs a Qt with `Image.Pad` (6.9+) — older setups fall back to cropping.

## Behavior notes

- The spanning modes (Fill, Fit, Stretch) are whole-desktop modes: while one
  is active, per-screen pins are ignored but never deleted — switching back
  to Per Screen restores them.
- Spanning applies to static images. Videos and GIFs keep Ambxst's per-screen
  rendering.
- The lockscreen follows the layout mode: under a spanning mode its static
  wallpaper is continuous across screens. Lockscreen videos and GIFs keep
  playing per screen.
- The mode is stored in the mod's settings (Settings -> Mods -> Span wall) and
  the dropdown there stays in sync with the one in the Wallpapers tab.
- With only one monitor the dropdown hides itself and the mode is inert.
- The dropdown is intentionally Wallpapers-tab only; nothing else changes.

If you also use a mod that hands wallpaper rendering to an external daemon
(such as ambxst-skwd-wall), that daemon's surfaces draw above Ambxst's, so
spanning has no visible effect while it is active. Disable such a mod to use
a spanning layout.

## Install

Installable straight from its GitHub URL, either with the mod manager CLI:

```sh
ambxst mods install https://github.com/EliasLd/ambxst-mods/tree/main/packages/span-wall
```

or from the GUI (Settings -> Mods) by pasting the same URL, then enable the
mod and rebuild. Restart Ambxst afterwards.

## Compatibility

Tested against Ambxst 1.3.15 (commit 5d71e924212ce2c0203e7448e0b1e3db52608640)
and 1.4.1 (commit 5db90ba000713b5cb991a2abce1b766ab47fbd2b): the wallpaper,
lockscreen and Wallpapers tab sources the mod patches are identical between
these versions, so one build serves both; see `patches/span-wall.patch`.
