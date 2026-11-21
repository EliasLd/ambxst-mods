# Changelog

## 0.3.0

- The layout dropdown gains Fill, Fit, Stretch and Center for spanning:
  Fill is the previous span behavior (cover and crop), Fit never crops
  (empty side bars on wide desktops), Stretch distorts to cover exactly,
  Center draws the image at its original size, centered (cropped at the
  desktop edges when larger). Per Screen is unchanged; a stored Span
  setting migrates to Fill.

## 0.2.2

- The layout-mode dropdown no longer paints over the expanded scheme
  (accent color) list; the filter row drops below the search row's layer.
  Opening one dropdown also closes the other.

## 0.2.1

- Compatibility with Ambxst 1.4.1: the sources the mod composes against are
  unchanged between 1.3.15 and 1.4.1, so no code change was needed.

## 0.2.0

- The lockscreen follows the layout mode: under Span its static wallpaper is
  continuous across screens. Lockscreen videos and GIFs keep playing per
  screen.

## 0.1.1

- Initial release: a layout dropdown in the Wallpapers tab with two modes,
  Per Screen (Ambxst's default behavior) and Span, where the current wallpaper
  is drawn once across the whole virtual desktop and every screen shows its
  slice. Per-screen wallpaper pins are ignored while Span is active and
  restored when you switch back. Static images span; videos and GIFs keep
  Ambxst's per-screen rendering.
