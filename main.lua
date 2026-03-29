local api = require("api")

local function loadModule(name)
    local ok, mod = pcall(require, "polar-raid/" .. name)
    if ok then
        return mod
    end
    ok, mod = pcall(require, "polar-raid." .. name)
    if ok then
        return mod
    end
    return nil
end

local Shared = loadModule("shared")
local RaidFrames = loadModule("raidframes")
local SettingsUi = loadModule("settings_ui")
local Runtime = loadModule("runtime")
local Compat = loadModule("compat")

local addon = {
    name = "Polar Raid",
    author = "Nuzi",
    version = "1.1.3",
    desc = "Custom raid frames"
}

local vitalsElapsedMs = 0
local metadataElapsedMs = 0
local rosterElapsedMs = 0
local rosterForceElapsedMs = 0

local UPDATE_INTERVALS = {
    vitals_ms = 100,
    metadata_ms = 900,
    roster_ms = 500,
    force_roster_ms = 2000
}

local function logInfo(message)
    if api.Log ~= nil and api.Log.Info ~= nil then
        api.Log:Info("[Polar Raid] " .. tostring(message or ""))
    end
end

local function modulesReady()
    return Shared ~= nil and RaidFrames ~= nil and SettingsUi ~= nil and Runtime ~= nil and Compat ~= nil
end

local function logRuntimeSummary()
    local runtime = Compat.Get()
    local caps = runtime.caps or {}
    logInfo(string.format(
        "Runtime raidframes=%s sliders=%s raid_manager=%s target_frame=%s",
        caps.raidframes_supported and "yes" or "no",
        caps.slider_factory and "yes" or "no",
        caps.stock_raid_manager and "yes" or "no",
        caps.stock_target_frame and "yes" or "no"
    ))
    for _, warning in ipairs(runtime.warnings or {}) do
        logInfo(warning)
    end
    for _, blocker in ipairs(runtime.blockers or {}) do
        if api.Log ~= nil and api.Log.Err ~= nil then
            api.Log:Err("[Polar Raid] " .. tostring(blocker))
        end
    end
end

local function applyAll()
    local settings = Shared.GetSettings()
    RaidFrames.SetEnabled(settings.enabled)
    RaidFrames.OnUpdate(settings, {
        update_vitals = true,
        update_metadata = true,
        update_roster = true,
        force_roster = true,
        update_target = true
    })
    SettingsUi.Refresh()
end

local function buildActions()
    return {
        apply = function()
            applyAll()
            return true, "Applied"
        end,
        save = function()
            return Shared.SaveSettings()
        end,
        backup = function()
            return Shared.SaveSettingsBackup()
        end,
        import = function()
            local ok, detail = Shared.ImportLatestBackup()
            if ok then
                applyAll()
            end
            return ok, detail
        end,
        reset_raid = function()
            Shared.ResetRaidSettings()
            applyAll()
            return true, "Raid settings reset"
        end,
        reset_style = function()
            Shared.ResetStyleSettings()
            applyAll()
            return true, "Style settings reset"
        end,
        reset_all = function()
            Shared.ResetAllSettings()
            applyAll()
            return true, "All settings reset"
        end
    }
end

local function onUpdate(dt)
    local delta = tonumber(dt) or 0
    if delta < 0 then
        delta = 0
    end
    if delta < 5 then
        delta = delta * 1000
    end
    vitalsElapsedMs = vitalsElapsedMs + delta
    metadataElapsedMs = metadataElapsedMs + delta
    rosterElapsedMs = rosterElapsedMs + delta
    rosterForceElapsedMs = rosterForceElapsedMs + delta

    local updateVitals = vitalsElapsedMs >= UPDATE_INTERVALS.vitals_ms
    local updateMetadata = metadataElapsedMs >= UPDATE_INTERVALS.metadata_ms
    local updateRoster = rosterElapsedMs >= UPDATE_INTERVALS.roster_ms
    local forceRoster = rosterForceElapsedMs >= UPDATE_INTERVALS.force_roster_ms
    local updateTarget = updateVitals

    if not updateVitals and not updateMetadata and not updateRoster then
        return
    end

    if updateVitals then
        vitalsElapsedMs = 0
    end
    if updateMetadata then
        metadataElapsedMs = 0
    end
    if updateRoster then
        rosterElapsedMs = 0
    end
    if forceRoster then
        rosterForceElapsedMs = 0
    end
    local ok, err = pcall(function()
        RaidFrames.OnUpdate(Shared.GetSettings(), {
            update_vitals = updateVitals,
            update_metadata = updateMetadata,
            update_roster = updateRoster,
            force_roster = forceRoster,
            update_target = updateTarget
        })
    end)
    if not ok and api.Log ~= nil and api.Log.Err ~= nil then
        api.Log:Err("[Polar Raid] RaidFrames.OnUpdate failed: " .. tostring(err))
    end
end

local function onUiReloaded()
    vitalsElapsedMs = 0
    metadataElapsedMs = 0
    rosterElapsedMs = 0
    rosterForceElapsedMs = 0
    Compat.Probe(true)
    RaidFrames.Unload()
    SettingsUi.Unload()
    RaidFrames.Init(Shared.GetSettings())
    RaidFrames.SetEnabled(Shared.GetSettings().enabled)
    SettingsUi.Init(buildActions())
    applyAll()
end

local function onChatMessage(_, _, _, senderName, message)
    local raw = tostring(message or "")
    local playerName = Runtime.GetPlayerName()
    if playerName ~= nil and senderName ~= nil and tostring(senderName) ~= "" and tostring(senderName) ~= tostring(playerName) then
        return
    end
    if raw == "!pr" or raw == "!polarraid" then
        SettingsUi.Toggle()
    end
end

local function onLoad()
    if not modulesReady() then
        if api.Log ~= nil and api.Log.Err ~= nil then
            api.Log:Err("[Polar Raid] Failed to load one or more modules")
        end
        return
    end
    Shared.LoadSettings()
    Compat.Probe(true)
    logRuntimeSummary()
    RaidFrames.Init(Shared.GetSettings())
    RaidFrames.SetEnabled(Shared.GetSettings().enabled)
    SettingsUi.Init(buildActions())
    applyAll()
    api.On("UPDATE", onUpdate)
    api.On("UI_RELOADED", onUiReloaded)
    api.On("CHAT_MESSAGE", onChatMessage)
    pcall(function()
        api.On("COMMUNITY_CHAT_MESSAGE", onChatMessage)
    end)
    logInfo("Loaded v" .. tostring(addon.version) .. ". Use the PR button for settings.")
end

local function onUnload()
    api.On("UPDATE", function() end)
    api.On("UI_RELOADED", function() end)
    api.On("CHAT_MESSAGE", function() end)
    pcall(function()
        api.On("COMMUNITY_CHAT_MESSAGE", function() end)
    end)
    if RaidFrames ~= nil then
        RaidFrames.Unload()
    end
    if SettingsUi ~= nil then
        SettingsUi.Unload()
    end
end

addon.OnLoad = onLoad
addon.OnUnload = onUnload

return addon
