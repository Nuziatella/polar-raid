local api = require("api")

local Utils = nil
do
    local ok, mod = pcall(require, "polar-raid/overlay_utils")
    if ok then
        Utils = mod
    else
        ok, mod = pcall(require, "polar-raid.overlay_utils")
        if ok then
            Utils = mod
        end
    end
end

local function BuildLayoutKey(cfg)
    if type(cfg) ~= "table" then
        return ""
    end
    return table.concat({
        tostring(cfg.width),
        tostring(cfg.hp_height),
        tostring(cfg.mp_height),
        tostring(cfg.name_font_size),
        tostring(cfg.name_padding_left),
        tostring(cfg.name_offset_x),
        tostring(cfg.name_offset_y),
        tostring(cfg.show_name),
        tostring(cfg.show_value_text),
        tostring(cfg.value_text_mode),
        tostring(cfg.value_font_size),
        tostring(cfg.value_offset_x),
        tostring(cfg.value_offset_y),
        tostring(cfg.show_status_text),
        tostring(cfg.use_role_name_colors),
        tostring(cfg.use_class_name_colors),
        tostring(cfg.show_target_highlight),
        tostring(cfg.show_debuff_alert),
        tostring(cfg.prefer_dispel_alert),
        tostring(cfg.show_group_headers),
        tostring(cfg.group_header_font_size),
        tostring(cfg.bar_style_mode),
        tostring(cfg.icon_size),
        tostring(cfg.icon_gap),
        tostring(cfg.icon_offset_x),
        tostring(cfg.icon_offset_y),
        tostring(cfg.show_class_icon),
        tostring(cfg.show_role_badge),
        tostring(cfg.hide_dps_role_badge)
    }, "|")
end

local function ColorKey(rgba)
    if type(rgba) ~= "table" then
        return ""
    end
    return table.concat({
        tostring(rgba[1] or ""),
        tostring(rgba[2] or ""),
        tostring(rgba[3] or ""),
        tostring(rgba[4] or "")
    }, ",")
end

local function BuildBarStyleKey(settings, teamRoleKey)
    local cfg = type(settings) == "table" and settings.raidframes or nil
    local style = type(settings) == "table" and settings.style or nil
    return table.concat({
        tostring(cfg ~= nil and cfg.bar_style_mode or ""),
        tostring(cfg ~= nil and cfg.use_team_role_colors or ""),
        tostring(teamRoleKey or ""),
        tostring(style ~= nil and style.hp_texture_mode or ""),
        tostring(style ~= nil and style.bar_colors_enabled or ""),
        ColorKey(style ~= nil and (style.hp_fill_color or style.hp_bar_color) or nil),
        ColorKey(style ~= nil and (style.mp_fill_color or style.mp_bar_color) or nil)
    }, "|")
end

local RaidFrames = {
    settings = nil,
    enabled = false,
    container = nil,
    frames = {},
    group_headers = {},
    group_header_bgs = {},
    target_unitframe = nil,
    tried_hide_stock = false,
    last_roster_force_refresh_ms = 0,
    now_ms = 0,
    context_menu = nil,
    current_target_id = nil
}

if Utils == nil then
    error("[Polar Raid] overlay_utils unavailable")
end

local ClampNumber = Utils.ClampNumber
local Percent01 = Utils.Percent01
local SafeShow = Utils.SafeShow
local SafeClickable = Utils.SafeClickable
local SafeSetAlpha = Utils.SafeSetAlpha
local SafeSetBg = Utils.SafeSetBg

local STOCK_NAME_CACHE = {
    last_refresh_ms = 0,
    map = {},
    id_map = {},
    member_map = {},
    id_member_map = {}
}

local function LookupNameFromStockCache(unit, unitId)
    if type(unit) ~= "string" then
        return nil
    end
    local name = STOCK_NAME_CACHE.map ~= nil and STOCK_NAME_CACHE.map[unit] or nil
    if name ~= nil and tostring(name) ~= "" then
        return tostring(name)
    end

    if unitId ~= nil and STOCK_NAME_CACHE.id_map ~= nil then
        local idName = STOCK_NAME_CACHE.id_map[tostring(unitId)]
        if idName ~= nil and tostring(idName) ~= "" then
            return tostring(idName)
        end
    end
    return nil
end

local function ClearStockNameCache(now)
    STOCK_NAME_CACHE.map = {}
    STOCK_NAME_CACHE.id_map = {}
    STOCK_NAME_CACHE.member_map = {}
    STOCK_NAME_CACHE.id_member_map = {}
    STOCK_NAME_CACHE.last_refresh_ms = tonumber(now) or 0
end

local function NowMs()
    if api.Time ~= nil and api.Time.GetUiMsec ~= nil then
        local ok, res = pcall(function()
            return api.Time:GetUiMsec()
        end)
        if ok and type(res) == "number" then
            return res
        end
    end
    return 0
end

local function SafeGetStockRaidManager()
    if ADDON == nil or ADDON.GetContent == nil or UIC == nil or UIC.RAID_MANAGER == nil then
        return nil
    end
    local ok, res = pcall(function()
        return ADDON:GetContent(UIC.RAID_MANAGER)
    end)
    if ok then
        return res
    end
    return nil
end

local function SafeWidgetGetText(widget)
    if widget == nil then
        return nil
    end
    local wt = type(widget)
    if wt ~= "table" and wt ~= "userdata" then
        return nil
    end
    if widget.GetText == nil then
        return nil
    end
    local ok, res = pcall(function()
        return widget:GetText()
    end)
    if ok and res ~= nil and tostring(res) ~= "" then
        return tostring(res)
    end
    return nil
end

local function UpdateCachedText(owner, key, widget, text)
    if owner == nil or widget == nil or widget.SetText == nil then
        return
    end
    local value = tostring(text or "")
    if owner[key] == value then
        return
    end
    owner[key] = value
    pcall(function()
        widget:SetText(value)
    end)
end

local function UpdateCachedLabelColor(owner, key, label, rgba)
    if owner == nil or label == nil or label.style == nil or label.style.SetColor == nil then
        return
    end
    local cacheKey = ColorKey(rgba)
    if owner[key] == cacheKey then
        return
    end
    owner[key] = cacheKey
    pcall(function()
        local function c(index)
            local n = tonumber(rgba[index])
            if n == nil then
                n = 255
            end
            if n < 0 then
                n = 0
            elseif n > 255 then
                n = 255
            end
            return n / 255
        end
        label.style:SetColor(
            c(1),
            c(2),
            c(3),
            c(4)
        )
    end)
end

local function UpdateCachedVisible(owner, key, widget, show)
    if owner == nil or widget == nil then
        return
    end
    local visible = show and true or false
    if owner[key] == visible then
        return
    end
    owner[key] = visible
    pcall(function()
        if widget.SetVisible ~= nil then
            widget:SetVisible(visible)
        elseif widget.Show ~= nil then
            widget:Show(visible)
        end
    end)
end

local function ExtractNameFromStockMember(member)
    if type(member) ~= "table" then
        return nil
    end

    if type(member.name) == "string" and member.name ~= "" then
        return member.name
    end
    if type(member.unitName) == "string" and member.unitName ~= "" then
        return member.unitName
    end
    if type(member.characterName) == "string" and member.characterName ~= "" then
        return member.characterName
    end
    if type(member.nickName) == "string" and member.nickName ~= "" then
        return member.nickName
    end

    local candidates = {
        member.nameLabel,
        member.name_label,
        member.name,
        member.charNameLabel,
        member.characterNameLabel,
        member.nickNameLabel
    }
    for _, w in ipairs(candidates) do
        local t = SafeWidgetGetText(w)
        if t ~= nil then
            return t
        end
    end

    for k, v in pairs(member) do
        if type(k) == "string" and string.find(string.lower(k), "name") ~= nil then
            if type(v) == "string" and v ~= "" then
                return v
            end
            local t = SafeWidgetGetText(v)
            if t ~= nil then
                return t
            end
        end
    end

    return nil
end

local function ExtractUnitTokenFromStockMember(member)
    if type(member) ~= "table" then
        return nil
    end
    local tok = member.unit or member.target or member.unitToken or member.unittoken
    if tok == nil then
        return nil
    end
    if type(tok) == "string" then
        if tok == "" then
            return nil
        end
        return tok
    end
    if type(tok) == "number" then
        return tok
    end
    return nil
end

local function RefreshStockNameCache(force)
    local now = NowMs()
    if not force and now > 0 and (now - (STOCK_NAME_CACHE.last_refresh_ms or 0)) < 500 then
        return
    end

    local rm = SafeGetStockRaidManager()
    if rm == nil or type(rm.party) ~= "table" then
        if force then
            local last = tonumber(STOCK_NAME_CACHE.last_refresh_ms) or 0
            if now == 0 or (now - last) > 2000 then
                ClearStockNameCache(now)
            end
        end
        return
    end

    local out = {}
    local outId = {}
    local outMembers = {}
    local outIdMembers = {}

    local function ingestMember(member)
        if type(member) ~= "table" then
            return
        end
        local unitTok = ExtractUnitTokenFromStockMember(member)
        if unitTok == nil then
            return
        end
        local nm = ExtractNameFromStockMember(member)
        if nm ~= nil and nm ~= "" then
            if type(unitTok) == "string" and string.find(unitTok, "team") == 1 then
                out[unitTok] = nm
                outMembers[unitTok] = member
            else
                outId[tostring(unitTok)] = nm
                outIdMembers[tostring(unitTok)] = member
            end
        end
    end

    for _, group in pairs(rm.party) do
        if type(group) == "table" then
            if type(group.member) == "table" then
                for _, member in pairs(group.member) do
                    ingestMember(member)
                end
            elseif type(group.members) == "table" then
                for _, member in pairs(group.members) do
                    ingestMember(member)
                end
            else
                for _, member in pairs(group) do
                    ingestMember(member)
                end
            end
        end
    end

    local function hasAny(tbl)
        if type(tbl) ~= "table" then
            return false
        end
        for _, _ in pairs(tbl) do
            return true
        end
        return false
    end

    if hasAny(out) or hasAny(outId) then
        STOCK_NAME_CACHE.map = out
        STOCK_NAME_CACHE.id_map = outId
        STOCK_NAME_CACHE.member_map = outMembers
        STOCK_NAME_CACHE.id_member_map = outIdMembers
        STOCK_NAME_CACHE.last_refresh_ms = now
    elseif force then
        ClearStockNameCache(now)
    end
end

