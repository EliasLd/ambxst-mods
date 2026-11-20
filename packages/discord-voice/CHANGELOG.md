# Changelog

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
