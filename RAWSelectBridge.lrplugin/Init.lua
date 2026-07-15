-- RAW Select Bridge – Hintergrund-Watcher
--
-- Läuft dauerhaft in Lightroom Classic und überwacht einen Spool-Ordner.
-- RAW Select legt dort eine *.job-Datei ab; der Watcher importiert das RAW
-- (dessen .xmp-Sidecar den Preset inkl. Masken trägt) und exportiert ein JPEG.
--
-- Ablauf pro Job – bewusst robust:
--  1) Watcher-Schleife benennt eine *.job sofort in *.processing um (nicht-blockierend),
--     damit sie nicht doppelt aufgegriffen wird.
--  2) Jeder Job läuft in einer EIGENEN Async-Task -> ein Fehler killt nur den Job,
--     nicht den Watcher. (SDK-Aufrufe, die warten, dürfen NICHT in pcall stehen,
--     weil Lua über eine pcall-Grenze nicht yielden kann.)
--  3) Ergebnis wird als done/<id>.done geschrieben, das RAW Select pollt.
--
-- Protokoll (muss zu Sources/RAWSelect/Services/LightroomExportService.swift passen):
--   jobs/<id>.job            Anfrage der App
--   jobs/<id>.job.processing vom Watcher reserviert
--   done/<id>.done           Antwort: status=ok|error, path=…, message=…,
--                            optional temperature=… / tint=…

local LrApplication   = import 'LrApplication'
local LrTasks         = import 'LrTasks'
local LrExportSession = import 'LrExportSession'
local LrPathUtils     = import 'LrPathUtils'
local LrFileUtils     = import 'LrFileUtils'

-- Spool-Verzeichnisse (~/Library/Application Support/RAW Select/LightroomBridge)
local home    = LrPathUtils.getStandardFilePath('home')
local base    = LrPathUtils.child(home, 'Library')
base          = LrPathUtils.child(base, 'Application Support')
base          = LrPathUtils.child(base, 'RAW Select')
base          = LrPathUtils.child(base, 'LightroomBridge')
local jobsDir = LrPathUtils.child(base, 'jobs')
local doneDir = LrPathUtils.child(base, 'done')
local logDir  = LrPathUtils.child(base, 'logs')

local function ensureDir(p)
    if not LrFileUtils.exists(p) then LrFileUtils.createAllDirectories(p) end
end

local function appendLog(path, s)
    local f = io.open(path, 'a')
    if f then f:write(os.date('%H:%M:%S ') .. tostring(s) .. '\n'); f:close() end
end

local function parseJob(path)
    local job = {}
    for line in io.lines(path) do
        local k, v = line:match('^(%w+)=(.*)$')
        if k then job[k] = v end
    end
    return job
end

-- Schreibt den Ergebnis-Marker, den RAW Select pollt.
-- temp/tint = der Weissabgleich, den Camera Raw für dieses Foto aufgelöst hat. Die App
-- braucht ihn als BASIS ihrer WB-Regler: Presets stehen meist auf "As Shot" und tragen
-- gar keine Temperatur, und ohne bekannte Basis darf die App keinen absoluten Kelvin-
-- Wert schreiben (ein Delta von +300 landete sonst als 300 K = tiefblau).
local function writeDone(id, status, outPath, message, temp, tint)
    local f = io.open(LrPathUtils.child(doneDir, id .. '.done'), 'w')
    if f then
        f:write('status=' .. status .. '\n')
        f:write('path=' .. (outPath or '') .. '\n')
        f:write('message=' .. (message or '') .. '\n')
        if temp then f:write('temperature=' .. tostring(temp) .. '\n') end
        if tint then f:write('tint=' .. tostring(tint) .. '\n') end
        f:close()
    end
end

