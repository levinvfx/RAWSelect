--[[
    RAW Select Bridge — Lightroom Classic plug-in.

    Runs a small background watcher inside Lightroom that turns "job" files
    dropped by the RAW Select app into rendered JPEGs. This lets RAW Select use
    Lightroom Classic as a local render engine (applying Camera-Raw presets,
    local masks and noise reduction) without any network access.

    Install: Lightroom → Datei → Zusatzmodul-Manager… → Hinzufügen → diesen Ordner wählen.

    WICHTIG beim Ändern des Plugins: Lightroom merkt sich die Dateiliste eines Zusatzmoduls
    beim HINZUFÜGEN. Legt man danach eine neue .lua an, bleibt sie unsichtbar ("No script by
    the name …"), auch nach Neustart. Neue Dateien ⇒ im Zusatzmodul-Manager entfernen und
    erneut hinzufügen. Inhaltliche Änderungen an bestehenden Dateien reichen dagegen
    "Zusatzmodul neu laden".
]]

return {
    -- SDK-Version muss ≤ der tatsächlichen LrC-Lua-SDK-Version sein, sonst lädt LR das Modul
    -- nur HALB (grün/„aktiviert", aber Init.lua + Menüs laufen nie, Watcher tot). Achtung: die
    -- LrC-App heisst „15.4.1", die Lua-SDK ist aber nur 14.3 (Adobe Developer Console). 15.0 war
    -- deshalb UNGÜLTIG → half-load. 14.0 ist gültig (02.08.2026 recherchiert).
    LrSdkVersion        = 14.0,
    LrSdkMinimumVersion = 10.0,
    -- Kennung frisch (…bridge3, 02.08.2026): unter …bridge2 hing nach einem Lightroom-Absturz
    -- (LR 15.4.1) eine kaputte Registrierung, die grün/„aktiviert" anzeigte, aber Init.lua nie
    -- ausführte (Watcher tot). Eine neue Kennung erzwingt eine saubere Neu-Registrierung.
    -- Wenn das wieder passiert: hochzählen (…bridge4) und im Zusatzmodul-Manager neu hinzufügen.
    LrToolkitIdentifier = 'ch.anneler.rawselect.bridge4',
    LrPluginName        = 'RAW Select Bridge',

    -- Startet den Hintergrund-Watcher automatisch, sobald Lightroom das Plugin lädt.
    -- LrForceInitPlugin = true erzwingt den Lauf beim Start (auch wenn der Nutzer das
    -- Plugin nie manuell aufruft) — sonst wäre die Bridge nach jedem Neustart tot.
    LrInitPlugin      = 'Init.lua',
    LrForceInitPlugin = true,
    LrShutdownPlugin  = 'Shutdown.lua',

    LrLibraryMenuItems = {
        { title = 'RAW Select – Watcher-Status', file = 'Status.lua' },
    },

    VERSION = { major = 0, minor = 3 },
}
