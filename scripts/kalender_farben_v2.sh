#!/bin/bash
# Kalender Farbcode v2 setzen — iCloud Kalender
# Ausführen: bash ~/repogithub_tom/scripts/kalender_farben_v2.sh
# Hinweis: Kalender.app muss geschlossen sein

osascript <<'EOF'
tell application "Calendar"
    -- Privat → Grün
    repeat with c in calendars
        if name of c is "Privat" then
            set color of c to {5140, 43690, 16383}
        end if
        if name of c is "Familie" then
            set color of c to {5140, 43690, 16383}
        end if
        -- Praxis Bellheim → Rot
        if name of c is "Praxis Bellheim" then
            set color of c to {65535, 0, 0}
        end if
        -- Berufliches/KV → Violett
        if name of c is "Berufliches/KV" then
            set color of c to {32767, 0, 65535}
        end if
        if name of c is "Berufliches" then
            set color of c to {32767, 0, 65535}
        end if
        -- Firma → Türkis
        if name of c is "Firma" then
            set color of c to {0, 52428, 52428}
        end if
        -- SüdpfalzDOC e.V. → Orange
        if name of c is "SüdpfalzDOC e.V." then
            set color of c to {65535, 32767, 0}
        end if
        -- SüdpfalzDOCs gGmbH → Gelb
        if name of c is "SüdpfalzDOCs gGmbH" then
            set color of c to {65535, 65535, 0}
        end if
    end repeat
end tell
EOF

echo "Kalender-Farben v2 gesetzt."
