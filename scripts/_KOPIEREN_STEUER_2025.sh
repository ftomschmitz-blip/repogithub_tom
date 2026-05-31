#!/bin/bash
# =====================================================================
# _KOPIEREN_STEUER_2025.sh
# ---------------------------------------------------------------------
# Erstellt am: 2026-05-15
# Aufgabe: Sortiert alle steuerrelevanten Dateien aus 2025 in eine
#          klare Ordnerstruktur unter
#            ~/iCloud Drive/Finanzen/Steuer 2025/_FÜR_STEUERBERATER/
# Sicherheit:
#   - Originaldateien werden NICHT verschoben/verändert (nur cp)
#   - Skript ist idempotent (kann mehrfach laufen)
#   - Volles Aktions-Log in _AKTIONS_LOG.csv
#   - Eingebautes Rollback: ./SCRIPT --rollback
#
# Nutzung in Terminal.app:
#   bash "/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/_KOPIEREN_STEUER_2025.sh"
#
# Optionen:
#   --dry-run    Nur zeigen, was passieren würde, nicht ausführen
#   --rollback   Den Zielordner _FÜR_STEUERBERATER in den Papierkorb verschieben
#   --help       Diese Hilfe
# =====================================================================

set -u  # NICHT set -e — wir wollen bei einzelnen Fehlern weitermachen
LC_ALL=de_DE.UTF-8

# === Konfiguration =====================================
ZIEL_BASIS="/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Finanzen privat/Finanzen/Steuer 2025/_FÜR_STEUERBERATER"
ICLOUD_ROOT="/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs"
LOG="$ZIEL_BASIS/_AKTIONS_LOG.csv"
DRY_RUN=0

# === Argumente =========================================
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --rollback) ACTION="rollback" ;;
    --help|-h)
      sed -n '2,25p' "$0"
      exit 0
      ;;
  esac
done

ACTION="${ACTION:-kopieren}"

# === Hilfsfunktionen ===================================
log() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
err() { printf 'FEHLER: %s\n' "$*" >&2; }

# Versucht, eine iCloud-Stub-Datei lokal verfügbar zu machen.
# Auf macOS triggert ein Lesezugriff den iCloud-Download.
trigger_download() {
  local src="$1"
  # Erstmal versuchen, die Datei zu öffnen — das stößt iCloud an
  /bin/cat "$src" > /dev/null 2>&1 || true
  # Geduldig warten bis Datei nicht mehr 0 Bytes ist (max 30s)
  local i=0
  while [[ ! -s "$src" && $i -lt 30 ]]; do
    sleep 1
    /bin/cat "$src" > /dev/null 2>&1 || true
    i=$((i+1))
  done
}

# === Rollback ==========================================
if [[ "$ACTION" == "rollback" ]]; then
  if [[ ! -d "$ZIEL_BASIS" ]]; then
    log "Zielordner existiert nicht — nichts zu tun."
    exit 0
  fi
  log "Verschiebe $ZIEL_BASIS in den Papierkorb ..."
  if [[ "$ZIEL_BASIS" != *"_FÜR_STEUERBERATER"* ]]; then
    err "Sicherheits-Check fehlgeschlagen — Pfad sieht nicht wie der erwartete Zielordner aus. Abbruch."
    exit 1
  fi
  /usr/bin/osascript -e "tell application \"Finder\" to delete POSIX file \"$ZIEL_BASIS\"" > /dev/null \
    && log "OK — Zielordner ist im Papierkorb." \
    || err "osascript hat nicht funktioniert. Bitte den Ordner manuell in den Papierkorb ziehen."
  exit 0
fi

# === Vorbereitung ======================================
log "============================================="
log "Steuerunterlagen 2025 sortieren für Czerny/Pereira"
log "Datum: $(date '+%Y-%m-%d %H:%M')"
log "Modus: $([[ $DRY_RUN -eq 1 ]] && echo 'DRY RUN (nur Anzeige)' || echo 'live')"
log "============================================="

# Zielstruktur anlegen
if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$ZIEL_BASIS"
  for sub in \
    "00_Steuerberater-Korrespondenz" \
    "01_Privat/Einkommen" \
    "01_Privat/Versicherungen" \
    "01_Privat/Vorsorge" \
    "01_Privat/Spenden" \
    "01_Privat/Kinder" \
    "01_Privat/Kapitalerträge" \
    "01_Privat/außergewöhnliche-Belastungen" \
    "01_Privat/Sonstiges-Privat" \
    "02_Praxis-Bellheim/Einnahmen" \
    "02_Praxis-Bellheim/Personalkosten" \
    "02_Praxis-Bellheim/Praxiskosten" \
    "02_Praxis-Bellheim/Anschaffungen-GwG" \
    "02_Praxis-Bellheim/Fortbildung-CME" \
    "02_Praxis-Bellheim/Abos-Software" \
    "02_Praxis-Bellheim/Reisekosten" \
    "02_Praxis-Bellheim/BWA-EÜR" \
    "03_Firma-Investments" \
    "04_SuedpfalzDOCs" \
    "99_Unklar-bitte-prüfen" \
    "99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung" \
  ; do
    mkdir -p "$ZIEL_BASIS/$sub"
  done
  # Log-Header
  printf 'quelle\tziel\tstatus\tbegruendung\n' > "$LOG"
fi

# === Quelldaten (eingebettet als Tab-CSV) ==============
# Format: QUELLE \t ZIEL_UNTERORDNER \t BEGRÜNDUNG

# === Hauptschleife =====================================
total=0; ok=0; fail=0; skip=0; nicht_da=0

