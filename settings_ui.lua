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

local SettingsUi = {
    button = nil,
    window = nil,
    controls = {},
    actions = nil
}

local function safeShow(widget, show)
    if widget ~= nil and widget.Show ~= nil then
        pcall(function()
            widget:Show(show and true or false)
        end)
    end
end

local function safeSetText(widget, text)
    if widget ~= nil and widget.SetText ~= nil then
        pcall(function()
            widget:SetText(tostring(text or ""))
        end)
    end
end

local function createLabel(id, parent, text, x, y, fontSize, width)
    local label = api.Interface:CreateWidget("label", id, parent)
    label:AddAnchor("TOPLEFT", x, y)
    label:SetExtent(width or 220, 18)
    label:SetText(text)
    if label.style ~= nil then
        if label.style.SetFontSize ~= nil then
            label.style:SetFontSize(fontSize or 13)
        end
        if label.style.SetAlign ~= nil then
            label.style:SetAlign(ALIGN.LEFT)
        end
    end
    return label
end

local function createButton(id, parent, text, x, y, width, height)
    local button = api.Interface:CreateWidget("button", id, parent)
    button:AddAnchor("TOPLEFT", x, y)
    button:SetExtent(width or 100, height or 28)
    button:SetText(text)
    if api.Interface ~= nil and api.Interface.ApplyButtonSkin ~= nil then
        pcall(function()
            api.Interface:ApplyButtonSkin(button, BUTTON_BASIC.DEFAULT)
        end)
    end
    return button
end

local function createCheckbox(id, parent, text, x, y)
    local box = api.Interface:CreateWidget("button", id, parent)
    box:AddAnchor("TOPLEFT", x, y)
    box:SetExtent(24, 24)
    local label = createLabel(id .. "Label", parent, text, x + 34, y + 2, 13, 240)
    local proxy = { button = box, label = label, checked = false }
    function proxy:SetChecked(v)
        self.checked = v and true or false
        safeSetText(self.button, self.checked and "[X]" or "[ ]")
    end
    function proxy:GetChecked()
        return self.checked and true or false
    end
    function proxy:SetHandler(_, fn)
        if self.button ~= nil and self.button.SetHandler ~= nil then
            self.button:SetHandler("OnClick", fn)
        end
    end
    proxy:SetChecked(false)
    return proxy
end

local function createSlider(id, parent, text, x, y, minValue, maxValue)
    createLabel(id .. "Label", parent, text, x, y, 13, 170)
    local slider = nil
    if api._Library ~= nil and api._Library.UI ~= nil and api._Library.UI.CreateSlider ~= nil then
        local ok, res = pcall(function()
            return api._Library.UI.CreateSlider(id, parent)
        end)
        if ok then
            slider = res
        end
    end
    if slider ~= nil then
        slider:AddAnchor("TOPLEFT", x + 180, y - 4)
        slider:SetExtent(180, 26)
        slider:SetMinMaxValues(minValue, maxValue)
        if slider.SetStep ~= nil then
            slider:SetStep(1)
        elseif slider.SetValueStep ~= nil then
            slider:SetValueStep(1)
        end
    end
    local value = createLabel(id .. "Value", parent, "0", x + 370, y, 13, 50)
    return slider, value
end

local function sliderValue(slider, fallback)
    if slider ~= nil and slider.GetValue ~= nil then
        local ok, res = pcall(function()
            return slider:GetValue()
        end)
        if ok and res ~= nil then
            return math.floor((tonumber(res) or fallback or 0) + 0.5)
        end
    end
    return fallback
end

local function setSlider(slider, valueLabel, value)
    if slider ~= nil and slider.SetValue ~= nil then
        pcall(function()
            slider:SetValue(tonumber(value) or 0, false)
        end)
    end
    safeSetText(valueLabel, tostring(math.floor((tonumber(value) or 0) + 0.5)))
end

local function setStatus(text)
    safeSetText(SettingsUi.controls.status, text)
end

