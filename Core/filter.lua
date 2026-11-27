local addonName, ns = ...

----------------------------------------------------------------------------------------------------------------
-- Supported chat events
--
-- Only events whose payload starts with (msg, sender, language, ...) are listed.
-- Events with a different signature (CHANNEL_NOTICE, AFK, DND, ...) are left out
-- on purpose. The system/loot group is not offered at all: those events share the
-- same string space as drops, errors and invites.
----------------------------------------------------------------------------------------------------------------

ns.CHANNELS = {
    -- ticked by default
    { event = "CHAT_MSG_SAY",              key = "SAY",              group = "main",  default = true  },
    { event = "CHAT_MSG_YELL",             key = "YELL",             group = "main",  default = true  },
    { event = "CHAT_MSG_CHANNEL",          key = "CHANNEL",          group = "main",  default = true  },
    -- unticked by default
    { event = "CHAT_MSG_WHISPER",          key = "WHISPER",          group = "other", default = false },
    { event = "CHAT_MSG_PARTY",            key = "PARTY",            group = "other", default = false },
    { event = "CHAT_MSG_PARTY_LEADER",     key = "PARTY_LEADER",     group = "other", default = false },
    { event = "CHAT_MSG_RAID",             key = "RAID",             group = "other", default = false },
    { event = "CHAT_MSG_RAID_LEADER",      key = "RAID_LEADER",      group = "other", default = false },
    { event = "CHAT_MSG_RAID_WARNING",     key = "RAID_WARNING",     group = "other", default = false },
    { event = "CHAT_MSG_INSTANCE_CHAT",    key = "INSTANCE_CHAT",    group = "other", default = false },
    { event = "CHAT_MSG_INSTANCE_CHAT_LEADER", key = "INSTANCE_CHAT_LEADER", group = "other", default = false },
    { event = "CHAT_MSG_GUILD",            key = "GUILD",            group = "other", default = false },
    { event = "CHAT_MSG_OFFICER",          key = "OFFICER",          group = "other", default = false },
    { event = "CHAT_MSG_BATTLEGROUND",     key = "BATTLEGROUND",     group = "other", default = false },
    { event = "CHAT_MSG_EMOTE",            key = "EMOTE",            group = "other", default = false },
    { event = "CHAT_MSG_TEXT_EMOTE",       key = "TEXT_EMOTE",       group = "other", default = false },
}

ns.eventInfo = {}
for i = 1, #ns.CHANNELS do
    ns.eventInfo[ns.CHANNELS[i].event] = ns.CHANNELS[i]
end

function ns.ChannelLabel(key)
    return ns.L("CH_" .. tostring(key))
end

----------------------------------------------------------------------------------------------------------------
-- Player-made channels
----------------------------------------------------------------------------------------------------------------

--- The payload of CHAT_MSG_CHANNEL starts with the channel number glued to the
-- name ("5.大脚世界频道"). Strip the prefix so the page and the log show the name
-- the player typed and the per-channel tick keys stay stable.
-- @return name, number (number is nil when there is no prefix)
function ns.SplitChannelString(channelString)
    if type(channelString) ~= "string" or channelString == "" then
        return nil, nil
    end

    local number, name = channelString:match("^(%d+)%.(.+)$")
    if number then
        return name, tonumber(number)
    end
    return channelString, nil
end

--- Canonical key for a channel name.
-- Two names that render identically have to land on one key, or the page lists the
-- same channel twice: "大脚世界频道 36" arrived both with and without trailing
-- whitespace, and the two ended up side by side in the player-made list.
-- Non-breaking and ideographic spaces are folded first — %s only covers ASCII.
function ns.ChannelKey(name)
    if type(name) ~= "string" or name == "" then
        return name
    end

    local s = name:gsub("\227\128\128", " ") -- U+3000 ideographic space
    s = s:gsub("\194\160", " ")              -- U+00A0 no-break space
    s = s:gsub("%s+", " ")
    s = (s:gsub("^%s*(.-)%s*$", "%1"))

    -- A trailing " <number>" is the same channel: 大脚世界频道 36 is one of the 大脚
    -- world-channel copies and shares a switch with the base name. Only a SPACE plus
    -- digits is folded — "副本2" written without the space is left alone.
    s = s:gsub("%s+%d+$", "")

    return s
end