local function GetNameFromStockRoster(unit)
    if type(unit) ~= "string" then
        return nil
    end
    RefreshStockNameCache(false)
    local name = STOCK_NAME_CACHE.map ~= nil and STOCK_NAME_CACHE.map[unit] or nil
    if name ~= nil and tostring(name) ~= "" then
        return tostring(name)
    end

    local idName = nil
    pcall(function()
        if api.Unit ~= nil and api.Unit.GetUnitId ~= nil then
            local uid = api.Unit:GetUnitId(unit)
            if uid ~= nil and STOCK_NAME_CACHE.id_map ~= nil then
                idName = STOCK_NAME_CACHE.id_map[tostring(uid)]
            end
        end
    end)
    if idName ~= nil and tostring(idName) ~= "" then
        return tostring(idName)
    end

    RefreshStockNameCache(true)
    name = STOCK_NAME_CACHE.map ~= nil and STOCK_NAME_CACHE.map[unit] or nil
    if name ~= nil and tostring(name) ~= "" then
        return tostring(name)
    end

    idName = nil
    pcall(function()
        if api.Unit ~= nil and api.Unit.GetUnitId ~= nil then
            local uid = api.Unit:GetUnitId(unit)
            if uid ~= nil and STOCK_NAME_CACHE.id_map ~= nil then
                idName = STOCK_NAME_CACHE.id_map[tostring(uid)]
            end
        end
    end)
    if idName ~= nil and tostring(idName) ~= "" then
        return tostring(idName)
    end
    return nil
end

local function GetStockMember(unit, unitId)
    RefreshStockNameCache(false)

    if type(unit) == "string" and STOCK_NAME_CACHE.member_map ~= nil then
        local member = STOCK_NAME_CACHE.member_map[unit]
        if type(member) == "table" then
            return member
        end
    end

    if unitId ~= nil and STOCK_NAME_CACHE.id_member_map ~= nil then
        local member = STOCK_NAME_CACHE.id_member_map[tostring(unitId)]
        if type(member) == "table" then
            return member
        end
    end

    RefreshStockNameCache(true)

    if type(unit) == "string" and STOCK_NAME_CACHE.member_map ~= nil then
        local member = STOCK_NAME_CACHE.member_map[unit]
        if type(member) == "table" then
            return member
        end
    end

    if unitId ~= nil and STOCK_NAME_CACHE.id_member_map ~= nil then
        local member = STOCK_NAME_CACHE.id_member_map[tostring(unitId)]
        if type(member) == "table" then
            return member
        end
    end

    return nil
end

local function ExtractTeamIndex(unit)
    if type(unit) ~= "string" then
        return nil
    end
    local match = string.match(unit, "^team(%d+)$")
    if match == nil then
        return nil
    end
    return tonumber(match)
end

local function BuildActiveTeamUnits(maxCount)
    local units = {}
    local seen = {}
    if type(STOCK_NAME_CACHE.member_map) == "table" then
        for unit, member in pairs(STOCK_NAME_CACHE.member_map) do
            if type(member) == "table" then
                local idx = ExtractTeamIndex(unit)
                if idx ~= nil and idx >= 1 and idx <= maxCount then
                    table.insert(units, { unit = unit, idx = idx })
                    seen[unit] = true
                end
            end
        end
    end
    table.sort(units, function(a, b)
        return (a.idx or 0) < (b.idx or 0)
    end)
    if #units > 0 then
        return units, seen
    end
    for i = 1, maxCount do
        local unit = string.format("team%d", i)
        table.insert(units, { unit = unit, idx = i })
        seen[unit] = true
    end
    return units, seen
end

local function BuildUnitIdCandidates(id)
    if id == nil then
        return {}
    end

    local out = {}
    local seen = {}

    local function add(v)
        if v == nil then
            return
        end
        local k = type(v) .. ":" .. tostring(v)
        if seen[k] then
            return
        end
        seen[k] = true
        table.insert(out, v)
    end

    add(id)

    if type(id) == "number" then
        add(tostring(id))
    elseif type(id) == "string" then
        add(tostring(id))
        add(tonumber(id))
        add(tonumber(id, 16))
    end

    return out
end

local function SafeGetUnitNameById(id)
    if api.Unit == nil or api.Unit.GetUnitNameById == nil or id == nil then
        return nil
    end

    for _, candidate in ipairs(BuildUnitIdCandidates(id)) do
        local ok, res = pcall(function()
            return api.Unit:GetUnitNameById(candidate)
        end)
        if ok and res ~= nil and tostring(res) ~= "" then
            return res
        end
    end
    return nil
end

local function SafeGetUnitInfoById(id)
    if api.Unit == nil or api.Unit.GetUnitInfoById == nil or id == nil then
        return nil
    end

    for _, candidate in ipairs(BuildUnitIdCandidates(id)) do
        local ok, res = pcall(function()
            return api.Unit:GetUnitInfoById(candidate)
        end)
        if ok and res ~= nil then
            return res
        end
    end
    return nil
end

local function InList(list, value)
    if type(list) ~= "table" or value == nil then
        return false
    end
    for _, v in ipairs(list) do
        if tostring(v) == tostring(value) then
            return true
        end
    end
    return false
end

local function ChangeTarget(unit)
    local tu = RaidFrames.target_unitframe
    if tu == nil or tu.eventWindow == nil or tu.eventWindow.OnClick == nil then
        return
    end

    pcall(function()
        tu.target = unit
        tu.eventWindow:OnClick("LeftButton")
        tu.target = "target"
        if tu.ChangedTarget ~= nil then
            tu:ChangedTarget()
        end
        if tu.UpdateAll ~= nil then
            tu:UpdateAll()
        end
    end)
end

local function GetRoleForClass(settings, className)
    if type(settings) ~= "table" or type(settings.role) ~= "table" then
        return "dps"
    end
    if InList(settings.role.tanks, className) then
        return "tank"
    end
    if InList(settings.role.healers, className) then
        return "healer"
    end
    return "dps"
end

local TEAM_ROLE_COLORS = {
    defender = { 255, 210, 70, 255 },
    healer = { 255, 120, 205, 255 },
    attacker = { 255, 95, 95, 255 },
    undecided = { 110, 170, 255, 255 }
}

local function GetTeamRoleKeyFromId(roleId)
    roleId = tonumber(roleId)
    if roleId == nil then
        return nil
    end
    if roleId == 0 then
        return "undecided"
    end
    if roleId == 1 then
        return "defender"
    end
    if roleId == 2 then
        return "attacker"
    end
    if roleId == 3 then
        return "healer"
    end
    return nil
end

local function GetTeamRoleKeyFromStockMember(member)
    if type(member) ~= "table" then
        return nil
    end
    local stringCandidates = {
        member.roleName,
        member.role_name,
        member.role,
        member.teamRole,
        member.team_role
    }
    for _, value in ipairs(stringCandidates) do
        if type(value) == "string" and value ~= "" then
            local lowered = string.lower(value)
            if string.find(lowered, "defend", 1, true) ~= nil then
                return "defender"
            end
            if string.find(lowered, "heal", 1, true) ~= nil then
                return "healer"
            end
            if string.find(lowered, "attack", 1, true) ~= nil then
                return "attacker"
            end
            if string.find(lowered, "undec", 1, true) ~= nil or string.find(lowered, "blue", 1, true) ~= nil then
                return "undecided"
            end
        end
    end

    local numericCandidates = {
        member.roleId,
        member.role_id,
        member.teamRoleId,
        member.team_role_id,
        member.role
    }
    for _, value in ipairs(numericCandidates) do
        local key = GetTeamRoleKeyFromId(value)
        if key ~= nil then
            return key
        end
    end
    return nil
end

local function GetTeamRoleKey(unit, name, stockMember)
    local fromMember = GetTeamRoleKeyFromStockMember(stockMember)
    if fromMember ~= nil then
        return fromMember
    end

    if api.Team == nil or api.Team.GetMemberIndexByName == nil or api.Team.GetRole == nil then
        return nil
    end

    local memberName = tostring(name or "")
    if memberName == "" then
        memberName = tostring(GetNameFromStockRoster(unit) or "")
    end
    if memberName == "" then
        return nil
    end

    local memberIndex = nil
    pcall(function()
        memberIndex = api.Team:GetMemberIndexByName(memberName)
    end)
    if memberIndex == nil then
        return nil
    end

    local roleId = nil
    pcall(function()
        roleId = api.Team:GetRole(memberIndex)
    end)
    return GetTeamRoleKeyFromId(roleId)
end

local function GetRoleColor(role, teamRoleKey)
    if teamRoleKey ~= nil and TEAM_ROLE_COLORS[teamRoleKey] ~= nil then
        return TEAM_ROLE_COLORS[teamRoleKey]
    end
    return ROLE_TEXT_COLORS[tostring(role or "dps")] or ROLE_TEXT_COLORS.dps
end

local function FormatUnitName(name, maxChars)
    local s = tostring(name or "")
    local maxN = tonumber(maxChars)
    if maxN == nil or maxN < 1 then
        return s
    end
    if string.len(s) <= maxN then
        return s
    end
    return string.sub(s, 1, maxN)
end

local function GetSkillsetIdFromClassTable(unitClassTable)
    if type(unitClassTable) ~= "table" then
        return nil
    end

    local function hasValue(tbl, checkFor)
        for _, value in pairs(tbl) do
            if value == checkFor then
                return true
            end
        end
        return false
    end

    if hasValue(unitClassTable, 6) then
        return 6
    end
    if hasValue(unitClassTable, 10) then
        return 10
    end
    if hasValue(unitClassTable, 7) then
        return 7
    end
    if hasValue(unitClassTable, 1) then
        return 1
    end
    if hasValue(unitClassTable, 3) then
        return 3
    end
    return nil
end

local function GetSkillsetIconCoords(skillsetId)
    local size = 12
    if type(skillsetId) ~= "number" or skillsetId < 1 or skillsetId > 10 then
        return nil
    end
    local coords = {
        {480, 498, size, size},
        {534, 483, size, size},
        {492, 498, size, size},
        {510, 483, size, size},
        {522, 471, size, size},
        {528, 454, size, size},
        {504, 498, size, size},
        {522, 483, size, size},
        {534, 471, size, size},
        {510, 471, size, size}
    }
    return coords[skillsetId]
end

local function SetRoleBadgeColor(drawable, role, teamRoleKey)
    if drawable == nil or drawable.SetColor == nil then
        return
    end
    if teamRoleKey ~= nil and TEAM_ROLE_COLORS[teamRoleKey] ~= nil then
        local rgba = TEAM_ROLE_COLORS[teamRoleKey]
        drawable:SetColor(
            (tonumber(rgba[1]) or 255) / 255,
            (tonumber(rgba[2]) or 255) / 255,
            (tonumber(rgba[3]) or 255) / 255,
            (tonumber(rgba[4]) or 255) / 255
        )
        return
    end
    if role == "tank" then
        drawable:SetColor(0.1, 1, 0.1, 1)
    elseif role == "healer" then
        drawable:SetColor(1, 0.35, 0.8, 1)
    else
        drawable:SetColor(1, 0.15, 0.15, 1)
    end
end

