# repogithub_tom

Toms persönliches Steuerungs-Repo für Cleanup, Automatisierung und Remote-Kontrolle.

## Struktur

| Ordner | Inhalt |
|--------|--------|
| `status/` | Offene Aufgaben, Cleanup-Status |
| `scripts/` | Lokale Skripte (Mac, AppleScript, Shell) |
| `routines/` | Prompts für Claude Remote-Routinen |
| `config/` | Dokumentation der iCloud-Struktur, Farben etc. |

## Wichtige Dateien

- [`status/CLEANUP_STATUS.md`](status/CLEANUP_STATUS.md) — Alle offenen Cleanup-Aufgaben
- [`scripts/kalender_farben_v2.sh`](scripts/kalender_farben_v2.sh) — Kalender-Farben v2 setzen (lokal auf Mac)
- [`config/icloud_struktur.md`](config/icloud_struktur.md) — 6-Hüte-Struktur Dokumentation

## Remote-Kontrolle

Tägliches Briefing via Claude Remote-Routine → Gmail `f.tom.schmitz@gmail.com`

Manuell triggern: [claude.ai/code/routines](https://claude.ai/code/routines)

## Lokaler Workflow

```bash
cd ~/repogithub_tom
claude          # Claude Code lokal starten
git push        # Änderungen hochladen
```
