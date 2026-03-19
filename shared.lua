local api = require("api")

local Shared = {}

Shared.CONSTANTS = {
    ADDON_ID = "polar-raid",
    TITLE = "Polar Raid",
    VERSION = "1.0.1",
    BUTTON_ID = "polarRaidSettingsButton",
    WINDOW_ID = "polarRaidSettingsWindow",
    SETTINGS_FILE_PATH = "polar-raid/settings.txt",
    SETTINGS_BACKUP_INDEX_FILE_PATH = "polar-raid/backups/index.txt",
    SETTINGS_BACKUP_INDEX_FALLBACK_FILE_PATH = "polar-raid/settings_backup_index.txt",
    SETTINGS_BACKUP_DIR = "polar-raid/backups",
    LEGACY_POLAR_UI_SETTINGS_PATH = "polar-ui/settings.txt"
}

Shared.DEFAULT_SETTINGS = {
    enabled = true,
    drag_requires_shift = true,
    button_x = 90,
    button_y = 420,
    role = {
        tanks = {
            "Abolisher",
            "Skullknight"
        },
        healers = {
            "Cleric",
            "Hierophant"
        }
    },
    style = {
        hp_texture_mode = "stock",
        bar_colors_enabled = false,
        hp_fill_color = { 223, 69, 69, 255 },
        hp_bar_color = { 223, 69, 69, 255 },
        hp_after_color = { 223, 69, 69, 255 },
        mp_fill_color = { 86, 198, 239, 255 },
        mp_bar_color = { 86, 198, 239, 255 },
        mp_after_color = { 86, 198, 239, 255 }
    },
    raidframes = {
        enabled = true,
        hide_stock = false,
        layout_mode = "party_columns",
        x = 600,
        y = 250,
        alpha_pct = 100,
        width = 80,
        hp_height = 16,
        mp_height = 0,
        name_font_size = 11,
        show_name = true,
        name_max_chars = 0,
        name_padding_left = 2,
        name_offset_x = 0,
        name_offset_y = 0,
        show_role_prefix = true,
        show_class_icon = true,
        icon_size = 12,
        icon_gap = 2,
        icon_offset_x = 0,
        icon_offset_y = 0,
        show_role_badge = false,
        hide_dps_role_badge = true,
        use_team_role_colors = true,
        use_role_name_colors = true,
        use_class_name_colors = false,
        show_value_text = false,
        value_text_mode = "percent",
        value_font_size = 10,
        value_offset_x = 0,
        value_offset_y = 0,
        show_status_text = true,
        range_fade_enabled = true,
        range_max_distance = 80,
        range_alpha_pct = 45,
        dead_alpha_pct = 30,
        offline_alpha_pct = 20,
        show_debuff_alert = true,
        prefer_dispel_alert = true,
        show_target_highlight = true,
        show_group_headers = true,
        group_header_font_size = 11,
        right_click_fallback_menu = true,
        bar_style_mode = "shared",
        gap_x = 2,
        gap_y = 2,
        grid_columns = 8,
        bg_enabled = false,
        bg_alpha_pct = 80
    }
}

Shared.state = {
    settings = nil
}

local function deepCopy(value, visited)
    if type(value) ~= "table" then
        return value
    end
    visited = visited or {}
    if visited[value] ~= nil then
        return visited[value]
    end
    local out = {}
    visited[value] = out
    for k, v in pairs(value) do
        out[deepCopy(k, visited)] = deepCopy(v, visited)
    end
    return out
end

