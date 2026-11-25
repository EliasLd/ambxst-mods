# Changelog

## 0.1.0

- The Effects section leaves the Settings tab: the sidebar entry, the
  searchable "Audio Effects" result and the panel behind them are removed.
  With every reference gone, the EasyEffects service singleton is never
  instantiated, so the shell stops probing and respawn-triggering the
  `easyeffects` CLI altogether.
