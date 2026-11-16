local addonName, ns = ...

local W = ns.W

local ICON = "Interface\\ICONS\\UI_Chat"
local DEFAULT_ANGLE = 200 -- degrees, clockwise from the minimap's right edge

local button

local atan2 = math.atan2 or function(y, x)
    return math.atan(y, x)
end

local function PositionAt(angle)
    if not button then
        return
    end

    local minimap = button:GetParent()
    local size = (minimap and minimap:GetWidth()) or 140
    if size <= 0 then
        size = 140
    end

    -- Centre of the button sits on the minimap's ring: half the minimap plus
    -- half the button, minus the small overlap every minimap button has.
    local distance = size / 2 + (button:GetWidth() or 31) / 2 - 5

    button:ClearAllPoints()
    button:SetPoint("CENTER", minimap, "CENTER", math.cos(angle) * distance, math.sin(angle) * distance)
end

local function StoredAngle()
    local db = ns.db
    if db and db.settings and type(db.settings.minimapAngle) == "number" then
        return math.rad(db.settings.minimapAngle)
    end
    return math.rad(DEFAULT_ANGLE)
end

local function Position()
    PositionAt(StoredAngle())
end

local function FollowCursor()
    if not button then
        return
    end

    local scale = UIParent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    cursorX, cursorY = cursorX / scale, cursorY / scale

    local minimap = button:GetParent()
    local centerX, centerY = minimap:GetCenter()
    if not (centerX and centerY) then
        return
    end

    PositionAt(atan2(cursorY - centerY, cursorX - centerX))
end

local function SaveAngle()
    local minimap = button:GetParent()
    local centerX, centerY = minimap:GetCenter()
    local x, y = button:GetCenter()
    if not (centerX and centerY and x and y) then
        return
    end

    ns.db.settings.minimapAngle = math.floor(math.deg(atan2(y - centerY, x - centerX)) + 0.5)
end

--- Show/hide the button and repaint the icon for the current on/off state.
-- Deliberately does NOT reposition the button: this runs on every toggle click,
-- and re-anchoring on a click is what made the icon appear to drift.
function ns.UpdateMinimapButton()
    if not button then
        return
    end

    if ns.db and ns.db.settings and ns.db.settings.showMinimap then
        button:Show()

        if ns.db.settings.enabled then
            button.icon:SetVertexColor(1, 1, 1)
        else
            button.icon:SetVertexColor(0.55, 0.55, 0.55)
        end
    else
        button:Hide()
    end
end

function ns.HookMinimapSize()
    local minimap = _G.Minimap
    if not minimap or ns.minimapHooked then
        return
    end

    -- pcall: hooksecurefunc raises when the named function is missing on this
    -- client, and a missing hook must never break the button itself.
    ns.minimapHooked = true
    pcall(hooksecurefunc, minimap, "SetSize", Position)
    pcall(hooksecurefunc, minimap, "SetScale", Position)
end

function ns.CreateMinimapButton()
    local minimap = _G.Minimap
    if not minimap then
        return button
    end

    if button then
        if button:GetParent() ~= minimap then
            button:SetParent(minimap)
            ns.HookMinimapSize()
            Position()
        end
        return button
    end

    local frame = CreateFrame("Button", "SimpleChatFilterMinimapButton", minimap)
    button = frame

    frame:SetSize(31, 31)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(8)
    frame:SetClampedToScreen(false)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")

    -- Same two textures every minimap button addon uses: a ring border and a
    -- compact icon inside it, so the button reads as part of the minimap instead
    -- of a floating square.
    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetSize(53, 53)
    frame.background:SetPoint("CENTER", 0, 0)
    frame.background:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    frame.icon = frame:CreateTexture(nil, "BACKGROUND")
    frame.icon:SetSize(20, 20)
    frame.icon:SetPoint("CENTER", 0, 1)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.icon:SetTexture(ICON)

    frame.highlight = frame:CreateTexture(nil, "HIGHLIGHT")
    frame.highlight:SetAllPoints(frame.icon)
    frame.highlight:SetColorTexture(1, 1, 1, 0.18)

    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(ns.L("MINIMAP_TIP_TITLE"), 1, 0.82, 0.2)
        GameTooltip:AddLine(ns.L("MINIMAP_TIP_LEFT"), 0.9, 0.9, 0.9)
        GameTooltip:AddLine(ns.L("MINIMAP_TIP_RIGHT"), 0.9, 0.9, 0.9)
        GameTooltip:AddLine(ns.L("MINIMAP_TIP_MIDDLE"), 0.9, 0.9, 0.9)
        GameTooltip:AddLine(ns.L("MINIMAP_TIP_DRAG"), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)

    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    frame:SetScript("OnDragStart", function(self)
        if not ns.db then
            return
        end
        self.dragging = true
        self:SetScript("OnUpdate", FollowCursor)
    end)

    frame:SetScript("OnDragStop", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
        SaveAngle()
        Position()
    end)

    frame:SetScript("OnClick", function(_, mouseButton)
        if not ns.db then
            return
        end

        if mouseButton == "LeftButton" then
            -- Top level of the addon's settings, not a sub-page.
            ns.OpenSettings("options")
        elseif mouseButton == "RightButton" then
            ns.OpenSettings("log")
        else
            ns.db.settings.enabled = not ns.db.settings.enabled
            if ns.pages and ns.pages.options then
                ns.pages.options:Refresh()
            end
            ns.Print(ns.L("OVERVIEW_STATUS", ns.db.settings.enabled and ns.L("STATE_ON") or ns.L("STATE_OFF")))
        end

        ns.UpdateMinimapButton()
        GameTooltip:Hide()
    end)

    frame:SetScript("OnShow", Position)

    ns.HookMinimapSize()
    Position()
    ns.UpdateMinimapButton()

    return frame
end
