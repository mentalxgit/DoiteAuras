---------------------------------------------------------------
-- DoiteBars.lua
--
-- HOW TO ADD A NEW BAR KIND:
--   1. Add an entry to DoiteBars.Kinds (see below).
--   2. Add the key to DoiteBars.KindOrder.
--   3. That's it. The rest of the system picks it up automatically.
--
-- EDIT PANEL:
--   When the user clicks Edit on a Bar list entry, DoiteEdit.lua
--   calls DoiteBars.InjectEditControls(condFrame, key).
--   This hides all of condFrame's normal children and injects a
--   scrollable Bar-specific settings container directly inside it.
--   DoiteBars.CleanupCondFrame(condFrame) reverses this.
---------------------------------------------------------------

DoiteBars = DoiteBars or {}

---------------------------------------------------------------
-- Bar Kind Registry
---------------------------------------------------------------
DoiteBars.Kinds = {

    Powerbar = {
        label = "Powerbar",
        getValues = function()
            local cur = UnitMana("player")    or 0
            local max = UnitManaMax("player") or 1
            if max <= 0 then max = 1 end
            return cur, max
        end,
        r = 0.0, g = 0.44, b = 0.87,
    },

    Healthbar = {
        label = "Healthbar",
        getValues = function()
            local cur = UnitHealth("player")    or 0
            local max = UnitHealthMax("player") or 1
            if max <= 0 then max = 1 end
            return cur, max
        end,
        r = 0.0, g = 0.9, b = 0.0,
    },
}

DoiteBars.KindOrder = {
    "Powerbar",
    "Healthbar",
}

---------------------------------------------------------------
-- Per-power-type colour lookup
-- 0=Mana  1=Rage  2=Focus  3=Energy
---------------------------------------------------------------
local DA_PowerColors = {
    [0] = { r = 0.00, g = 0.44, b = 0.87 },
    [1] = { r = 1.00, g = 0.00, b = 0.00 },
    [2] = { r = 0.90, g = 0.61, b = 0.23 },
    [3] = { r = 1.00, g = 0.90, b = 0.00 },
}

local function DA_BarColorForPowerType()
    local pt = UnitPowerType and UnitPowerType("player") or 0
    local c  = DA_PowerColors[pt]
    if c then return c.r, c.g, c.b end
    return 0.0, 0.44, 0.87
end

---------------------------------------------------------------
-- Internal frame pool
---------------------------------------------------------------
local barFrames = {}
local BAR_BORDER = 1

---------------------------------------------------------------
-- Shared defaults
---------------------------------------------------------------
local BAR_DEFAULTS = {
    barWidth      = 200,
    barHeight     = 24,
    offsetX       = 0,
    offsetY       = 0,
    scale         = 1,
    alpha         = 1,
    inCombat      = true,
    outCombat     = true,
    barR          = -1,
    barG          = -1,
    barB          = -1,
    barAlpha      = 1,
    bgR           = 0,
    bgG           = 0,
    bgB           = 0,
    bgAlpha       = 0.7,
    textFormat    = "Actual",
    textPosition  = "Center",
    fontSize      = 10,
}

local function DA_BarApplyDefaults(data)
    for k, v in pairs(BAR_DEFAULTS) do
        if data[k] == nil then
            data[k] = v
        end
    end
end