local function Color01From255(v, fallback)
    local n = tonumber(v)
    if n == nil then
        n = tonumber(fallback)
    end
    if n == nil then
        n = 255
    end
    if n < 0 then
        n = 0
    elseif n > 255 then
        n = 255
    end
    return n / 255
end

local function ApplyLabelColor(label, rgba)
    if label == nil or label.style == nil or type(rgba) ~= "table" then
        return
    end
    pcall(function()
        label.style:SetColor(
            Color01From255(rgba[1], 255),
            Color01From255(rgba[2], 255),
            Color01From255(rgba[3], 255),
            Color01From255(rgba[4], 255)
        )
    end)
end

local ROLE_TEXT_COLORS = {
    tank = { 60, 220, 90, 255 },
    healer = { 255, 110, 205, 255 },
    dps = { 255, 90, 90, 255 }
}

local SKILLSET_TEXT_COLORS = {
    [1] = { 255, 150, 90, 255 },
    [3] = { 255, 205, 95, 255 },
    [6] = { 110, 255, 155, 255 },
    [7] = { 120, 180, 255, 255 },
    [10] = { 205, 135, 255, 255 }
}

local function GetClassColor(classTable)
    local skillsetId = GetSkillsetIdFromClassTable(classTable)
    return SKILLSET_TEXT_COLORS[skillsetId]
end

local function SafeUnitDistance(unit)
    if api.Unit == nil or api.Unit.UnitDistance == nil then
        return nil
    end
    local ok, distance = pcall(function()
        return api.Unit:UnitDistance(unit)
    end)
    if ok and type(distance) == "number" then
        return distance
    end
    return nil
end

local AnalyzeDebuffs

local function GetCachedDistance(frame, unit)
    if frame == nil then
        return SafeUnitDistance(unit)
    end
    local now = tonumber(RaidFrames.now_ms) or 0
    local last = tonumber(frame.__polar_last_distance_ms) or 0
    if frame.__polar_cached_distance ~= nil and now > 0 and last > 0 and (now - last) < 250 then
        return frame.__polar_cached_distance
    end
    local distance = SafeUnitDistance(unit)
    frame.__polar_cached_distance = distance
    frame.__polar_last_distance_ms = now
    return distance
end

local function GetCachedDebuffInfo(frame, unit, force)
    if frame == nil then
        return AnalyzeDebuffs(unit)
    end
    local now = tonumber(RaidFrames.now_ms) or 0
    local last = tonumber(frame.__polar_last_debuff_ms) or 0
    if not force and type(frame.__polar_cached_debuff_info) == "table" and now > 0 and last > 0 and (now - last) < 400 then
        return frame.__polar_cached_debuff_info
    end
    local info = AnalyzeDebuffs(unit)
    frame.__polar_cached_debuff_info = info
    frame.__polar_last_debuff_ms = now
    return info
end

local function SafeUnitIsOffline(unit)
    if api.Unit == nil or api.Unit.UnitIsOffline == nil then
        return false
    end
    local ok, offline = pcall(function()
        return api.Unit:UnitIsOffline(unit)
    end)
    return ok and offline and true or false
end

local function TableHasTruthyMatch(tbl, patterns, depth)
    if type(tbl) ~= "table" then
        return false
    end
    depth = tonumber(depth) or 1
    if depth < 0 then
        return false
    end
    for k, v in pairs(tbl) do
        local key = string.lower(tostring(k or ""))
        local matched = false
        for _, pattern in ipairs(patterns or {}) do
            if string.find(key, pattern, 1, true) ~= nil then
                matched = true
                break
            end
        end
        if matched then
            if v == true then
                return true
            end
            if type(v) == "number" and v ~= 0 then
                return true
            end
            if type(v) == "string" then
                local s = string.lower(v)
                if s == "true" or s == "yes" or s == "1" then
                    return true
                end
            end
        end
        if depth > 0 and type(v) == "table" and TableHasTruthyMatch(v, patterns, depth - 1) then
            return true
        end
    end
    return false
end

local function EffectLooksDispellable(effect)
    return TableHasTruthyMatch(effect, { "dispel", "dispell", "cleanse", "cure", "purge", "remove" }, 2)
end

AnalyzeDebuffs = function(unit)
    local out = {
        count = 0,
        dispellable = false
    }
    if api.Unit == nil or api.Unit.UnitDeBuffCount == nil or api.Unit.UnitDeBuff == nil then
        return out
    end

    local ok = pcall(function()
        local count = tonumber(api.Unit:UnitDeBuffCount(unit)) or 0
        out.count = count
        for i = 1, count do
            local debuff = api.Unit:UnitDeBuff(unit, i)
            if EffectLooksDispellable(debuff) then
                out.dispellable = true
                break
            end
        end
    end)
    if not ok then
        out.count = 0
        out.dispellable = false
    end
    return out
end

local function GetUnitState(info, modifier, hp, maxHp, offline)
    local dead = false
    if not offline and tonumber(maxHp) ~= nil and tonumber(maxHp) > 0 and tonumber(hp) ~= nil and tonumber(hp) <= 0 then
        dead = true
    end
    if not dead then
        dead = TableHasTruthyMatch(info, { "dead", "death", "ghost" }, 1)
            or TableHasTruthyMatch(modifier, { "dead", "death", "ghost" }, 1)
    end
    return {
        offline = offline and true or false,
        dead = dead and true or false
    }
end

local function GetValueText(mode, cur, max, kind)
    cur = tonumber(cur) or 0
    max = tonumber(max) or 0
    mode = tostring(mode or "percent")
    kind = tostring(kind or "hp")
    if max < 0 then
        max = 0
    end

    if mode == "curmax" then
        return string.format("%d/%d", math.floor(cur + 0.5), math.floor(max + 0.5))
    end
    if mode == "missing" and kind == "hp" then
        local missing = max - cur
        if missing < 0 then
            missing = 0
        end
        return string.format("-%d", math.floor(missing + 0.5))
    end
    if max <= 0 then
        return "0%"
    end
    return string.format("%d%%", math.floor(((cur / max) * 100) + 0.5))
end

local function ShouldShowUnit(unit, cfg)
    if unit == nil or type(cfg) ~= "table" then
        return false
    end
    if string.match(unit, "^team%d+$") then
        return cfg.enabled and true or false
    end
    return false
end

local function EnsureFrame(container, unit)
    if RaidFrames.frames[unit] ~= nil then
        return RaidFrames.frames[unit]
    end

    local frame_id = "polarRaidFrame_" .. unit
    local frame = api.Interface:CreateEmptyWindow(frame_id)
    if frame == nil then
        return nil
    end
    pcall(function()
        if frame.SetUILayer ~= nil then
            frame:SetUILayer("hud")
        end
    end)
    SafeClickable(frame, false)
    SafeShow(frame, false)

    pcall(function()
        frame:RemoveAllAnchors()
        frame:AddAnchor("TOPLEFT", container, 0, 0)
    end)

    local bg = nil
    pcall(function()
        if frame.CreateNinePartDrawable ~= nil and TEXTURE_PATH ~= nil and TEXTURE_PATH.RAID ~= nil then
            bg = frame:CreateNinePartDrawable(TEXTURE_PATH.RAID, "background")
            bg:SetCoords(33, 141, 7, 7)
            bg:SetInset(3, 3, 3, 3)
            bg:SetColor(1, 1, 1, 0.8)
            bg:Show(false)
        end
    end)
    frame.bg = bg

    local hp_bar = nil
    local mp_bar = nil
    pcall(function()
        if W_BAR ~= nil and W_BAR.CreateStatusBarOfRaidFrame ~= nil then
            hp_bar = W_BAR.CreateStatusBarOfRaidFrame(frame_id .. ".hpBar", frame)
            hp_bar:Show(true)
            hp_bar:Clickable(false)
            if hp_bar.statusBar ~= nil and hp_bar.statusBar.Clickable ~= nil then
                hp_bar.statusBar:Clickable(false)
            end
            if STATUSBAR_STYLE ~= nil and STATUSBAR_STYLE.HP_RAID ~= nil then
                hp_bar:ApplyBarTexture(STATUSBAR_STYLE.HP_RAID)
            end

            mp_bar = W_BAR.CreateStatusBarOfRaidFrame(frame_id .. ".mpBar", frame)
            mp_bar:Show(true)
            mp_bar:Clickable(false)
            if mp_bar.statusBar ~= nil and mp_bar.statusBar.Clickable ~= nil then
                mp_bar.statusBar:Clickable(false)
            end
            if STATUSBAR_STYLE ~= nil and STATUSBAR_STYLE.MP_RAID ~= nil then
                mp_bar:ApplyBarTexture(STATUSBAR_STYLE.MP_RAID)
            end
        end
    end)
    frame.hpBar = hp_bar
    frame.mpBar = mp_bar

    local name_label = api.Interface:CreateWidget("label", frame_id .. ".name", frame)
    pcall(function()
        name_label:Show(true)
        if name_label.Clickable ~= nil then
            name_label:Clickable(false)
        end
        if name_label.SetLimitWidth ~= nil then
            name_label:SetLimitWidth(true)
        end
        if name_label.SetExtent ~= nil then
            local fs = FONT_SIZE and FONT_SIZE.SMALL or 11
            name_label:SetExtent(220, fs + 6)
        end
        if name_label.style ~= nil then
            name_label.style:SetAlign(ALIGN.LEFT)
            name_label.style:SetFontSize(FONT_SIZE and FONT_SIZE.SMALL or 11)
            name_label.style:SetColor(1, 1, 1, 1)
        end
        name_label:AddAnchor("LEFT", frame, 0, 0)
    end)
    frame.nameLabel = name_label

    local classIcon = nil
    pcall(function()
        if frame.CreateImageDrawable ~= nil and TEXTURE_PATH ~= nil and TEXTURE_PATH.HUD ~= nil then
            classIcon = frame:CreateImageDrawable(TEXTURE_PATH.HUD, "overlay")
            classIcon:SetVisible(false)
        end
    end)
    frame.classIcon = classIcon

    local roleBadge = nil
    pcall(function()
        if frame.CreateImageDrawable ~= nil then
            roleBadge = frame:CreateImageDrawable("Textures/Defaults/White.dds", "overlay")
            roleBadge:SetVisible(false)
        end
    end)
    frame.roleBadge = roleBadge

    local targetHighlight = nil
    pcall(function()
        if frame.CreateImageDrawable ~= nil then
            targetHighlight = frame:CreateImageDrawable("Textures/Defaults/White.dds", "overlay")
            targetHighlight:SetVisible(false)
            targetHighlight:SetColor(1, 0.9, 0.15, 0.35)
        end
    end)
    frame.targetHighlight = targetHighlight

    local debuffBadge = nil
    pcall(function()
        if frame.CreateImageDrawable ~= nil then
            debuffBadge = frame:CreateImageDrawable("Textures/Defaults/White.dds", "overlay")
            debuffBadge:SetVisible(false)
        end
    end)
    frame.debuffBadge = debuffBadge

    local hpText = api.Interface:CreateWidget("label", frame_id .. ".hpText", frame)
    pcall(function()
        hpText:Show(false)
        if hpText.Clickable ~= nil then
            hpText:Clickable(false)
        end
        if hpText.style ~= nil then
            hpText.style:SetAlign(ALIGN.CENTER)
            hpText.style:SetFontSize(FONT_SIZE and FONT_SIZE.SMALL or 10)
            hpText.style:SetColor(1, 1, 1, 1)
        end
    end)
    frame.hpText = hpText

    local mpText = api.Interface:CreateWidget("label", frame_id .. ".mpText", frame)
    pcall(function()
        mpText:Show(false)
        if mpText.Clickable ~= nil then
            mpText:Clickable(false)
        end
        if mpText.style ~= nil then
            mpText.style:SetAlign(ALIGN.CENTER)
            mpText.style:SetFontSize(FONT_SIZE and FONT_SIZE.SMALL or 10)
            mpText.style:SetColor(1, 1, 1, 1)
        end
    end)
    frame.mpText = mpText

    local statusText = api.Interface:CreateWidget("label", frame_id .. ".statusText", frame)
    pcall(function()
        statusText:Show(false)
        if statusText.Clickable ~= nil then
            statusText:Clickable(false)
        end
        if statusText.style ~= nil then
            statusText.style:SetAlign(ALIGN.CENTER)
            statusText.style:SetFontSize(FONT_SIZE and FONT_SIZE.SMALL or 10)
            statusText.style:SetColor(1, 1, 1, 1)
        end
    end)
    frame.statusText = statusText

    local eventWindow = nil
    pcall(function()
        eventWindow = api.Interface:CreateWidget("emptywidget", frame_id .. ".event", frame)
        if eventWindow.AddAnchor ~= nil then
            eventWindow:AddAnchor("TOPLEFT", frame, 0, 0)
            eventWindow:AddAnchor("BOTTOMRIGHT", frame, 0, 0)
        end
        if eventWindow.Show ~= nil then
            eventWindow:Show(true)
        end
        SafeClickable(eventWindow, true)
    end)
    frame.eventWindow = eventWindow
    frame.__polar_hovered = false
    frame.__polar_cached_name = nil
    frame.__polar_cached_id = nil
    frame.__polar_meta = nil
    frame.__polar_meta_cache_key = nil

    if eventWindow ~= nil and eventWindow.SetHandler ~= nil then
        eventWindow:SetHandler("OnClick", function(_, button)
            if RaidFrames.settings ~= nil and RaidFrames.settings.drag_requires_shift then
                if api.Input ~= nil and api.Input.IsShiftKeyDown ~= nil and api.Input:IsShiftKeyDown() then
                    return
                end
            end
            if button == "MiddleButton" then
                return
            end
            if button == "RightButton" and RaidFrames.HandleRightClick ~= nil then
                RaidFrames.HandleRightClick(unit, frame)
                return
            end
            ChangeTarget(unit)
        end)

        eventWindow:SetHandler("OnEnter", function()
            frame.__polar_hovered = true
        end)
        eventWindow:SetHandler("OnLeave", function()
            frame.__polar_hovered = false
        end)
        eventWindow:SetHandler("OnDragStart", function()
            local container = RaidFrames.container
            if container ~= nil and container.OnDragStart ~= nil then
                container:OnDragStart()
            end
        end)
        eventWindow:SetHandler("OnDragStop", function()
            local container = RaidFrames.container
            if container ~= nil and container.OnDragStop ~= nil then
                container:OnDragStop()
            end
        end)
        pcall(function()
            if eventWindow.RegisterForDrag ~= nil then
                eventWindow:RegisterForDrag("LeftButton")
            end
            if eventWindow.EnableDrag ~= nil then
                eventWindow:EnableDrag(true)
            end
        end)
    end

    RaidFrames.frames[unit] = frame
    return frame
