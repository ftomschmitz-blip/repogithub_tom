#!/bin/bash
# Apple Mail Regeln anlegen
# Dry-run:  bash ~/repogithub_tom/scripts/mail_regeln.sh --dry-run
# Ausführen: bash ~/repogithub_tom/scripts/mail_regeln.sh

DRY_RUN=false
[[ "$1" == "--dry-run" ]] && DRY_RUN=true

if [[ "$DRY_RUN" == true ]]; then
    echo "=== DRY-RUN: Geplante Mail-Regeln ==="
    echo ""
    echo "Ziel: 10 Praxis Bellheim/Abrechnung & KV"
    echo "  Von: kvrlp.de, kv-rlp.de, pvs-sw.de / Betreff: Honorarabrechnung"
    echo ""
    echo "Ziel: 10 Praxis Bellheim/HZV & DMP"
    echo "  Von: aok, barmer, dak, tkk, hek, bkk, techniker"
    echo ""
    echo "Ziel: 10 Praxis Bellheim/DMP Abrechnung"
    echo "  Betreff: DMP, Disease Management"
    echo ""
    echo "Ziel: 10 Praxis Bellheim/Personal & MFA"
    echo "  Betreff: Bewerbung, Vorstellungsgespraech"
    echo ""
    echo "Ziel: 10 Praxis Bellheim/Lieferanten & Rechnungen"
    echo "  Von: sparkasse-suedpfalz, mediverbund"
    echo ""
    echo "Ziel: 10 Praxis Bellheim/Behoerden"
    echo "  Von: gesundheitsamt, kreisverwaltung, ministerium"
    echo ""
    echo "Ziel: 20 Berufliches & CME/Aerztekammer"
    echo "  Von: aerztekammer, baek.de, laek"
    echo ""
    echo "Ziel: 20 Berufliches & CME/Fortbildung & CME"
    echo "  Von: cme-portal / Betreff: Fortbildung, CME, Kongress, Zertifikat"
    echo ""
    echo "Ziel: 00 Privat/Finanzen & Versicherungen"
    echo "  Von: bayerische-aerzteversorgung, ing.de, ing-diba, debeka"
    echo ""
    echo "Gesamt: ~19 Regeln"
    echo "Zum Anlegen: bash $0"
    exit 0
fi

echo "=== Apple Mail: Regeln anlegen ==="
echo "Fortfahren? (j/N)"
read -r answer
[[ "$answer" != "j" ]] && echo "Abgebrochen." && exit 1

echo "Lege Regeln an..."

python3 - <<'PYEOF'
import subprocess

RULES = [
    {
        "name": "KV RLP - Abrechnung",
        "criteria": [
            ("From", "kvrlp.de"),
            ("From", "kv-rlp.de"),
        ],
        "folder": ["10 Praxis Bellheim", "Abrechnung & KV"],
    },
    {
        "name": "PVS - Abrechnung",
        "criteria": [
            ("From", "pvs-sw.de"),
            ("Subject", "Honorarabrechnung"),
        ],
        "folder": ["10 Praxis Bellheim", "Abrechnung & KV"],
    },
    {
        "name": "Krankenkassen - HZV",
        "criteria": [
            ("From", "aok"),
            ("From", "barmer"),
            ("From", "dak-gesundheit"),
            ("From", "tkk.de"),
            ("From", "hek.de"),
            ("From", "bkk"),
            ("From", "techniker"),
        ],
        "folder": ["10 Praxis Bellheim", "HZV & DMP"],
    },
    {
        "name": "DMP - Abrechnung",
        "criteria": [
            ("Subject", "DMP"),
            ("Subject", "Disease Management"),
        ],
        "folder": ["10 Praxis Bellheim", "DMP Abrechnung"],
    },
    {
        "name": "Bewerbungen - Personal",
        "criteria": [
            ("Subject", "Bewerbung"),
            ("Subject", "Vorstellungsgesprach"),
            ("Subject", "Initiativbewerbung"),
        ],
        "folder": ["10 Praxis Bellheim", "Personal & MFA"],
    },
    {
        "name": "Sparkasse - Lieferanten",
        "criteria": [
            ("From", "sparkasse-suedpfalz"),
            ("From", "mediverbund"),
        ],
        "folder": ["10 Praxis Bellheim", "Lieferanten & Rechnungen"],
    },
    {
        "name": "Behoerden - Praxis",
        "criteria": [
            ("From", "gesundheitsamt"),
            ("From", "kreisverwaltung"),
            ("From", "ministerium"),
        ],
        "folder": ["10 Praxis Bellheim", "Behörden"],
    },
    {
        "name": "Aerztekammer",
        "criteria": [
            ("From", "aerztekammer"),
            ("From", "baek.de"),
            ("From", "laek"),
        ],
        "folder": ["20 Berufliches & CME", "Ärztekammer"],
    },
    {
        "name": "Fortbildung & CME",
        "criteria": [
            ("Subject", "Fortbildung"),
            ("Subject", "CME"),
            ("Subject", "Kongress"),
            ("Subject", "Zertifikat"),
            ("From", "cme-portal"),
        ],
        "folder": ["20 Berufliches & CME", "Fortbildung & CME"],
    },
    {
        "name": "Finanzen - Privat",
        "criteria": [
            ("From", "bayerische-aerzteversorgung"),
            ("From", "ing.de"),
            ("From", "ing-diba"),
            ("From", "debeka"),
        ],
        "folder": ["00 Privat", "Finanzen & Versicherungen"],
    },
]

for rule in RULES:
    # Build AppleScript for each rule individually
    criteria_lines = []
    for header, expr in rule["criteria"]:
        criteria_lines.append(
            f'make new rule criterion at end of rule criteria of r '
            f'with properties {{header:"{header}", qualifier:contains, expression:"{expr}"}}'
        )
    criteria_as = "\n        ".join(criteria_lines)

    parent, child = rule["folder"]
    script = f'''
tell application "Mail"
    try
        set r to make new rule with properties {{name:"{rule["name"]}", enabled:true}}
        {criteria_as}
        set localAccount to missing value
        repeat with acc in every account
            if (type of acc as text) contains "Mac" then
                set localAccount to acc
                exit repeat
            end if
        end repeat
        if localAccount is not missing value then
            set mb to mailbox "{child}" of mailbox "{parent}" of localAccount
            make new rule action at end of rule actions of r with properties {{rule action type:move to mailbox, target mailbox:mb}}
        end if
        log "OK: {rule["name"]}"
    on error e
        log "FEHLER {rule["name"]}: " & e
    end try
end tell
'''
    result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if result.returncode == 0:
        print(f"  OK: {rule['name']}")
    else:
        print(f"  FEHLER: {rule['name']} — {result.stderr.strip()}")

print("Fertig. Mail.app -> Einstellungen -> Regeln pruefen.")
PYEOF
