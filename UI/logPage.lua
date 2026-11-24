local addonName, ns = ...

local W = ns.W

local ROWS_PER_PAGE = 14
local ROW_HEIGHT = 22
local PANEL_HEIGHT = ROWS_PER_PAGE * ROW_HEIGHT + 12

-- Cleanup rows. The number box sits at a FIXED x, not "right of the tick box":
-- a CheckButton is only 16 px wide, so anchoring to its RIGHT point drops the
-- edit box on top of its own label text.
local LABEL_WIDTH = 160
local EDIT_X = 196
local EDIT_W = 54

-- Fixed columns. Every cell is cut to its own pixel width before drawing, so a
-- long sender name can never push into the next column or wrap onto the row below.
local COL = {
    time    = { x = 10,  width = 70 },
    channel = { x = 84,  width = 108 },
    from    = { x = 196, width = 100 },
    keyword = { x = 300, width = 76 },
    msg     = { x = 380, width = 168 },
}

local page

--- Keyword column text. "@spam" is a marker written by the filter, not a keyword,
-- so it is translated on display instead of being stored as localised text in the
-- save file (where it would freeze the language used on the day it was blocked).
local function KeywordText(entry)
    local kw = entry and entry.kw or ""
    if type(kw) == "string" and kw:sub(1, 1) == "@" then
        return ns.L("LOG_REASON_" .. kw:sub(2):upper())
    end
    return kw
end