--- Collapse a city/zone channel name to its type: "综合 - 贫瘠之地" -> "综合",
-- "General - Westfall" -> "General".
-- Zone channels are one room per region but only four kinds in total, so listing
-- them verbatim put a row per region on the page while every one of those rows
-- controlled the same thing. The type is what the player recognises.
-- Dashes are normalised with literal replacements first: a multi-byte character
-- inside a Lua character class matches one byte and leaves mojibake behind.
function ns.ZoneChannelType(name)
    if type(name) ~= "string" or name == "" then
        return name
    end

    local s = name:gsub("\226\128\147", "-") -- U+2013 en dash
    s = s:gsub("\226\128\148", "-")          -- U+2014 em dash
    s = s:gsub("\239\188\141", "-")          -- U+FF0D fullwidth hyphen

    -- Require whitespace on both sides of the dash: a player-made channel called
    -- "Co-Op" must not be folded into "Co".
    local base = s:match("^(.-)%s+%-%s+%S")
    if base and base ~= "" then
        return base
    end

    return name
end

--- A channel is filtered unless it was explicitly unticked. Channels the player
-- never opened on this page keep working through the master "custom channels"
-- switch, so joining a new channel never silently bypasses the filter.
function ns.IsCustomChannelAllowed(name)
    if type(name) ~= "string" or name == "" then
        return true
    end
    local custom = ns.db and ns.db.customChannels
    if not custom then
        return true
    end
    return custom[ns.ChannelKey(name)] ~= false
end

local MAX_SEEN_CHANNELS = 60

--- Remember a player-made channel that the filter actually saw. Joined channels
-- are not enumerable without a mess of numbering, and GetChannelList() also
-- returns the city/zone channels (General, Trade), which are NOT player-made, so
-- the page is built from what the filter has actually seen instead.
function ns.RememberChannel(name)
    local db = ns.db
    if not db then
        return
    end

    local key = ns.ChannelKey(name)
    if type(key) ~= "string" or key == "" then
        return
    end

    if type(db.seenChannels) ~= "table" then
        db.seenChannels = {}
    end
    if db.seenChannels[key] then
        return
    end

    local count = 0
    for _ in pairs(db.seenChannels) do
        count = count + 1
    end
    if count >= MAX_SEEN_CHANNELS then
        return
    end

    db.seenChannels[key] = true
end

--- Ask the client which channels are joined and file the city/zone ones under
-- their kind, so the page can list 综合 / 交易 / 本地防务 even in a session where no
-- message has arrived on them yet.
-- The judgement is the NAME SHAPE, not the zone id: C_ChatInfo.GetChannelInfoFromIdentifier
-- answers for every joined channel, and a player-made channel such as "大脚世界频道 36"
-- came back with a non-zero zone id, which put it at the top of the city-channel row.
function ns.SyncZoneChannels()
    local db = ns.db
    if not db then
        return
    end
    if not _G.GetChannelList then
        return
    end

    local packed = { pcall(_G.GetChannelList) }
    if not packed[1] then
        return
    end

    db.zoneChannels = type(db.zoneChannels) == "table" and db.zoneChannels or {}

    local lookup = _G.C_ChatInfo and _G.C_ChatInfo.GetChannelInfoFromIdentifier

    for i = 2, #packed, 3 do
        local name = packed[i + 1]
        local disabled = packed[i + 2]

        -- GetChannelList() returns (id, name, disabled). A channel that an addon
        -- created and keeps hidden comes back disabled: it never prints in the chat
        -- frame, so there is nothing to filter and it would only be noise on the page.
        local hidden = (disabled == 1 or disabled == true)

        if type(name) == "string" and name ~= "" and not hidden then
            -- GetChannelList() hands back the BARE name ("综合", "交易",
            -- "大脚世界频道"); the "<kind> - <region>" shape only exists in the
            -- full name, so that is what has to be classified. Player-made channels
            -- come back as "大脚世界频道 36": no dash, no region.
            local fullName = name
            if _G.GetChannelName then
                local ok, _, full = pcall(_G.GetChannelName, name)
                if ok and type(full) == "string" and full ~= "" then
                    fullName = full
                end
            end

            local kind = ns.ZoneChannelType(fullName)
            local zoneID = 0

            if lookup then
                local okInfo, info = pcall(lookup, fullName)
                if okInfo and type(info) == "table" then
                    zoneID = tonumber(info.zoneChannelID) or 0
                end
            end

            -- The zone id alone is NOT enough: a player-made channel reports 27, not
            -- 0. Requiring the dashed name as well is what separates 综合 - 暴风城
            -- (zone id 1) from 大脚世界频道 36 (zone id 27).
            if zoneID ~= 0 and kind ~= fullName then
                -- The BARE name is what the player recognises ("本地交易"), while the
                -- full name reads "交易（本地） - 西部荒野"; folding the full name gave
                -- "交易（本地）", a second label for the same switch. The zone id → bare
                -- name map is also what Process() looks up, so both sides agree on ONE
                -- string and a tick on the page actually reaches the filter.
                local label = (type(name) == "string" and name ~= "") and name or kind

                db.zoneChannelIDs = type(db.zoneChannelIDs) == "table" and db.zoneChannelIDs or {}
                db.zoneChannelIDs[zoneID] = label
                db.zoneChannels[label] = true
            else
                -- Remember the full name, not the bare one, so this agrees with what
                -- Process() stores from the message payload ("大脚世界频道 36", not
                -- "大脚世界频道"); otherwise the page lists the same channel twice.
                ns.RememberChannel(fullName)
            end
        end
    end
