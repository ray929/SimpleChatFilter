local addonName, ns = ...

----------------------------------------------------------------------------------------------------------------
-- Widget layer, ported from CChatNotifier's UI/widgets.lua: plain frames with
-- BackdropTemplate, WHITE8X8 fills and the tooltip border. No ButtonFrameTemplate,
-- no OptionsButtonTemplate, no UIDropDownMenu -- those move between client
-- generations.
----------------------------------------------------------------------------------------------------------------

local W = {}
ns.W = W

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local TOOLTIP_BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"

local GOLD = { 1, 0.82, 0 }
local BORDER = { 0.35, 0.35, 0.35 }

function W.ApplyBackdrop(frame, r, g, b, a, br, bg, bb)
    frame:SetBackdrop({
        bgFile = WHITE8X8,
        edgeFile = TOOLTIP_BORDER,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(r or 0.05, g or 0.05, b or 0.06, a or 0.9)
    frame:SetBackdropBorderColor(br or BORDER[1], bg or BORDER[2], bb or BORDER[3], 1)
end

function W.Text(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if text then
        fs:SetText(text)
    end
    return fs
end

function W.Small(parent, text)
    return W.Text(parent, text, "GameFontHighlightSmall")
end

function W.Dim(parent, text)
    local fs = W.Small(parent, text)
    fs:SetTextColor(0.62, 0.62, 0.62, 1)
    return fs
end

function W.Heading(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetText(text or "")
    fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    return fs
end

function W.SetTooltip(frame, text)
    if not text then
        return
    end

    -- Chain onto the widget's own hover scripts on the FIRST call only, then rebuild
    -- from that saved base every time. The channel page re-applies its tooltips on
    -- every refresh, and chaining onto our own wrapper each time would grow the
    -- script chain without bound.
    if frame.tooltipBaseEnter == nil then
        frame.tooltipBaseEnter = frame:GetScript("OnEnter") or false
        frame.tooltipBaseLeave = frame:GetScript("OnLeave") or false
    end

    local baseEnter = frame.tooltipBaseEnter or nil
    local baseLeave = frame.tooltipBaseLeave or nil

    frame:SetScript("OnEnter", function(self)
        if baseEnter then
            baseEnter(self)
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        if baseLeave then
            baseLeave(self)
        end
        GameTooltip:Hide()
    end)
end

function W.Button(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 90, height or 22)
    W.ApplyBackdrop(button, 0.1, 0.1, 0.1, 0.9, BORDER[1], BORDER[2], BORDER[3])

    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.text:SetPoint("CENTER", 0, 0)
    button.text:SetText(text or "")

    button:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)
    end)
    button:SetScript("OnMouseDown", function(self)
        self.text:SetPoint("CENTER", 1, -1)
    end)
    button:SetScript("OnMouseUp", function(self)
        self.text:SetPoint("CENTER", 0, 0)
    end)

    function button:SetText(value)
        self.text:SetText(value or "")
    end

    function button:SetTextColor(r, g, b)
        self.text:SetTextColor(r, g, b, 1)
    end

    return button
end

function W.Checkbox(parent, label)
    local box = CreateFrame("CheckButton", nil, parent)
    box:SetSize(24, 24)

    -- The stock textures, same as Syndicator and every other Blizzard options page:
    -- a framed square that turns into a fat gold tick. The hand-drawn colour block
    -- this replaced was both hard to see and hard to hit.
    box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    box:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    box:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")

    box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    box.label:SetPoint("LEFT", box, "RIGHT", 4, 0)
    box.label:SetJustifyH("LEFT")
    box.label:SetText(label or "")

    -- A FontString never sees the mouse, so the click target has to be the button
    -- itself. Growing the hit rectangle to cover the label makes the whole row
    -- clickable; SetHitRectInsets takes negative insets to enlarge.
    -- Measured on the label's laid-out WIDTH when the caller set one (the log page
    -- gives its labels a fixed column width): the click area has to cover where the
    -- text is drawn, and a short text in a wide box otherwise leaves the tail of the
    -- row responding to nothing.
    function box:UpdateHitArea()
        local width = self.label:GetWidth() or 0
        if width <= 0 then
            width = self.label:GetStringWidth() or 0
        end
        self:SetHitRectInsets(-4, -(width + 10), -6, -6)
    end

    -- CheckButton flips its own state on click; do not invert here or the box
    -- appears to ignore clicks while the setting silently flips.
    box:SetScript("OnClick", function(self)
        self:Refresh()
    end)

    function box:Refresh()
        self:UpdateHitArea()
    end

    box:UpdateHitArea()

    return box
end

function W.EditBox(parent, width, height, multiline)
    local edit = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    edit:SetSize(width or 120, height or 22)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetTextColor(1, 1, 1, 1)
    edit:SetTextInsets(6, 6, 3, 3)
    edit:SetJustifyH("LEFT")
    edit:SetJustifyV("MIDDLE")
    W.ApplyBackdrop(edit, 0, 0, 0, 0.85, 0.3, 0.3, 0.3)

    if multiline then
        edit:SetMultiLine(true)
        edit:SetMaxLetters(1024)
    else
        edit:SetMaxLetters(200)
        edit:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
    end

    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
        self:HighlightText()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        self:HighlightText(0, 0)
    end)

    return edit