---------------------------------------------------------------
-- DoiteBars.CreateOrUpdateBar(key, data)
---------------------------------------------------------------
function DoiteBars.CreateOrUpdateBar(key, data)
    if not key or not data then return nil end
    DA_BarApplyDefaults(data)

    local globalName = "DoiteBar_" .. key
    local f = barFrames[key] or _G[globalName]

    local w = data.barWidth
    local h = data.barHeight

    if not f then
        f = CreateFrame("Frame", globalName, UIParent)
        f:SetFrameStrata("MEDIUM")
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetWidth(w)
        f:SetHeight(h)

        -- Background
        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAllPoints(f)
        f.bg:SetTexture(0, 0, 0, 1)

        -- Fill bar
        f.bar = CreateFrame("StatusBar", nil, f)
        f.bar:SetPoint("TOPLEFT",     f, "TOPLEFT",     BAR_BORDER, -BAR_BORDER)
        f.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -BAR_BORDER, BAR_BORDER)
        f.bar:SetMinMaxValues(0, 1)
        f.bar:SetValue(1)
        f.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")

        -- Label
        f.label = f.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.label:SetAllPoints(f.bar)
        f.label:SetJustifyH("CENTER")
        f.label:SetJustifyV("MIDDLE")

        f._daKey = key

        f:SetScript("OnDragStart", function()
            local fk = this._daKey
            local ek = _G["DoiteEdit_CurrentKey"]
            if not ek or ek ~= fk then return end
            _G["DoiteUI_Dragging"] = true
            this:StartMoving()
            this._daDragging = true
        end)

        f:SetScript("OnDragStop", function()
            this:StopMovingOrSizing()
            this._daDragging = nil
            _G["DoiteUI_Dragging"] = false

            local fk = this._daKey
            if not fk then return end

            local rScale = UIParent:GetEffectiveScale()
            local rX, rY = UIParent:GetCenter()
            rX, rY = rX * rScale, rY * rScale

            local pScale = this:GetEffectiveScale()
            local pX, pY = this:GetCenter()
            pX, pY = pX * pScale, pY * pScale

            local x = math.floor((pX - rX) / pScale * 10 + 0.5) / 10
            local y = math.floor((pY - rY) / pScale * 10 + 0.5) / 10

            local d = DoiteAurasDB and DoiteAurasDB.spells and DoiteAurasDB.spells[fk]
            if d then
                d.offsetX = x
                d.offsetY = y
            end

            -- Sync position sliders in injected edit panel if open
            DoiteBars._SyncPositionSliders(fk, x, y)
        end)

        barFrames[key] = f
        _G[globalName] = f
    end

    -- Apply size
    f:SetWidth(w)
    f:SetHeight(h)

    -- Apply position
    if not f._daDragging then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", data.offsetX, data.offsetY)
    end

    -- Scale / alpha
    f:SetScale(data.scale)
    f:SetAlpha(data.alpha)

    -- Background colour
    f.bg:SetTexture(data.bgR, data.bgG, data.bgB, data.bgAlpha)

    -- Label font
    if f.label and f.label.SetFont then
        f.label:SetFont("Fonts\\FRIZQT__.TTF", data.fontSize, "OUTLINE")
    end

    -- Label position
    f.label:ClearAllPoints()
    local tp = data.textPosition or "Center"
    if tp == "Center" then
        f.label:SetAllPoints(f.bar)
        f.label:SetJustifyH("CENTER")
        f.label:SetJustifyV("MIDDLE")
    elseif tp == "TopLeft" then
        f.label:SetPoint("TOPLEFT", f.bar, "TOPLEFT", 2, -2)
        f.label:SetJustifyH("LEFT")
        f.label:SetJustifyV("TOP")
    elseif tp == "TopRight" then
        f.label:SetPoint("TOPRIGHT", f.bar, "TOPRIGHT", -2, -2)
        f.label:SetJustifyH("RIGHT")
        f.label:SetJustifyV("TOP")
    elseif tp == "BottomLeft" then
        f.label:SetPoint("BOTTOMLEFT", f.bar, "BOTTOMLEFT", 2, 2)
        f.label:SetJustifyH("LEFT")
        f.label:SetJustifyV("BOTTOM")
    elseif tp == "BottomRight" then
        f.label:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMRIGHT", -2, 2)
        f.label:SetJustifyH("RIGHT")
        f.label:SetJustifyV("BOTTOM")
    end

    -- Edit mode mouse
    local editKey = _G["DoiteEdit_CurrentKey"]
    if editKey and editKey == key then
        f:EnableMouse(true)
    else
        f:EnableMouse(false)
    end

    return f
end

