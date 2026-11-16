local addonName, ns = ...

local W = ns.W

local ROW_HEIGHT = 26
local ARM_SECONDS = 5

local page, scroll, content
local rows = {}
local clearArmed = false
local armToken = 0

--- One list row: keyword text, normalised form, toggle and delete.
local function EnsureRow(index)
    local row = rows[index]
    if row then
        return row
    end

    row = CreateFrame("Frame", nil, content, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT - 2)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    row:SetBackdropColor(0.2, 0.2, 0.2, 0.8)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", 10, 0)
    row.text:SetWidth(200)
    row.text:SetJustifyH("LEFT")

    -- Normalised form. Shown only when it differs from what was typed, so an
    -- ordinary keyword does not get a second identical looking column.
    row.norm = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.norm:SetPoint("LEFT", row.text, "RIGHT", 12, 0)
    row.norm:SetWidth(150)
    row.norm:SetJustifyH("LEFT")

    row.toggle = W.Button(row, "", 50, 18)
    row.toggle:SetPoint("RIGHT", -58, 0)
    W.SetTooltip(row.toggle, ns.L("KEYWORDS_TOGGLE_TIP"))

    row.delete = W.Button(row, ns.L("BTN_DELETE"), 50, 18)
    row.delete:SetPoint("RIGHT", -4, 0)

    row.toggle:SetScript("OnClick", function()
        local entry = row.entry
        if not entry then
            return
        end
        entry.enabled = not entry.enabled
        ns.RefreshKeywordIndex()
        page:Refresh()
    end)

    row.delete:SetScript("OnClick", function()
        local entry = row.entry
        if not entry then
            return
        end
        ns.RemoveKeywordEntry(entry)
        page:Refresh()
    end)

    rows[index] = row
    return row
end