end

----------------------------------------------------------------------------------------------------------------
-- Picker: a button that opens a small list of options. Replaces UIDropDownMenu.
----------------------------------------------------------------------------------------------------------------

local popup
local POPUP_ROW_HEIGHT = 22

local function HidePopup()
    if popup then
        popup:Hide()
    end
end

local function EnsurePopup()
    if popup then
        return popup
    end

    popup = CreateFrame("Frame", "SimpleChatFilterPickerPopup", UIParent, "BackdropTemplate")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    W.ApplyBackdrop(popup, 0.02, 0.02, 0.03, 0.98, 0.6, 0.5, 0.2)
    popup.rows = {}
    popup:Hide()

    popup.catcher = CreateFrame("Frame", nil, UIParent)
    popup.catcher:SetAllPoints(UIParent)
    popup.catcher:SetFrameStrata("FULLSCREEN")
    popup.catcher:EnableMouse(true)
    popup.catcher:Hide()
    popup.catcher:SetScript("OnMouseDown", HidePopup)

    popup:SetScript("OnHide", function(self)
        if self.catcher then
            self.catcher:Hide()
        end
    end)

    return popup
end

local function PopupRow(menu, index)
    local row = menu.rows[index]
    if row then
        return row
    end

    row = CreateFrame("Button", nil, menu)
    row:SetHeight(POPUP_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 4, -4 - (index - 1) * POPUP_ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", -4, -4 - (index - 1) * POPUP_ROW_HEIGHT)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 6, 0)
    row.text:SetPoint("RIGHT", -6, 0)
    row.text:SetJustifyH("LEFT")

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.12)

    menu.rows[index] = row
    return row
end

