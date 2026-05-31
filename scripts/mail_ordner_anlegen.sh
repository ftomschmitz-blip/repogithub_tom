#!/bin/bash
# Apple Mail + Outlook Ordnerstruktur anlegen
# Ausführen: bash ~/repogithub_tom/scripts/mail_ordner_anlegen.sh
# Hinweis: Mail.app und Outlook müssen geschlossen sein

echo "=== Apple Mail: Ordner anlegen (Auf meinem Mac) ==="
echo ""

osascript <<'EOF'
tell application "Mail"
    -- Auf meinem Mac: Toplevel
    set folders to {¬
        "00 Privat", ¬
        "00 Privat/Familie", ¬
        "00 Privat/Finanzen & Versicherungen", ¬
        "00 Privat/Wohnen", ¬
        "00 Privat/Gesundheit", ¬
        "00 Privat/Reisen & Freizeit", ¬
        "10 Praxis Bellheim", ¬
        "10 Praxis Bellheim/Abrechnung & KV", ¬
        "10 Praxis Bellheim/Personal & MFA", ¬
        "10 Praxis Bellheim/Lieferanten & Rechnungen", ¬
        "10 Praxis Bellheim/HZV & DMP", ¬
        "10 Praxis Bellheim/Behoerden", ¬
        "10 Praxis Bellheim/Kollegen & Aerzte", ¬
        "20 Berufliches & CME", ¬
        "20 Berufliches & CME/Aerztekammer", ¬
        "20 Berufliches & CME/KV Rheinland-Pfalz", ¬
        "20 Berufliches & CME/Fortbildung & CME", ¬
        "30 Firma & Investments", ¬
        "30 Firma & Investments/Smartlaunch", ¬
        "90 Archiv", ¬
        "_WARTEN_AUF_ANTWORT", ¬
        "_FOLLOW_UP"}

    repeat with folderName in folders
        try
            make new mailbox with properties {name:folderName}
            log "Angelegt: " & folderName
        on error errMsg
            if errMsg contains "already exists" or errMsg contains "existiert" then
                log "Bereits vorhanden: " & folderName
            else
                log "Fehler bei " & folderName & ": " & errMsg
            end if
        end try
    end repeat
end tell
EOF

echo ""
echo "Apple Mail Ordner angelegt."
echo ""
echo "=== Outlook SüdpfalzDOCs: Ordner anlegen ==="
echo ""

osascript <<'EOF'
tell application "Microsoft Outlook"
    set suedpfalzFolders to {¬
        "Dienstplanung", ¬
        "Finanzen SuedpfalzDOCs", ¬
        "Mitglieder", ¬
        "Behoerden & KV", ¬
        "Archiv SuedpfalzDOCs", ¬
        "_Warten auf Antwort"}

    try
        set theAccount to first exchange account whose email address is "t.schmitz@suedpfalzdocs.de"
        repeat with folderName in suedpfalzFolders
            try
                make new mail folder with properties {name:folderName, container:inbox of theAccount}
                log "Angelegt: " & folderName
            on error errMsg
                log "Übersprungen (" & folderName & "): " & errMsg
            end try
        end repeat
    on error
        log "SüdpfalzDOCs-Account nicht gefunden — Outlook-Ordner werden übersprungen."
    end try
end tell
EOF

echo ""
echo "Fertig. Mail.app öffnen und Ordner in Sidebar prüfen."
