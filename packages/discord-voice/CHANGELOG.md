# Changelog

## 0.1.8

- The self tile gets a mic volume bar in the same style as the other
  participants, with a microphone glyph: it drives Vesktop's own mic
  capture stream, so it changes exactly what the call hears without touching
  other apps or the device volume.

## 0.1.7

- The per-user volume slider renders on Discord's own curve (slider percent
  is the stored percent to the power 1/2.8): fill and tooltip now match what
  Vesktop's user-volume slider shows, and drags here land on the same number
  in Vesktop.

## 0.1.6

- Per-user volume drags no longer cut short after ~10ms: state pushes from
  the companion plugin rebuilt every tile through the participant Repeater;
  the tab now holds a stable id list and tiles read their data reactively.
- Same fix keeps volume reads steady while sliders are moved on Vesktop's
  own side.

## 0.1.5

- The per-user volume bar gets the bar sliders' animated wavy fill, scaled
  by the volume.
- The volume icon is drawn by the tile instead of living inside the
  slider, so the whole track is grabbable: drags starting near the icon no
  longer scroll the participant grid.

## 0.1.4

- The self controls dock into the tab's bottom margin instead of taking
  layout space above it: the second participant row is no longer cropped,
  and the grid scrolls to a stop above the dock when three or more rows
  wrap.

## 0.1.3

- The avatar photo fills its circle edge-to-edge like Discord's, instead
  of floating inside a black backing disc; the speaking ring rides the
  photo rim.
- Mute, deafen and suppressed badge icons are white instead of theme
  red, to read on the black badge like Discord's own.

## 0.1.2

- The voice bridge comes up with the shell instead of waiting for the
  first tab open or keybind press; the companion plugin reconnects
  within a couple of seconds after a shell restart.

## 0.1.1

- The participant grid always uses the full-channel four-tile layout: the
  self tile keeps its size and far-left spot whether you are alone or with
  three others.

## 0.1.0

- Initial release: a Discord voice tab in the dashboard showing the
  participants of your Vesktop voice channel (avatar, name, mic and deafen
  state, speaking glow) with a per-user local volume slider, plus self
  controls for mic mute, deafen, camera and leaving the channel. Companion
  Vencord plugin `AmbxstDiscord` streams voice state from Vesktop to the tab
  and executes every action through Discord's own stores over a local Unix
  socket; released Vesktop has no control socket a shell could write to.