end

local function ApplyLayout(unit, frame, cfg)
    if frame == nil or type(cfg) ~= "table" then
        return
    end

    local width = ClampNumber(cfg.width, 40, 400, 80)
    local hp_h = ClampNumber(cfg.hp_height, 4, 60, 16)
    local mp_h = ClampNumber(cfg.mp_height, 0, 40, 0)
    local total_h = hp_h + mp_h

    pcall(function()
        if frame.SetExtent ~= nil then
            frame:SetExtent(width, total_h)
        end
    end)

    if frame.hpBar ~= nil then
        pcall(function()
            frame.hpBar:RemoveAllAnchors()
            frame.hpBar:AddAnchor("TOPLEFT", frame, 0, 0)
            frame.hpBar:AddAnchor("TOPRIGHT", frame, 0, 0)
            frame.hpBar:SetHeight(hp_h)
        end)
    end

    if frame.mpBar ~= nil then
        pcall(function()
            frame.mpBar:RemoveAllAnchors()
            frame.mpBar:AddAnchor("TOPLEFT", frame.hpBar, "BOTTOMLEFT", 0, -1)
            frame.mpBar:AddAnchor("TOPRIGHT", frame.hpBar, "BOTTOMRIGHT", 0, -1)
            frame.mpBar:SetHeight(mp_h)
        end)
        SafeShow(frame.mpBar, mp_h > 0)
    end

    if frame.nameLabel ~= nil and frame.nameLabel.style ~= nil then
        pcall(function()
            local fs = ClampNumber(cfg.name_font_size, 6, 32, 11)
            frame.nameLabel.style:SetFontSize(fs)
            if frame.nameLabel.SetExtent ~= nil then
                local pad = ClampNumber(cfg.name_padding_left, -50, 200, 2)
                local w = ClampNumber(cfg.width, 40, 400, 80)
                local lw = w - pad - 2
                if lw < 10 then
                    lw = 10
                end
                frame.nameLabel:SetExtent(lw, fs + 6)
            end
        end)

        pcall(function()
            if frame.nameLabel.RemoveAllAnchors ~= nil then
                frame.nameLabel:RemoveAllAnchors()
            end
            local pad = ClampNumber(cfg.name_padding_left, -50, 200, 2)
            frame.nameLabel:AddAnchor(
                "LEFT",
                frame,
                pad + ClampNumber(cfg.name_offset_x, -120, 120, 0),
                ClampNumber(cfg.name_offset_y, -40, 40, 0)
            )
        end)

        SafeShow(frame.nameLabel, cfg.show_name ~= false)
    end

    local iconSize = ClampNumber(cfg.icon_size, 6, 40, 12)
    local iconGap = ClampNumber(cfg.icon_gap, 0, 40, 2)
    if frame.classIcon ~= nil then
        pcall(function()
            frame.classIcon:SetExtent(iconSize, iconSize)
            if frame.classIcon.RemoveAllAnchors ~= nil then
                frame.classIcon:RemoveAllAnchors()
            end
            if frame.classIcon.AddAnchor ~= nil then
                frame.classIcon:AddAnchor(
                    "LEFT",
                    frame,
                    ClampNumber(cfg.name_padding_left, -50, 200, 2) + ClampNumber(cfg.icon_offset_x, -120, 120, 0),
                    ClampNumber(cfg.icon_offset_y, -40, 40, 0)
                )
            end
        end)
    end
    if frame.roleBadge ~= nil then
        pcall(function()
            frame.roleBadge:SetExtent(iconSize, iconSize)
            if frame.roleBadge.RemoveAllAnchors ~= nil then
                frame.roleBadge:RemoveAllAnchors()
            end
            local x = ClampNumber(cfg.name_padding_left, -50, 200, 2)
            if cfg.show_class_icon ~= false and frame.classIcon ~= nil then
                x = x + iconSize + iconGap
            end
            if frame.roleBadge.AddAnchor ~= nil then
                frame.roleBadge:AddAnchor(
                    "LEFT",
                    frame,
                    x + ClampNumber(cfg.icon_offset_x, -120, 120, 0),
                    ClampNumber(cfg.icon_offset_y, -40, 40, 0)
                )
            end
        end)
    end

    if frame.bg ~= nil then
        pcall(function()
            if frame.bg.RemoveAllAnchors ~= nil then
                frame.bg:RemoveAllAnchors()
            end
            if frame.hpBar ~= nil and frame.mpBar ~= nil and frame.bg.AddAnchor ~= nil then
                frame.bg:AddAnchor("TOPLEFT", frame.hpBar, -3, -3)
                frame.bg:AddAnchor("BOTTOMRIGHT", frame.mpBar, 2, 3)
            elseif frame.hpBar ~= nil and frame.bg.AddAnchor ~= nil then
                frame.bg:AddAnchor("TOPLEFT", frame.hpBar, -3, -3)
                frame.bg:AddAnchor("BOTTOMRIGHT", frame.hpBar, 2, 3)
            end
        end)
    end

    if frame.targetHighlight ~= nil then
        pcall(function()
            frame.targetHighlight:SetExtent(width + 4, total_h + 4)
            if frame.targetHighlight.RemoveAllAnchors ~= nil then
                frame.targetHighlight:RemoveAllAnchors()
            end
            if frame.targetHighlight.AddAnchor ~= nil then
                frame.targetHighlight:AddAnchor("TOPLEFT", frame, -2, -2)
            end
        end)
    end

    if frame.debuffBadge ~= nil then
        pcall(function()
            frame.debuffBadge:SetExtent(8, 8)
            if frame.debuffBadge.RemoveAllAnchors ~= nil then
                frame.debuffBadge:RemoveAllAnchors()
            end
            if frame.debuffBadge.AddAnchor ~= nil then
                frame.debuffBadge:AddAnchor("TOPRIGHT", frame, 0, 0)
            end
        end)
    end

    local valueFontSize = ClampNumber(cfg.value_font_size, 6, 24, 10)
    if frame.hpText ~= nil then
        pcall(function()
            if frame.hpText.style ~= nil then
                frame.hpText.style:SetFontSize(valueFontSize)
            end
            if frame.hpText.RemoveAllAnchors ~= nil then
                frame.hpText:RemoveAllAnchors()
            end
            if frame.hpText.AddAnchor ~= nil and frame.hpBar ~= nil then
                frame.hpText:AddAnchor(
                    "CENTER",
                    frame.hpBar,
                    ClampNumber(cfg.value_offset_x, -120, 120, 0),
                    ClampNumber(cfg.value_offset_y, -40, 40, 0)
                )
            end
            if frame.hpText.SetExtent ~= nil then
                frame.hpText:SetExtent(width, valueFontSize + 6)
            end
        end)
    end

    if frame.mpText ~= nil then
        pcall(function()
            if frame.mpText.style ~= nil then
                frame.mpText.style:SetFontSize(valueFontSize)
            end
            if frame.mpText.RemoveAllAnchors ~= nil then
                frame.mpText:RemoveAllAnchors()
            end
            if frame.mpText.AddAnchor ~= nil and frame.mpBar ~= nil then
                frame.mpText:AddAnchor(
                    "CENTER",
                    frame.mpBar,
                    ClampNumber(cfg.value_offset_x, -120, 120, 0),
                    ClampNumber(cfg.value_offset_y, -40, 40, 0)
                )
            end
            if frame.mpText.SetExtent ~= nil then
                frame.mpText:SetExtent(width, valueFontSize + 6)
            end
        end)
    end

    if frame.statusText ~= nil then
        pcall(function()
            if frame.statusText.style ~= nil then
                frame.statusText.style:SetFontSize(valueFontSize)
            end
            if frame.statusText.RemoveAllAnchors ~= nil then
                frame.statusText:RemoveAllAnchors()
            end
            if frame.statusText.AddAnchor ~= nil then
                frame.statusText:AddAnchor(
                    "CENTER",
                    frame,
                    ClampNumber(cfg.value_offset_x, -120, 120, 0),
                    ClampNumber(cfg.value_offset_y, -40, 40, 0)
                )
            end
            if frame.statusText.SetExtent ~= nil then
                frame.statusText:SetExtent(width, valueFontSize + 6)
            end
        end)
    end
