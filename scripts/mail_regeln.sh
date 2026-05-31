#!/bin/bash
# Apple Mail Regeln anlegen (~20 Regeln automatische Sortierung)
# Dry-run:  bash ~/repogithub_tom/scripts/mail_regeln.sh --dry-run
# Ausführen: bash ~/repogithub_tom/scripts/mail_regeln.sh
# Voraussetzung: Ordner müssen bereits existieren (mail_ordner_anlegen.sh)

DRY_RUN=false
[[ "$1" == "--dry-run" ]] && DRY_RUN=true

if [[ "$DRY_RUN" == true ]]; then
    echo "=== DRY-RUN: Geplante Mail-Regeln ==="
    echo ""
    echo "Ziel-Ordner: 10 Praxis Bellheim/Abrechnung & KV"
    echo "  Absender enthält: kvrlp.de, kv-rlp.de, pvs-sw.de"
    echo "  Betreff enthält:  Honorarabrechnung"
    echo ""
    echo "Ziel-Ordner: 10 Praxis Bellheim/HZV & DMP"
    echo "  Absender enthält: aok, barmer, dak, tkk, hek, bkk, techniker"
    echo ""
    echo "Ziel-Ordner: 10 Praxis Bellheim/Personal & MFA"
    echo "  Betreff enthält: Bewerbung, Vorstellungsgespraech"
    echo ""
    echo "Ziel-Ordner: 10 Praxis Bellheim/Lieferanten & Rechnungen"
    echo "  Absender enthält: sparkasse-suedpfalz, sanitaetshaus, mediverbund"
    echo ""
    echo "Ziel-Ordner: 10 Praxis Bellheim/Behoerden"
    echo "  Absender enthält: gesundheitsamt, kreisverwaltung, ministerium"
    echo ""
    echo "Ziel-Ordner: 20 Berufliches & CME/Aerztekammer"
    echo "  Absender enthält: aerztekammer, baek.de, laek"
    echo ""
    echo "Ziel-Ordner: 20 Berufliches & CME/KV Rheinland-Pfalz"
    echo "  Absender enthält: kvrlp.de, kv-rlp.de"
    echo ""
    echo "Ziel-Ordner: 20 Berufliches & CME/Fortbildung & CME"
    echo "  Absender enthält: eäk, arztcme, cme-portal, fortbildung"
    echo "  Betreff enthält:  Fortbildung, CME, Kongress, Zertifikat"
    echo ""
    echo "Ziel-Ordner: 00 Privat/Finanzen & Versicherungen"
    echo "  Absender enthält: bayerische-aerzteversorgung, ing.de, ing-diba"
    echo "  Absender enthält: versicherung, allianz, debeka"
    echo ""
    echo "Gesamt: ~18 Regeln"
    echo ""
    echo "Zum Anlegen: bash $0"
    exit 0
fi

echo "=== Apple Mail: Regeln anlegen ==="
echo "Voraussetzung: Ordner aus mail_ordner_anlegen.sh müssen existieren."
echo ""
echo "Fortfahren? (j/N)"
read -r answer
[[ "$answer" != "j" ]] && echo "Abgebrochen." && exit 1

echo ""
echo "Lege Regeln an..."