while IFS=$'\t' read -r SRC DST_SUB GRUND; do
  [[ -z "$SRC" ]] && continue
  total=$((total+1))

  if [[ ! -f "$SRC" ]]; then
    # Quelle existiert nicht (vermutlich vom User schon verschoben)
    nicht_da=$((nicht_da+1))
    printf '%s\t%s\tQUELLE_FEHLT\t%s\n' "$SRC" "" "$GRUND" >> "$LOG"
    continue
  fi

  # Wenn Datei 0 Bytes hat → iCloud-Stub → Download triggern
  if [[ ! -s "$SRC" ]]; then
    if [[ $DRY_RUN -eq 0 ]]; then
      trigger_download "$SRC"
    fi
  fi

  basename=$(basename "$SRC")
  dst_dir="$ZIEL_BASIS/$DST_SUB"
  dst="$dst_dir/$basename"

  # Bei Namenskonflikt: parent-Ordner-Hinweis anhängen
  if [[ -e "$dst" ]]; then
    src_parent=$(basename "$(dirname "$SRC")")
    stem="${basename%.*}"
    ext="${basename##*.}"
    if [[ "$stem" == "$basename" ]]; then
      dst="$dst_dir/${basename} (aus $src_parent)"
    else
      dst="$dst_dir/${stem} (aus $src_parent).${ext}"
    fi
    # Falls auch das schon da ist → noch nicht idempotent für gleiche Quelle, daher skippen
    if [[ -e "$dst" ]]; then
      # Falls Zieldatei identisch zur Quelle (nach Größe): überspringen (idempotent)
      src_size=$(stat -f%z "$SRC" 2>/dev/null || stat -c%s "$SRC" 2>/dev/null)
      dst_size=$(stat -f%z "$dst" 2>/dev/null || stat -c%s "$dst" 2>/dev/null)
      if [[ "$src_size" == "$dst_size" && "$src_size" -gt 0 ]]; then
        skip=$((skip+1))
        printf '%s\t%s\tSCHON_DA\t%s\n' "$SRC" "$dst" "$GRUND" >> "$LOG"
        continue
      fi
    fi
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY: $SRC  →  $dst"
    ok=$((ok+1))
    continue
  fi

  if /bin/cp -p "$SRC" "$dst" 2>/dev/null; then
    ok=$((ok+1))
    printf '%s\t%s\tOK\t%s\n' "$SRC" "$dst" "$GRUND" >> "$LOG"
  else
    # Retry nach kurzem Warten — Stub könnte noch nicht fertig sein
    sleep 2
    if /bin/cp -p "$SRC" "$dst" 2>/dev/null; then
      ok=$((ok+1))
      printf '%s\t%s\tOK_RETRY\t%s\n' "$SRC" "$dst" "$GRUND" >> "$LOG"
    else
      fail=$((fail+1))
      printf '%s\t%s\tFEHLER\t%s\n' "$SRC" "$dst" "$GRUND" >> "$LOG"
    fi
  fi
