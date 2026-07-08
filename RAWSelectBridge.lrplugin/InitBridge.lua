--[[
    RAW Select Bridge — background watcher.

    Protocol (must match Sources/RAWSelect/Services/LightroomExportService.swift):

      Spool root:  ~/Library/Application Support/RAW Select/LightroomBridge
        jobs/<id>.job   key=value request written atomically by the app
        done/<id>.done  key=value reply written atomically by this plugin

    A .job contains:
        id=RS_…
        raw=/abs/path/to/copy.ARW      (a temp copy; a <base>.xmp sidecar with the
                                         preset + exposure (+ noise reduction) sits
                                         next to it — Lightroom reads it on import)
        out=/abs/path/to/stage_dir     (folder to export the JPEG into)
        maxwidth=0                      (0 = no resize, else long-edge px)
        maxheight=0
        quality=0.92                    (0…1)
        colorspace=sRGB                 (sRGB | AdobeRGB | ProPhotoRGB)
        denoise=0                       (0…100; already baked into the sidecar)
        enhance=0                       (1 = the app requested AI Enhance-Denoise)

    A .done contains:
        status=ok|err
        path=/abs/path/to/exported.jpg  (on ok)
        message=…                        (on err)

    Note on "enhance": Adobe's AI Enhance-Denoise creates a new DNG and is NOT
    exposed to the SDK, so it cannot be triggered from Lua. The app therefore
    also writes strong Camera-Raw noise reduction into the sidecar, which this
    plugin applies on import/export — that is the effective denoise here.
]]

local LrTasks       = import 'LrTasks'
local LrPathUtils   = import 'LrPathUtils'
local LrFileUtils   = import 'LrFileUtils'
local LrApplication = import 'LrApplication'
local LrExportSession = import 'LrExportSession'

-- ---------------------------------------------------------------- paths / log

local home    = LrPathUtils.getStandardFilePath('home')
local base    = LrPathUtils.child(home, 'Library')
base          = LrPathUtils.child(base, 'Application Support')
base          = LrPathUtils.child(base, 'RAW Select')
base          = LrPathUtils.child(base, 'LightroomBridge')
local jobsDir = LrPathUtils.child(base, 'jobs')
local doneDir = LrPathUtils.child(base, 'done')
local logPath = LrPathUtils.child(base, 'bridge.log')

local function ensureDir(dir)
    if not LrFileUtils.exists(dir) then LrFileUtils.createAllDirectories(dir) end
end

local function log(msg)
    local f = io.open(logPath, 'a')
    if f then f:write(os.date('%Y-%m-%d %H:%M:%S ') .. tostring(msg) .. '\n'); f:close() end
end

-- ---------------------------------------------------------------- file helpers

local function readFile(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local data = f:read('*a'); f:close()
    return data
end

-- Atomic write: write .part then move into place so the app never reads a half file.
local function writeAtomic(path, contents)
    local tmp = path .. '.part'
    local f = io.open(tmp, 'w')
    if not f then return false end
    f:write(contents); f:close()
    if LrFileUtils.exists(path) then LrFileUtils.delete(path) end
    LrFileUtils.move(tmp, path)
    return true
end

local function parseJob(text)
    local job = {}
    for line in text:gmatch('[^\r\n]+') do
        local k, v = line:match('^(%w+)=(.*)$')
        if k then job[k] = v end
    end
    return job
end

local function writeDone(id, status, pathOrMsg)
    local body
    if status == 'ok' then
        body = 'status=ok\npath=' .. (pathOrMsg or '')
    else
        body = 'status=err\nmessage=' .. (pathOrMsg or 'unknown')
    end
    writeAtomic(LrPathUtils.child(doneDir, id .. '.done'), body)
end

-- ---------------------------------------------------------------- one job

local function exportJob(job)
    local catalog = LrApplication.activeCatalog()

    -- Import the temp RAW. Lightroom reads the <base>.xmp sidecar next to it, so
    -- the preset, exposure and noise reduction come along automatically.
    local photo
    catalog:withWriteAccessDo('RAW Select import', function()
        photo = catalog:addPhoto(job.raw)
    end, { timeout = 30 })

    if not photo then error('addPhoto returned nil for ' .. tostring(job.raw)) end

    local constrain = (tonumber(job.maxwidth) or 0) > 0
    local exportSettings = {
        LR_export_destinationType        = 'specificFolder',
        LR_export_destinationPathPrefix  = job.out,
        LR_export_useSubfolder           = false,
        LR_format                        = 'JPEG',
        LR_jpeg_quality                  = tonumber(job.quality) or 0.9,
        LR_jpeg_useLimitSize             = false,
        LR_export_colorSpace             = job.colorspace or 'sRGB',
        LR_size_doConstrain              = constrain,
        LR_size_maxWidth                 = tonumber(job.maxwidth) or 0,
        LR_size_maxHeight                = tonumber(job.maxheight) or 0,
        LR_size_units                    = 'pixels',
        LR_size_resolution               = 300,
        LR_size_resolutionUnits          = 'inch',
        LR_collisionHandling             = 'rename',
        LR_reimportExportedPhoto         = false,
        LR_embeddedMetadataOption        = 'all',
        LR_removeLocationMetadata        = false,
    }

    local session = LrExportSession({
        photosToExport = { photo },
        exportSettings = exportSettings,
    })
    session:doExportOnCurrentTask()

    local outPath
    for _, rendition in session:renditions() do
        outPath = rendition.destinationPath
    end
    if not outPath or not LrFileUtils.exists(outPath) then
        error('export produced no file in ' .. tostring(job.out))
    end
    return outPath
end

local function processJobFile(jobPath)
    local id = LrPathUtils.leafName(jobPath):gsub('%.job$', '')
    local text = readFile(jobPath)
    -- Consume the request first so we never process it twice.
    LrFileUtils.delete(jobPath)
    if not text then writeDone(id, 'err', 'could not read job'); return end

    local job = parseJob(text)
    if not job.id or not job.raw or not job.out then
        writeDone(id, 'err', 'malformed job'); return
    end

    local ok, result = LrTasks.pcall(function() return exportJob(job) end)
    if ok then
        log('OK ' .. id .. ' -> ' .. tostring(result))
        writeDone(id, 'ok', result)
    else
        log('ERR ' .. id .. ': ' .. tostring(result))
        writeDone(id, 'err', tostring(result))
    end
end

-- ---------------------------------------------------------------- watch loop

ensureDir(jobsDir)
ensureDir(doneDir)
log('RAW Select Bridge started; watching ' .. jobsDir)

LrTasks.startAsyncTask(function()
    while true do
        local ok, err = LrTasks.pcall(function()
            if LrFileUtils.exists(jobsDir) then
                for filePath in LrFileUtils.files(jobsDir) do
                    if filePath:sub(-4) == '.job' then
                        processJobFile(filePath)
                    end
                end
            end
        end)
        if not ok then log('watch loop error: ' .. tostring(err)) end
        LrTasks.sleep(1)   -- poll once per second
    end
end)