function ns.CreateLogPage(parent)
    if page then
        return page
    end

    page = CreateFrame("Frame", "SimpleChatFilterLogPanel", parent)
    page:SetSize(600, 520)
    page.page = 1

    page.heading = W.Heading(page, ns.L("PAGE_LOG"))
    page.heading:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -8)

    page.clear = W.Button(page, ns.L("BTN_CLEAR"), 110, 20)
    page.clear:SetPoint("TOPRIGHT", page, "TOPRIGHT", -14, -8)
    page.clear:SetTextColor(1, 0.5, 0.5)

    page.count = W.Dim(page, "")
    page.count:SetPoint("RIGHT", page.clear, "LEFT", -8, 0)

    page.desc = W.Dim(page, nil)
    page.desc:SetPoint("TOPLEFT", page, "TOPLEFT", 12, -34)
    page.desc:SetWidth(470)
    page.desc:SetJustifyH("LEFT")
    page.desc:SetText(ns.L("LOG_DESC"))

    -- column header
    page.header = CreateFrame("Frame", nil, page)
    page.header:SetPoint("TOPLEFT", page, "TOPLEFT", 12, -58)
    page.header:SetSize(560, 16)

    local function Header(key, column)
        local label = page.header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", page.header, "LEFT", column.x, 0)
        label:SetWidth(column.width)
        label:SetJustifyH("LEFT")
        label:SetText(ns.L(key))
        label:SetTextColor(1, 0.82, 0, 1)
        return label
    end

    Header("LOG_COL_TIME", COL.time)
    Header("LOG_COL_CHANNEL", COL.channel)
    Header("LOG_COL_FROM", COL.from)
    Header("LOG_COL_KEYWORD", COL.keyword)
    Header("LOG_COL_MSG", COL.msg)

    page.list = CreateFrame("Frame", nil, page)
    page.list:SetPoint("TOPLEFT", page, "TOPLEFT", 12, -78)
    page.list:SetSize(560, PANEL_HEIGHT)

    page.emptyLabel = W.Dim(page, ns.L("LOG_EMPTY"))
    page.emptyLabel:SetPoint("TOPLEFT", page.list, "TOPLEFT", 10, -8)

    -- pager
    page.prev = W.Button(page, ns.L("BTN_PREV"), 56, 20)
    page.next = W.Button(page, ns.L("BTN_NEXT"), 56, 20)
    page.pagerText = W.Small(page, "")
    page.pagerText:SetTextColor(0.62, 0.62, 0.62, 1)

    page.prev:SetPoint("TOPLEFT", page.list, "BOTTOMLEFT", 0, -8)
    page.next:SetPoint("LEFT", page.prev, "RIGHT", 6, 0)
    page.pagerText:SetPoint("LEFT", page.next, "RIGHT", 10, 0)

    page.prev:SetScript("OnClick", function()
        if page.page > 1 then
            page.page = page.page - 1
            page:Refresh()
        end
    end)

    page.next:SetScript("OnClick", function()
        if page.totalPages and page.page < page.totalPages then
            page.page = page.page + 1
            page:Refresh()
        end
    end)

    -- cleanup controls
    page.cleanup = CreateFrame("Frame", nil, page)
    page.cleanup:SetPoint("TOPLEFT", page.list, "BOTTOMLEFT", 0, -36)
    page.cleanup:SetSize(560, 80)

    page.cleanup.heading = W.Heading(page.cleanup, ns.L("LOG_CLEANUP"))
    page.cleanup.heading:SetPoint("TOPLEFT", 0, 0)

    page.timeoutCheck = W.Checkbox(page.cleanup, ns.L("LOG_TIMEOUT_ON"))
    page.timeoutCheck:SetPoint("TOPLEFT", 0, -26)
    page.timeoutCheck.label:SetWidth(LABEL_WIDTH)
    page.timeoutCheck.label:SetWordWrap(false)
    W.FitText(page.timeoutCheck.label, ns.L("LOG_TIMEOUT_ON"), LABEL_WIDTH - 4)
    page.timeoutCheck:SetScript("OnClick", function(self)
        local value = self:GetChecked() and true or false
        self:Refresh()
        ns.db.cleanup.timeoutOn = value
        if value then
            ns.db.cleanup.timeoutHours = page:ReadHours()
        end
        ns.PruneLog()
        page:Refresh()
    end)

    page.timeoutEdit = W.EditBox(page.cleanup, EDIT_W, 20)
    page.timeoutEdit:SetNumeric(true)
    -- Anchored to its own tick box, not to a hard-coded offset: the boxes grew to
    -- 24 px in the checkbox rework, and a fixed -24/-46 pair left the second row's
    -- number box sitting a row higher than its tick.
    page.timeoutEdit:SetPoint("TOPLEFT", page.timeoutCheck, "TOPLEFT", EDIT_X, 2)

    page.timeoutUnit = W.Dim(page.cleanup, ns.L("LOG_HOURS"))
    page.timeoutUnit:SetPoint("LEFT", page.timeoutEdit, "RIGHT", 6, 0)

    -- "720" means nothing at a glance; show the same value in days next to it.
    page.timeoutDays = W.Dim(page.cleanup, "")
    page.timeoutDays:SetPoint("LEFT", page.timeoutUnit, "RIGHT", 6, 0)

    page.maxCheck = W.Checkbox(page.cleanup, ns.L("LOG_MAX_ON"))
    page.maxCheck:SetPoint("TOPLEFT", page.timeoutCheck, "BOTTOMLEFT", 0, -6)
    page.maxCheck.label:SetWidth(LABEL_WIDTH)
    page.maxCheck.label:SetWordWrap(false)
    W.FitText(page.maxCheck.label, ns.L("LOG_MAX_ON"), LABEL_WIDTH - 4)
    page.maxCheck:SetScript("OnClick", function(self)
        local value = self:GetChecked() and true or false
        self:Refresh()
        ns.db.cleanup.maxOn = value
        if value then
            ns.db.cleanup.maxEntries = page:ReadMax()
        end
        ns.PruneLog()
        page:Refresh()
    end)

    page.maxEdit = W.EditBox(page.cleanup, EDIT_W, 20)
    page.maxEdit:SetNumeric(true)
    page.maxEdit:SetPoint("TOPLEFT", page.maxCheck, "TOPLEFT", EDIT_X, 2)

    page.maxUnit = W.Dim(page.cleanup, ns.L("LOG_ENTRIES"))
    page.maxUnit:SetPoint("LEFT", page.maxEdit, "RIGHT", 6, 0)

    -- rows
    local rows = {}
    for i = 1, ROWS_PER_PAGE do
        local row = CreateFrame("Frame", nil, page.list, "BackdropTemplate")
        row:SetPoint("TOPLEFT", page.list, "TOPLEFT", 4, -4 - (i - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", page.list, "TOPRIGHT", -4, -4 - (i - 1) * ROW_HEIGHT)
        row:SetHeight(ROW_HEIGHT - 2)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        row:SetBackdropColor(0.2, 0.2, 0.2, i % 2 == 1 and 0.55 or 0.8)
        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.28, 0.28, 0.28, 0.95)

            if not self.entry then
                return
            end

            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(page:ChannelText(self.entry), 1, 1, 1)
            GameTooltip:AddLine(ns.L("LOG_COL_FROM") .. ": " .. tostring(self.entry.from or "?"), 0.85, 0.85, 0.85)
            GameTooltip:AddLine(ns.L("LOG_COL_KEYWORD") .. ": " .. tostring(KeywordText(self.entry)), 1, 0.82, 0.3)
            GameTooltip:AddLine(self.entry.msg or "", 1, 0.95, 0.8, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.2, 0.2, 0.2, i % 2 == 1 and 0.55 or 0.8)
            GameTooltip:Hide()
        end)
        row:Hide()

        local function Cell(column, template, r, g, b)
            local label = row:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
            label:SetPoint("LEFT", row, "LEFT", column.x, 0)
            label:SetWidth(column.width)
            label:SetJustifyH("LEFT")
            if r then
                label:SetTextColor(r, g, b, 1)
            end
            return label
        end

        row.time = Cell(COL.time, nil, 0.55, 0.55, 0.55)
        row.channel = Cell(COL.channel, nil, 0.62, 0.62, 0.62)
        row.from = Cell(COL.from, nil, 1, 1, 1)
        row.keyword = Cell(COL.keyword, nil, 1, 0.72, 0.3)
        row.msg = Cell(COL.msg, nil, 0.85, 0.85, 0.85)

        rows[i] = row
    end

    function page:ReadHours()
        local value = tonumber(self.timeoutEdit:GetText())
        if not value then
            return ns.db.cleanup.timeoutHours
        end
        return ns.Clamp(math.floor(value + 0.5), 1, 8760)
    end

    function page:ReadMax()
        local value = tonumber(self.maxEdit:GetText())
        if not value then
            return ns.db.cleanup.maxEntries
        end
        return ns.Clamp(math.floor(value + 0.5), 100, 5000)
    end

    local function CommitEdit(edit, field, low, high)
        local value = tonumber(edit:GetText())
        if not value then
            edit:SetText(tostring(ns.db.cleanup[field]))
            return
        end
        ns.db.cleanup[field] = ns.Clamp(math.floor(value + 0.5), low, high)
        edit:SetText(tostring(ns.db.cleanup[field]))
        ns.PruneLog()
        page:Refresh()
    end

    page.timeoutEdit:SetScript("OnEnterPressed", function(self)
        CommitEdit(self, "timeoutHours", 1, 8760)
        self:ClearFocus()
    end)
    page.timeoutEdit:SetScript("OnEditFocusLost", function(self)
        CommitEdit(self, "timeoutHours", 1, 8760)
    end)

    page.maxEdit:SetScript("OnEnterPressed", function(self)
        CommitEdit(self, "maxEntries", 100, 5000)
        self:ClearFocus()
    end)
    page.maxEdit:SetScript("OnEditFocusLost", function(self)
        CommitEdit(self, "maxEntries", 100, 5000)
    end)

    page.clear:SetScript("OnClick", function()
        if not page.confirmClear then
            page.confirmClear = true
            page.clear:SetText(ns.L("BTN_CLEAR_CONFIRM"))
            return
        end

        page.confirmClear = false
        page.clear:SetText(ns.L("BTN_CLEAR"))
        ns.ClearLog()
        ns.Print(ns.L("MSG_CLEARED"))
        page.page = 1
        page:Refresh()
    end)

    page.clear:SetScript("OnLeave", function()
        page.clear:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        if page.confirmClear then
            page.confirmClear = false
            page.clear:SetText(ns.L("BTN_CLEAR"))
        end
    end)

    --- Channel cell text. A player-made channel shows its own name only: the
    -- "custom channel ·" prefix was noise in a narrow column.
    function page:ChannelText(entry)
        if entry.channel and entry.channel ~= "" then
            return entry.channel
        end
        return ns.ChannelLabel(entry.ch)
    end

    function page:Refresh()
        local total = ns.GetLogCount()
        local totalPages = math.max(1, math.ceil(total / ROWS_PER_PAGE))
        self.totalPages = totalPages

        if self.page > totalPages then
            self.page = totalPages
        end
        if self.page < 1 then
            self.page = 1
        end

        self.pagerText:SetText(ns.L("PAGER_TEXT", tostring(self.page), tostring(totalPages), tostring(total)))
        self.prev:SetAlpha(self.page > 1 and 1 or 0.4)
        self.next:SetAlpha(self.page < totalPages and 1 or 0.4)

        if total == 0 then
            self.emptyLabel:Show()
        else
            self.emptyLabel:Hide()
        end
        self.count:SetText(tostring(total))

        if not self.confirmClear then
            self.clear:SetText(ns.L("BTN_CLEAR"))
        end

        local offsetBase = (self.page - 1) * ROWS_PER_PAGE

        for i = 1, ROWS_PER_PAGE do
            local row = rows[i]
            local entry = ns.GetLogEntry(offsetBase + i)

            if entry then
                row.entry = entry
                W.FitText(row.time, ns.Clock(entry.t), COL.time.width)
                W.FitText(row.channel, self:ChannelText(entry), COL.channel.width)

                local from = entry.from or "?"
                if not ns.db.settings.showRealm then
                    from = ns.NameWithoutRealm(from)
                end
                W.FitText(row.from, from, COL.from.width)
                W.FitText(row.keyword, KeywordText(entry), COL.keyword.width)
                W.FitText(row.msg, entry.msg or "", COL.msg.width)
                row:Show()
            else
                row.entry = nil
                row:Hide()
            end
        end

        local cleanup = ns.db.cleanup
        self.timeoutCheck:SetChecked(cleanup.timeoutOn)
        self.timeoutCheck:Refresh()
        self.maxCheck:SetChecked(cleanup.maxOn)
        self.maxCheck:Refresh()
        self.timeoutEdit:SetText(tostring(cleanup.timeoutHours))
        self.maxEdit:SetText(tostring(cleanup.maxEntries))
        self.timeoutEdit:SetAlpha(cleanup.timeoutOn and 1 or 0.4)
        self.maxEdit:SetAlpha(cleanup.maxOn and 1 or 0.4)

        local hours = tonumber(cleanup.timeoutHours) or 0
        if hours >= 24 then
            self.timeoutDays:SetText(ns.L("LOG_TIMEOUT_DAYS", tostring(math.floor(hours / 24))))
        else
            self.timeoutDays:SetText("")
        end
    end

    page:SetScript("OnShow", function(self)
        self.page = 1
        self:Refresh()
    end)

    page:SetScript("OnHide", function()
        GameTooltip:Hide()
    end)

    -- While the page is open a new blocked line should appear without reopening it.
    -- Coalesced: one refresh redraws 14 rows x 5 cells, and every cell measures the
    -- text several times, so a burst of blocked lines used to repaint the whole
    -- page once per line. A pending "click again to confirm" and a focused edit box
    -- are still left alone.
    ns.logListeners[#ns.logListeners + 1] = function()
        if page.refreshPending or not page:IsShown() then
            return
        end

        page.refreshPending = true

        local function Flush()
            page.refreshPending = false

            if not page:IsShown() then
                return
            end
            if page.confirmClear or page.timeoutEdit:HasFocus() or page.maxEdit:HasFocus() then
                return
            end

            page:Refresh()
        end

        if C_Timer and C_Timer.After then
            C_Timer.After(0.4, Flush)
        else
            Flush()
        end
    end

    ns.pages = ns.pages or {}
    ns.pages.log = page

    return page
end