-- Verarbeitet EINE bereits in *.processing umbenannte Job-Datei.
local function processJob(procPath)
    local job = parseJob(procPath)
    local id  = job.id or LrPathUtils.removeExtension(LrPathUtils.leafName(procPath))
    local logPath = LrPathUtils.child(logDir, id .. '.log')
    local function L(s) appendLog(logPath, s) end

    L('--- Job ' .. id)
    L('raw=' .. tostring(job.raw))
    L('out=' .. tostring(job.out))

    if not job.raw or not job.out then
        L('FEHLER: raw/out fehlt')
        writeDone(id, 'error', '', 'raw/out fehlt')
        return
    end

    -- Die RAW-Kopie liegt im Temp-Ordner und ist irgendwann weg. Bleibt ein Job liegen
    -- (App-Absturz, Lightroom zu), zeigt addPhoto sonst beim naechsten Start einen modalen
    -- "interner Fehler: no file at path"-Dialog — mitten in Lightroom, fuer einen Job, den
    -- niemand mehr will.
    if not LrFileUtils.exists(job.raw) then
        L('FEHLER: RAW nicht mehr vorhanden (veralteter Job) -> ' .. tostring(job.raw))
        writeDone(id, 'error', '', 'RAW nicht mehr vorhanden')
        return
    end

    local catalog = LrApplication.activeCatalog()
    local photo = catalog:findPhotoByPath(job.raw)
    L('bereits im Katalog: ' .. tostring(photo ~= nil))

    if not photo then
        catalog:withWriteAccessDo('RAW Select Import', function()
            photo = catalog:addPhoto(job.raw)
        end, { timeout = 60 })
    end

    if not photo then
        L('FEHLER: Import fehlgeschlagen')
        writeDone(id, 'error', '', 'Import fehlgeschlagen')
        return
    end

    -- Develop-Settings aus dem Sidecar: Diagnose + der Weissabgleich für die App.
    local ds = photo:getDevelopSettings()
    if ds then
        L('Masken vorhanden: ' .. tostring(ds.MaskGroupBasedCorrections ~= nil))
        L('wb vor Render: WhiteBalance=' .. tostring(ds.WhiteBalance) ..
          ' temp=' .. tostring(ds.Temperature) .. ' tint=' .. tostring(ds.Tint))
    end

    -- Export-Einstellungen aus dem Job
    local settings = {
        LR_export_destinationType       = 'specificFolder',
        LR_export_destinationPathPrefix = job.out,
        LR_export_useSubfolder          = false,
        LR_format                       = 'JPEG',
        LR_jpeg_quality                 = tonumber(job.quality) or 0.9,
        LR_export_colorSpace            = job.colorspace or 'sRGB',
        LR_collisionHandling            = 'rename',
        LR_reimportExportedPhoto        = false,
    }
    local maxW = tonumber(job.maxwidth) or 0
    local maxH = tonumber(job.maxheight) or 0
    if maxW > 0 and maxH > 0 then
        settings.LR_size_doConstrain = true
        settings.LR_size_maxWidth    = maxW
        settings.LR_size_maxHeight   = maxH
        settings.LR_size_units       = 'pixels'
    else
        settings.LR_size_doConstrain = false
    end

    local session = LrExportSession({ photosToExport = { photo }, exportSettings = settings })
    local outPath, okAny = nil, false
    for _, rendition in session:renditions() do
        local ok, path = rendition:waitForRender()
        L('gerendert: ' .. tostring(ok) .. ' -> ' .. tostring(path))
        if ok then okAny = true; outPath = path end
    end

    -- Weissabgleich ERST JETZT lesen: bei WhiteBalance="As Shot" trägt das Preset gar keine
    -- Temperatur, Camera Raw muss das RAW erst dekodieren, um den Kelvin-Wert zu kennen.
    -- Direkt nach addPhoto ist er darum noch nil — nach dem Render steht er fest.
    local wbTemp, wbTint
    local ds2 = photo:getDevelopSettings()
    if ds2 then
        wbTemp = tonumber(ds2.Temperature)
        wbTint = tonumber(ds2.Tint)
    end
    L('wb nach Render: temp=' .. tostring(wbTemp) .. ' tint=' .. tostring(wbTint))

    if okAny then
        writeDone(id, 'ok', outPath, '', wbTemp, wbTint)
        L('FERTIG ok')
    else
        writeDone(id, 'error', '', 'Render fehlgeschlagen')
        L('FERTIG error')
    end

    -- verarbeitete Job-Datei aus jobs/ entfernen, damit der Ordner sauber bleibt
    LrFileUtils.delete(procPath)
end

-- Generationszähler: verhindert doppelte Watcher-Schleifen bei Plugin-Reload.
_G.RAWSelectGen = (_G.RAWSelectGen or 0) + 1
local myGen = _G.RAWSelectGen

LrTasks.startAsyncTask(function()
    ensureDir(jobsDir); ensureDir(doneDir); ensureDir(logDir)
    appendLog(LrPathUtils.child(logDir, 'watcher.log'),
              'Watcher gestartet (gen ' .. myGen .. ')  SDK=' ..
              tostring(LrApplication.versionString and LrApplication.versionString()))

    while _G.RAWSelectGen == myGen do
        for filePath in LrFileUtils.directoryEntries(jobsDir) do
            if LrPathUtils.extension(filePath) == 'job' then
                -- sofort reservieren, damit kein Doppelgriff passiert
                local procPath = filePath .. '.processing'
                local moved = LrFileUtils.move(filePath, procPath)
                if moved ~= false then
                    LrTasks.startAsyncTask(function()
                        -- LrTasks.pcall (yield-fest, im Gegensatz zum nackten pcall): ein
                        -- unerwarteter Fehler landet im Log, statt Lightroom einen modalen
                        -- "interner Fehler"-Dialog zeigen zu lassen. Der Job wird trotzdem
                        -- beantwortet und entfernt, damit die App nicht ewig wartet.
                        local ok, err = LrTasks.pcall(function() processJob(procPath) end)
                        if not ok then
                            local id = LrPathUtils.leafName(procPath):gsub('%.job%.processing$', '')
                            appendLog(LrPathUtils.child(logDir, 'watcher.log'),
                                      'Job-Fehler ' .. id .. ': ' .. tostring(err))
                            writeDone(id, 'error', '', tostring(err))
                            LrFileUtils.delete(procPath)
                        end
                    end)
                end
            end
        end
        LrTasks.sleep(2)
    end

    appendLog(LrPathUtils.child(logDir, 'watcher.log'), 'Watcher beendet (gen ' .. myGen .. ')')
end)
