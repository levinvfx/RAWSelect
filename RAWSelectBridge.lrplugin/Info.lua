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
    -- 13.0: Lightroom 15.4 lädt ein Modul mit SDK 10.0 nur halb (Skripte werden dann nie
    -- registriert), obwohl LrSdkMinimumVersion das erlauben würde.
    LrSdkVersion        = 13.0,
    LrSdkMinimumVersion = 6.0,
    -- Kennung bewusst neu (…bridge2): unter der alten hing eine kaputte Registrierung, die
    -- Entfernen + Hinzufügen überlebt hat.
    LrToolkitIdentifier = 'ch.anneler.rawselect.bridge2',
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
