--[[
    RAW Select Bridge — Lightroom Classic plug-in.

    Runs a small background watcher inside Lightroom that turns "job" files
    dropped by the RAW Select app into rendered JPEGs. This lets RAW Select use
    Lightroom Classic as a local render engine (applying Camera-Raw presets,
    local masks and noise reduction) without any network access.

    Install: Lightroom → File → Plug-in Manager… → Add → pick this .lrplugin.
]]

return {
    LrSdkVersion        = 10.0,
    LrSdkMinimumVersion = 6.0,
    LrPluginName        = "RAW Select Bridge",
    LrToolkitIdentifier = "ch.anneler.rawselect.bridge",
    LrInitPlugin        = "InitBridge.lua",
    VERSION             = { major = 1, minor = 0, revision = 0 },
}