end

--- Diagnose the channel split. `/scf debug` prints what the client says about every
-- joined channel (raw name, folded kind, full name, zone id) plus what the addon
-- stores, and arms the next few channel lines to dump their raw arguments. The point
-- is to check the city / player-made judgement against the real client instead of
-- against assumptions: two rounds of guesswork already put the wrong rows on the page.
function ns.DumpChannelDebug()
    local db = ns.db
    local packed = { pcall(_G.GetChannelList) }

    if not packed[1] then
        ns.Print("GetChannelList() 调用失败")
        return
    end

    ns.Print(string.format("GetChannelList() 返回 %d 个频道：", (#packed - 1) / 3))

    for i = 2, #packed, 3 do
        local id, name, disabled = packed[i], packed[i + 1], packed[i + 2]
        local fullName = name

        if _G.GetChannelName then
            local ok, _, full = pcall(_G.GetChannelName, name)
            if ok and type(full) == "string" and full ~= "" then
                fullName = full
            end
        end

        local kind = ns.ZoneChannelType(fullName)
        local zoneID = "?"
        local key = kind

        if _G.C_ChatInfo and _G.C_ChatInfo.GetChannelInfoFromIdentifier then
            local ok, info = pcall(_G.C_ChatInfo.GetChannelInfoFromIdentifier, fullName)
            if ok and type(info) == "table" then
                zoneID = tostring(info.zoneChannelID)
            end
        end

        -- What SyncZoneChannels() would store: the bare name for a city channel
        -- ("本地交易"), the folded name otherwise. zonesChannelIDs is what the filter
        -- looks up, so this column has to show the same string or the report lies.
        if kind ~= fullName then
            key = (type(name) == "string" and name ~= "") and name or kind
        end

        -- Hidden means an addon owns it and the player never sees a line from it.
        local hidden = (disabled == 1 or disabled == true)

        ns.Print(string.format("  #%s name=%s | full=%s | 键=%s | zoneID=%s | %s%s",
            tostring(id), tostring(name), tostring(fullName), tostring(key), tostring(zoneID),
            (kind ~= fullName) and "城市频道" or "自建频道",
            hidden and "（隐藏，已忽略）" or ""))
    end

    local function Keys(t)
        local list = {}
        for k in pairs(t or {}) do
            list[#list + 1] = tostring(k)
        end
        table.sort(list)
        return #list > 0 and table.concat(list, ", ") or "(空)"
    end

    local idPairs = {}
    for id, label in pairs((db and db.zoneChannelIDs) or {}) do
        idPairs[#idPairs + 1] = tostring(id) .. "=" .. tostring(label)
    end
    table.sort(idPairs)

    ns.Print("  zoneChannels   = " .. Keys(db and db.zoneChannels))
    ns.Print("  zoneChannelIDs = " .. (#idPairs > 0 and table.concat(idPairs, ", ") or "(空)"))
    ns.Print("  seenChannels   = " .. Keys(db and db.seenChannels))
    ns.Print("  customChannels = " .. Keys(db and db.customChannels))

    ns.debugPayloadLeft = 10
    ns.Print("以上是客户端直答，不需要自己发言。接下来 10 条频道消息会额外带出原始参数。")
end

----------------------------------------------------------------------------------------------------------------
-- Keywords
----------------------------------------------------------------------------------------------------------------

function ns.KeywordTooShort(kw)
    local db = ns.db
    local minLen = (db and db.settings and db.settings.minLen) or 2
    local parts = kw.parts
    if not parts or #parts == 0 then
        return true
    end

    -- Each AND part has to clear the same bar as a single keyword; otherwise a
    -- keyword like "a 出" would sneak a one-character part past the guard.
    for i = 1, #parts do
        if ns.CharCount(parts[i]) < minLen then
            return true
        end
    end

    return false
end

--- Rebuild the matching index. Only enabled keywords long enough to be useful.
function ns.RefreshKeywordIndex()
    local db = ns.db
    local list = {}

    local keywords = (db and db.keywords) or {}
    for i = 1, #keywords do
        local kw = keywords[i]
        if kw and kw.enabled and kw.norm and kw.norm ~= "" and not ns.KeywordTooShort(kw) then
            list[#list + 1] = kw
        end
    end

    -- Longest first: the more specific keyword wins, and the first hit is what
    -- gets written into the log line.
    table.sort(list, function(a, b)
        return #a.norm > #b.norm
    end)

    ns.activeKeywords = list
end

function ns.AddKeyword(text)
    local db = ns.db
    if not db then
        return false, "ERR_EMPTY"
    end

    local raw = ns.Trim(text)
    if raw == "" then
        return false, "ERR_EMPTY"
    end

    local norm = ns.Normalize(raw)
    if norm == "" then
        return false, "ERR_MEANINGLESS"
    end

    db.keywords = db.keywords or {}
    for i = 1, #db.keywords do
        if db.keywords[i].norm == norm then
            return false, "ERR_DUP"
        end
    end

    table.insert(db.keywords, {
        text = raw,
        norm = norm,
        parts = ns.KeywordParts(raw),
        enabled = true,
        added = ns.Now(),
    })

    ns.RefreshKeywordIndex()
    return true
end

function ns.RemoveKeyword(index)
    local db = ns.db
    if not db or not db.keywords or not db.keywords[index] then
        return nil
    end

    local removed = table.remove(db.keywords, index)
    ns.RefreshKeywordIndex()
    return removed
end

--- Remove by identity, not by index: list rows are sorted for display, so a row
-- cannot hold a reliable index into the saved table.
function ns.RemoveKeywordEntry(entry)
    local db = ns.db
    if not db or not db.keywords then
        return nil
    end

    for i = 1, #db.keywords do
        if db.keywords[i] == entry then
            return ns.RemoveKeyword(i)
        end
    end

    return nil
end

function ns.SetKeywordEnabled(index, enabled)
    local db = ns.db
    local kw = db and db.keywords and db.keywords[index]
    if not kw then
        return
    end
    kw.enabled = enabled and true or false
    ns.RefreshKeywordIndex()
end

function ns.ClearKeywords()
    if not ns.db then
        return
    end
    ns.db.keywords = {}
    ns.RefreshKeywordIndex()
end

function ns.ApplyDefaultChannels()
    if not ns.db then
        return
    end
    ns.db.channels = {}
    for i = 1, #ns.CHANNELS do
        local info = ns.CHANNELS[i]
        ns.db.channels[info.key] = info.default and true or false
    end
end

----------------------------------------------------------------------------------------------------------------
-- The filter itself
----------------------------------------------------------------------------------------------------------------

local DEDUPE_WINDOW = 0.5
ns.dedupe = {}
ns.dedupeCount = 0

function ns.ResetDedupe()
    ns.dedupe = {}
    ns.dedupeCount = 0
end

----------------------------------------------------------------------------------------------------------------
-- Anti-spam: the same person posting the same text again and again
----------------------------------------------------------------------------------------------------------------

local SPAM_WINDOW = 60 -- seconds between two copies to still count as one burst
local SPAM_MAX_ENTRIES = 400
local SPAM_REASON = "@spam" -- log marker; the log page translates it

ns.spamSeen = {}
ns.spamCount = 0

function ns.ResetSpam()
    ns.spamSeen = {}
    ns.spamCount = 0
end

--- Is this line a repeat of what the same person just said?
-- Keyed by sender + normalised text only: the channel it arrives on is
-- deliberately NOT part of the key (nor compared), so a line shouted into a
-- second channel right after being said in the first one is caught too.
-- @return true when the line should be hidden as spam
function ns.IsSpam(senderText, norm)
    if type(norm) ~= "string" or norm == "" then
        return false
    end

    local key = senderText .. "\1" .. norm
    local now = GetTime()
    local last = ns.spamSeen[key]

    if last then
        local elapsed = now - last

        -- elapsed == 0 means the very same line was handed to the filter again
        -- inside one frame (every chat frame that listens to the event delivers a
        -- copy), which is not a repeat the player typed. Calling GetTime() twice
        -- within a frame returns the same value, so this tells the two apart.
        if elapsed > 0 and elapsed <= SPAM_WINDOW then
            ns.spamSeen[key] = now
            return true
        end
    else
        ns.spamCount = ns.spamCount + 1
        if ns.spamCount > SPAM_MAX_ENTRIES then
            ns.ResetSpam()
            ns.spamCount = 1
        end
    end

    -- The stamp is stored as a bare number, not a { t = now } table: one fewer
    -- allocation per entry, and this table is the only thing here that grows.
    ns.spamSeen[key] = now

    return false
end

--- Decide whether this line must be thrown away, and store it first when it is.
local function Process(event, msg, sender, channelString, zoneChannelID)
    local db = ns.db
    if not db then
        return false
    end

    local settings = db.settings
    if not settings or not settings.enabled then
        return false
    end

    local info = ns.eventInfo[event]
    if not info then
        return false
    end

    if not (db.channels and db.channels[info.key]) then
        return false
    end

    -- secret values: no comparison, no length, no tostring. Let it through.
    if not ns.IsReadable(msg) then
        return false
    end
    if type(msg) ~= "string" or msg == "" then
        return false
    end

    -- Channels are filtered per name. City/zone channels (综合 / 交易 / 本地防务…)
    -- are one room per region but only a handful of kinds: they get one switch per
    -- kind and stay out of the player-made list entirely, because they are not
    -- player-made. A region that was never joined still inherits the kind's switch,
    -- so joining 综合 - 灰谷 later obeys the 综合 tick.
    local channel = nil
    if info.key == "CHANNEL" then
        local name = ns.SplitChannelString(channelString)
        if name then
            local folded = ns.ZoneChannelType(name)
            local zoneID = tonumber(zoneChannelID) or 0
            local kind = db.zoneChannelIDs and db.zoneChannelIDs[zoneID]

            -- The zone id alone is not a verdict: a player-made channel reports 27, not
            -- 0. It only counts when the id is one GetChannelList() actually called a
            -- city channel (the map built by SyncZoneChannels) AND the payload name still
            -- carries " - <region>". Both signals, so a page tick reaches the filter and
            -- a player channel can never slip into the city row.
            if kind and folded ~= name then
                channel = kind

                db.zoneChannels = type(db.zoneChannels) == "table" and db.zoneChannels or {}
                if db.zoneChannels[kind] == nil then
                    db.zoneChannels[kind] = true
                end

                if db.zoneChannels[kind] == false then
                    return false
                end
            else
                channel = ns.ChannelKey(name)

                -- Remembered even when the channel is unticked, so the page keeps
                -- listing it with its tick state after a relog.
                ns.RememberChannel(name)
                if not ns.IsCustomChannelAllowed(name) then
                    return false
                end
            end
        end
    end

    if ns.IsSelf(sender) then
        return false
    end

    local senderText = "?"
    if ns.IsReadable(sender) and type(sender) == "string" and sender ~= "" then
        senderText = sender
    end

    -- Normalise once: the anti-spam check and the keyword match both need it, so the
    -- early "no keywords configured" bail-out has to happen after this point.
    local norm = ns.Normalize(msg)
    if norm == "" then
        return false
    end

    -- Repeat spam, when the player turned it on. The channel does not matter here:
    -- saying the same thing twice in one channel is caught just like saying it once
    -- in each of two channels.
    local spam = false
    if settings.antiSpam then
        spam = ns.IsSpam(senderText, norm)
    end

    local matched = nil
    local keywords = ns.activeKeywords

    if keywords and #keywords > 0 then
        for i = 1, #keywords do
            local kw = keywords[i]
            local parts = kw.parts

            if not parts or #parts == 0 then
                -- Defensive: an entry that somehow lost its parts still matches as a
                -- single glued string instead of silently doing nothing.
                if kw.norm and kw.norm ~= "" and norm:find(kw.norm, 1, true) then
                    matched = kw
                    break
                end
            else
                local all = true
                for p = 1, #parts do
                    if not norm:find(parts[p], 1, true) then
                        all = false
                        break
                    end
                end
                if all then
                    matched = kw
                    break
                end
            end
        end
    end

    if not matched and not spam then
        return false
    end

    -- One line reaches the filter once per chat window that listens to that
    -- event, so the same payload arrives several times in the same frame. Keep
    -- only the first copy in the log, but still block every copy.
    local key = event .. "\1" .. senderText .. "\1" .. msg
    local now = GetTime()
    local last = ns.dedupe[key]

    if last and (now - last) < DEDUPE_WINDOW then
        return true
    end

    ns.dedupe[key] = now
    ns.dedupeCount = ns.dedupeCount + 1
    if ns.dedupeCount > 400 then
        ns.ResetDedupe()
        ns.dedupe[key] = now
        ns.dedupeCount = 1
    end

    ns.AddLogEntry({
        t = ns.Now(),
        ch = info.key,
        channel = channel,
        from = senderText,
        msg = ns.StoreMessage(msg),
        kw = matched and matched.text or SPAM_REASON,
    })

    -- "log only" mode: record it, then let the chat frame draw it.
    if settings.logOnly then
        return false
    end

    return true
end

--- Registered callback. Errors must never escape into the chat pipeline, and a
-- throw is treated as "do not block".
-- CHAT_MSG_CHANNEL payload (1-based, after the event name):
--   1 text, 2 playerName, 3 languageName, 4 channelName, 5 playerName2,
--   6 specialFlags, 7 zoneChannelID, 8 channelIndex, 9 channelBaseName, ...
-- specialFlags is a STRING ("GM" / "AFK" / "DND"), so reading it as the zone id
-- made every city channel look player-made. The slot has to stay even though it
-- is unused, or everything after it shifts by one.
local function Handler(self, event, msg, sender, language, channelString, _playerName2, _specialFlags, zoneChannelID)
    -- `/scf debug` arms this for the next few channel lines: the exact argument
    -- positions are the thing to check against the client, not against the wiki.
    -- Only CHANNEL lines: this handler is registered on 17 events, so a stray SAY or
    -- YELL used to burn the quota before a single channel line arrived.
    if (ns.debugPayloadLeft or 0) > 0 and event == "CHAT_MSG_CHANNEL" then
        ns.debugPayloadLeft = ns.debugPayloadLeft - 1
        ns.Print(string.format("payload chStr=%s p2=%s flags=%s zoneID=%s | msg=%s",
            tostring(channelString), tostring(_playerName2),
            tostring(_specialFlags), tostring(zoneChannelID), tostring(ns.Truncate(msg, 24))))
    end

    local ok, block = pcall(Process, event, msg, sender, channelString, zoneChannelID)
    if not ok then
        return false
    end
    return block and true or false
end

ns.registered = {}

--- Is our handler still on the client's filter chain for this event?
-- Both ChatFrame_AddMessageEventFilter and the ChatFrameUtil wrapper keep the list
-- in the ChatFrame_MessageEventFilters global. Returning nil means the table is not
-- readable on this client, and the caller falls back to the `registered` flag.
local function HandlerOnChain(event)
    local chain = _G.ChatFrame_MessageEventFilters
    local list = chain and chain[event]

    if type(list) ~= "table" then
        return nil
    end

    for i = 1, #list do
        if list[i] == Handler then
            return true
        end
    end

    return false
end

--- Register one filter per supported event.
-- Some loading paths wipe the client's filter list, so "we registered at login" is
-- not proof the filter is still there. Each pass asks the chain itself and only
-- re-adds what is genuinely missing; the `registered` flag stays as the fallback
-- for clients where the chain cannot be read.
-- @return how many events were registered this pass, or nil when the API is absent
function ns.RegisterFilters()
    local add = (_G.ChatFrameUtil and _G.ChatFrameUtil.AddMessageEventFilter)
        or _G.ChatFrame_AddMessageEventFilter

    if not add then
        return nil
    end

    local added = 0
    for i = 1, #ns.CHANNELS do
        local info = ns.CHANNELS[i]
        local onChain = HandlerOnChain(info.event)
        local needed = (onChain == false) or (onChain == nil and not ns.registered[info.event])

        if needed then
            local ok = pcall(add, info.event, Handler)
            if ok then
                ns.registered[info.event] = true
                added = added + 1
            end
        end
    end

    return added
end