end

local function ComputeUnitOffset(unit, idx, cfg)
    local layout = tostring(cfg.layout_mode or "party_columns")
    local w = ClampNumber(cfg.width, 40, 400, 80)
    local hp_h = ClampNumber(cfg.hp_height, 4, 60, 16)
    local mp_h = ClampNumber(cfg.mp_height, 0, 40, 0)
    local h = hp_h + mp_h
    local gap_x = ClampNumber(cfg.gap_x, 0, 50, 2)
    local gap_y = ClampNumber(cfg.gap_y, 0, 50, 2)
    local headerOffset = 0
    if layout == "party_columns" and cfg.show_group_headers ~= false then
        headerOffset = ClampNumber(cfg.group_header_font_size, 8, 24, 11) + 8
    end

    if layout == "party_only" then
        local row = idx - 1
        return 0, row * (h + gap_y) + headerOffset
    end

    if layout == "single_list" then
        local row = idx - 1
        return 0, row * (h + gap_y) + headerOffset
    end

    if layout == "compact_grid" then
        local cols = ClampNumber(cfg.grid_columns, 1, 20, 8)
        local col = (idx - 1) % cols
        local row = math.floor((idx - 1) / cols)
        return col * (w + gap_x), row * (h + gap_y) + headerOffset
    end

    -- party_columns default: 10 columns (party 1..10), 5 rows
    local col = math.floor((idx - 1) / 5)
    local row = (idx - 1) % 5
    return col * (w + gap_x), row * (h + gap_y) + headerOffset
end

local function EnsureGroupHeaders(container)
    if container == nil or RaidFrames.group_headers == nil or RaidFrames.group_header_bgs == nil then
        return
    end
    for i = 1, 10 do
        if RaidFrames.group_headers[i] == nil then
            local label = api.Interface:CreateWidget("label", "polarRaidGroupHeader" .. tostring(i), container)
            pcall(function()
                label:Show(false)
                if label.Clickable ~= nil then
                    label:Clickable(false)
                end
                if label.style ~= nil then
                    label.style:SetAlign(ALIGN.LEFT)
                    label.style:SetColor(1, 1, 1, 0.95)
                    label.style:SetFontSize(FONT_SIZE and FONT_SIZE.SMALL or 11)
                end
            end)
            RaidFrames.group_headers[i] = label
        end
        if RaidFrames.group_header_bgs[i] == nil and container.CreateImageDrawable ~= nil then
            local bg = nil
            pcall(function()
                bg = container:CreateImageDrawable("Textures/Defaults/White.dds", "background")
                bg:SetVisible(false)
                bg:SetColor(0, 0, 0, 0.55)
            end)
            RaidFrames.group_header_bgs[i] = bg
        end
    end
end

local function UpdateGroupHeaders(cfg, shownGroups)
    local container = RaidFrames.container
    if container == nil then
        return
    end
    EnsureGroupHeaders(container)

    local show = tostring(cfg.layout_mode or "party_columns") == "party_columns" and cfg.show_group_headers ~= false
    local w = ClampNumber(cfg.width, 40, 400, 80)
    local gap_x = ClampNumber(cfg.gap_x, 0, 50, 2)
    local fontSize = ClampNumber(cfg.group_header_font_size, 8, 24, 11)

    for i, label in ipairs(RaidFrames.group_headers) do
        local showOne = show and type(shownGroups) == "table" and shownGroups[i] and true or false
        local bg = RaidFrames.group_header_bgs[i]
        if label ~= nil then
            pcall(function()
                if label.style ~= nil then
                    label.style:SetFontSize(fontSize)
                end
                if label.RemoveAllAnchors ~= nil then
                    label:RemoveAllAnchors()
                end
                if showOne and label.AddAnchor ~= nil then
                    local x = (i - 1) * (w + gap_x)
                    label:AddAnchor("TOPLEFT", container, x, 0)
                    if label.SetText ~= nil then
                        label:SetText("Party " .. tostring(i))
                    end
                end
                if label.Show ~= nil then
                    label:Show(showOne)
                end
            end)
        end
        if bg ~= nil then
            pcall(function()
                if bg.RemoveAllAnchors ~= nil then
                    bg:RemoveAllAnchors()
                end
                if showOne and bg.AddAnchor ~= nil then
                    local x = (i - 1) * (w + gap_x)
                    bg:AddAnchor("TOPLEFT", container, x - 4, -2)
                end
                if bg.SetExtent ~= nil then
                    bg:SetExtent(w - 4, fontSize + 8)
                end
                if bg.SetVisible ~= nil then
                    bg:SetVisible(showOne)
                elseif bg.Show ~= nil then
                    bg:Show(showOne)
                end
            end)
        end
    end
end

local function HideRaidContextMenu()
    if RaidFrames.context_menu ~= nil and RaidFrames.context_menu.Show ~= nil then
        pcall(function()
            RaidFrames.context_menu:Show(false)
        end)
    end
end

local function EnsureRaidContextMenu()
    if RaidFrames.context_menu ~= nil then
        return RaidFrames.context_menu
    end
    if api.Interface == nil or api.Interface.CreateWindow == nil then
        return nil
    end

    local wnd = nil
    pcall(function()
        wnd = api.Interface:CreateWindow("polarRaidContextMenu", "Raid Actions", 190, 170)
    end)
    if wnd == nil then
        return nil
    end

    pcall(function()
        wnd:SetExtent(190, 170)
        wnd:Show(false)
    end)

    local buttons = {
        { key = "target", text = "Target", y = 40 },
        { key = "invite_party", text = "Invite To Party", y = 72 },
        { key = "invite_raid", text = "Invite To Raid", y = 104 },
        { key = "close", text = "Close", y = 136 }
    }

    wnd.__polar_buttons = {}
    for _, entry in ipairs(buttons) do
        local btn = wnd:CreateChildWidget("button", "polarRaidCtx_" .. entry.key, 0, true)
        btn:SetExtent(150, 24)
        btn:SetText(entry.text)
        pcall(function()
            if btn.RemoveAllAnchors ~= nil then
                btn:RemoveAllAnchors()
            end
            if btn.AddAnchor ~= nil then
                btn:AddAnchor("TOPLEFT", wnd, 20, entry.y)
            end
            if api.Interface ~= nil and api.Interface.ApplyButtonSkin ~= nil and BUTTON_BASIC ~= nil then
                api.Interface:ApplyButtonSkin(btn, BUTTON_BASIC.DEFAULT)
            end
        end)
        wnd.__polar_buttons[entry.key] = btn
    end

    local function getCurrentName()
        return tostring(wnd.__polar_unit_name or "")
    end

    if wnd.__polar_buttons.target ~= nil and wnd.__polar_buttons.target.SetHandler ~= nil then
        wnd.__polar_buttons.target:SetHandler("OnClick", function()
            if wnd.__polar_unit ~= nil then
                ChangeTarget(wnd.__polar_unit)
            end
            HideRaidContextMenu()
        end)
    end
    if wnd.__polar_buttons.invite_party ~= nil and wnd.__polar_buttons.invite_party.SetHandler ~= nil then
        wnd.__polar_buttons.invite_party:SetHandler("OnClick", function()
            local name = getCurrentName()
            if name ~= "" and api.Team ~= nil and api.Team.InviteToTeam ~= nil then
                pcall(function()
                    api.Team:InviteToTeam(name, true)
                end)
            end
            HideRaidContextMenu()
        end)
    end
    if wnd.__polar_buttons.invite_raid ~= nil and wnd.__polar_buttons.invite_raid.SetHandler ~= nil then
        wnd.__polar_buttons.invite_raid:SetHandler("OnClick", function()
            local name = getCurrentName()
            if name ~= "" and api.Team ~= nil and api.Team.InviteToTeam ~= nil then
                pcall(function()
                    api.Team:InviteToTeam(name, false)
                end)
            end
            HideRaidContextMenu()
        end)
    end
    if wnd.__polar_buttons.close ~= nil and wnd.__polar_buttons.close.SetHandler ~= nil then
        wnd.__polar_buttons.close:SetHandler("OnClick", function()
            HideRaidContextMenu()
        end)
    end

    RaidFrames.context_menu = wnd
    return wnd
end

local function TryForwardStockRightClick(unit, unitId)
    local member = GetStockMember(unit, unitId)
    if type(member) ~= "table" then
        return false
    end

    local candidates = {
        member.eventWindow,
        member.event_window,
        member.button,
        member
    }

    for _, candidate in ipairs(candidates) do
        if candidate ~= nil then
            local ok, handled = pcall(function()
                if candidate.OnClick ~= nil then
                    candidate:OnClick("RightButton")
                    return true
                end
                return false
            end)
            if ok and handled then
                return true
            end
        end
    end
    return false
end

local function ShowRaidContextMenu(unit, frame)
    local cfg = type(RaidFrames.settings) == "table" and RaidFrames.settings.raidframes or nil
    if type(cfg) == "table" and cfg.right_click_fallback_menu == false then
        return
    end

    local wnd = EnsureRaidContextMenu()
    if wnd == nil then
        return
    end

    wnd.__polar_unit = unit
    wnd.__polar_unit_name = frame ~= nil and tostring(frame.__polar_cached_name or "") or ""

    local mouseX = 400
    local mouseY = 300
    pcall(function()
        if api.Input ~= nil and api.Input.GetMousePos ~= nil then
            mouseX, mouseY = api.Input:GetMousePos()
        end
    end)
    mouseX = ClampNumber(mouseX, 0, 5000, 400)
    mouseY = ClampNumber(mouseY, 0, 5000, 300)

    pcall(function()
        if wnd.RemoveAllAnchors ~= nil then
            wnd:RemoveAllAnchors()
        end
        if wnd.AddAnchor ~= nil then
            wnd:AddAnchor("TOPLEFT", "UIParent", mouseX, mouseY)
        end
        if wnd.SetTitle ~= nil then
            wnd:SetTitle("Raid Actions: " .. tostring(wnd.__polar_unit_name ~= "" and wnd.__polar_unit_name or unit))
        end
        wnd:Show(true)
    end)