---------------------------------------------------------------
-- DoiteBars.RefreshBar(key, data)
---------------------------------------------------------------
function DoiteBars.RefreshBar(key, data)
    if not key or not data then return end
    DA_BarApplyDefaults(data)

    local f = barFrames[key] or _G["DoiteBar_" .. key]
    if not f or not f.bar then return end

    -- Visibility (combat state)
    local inCombat = UnitAffectingCombat and UnitAffectingCombat("player") or false
    local visible  = (inCombat and data.inCombat) or ((not inCombat) and data.outCombat)
    if not visible then
        f:Hide()
        return
    end
    f:Show()

    local kindKey = data.barType or "Powerbar"
    local kind    = DoiteBars.Kinds[kindKey]
    if not kind then return end

    local cur, max = kind.getValues()

    -- Bar colour
    local r, g, b
    if data.barR and data.barR >= 0 then
        r, g, b = data.barR, data.barG, data.barB
    elseif kindKey == "Powerbar" then
        r, g, b = DA_BarColorForPowerType()
    else
        r, g, b = kind.r, kind.g, kind.b
    end
    f.bar:SetStatusBarColor(r, g, b, data.barAlpha)

    -- Fill value
    f.bar:SetMinMaxValues(0, max)
    f.bar:SetValue(math.min(cur, max))

    -- Label text
    if f.label then
        local fmt = data.textFormat or "Actual"
        local txt
        if fmt == "Percent" then
            local pct = (max > 0) and math.floor(cur / max * 100 + 0.5) or 0
            txt = tostring(pct) .. "%"
        elseif fmt == "Short" then
            local function shorten(n)
                if n >= 1000 then return string.format("%.1fk", n / 1000) end
                return tostring(n)
            end
            txt = shorten(cur) .. " / " .. shorten(max)
        else
            txt = tostring(cur) .. " / " .. tostring(max)
        end
        f.label:SetText(txt)
    end
end

---------------------------------------------------------------
-- DoiteBars.RefreshAll()
---------------------------------------------------------------
function DoiteBars.RefreshAll()
    if not DoiteAurasDB or not DoiteAurasDB.spells then return end
    for key, data in pairs(DoiteAurasDB.spells) do
        if data and data.type == "Bar" then
            local f = DoiteBars.CreateOrUpdateBar(key, data)
            if f then DoiteBars.RefreshBar(key, data) end
        end
    end
end

---------------------------------------------------------------
-- DoiteBars.HideBar / DestroyBar / GetBarFrame
---------------------------------------------------------------
function DoiteBars.HideBar(key)
    if not key then return end
    local f = barFrames[key] or _G["DoiteBar_" .. key]
    if f then f:Hide() end
end

function DoiteBars.DestroyBar(key)
    if not key then return end
    local f = barFrames[key] or _G["DoiteBar_" .. key]
    if f then
        f:Hide()
        barFrames[key] = nil
    end
end

function DoiteBars.GetBarFrame(key)
    return barFrames[key] or _G["DoiteBar_" .. key]
end

---------------------------------------------------------------
-- Event-driven bar refresh
---------------------------------------------------------------
local barEventFrame = CreateFrame("Frame", "DoiteBarsEventFrame")
barEventFrame:RegisterEvent("UNIT_MANA")
barEventFrame:RegisterEvent("UNIT_HEALTH")
barEventFrame:RegisterEvent("UNIT_MAXMANA")
barEventFrame:RegisterEvent("UNIT_MAXHEALTH")
barEventFrame:RegisterEvent("UNIT_RAGE")
barEventFrame:RegisterEvent("UNIT_MAXRAGE")
barEventFrame:RegisterEvent("UNIT_ENERGY")
barEventFrame:RegisterEvent("UNIT_MAXENERGY")
barEventFrame:RegisterEvent("UNIT_FOCUS")
barEventFrame:RegisterEvent("UNIT_MAXFOCUS")
barEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
barEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
barEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

barEventFrame:SetScript("OnEvent", function()
    if _G["DoiteAuras_HardDisabled"] == true then return end
    if  event == "UNIT_MANA" or event == "UNIT_HEALTH" or
        event == "UNIT_MAXMANA" or event == "UNIT_MAXHEALTH" or
        event == "UNIT_RAGE" or event == "UNIT_MAXRAGE" or
        event == "UNIT_ENERGY" or event == "UNIT_MAXENERGY" or
        event == "UNIT_FOCUS" or event == "UNIT_MAXFOCUS" then
            if arg1 ~= "player" then return end
    end
    DoiteBars.RefreshAll()
end)

-- Initial render on login
local barWorldFrame = CreateFrame("Frame", "DoiteBarsWorldFrame")
barWorldFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
barWorldFrame:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        DoiteBars.RefreshAll()
    end
end)