local function OpenPopup(picker)
    local menu = EnsurePopup()
    local options = picker.getOptions and picker.getOptions() or {}
    local current = picker.value

    local count = 0
    for _, option in ipairs(options) do
        count = count + 1
        local row = PopupRow(menu, count)
        row.text:SetText(option.text or tostring(option.value))
        if option.value == current then
            row.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
        else
            row.text:SetTextColor(1, 1, 1, 1)
        end
        row:SetScript("OnClick", function()
            picker:SetValue(option.value)
            HidePopup()
            if picker.onSelect then
                picker.onSelect(option.value)
            end
        end)
        row:Show()
    end

    for i = count + 1, #menu.rows do
        menu.rows[i]:Hide()
    end

    menu:SetSize(picker:GetWidth(), math.max(count, 1) * POPUP_ROW_HEIGHT + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", picker, "BOTTOMLEFT", 0, -2)
    menu:Show()
    menu.catcher:Show()
end

--- A labelled picker button.
-- @param labelWidth When given, the label occupies a fixed column so a stack of
--        pickers lines up into a table instead of a ragged right-aligned edge.
function W.Picker(parent, labelText, width, labelWidth)
    local picker = CreateFrame("Button", nil, parent, "BackdropTemplate")
    picker:SetSize(width or 140, 22)

    picker.label = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    picker.label:SetText(labelText or "")
    if labelWidth and labelWidth > 0 then
        picker.label:SetPoint("LEFT", picker, "LEFT", -labelWidth, 0)
        picker.label:SetWidth(labelWidth - 6)
        picker.label:SetJustifyH("LEFT")
    else
        picker.label:SetPoint("RIGHT", picker, "LEFT", -6, 0)
        picker.label:SetJustifyH("RIGHT")
    end

    picker.valueText = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    picker.valueText:SetPoint("LEFT", 8, 0)
    picker.valueText:SetPoint("RIGHT", -18, 0)
    picker.valueText:SetJustifyH("LEFT")

    picker.arrow = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    picker.arrow:SetPoint("RIGHT", -6, 0)
    picker.arrow:SetText("v")

    W.ApplyBackdrop(picker, 0.1, 0.1, 0.1, 0.9, BORDER[1], BORDER[2], BORDER[3])

    local function UpdateText()
        local options = picker.getOptions and picker.getOptions() or {}
        local current = picker.value
        for _, option in ipairs(options) do
            if option.value == current then
                picker.valueText:SetText(option.text or tostring(option.value))
                return
            end
        end
        picker.valueText:SetText(tostring(current or ""))
    end

    function picker:SetOptions(fn)
        self.getOptions = fn
        UpdateText()
    end

    function picker:SetValue(value)
        self.value = value
        UpdateText()
    end

    function picker:GetValue()
        return self.value
    end

    function picker:SetOnSelect(fn)
        self.onSelect = fn
    end

    function picker:Refresh()
        UpdateText()
    end

    picker:SetScript("OnClick", function(self)
        if popup and popup:IsShown() and popup.owner == self then
            HidePopup()
            return
        end
        EnsurePopup().owner = self
        OpenPopup(self)
    end)
    picker:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
    end)
    picker:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)
    end)

    return picker
end

----------------------------------------------------------------------------------------------------------------
-- Text fitting. A FontString with a width wraps its text and then paints over the
-- row below, which is exactly how the log columns ended up on top of each other.
-- Cutting the string to the measured pixel width is the only way to guarantee one
-- line per cell.
----------------------------------------------------------------------------------------------------------------

local function CharPrefix(text, charCount)
    if charCount <= 0 then
        return ""
    end

    local counted, index = 0, 1
    while index <= #text do
        local byte = text:byte(index)
        local size = 1
        if byte >= 240 then
            size = 4
        elseif byte >= 224 then
            size = 3
        elseif byte >= 192 then
            size = 2
        end

        counted = counted + 1
        if counted > charCount then
            return text:sub(1, index - 1)
        end
        index = index + size
    end

    return text
end

local ELLIPSIS = "..."

--- Set the text, cutting it with an ellipsis so it never exceeds maxWidth pixels.
-- @return the text actually shown
function W.FitText(fontString, text, maxWidth)
    text = tostring(text or "")
    if text == "" then
        fontString:SetText("")
        return ""
    end

    fontString:SetText(text)
    local width = fontString:GetStringWidth() or 0
    if width <= maxWidth then
        return text
    end

    fontString:SetText(ELLIPSIS)
    local budget = maxWidth - (fontString:GetStringWidth() or 0)

    local total = ns.CharCount(text)
    local low, high, best = 0, total, 0
    while low <= high do
        local middle = math.floor((low + high) / 2)
        local candidate = CharPrefix(text, middle)
        fontString:SetText(candidate)
        if (fontString:GetStringWidth() or 0) <= budget then
            best = middle
            low = middle + 1
        else
            high = middle - 1
        end
    end

    local shown = CharPrefix(text, best) .. ELLIPSIS
    fontString:SetText(shown)
    return shown
end