local function refreshControls()
    local settings = Shared.GetSettings()
    local raid = settings.raidframes
    local style = settings.style
    SettingsUi.controls.enabled:SetChecked(settings.enabled)
    SettingsUi.controls.raid_enabled:SetChecked(raid.enabled)
    SettingsUi.controls.hide_stock:SetChecked(raid.hide_stock)
    SettingsUi.controls.use_team_role_colors:SetChecked(raid.use_team_role_colors ~= false)
    SettingsUi.controls.show_target_highlight:SetChecked(raid.show_target_highlight ~= false)
    SettingsUi.controls.show_debuff_alert:SetChecked(raid.show_debuff_alert ~= false)
    SettingsUi.controls.bg_enabled:SetChecked(raid.bg_enabled and true or false)
    SettingsUi.controls.show_value_text:SetChecked(raid.show_value_text and true or false)
    SettingsUi.controls.bar_colors_enabled:SetChecked(style.bar_colors_enabled and true or false)
    setSlider(SettingsUi.controls.width, SettingsUi.controls.width_val, raid.width or 80)
    setSlider(SettingsUi.controls.hp_height, SettingsUi.controls.hp_height_val, raid.hp_height or 16)
    setSlider(SettingsUi.controls.mp_height, SettingsUi.controls.mp_height_val, raid.mp_height or 0)
    setSlider(SettingsUi.controls.name_font_size, SettingsUi.controls.name_font_size_val, raid.name_font_size or 11)
    setSlider(SettingsUi.controls.name_max_chars, SettingsUi.controls.name_max_chars_val, raid.name_max_chars or 0)
    SettingsUi.controls.layout.__value = tostring(raid.layout_mode or "party_columns")
    SettingsUi.controls.bar_style_mode.__value = tostring(raid.bar_style_mode or "shared")
    SettingsUi.controls.hp_texture_mode.__value = tostring(style.hp_texture_mode or "stock")
    safeSetText(SettingsUi.controls.layout, tostring(raid.layout_mode or "party_columns"))
    safeSetText(SettingsUi.controls.bar_style_mode, tostring(raid.bar_style_mode or "shared"))
    safeSetText(SettingsUi.controls.hp_texture_mode, tostring(style.hp_texture_mode or "stock"))
end

local function collectSettings()
    local settings = Shared.GetSettings()
    local raid = settings.raidframes
    local style = settings.style
    settings.enabled = SettingsUi.controls.enabled:GetChecked()
    raid.enabled = SettingsUi.controls.raid_enabled:GetChecked()
    raid.hide_stock = SettingsUi.controls.hide_stock:GetChecked()
    raid.use_team_role_colors = SettingsUi.controls.use_team_role_colors:GetChecked()
    raid.show_target_highlight = SettingsUi.controls.show_target_highlight:GetChecked()
    raid.show_debuff_alert = SettingsUi.controls.show_debuff_alert:GetChecked()
    raid.bg_enabled = SettingsUi.controls.bg_enabled:GetChecked()
    raid.show_value_text = SettingsUi.controls.show_value_text:GetChecked()
    style.bar_colors_enabled = SettingsUi.controls.bar_colors_enabled:GetChecked()
    raid.width = sliderValue(SettingsUi.controls.width, raid.width)
    raid.hp_height = sliderValue(SettingsUi.controls.hp_height, raid.hp_height)
    raid.mp_height = sliderValue(SettingsUi.controls.mp_height, raid.mp_height)
    raid.name_font_size = sliderValue(SettingsUi.controls.name_font_size, raid.name_font_size)
    raid.name_max_chars = sliderValue(SettingsUi.controls.name_max_chars, raid.name_max_chars)
end

local function cycleControlText(key, options)
    local current = tostring(SettingsUi.controls[key].__value or options[1])
    local nextIndex = 1
    for index, option in ipairs(options) do
        if tostring(option) == current then
            nextIndex = index + 1
            break
        end
    end
    if nextIndex > #options then
        nextIndex = 1
    end
    SettingsUi.controls[key].__value = tostring(options[nextIndex])
    safeSetText(SettingsUi.controls[key], SettingsUi.controls[key].__value)
    setStatus("Unsaved changes. Use Apply or Save.")
end