---------------------------------------------------------------
-- ============================================================
-- BAR EDIT PANEL — injected directly into condFrame
-- ============================================================
--
-- DoiteBars.InjectEditControls(condFrame, key)
--   Called from UpdateCondFrameForKey in DoiteEdit.lua when
--   data.type == "Bar". Hides all of condFrame's normal
--   children and injects scrollable settings container.
--
-- DoiteBars.CleanupCondFrame(condFrame)
--   Called from condFrame OnHide. Destroys the injected
--   container and restores condFrame's normal children.
-- ============================================================

-- Key currently being edited via injected panel
local _beKey = nil

-- Reference to the injected scrollable container
-- destroyed and recreated each time a Bar is opened
local _beContainer = nil

local _beSliderX = nil
local _beSliderY = nil

---------------------------------------------------------------
-- Slider helper; parents to a given frame, mirrors MakeSlider
---------------------------------------------------------------
local function BE_MakeSlider(parent, name, text, x, y, width, minVal, maxVal, step)
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetWidth(width)
    s:SetHeight(16)
    s:SetMinMaxValues(minVal, maxVal)
    s:SetValueStep(step)
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local txt  = _G[s:GetName() .. "Text"]
    local low  = _G[s:GetName() .. "Low"]
    local high = _G[s:GetName() .. "High"]
    if txt  then txt:SetText(text);             txt:SetFontObject("GameFontNormalSmall") end
    if low  then low:SetText(tostring(minVal));  low:SetFontObject("GameFontNormalSmall") end
    if high then high:SetText(tostring(maxVal)); high:SetFontObject("GameFontNormalSmall") end

    local eb = CreateFrame("EditBox", name .. "_EditBox", parent, "InputBoxTemplate")
    eb:SetWidth(38); eb:SetHeight(18)
    eb:SetPoint("TOP", s, "BOTTOM", 3, -8)
    eb:SetAutoFocus(false)
    eb:SetText("0")
    eb:SetJustifyH("CENTER")
    eb:SetFontObject("GameFontNormalSmall")
    eb.slider    = s
    eb._updating = false

    s:SetScript("OnValueChanged", function()
        if this._isSyncing then return end
        local v = math.floor((this:GetValue() or 0) + 0.5)
        if eb and not eb._updating then
            eb._updating = true
            eb:SetText(tostring(v))
            eb._updating = false
        end
        if this.updateFunc then this.updateFunc(v) end
    end)

    s:SetScript("OnMouseDown", function() _G["DoiteUI_Dragging"] = true end)
    s:SetScript("OnMouseUp", function()
        _G["DoiteUI_Dragging"] = false
        if DoiteEdit_FlushHeavy then DoiteEdit_FlushHeavy() end
    end)

    local function CommitEB(box)
        if not box or not box.slider then return end
        local val = tonumber(box:GetText())
        if not val then
            box:SetText(tostring(math.floor((box.slider:GetValue() or 0) + 0.5)))
        else
            val = math.max(minVal, math.min(maxVal, val))
            box._updating = true
            box.slider:SetValue(val)
            box._updating = false
        end
    end

    eb:SetScript("OnTextChanged", function()
        if this._updating then return end
        local num = tonumber(this:GetText())
        if not num then return end
        num = math.max(minVal, math.min(maxVal, num))
        this._updating = true
        this.slider:SetValue(num)
        this._updating = false
    end)
    eb:SetScript("OnEnterPressed", function() CommitEB(this); this:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function()
        this:ClearFocus()
        this._updating = true
        this:SetText(tostring(math.floor((this.slider:GetValue() or 0) + 0.5)))
        this._updating = false
    end)
    eb:SetScript("OnEditFocusLost", function() CommitEB(this) end)

    return s, eb
end

---------------------------------------------------------------
-- Section header + separator
---------------------------------------------------------------
local function BE_MakeHeader(parent, y, labelText)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    fs:SetText("|cff6FA8DC" .. labelText .. "|r")

    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  parent, "TOPLEFT",  6, y - 14)
    sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, y - 14)
    sep:SetTexture(1, 1, 1)
    if sep.SetVertexColor then sep:SetVertexColor(1, 1, 1, 0.25) end
end