local function mergeInto(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return
    end
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then
                dst[key] = {}
            end
            mergeInto(dst[key], value)
        else
            dst[key] = value
        end
    end
end

local function ensureDefaults(dst, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then
                dst[key] = deepCopy(value)
            else
                ensureDefaults(dst[key], value)
            end
        elseif dst[key] == nil then
            dst[key] = value
        end
    end
end

local function readTableFile(path)
    if api.File == nil or api.File.Read == nil then
        return nil
    end
    local ok, res = pcall(function()
        return api.File:Read(path)
    end)
    if ok and type(res) == "table" then
        return res
    end
    return nil
end

local function writeTableFile(path, tbl)
    if api.File == nil or api.File.Write == nil or type(tbl) ~= "table" then
        return false, "api.File:Write unavailable"
    end
    local ok, err = pcall(function()
        api.File:Write(path, tbl)
    end)
    if not ok then
        return false, tostring(err)
    end
    return true, ""
end

local function buildMigratedSettings(legacy)
    local out = deepCopy(Shared.DEFAULT_SETTINGS)
    if type(legacy) ~= "table" then
        return out, false
    end
    if type(legacy.raidframes) == "table" then
        mergeInto(out.raidframes, legacy.raidframes)
    end
    if type(legacy.style) == "table" then
        mergeInto(out.style, legacy.style)
    end
    if type(legacy.role) == "table" then
        mergeInto(out.role, legacy.role)
    end
    if legacy.drag_requires_shift ~= nil then
        out.drag_requires_shift = legacy.drag_requires_shift and true or false
    end
    out.migrated_from_polar_ui = true
    return out, true
end

function Shared.EnsureSettings()
    if type(Shared.state.settings) ~= "table" then
        Shared.state.settings = {}
    end
    ensureDefaults(Shared.state.settings, Shared.DEFAULT_SETTINGS)
    if type(Shared.state.settings.raidframes) ~= "table" then
        Shared.state.settings.raidframes = deepCopy(Shared.DEFAULT_SETTINGS.raidframes)
    end
    if type(Shared.state.settings.style) ~= "table" then
        Shared.state.settings.style = deepCopy(Shared.DEFAULT_SETTINGS.style)
    end
    if type(Shared.state.settings.role) ~= "table" then
        Shared.state.settings.role = deepCopy(Shared.DEFAULT_SETTINGS.role)
    end
    return Shared.state.settings
end

function Shared.GetSettings()
    return Shared.EnsureSettings()
end

function Shared.LoadSettings()
    local loaded = readTableFile(Shared.CONSTANTS.SETTINGS_FILE_PATH)
    local migrated = false
    if type(loaded) == "table" then
        Shared.state.settings = loaded
    else
        local legacy = readTableFile(Shared.CONSTANTS.LEGACY_POLAR_UI_SETTINGS_PATH)
        local migratedSettings, didMigrate = buildMigratedSettings(legacy)
        if didMigrate then
            Shared.state.settings = migratedSettings
            migrated = true
        elseif api.GetSettings ~= nil then
            Shared.state.settings = api.GetSettings(Shared.CONSTANTS.ADDON_ID) or {}
        else
            Shared.state.settings = {}
        end
    end
    Shared.EnsureSettings()
    if migrated then
        Shared.SaveSettings()
    end
    return Shared.state.settings
end

function Shared.ResetRaidSettings()
    Shared.EnsureSettings().raidframes = deepCopy(Shared.DEFAULT_SETTINGS.raidframes)
end

function Shared.ResetStyleSettings()
    Shared.EnsureSettings().style = deepCopy(Shared.DEFAULT_SETTINGS.style)
end

function Shared.ResetAllSettings()
    Shared.state.settings = deepCopy(Shared.DEFAULT_SETTINGS)
end

function Shared.SaveSettings()
    local settings = Shared.EnsureSettings()
    if api.SaveSettings ~= nil then
        pcall(function()
            api.SaveSettings()
        end)
    end
    return writeTableFile(Shared.CONSTANTS.SETTINGS_FILE_PATH, settings)
end

function Shared.SaveSettingsBackup()
    local settings = Shared.EnsureSettings()
    local ts = nil
    pcall(function()
        if api.Time ~= nil and api.Time.GetLocalTime ~= nil then
            ts = api.Time:GetLocalTime()
        end
    end)
    if ts == nil then
        ts = tostring(math.random(1000000000, 9999999999))
    end
    ts = tostring(ts)

    local backupPath = string.format("%s/settings_%s.txt", Shared.CONSTANTS.SETTINGS_BACKUP_DIR, ts)
    local ok, err = writeTableFile(backupPath, settings)
    if not ok then
        backupPath = string.format("polar-raid/settings_backup_%s.txt", ts)
        ok, err = writeTableFile(backupPath, settings)
        if not ok then
            return false, err
        end
    end

    local idx = readTableFile(Shared.CONSTANTS.SETTINGS_BACKUP_INDEX_FILE_PATH)
    if type(idx) ~= "table" then
        idx = readTableFile(Shared.CONSTANTS.SETTINGS_BACKUP_INDEX_FALLBACK_FILE_PATH)
    end
    if type(idx) ~= "table" then
        idx = { version = 1, backups = {} }
    end
    if type(idx.backups) ~= "table" then
        idx.backups = {}
    end
    table.insert(idx.backups, 1, { path = backupPath, timestamp = ts })

    local savedIndex, saveErr = writeTableFile(Shared.CONSTANTS.SETTINGS_BACKUP_INDEX_FILE_PATH, idx)
    if not savedIndex then
        savedIndex, saveErr = writeTableFile(Shared.CONSTANTS.SETTINGS_BACKUP_INDEX_FALLBACK_FILE_PATH, idx)
        if not savedIndex then
            return false, saveErr
        end
    end
    return true, backupPath
end

function Shared.ImportLatestBackup()
    local idx = readTableFile(Shared.CONSTANTS.SETTINGS_BACKUP_INDEX_FILE_PATH)
    if type(idx) ~= "table" then
        idx = readTableFile(Shared.CONSTANTS.SETTINGS_BACKUP_INDEX_FALLBACK_FILE_PATH)
    end
    if type(idx) ~= "table" or type(idx.backups) ~= "table" or idx.backups[1] == nil then
        return false, "No backup found"
    end

    local backup = idx.backups[1]
    local path = type(backup) == "table" and backup.path or nil
    if type(path) ~= "string" or path == "" then
        return false, "Backup path missing"
    end

    local loaded = readTableFile(path)
    if type(loaded) ~= "table" then
        return false, "Failed to read backup"
    end

    Shared.state.settings = loaded
    Shared.EnsureSettings()
    return Shared.SaveSettings()
end

return Shared