end

RaidFrames.HandleRightClick = function(unit, frame)
    local unitId = nil
    pcall(function()
        if api.Unit ~= nil and api.Unit.GetUnitId ~= nil then
            unitId = api.Unit:GetUnitId(unit)
        end
    end)
    if TryForwardStockRightClick(unit, unitId) then
        return
    end
    ShowRaidContextMenu(unit, frame)
end

local function EnsureContainer(cfg)
    if RaidFrames.container ~= nil then
        return
    end

    local wnd = api.Interface:CreateEmptyWindow("polarRaidFramesContainer")
    if wnd == nil then
        return
    end
    pcall(function()
        if wnd.SetUILayer ~= nil then
            wnd:SetUILayer("hud")
        end
    end)

    SafeShow(wnd, false)

    pcall(function()
        wnd:RemoveAllAnchors()
        wnd:AddAnchor(
            "TOPLEFT",
            "UIParent",
            ClampNumber(cfg.x, 0, 5000, 600),
            ClampNumber(cfg.y, 0, 5000, 250)
        )
    end)

    local function savePos()
        if RaidFrames.settings == nil or type(RaidFrames.settings.raidframes) ~= "table" then
            return
        end
        local s = RaidFrames.settings.raidframes
        local x = nil
        local y = nil
        pcall(function()
            if wnd.GetOffset ~= nil then
                x, y = wnd:GetOffset()
            end
        end)
        if type(x) == "number" then
            s.x = x
        end
        if type(y) == "number" then
            s.y = y
        end
    end

    function wnd:OnDragStart()
        if RaidFrames.settings ~= nil and RaidFrames.settings.drag_requires_shift then
            if api.Input ~= nil and api.Input.IsShiftKeyDown ~= nil and not api.Input:IsShiftKeyDown() then
                return
            end
        end
        if self.StartMoving ~= nil then
            self:StartMoving()
        end
    end

    function wnd:OnDragStop()
        if self.StopMovingOrSizing ~= nil then
            self:StopMovingOrSizing()
        end
        if api.Cursor ~= nil and api.Cursor.ClearCursor ~= nil then
            pcall(function()
                api.Cursor:ClearCursor()
            end)
        end
        savePos()
    end

    pcall(function()
        if wnd.SetHandler ~= nil then
            wnd:SetHandler("OnDragStart", wnd.OnDragStart)
            wnd:SetHandler("OnDragStop", wnd.OnDragStop)
        end
        if wnd.RegisterForDrag ~= nil then
            wnd:RegisterForDrag("LeftButton")
        end
        if wnd.EnableDrag ~= nil then
            wnd:EnableDrag(true)
        end
    end)

    RaidFrames.container = wnd
end

local function TryHideStockRaidFrames(cfg)
    if type(cfg) ~= "table" or not cfg.hide_stock then
        RaidFrames.tried_hide_stock = false
        return
    end
    if RaidFrames.tried_hide_stock then
        return
    end
    RaidFrames.tried_hide_stock = true

    if ADDON == nil or ADDON.GetContent == nil or UIC == nil or UIC.RAID_MANAGER == nil then
        return
    end

    pcall(function()
        local rm = ADDON:GetContent(UIC.RAID_MANAGER)
        if rm == nil then
            return
        end

        local opt_frame = rm.raidOptionFrame
        if opt_frame == nil then
            return
        end

        local cb = opt_frame.invisibleRaidFrameCheckBox
        if cb == nil then
            return
        end

        if cb.SetChecked ~= nil then
            cb:SetChecked(true)
        end
        if cb.OnClick ~= nil then
            cb:OnClick()
        end
    end)
end

local function ApplyRaidBarStyle(frame, settings, teamRoleKey)
    if frame == nil or type(settings) ~= "table" then
        return
    end
    local cfg = type(settings.raidframes) == "table" and settings.raidframes or nil
    local style = type(settings.style) == "table" and settings.style or nil
    if type(cfg) ~= "table" or type(style) ~= "table" then
        return
    end
    if tostring(cfg.bar_style_mode or "shared") ~= "shared" then
        return
    end

    local styleKey = BuildBarStyleKey(settings, teamRoleKey)
    if frame.__polar_bar_style_key == styleKey then
        return
    end

    local statusbarStyle = nil
    pcall(function()
        if type(_G) == "table" and _G.STATUSBAR_STYLE ~= nil then
            statusbarStyle = _G.STATUSBAR_STYLE
        elseif STATUSBAR_STYLE ~= nil then
            statusbarStyle = STATUSBAR_STYLE
        end
    end)
    local hpKey = "HP_RAID"
    local mpKey = "MP_RAID"
    local hpMode = tostring(style.hp_texture_mode or "stock")
    if hpMode == "pc" and type(statusbarStyle) == "table" and statusbarStyle.L_HP_FRIENDLY ~= nil then
        hpKey = "L_HP_FRIENDLY"
    elseif hpMode == "npc" and type(statusbarStyle) == "table" and statusbarStyle.L_HP_NEUTRAL ~= nil then
        hpKey = "L_HP_NEUTRAL"
    end
    if hpMode ~= "stock" and type(statusbarStyle) == "table" and statusbarStyle.L_MP ~= nil then
        mpKey = "L_MP"
    end

    pcall(function()
        if frame.hpBar ~= nil then
            if type(statusbarStyle) == "table" and statusbarStyle[hpKey] ~= nil then
                frame.hpBar:ApplyBarTexture(statusbarStyle[hpKey])
            else
                frame.hpBar:ApplyBarTexture()
            end
        end
    end)
    pcall(function()
        if frame.mpBar ~= nil then
            if type(statusbarStyle) == "table" and statusbarStyle[mpKey] ~= nil then
                frame.mpBar:ApplyBarTexture(statusbarStyle[mpKey])
            else
                frame.mpBar:ApplyBarTexture()
            end
        end
    end)

    if cfg.use_team_role_colors ~= false and teamRoleKey ~= nil and TEAM_ROLE_COLORS[teamRoleKey] ~= nil then
        local rgba = TEAM_ROLE_COLORS[teamRoleKey]
        local function applyFill(bar)
            if bar == nil or bar.statusBar == nil then
                return
            end
            local r = Color01From255(rgba[1], 255)
            local g = Color01From255(rgba[2], 255)
            local b = Color01From255(rgba[3], 255)
            local a = Color01From255(rgba[4], 255)
            pcall(function()
                bar.statusBar:SetBarColor(r, g, b, a)
            end)
            pcall(function()
                bar.statusBar:SetColor(r, g, b, a)
            end)
        end
        applyFill(frame.hpBar)
    elseif style.bar_colors_enabled then
        local function applyFill(bar, rgba)
            if bar == nil or bar.statusBar == nil or type(rgba) ~= "table" then
                return
            end
            local r = Color01From255(rgba[1], 255)
            local g = Color01From255(rgba[2], 255)
            local b = Color01From255(rgba[3], 255)
            local a = Color01From255(rgba[4], 255)
            pcall(function()
                bar.statusBar:SetBarColor(r, g, b, a)
            end)
            pcall(function()
                bar.statusBar:SetColor(r, g, b, a)
            end)
        end
        applyFill(frame.hpBar, style.hp_fill_color or style.hp_bar_color)
        applyFill(frame.mpBar, style.mp_fill_color or style.mp_bar_color)
    end

    frame.__polar_bar_style_key = styleKey
end