---------------------------------------------------------------
-- RGB slider trio
---------------------------------------------------------------
local function BE_MakeRGBSliders(parent, namePrefix, baseX, baseY, sliderW, onChangeFn)
    local gap = 8
    local sR, _ = BE_MakeSlider(parent, namePrefix .. "_R", "Red",   baseX,                    baseY, sliderW, 0, 100, 1)
    local sG, _ = BE_MakeSlider(parent, namePrefix .. "_G", "Green", baseX + sliderW + gap,     baseY, sliderW, 0, 100, 1)
    local sB, _ = BE_MakeSlider(parent, namePrefix .. "_B", "Blue",  baseX + 2*(sliderW + gap), baseY, sliderW, 0, 100, 1)
    sR.updateFunc = function(v) onChangeFn("r", v / 100) end
    sG.updateFunc = function(v) onChangeFn("g", v / 100) end
    sB.updateFunc = function(v) onChangeFn("b", v / 100) end
    return sR, sG, sB
end

---------------------------------------------------------------
-- Sync position sliders when bar is dragged on screen
---------------------------------------------------------------
function DoiteBars._SyncPositionSliders(key, x, y)
    if _beKey ~= key then return end
    if _beSliderX then
        _beSliderX._isSyncing = true
        _beSliderX:SetValue(x)
        _beSliderX._isSyncing = false
    end
    if _beSliderY then
        _beSliderY._isSyncing = true
        _beSliderY:SetValue(y)
        _beSliderY._isSyncing = false
    end
end

---------------------------------------------------------------
-- BE_BuildContainer(cf)
-- Creates the scrollable container as a child of condFrame.
-- cf = The main "condFrame" (parent window)
---------------------------------------------------------------
local function BE_BuildContainer(cf)
    -- Defines boundaries of settings area
    local cW = cf:GetWidth() - 43
    local cH = 190

    -- Container: anchor for scroll area
    local container = CreateFrame("Frame", "DoiteBarsEditContainer", cf)
    container:SetWidth(cW)
    container:SetHeight(cH)
    container:SetPoint("TOPLEFT", cf, "TOPLEFT", 14, -173)
    container:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
    })
    container:SetBackdropColor(0, 0, 0, 0.7)

    -- Scrollframe
    -- Using default blizzard template to get standard scrollbar etc
    local scrollFrame = CreateFrame("ScrollFrame", "DoiteBarsEditScroll", container, "UIPanelScrollFrameTemplate")
    -- Positioning the scrollbar in the container:
    -- -25 on the right leaves space for the scrollbar (surely)
    scrollFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -25, 5)

    -- Enables mouse scrolling
    if scrollFrame.EnableMouseWheel then scrollFrame:EnableMouseWheel(true) end

    -- the content inside of the scrollframe
    local content = CreateFrame("Frame", "DoiteBarsEditContent", scrollFrame)
    content:SetWidth(cW - 22)
    content:SetHeight(1200) -- Increase/decrease this depending on the amount of options in the frame
    scrollFrame:SetScrollChild(content) -- tells scrollframe that it needs to move content

    -- returned for use in injectcontrolls.
    return container, content
end

