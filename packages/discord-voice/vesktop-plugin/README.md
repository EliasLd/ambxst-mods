# AmbxstDiscord plugin source

Companion Vencord userplugin for the Ambxst `discord-voice` mod. This
directory is the source of truth for published builds and for local builds;
it is never composed into Ambxst itself.

User-facing install and troubleshooting steps live in the package
`README.md`; the wire protocol lives there too.

## Files

| file | role |
|---|---|
| `index.tsx` | renderer side: voice state serialization, speaking coalescing (30 ms), op execution (M4) |
| `native.ts` | Vesktop main process side (M3): unix socket transport with backoff reconnect |
| `VENCORD_REF` | the Vencord ref all published builds are pinned to |

## Local build

Injects the plugin into a checkout of Vencord at the pinned ref and builds
the four Vesktop files:

```
git clone --depth 1 --branch "$(cat VENCORD_REF)" https://github.com/Vencord/Vencord /tmp/vencord-build
rsync -a --delete ./ /tmp/vencord-build/src/userplugins/ambxst-discord/
cd /tmp/vencord-build && pnpm install --frozen-lockfile && pnpm build
```

Build outputs land in `/tmp/vencord-build/dist/`. M5 ships
`scripts/discord-plugin-build.sh` which does this without the manual steps.
