local addonName, ns = ...

ns.logListeners = {}

--- Notify the log page. Cheap: one listener, and it no-ops when the page is hidden.
function ns.NotifyLogChanged()
    for i = 1, #ns.logListeners do
        pcall(ns.logListeners[i])
    end
end

local MAX_STORED_CHARS = 200

--- Append one blocked line. Oldest entries sit at index 1, newest at the end;
-- the page walks backwards from the tail.
function ns.AddLogEntry(entry)
    local db = ns.db
    if not db then
        return
    end

    db.log = db.log or {}
    table.insert(db.log, entry)

    -- Keep the table from exploding between two prune ticks.
    local hardCap = (db.cleanup and db.cleanup.maxEntries or 2000) + 200
    if #db.log > hardCap then
        ns.PruneLog()
    end

    ns.NotifyLogChanged()
end

--- Drop entries that are too old or beyond the count limit.
-- @return true when something was actually dropped
function ns.PruneLog()
    local db = ns.db
    if not db or not db.log then
        return false
    end

    local log = db.log
    local count = #log
    if count == 0 then
        return false
    end

    local cleanup = db.cleanup or {}
    local now = ns.Now()
    local drop = 0

    if cleanup.timeoutOn then
        local horizon = now - (cleanup.timeoutHours or 720) * 3600
        while drop < count and (log[drop + 1].t or now) < horizon do
            drop = drop + 1
        end
    end

    if cleanup.maxOn then
        local overflow = count - (cleanup.maxEntries or 2000)
        if overflow > drop then
            drop = overflow
        end
    end

    if drop <= 0 then
        return false
    end

    local kept = {}
    for i = drop + 1, count do
        kept[#kept + 1] = log[i]
    end
    db.log = kept

    return true
end

function ns.ClearLog()
    if not ns.db then
        return
    end
    ns.db.log = {}
    ns.NotifyLogChanged()
end

function ns.GetLogCount()
    local db = ns.db
    if not db or not db.log then
        return 0
    end
    return #db.log
end

--- Entry number `offset` counted from the newest one (1 = newest).
function ns.GetLogEntry(offset)
    local db = ns.db
    if not db or not db.log then
        return nil
    end
    return db.log[#db.log - offset + 1]
end

function ns.StoreMessage(msg)
    return ns.Truncate(msg, MAX_STORED_CHARS)
end