local function UpdateOne(unit, idx, settings, updateFlags)
    if settings == nil then
        return false
    end
    if type(settings.raidframes) ~= "table" then
        return false
    end
    local cfg = settings.raidframes
    local flags = type(updateFlags) == "table" and updateFlags or {}

    if not (RaidFrames.enabled and cfg.enabled) then
        SafeShow(RaidFrames.frames[unit], false)
        return false
    end

    if not ShouldShowUnit(unit, cfg) then
        SafeShow(RaidFrames.frames[unit], false)
        return false
    end

    EnsureContainer(cfg)
    local container = RaidFrames.container
    if container == nil then
        return false
    end

    local frame = EnsureFrame(container, unit)
    if frame == nil then
        return false
    end

    local layoutKey = BuildLayoutKey(cfg)
    if frame.__polar_layout_key ~= layoutKey then
        ApplyLayout(unit, frame, cfg)
        frame.__polar_layout_key = layoutKey
    end

    if frame.eventWindow ~= nil and frame.eventWindow.EnablePick ~= nil and frame.__polar_last_allow_pick ~= true then
        pcall(function()
            frame.eventWindow:EnablePick(true)
        end)
        frame.__polar_last_allow_pick = true
    end

    local alpha01 = Percent01(cfg.alpha_pct, 100)
    if frame.__polar_last_alpha ~= alpha01 then
        SafeSetAlpha(frame, alpha01)
        frame.__polar_last_alpha = alpha01
    end

    local bg_enabled = cfg.bg_enabled ~= false
    local bg_alpha01 = Percent01(cfg.bg_alpha_pct, 80)
    if frame.__polar_last_bg_enabled ~= bg_enabled or frame.__polar_last_bg_alpha ~= bg_alpha01 then
        SafeSetBg(frame, bg_enabled, bg_alpha01)
        frame.__polar_last_bg_enabled = bg_enabled
        frame.__polar_last_bg_alpha = bg_alpha01
    end

    if frame.__polar_hovered and frame.bg ~= nil and frame.bg.SetColor ~= nil and bg_enabled then
        pcall(function()
            local a = bg_alpha01
            if type(a) ~= "number" then
                a = 0.8
            end
            a = ClampNumber(a + 0.2, 0, 1, 1)
            frame.bg:SetColor(1, 1, 1, a)
        end)
    end

    local x, y = ComputeUnitOffset(unit, idx, cfg)
    if frame.__polar_last_anchor_x ~= x or frame.__polar_last_anchor_y ~= y then
        pcall(function()
            frame:RemoveAllAnchors()
            frame:AddAnchor("TOPLEFT", container, x, y)
        end)
        frame.__polar_last_anchor_x = x
        frame.__polar_last_anchor_y = y
    end

    local id = nil
    pcall(function()
        if api.Unit ~= nil and api.Unit.GetUnitId ~= nil then
            id = api.Unit:GetUnitId(unit)
        end
    end)
    local idStr = id ~= nil and tostring(id) or tostring(unit)
    local stableCacheKey = nil
    if id ~= nil then
        stableCacheKey = tostring(id)
    end
    local cacheKey = stableCacheKey or tostring(unit)

    local name = LookupNameFromStockCache(unit, id)
    local stockMember = GetStockMember(unit, id)

    if string.match(tostring(unit or ""), "^team%d+$") and type(stockMember) ~= "table" and (name == nil or tostring(name) == "") then
        frame.__polar_cached_id = nil
        frame.__polar_cached_name = nil
        frame.__polar_meta = nil
        frame.__polar_meta_cache_key = nil
        SafeShow(frame, false)
        return false
    end

    local wantRole = cfg.show_role_prefix ~= false or (cfg.show_role_badge and true or false)
    local wantClassIcon = cfg.show_class_icon ~= false
    local refreshMetadata = flags.update_metadata == true
        or type(frame.__polar_meta) ~= "table"
        or frame.__polar_meta_cache_key ~= cacheKey

    local role = "dps"
    local info = nil
    local modifier = nil
    local classTable = nil
    local teamRoleKey = nil

    if refreshMetadata then
        if name == nil or tostring(name) == "" then
            if stableCacheKey ~= nil and frame.__polar_cached_name ~= nil and frame.__polar_cached_id == stableCacheKey then
                name = frame.__polar_cached_name
            end
        end

        if wantRole then
            pcall(function()
                if api.Ability ~= nil and api.Ability.GetUnitClassName ~= nil then
                    local className = api.Ability:GetUnitClassName(unit) or ""
                    role = GetRoleForClass(settings, className)
                end
            end)
        end

        teamRoleKey = GetTeamRoleKey(unit, name, stockMember)
        if teamRoleKey == "defender" then
            role = "tank"
        elseif teamRoleKey == "healer" then
            role = "healer"
        elseif teamRoleKey == "attacker" then
            role = "dps"
        elseif teamRoleKey == "undecided" and cfg.show_role_prefix ~= false then
            role = "dps"
        end

        if wantClassIcon and id ~= nil then
            info = SafeGetUnitInfoById(id)
            if info == nil then
                info = SafeGetUnitInfoById(idStr)
            end
            if type(info) == "table" then
                classTable = info.class
            end
        end
        if info == nil then
            info = SafeGetUnitInfoById(id) or SafeGetUnitInfoById(idStr)
        end

        pcall(function()
            if api.Unit ~= nil and api.Unit.UnitModifierInfo ~= nil then
                modifier = api.Unit:UnitModifierInfo(unit)
            end
        end)

        if (name == nil or tostring(name) == "") and id ~= nil then
            name = SafeGetUnitNameById(id)
        end
        if (name == nil or tostring(name) == "") and id ~= nil then
            name = SafeGetUnitNameById(idStr)
        end
        if (name == nil or tostring(name) == "") and type(info) == "table" then
            name = info.name
                or info.unitName
                or info.unit_name
                or info.characterName
                or info.character_name
                or info.nickName
                or info.nickname
                or info.nick_name
                or name
        end
        if name == nil or tostring(name) == "" then
            pcall(function()
                if api.Unit ~= nil and api.Unit.UnitInfo ~= nil then
                    local uinfo = api.Unit:UnitInfo(unit)
                    if type(uinfo) == "table" then
                        name = uinfo.name
                            or uinfo.unitName
                            or uinfo.unit_name
                            or uinfo.characterName
                            or uinfo.character_name
                            or uinfo.nickName
                            or uinfo.nickname
                            or uinfo.nick_name
                            or name
                    end
                end
            end)
        end

        if name == nil or tostring(name) == "" then
            pcall(function()
                if api.Unit ~= nil and api.Unit.GetUnitInfo ~= nil then
                    local uinfo = api.Unit:GetUnitInfo(unit)
                    if type(uinfo) == "table" then
                        name = uinfo.name
                            or uinfo.unitName
                            or uinfo.unit_name
                            or uinfo.characterName
                            or uinfo.character_name
                            or uinfo.nickName
                            or uinfo.nickname
                            or uinfo.nick_name
                            or name
                    end
                end
            end)
        end

        if name == nil or tostring(name) == "" then
            pcall(function()
                if api.Unit ~= nil and api.Unit.GetUnitId ~= nil then
                    local playerId = api.Unit:GetUnitId("player")
                    if playerId ~= nil and tostring(playerId) == idStr then
                        name = api.Unit:GetUnitNameById(tostring(playerId))
                        if (name == nil or tostring(name) == "") and api.Unit.UnitInfo ~= nil then
                            local pinfo = api.Unit:UnitInfo("player")
                            if type(pinfo) == "table" then
                                name = pinfo.name or pinfo.unitName or pinfo.unit_name or name
                            end
                        end
                    end
                end
            end)
        end

        frame.__polar_meta = {
            name = tostring(name or ""),
            role = role,
            teamRoleKey = teamRoleKey,
            info = info,
            classTable = classTable,
            modifier = modifier
        }
        frame.__polar_meta_cache_key = cacheKey
    else
        local meta = frame.__polar_meta or {}
        if (name == nil or tostring(name) == "") and tostring(meta.name or "") ~= "" then
            name = meta.name
        end
        role = tostring(meta.role or "dps")
        teamRoleKey = meta.teamRoleKey
        info = meta.info
        classTable = meta.classTable
        modifier = meta.modifier
    end

    if stableCacheKey == nil then
        frame.__polar_cached_id = nil
        frame.__polar_cached_name = nil
    elseif frame.__polar_cached_id ~= nil and frame.__polar_cached_id ~= stableCacheKey then
        frame.__polar_cached_id = nil
        frame.__polar_cached_name = nil
    end

    if name ~= nil and tostring(name) ~= "" then
        if stableCacheKey ~= nil then
            frame.__polar_cached_id = stableCacheKey
            frame.__polar_cached_name = tostring(name)
        end
    elseif stableCacheKey ~= nil and frame.__polar_cached_name ~= nil and frame.__polar_cached_id == stableCacheKey then
        name = frame.__polar_cached_name
    end

    if name == nil or tostring(name) == "" then
        SafeShow(frame, false)
        return false
    end

    if frame.nameLabel ~= nil and frame.nameLabel.SetText ~= nil then
        local baseName = FormatUnitName(name, cfg.name_max_chars)
        local rolePrefix = ""
        if cfg.show_role_prefix ~= false then
            if teamRoleKey == "defender" then
                rolePrefix = "D "
            elseif teamRoleKey == "healer" then
                rolePrefix = "H "
            elseif teamRoleKey == "attacker" then
                rolePrefix = "A "
            elseif teamRoleKey == "undecided" then
                rolePrefix = "U "
            elseif role == "tank" then
                rolePrefix = "T "
            elseif role == "healer" then
                rolePrefix = "H "
            end
        end

        if tostring(baseName or "") ~= "" then
            UpdateCachedText(frame, "__polar_last_text", frame.nameLabel, rolePrefix .. tostring(baseName or ""))
        end
    end

    local updateVitals = flags.update_vitals == true or frame.__polar_has_vitals ~= true
    local hp = tonumber(frame.__polar_last_hp) or 0
    local maxHp = tonumber(frame.__polar_last_max_hp) or 0
    local mp = tonumber(frame.__polar_last_mp) or 0
    local maxMp = tonumber(frame.__polar_last_max_mp) or 0
    if updateVitals then
        pcall(function()
            maxHp = tonumber(api.Unit:UnitMaxHealth(unit)) or 0
            hp = tonumber(api.Unit:UnitHealth(unit)) or 0
            maxMp = tonumber(api.Unit:UnitMaxMana(unit)) or 0
            mp = tonumber(api.Unit:UnitMana(unit)) or 0
        end)
        frame.__polar_has_vitals = true
    end

    local offline = frame.__polar_last_offline and true or false
    if updateVitals or refreshMetadata then
        offline = SafeUnitIsOffline(unit)
        frame.__polar_last_offline = offline and true or false
    end
    local distance = nil
    if cfg.range_fade_enabled ~= false then
        distance = GetCachedDistance(frame, unit)
    end
    local outOfRange = cfg.range_fade_enabled ~= false and type(distance) == "number"
        and distance > ClampNumber(cfg.range_max_distance, 1, 300, 80)
    local state = GetUnitState(info, modifier, hp, maxHp, offline)

    local baseAlpha = Percent01(cfg.alpha_pct, 100)
    local effectiveAlpha = baseAlpha
    if state.offline then
        effectiveAlpha = effectiveAlpha * Percent01(cfg.offline_alpha_pct, 20)
    elseif state.dead then
        effectiveAlpha = effectiveAlpha * Percent01(cfg.dead_alpha_pct, 30)
    elseif outOfRange then
        effectiveAlpha = effectiveAlpha * Percent01(cfg.range_alpha_pct, 45)
    end
    if frame.__polar_last_effective_alpha ~= effectiveAlpha then
        SafeSetAlpha(frame, effectiveAlpha)
        frame.__polar_last_effective_alpha = effectiveAlpha
    end

    local targetId = RaidFrames.current_target_id
    local isCurrentTarget = (id ~= nil and targetId ~= nil and tostring(id) == tostring(targetId))

    local debuffInfo = { count = 0, dispellable = false }
    if cfg.show_debuff_alert ~= false then
        debuffInfo = GetCachedDebuffInfo(frame, unit, refreshMetadata)
    end
    local showDebuffAlert = cfg.show_debuff_alert ~= false and tonumber(debuffInfo.count) ~= nil and debuffInfo.count > 0

    if frame.targetHighlight ~= nil then
        UpdateCachedVisible(frame, "__polar_target_visible", frame.targetHighlight, cfg.show_target_highlight ~= false and isCurrentTarget)
    end

    if frame.debuffBadge ~= nil then
        local debuffColor = nil
        if showDebuffAlert then
            if cfg.prefer_dispel_alert ~= false and debuffInfo.dispellable then
                debuffColor = { 255, 217, 51, 242 }
            else
                debuffColor = { 255, 51, 51, 242 }
            end
        end
        local colorKey = ColorKey(debuffColor)
        if frame.__polar_debuff_color_key ~= colorKey and debuffColor ~= nil then
            frame.__polar_debuff_color_key = colorKey
            pcall(function()
                frame.debuffBadge:SetColor(debuffColor[1] / 255, debuffColor[2] / 255, debuffColor[3] / 255, debuffColor[4] / 255)
            end)
        end
        UpdateCachedVisible(frame, "__polar_debuff_visible", frame.debuffBadge, showDebuffAlert)
    end

    if frame.nameLabel ~= nil then
        local textColor = { 255, 255, 255, 255 }
        if state.offline then
            textColor = { 170, 170, 170, 255 }
        elseif state.dead then
            textColor = { 210, 120, 120, 255 }
        elseif cfg.use_class_name_colors and type(classTable) == "table" and GetClassColor(classTable) ~= nil then
            textColor = GetClassColor(classTable)
        elseif cfg.use_role_name_colors ~= false then
            textColor = GetRoleColor(role, teamRoleKey)
        end
        UpdateCachedLabelColor(frame, "__polar_name_color", frame.nameLabel, textColor)
    end

    local statusText = ""
    if state.offline then
        statusText = "Offline"
    elseif state.dead then
        statusText = "Dead"
    end

    if frame.statusText ~= nil then
        local showStatus = cfg.show_status_text ~= false and statusText ~= ""
        UpdateCachedText(frame, "__polar_status_text", frame.statusText, statusText)
        UpdateCachedVisible(frame, "__polar_status_visible", frame.statusText, showStatus)
    end

    if frame.classIcon ~= nil then
        local want = cfg.show_class_icon ~= false
        local coords = nil
        if want and type(classTable) == "table" then
            local skillsetId = GetSkillsetIdFromClassTable(classTable)
            coords = GetSkillsetIconCoords(skillsetId)
        end

        local coordsKey = coords ~= nil and table.concat({
            tostring(coords[1]),
            tostring(coords[2]),
            tostring(coords[3]),
            tostring(coords[4])
        }, ",") or ""
        if want and coords ~= nil then
            if frame.__polar_class_icon_coords_key ~= coordsKey then
                frame.__polar_class_icon_coords_key = coordsKey
                pcall(function()
                    frame.classIcon:SetCoords(coords[1], coords[2], coords[3], coords[4])
                end)
            end
            UpdateCachedVisible(frame, "__polar_class_icon_visible", frame.classIcon, true)
        else
            frame.__polar_class_icon_coords_key = ""
            UpdateCachedVisible(frame, "__polar_class_icon_visible", frame.classIcon, false)
        end
    end

    if frame.roleBadge ~= nil then
        local want = cfg.show_role_badge and true or false
        if want and teamRoleKey == "undecided" then
            want = false
        elseif want and teamRoleKey == nil and cfg.hide_dps_role_badge and role == "dps" then
            want = false
        end

        local badgeKey = tostring(role or "") .. "|" .. tostring(teamRoleKey or "")
        if want then
            if frame.__polar_role_badge_key ~= badgeKey then
                frame.__polar_role_badge_key = badgeKey
                pcall(function()
                    SetRoleBadgeColor(frame.roleBadge, role, teamRoleKey)
                end)
            end
            UpdateCachedVisible(frame, "__polar_role_badge_visible", frame.roleBadge, true)
        else
            frame.__polar_role_badge_key = ""
            UpdateCachedVisible(frame, "__polar_role_badge_visible", frame.roleBadge, false)
        end
    end

    if frame.nameLabel ~= nil and frame.nameLabel.AddAnchor ~= nil then
        local pad = ClampNumber(cfg.name_padding_left, -50, 200, 2)
        local nameOffsetX = ClampNumber(cfg.name_offset_x, -120, 120, 0)
        local nameOffsetY = ClampNumber(cfg.name_offset_y, -40, 40, 0)
        local iconSize = ClampNumber(cfg.icon_size, 6, 40, 12)
        local iconGap = ClampNumber(cfg.icon_gap, 0, 40, 2)
        if frame.__polar_class_icon_visible then
            pad = pad + iconSize + iconGap
        end
        if frame.__polar_role_badge_visible then
            pad = pad + iconSize + iconGap
        end

        if frame.__polar_last_name_pad ~= pad
            or frame.__polar_last_name_offset_x ~= nameOffsetX
            or frame.__polar_last_name_offset_y ~= nameOffsetY
        then
            pcall(function()
                if frame.nameLabel.RemoveAllAnchors ~= nil then
                    frame.nameLabel:RemoveAllAnchors()
                end
                frame.nameLabel:AddAnchor("LEFT", frame, pad + nameOffsetX, nameOffsetY)
            end)
            frame.__polar_last_name_pad = pad
            frame.__polar_last_name_offset_x = nameOffsetX
            frame.__polar_last_name_offset_y = nameOffsetY
        end
    end

    ApplyRaidBarStyle(frame, settings, teamRoleKey)

    if frame.hpText ~= nil then
        local showHpText = cfg.show_value_text and statusText == ""
        if showHpText then
            UpdateCachedText(frame, "__polar_hp_text", frame.hpText, GetValueText(cfg.value_text_mode, hp, maxHp, "hp"))
        end
        UpdateCachedVisible(frame, "__polar_hp_text_visible", frame.hpText, showHpText)
    end

    if frame.mpText ~= nil then
        local showMpText = cfg.show_value_text and statusText == "" and ClampNumber(cfg.mp_height, 0, 40, 0) > 0
        if showMpText then
            UpdateCachedText(frame, "__polar_mp_text", frame.mpText, GetValueText(cfg.value_text_mode, mp, maxMp, "mp"))
        end
        UpdateCachedVisible(frame, "__polar_mp_text_visible", frame.mpText, showMpText)
    end

    if frame.hpBar ~= nil and frame.hpBar.statusBar ~= nil then
        pcall(function()
            if frame.__polar_last_max_hp ~= maxHp then
                frame.hpBar.statusBar:SetMinMaxValues(0, maxHp)
                frame.__polar_last_max_hp = maxHp
            end
            if frame.__polar_last_hp ~= hp then
                frame.hpBar.statusBar:SetValue(hp)
                frame.__polar_last_hp = hp
            end
        end)
    end

    if frame.mpBar ~= nil and frame.mpBar.statusBar ~= nil and ClampNumber(cfg.mp_height, 0, 40, 0) > 0 then
        pcall(function()
            if frame.__polar_last_max_mp ~= maxMp then
                frame.mpBar.statusBar:SetMinMaxValues(0, maxMp)
                frame.__polar_last_max_mp = maxMp
            end
            if frame.__polar_last_mp ~= mp then
                frame.mpBar.statusBar:SetValue(mp)
                frame.__polar_last_mp = mp
            end
        end)
    end

    SafeShow(frame, true)
    return true