--- Rebuild the list from the saved keyword table.
local function RefreshList()
    if not page then
        return
    end

    local keywords = (ns.db and ns.db.keywords) or {}

    -- Sorted by the normalised form: that is what the matcher compares, and
    -- "打手" and "打 手" end up next to each other.
    local ordered = {}
    for i = 1, #keywords do
        ordered[#ordered + 1] = keywords[i]
    end
    table.sort(ordered, function(a, b)
        return (a.norm or "") < (b.norm or "")
    end)

    local total = #ordered
    content:SetHeight(math.max(total * ROW_HEIGHT, 40))

    for index = total + 1, #rows do
        rows[index].entry = nil
        rows[index]:Hide()
    end

    for index = 1, total do
        local entry = ordered[index]
        local row = EnsureRow(index)

        row.entry = entry
        W.FitText(row.text, entry.text, 190)

        if ns.KeywordTooShort(entry) then
            row.norm:SetText(ns.L("KEYWORDS_TOO_SHORT"))
            row.norm:SetTextColor(1, 0.3, 0.3, 1)
        elseif entry.norm ~= (entry.text or ""):lower() then
            W.FitText(row.norm, ns.L("KEYWORDS_MATCHED", page:MatchLabel(entry)), 140)
            row.norm:SetTextColor(0.55, 0.55, 0.55, 1)
        else
            row.norm:SetText("")
        end

        if entry.enabled then
            row.toggle:SetText(ns.L("KEYWORD_ON"))
            row.toggle:SetTextColor(0.4, 0.9, 0.5)
            row:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
            row.text:SetTextColor(1, 1, 1, 1)
        else
            row.toggle:SetText(ns.L("KEYWORD_OFF"))
            row.toggle:SetTextColor(0.8, 0.4, 0.4)
            row:SetBackdropColor(0.2, 0.2, 0.2, 0.4)
            row.text:SetTextColor(0.5, 0.5, 0.5, 1)
        end

        row:Show()
    end

    if total == 0 then
        page.emptyText:Show()
    else
        page.emptyText:Hide()
    end
    page.countText:SetText(ns.L("KEYWORDS_COUNT", tostring(total)))
end

function ns.CreateKeywordPage(parent)
    if page then
        return page
    end

    page = CreateFrame("Frame", "SimpleChatFilterKeywordPanel", parent)
    page:SetSize(600, 520)

    local y = -8

    page.heading = W.Heading(page, ns.L("PAGE_KEYWORDS"))
    page.heading:SetPoint("TOPLEFT", page, "TOPLEFT", 10, y)
    y = y - 28

    -- Width before text: a font string only wraps once its width is known.
    page.desc = W.Dim(page, nil)
    page.desc:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
    page.desc:SetWidth(560)
    page.desc:SetJustifyH("LEFT")
    page.desc:SetText(ns.L("KEYWORDS_DESC"))
    y = y - math.max(page.desc:GetStringHeight() or 0, 28) - 10

    page.edit = W.EditBox(page, 300, 24)
    page.edit:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)

    page.addButton = W.Button(page, ns.L("BTN_ADD"), 70, 24)
    page.addButton:SetPoint("LEFT", page.edit, "RIGHT", 8, 0)

    page.clearButton = W.Button(page, ns.L("BTN_CLEAR"), 150, 24)
    page.clearButton:SetPoint("LEFT", page.addButton, "RIGHT", 8, 0)

    local function DisarmClear()
        clearArmed = false
        armToken = armToken + 1
        page.clearButton:SetText(ns.L("BTN_CLEAR"))
        page.clearButton:SetTextColor(1, 1, 1)
    end

    -- Two-step delete: the first click only arms the button, so a stray click on
    -- a settings page cannot wipe a long list.
    page.clearButton:SetScript("OnClick", function()
        if not clearArmed then
            clearArmed = true
            armToken = armToken + 1
            local token = armToken
            page.clearButton:SetText(ns.L("BTN_CLEAR_CONFIRM"))
            page.clearButton:SetTextColor(1, 0.3, 0.3)
            if C_Timer and C_Timer.After then
                C_Timer.After(ARM_SECONDS, function()
                    if token == armToken then
                        DisarmClear()
                    end
                end)
            end
            return
        end

        DisarmClear()
        ns.ClearKeywords()
        page:Refresh()
    end)

    local function AddCurrent()
        local ok, err = ns.AddKeyword(page.edit:GetText())
        if not ok then
            ns.Print(ns.L(err))
            return
        end

        page.edit:SetText("")
        page.edit:SetFocus()
        page:Refresh()

        local entry = ns.db.keywords[#ns.db.keywords]
        if entry and ns.KeywordTooShort(entry) then
            ns.Print(ns.L("ERR_TOO_SHORT", tostring(ns.db.settings.minLen)))
        end
    end

    page.addButton:SetScript("OnClick", AddCurrent)
    page.edit:SetScript("OnEnterPressed", function(self)
        AddCurrent()
        self:SetFocus()
    end)

    y = y - 24 - 12

    scroll = CreateFrame("ScrollFrame", nil, page)
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -14, 24)
    scroll:EnableMouseWheel(true)

    content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(560)
    scroll:SetScrollChild(content)

    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        local value = (self:GetVerticalScroll() or 0) - delta * (ROW_HEIGHT * 2)
        if value < 0 then
            value = 0
        elseif value > range then
            value = range
        end
        self:SetVerticalScroll(value)
    end)

    scroll:SetScript("OnSizeChanged", function(self, width)
        content:SetWidth(math.max(width, 100))
    end)

    page.emptyText = W.Text(page, ns.L("KEYWORDS_EMPTY"), "GameFontDisableSmall")
    page.emptyText:SetPoint("CENTER", scroll, "CENTER", 0, 0)
    page.emptyText:SetWidth(400)
    page.emptyText:SetJustifyH("CENTER")
    page.emptyText:Hide()

    page.countText = W.Small(page, "")
    page.countText:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 14, 6)
    page.countText:SetTextColor(0.62, 0.62, 0.62, 1)

    -- What the matcher actually looks for. A keyword typed with spaces is a set
    -- of AND parts, so show them joined rather than as one glued string.
    function page:MatchLabel(entry)
        local parts = entry.parts
        if parts and #parts > 1 then
            return table.concat(parts, " + ")
        end
        return entry.norm or ""
    end

    function page:Refresh()
        RefreshList()
    end

    page:SetScript("OnShow", function(self)
        self:Refresh()
    end)

    ns.pages = ns.pages or {}
    ns.pages.keyword = page

    page:Refresh()
    return page
end