---------------------------------------------------------------
-- BE_PopulateContent(content, key)
---------------------------------------------------------------
local function BE_PopulateContent(content, key)
    local data = DoiteAurasDB and DoiteAurasDB.spells and DoiteAurasDB.spells[key]
    if not data then return {} end
    DA_BarApplyDefaults(data)

    local sliderW = math.floor((content:GetWidth() - 40 - 16) / 3)
    if sliderW < 80 then sliderW = 80 end
    local baseX = 10
    local gap   = 8
    local y     = -10
    local refs  = {}

    BE_MakeHeader(content, y, "BAR INFO")
    y = y - 28

    refs.nameLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    refs.nameLabel:SetPoint("TOPLEFT", content, "TOPLEFT", baseX, y)
    refs.nameLabel:SetText("Name: " .. (data.displayName or key))
    y = y - 16

    refs.kindLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    refs.kindLabel:SetPoint("TOPLEFT", content, "TOPLEFT", baseX, y)
    refs.kindLabel:SetText("Kind: " .. (data.barType or "Powerbar"))
    y = y - 26

    BE_MakeHeader(content, y, "VISIBILITY")
    y = y - 28

    refs.cbInCombat = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    refs.cbInCombat:SetWidth(20); refs.cbInCombat:SetHeight(20)
    refs.cbInCombat:SetPoint("TOPLEFT", content, "TOPLEFT", baseX, y)
    refs.cbInCombat:SetChecked(data.inCombat and 1 or 0)
    local lblIn = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lblIn:SetPoint("LEFT", refs.cbInCombat, "RIGHT", 2, 0)
    lblIn:SetText("Show in combat")
    refs.cbInCombat:SetScript("OnClick", function()
        if not _beKey then return end
        local d = DoiteAurasDB.spells[_beKey]
        if d then d.inCombat = (this:GetChecked() == 1) end
    end)

    refs.cbOutCombat = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    refs.cbOutCombat:SetWidth(20); refs.cbOutCombat:SetHeight(20)
    refs.cbOutCombat:SetPoint("TOPLEFT", content, "TOPLEFT", baseX + 160, y)
    refs.cbOutCombat:SetChecked(data.outCombat and 1 or 0)
    local lblOut = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lblOut:SetPoint("LEFT", refs.cbOutCombat, "RIGHT", 2, 0)
    lblOut:SetText("Show out of combat")
    lblOut:SetWidth(120)
    refs.cbOutCombat:SetScript("OnClick", function()
        if not _beKey then return end
        local d = DoiteAurasDB.spells[_beKey]
        if d then d.outCombat = (this:GetChecked() == 1) end
    end)
    y = y - 35

    BE_MakeHeader(content, y, "POSITION & SIZE")
    y = y - 28

    local minX, maxX, minY, maxY = -1200, 1200, -1200, 1200
    local sX, _ = BE_MakeSlider(content, "DoiteBarsEdit_SliderX", "Horizontal Position", baseX, y, sliderW, minX, maxX, 1)
    local sY, _ = BE_MakeSlider(content, "DoiteBarsEdit_SliderY", "Vertical Position", baseX + sliderW + gap, y, sliderW, minY, maxY, 1)
    refs.sliderX = sX
    refs.sliderY = sY
    sX:SetValue(data.offsetX)
    sY:SetValue(data.offsetY)
    sX.updateFunc = function(v)
        if not _beKey then return end
        local d = DoiteAurasDB.spells[_beKey]
        if d then d.offsetX = v; DoiteBars.CreateOrUpdateBar(_beKey, d) end
    end
    sY.updateFunc = function(v)
        if not _beKey then return end
        local d = DoiteAurasDB.spells[_beKey]
        if d then d.offsetY = v; DoiteBars.CreateOrUpdateBar(_beKey, d) end
    end
    y = y - 55

    local sW, _ = BE_MakeSlider(content, "DoiteBarsEdit_SliderW", "Width",  baseX,                 y, sliderW, 20, 800, 1)
    local sH, _ = BE_MakeSlider(content, "DoiteBarsEdit_SliderH", "Height", baseX + sliderW + gap, y, sliderW, 4,  200, 1)
    sW:SetValue(data.barWidth)
    sH:SetValue(data.barHeight)
    sW.updateFunc = function(v)
        if not _beKey then return end
        local d = DoiteAurasDB.spells[_beKey]
        if d then d.barWidth = v; DoiteBars.CreateOrUpdateBar(_beKey, d) end
    end
    sH.updateFunc = function(v)
        if not _beKey then return end
        local d = DoiteAurasDB.spells[_beKey]
        if d then d.barHeight = v; DoiteBars.CreateOrUpdateBar(_beKey, d) end
    end
    y = y - 55

    BE_MakeHeader(content, y, "BAR COLOR  (set R to -1 to use default)")
    y = y - 28

    local sBarR, sBarG, sBarB = BE_MakeRGBSliders(content, "DoiteBarsEdit_BarRGB", baseX, y, sliderW,
        function(channel, val)
            if not _beKey then return end
            local d = DoiteAurasDB.spells[_beKey]
            if not d then return end
            if channel == "r" then d.barR = val
            elseif channel == "g" then d.barG = val
            else d.barB = val end
        end)
    sBarR:SetMinMaxValues(-1, 100)
    sBarR:SetValue(data.barR >= 0 and math.floor(data.barR * 100 + 0.5) or -1)
    sBarG:SetValue(data.barG >= 0 and math.floor(data.barG * 100 + 0.5) or -1)
    sBarB:SetValue(data.barB >= 0 and math.floor(data.barB * 100 + 0.5) or -1)
    y = y - 55

    local sBarA, _ = BE_MakeSlider(content, "DoiteBarsEdit_BarAlpha", "Bar Opacity", baseX, y, sliderW, 0, 100, 1)
    sBarA:SetValue(math.floor(data.barAlpha * 100 + 0.5))
    sBarA.updateFunc = function(v)
        if not _beKey then return end
        local d = DoiteAurasDB.spells[_beKey]
        if d then d.barAlpha = v / 100 end
    end
    y = y - 55

    BE_MakeHeader(content, y, "BACKGROUND COLOR")
    y = y - 28

    local sBgR, sBgG, sBgB = BE_MakeRGBSliders(content, "DoiteBarsEdit_BgRGB", baseX, y, sliderW,
        function(channel, val)
            if not _beKey then return end
            local d = DoiteAurasDB.spells[_beKey]
            if not d then return end
            if channel == "r" then d.bgR = val
            elseif channel == "g" then d.bgG = val
            else d.bgB = val end
            DoiteBars.CreateOrUpdateBar(_beKey, d)
        end)
    sBgR:SetValue(math.floor(data.bgR * 100 + 0.5))
    sBgG:SetValue(math.floor(data.bgG * 100 + 0.5))
    sBgB:SetValue(math.floor(data.bgB * 100 + 0.5))
    y = y - 55

    local sBgA, _ = BE_MakeSlider(content, "DoiteBarsEdit_BgAlpha", "Background Opacity", baseX, y, sliderW, 0, 100, 1)
    sBgA:SetValue(math.floor(data.bgAlpha * 100 + 0.5))
    sBgA.updateFunc = function(v)
        if not _beKey then return end
        local d = DoiteAurasDB.spells[_beKey]
        if d then
            d.bgAlpha = v / 100
            DoiteBars.CreateOrUpdateBar(_beKey, d)
        end
    end
    y = y - 55

    BE_MakeHeader(content, y, "TEXT")
    y = y - 28

    local sFontSize, _ = BE_MakeSlider(content, "DoiteBarsEdit_FontSize", "Font Size", baseX, y, sliderW, 6, 32, 1)
    sFontSize:SetValue(data.fontSize)
    sFontSize.updateFunc = function(v)
        if not _beKey then return end
        local d = DoiteAurasDB.spells[_beKey]
        if d then
            d.fontSize = v
            DoiteBars.CreateOrUpdateBar(_beKey, d)
        end
    end
    y = y - 55

    -- Format buttons
    local fmtLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fmtLabel:SetPoint("TOPLEFT", content, "TOPLEFT", baseX, y)
    fmtLabel:SetText("Format:")
    y = y - 20

    local fmtOptions = { "Actual", "Short", "Percent" }
    local fmtBtns    = {}
    local fmtX       = baseX
    for i = 1, table.getn(fmtOptions) do
        local opt = fmtOptions[i]
        local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        btn:SetWidth(70); btn:SetHeight(20)
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", fmtX, y)
        btn:SetText(opt)
        btn._fmtValue = opt
        if opt == data.textFormat then
            btn:SetText("|cff6FA8DC" .. opt .. "|r")
        end
        btn:SetScript("OnClick", function()
            if not _beKey then return end
            local d = DoiteAurasDB.spells[_beKey]
            if not d then return end
            d.textFormat = this._fmtValue
            for _, fb in ipairs(fmtBtns) do
                if fb._fmtValue == d.textFormat then
                    fb:SetText("|cff6FA8DC" .. fb._fmtValue .. "|r")
                else
                    fb:SetText(fb._fmtValue)
                end
            end
        end)
        fmtBtns[i] = btn
        fmtX = fmtX + 75
    end
    y = y - 35

    -- Text position buttons
    local posLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    posLabel:SetPoint("TOPLEFT", content, "TOPLEFT", baseX, y)
    posLabel:SetText("Text position:")
    y = y - 20

    local posOptions = { "Center", "TopLeft", "TopRight", "BottomLeft", "BottomRight" }
    local posBtns    = {}
    local posX       = baseX
    for i = 1, table.getn(posOptions) do
        local opt = posOptions[i]
        local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        btn:SetWidth(82); btn:SetHeight(20)
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", posX, y)
        btn:SetText(opt)
        btn._posValue = opt
        if opt == data.textPosition then
            btn:SetText("|cff6FA8DC" .. opt .. "|r")
        end
        btn:SetScript("OnClick", function()
            if not _beKey then return end
            local d = DoiteAurasDB.spells[_beKey]
            if not d then return end
            d.textPosition = this._posValue
            DoiteBars.CreateOrUpdateBar(_beKey, d)
            for _, pb in ipairs(posBtns) do
                if pb._posValue == d.textPosition then
                    pb:SetText("|cff6FA8DC" .. pb._posValue .. "|r")
                else
                    pb:SetText(pb._posValue)
                end
            end
        end)
        posBtns[i] = btn
        if i == 3 then
            y = y - 25
            posX = baseX
        else
            posX = posX + 87
        end
    end

    return refs
