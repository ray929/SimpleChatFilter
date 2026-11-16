local addonName, ns = ...

local W = ns.W

local COLUMN_WIDTH = 265
local ROW_HEIGHT = 28 -- checkbox is 24 px tall; 28 gives 4 px of breathing room
local GRID_TOP = 70 -- distance from the panel top to the first grid row
local CUSTOM_ROWS = 8
local ZONE_SLOTS = 6 -- how many city/zone channel kinds can be listed

local page
local eventChecks = {}
local channelChecks = {}
local zoneChecks = {}

local function BindCheck(parent, label, getter, setter)
    local box = W.Checkbox(parent, label)
    box.getter = getter
    box.setter = setter

    box:SetScript("OnClick", function(self)
        local value = self:GetChecked() and true or false
        self:Refresh()
        if self.setter then
            self.setter(value)
        end
    end)

    box.Sync = function(self)
        self:SetChecked(self.getter and self.getter() and true or false)
        self:Refresh()
    end

    return box
end

----------------------------------------------------------------------------------------------------------------
-- City / zone channels (综合 / 交易 / 本地防务 / 本地交易)
--
-- They are chat channels but NOT player-made, so they must not show up in the
-- player-made list below. They still need a switch each, because "filter every
-- channel" and "filter the trade channel" are different wishes. One switch covers
-- every region of that kind: 综合 - 贫瘠之地 and 综合 - 灰谷 share the 综合 tick.
----------------------------------------------------------------------------------------------------------------

local function BuildZoneChecks()
    for i = 1, ZONE_SLOTS do
        local box = BindCheck(page.grid, "", function()
            local kind = zoneChecks[i].kind
            local db = ns.db
            if not kind or not db then
                return true
            end
            db.zoneChannels = db.zoneChannels or {}
            return db.zoneChannels[kind] ~= false
        end, function(value)
            local kind = zoneChecks[i].kind
            if kind and ns.db then
                ns.db.zoneChannels = ns.db.zoneChannels or {}
                ns.db.zoneChannels[kind] = value
            end
        end)

        box:Hide()
        zoneChecks[i] = box
    end
end

