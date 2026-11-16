local addonName, ns = ...

local DEFAULTS_SETTINGS = {
    enabled = true,
    logOnly = false,
    showRealm = false,
    showMinimap = true,
    minimapAngle = 200,
    minLen = 2,
    locale = "auto",
}

local DEFAULTS_CLEANUP = {
    timeoutOn = true,
    timeoutHours = 720, -- one month
    maxOn = true,
    maxEntries = 2000,
}

----------------------------------------------------------------------------------------------------------------
-- Saved variables
----------------------------------------------------------------------------------------------------------------

local function GetVersion()
    local version = ""
    if _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata then
        version = _G.C_AddOns.GetAddOnMetadata(addonName, "Version") or ""
    elseif _G.GetAddOnMetadata then
        version = _G.GetAddOnMetadata(addonName, "Version") or ""
    end
    return (tostring(version):gsub("^[vV]", ""))
end

--- Version to show in game. An unpackaged dev copy still carries the literal
-- "@project-version@" placeholder, which must not be shown as if it were a release.
-- Returns nil for a dev copy; the UI substitutes its own localised label, so a
-- Chinese client does not read "版本 dev".
local function DisplayVersion()
    local version = GetVersion()
    if version == "" or version:find("@", 1, true) or version:lower() == "project-version" then
        return nil
    end
    return version
end

local function FillDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = value
        end
    end
end

--- Rebuild a keyword entry from whatever was stored. A hand-edited saved
-- variables file, or a schema change, must not leave an entry without `norm`,
-- because the matcher compares against exactly that field.
local function RepairKeyword(entry)
    if type(entry) == "string" then
        entry = { text = entry }
    end
    if type(entry) ~= "table" then
        return nil
    end

    local text = ns.Trim(entry.text)
    if text == "" then
        return nil
    end

    entry.text = text
    entry.norm = ns.Normalize(text)
    entry.parts = ns.KeywordParts(text)
    if entry.norm == "" or #entry.parts == 0 then
        return nil
    end

    if entry.enabled == nil then
        entry.enabled = true
    end
    entry.enabled = entry.enabled and true or false

    return entry
end