local function ensureWindow()
    if SettingsUi.window ~= nil then
        return
    end
    local wnd = api.Interface:CreateWindow(Shared.CONSTANTS.WINDOW_ID, Shared.CONSTANTS.TITLE, 500, 700)
    SettingsUi.window = wnd
    wnd:AddAnchor("CENTER", "UIParent", 0, 0)
    if wnd.SetHandler ~= nil then
        wnd:SetHandler("OnCloseByEsc", function()
            safeShow(wnd, false)
        end)
    end

    createLabel("polarRaidHint", wnd, "Standalone raid frames. Apply updates live; Save persists changes.", 24, 46, 12, 450)

    local y = 86
    createLabel("polarRaidSectionToggles", wnd, "Toggles", 24, y, 15, 120)
    y = y + 26
    SettingsUi.controls.enabled = createCheckbox("polarRaidEnabled", wnd, "Addon enabled", 24, y); y = y + 30
    SettingsUi.controls.raid_enabled = createCheckbox("polarRaidRaidEnabled", wnd, "Replacement frames enabled", 24, y); y = y + 30
    SettingsUi.controls.hide_stock = createCheckbox("polarRaidHideStock", wnd, "Try hide stock raid frames", 24, y); y = y + 30
    SettingsUi.controls.use_team_role_colors = createCheckbox("polarRaidRoleColors", wnd, "Use team role colors on HP bars", 24, y); y = y + 30
    SettingsUi.controls.show_target_highlight = createCheckbox("polarRaidTargetHighlight", wnd, "Highlight current target", 24, y); y = y + 30
    SettingsUi.controls.show_debuff_alert = createCheckbox("polarRaidDebuffAlert", wnd, "Show debuff alert badge", 24, y); y = y + 30
    SettingsUi.controls.bg_enabled = createCheckbox("polarRaidBgEnabled", wnd, "Show frame background", 24, y); y = y + 30
    SettingsUi.controls.show_value_text = createCheckbox("polarRaidValueText", wnd, "Show HP/MP text on bars", 24, y); y = y + 30
    SettingsUi.controls.bar_colors_enabled = createCheckbox("polarRaidBarColors", wnd, "Use custom HP/MP colors", 24, y); y = y + 40

    createLabel("polarRaidSectionSizing", wnd, "Sizing", 24, y, 15, 120)
    y = y + 26
    SettingsUi.controls.width, SettingsUi.controls.width_val = createSlider("polarRaidWidth", wnd, "Frame width", 24, y, 30, 300); y = y + 32
    SettingsUi.controls.hp_height, SettingsUi.controls.hp_height_val = createSlider("polarRaidHpHeight", wnd, "HP height", 24, y, 4, 60); y = y + 32
    SettingsUi.controls.mp_height, SettingsUi.controls.mp_height_val = createSlider("polarRaidMpHeight", wnd, "MP height", 24, y, 0, 40); y = y + 32
    SettingsUi.controls.name_font_size, SettingsUi.controls.name_font_size_val = createSlider("polarRaidNameFont", wnd, "Name font size", 24, y, 6, 32); y = y + 32
    SettingsUi.controls.name_max_chars, SettingsUi.controls.name_max_chars_val = createSlider("polarRaidNameMaxChars", wnd, "Name max chars (0 = full)", 24, y, 0, 32); y = y + 40

    createLabel("polarRaidSectionModes", wnd, "Modes", 24, y, 15, 120)
    y = y + 26
    createLabel("polarRaidLayoutLbl", wnd, "Layout mode", 24, y, 13, 140)
    SettingsUi.controls.layout = createButton("polarRaidLayoutBtn", wnd, "", 204, y - 4, 160, 28)
    SettingsUi.controls.layout:SetHandler("OnClick", function()
        cycleControlText("layout", { "party_columns", "single_list", "compact_grid", "party_only" })
    end)
    y = y + 34

    createLabel("polarRaidBarStyleLbl", wnd, "Bar style source", 24, y, 13, 140)
    SettingsUi.controls.bar_style_mode = createButton("polarRaidBarStyleBtn", wnd, "", 204, y - 4, 160, 28)
    SettingsUi.controls.bar_style_mode:SetHandler("OnClick", function()
        cycleControlText("bar_style_mode", { "shared", "stock" })
    end)
    y = y + 34

    createLabel("polarRaidTextureLbl", wnd, "HP texture mode", 24, y, 13, 140)
    SettingsUi.controls.hp_texture_mode = createButton("polarRaidTextureBtn", wnd, "", 204, y - 4, 160, 28)
    SettingsUi.controls.hp_texture_mode:SetHandler("OnClick", function()
        cycleControlText("hp_texture_mode", { "stock", "pc", "npc" })
    end)

    y = y + 52
    local applyButton = createButton("polarRaidApply", wnd, "Apply", 24, y, 82, 28)
    local saveButton = createButton("polarRaidSave", wnd, "Save", 114, y, 82, 28)
    local backupButton = createButton("polarRaidBackup", wnd, "Backup", 204, y, 82, 28)
    local importButton = createButton("polarRaidImport", wnd, "Import", 294, y, 82, 28)
    local closeButton = createButton("polarRaidClose", wnd, "Close", 414, y, 62, 28)
    y = y + 34
    local resetButton = createButton("polarRaidReset", wnd, "Reset", 24, y, 82, 28)
    SettingsUi.controls.status = createLabel("polarRaidStatus", wnd, "", 114, y + 4, 12, 350)

    local function applyChanges(persist)
        collectSettings()
        Shared.GetSettings().raidframes.layout_mode = tostring(SettingsUi.controls.layout.__value or Shared.GetSettings().raidframes.layout_mode or "party_columns")
        Shared.GetSettings().raidframes.bar_style_mode = tostring(SettingsUi.controls.bar_style_mode.__value or Shared.GetSettings().raidframes.bar_style_mode or "shared")
        Shared.GetSettings().style.hp_texture_mode = tostring(SettingsUi.controls.hp_texture_mode.__value or Shared.GetSettings().style.hp_texture_mode or "stock")
        if type(SettingsUi.actions) == "table" and type(SettingsUi.actions.apply) == "function" then
            SettingsUi.actions.apply()
        end
        if persist and type(SettingsUi.actions) == "table" and type(SettingsUi.actions.save) == "function" then
            local ok, detail = SettingsUi.actions.save()
            setStatus(ok and ("Saved" .. (detail and detail ~= "" and (": " .. tostring(detail)) or "")) or ("Save failed: " .. tostring(detail)))
        else
            setStatus("Applied")
        end
        refreshControls()
    end

    applyButton:SetHandler("OnClick", function()
        applyChanges(false)
    end)
    saveButton:SetHandler("OnClick", function()
        applyChanges(true)
    end)
    backupButton:SetHandler("OnClick", function()
        if type(SettingsUi.actions) == "table" and type(SettingsUi.actions.backup) == "function" then
            local ok, detail = SettingsUi.actions.backup()
            setStatus(ok and ("Backup saved: " .. tostring(detail or "")) or ("Backup failed: " .. tostring(detail)))
        end
    end)
    importButton:SetHandler("OnClick", function()
        if type(SettingsUi.actions) == "table" and type(SettingsUi.actions.import) == "function" then
            local ok, detail = SettingsUi.actions.import()
            setStatus(ok and "Imported latest backup" or ("Import failed: " .. tostring(detail)))
            refreshControls()
        end
    end)
    resetButton:SetHandler("OnClick", function()
        if type(SettingsUi.actions) == "table" and type(SettingsUi.actions.reset_all) == "function" then
            SettingsUi.actions.reset_all()
            refreshControls()
            setStatus("Reset to defaults")
        end
    end)
    closeButton:SetHandler("OnClick", function()
        safeShow(wnd, false)
    end)

    safeShow(wnd, false)
    refreshControls()
