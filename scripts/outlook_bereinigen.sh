#!/bin/bash
# Outlook bereinigen — nur t.schmitz@suedpfalzdocs.de behalten
# Dry-run:  bash ~/repogithub_tom/scripts/outlook_bereinigen.sh
# Ausführen: bash ~/repogithub_tom/scripts/outlook_bereinigen.sh --execute

KEEP="t.schmitz@suedpfalzdocs.de"
EXECUTE=false
[[ "$1" == "--execute" ]] && EXECUTE=true

echo "=== Outlook: Account-Inventur ==="
echo ""

ACCOUNT_LIST=$(osascript <<'EOF'
tell application "Microsoft Outlook"
    set output to {}
    try
        repeat with acc in (every exchange account)
            set end of output to "  Exchange : " & (email address of acc)
        end repeat
    end try
    try
        repeat with acc in (every imap account)
            set end of output to "  IMAP     : " & (email address of acc)
        end repeat
    end try
    try
        repeat with acc in (every pop account)
            set end of output to "  POP      : " & (email address of acc)
        end repeat
    end try
    set AppleScript's text item delimiters to linefeed
    return output as text
end tell
EOF
)

echo "$ACCOUNT_LIST"
echo ""
echo "Behalten: $KEEP"
echo "Entfernt: alle anderen"

if [[ "$EXECUTE" == false ]]; then
    echo ""
    echo "[DRY-RUN] Keine Änderungen. Ausführen: bash $0 --execute"
    exit 0
fi

echo ""
echo "WARNUNG: Alle anderen Accounts werden dauerhaft aus Outlook entfernt."
echo "Voraussetzung: Gmail + iCloud laufen bereits in Apple Mail. Fortfahren? (j/N)"
read -r answer
[[ "$answer" != "j" ]] && echo "Abgebrochen." && exit 1

echo ""
echo "Entferne Accounts..."

osascript << SCRIPT
set keepAccount to "$KEEP"
tell application "Microsoft Outlook"
    set removedList to {}
    try
        set allExchange to every exchange account
        repeat with acc in allExchange
            if (email address of acc) is not keepAccount then
                set end of removedList to (email address of acc) & " [Exchange]"
                delete acc
            end if
        end repeat
    end try
    try
        set allImap to every imap account
        repeat with acc in allImap
            if (email address of acc) is not keepAccount then
                set end of removedList to (email address of acc) & " [IMAP]"
                delete acc
            end if
        end repeat
    end try
    try
        set allPop to every pop account
        repeat with acc in allPop
            if (email address of acc) is not keepAccount then
                set end of removedList to (email address of acc) & " [POP]"
                delete acc
            end if
        end repeat
    end try
    if (count of removedList) > 0 then
        set AppleScript's text item delimiters to linefeed
        log "Entfernt: " & (removedList as text)
    else
        log "Keine weiteren Accounts gefunden."
    end if
end tell
SCRIPT

EXIT=$?
if [[ $EXIT -ne 0 ]]; then
    echo ""
    echo "AppleScript konnte Accounts nicht automatisch entfernen."
    echo "Manuelle Alternative:"
    echo "  Outlook öffnen → Cmd+, → Accounts → alle außer '$KEEP' mit '-' löschen"
    open -a "Microsoft Outlook"
else
    echo ""
    echo "Fertig. Bitte Outlook neu starten und prüfen."
fi