end

---------------------------------------------------------------
-- UpdateSliderValues : Syncs slider values to current pos
---------------------------------------------------------------
local function BE_UpdateSliderValues(refs, data)
    if refs.sliderX then refs.sliderX:SetValue(data.offsetX or 0) end
    if refs.sliderY then refs.sliderY:SetValue(data.offsetY or 0) end
    if refs.sliderW then refs.sliderW:SetValue(data.barWidth or 200) end
    if refs.sliderH then refs.sliderH:SetValue(data.barHeight or 24) end
    -- bar color
    if refs.sBarR then refs.sBarR:SetValue(data.barR >= 0 and math.floor(data.barR * 100 + 0.5) or -1) end
    if refs.sBarG then refs.sBarG:SetValue(data.barG >= 0 and math.floor(data.barG * 100 + 0.5) or -1) end
    if refs.sBarB then refs.sBarB:SetValue(data.barB >= 0 and math.floor(data.barB * 100 + 0.5) or -1) end
    if refs.sBarA then refs.sBarA:SetValue(math.floor(data.barAlpha * 100 + 0.5)) end
    -- bg color
    if refs.sBgR then refs.sBgR:SetValue(math.floor(data.bgR * 100 + 0.5)) end
    if refs.sBgG then refs.sBgG:SetValue(math.floor(data.bgG * 100 + 0.5)) end
    if refs.sBgB then refs.sBgB:SetValue(math.floor(data.bgB * 100 + 0.5)) end
    if refs.sBgA then refs.sBgA:SetValue(math.floor(data.bgAlpha * 100 + 0.5)) end
    -- text
    if refs.sFontSize then refs.sFontSize:SetValue(data.fontSize or 10) end
