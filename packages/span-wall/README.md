# Span wall

Adds a **layout mode** dropdown to the Wallpapers tab, on the far right of the
content filter row, modelled after the scheme selector on the same tab.

- **Per Screen** — Ambxst's default: the wallpaper is cropped to each screen,
  and the per-screen checkbox pins individual wallpapers to individual
  monitors.
- **Span** — the current wallpaper is scaled uniformly over the bounding box
  of all monitors and every monitor shows its slice, the way Wallpaper
  Engine's "span" does it. Rotation of a monitor is handled by the compositor,
  no configuration needed.

## Behavior notes

- Span is a whole-desktop mode: while it is active, per-screen pins are
  ignored but never deleted — switching back to Per Screen restores them.
- Span applies to static images. Videos and GIFs keep Ambxst's per-screen
  rendering.
- The lockscreen follows the layout mode: under Span its static wallpaper is
  continuous across screens. Lockscreen videos and GIFs keep playing per
  screen.
- The mode is stored in the mod's settings (Settings -> Mods -> Span wall) and
  the dropdown there stays in sync with the one in the Wallpapers tab.
- With only one monitor the dropdown hides itself and the mode is inert.
- The dropdown is intentionally Wallpapers-tab only; nothing else changes.

If you also use a mod that hands wallpaper rendering to an external daemon
(such as ambxst-skwd-wall), that daemon's surfaces draw above Ambxst's, so
Span has no visible effect while it is active. Disable such a mod to use Span.

## Install

Installable straight from its GitHub URL, either with the mod manager CLI:

```sh
ambxst mods install https://github.com/EliasLd/ambxst-mods/tree/main/packages/span-wall
```

or from the GUI (Settings -> Mods) by pasting the same URL, then enable the
mod and rebuild. Restart Ambxst afterwards.

## Compatibility

Base Ambxst 1.3.15 (commit 5d71e924212ce2c0203e7448e0b1e3db52608640). The
mod patches wallpaper geometry on the desktop and the lockscreen, plus the
Wallpapers tab; see `patches/span-wall.patch`.