done < <(grep -v '^#' <<'QUELLEN_END'
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Auto/E Auto Ladevorgänge/invoice_1754047393000.pdf	01_Privat/Sonstiges-Privat	Pfad: Privat/Auto
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Auto/E Auto Ladevorgänge/invoice_1756677599000.pdf	01_Privat/Sonstiges-Privat	Pfad: Privat/Auto
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Auto/E Auto Ladevorgänge/invoice_1759269599000.pdf	01_Privat/Sonstiges-Privat	Pfad: Privat/Auto
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Familie/Kinder/Nico/41f82472-37df-4a45-8d2b-8357def53fc5.JPG	01_Privat/Kinder	Pfad: Privat/Kinder
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Finanzen privat/Finanzen/HEK/IMG_1555.jpg	01_Privat/Kapitalerträge	Pfad: Privat/Finanzen
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Finanzen privat/Finanzen/Steuer 2023/Reisekosten fuer Steuer 23 .xlsx	02_Praxis-Bellheim/Reisekosten	Reisekosten / Flug / Hotel / Umzug Praxis (Match: 'reisekosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2023_Matz & Jung Gutschrift W LA 1. OG bis Penthouse.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_14_MA_Penthouse_Schmitz.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_Axa Versicherung.pdf	01_Privat/Versicherungen	Privatversicherung (Match: 'axa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_G&C Hausmeister + Hausreinigung.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_Grundsteuer.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_HZA 14 Schmitz.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_Haushahn Wartung Aufzug.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_K&C Wartung Brandschutztür.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_Matz & Jung Lüfter Bäder Tausch.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_Matz & Jung Umstellung Heizbetrieb.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_Matz & Jung W GT Penthouse.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_Matz & Jung W KA Penthouse.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_Matz & Jung W LA 1.OG bis Penthouse.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_Matz & Jung Wartung Druckerhöhung.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_Müll Wohnungen.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_Pfalzwerke Allgemeinstrom.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_Pfalzwerke WP.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_Sanncompact RWM Prüfung Wohnungen.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_Sanncompact Rechnungen Wohnungen.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_Schmitt Schornsteinfeger.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_Süd Müll Plastik Praxen und Whg.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /2024_VG Bellheim Wasser.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /Nebenkosten Wohnung 4 Bellheim 2024_2025-11-19_100254.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /Nebenkosten_Teampraxis_Bellheim2024_1864.jpeg	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Bellheim Wohnung/Nebenkosten 2024  etc. /image001.jpg	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Mietwohnung Großfischlingen/12-5351510-59_Erinnerung Rückgabe BU VN_2025-07-11_a7cefdfd0.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'großfischlingen')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/00 Privat/Wohnen/Mietwohnung Großfischlingen/51-1661119-43.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'großfischlingen')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Auswertungen/TESt-tomedoExport-2025_03_18_16_44_39.xlsx	02_Praxis-Bellheim/Abos-Software	Software / Abo (Match: 'tomedo')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Auswertungen/Z01510119500_01.07.2025_09.03.CON.pdf	02_Praxis-Bellheim/Einnahmen	Pfad: Praxis-Auswertungen
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /11 2025 Mastercard/5584xxxxxxxx0023_Abrechnung_vom_2025-12-01_Schmitz_Thomas.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Auszuge IGELKonto/Monatslisten_Kontoauszuege_12_2023_-_04_2025_Konto_Nr_1700277849.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Auszuge IGELKonto/Monatslisten_Kontoauszuege_12_2023_-_04_2025_Konto_Nr_1700277849_Monatsliste_12-2023.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Auszuge IGELKonto/Monatslisten_Kontoauszuege_12_2023_-_04_2025_Konto_Nr_1700277849_Monatslisten_01_01_2024_-_31_12_2024.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Auszuge IGELKonto/Monatslisten_Kontoauszuege_12_2023_-_04_2025_Konto_Nr_1700277849_Monatslisten_01_01_2025_-_30_04_2025.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Auszüge 24 /Konto_1700274010-Auszug_2024_0008.PDF	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Auszüge 24 /Konto_1700274010-Auszug_2024_0009.PDF	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Auszüge 24 /Konto_1700274010-Auszug_2024_0010.PDF	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Auszüge 24 /Konto_1700274010-Auszug_2024_0011.PDF	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Auszüge 24 /Konto_1700274010-Auszug_2024_0012.PDF	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Auszüge 25/Konto_1700274010-Auszug_2025_0001.PDF	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Auszüge 25/Konto_1700274010-Auszug_2025_0003.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Auszüge 25/Konto_1700274010-Auszug_2025_0005.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Auszüge 25/Konto_1700274010-Auszug_2025_0006.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Auszüge 25/Konto_1700277849-Auszug_2025_0009.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Darlehenskonto/20250410-6770157276-umsatz.xlsx	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Darlehenskonto/S_20250820_131151_Jahresauszuege_2023_und_2024_-_Darlehen_6770157276/Jahresauszuege_2023_und_2024_-_Darlehen_6770157276.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Darlehenskonto/S_20250820_131151_Jahresauszuege_2023_und_2024_-_Darlehen_6770157276/Jahresauszuege_2023_und_2024_-_Darlehen_6770157276_6770157276_2023.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Darlehenskonto/S_20250820_131151_Jahresauszuege_2023_und_2024_-_Darlehen_6770157276/Jahresauszuege_2023_und_2024_-_Darlehen_6770157276_6770157276_2024.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Darlehenskonto/_DL 6770157276 Mittelstandskredit.xlsx	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Darlehenskontoauszuege/Jahresauszuege_2023_und_2024_-_Darlehen_6770157276.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Darlehenskontoauszuege/Jahresauszuege_2023_und_2024_-_Darlehen_6770157276_6770157276_2023.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Darlehenskontoauszuege/Jahresauszuege_2023_und_2024_-_Darlehen_6770157276_6770157276_2024.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Konten Auswertungen/01 24 - 05 25 Umsätze-2.xlsx	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Tageskonto/20250820-1700290107-umsatz.xls	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Versicherungskammer Bayern /Ihr_Dokument_von_der_Versicherungskammer_Bayern 2.PDF	01_Privat/Versicherungen	Privatversicherung (Match: 'versicherungskammer bayern')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/ Sparkasse Südpfalz /Versicherungskammer Bayern /Ihr_Dokument_von_der_Versicherungskammer_Bayern.PDF	01_Privat/Versicherungen	Privatversicherung (Match: 'versicherungskammer bayern')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/5584xxxxxxxx0023_Abrechnung_vom_2025-12-01_Schmitz_Thomas-2.PDF	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/AAA KI analysedaten EBM etc./EBM0124-1125_tomedoExport-2025_11_19_16_15_11.csv	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'ebm')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/AAA KI analysedaten EBM etc./EBM0124-1125_tomedoExport-2025_11_19_16_15_11.xlsx	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'ebm')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/AAA KI analysedaten EBM etc./EBM_Analyse_2025_Charts.png.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'ebm')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/AAA KI analysedaten EBM etc./ICD Codes ab 01.24 bis 19 11 25_tomedoExp2025_11_19_16_09_02.csv	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'ebm')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/AIW/Praxis-Curriculum_Checkbox_KWBW_HAEV-2.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Abrechnung /Abrechnungssuchlauf_Hausarztpraxis_RLP_Checkliste.xlsx	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Abrechnung /Honorarbescheide/2024/Honorarbescheid Quartal_3_2024.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Abrechnung /Honorarbescheide/2024/Honorarbescheid für Quartal 4 2024.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Abrechnung /Honorarbescheide/2025/Honorarbescheid  Q 2_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Abrechnung /Honorarbescheide/2025/Honorarbescheid Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Abrechnung /KV Abrechnung 01 2025/P010818140_Honorarbescheid für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Abrechnung /KV Abrechnung 01 2025/P010826377_Sonderauswertung zum Honorarbescheid_ Anlage 2d je GOP für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Abrechnung /KV Abrechnung 01 2025/P010826400_Sonderauswertung zum Honorarbescheid_ Anlage 2f je LANR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Abrechnung /KV Abrechnung 01 2025/P010827166_Sonderauswertung zum Honorarbescheid_ Anlage 2g je LANR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Abrechnung /KV Abrechnung 01 2025/P010852956_Sonderauswertung zum Honorarbescheid_ Anlage 6b je BSNR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Abrechnung /KV Abrechnung 01 2025/P010852966_Sonderauswertung zum Honorarbescheid_ Anlage 6c je BSNR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Abrechnung /KV Abrechnung 01 2025/P010852976_Sonderauswertung zum Honorarbescheid_ Anlage 6d je BSNR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Abrechnung /KV Abrechnung 01 2025/P010852986_Sonderauswertung zum Honorarbescheid_ Anlage 6f je BSNR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Abrechnung /KV Abrechnung 01 2025/P010855332_Sonderauswertung zum Honorarbescheid_ Anlage 6g je BSNR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Abrechnung /KV Abrechnung 01 2025/P010869823_Praxischeck für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'praxischeck')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Abrechnung /tomedoExport-2025_11_16_14_33_48.xlsx	02_Praxis-Bellheim/Abos-Software	Software / Abo (Match: 'tomedo')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Anträge WBA KVRLP/Praxis-Curriculum_Checkbox_KWBW_HAEV-2.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Auswertungen KV /Auszahlungen KV RLP seit Januar 24 .xlsx	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/BWA Czerny/2024/BWA 2024_vorläufig _2025.pdf	02_Praxis-Bellheim/BWA-EÜR	BWA / EÜR / Buchhaltung / Praxisvertrag (Match: 'bwa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/BWA Czerny/2024/BWA Q4 24 Czerny/FIBU_KER_49998_17025_2024-01-01_Q4.pdf	02_Praxis-Bellheim/BWA-EÜR	BWA / EÜR / Buchhaltung / Praxisvertrag (Match: 'bwa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/BWA Czerny/2024/BWA Q4 24 Czerny/FIBU_NACHRICHT_49998_17025_2024-01-01_Q4.pdf	02_Praxis-Bellheim/BWA-EÜR	BWA / EÜR / Buchhaltung / Praxisvertrag (Match: 'bwa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/BWA Czerny/2024/BWA Q4 24 Czerny/FIBU_WKER_49998_17025_2024-01-01_Q4.pdf	02_Praxis-Bellheim/BWA-EÜR	BWA / EÜR / Buchhaltung / Praxisvertrag (Match: 'bwa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/BWA Czerny/269233 - STA BvFA Zuteilung Steuernummer (GuE, LSt, USt, Gewinnermittlung) 2024.pdf	02_Praxis-Bellheim/BWA-EÜR	BWA / EÜR / Buchhaltung / Praxisvertrag (Match: 'bwa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/BWA Czerny/BWA 03 25 /FIBU_KER_49998_17025_2025-01-01_Q3.pdf	02_Praxis-Bellheim/BWA-EÜR	BWA / EÜR / Buchhaltung / Praxisvertrag (Match: 'bwa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/BWA Czerny/BWA 03 25 /FIBU_NACHRICHT_49998_17025_2025-01-01_Q3.pdf	02_Praxis-Bellheim/BWA-EÜR	BWA / EÜR / Buchhaltung / Praxisvertrag (Match: 'bwa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/BWA Czerny/BWA 03 25 /FIBU_VJV_49998_17025_2025-01-01_Q3.pdf	02_Praxis-Bellheim/BWA-EÜR	BWA / EÜR / Buchhaltung / Praxisvertrag (Match: 'bwa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/BWA Czerny/BWA 03 25 /FIBU_WKER_49998_17025_2025-01-01_Q3.pdf	02_Praxis-Bellheim/BWA-EÜR	BWA / EÜR / Buchhaltung / Praxisvertrag (Match: 'bwa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/BWA Czerny/BWA 03 25 /FIBU_WVJV_49998_17025_2025-01-01_Q3.pdf	02_Praxis-Bellheim/BWA-EÜR	BWA / EÜR / Buchhaltung / Praxisvertrag (Match: 'bwa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/BWA Czerny/BWA Q4 24 Czerny/FIBU_KER_49998_17025_2024-01-01_Q4.pdf	02_Praxis-Bellheim/BWA-EÜR	BWA / EÜR / Buchhaltung / Praxisvertrag (Match: 'bwa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/BWA Czerny/BWA Q4 24 Czerny/FIBU_NACHRICHT_49998_17025_2024-01-01_Q4.pdf	02_Praxis-Bellheim/BWA-EÜR	BWA / EÜR / Buchhaltung / Praxisvertrag (Match: 'bwa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/BWA Czerny/BWA Q4 24 Czerny/FIBU_WKER_49998_17025_2024-01-01_Q4.pdf	02_Praxis-Bellheim/BWA-EÜR	BWA / EÜR / Buchhaltung / Praxisvertrag (Match: 'bwa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/BWA Czerny/Q2/BWA Q2 2024 .pdf	02_Praxis-Bellheim/BWA-EÜR	BWA / EÜR / Buchhaltung / Praxisvertrag (Match: 'bwa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/BWA Czerny/Q2/Wertenachweis zur BWA Q2 2024.pdf	02_Praxis-Bellheim/BWA-EÜR	BWA / EÜR / Buchhaltung / Praxisvertrag (Match: 'bwa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/BWA Czerny/Steuernummer BAG.pdf	02_Praxis-Bellheim/BWA-EÜR	BWA / EÜR / Buchhaltung / Praxisvertrag (Match: 'bwa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/IGEL Leistungen u.a./Flyer IGeL Angebote.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Neu SMCB 2025/2_Schmitz_Thomas_28122025.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Neu SMCB 2025/542c2b88-2279-4d57-9ea5-bf7e3ff41c70.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Neu SMCB 2025/Antragsdokument_S40350-2 2.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Neu SMCB 2025/Antragsdokument_S40350-2.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Neu SMCB 2025/Antragsdokument_S40350-3.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Neu SMCB 2025/Fehlermeldung D Trust.jpg	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Neu SMCB 2025/SMC Antrag Neu 2025 Antragsdokument_S40350.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Personal/Lohnkosten Übersicht /02 2025/lops_202502_0049998_17025_00000-2.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Personal/Lohnkosten Übersicht /03 25/März_2025.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Personal/Lohnkosten Übersicht /20250327-1700274010-umsatz.numbers	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Personal/Lohnkosten Übersicht /lojo_202502_0049998_17025_00000-3.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Personal/Personalübersicht.xlsx	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Personal/September_2025.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Praxis-Curriculum_Checkbox_KWBW_HAEV-2.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Presse/rlp2502_030.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Rechnungen Cortrium/Druckansicht.pdf	02_Praxis-Bellheim/Anschaffungen-GwG	Praxis-Anschaffung / Medizingerät (Match: 'cortrium')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Rechnungen Cortrium/Re Cortium .pdf	02_Praxis-Bellheim/Anschaffungen-GwG	Praxis-Anschaffung / Medizingerät (Match: 'cortrium')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/S_20250820_131151_Jahresauszuege_2023_und_2024_-_Darlehen_6770157276/Jahresauszuege_2023_und_2024_-_Darlehen_6770157276.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/S_20250820_131151_Jahresauszuege_2023_und_2024_-_Darlehen_6770157276/Jahresauszuege_2023_und_2024_-_Darlehen_6770157276_6770157276_2023.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/S_20250820_131151_Jahresauszuege_2023_und_2024_-_Darlehen_6770157276/Jahresauszuege_2023_und_2024_-_Darlehen_6770157276_6770157276_2024.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Sparkasse SÜW/Kreditkarte /S_20250823_144829_Postfach_-_Sammeldownload/Kreditkartenabrechnung.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Sparkasse SÜW/Kreditkarte /S_20250823_144829_Postfach_-_Sammeldownload/Kreditkartenabrechnung_Thomas_Schmitz.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Sparkasse SÜW/Kreditkarte /Thomas_Schmitz.PDF	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Spickzettel-christophhilft/2023-05-10-VorsorgePlus-Infos.pdf	01_Privat/Vorsorge	Vorsorge / Rürup / Ärzteversorgung (Match: 'vorsorgeplus')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Spickzettel-christophhilft/2025-03-25-KV-Früherkennungsplan.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Spickzettel-christophhilft/2025-03-29-Christoph Terminplanung und Wirtschaftlichkeit.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Spickzettel-christophhilft/2025-10-16-Bestätigung-Kostenübernahme.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Spickzettel-christophhilft/2025-10-17-Abrechnung EBM.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'abrechnung ebm')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Telematik SMCB etc./Neu SMCB 2025/SMC Antrag Neu 2025 Antragsdokument_S40350.pdf	02_Praxis-Bellheim/Praxiskosten	Pfad: Teampraxis (Default Praxiskosten)
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Verträge/BAG Vertrag komprimiert .pdf	02_Praxis-Bellheim/BWA-EÜR	BWA / EÜR / Buchhaltung / Praxisvertrag (Match: 'bag vertrag')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Vorleistungen Tom/Girokonto_5427015267_Kontoauszug_20231203.pdf	01_Privat/Kapitalerträge	Kapitalerträge / Depot / Bank (Match: 'kontoauszug')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/Bellheim Teampraxis/Vorleistungen Tom/Girokonto_5427015267_Kontoauszug_20240104.pdf	01_Privat/Kapitalerträge	Kapitalerträge / Depot / Bank (Match: 'kontoauszug')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /166465720021942274_2530_Weissler_Christiane_20250122204230136.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /2530_Weißler_Christiane_20250122204144428.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /2530_Weißler_Christiane_20250122204209139.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /2530_Weißler_Christiane_20250122204221034.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /2530_Weißler_Christiane_20250122204221402.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /2530_Weißler_Christiane_20250122204227454.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /2530_Weißler_Christiane_20250122204227588.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172819268.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172819445.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172819548.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172819661.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172819773.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172819875.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172819986.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172820100.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172820214.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172820325.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172820472.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172820586.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172820698.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172820814.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172820922.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172821029.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172821162.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172821270.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172821376.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172821497.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172821613.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/10 Praxis Bellheim/SONOCOACH Fortbildung/Meine Bilder /Tempel/1660_Tempel_Dieter_20250130172821725.US.dcm.0.jpg	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'sonocoach')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/20 Berufliches & CME/Berufliches/CME Zertifkate/2025/certificate-regress-in-der-praxis-67628959f755d4fd9502ad38.pdf	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'cme')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/30 Firma & Investments/Smartlaunch Lazy Investors/10 super wichtige Regeln bei der Gründung.pdf	03_Firma-Investments	GmbH-Beteiligung (Match: 'smartlaunch')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/30 Firma & Investments/Smartlaunch Lazy Investors/Mit diesen Eigenschaften wirst Du erfolgreich (1).pdf	03_Firma-Investments	GmbH-Beteiligung (Match: 'smartlaunch')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/12-5351510-59_Mietkautionsversicherung_Anfrage_vom_2025-02-27_d5212efc0.pdf	01_Privat/Versicherungen	Privatversicherung (Match: 'mietkaution')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/12-5351510-59_Mietkautionsversicherung_Bürgschaftsurkunde_vom_2019-05-28_8f5e91f40.pdf	01_Privat/Versicherungen	Privatversicherung (Match: 'mietkaution')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/12-5351510-59_Mietkautionsversicherung_Versicherungsschein_vom_2019-05-28_ba44b2c43.pdf	01_Privat/Versicherungen	Privatversicherung (Match: 'versicherungsschein')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/170299157679964160_5101195000P010631530.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/200105_Praxiskaufvertrag_Hebgen_rein.pdf	02_Praxis-Bellheim/Personalkosten	Personal / Anstellung Praxis (Match: 'hebgen')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/200105_Praxiskaufvertrag_Hebgen_überarb.pdf	02_Praxis-Bellheim/Personalkosten	Personal / Anstellung Praxis (Match: 'hebgen')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/2024  Schmitz  Winter.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'schmitz  winter')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/20240929-Beitragsinformation-25737848002.pdf	01_Privat/Versicherungen	Privatversicherung (Match: 'beitragsinformation')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/2024_10_Rechnung_7670715763_FN_5630680873.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/2025 11 20 Hetzelstift vorläufiger Entlassungsbericht.pdf	01_Privat/außergewöhnliche-Belastungen	Außergewöhnliche Belastungen / Krankheitskosten (Match: 'hetzelstift')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/2025-10-29_Honoraranalyse_Leydecker_Schmitz.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honoraranalyse')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/2025360061 Rechnung Schmitz Privat Februar.pdf	01_Privat/außergewöhnliche-Belastungen	Außergewöhnliche Belastungen / Krankheitskosten (Match: 'rechnung schmitz privat')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/2025360076 Rechnung Schmitz Privat März.pdf	01_Privat/außergewöhnliche-Belastungen	Außergewöhnliche Belastungen / Krankheitskosten (Match: 'rechnung schmitz privat')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/2025360126 Rechnung Schmitz Privat April.pdf	01_Privat/außergewöhnliche-Belastungen	Außergewöhnliche Belastungen / Krankheitskosten (Match: 'rechnung schmitz privat')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/2025360154 Rechnung Schmitz Privat Mai.pdf	01_Privat/außergewöhnliche-Belastungen	Außergewöhnliche Belastungen / Krankheitskosten (Match: 'rechnung schmitz privat')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/2025360206 Rechnung Schmitz Privat Juli.pdf	01_Privat/außergewöhnliche-Belastungen	Außergewöhnliche Belastungen / Krankheitskosten (Match: 'rechnung schmitz privat')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/2025360229 Rechnung Schmitz Privat August.pdf	01_Privat/außergewöhnliche-Belastungen	Außergewöhnliche Belastungen / Krankheitskosten (Match: 'rechnung schmitz privat')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/2025360256 Rechnung Schmitz Privat September.pdf	01_Privat/außergewöhnliche-Belastungen	Außergewöhnliche Belastungen / Krankheitskosten (Match: 'rechnung schmitz privat')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/2025360281 Rechnung Schmitz Privat Oktober.pdf	01_Privat/außergewöhnliche-Belastungen	Außergewöhnliche Belastungen / Krankheitskosten (Match: 'rechnung schmitz privat')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/2025_08rechnung_5630680873.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/230105_Anstellungsvertrag Dr. Hebgen_final.pdf	02_Praxis-Bellheim/Personalkosten	Personal / Anstellung Praxis (Match: 'hebgen')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/230105_Zusatzvereinbarung_Dr. Hebgen.pdf	02_Praxis-Bellheim/Personalkosten	Personal / Anstellung Praxis (Match: 'hebgen')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/2KMAFS6566857bd908a16ce25d740dbe3.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/33920_AR18877.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/40-677991543_Flight-Booking-Details.pdf	02_Praxis-Bellheim/Reisekosten	Reisekosten / Flug / Hotel / Umzug Praxis (Match: 'flight-booking')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/AXA Krankenversicherung AG Information 28.02.2023.pdf	01_Privat/Versicherungen	Privatversicherung (Match: 'axa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Antrag_Beschaeftigung_Entlastungsassistenz_Sicherstellungsassistenz.pdf	02_Praxis-Bellheim/Personalkosten	Personal / Anstellung Praxis (Match: 'entlastungsassistenz')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/April_2025 2.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Archiv/P010818140_Honorarbescheid für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Archiv/P010826377_Sonderauswertung zum Honorarbescheid_ Anlage 2d je GOP für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Archiv/P010826400_Sonderauswertung zum Honorarbescheid_ Anlage 2f je LANR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Archiv/P010827166_Sonderauswertung zum Honorarbescheid_ Anlage 2g je LANR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Archiv/P010852956_Sonderauswertung zum Honorarbescheid_ Anlage 6b je BSNR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Archiv/P010852966_Sonderauswertung zum Honorarbescheid_ Anlage 6c je BSNR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Archiv/P010852976_Sonderauswertung zum Honorarbescheid_ Anlage 6d je BSNR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Archiv/P010852986_Sonderauswertung zum Honorarbescheid_ Anlage 6f je BSNR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Archiv/P010855332_Sonderauswertung zum Honorarbescheid_ Anlage 6g je BSNR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Archiv/P010869823_Praxischeck für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'praxischeck')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Arztbrief Uni HD.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Auto-Abo_AGB_2024.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'auto-abo')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/BMWIX /BMW Ladehistorie Juli 2025.xlsx	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'ladehistorie')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Bayerische Aerzteversorgung _Anfrage_2025-04-05_143852.pdf	01_Privat/Vorsorge	Vorsorge / Rürup / Ärzteversorgung (Match: 'aerzteversorgung')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/ChronQ1_nicht Q2-2025_07_03_16_20_11.csv	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Concordia Versicherungs-Gesellschaft aG Information 10.04.25.pdf	01_Privat/Versicherungen	Privatversicherung (Match: 'concordia')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Czerny & Collegen PartG mbB.pdf	00_Steuerberater-Korrespondenz	Korrespondenz Steuerberater (Match: 'czerny')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Denis Winter NK 2024.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'denis winter')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Depotauszug.pdf	01_Privat/Kapitalerträge	Kapitalerträge / Depot / Bank (Match: 'depot')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Dr. Franz Thomas Schmitz 05.11.25.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/EBM Praxis/ebm_analysis_comprehensive.png	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'ebm')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/EBM komplett bis Q25_tomedoExport-2025_07_03_16_13_14.csv	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'ebm')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/EBM_einzeln_komplett bis Q25_tomedoExport-2025_07_03_16_13_14.csv	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'ebm')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/EINTRITT-2025-XYGBY-1-pdf.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Erträgnisaufstellung_20230307.pdf	01_Privat/Kapitalerträge	Kapitalerträge / Depot / Bank (Match: 'erträgnis')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Erträgnisaufstellung_20240305.pdf	01_Privat/Kapitalerträge	Kapitalerträge / Depot / Bank (Match: 'erträgnis')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Erträgnisaufstellung_20250314.pdf	01_Privat/Kapitalerträge	Kapitalerträge / Depot / Bank (Match: 'erträgnis')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Gescannt_20251120-0937.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/HE000010494762_Geschäftsbrief_2025-12-06.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Heiratsurkunde 20.06.2025.pdf	01_Privat/Einkommen	Privat-Einkommen / Rente / Anstellung / Familienstand (Match: 'heiratsurkunde')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/IMG_1223.heic	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/INV_BDE01703981.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/INV_BDE01883686.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Ihr_Dokument_von_der_Versicherungskammer_Bayern-2.PDF	01_Privat/Versicherungen	Privatversicherung (Match: 'versicherungskammer')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Ihr_Dokument_von_der_Versicherungskammer_Bayern.PDF	01_Privat/Versicherungen	Privatversicherung (Match: 'versicherungskammer')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Ihre_Unterlagen_vom_04_04_2025_08_30_Rahmenvereinbarung_ueber_die_Teilnahme_am_Online-Banking_Telefon-Banking.pdf	01_Privat/Kapitalerträge	Kapitalerträge / Depot / Bank (Match: 'rahmenvereinbarung')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Impfkosten_Verordnungen_der_Arznei-_und_Verbandmittel_20244_510119500_VPG212.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'impfkosten_verordnungen')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Invoice-52CFE1AA-2171.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Invoice-53CFA98A-153781.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Invoice-53CFA98A-189893.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Invoice-53CFA98A-225813.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Invoice-9200FF8A-0001.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Invoice-9200FF8A-0002.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Invoice-LHA-TEI1-2025-00004143.pdf	02_Praxis-Bellheim/Reisekosten	Reisekosten / Flug / Hotel / Umzug Praxis (Match: 'invoice-lha')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Invoice-STRP-17784.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Jahressteuerbescheinigung_20230307.pdf	01_Privat/Kapitalerträge	Kapitalerträge / Depot / Bank (Match: 'jahressteuerbescheinigung')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Jahressteuerbescheinigung_20240305.pdf	01_Privat/Kapitalerträge	Kapitalerträge / Depot / Bank (Match: 'jahressteuerbescheinigung')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Jahressteuerbescheinigung_20250314.pdf	01_Privat/Kapitalerträge	Kapitalerträge / Depot / Bank (Match: 'jahressteuerbescheinigung')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/KI Alfima/Depotauszug.pdf	01_Privat/Kapitalerträge	Kapitalerträge / Depot / Bank (Match: 'depot')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/KI Alfima/Workbook_Tag1.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/KI Alfima/Workbook_Tag2.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/KV Abrechnung 01 2025/P010818140_Honorarbescheid für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/KV Abrechnung 01 2025/P010826377_Sonderauswertung zum Honorarbescheid_ Anlage 2d je GOP für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/KV Abrechnung 01 2025/P010826400_Sonderauswertung zum Honorarbescheid_ Anlage 2f je LANR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/KV Abrechnung 01 2025/P010827166_Sonderauswertung zum Honorarbescheid_ Anlage 2g je LANR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/KV Abrechnung 01 2025/P010852956_Sonderauswertung zum Honorarbescheid_ Anlage 6b je BSNR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/KV Abrechnung 01 2025/P010852966_Sonderauswertung zum Honorarbescheid_ Anlage 6c je BSNR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/KV Abrechnung 01 2025/P010852976_Sonderauswertung zum Honorarbescheid_ Anlage 6d je BSNR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/KV Abrechnung 01 2025/P010852986_Sonderauswertung zum Honorarbescheid_ Anlage 6f je BSNR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/KV Abrechnung 01 2025/P010855332_Sonderauswertung zum Honorarbescheid_ Anlage 6g je BSNR für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'honorarbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/KV Abrechnung 01 2025/P010869823_Praxischeck für Quartal 1_2025.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'praxischeck')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/KV RLP Selektivvertraege/DAK_Diabetes_A6_Verguetung.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'kv rlp selektiv')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/KV RLP Selektivvertraege/KV_RLP_Selektivvertraege_Uebersicht.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'kv rlp selektiv')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Kontoauszug_20250302.jpeg.png	01_Privat/Kapitalerträge	Kapitalerträge / Depot / Bank (Match: 'kontoauszug')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Kontrollansicht Steuer 22.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/LV000120514276_Anschreiben_02_2025-10-15.pdf	01_Privat/Versicherungen	Privatversicherung (Match: 'lv000')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/LV000120514276_Änderungsantrag_01_2025-10-15.pdf	01_Privat/Versicherungen	Privatversicherung (Match: 'änderungsantrag')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Lipidserologie Fortbildung SüdpfalzDOCs  2025-06-16.pdf	02_Praxis-Bellheim/Fortbildung-CME	Fortbildung / CME (Match: 'fortbildung')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Mail an Frederking.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'frederking')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Mietvertrag_800089666_Uebergabeprotokoll.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'mietvertrag')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Mietvertrag_800099989_Uebergabeprotokoll.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'mietvertrag')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/NK Praxis Derma  Einheit 7.jpg	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'einheit 7')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/NK Rupp/NK 2023 Einheit 10.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'einheit 10')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/NK Rupp/NK 2024  Einheit 10.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'einheit 10')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/NK Rupp/Wohnung Einheit 13 2023 .pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'wohnung einheit')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/NK Rupp/Wohnung Einheit 13 2024.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'wohnung einheit')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Nebenkosten_Vergleich_Wohnungen_Praxen.png	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Nebenkosten_Vergleich_Wohnungen_Praxen_Tabelle.xlsx	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Nebenkosten_Vergleich_Wohnungen_Praxen_qm.png	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'nebenkosten')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Ordner „Mietvertrag Frederking“ öffnen.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'mietvertrag')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/PDF-Exposé #4430JM.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'exposé')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/PVS Rechnung Windbiel 2025-04-22 um 13.36.56.png	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'pvs rechnung')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Portfolio Projektübersicht_SüdpfalzDOCs.pdf	04_SuedpfalzDOCs	SüdpfalzDOCs (Match: 'südpfalzdocs')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Q4 2024.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/RG-2025-2845, SUEDPFALZDOCS.pdf	04_SuedpfalzDOCs	SüdpfalzDOCs (Match: 'suedpfalzdocs')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Rechnung 12.07.25.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Rechnung 2582 vom 02.10.2025 Mandant 17026.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Rechnung Umzug nach Bellheim 25 .pdf	02_Praxis-Bellheim/Reisekosten	Reisekosten / Flug / Hotel / Umzug Praxis (Match: 'umzug nach bellheim')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Rheuma TdA Berlin 2024.pdf	02_Praxis-Bellheim/Reisekosten	Reisekosten / Flug / Hotel / Umzug Praxis (Match: 'rheuma tda')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Rico Cannabis .pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/SG_Hausa_rztliche Versorgung_final_1799424042.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'hausa_rztliche')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Schadenanzeige Janitos 2.pdf	01_Privat/Versicherungen	Privatversicherung (Match: 'janitos')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Sonnen Apotheke Rechnung GLP 1 Analogon.pdf	01_Privat/außergewöhnliche-Belastungen	Außergewöhnliche Belastungen / Krankheitskosten (Match: 'apotheke rechnung')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Spickzettel-christophhilft/2023-05-10-VorsorgePlus-Infos.pdf	01_Privat/Vorsorge	Vorsorge / Rürup / Ärzteversorgung (Match: 'vorsorgeplus')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Spickzettel-christophhilft/2025-03-25-KV-Früherkennungsplan.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Spickzettel-christophhilft/2025-03-29-Christoph Terminplanung und Wirtschaftlichkeit.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Spickzettel-christophhilft/2025-10-16-Bestätigung-Kostenübernahme.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Spickzettel-christophhilft/2025-10-17-Abrechnung EBM.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'abrechnung ebm')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Suedpfalzdocs_Ausfüllbare_Tabelle.xls	04_SuedpfalzDOCs	SüdpfalzDOCs (Match: 'suedpfalzdocs')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/TS_NK_Widerspruch_Hausverwaltung.docx	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'widerspruch_hausverwaltung')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Thomas Schmitz 30.10.25.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Thomas Schmitz Rechnung 25 (1).pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Thomas Schmitz Rechnung Mr. Cycle E bike 25.05.2022.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Ticket_403143405429_Tages-Ticket__H.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/VRE3502128_2.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Vollmacht KFZ Zulassung online.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'kfz zulassung')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/WM_PDG_MFL71917085_03_250430_00_OM_WEB.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Workbook_Tag1.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.1.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.10.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.100.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.101.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.102.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.103.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.104.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.105.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.106.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.107.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.108.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.109.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.11.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.110.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.111.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.112.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.113.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.114.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.115.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.116.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.117.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.118.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.119.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.12.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.120.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.121.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.122.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.123.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.124.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.125.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.126.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.127.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.128.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.129.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.13.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.130.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.131.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.132.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.133.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.134.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.135.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.136.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.137.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.138.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.139.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.14.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.140.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.141.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.142.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.143.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.144.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.145.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.146.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.147.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.148.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.149.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.15.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.150.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.151.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.152.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.153.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.154.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.155.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.156.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.157.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.158.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.159.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.16.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.160.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.161.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.162.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.163.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.164.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.165.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.166.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.167.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.168.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.169.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.17.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.170.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.171.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.172.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.173.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.174.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.175.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.176.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.177.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.178.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.179.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.18.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.180.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.181.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.182.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.183.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.184.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.185.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.186.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.187.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.188.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.189.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.19.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.190.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.191.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.192.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.193.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.194.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.195.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.196.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.197.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.198.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.199.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.2.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.20.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.200.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.201.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.202.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.203.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.204.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.205.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.206.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.207.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.208.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.209.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.21.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.210.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.211.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.212.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.213.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.214.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.215.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.216.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.217.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.218.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.219.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.22.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.220.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.221.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.222.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.223.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.224.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.225.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.226.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.227.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.228.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.229.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.23.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.230.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.231.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.232.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.233.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.234.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.235.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.236.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.237.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.238.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.239.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.24.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.240.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.241.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.242.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.243.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.244.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.25.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.26.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.27.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.28.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.29.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.3.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.30.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.31.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.32.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.33.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.34.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.35.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.36.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.37.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.38.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.39.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.4.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.40.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.41.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.42.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.43.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.44.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.45.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.46.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.47.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.48.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.49.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.5.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.50.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.51.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.52.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.53.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.54.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.55.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.56.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.57.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.58.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.59.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.6.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.60.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.61.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.62.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.63.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.64.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.65.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.66.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.67.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.68.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.69.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.7.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.70.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.71.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.72.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.73.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.74.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.75.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.76.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.77.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.78.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.79.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.8.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.80.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.81.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.82.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.83.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.84.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.85.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.86.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.87.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.88.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.89.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.9.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.90.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.91.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.92.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.93.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.94.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.95.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.96.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.97.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.98.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.1/Retail.TransactionalInvoicing.99.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.1.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.10.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.11.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.12.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.13.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.14.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.15.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.16.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.17.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.18.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.19.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.2.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.20.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.21.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.22.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.23.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.24.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.25.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.26.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.27.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.28.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.29.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.3.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.30.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.31.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.32.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.33.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.34.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.35.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.36.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.37.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.38.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.39.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.4.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.40.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.41.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.42.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.43.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.44.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.45.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.46.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.47.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.48.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.49.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.5.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.50.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.51.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.52.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.53.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.54.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.55.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.56.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.57.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.58.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.59.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.6.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.60.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.61.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.62.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.63.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.64.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.65.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.66.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.67.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.68.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.69.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.7.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.70.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.71.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.72.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.73.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.74.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.75.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.76.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.77.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.78.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.79.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.8.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.80.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.81.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.82.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.83.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.84.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.85.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.86.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.87.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.88.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.89.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.9.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.90.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.91.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/Retail.TransactionalInvoicing.2.2/Retail.TransactionalInvoicing.92.pdf	99_Unklar-bitte-prüfen/Apple_Rechnungen_Sammlung	Apple Bestellungen (Mix privat/Praxis) — bitte sortieren
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/YourOrders.PhotoOnDelivery/media/11c61a20-e521-4520-b2fc-d9c1dc565bde.jpeg	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/YourOrders.PhotoOnDelivery/media/6e9d11d8-3a50-420a-af54-d621f32f275b.jpeg	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Your Orders/YourOrders.PhotoOnDelivery/media/88e37f9a-f648-4df5-924c-e07d92cec12b.jpeg	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Z01510119500_28.03.2025_11.26.CON.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Z01510119500_28.03.2025_11.26.Pruef.PDF	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Z01510119500_28.03.2025_11.26.Regelwerk.PDF	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Zahnzusatzversicherung_Axa_2025-11-19_101636.pdf	01_Privat/Versicherungen	Privatversicherung (Match: 'axa')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Zähler 10 25.HEIC	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'zähler 10')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Zähler 10 26.HEIC	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'zähler 10')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/Zulassungsbescheid.pdf	02_Praxis-Bellheim/Einnahmen	KV-Honorarbescheid / Selektivverträge / Einnahmen (Match: 'zulassungsbescheid')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/a7f31bc97b23ef9a4ef06bd4e2982bc3.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/attachments/DSGVO-Formular.pdf	02_Praxis-Bellheim/Praxiskosten	Praxiskosten (Match: 'dsgvo-formular')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/attachments/VK-NW-24136email.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/bellheim-über-240-liter-2025.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/dr_loges_downloadcenter/Preisliste.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/erneutes Schreiben an Gemeinde Bellheim Frederking August 25.pdf	01_Privat/Sonstiges-Privat	Vermietung / Wohnen / Auto (Match: 'frederking')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/kontaktanfrage-versicherung-73370174.pdf	01_Privat/Versicherungen	Privatversicherung (Match: 'kontaktanfrage-versicherung')
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/laborwerte_2219_tmp.pdf	99_Unklar-bitte-prüfen	keine Stichwort-Übereinstimmung
/Users/tschmitz/Library/Mobile Documents/com~apple~CloudDocs/99 Inbox/Downloads_Cloud/tomedoExport-2025_07_03_15_36_29.csv	02_Praxis-Bellheim/Abos-Software	Software / Abo (Match: 'tomedo')
QUELLEN_END
)