end

---------------------------------------------------------------
-- DoiteBars.InjectEditControls(cf, key)
-- Public. Called from UpdateCondFrameForKey in DoiteEdit.lua.
---------------------------------------------------------------
function DoiteBars.InjectEditControls(cf, key)
    if not cf or not key then return end

    _beKey = key
    local data = DoiteAurasDB and DoiteAurasDB.spells and DoiteAurasDB.spells[key]
    if not data then return end

    if cf.header then
        cf.header:SetText("Edit: " .. (data.displayName or key) .. " |cffd27dff(Bar)|r")
        cf.header:Show()
    end

    if cf.condListContainer then cf.condListContainer:Hide() end

    if not cf.BarEditContainer then
        local container, content = BE_BuildContainer(cf)
        cf.BarEditContainer = container
        cf.BarEditContent = content
        cf.beRefs = BE_PopulateContent(content, key) 
    end

    BE_UpdateSliderValues(cf.beRefs, data)
    cf.BarEditContainer:Show()
    
    local bf = DoiteBars.GetBarFrame(key)
    if bf then bf:EnableMouse(true) end
end

---------------------------------------------------------------
-- DoiteBars.CleanupCondFrame(cf)
---------------------------------------------------------------
function DoiteBars.CleanupCondFrame(cf)
    if not cf then return end
    
    if cf.BarEditContainer then
        cf.BarEditContainer:Hide()
    end
    if cf.beNameLbl then cf.beNameLbl:Hide() end
    if cf.beKindLbl then cf.beKindLbl:Hide() end

    if cf.condListContainer then
        cf.condListContainer:Show()
    end

    if _beKey then
        local bf = DoiteBars.GetBarFrame(_beKey)
        if bf then bf:EnableMouse(false) end
    end
    _beKey = nil
end
