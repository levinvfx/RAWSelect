-- Manueller Status-Check des Watchers (Bibliothek → Zusatzmodul-Optionen).
local LrDialogs   = import 'LrDialogs'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrTasks     = import 'LrTasks'

LrTasks.startAsyncTask(function()
    local home = LrPathUtils.getStandardFilePath('home')
    local base = LrPathUtils.child(home, 'Library')
    base = LrPathUtils.child(base, 'Application Support')
    base = LrPathUtils.child(base, 'RAW Select')
    base = LrPathUtils.child(base, 'LightroomBridge')
    local jobsDir = LrPathUtils.child(base, 'jobs')

    local function count(dir, ext)
        local n = 0
        if LrFileUtils.exists(dir) then
            for p in LrFileUtils.directoryEntries(dir) do
                if not ext or LrPathUtils.extension(p) == ext then n = n + 1 end
            end
        end
        return n
    end

    local running = (_G.RAWSelectGen ~= nil)
    LrDialogs.message(
        'RAW Select Watcher',
        'Läuft: ' .. tostring(running) .. ' (gen ' .. tostring(_G.RAWSelectGen) .. ')\n' ..
        'Offene Jobs: ' .. count(jobsDir, 'job') .. '\n' ..
        'Spool: ' .. base,
        'info')
end)