local function RepairLog()
    local db = ns.db
    local log = db.log
    if type(log) ~= "table" then
        db.log = {}
        return
    end

    local kept = {}
    for i = 1, #log do
        local entry = log[i]
        if type(entry) == "table" and type(entry.msg) == "string" and entry.msg ~= "" then
            entry.t = tonumber(entry.t) or ns.Now()
            entry.ch = entry.ch or "SAY"
            entry.from = entry.from or "?"
            entry.kw = entry.kw or ""
            kept[#kept + 1] = entry
        end
    end
    -- A hand-edited or corrupted file can carry far more rows than the cleanup
    -- settings allow. Trimming here keeps the first page refresh from walking a
    -- table that is hundreds of times the intended size.
    local cap = (tonumber(db.cleanup and db.cleanup.maxEntries) or 2000) + 200
    if #kept > cap then
        local trimmed = {}
        for i = #kept - cap + 1, #kept do
            trimmed[#trimmed + 1] = kept[i]
        end
        kept = trimmed
    end

    db.log = kept
end

local function SetupDB()
    if type(_G.SimpleChatFilterDB) ~= "table" then
        _G.SimpleChatFilterDB = {}
    end

    local db = _G.SimpleChatFilterDB
    ns.db = db

    if db.version == nil then
        db.version = 1
    end

    -- v2: the first build remembered channels straight off GetChannelList(), which
    -- also lists city/zone channels (General / Trade). Those entries are not
    -- player-made, so throw the old list away once; it rebuilds from real messages.
    if db.version < 2 then
        db.seenChannels = {}
        db.version = 2
    end

    db.settings = type(db.settings) == "table" and db.settings or {}
    FillDefaults(db.settings, DEFAULTS_SETTINGS)

    db.cleanup = type(db.cleanup) == "table" and db.cleanup or {}
    FillDefaults(db.cleanup, DEFAULTS_CLEANUP)

    -- Clamp values a hand-edited file could have pushed out of range.
    db.settings.minLen = ns.Clamp(math.floor(tonumber(db.settings.minLen) or 2), 2, 6)
    db.settings.minimapAngle = ns.Clamp(tonumber(db.settings.minimapAngle) or 200, -180, 360)
    -- Removed feature: do not leave its old key behind in the saved file.
    db.settings.pauseInInstance = nil
    db.cleanup.timeoutHours = ns.Clamp(math.floor(tonumber(db.cleanup.timeoutHours) or 720), 1, 8760)
    db.cleanup.maxEntries = ns.Clamp(math.floor(tonumber(db.cleanup.maxEntries) or 2000), 100, 5000)

    -- Per player-made channel switches. nil means "inherit" (filter it).
    if type(db.customChannels) ~= "table" then
        db.customChannels = {}
    end
    for name, value in pairs(db.customChannels) do
        if type(name) ~= "string" then
            db.customChannels[name] = nil
        else
            db.customChannels[name] = value and true or false
        end
    end

    -- Player-made channels the filter has seen, so the page can list them even
    -- in a session that has not rejoined them.
    if type(db.seenChannels) ~= "table" then
        db.seenChannels = {}
    end
    for name, value in pairs(db.seenChannels) do
        if type(name) ~= "string" or name == "" then
            db.seenChannels[name] = nil
        else
            db.seenChannels[name] = true
        end
    end

    -- City / zone channel switches, keyed by the channel kind ("综合" / "General").
    -- nil means "filter it", same semantics as customChannels. They are NOT
    -- player-made, so they live in their own table and get their own row on the
    -- channel page instead of showing up in the player-made list.
    if type(db.zoneChannels) ~= "table" then
        db.zoneChannels = {}
    end
    for kind, value in pairs(db.zoneChannels) do
        if type(kind) ~= "string" or kind == "" then
            db.zoneChannels[kind] = nil
        else
            db.zoneChannels[kind] = value and true or false
        end
    end

    -- Zone id -> channel kind ("本地交易"), built by SyncZoneChannels() from
    -- GetChannelList(). Process() looks a message up here instead of deriving a label
    -- from the payload name, so a tick on the page always reaches the filter.
    if type(db.zoneChannelIDs) ~= "table" then
        db.zoneChannelIDs = {}
    end
    for id, label in pairs(db.zoneChannelIDs) do
        if type(id) ~= "number" or type(label) ~= "string" or label == "" then
            db.zoneChannelIDs[id] = nil
        end
    end

    -- v4: city/zone channels were once written into the player-made tables (per
    -- region, then briefly folded into "综合"). Neither shape can be told apart from
    -- a real player-made channel by name alone, so both tables are rebuilt:
    -- seenChannels is only a cache, and customChannels defaults to "filtered".
    if (db.version or 0) < 4 then
        db.seenChannels = {}
        db.customChannels = {}
        db.version = 4
    end

    -- v5: the city-channel list was filled through GetChannelInfoFromIdentifier,
    -- which reported a zone id for player-made channels too, so "大脚世界频道 36"
    -- ended up in the city row. The kind list is derived from names now; drop the
    -- entries that the old rule let in. Player-made switches are left untouched.
    if (db.version or 0) < 5 then
        db.zoneChannels = {}
        db.version = 5
    end

    -- v6: the city row was still polluted by Process(), which treated a non-zero
    -- zone id alone as "city channel". Both the call site and the enumeration now
    -- require the "<kind> - <region>" name too, so the stored list is rebuilt once.
    if (db.version or 0) < 6 then
        db.zoneChannels = {}
        db.version = 6
    end

    -- v7: the enumeration classified the BARE name from GetChannelList() ("综合"),
    -- which never carries the " - <region>" suffix — so 交易 / 本地防务 were dropped
    -- while 大脚世界频道 (zone id 27, not 0) was pulled in. It classifies the full
    -- name now; rebuild the list once more.
    if (db.version or 0) < 7 then
        db.zoneChannels = {}
        db.version = 7
    end

    -- v8: the city row was keyed by the folded full name ("交易（本地）") while the page
    -- should read the bare name ("本地交易"), and the list was only built when the
    -- channel page happened to be opened. A zone id → bare name map is now the single
    -- source both the enumeration and the filter use.
    if (db.version or 0) < 8 then
        db.zoneChannels = {}
        db.zoneChannelIDs = {}
        db.version = 8
    end

    -- v9 / v10: two things made the page list one channel twice, and both are fixed by
    -- canonicalising the key. (a) The same name arrived with stray whitespace
    -- ("大脚世界频道 36 " vs "大脚世界频道 36"). (b) A trailing " <number>" marks another
    -- copy of the same channel (大脚世界频道 36 == 大脚世界频道 开关), which the player
    -- asked to fold into one switch. Re-key both tables once.
    if (db.version or 0) < 10 then
        local function FoldKeys(source)
            local out = {}
            for name, value in pairs(source) do
                local key = ns.ChannelKey(name)
                if type(key) == "string" and key ~= "" then
                    if out[key] == nil then
                        out[key] = value
                    else
                        -- Unticked wins: one copy switched off means the name is off.
                        out[key] = out[key] and value
                    end
                end
            end
            return out
        end

        db.seenChannels = FoldKeys(db.seenChannels)
        db.customChannels = FoldKeys(db.customChannels)
        db.version = 10
    end

    -- Channels: keep whatever the player ticked, and add newly supported events
    -- at their default. An event key that no longer exists is simply ignored by
    -- the filter, so it is harmless to leave behind.
    if type(db.channels) ~= "table" then
        db.channels = {}
        ns.ApplyDefaultChannels()
    else
        local valid = {}
        for i = 1, #ns.CHANNELS do
            local info = ns.CHANNELS[i]
            valid[info.key] = true
            if db.channels[info.key] == nil then
                db.channels[info.key] = info.default and true or false
            else
                db.channels[info.key] = db.channels[info.key] and true or false
            end
        end

        -- Drop keys for events that are no longer offered (BN whisper, guild
        -- achievement, ...) so an old saved file does not keep dead switches.
        for key in pairs(db.channels) do
            if not valid[key] then
                db.channels[key] = nil
            end
        end
    end

    -- Keywords
    local keywords = {}
    if type(db.keywords) == "table" then
        for i = 1, #db.keywords do
            local entry = RepairKeyword(db.keywords[i])
            if entry then
                keywords[#keywords + 1] = entry
            end
        end
    end
    db.keywords = keywords

    RepairLog()

    if db.firstStart == nil then
        db.firstStart = true
    end
end

----------------------------------------------------------------------------------------------------------------
-- Pages
----------------------------------------------------------------------------------------------------------------

local function BuildPanels()
    if ns.pages and ns.pages.options then
        return
    end

    ns.pages = {}

    local optionsPanel = ns.CreateOptionPage(UIParent)
    optionsPanel:SetSize(600, 520)

    local keywordPanel = ns.CreateKeywordPage(UIParent)
    keywordPanel:SetSize(600, 520)

    local channelPanel = ns.CreateChannelPage(UIParent)
    channelPanel:SetSize(600, 520)

    local logPanel = ns.CreateLogPage(UIParent)
    logPanel:SetSize(600, 520)

    -- Frames are shown when created. Without this every page would paint over
    -- the game at login; the settings canvas shows the one that is selected.
    optionsPanel:Hide()
    keywordPanel:Hide()
    channelPanel:Hide()
    logPanel:Hide()
end

----------------------------------------------------------------------------------------------------------------
-- Settings categories
----------------------------------------------------------------------------------------------------------------

local function CategoryID(category)
    if not category then
        return nil
    end
    if category.GetID then
        local id = category:GetID()
        if id then
            return id
        end
    end
    return category.ID
end

local function RegisterOne(panel, label)
    local Settings = _G.Settings
    local category = Settings.RegisterCanvasLayoutCategory(panel, label)
    if not category then
        return nil
    end
    Settings.RegisterAddOnCategory(category)
    return category
end

--- Register the addon category and its pages. Safe to call repeatedly: Settings
-- may not be ready while addons load, so PLAYER_LOGIN retries it.
-- @return true when every page is reachable
function ns.RegisterCategories()
    if ns.categoryRoot then
        return true
    end
    if not (ns.pages and ns.pages.options and ns.pages.keyword and ns.pages.channel and ns.pages.log) then
        return false
    end

    local Settings = _G.Settings
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return false
    end

    local root = RegisterOne(ns.pages.options, addonName)
    if not root then
        return false
    end
    ns.categoryRoot = root

    local function AddSub(key, panel, label)
        if Settings.RegisterCanvasLayoutSubcategory then
            local ok, category = pcall(Settings.RegisterCanvasLayoutSubcategory, root, panel, label)
            if ok and category then
                ns["category_" .. key] = category
                return
            end
        end

        -- Clients without subcategories still have to reach the page.
        ns["category_" .. key] = RegisterOne(panel, addonName .. " - " .. label)
    end

    AddSub("keyword", ns.pages.keyword, ns.L("PAGE_KEYWORDS"))
    AddSub("channel", ns.pages.channel, ns.L("PAGE_CHANNELS"))
    AddSub("log", ns.pages.log, ns.L("PAGE_LOG"))

    return true
end

--- Open the settings window on one of our pages.
-- @param which "keyword", "channel", "log" or "options"
function ns.OpenSettings(which)
    if not ns.RegisterCategories() then
        ns.Print(ns.L("HELP"))
        return
    end

    local target
    if which == "keyword" then
        target = ns.category_keyword
    elseif which == "channel" then
        target = ns.category_channel
    elseif which == "log" then
        target = ns.category_log
    else
        target = ns.categoryRoot
    end

    target = target or ns.categoryRoot

    local Settings = _G.Settings
    if not (Settings and Settings.OpenToCategory) then
        return
    end

    local id = CategoryID(target)
    if id and pcall(Settings.OpenToCategory, id) then
        return
    end
    pcall(Settings.OpenToCategory, addonName)
end

----------------------------------------------------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------------------------------------------------

local function RefreshAll()
    if ns.pages then
        for _, page in pairs(ns.pages) do
            if page:IsShown() and page.Refresh then
                page:Refresh()
            end
        end
    end
    if ns.pages and ns.pages.options then
        ns.pages.options:Refresh()
    end
end

local function HandleCommand(input)
    local command, rest = ns.Trim(input):match("^(%S*)(.-)$")
    command = (command or ""):lower()
    rest = ns.Trim(rest)

    if command == "" or command == "keywords" or command == "keyword" or command == "list" then
        ns.OpenSettings("keyword")
        return
    end

    if command == "log" or command == "logs" then
        ns.OpenSettings("log")
        return
    end

    if command == "channels" or command == "channel" then
        ns.OpenSettings("channel")
        return
    end

    if command == "options" or command == "config" then
        ns.OpenSettings("options")
        return
    end

    if command == "toggle" then
        ns.db.settings.enabled = not ns.db.settings.enabled
        ns.Print(ns.L("OVERVIEW_STATUS", ns.db.settings.enabled and ns.L("STATE_ON") or ns.L("STATE_OFF")))
        RefreshAll()
        return
    end

    if command == "add" then
        if rest == "" then
            ns.Print(ns.L("ERR_EMPTY"))
            return
        end

        local ok, err = ns.AddKeyword(rest)
        if ok then
            ns.Print(ns.L("MSG_ADDED", rest))
        else
            ns.Print(ns.L(err))
        end
        RefreshAll()
        return
    end

    if command == "clear" then
        ns.ClearKeywords()
        ns.Print(ns.L("MSG_CLEARED"))
        RefreshAll()
        return
    end

    if command == "debug" then
        ns.DumpChannelDebug()
        return
    end

    ns.Print(ns.L("HELP"))
end

_G.SLASH_SIMPLECHATFILTER1 = "/scf"
_G.SLASH_SIMPLECHATFILTER2 = "/simplechatfilter"
_G.SlashCmdList["SIMPLECHATFILTER"] = HandleCommand

----------------------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------------------

local function OnAddonLoaded()
    ns.VERSION = DisplayVersion()

    SetupDB()
    ns.SetLocale()

    BuildPanels()

    ns.RefreshKeywordIndex()
    ns.PruneLog()
    -- Build the city-channel list at login instead of waiting for the page to be
    -- opened: the filter needs the zone id map before the first channel line arrives.
    ns.SyncZoneChannels()
    ns.RegisterFilters()
    ns.CreateMinimapButton()
    ns.UpdateMinimapButton()

    if ns.db.firstStart then
        ns.db.firstStart = false
        ns.Print(ns.L("FIRST_START"))
    end

    ns.RegisterCategories()
end

ns.timeoutTicker = nil

local function StartTicker()
    if ns.timeoutTicker then
        return
    end

    -- Age based cleanup cannot wait for the page to be opened: a session that
    -- never opens the settings would keep every entry forever.
    local ticker = CreateFrame("Frame")
    ticker.elapsed = 0
    ticker:SetScript("OnUpdate", function(self, delta)
        self.elapsed = self.elapsed + delta
        if self.elapsed < 60 then
            return
        end
        self.elapsed = 0
        if ns.PruneLog() then
            ns.NotifyLogChanged()
        end
    end)
    ns.timeoutTicker = ticker
end

local events = CreateFrame("Frame")

--- Register one event, tolerating a client that does not know it. An unknown
-- event name raises a hard error out of RegisterEvent, and one stale name would
-- otherwise take the whole event frame down.
local function Listen(event)
    local ok = pcall(events.RegisterEvent, events, event)
    if not ok then
        ns.Print("SimpleChatFilter: unknown event " .. event)
    end
end

Listen("ADDON_LOADED")
Listen("PLAYER_LOGIN")
Listen("PLAYER_ENTERING_WORLD")
Listen("PLAYER_LOGOUT")

-- There is no CHANNEL_JOIN / CHANNEL_LEFT event. Joining and leaving a
-- player-made channel arrives as a channel notice instead:
--   CHAT_MSG_CHANNEL_NOTICE        ("You have joined channel X", "You left ...")
--   CHAT_MSG_CHANNEL_NOTICE_USER   (someone else joined or left X)
Listen("CHAT_MSG_CHANNEL_NOTICE")
Listen("CHAT_MSG_CHANNEL_NOTICE_USER")

events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            OnAddonLoaded()
            self:UnregisterEvent("ADDON_LOADED")
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        -- Two things may still be missing at ADDON_LOADED: the Settings API, and
        -- the minimap frame the button hangs off.
        if not ns.RegisterCategories() then
            if C_Timer and C_Timer.After then
                C_Timer.After(2, function()
                    ns.RegisterCategories()
                end)
            end
        end
        ns.CreateMinimapButton()
        ns.UpdateMinimapButton()
        ns.RegisterFilters()
        StartTicker()
        RefreshAll()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        -- Clients can clear the filter list while loading a character.
        ns.RegisterFilters()
        -- Changing zones swaps the city channels (综合 - 暴风城 -> 综合 - 西部荒野), so the
        -- id map has to be rebuilt here as well.
        ns.SyncZoneChannels()
        ns.UpdateMinimapButton()
        return
    end

    -- Joining or leaving a player-made channel changes the list on the channel
    -- page, so redraw it while it is open.
    if event == "CHAT_MSG_CHANNEL_NOTICE" or event == "CHAT_MSG_CHANNEL_NOTICE_USER" then
        if ns.pages and ns.pages.channel and ns.pages.channel:IsShown() then
            ns.pages.channel:Refresh()
        end
        return
    end

    if event == "PLAYER_LOGOUT" then
        ns.PruneLog()
    end
end)