local function SyncZoneChecks()
    local db = ns.db
    local list = {}

    for kind in pairs((db and db.zoneChannels) or {}) do
        if type(kind) == "string" and kind ~= "" then
            list[#list + 1] = kind
        end
    end
    table.sort(list)

    local tip = ns.L("CH_ZONE_TIP")
    local total = math.min(#list, ZONE_SLOTS)

    for i = 1, total do
        local box = zoneChecks[i]
        box.kind = list[i]
        W.FitText(box.label, list[i], 230)
        W.SetTooltip(box, list[i] .. "\n" .. tip)
        box:Show()
        box:Sync()
    end

    for i = total + 1, #zoneChecks do
        zoneChecks[i].kind = nil
        zoneChecks[i]:Hide()
    end
end

----------------------------------------------------------------------------------------------------------------
-- Event channels (say / yell / party / ...)
----------------------------------------------------------------------------------------------------------------

--- Only creates the boxes. Placement belongs to LayoutGrid, because the number of
-- city-channel rows changes how many rows the event channels start below.
local function BuildEventGrid()
    for _, info in ipairs(ns.CHANNELS) do
        local box = BindCheck(page.grid, ns.ChannelLabel(info.key), function()
            return ns.db and ns.db.channels and ns.db.channels[info.key]
        end, function(value)
            if ns.db and ns.db.channels then
                ns.db.channels[info.key] = value
            end
        end)

        eventChecks[#eventChecks + 1] = box
    end
end

local function SyncEventGrid()
    for i = 1, #eventChecks do
        eventChecks[i]:Sync()
    end
end

--- Lay out the whole grid, then move the three blocks below it.
-- Every box is anchored to the grid's own top-left at a fixed row pitch, NOT to the
-- box above it: anchoring to the previous box tied the pitch to that box's height,
-- which drifted silently once the checkboxes grew from 22 px to 24 px and ended up
-- pushing the last row onto the heading below it.
local function LayoutGrid()
    local index = 0

    local function Place(box)
        local column = index % 2
        local row = math.floor(index / 2)

        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", page.grid, "TOPLEFT", column * COLUMN_WIDTH, -row * ROW_HEIGHT)

        index = index + 1
    end

    for i = 1, #zoneChecks do
        if zoneChecks[i]:IsShown() then
            Place(zoneChecks[i])
        end
    end
    for i = 1, #eventChecks do
        Place(eventChecks[i])
    end

    local rows = math.max(math.ceil(index / 2), 1)
    local gridHeight = rows * ROW_HEIGHT
    page.grid:SetHeight(gridHeight)

    local bottom = -(GRID_TOP + gridHeight)

    page.customHeading:ClearAllPoints()
    page.customHeading:SetPoint("TOPLEFT", page, "TOPLEFT", 10, bottom - 20)

    page.customNote:ClearAllPoints()
    page.customNote:SetPoint("TOPLEFT", page, "TOPLEFT", 12, bottom - 46)

    page.channelsScroll:ClearAllPoints()
    page.channelsScroll:SetPoint("TOPLEFT", page, "TOPLEFT", 24, bottom - 72)
    page.channelsScroll:SetHeight(math.max(520 - (GRID_TOP + gridHeight + 72) - 8, 56))
end

----------------------------------------------------------------------------------------------------------------
-- Player-made channels
----------------------------------------------------------------------------------------------------------------

--- The custom (player-made) channels joined on this character. Their names are what
-- the filter sees in `channelName`, so they can be ticked one by one. City/zone
-- channels deliberately never reach this list: they live in `zoneChannels`.
local function BuildChannelChecks()
    for i = 1, CUSTOM_ROWS * 2 do
        local box = BindCheck(page.channels, "", function()
            return ns.IsCustomChannelAllowed(channelChecks[i] and channelChecks[i].channelName or "")
        end, function(value)
            if ns.db then
                ns.db.customChannels = ns.db.customChannels or {}
                ns.db.customChannels[channelChecks[i].channelName] = value
            end
        end)
        box:Hide()
        channelChecks[i] = box
    end
end

local function SyncChannelChecks()
    -- Built only from what the addon knows: channels the filter has seen, plus
    -- channels with an explicit tick state. GetChannelList() is not used here — its
    -- city/zone entries are handled separately, and its numbering differs between
    -- clients.
    local stored = (ns.db and ns.db.customChannels) or {}
    local seenTable = (ns.db and ns.db.seenChannels) or {}
    local seen = {}
    local list = {}

    local function AddName(raw)
        if type(raw) ~= "string" or raw == "" then
            return
        end

        -- Canonicalise before deduplicating: the same channel can be stored under two
        -- keys that render identically ("大脚世界频道 36 " with a trailing space), and
        -- the page used to list both copies side by side.
        local key = ns.ChannelKey(raw)
        if type(key) ~= "string" or key == "" or seen[key] then
            return
        end

        seen[key] = true
        list[#list + 1] = key
    end

    for name in pairs(stored) do
        AddName(name)
    end
    for name in pairs(seenTable) do
        AddName(name)
    end

    table.sort(list)

    local total = math.min(#list, CUSTOM_ROWS * 2)
    for i = 1, total do
        local box = channelChecks[i]
        box.channelName = list[i]

        -- Channel names can be long; the label has no width of its own and would
        -- otherwise run into the second column and out of the canvas.
        W.FitText(box.label, list[i], 230)
        W.SetTooltip(box, list[i])
        box:Show()

        local row = math.floor((i - 1) / 2)
        if (i - 1) % 2 == 0 then
            box:SetPoint("TOPLEFT", page.channels, "TOPLEFT", 0, -row * ROW_HEIGHT)
        else
            box:SetPoint("TOPLEFT", channelChecks[i - 1], "TOPLEFT", COLUMN_WIDTH, 0)
        end
        box:Sync()
    end

    for i = total + 1, #channelChecks do
        channelChecks[i].channelName = nil
        channelChecks[i]:Hide()
    end

    if total == 0 then
        page.channelsEmpty:Show()
    else
        page.channelsEmpty:Hide()
    end
    page.channels:SetHeight(math.max(math.ceil(total / 2) * ROW_HEIGHT, ROW_HEIGHT))
end

function ns.CreateChannelPage(parent)
    if page then
        return page
    end

    page = CreateFrame("Frame", "SimpleChatFilterChannelPanel", parent)
    page:SetSize(600, 520)

    page.heading = W.Heading(page, ns.L("PAGE_CHANNELS"))
    page.heading:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -8)

    page.defaults = W.Button(page, ns.L("BTN_DEFAULTS"), 120, 20)
    page.defaults:SetPoint("TOPRIGHT", page, "TOPRIGHT", -14, -8)

    page.none = W.Button(page, ns.L("BTN_NONE"), 100, 20)
    page.none:SetPoint("RIGHT", page.defaults, "LEFT", -6, 0)

    page.desc = W.Dim(page, nil)
    page.desc:SetPoint("TOPLEFT", page, "TOPLEFT", 12, -36)
    page.desc:SetWidth(560)
    page.desc:SetJustifyH("LEFT")
    page.desc:SetText(ns.L("CH_DESC"))

    page.grid = CreateFrame("Frame", nil, page)
    page.grid:SetPoint("TOPLEFT", page, "TOPLEFT", 12, -GRID_TOP)
    page.grid:SetWidth(560)

    page.customHeading = W.Heading(page, ns.L("CH_CUSTOM_HEAD"))

    page.customNote = W.Dim(page, nil)
    page.customNote:SetWidth(560)
    page.customNote:SetJustifyH("LEFT")
    page.customNote:SetText(ns.L("CH_CUSTOM_NOTE"))

    -- The list can hold CUSTOM_ROWS * 2 channels; at 16 entries it is 208 px tall,
    -- which ran past the 520 px panel and painted over whatever sat behind it.
    -- It scrolls inside a viewport whose height LayoutGrid recalculates.
    page.channelsScroll = CreateFrame("ScrollFrame", nil, page)
    page.channelsScroll:SetWidth(540)
    page.channelsScroll:EnableMouseWheel(true)

    page.channels = CreateFrame("Frame", nil, page.channelsScroll)
    page.channels:SetWidth(540)
    page.channelsScroll:SetScrollChild(page.channels)

    page.channelsScroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        local value = (self:GetVerticalScroll() or 0) - delta * (ROW_HEIGHT * 2)
        if value < 0 then
            value = 0
        elseif value > range then
            value = range
        end
        self:SetVerticalScroll(value)
    end)

    page.channelsEmpty = W.Dim(page, ns.L("CH_CUSTOM_EMPTY"))
    page.channelsEmpty:SetPoint("TOPLEFT", page.channels, "TOPLEFT", 0, 0)

    BuildZoneChecks()
    BuildEventGrid()
    BuildChannelChecks()

    function page:Refresh()
        SyncZoneChecks()
        SyncEventGrid()
        LayoutGrid()
        SyncChannelChecks()
    end

    page.defaults:SetScript("OnClick", function()
        ns.ApplyDefaultChannels()
        for kind in pairs(ns.db.zoneChannels or {}) do
            ns.db.zoneChannels[kind] = true
        end
        page:Refresh()
    end)

    page.none:SetScript("OnClick", function()
        if ns.db then
            for i = 1, #ns.CHANNELS do
                ns.db.channels[ns.CHANNELS[i].key] = false
            end
            for kind in pairs(ns.db.zoneChannels or {}) do
                ns.db.zoneChannels[kind] = false
            end
        end
        page:Refresh()
    end)

    page:SetScript("OnShow", function(self)
        -- The joined city channels change when the player moves between zones, and
        -- the list of kinds comes from the client, not from messages we happened to
        -- have seen.
        ns.SyncZoneChannels()
        self:Refresh()
    end)

    ns.pages = ns.pages or {}
    ns.pages.channel = page

    page:Refresh()

    return page
end