# === Übersicht.md ======================================
if [[ $DRY_RUN -eq 0 ]]; then
  OUT_MD="$ZIEL_BASIS/00_Übersicht.md"
  {
    printf '# Steuerunterlagen 2025 — Übersicht für Czerny/Pereira\n\n'
    printf 'Stand: %s\n\n' "$(date '+%Y-%m-%d %H:%M')"
    printf 'Erstellt durch das Hilfsskript `_KOPIEREN_STEUER_2025.sh`.\n\n'
    printf '## Status\n\n'
    printf -- '- Insgesamt geplant: %d\n' "$total"
    printf -- '- Erfolgreich kopiert: %d\n' "$ok"
    printf -- '- Übersprungen (schon da): %d\n' "$skip"
    printf -- '- Quelle nicht mehr da: %d\n' "$nicht_da"
    printf -- '- Fehler beim Kopieren: %d\n\n' "$fail"
    printf '> **Originaldateien wurden nicht angefasst.** Dieser Ordner enthält reine Kopien.\n\n'
    printf '## Ordnerstruktur\n\n'
    printf 'Pro Unterordner siehst du direkt die Inhalte:\n\n'
    for d in "$ZIEL_BASIS"/*/; do
      name=$(basename "$d")
      count=$(find "$d" -type f -not -name "00_*" -not -name "_*" | wc -l | tr -d ' ')
      printf -- '- `%s/` — %s Dateien\n' "$name" "$count"
    done
    printf '\n## Checkliste für den Steuerberater\n\n'
    printf '### Privat\n'
    printf -- '- [ ] Lohnsteuerbescheinigung (falls Angestellten-Anteil)\n'
    printf -- '- [ ] Beitragsbescheinigung Bayerische Ärzteversorgung (ÄVR)\n'
    printf -- '- [ ] Beitragsbescheinigung PKV\n'
    printf -- '- [ ] Beitragsbescheinigung BU-Versicherung\n'
    printf -- '- [ ] Beitragsbescheinigungen weitere Versicherungen (Haftpflicht, Hausrat, RS, KFZ)\n'
    printf -- '- [ ] Jahressteuerbescheinigung Depot(s)\n'
    printf -- '- [ ] Erträgnisaufstellungen aller Depots\n'
    printf -- '- [ ] Spendenbescheinigungen\n'
    printf -- '- [ ] Arzt-/Krankheitskosten\n'
    printf -- '- [ ] Kinderbetreuung / Schulgeld\n'
    printf -- '- [ ] Heiratsurkunde 20.06.2025\n'
    printf -- '- [ ] NK-Abrechnungen vermieteter Wohnungen\n\n'
    printf '### Praxis Bellheim\n'
    printf -- '- [ ] Alle 4 KV-Quartalsabrechnungen 2025 (Q1-Q4)\n'
    printf -- '- [ ] PVS-Abrechnungen Privatpatienten\n'
    printf -- '- [ ] Selektivverträge / HZV-Abrechnungen\n'
    printf -- '- [ ] Lohnabrechnungen Mitarbeiter inkl. Minijobs\n'
    printf -- '- [ ] Praxismiete-Belege\n'
    printf -- '- [ ] Praxisbedarf / Material\n'
    printf -- '- [ ] CME-Fortbildungsnachweise (Sonografie, Adipologie)\n'
    printf -- '- [ ] Software-Abos (Tomedo, Microsoft 365, anteilig Apple One)\n'
    printf -- '- [ ] Reisekosten Kongresse\n'
    printf -- '- [ ] Anschaffungsbelege (Cortrium EKG usw.)\n\n'
    printf '## Rückgängig machen\n\n'
    printf 'In Terminal.app ausführen:\n\n'
    printf '```\nbash "%s" --rollback\n```\n\n' "$0"
    printf 'Verschiebt den gesamten Zielordner in den Papierkorb. Originale bleiben unangetastet.\n'
  } > "$OUT_MD"
  log "Übersicht: $OUT_MD"
fi

# === Bericht in der Konsole ============================
log ""
log "============================================="
log "Fertig."
log "  Geplant: $total"
log "  Kopiert: $ok"
log "  Übersprungen (schon da): $skip"
log "  Quelle fehlt: $nicht_da"
log "  Fehler: $fail"
log "============================================="
log ""
log "Zielordner:"
log "  $ZIEL_BASIS"
log ""
log "Detail-Log:"
log "  $LOG"
log ""
[[ $fail -gt 0 ]] && log "Hinweis: $fail Fehler — schau ins Log, oft hilft erneutes Ausführen (Stubs werden dann beim 2. Lauf gezogen)."