end

RaidFrames.Init = function(settings)
    RaidFrames.settings = settings

    if ADDON ~= nil and ADDON.GetContent ~= nil and UIC ~= nil and UIC.TARGET_UNITFRAME ~= nil then
        pcall(function()
            RaidFrames.target_unitframe = ADDON:GetContent(UIC.TARGET_UNITFRAME)
        end)
    end
end

RaidFrames.SetEnabled = function(enabled)
    RaidFrames.enabled = enabled and true or false
    if not RaidFrames.enabled then
        SafeShow(RaidFrames.container, false)
        for _, frame in pairs(RaidFrames.frames) do
            SafeShow(frame, false)
        end
        for _, label in pairs(RaidFrames.group_headers) do
            SafeShow(label, false)
        end
        for _, bg in pairs(RaidFrames.group_header_bgs) do
            pcall(function()
                if bg ~= nil then
                    if bg.SetVisible ~= nil then
                        bg:SetVisible(false)
                    elseif bg.Show ~= nil then
                        bg:Show(false)
                    end
                end
            end)
        end
        HideRaidContextMenu()
    end
end

RaidFrames.OnUpdate = function(settings, updateFlags)
    if settings == nil or type(settings.raidframes) ~= "table" then
        SafeShow(RaidFrames.container, false)
        return
    end

    local cfg = settings.raidframes
    local flags = type(updateFlags) == "table" and updateFlags or {}
    if not (RaidFrames.enabled and cfg.enabled) then
        SafeShow(RaidFrames.container, false)
        for _, frame in pairs(RaidFrames.frames) do
            SafeShow(frame, false)
        end
        return
    end

    EnsureContainer(cfg)

    local now = NowMs()
    RaidFrames.now_ms = now
    if flags.update_roster == true or STOCK_NAME_CACHE.last_refresh_ms == 0 then
        local doForce = flags.force_roster == true
        if doForce and now > 0 then
            RaidFrames.last_roster_force_refresh_ms = now
        end
        pcall(function()
            RefreshStockNameCache(doForce)
        end)
    end

    if flags.update_target == true or RaidFrames.current_target_id == nil then
        RaidFrames.current_target_id = nil
        pcall(function()
            if api.Unit ~= nil and api.Unit.GetUnitId ~= nil then
                RaidFrames.current_target_id = api.Unit:GetUnitId("target")
            end
        end)
    end

    TryHideStockRaidFrames(cfg)

    local any_shown = false
    local shownGroups = {}

    local layout = tostring(cfg.layout_mode or "party_columns")
    local max = 50
    if layout == "party_only" then
        max = 5
    end

    local activeUnits, activeSet = BuildActiveTeamUnits(max)
    for _, entry in ipairs(activeUnits) do
        if UpdateOne(entry.unit, entry.idx, settings, flags) then
            any_shown = true
            local groupIndex = math.floor(((entry.idx or 1) - 1) / 5) + 1
            shownGroups[groupIndex] = true
        end
    end

    for i = 1, 50 do
        local unit = string.format("team%d", i)
        if not activeSet[unit] then
            SafeShow(RaidFrames.frames[unit], false)
        end
    end

    UpdateGroupHeaders(cfg, shownGroups)
    SafeShow(RaidFrames.container, any_shown)
end

RaidFrames.Unload = function()
    SafeShow(RaidFrames.container, false)
    HideRaidContextMenu()
    for _, frame in pairs(RaidFrames.frames) do
        SafeShow(frame, false)
        pcall(function()
            if api.Interface ~= nil and api.Interface.Free ~= nil and frame ~= nil then
                api.Interface:Free(frame)
            end
        end)
    end
    for _, label in pairs(RaidFrames.group_headers) do
        SafeShow(label, false)
        pcall(function()
            if api.Interface ~= nil and api.Interface.Free ~= nil and label ~= nil then
                api.Interface:Free(label)
            end
        end)
    end
    for _, bg in pairs(RaidFrames.group_header_bgs) do
        pcall(function()
            if bg ~= nil then
                if bg.SetVisible ~= nil then
                    bg:SetVisible(false)
                elseif bg.Show ~= nil then
                    bg:Show(false)
                end
            end
        end)
    end
    pcall(function()
        if api.Interface ~= nil and api.Interface.Free ~= nil and RaidFrames.context_menu ~= nil then
            api.Interface:Free(RaidFrames.context_menu)
        end
    end)
    pcall(function()
        if api.Interface ~= nil and api.Interface.Free ~= nil and RaidFrames.container ~= nil then
            api.Interface:Free(RaidFrames.container)
        end
    end)
    RaidFrames.frames = {}
    RaidFrames.group_headers = {}
    RaidFrames.group_header_bgs = {}
    RaidFrames.container = nil
    RaidFrames.context_menu = nil
    RaidFrames.settings = nil
    RaidFrames.tried_hide_stock = false
    RaidFrames.current_target_id = nil
end

return RaidFrames
