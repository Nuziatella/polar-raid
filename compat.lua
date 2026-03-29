local api = require("api")

local Compat = {
    state = nil
}

local function hasFunction(tbl, key)
    return type(tbl) == "table" and type(tbl[key]) == "function"
end

local function append(list, value)
    list[#list + 1] = value
end

local function buildRuntimeLines(caps)
    local sliderText = caps.slider_factory and "Available" or "Unavailable"
    local raidManagerText = caps.stock_raid_manager and "Available" or "Unavailable"
    local targetFrameText = caps.stock_target_frame and "Available" or "Unavailable"
    return {
        string.format("Raid frames: %s", caps.raidframes_supported and "Supported" or "Blocked"),
        string.format("Raid manager: %s | Target frame: %s", raidManagerText, targetFrameText),
        string.format("Sliders: %s | Status bars: %s", sliderText, caps.statusbar_factory and "Available" or "Unavailable")
    }
end

function Compat.Probe(force)
    if Compat.state ~= nil and not force then
        return Compat.state
    end

    local caps = {
        create_window = hasFunction(api.Interface, "CreateWindow"),
        create_empty_window = hasFunction(api.Interface, "CreateEmptyWindow"),
        create_widget = hasFunction(api.Interface, "CreateWidget"),
        free_widget = hasFunction(api.Interface, "Free"),
        slider_factory = type(api._Library) == "table"
            and type(api._Library.UI) == "table"
            and type(api._Library.UI.CreateSlider) == "function",
        save_settings = type(api.SaveSettings) == "function",
        statusbar_factory = type(W_BAR) == "table" and type(W_BAR.CreateStatusBarOfRaidFrame) == "function",
        stock_raid_manager = ADDON ~= nil and type(ADDON.GetContent) == "function" and UIC ~= nil and UIC.RAID_MANAGER ~= nil,
        stock_target_frame = ADDON ~= nil and type(ADDON.GetContent) == "function" and UIC ~= nil and UIC.TARGET_UNITFRAME ~= nil,
        unit_id = hasFunction(api.Unit, "GetUnitId"),
        unit_name_by_id = hasFunction(api.Unit, "GetUnitNameById"),
        team_role = type(api.Team) == "table" and type(api.Team.GetRole) == "function"
    }

    local blockers = {}
    local warnings = {}

    if not caps.create_empty_window then
        append(blockers, "CreateEmptyWindow unavailable")
    end
    if not caps.create_widget then
        append(blockers, "CreateWidget unavailable")
    end
    if not caps.statusbar_factory then
        append(blockers, "W_BAR.CreateStatusBarOfRaidFrame unavailable")
    end

    if not caps.stock_raid_manager then
        append(warnings, "Stock raid manager content unavailable.")
    end
    if not caps.stock_target_frame then
        append(warnings, "Stock target frame content unavailable.")
    end
    if not caps.slider_factory then
        append(warnings, "Slider helper unavailable; settings UI uses reduced controls.")
    end

    caps.raidframes_supported = #blockers == 0

    Compat.state = {
        caps = caps,
        blockers = blockers,
        warnings = warnings,
        runtime_lines = buildRuntimeLines(caps)
    }
    return Compat.state
end

function Compat.Get()
    return Compat.Probe(false)
end

function Compat.GetStatusText()
    local state = Compat.Get()
    if #state.blockers > 0 then
        return "Runtime blocked: " .. table.concat(state.blockers, "; ")
    end
    if #state.warnings > 0 then
        return "Runtime warnings: " .. table.concat(state.warnings, " ")
    end
    return "Runtime OK"
end

function Compat.GetRuntimeLines()
    return Compat.Get().runtime_lines
end

return Compat