end

local function ensureButton()
    if SettingsUi.button ~= nil then
        return
    end
    local parent = api.rootWindow
    if parent == nil then
        return
    end
    local button = createButton(Shared.CONSTANTS.BUTTON_ID, parent, "PR", 0, 0, 34, 28)
    SettingsUi.button = button
    local settings = Shared.GetSettings()
    button:AddAnchor("TOPLEFT", "UIParent", tonumber(settings.button_x) or 90, tonumber(settings.button_y) or 420)
    button:SetHandler("OnClick", function()
        SettingsUi.Toggle()
    end)
end

function SettingsUi.Refresh()
    if SettingsUi.window ~= nil then
        refreshControls()
    end
end

function SettingsUi.Toggle()
    ensureWindow()
    local show = true
    if SettingsUi.window ~= nil and SettingsUi.window.IsVisible ~= nil then
        local ok, visible = pcall(function()
            return SettingsUi.window:IsVisible()
        end)
        if ok then
            show = not visible
        end
    end
    safeShow(SettingsUi.window, show)
    if show then
        refreshControls()
    end
end

function SettingsUi.Init(actions)
    SettingsUi.actions = actions or {}
    ensureButton()
    ensureWindow()
    refreshControls()
end

function SettingsUi.Unload()
    if SettingsUi.button ~= nil and api.Interface ~= nil and api.Interface.Free ~= nil then
        pcall(function()
            api.Interface:Free(SettingsUi.button)
        end)
    end
    if SettingsUi.window ~= nil and api.Interface ~= nil and api.Interface.Free ~= nil then
        pcall(function()
            api.Interface:Free(SettingsUi.window)
        end)
    end
    SettingsUi.button = nil
    SettingsUi.window = nil
    SettingsUi.controls = {}
end

return SettingsUi