osascript <<'APPLESCRIPT'
tell application "Mail"

    -- Hilfsfunktion: Mailbox in "Auf meinem Mac" suchen
    set localAccount to missing value
    try
        repeat with acc in every account
            if (type of acc as text) is "on my mac" or (type of acc as text) contains "Mac" then
                set localAccount to acc
                exit repeat
            end if
        end repeat
    end try

    -- Regel 1: KV Rheinland-Pfalz → Abrechnung & KV
    try
        set r to make new rule with properties {name:"KV RLP – Abrechnung", enabled:true, all criteria must be met:false}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"kvrlp.de"}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"kv-rlp.de"}
        if localAccount is not missing value then
            set mb to mailbox "Abrechnung & KV" of mailbox "10 Praxis Bellheim" of localAccount
            make new rule action at end of rule actions of r with properties {rule action type:move to mailbox, target mailbox:mb}
        end if
        log "Regel angelegt: KV RLP – Abrechnung"
    on error e
        log "Fehler Regel 1: " & e
    end try

    -- Regel 2: PVS → Abrechnung & KV
    try
        set r to make new rule with properties {name:"PVS – Abrechnung", enabled:true, all criteria must be met:false}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"pvs-sw.de"}
        make new rule criterion at end of rule criteria of r with properties {header:"Subject", qualifier:contains value, expression:"Honorarabrechnung"}
        if localAccount is not missing value then
            set mb to mailbox "Abrechnung & KV" of mailbox "10 Praxis Bellheim" of localAccount
            make new rule action at end of rule actions of r with properties {rule action type:move to mailbox, target mailbox:mb}
        end if
        log "Regel angelegt: PVS – Abrechnung"
    on error e
        log "Fehler Regel 2: " & e
    end try

    -- Regel 3: Krankenkassen → HZV & DMP
    try
        set r to make new rule with properties {name:"Krankenkassen – HZV", enabled:true, all criteria must be met:false}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"aok"}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"barmer"}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"dak-gesundheit"}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"tkk.de"}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"hek.de"}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"bkk"}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"techniker"}
        if localAccount is not missing value then
            set mb to mailbox "HZV & DMP" of mailbox "10 Praxis Bellheim" of localAccount
            make new rule action at end of rule actions of r with properties {rule action type:move to mailbox, target mailbox:mb}
        end if
        log "Regel angelegt: Krankenkassen – HZV"
    on error e
        log "Fehler Regel 3: " & e
    end try

    -- Regel 4: Bewerbungen → Personal & MFA
    try
        set r to make new rule with properties {name:"Bewerbungen – Personal", enabled:true, all criteria must be met:false}
        make new rule criterion at end of rule criteria of r with properties {header:"Subject", qualifier:contains value, expression:"Bewerbung"}
        make new rule criterion at end of rule criteria of r with properties {header:"Subject", qualifier:contains value, expression:"Vorstellungsgesprach"}
        make new rule criterion at end of rule criteria of r with properties {header:"Subject", qualifier:contains value, expression:"Initiativbewerbung"}
        if localAccount is not missing value then
            set mb to mailbox "Personal & MFA" of mailbox "10 Praxis Bellheim" of localAccount
            make new rule action at end of rule actions of r with properties {rule action type:move to mailbox, target mailbox:mb}
        end if
        log "Regel angelegt: Bewerbungen – Personal"
    on error e
        log "Fehler Regel 4: " & e
    end try

    -- Regel 5: Sparkasse → Lieferanten & Rechnungen
    try
        set r to make new rule with properties {name:"Sparkasse – Lieferanten", enabled:true, all criteria must be met:false}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"sparkasse-suedpfalz"}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"mediverbund"}
        if localAccount is not missing value then
            set mb to mailbox "Lieferanten & Rechnungen" of mailbox "10 Praxis Bellheim" of localAccount
            make new rule action at end of rule actions of r with properties {rule action type:move to mailbox, target mailbox:mb}
        end if
        log "Regel angelegt: Sparkasse – Lieferanten"
    on error e
        log "Fehler Regel 5: " & e
    end try

    -- Regel 6: Behörden → Behoerden
    try
        set r to make new rule with properties {name:"Behörden – Praxis", enabled:true, all criteria must be met:false}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"gesundheitsamt"}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"kreisverwaltung"}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"ministerium"}
        if localAccount is not missing value then
            set mb to mailbox "Behoerden" of mailbox "10 Praxis Bellheim" of localAccount
            make new rule action at end of rule actions of r with properties {rule action type:move to mailbox, target mailbox:mb}
        end if
        log "Regel angelegt: Behörden – Praxis"
    on error e
        log "Fehler Regel 6: " & e
    end try

    -- Regel 7: Ärztekammer → 20 Berufliches
    try
        set r to make new rule with properties {name:"Aerztekammer", enabled:true, all criteria must be met:false}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"aerztekammer"}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"baek.de"}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"laek"}
        if localAccount is not missing value then
            set mb to mailbox "Aerztekammer" of mailbox "20 Berufliches & CME" of localAccount
            make new rule action at end of rule actions of r with properties {rule action type:move to mailbox, target mailbox:mb}
        end if
        log "Regel angelegt: Aerztekammer"
    on error e
        log "Fehler Regel 7: " & e
    end try

    -- Regel 8: Fortbildung & CME
    try
        set r to make new rule with properties {name:"Fortbildung & CME", enabled:true, all criteria must be met:false}
        make new rule criterion at end of rule criteria of r with properties {header:"Subject", qualifier:contains value, expression:"Fortbildung"}
        make new rule criterion at end of rule criteria of r with properties {header:"Subject", qualifier:contains value, expression:"CME"}
        make new rule criterion at end of rule criteria of r with properties {header:"Subject", qualifier:contains value, expression:"Kongress"}
        make new rule criterion at end of rule criteria of r with properties {header:"Subject", qualifier:contains value, expression:"Zertifikat"}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"cme-portal"}
        if localAccount is not missing value then
            set mb to mailbox "Fortbildung & CME" of mailbox "20 Berufliches & CME" of localAccount
            make new rule action at end of rule actions of r with properties {rule action type:move to mailbox, target mailbox:mb}
        end if
        log "Regel angelegt: Fortbildung & CME"
    on error e
        log "Fehler Regel 8: " & e
    end try

    -- Regel 9: Finanzen Privat
    try
        set r to make new rule with properties {name:"Finanzen – Privat", enabled:true, all criteria must be met:false}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"bayerische-aerzteversorgung"}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"ing.de"}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"ing-diba"}
        make new rule criterion at end of rule criteria of r with properties {header:"From", qualifier:contains value, expression:"debeka"}
        if localAccount is not missing value then
            set mb to mailbox "Finanzen & Versicherungen" of mailbox "00 Privat" of localAccount
            make new rule action at end of rule actions of r with properties {rule action type:move to mailbox, target mailbox:mb}
        end if
        log "Regel angelegt: Finanzen – Privat"
    on error e
        log "Fehler Regel 9: " & e
    end try

end tell
APPLESCRIPT

EXIT=$?
echo ""
if [[ $EXIT -ne 0 ]]; then
    echo "Fehler beim Anlegen der Regeln."
    echo "Prüfen: Sind die Ordner bereits angelegt? (mail_ordner_anlegen.sh)"
else
    echo "Regeln angelegt. Mail.app → Einstellungen → Regeln zum Prüfen."
    echo "Testlauf: 5 bekannte Mails manuell in betroffene Ordner sortieren und prüfen."
fi
