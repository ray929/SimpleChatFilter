local addonName, ns = ...

local issecretvalue = _G.issecretvalue
local gsub, strsub, strformat = string.gsub, string.sub, string.format

----------------------------------------------------------------------------------------------------------------
-- Text normalisation (design.md §4, tier A)
----------------------------------------------------------------------------------------------------------------

-- Chat escape sequences. Blizzard's own pipeline never shows these to the
-- player, but they arrive intact on the raw event payload, and a keyword must
-- never match inside one of them.
local ESCAPES = {
    "|c%x%x%x%x%x%x%x%x",   -- colour start
    "|H[^|]*|h",            -- hyperlink payload (the visible text follows it)
    "|T[^|]*|t",            -- texture / icon inline
    "|A[^|]*|a",            -- atlas inline
    "|K[^|]*|k",            -- battle.net inline
    "|n",                   -- newline escape
    "|r",                   -- colour reset
    "|h",                   -- hyperlink close
}

-- Noise that is NOT ASCII. These must be literal byte strings: a Lua character
-- class works per byte, so putting a multi-byte character inside "[...]" deletes
-- one byte of it and leaves mojibake that breaks every later match.
local NOISE = {
    "\227\128\128", -- U+3000 ideographic space
    "\194\160",     -- U+00A0 no-break space
    "\226\128\139", -- U+200B zero width space
    "\226\128\142", -- U+200E left-to-right mark
    "\226\128\143", -- U+200F right-to-left mark
    "\239\187\191", -- U+FEFF byte order mark
}

--- Normalise a chat line (or a keyword) for matching.
-- Escapes out, lower case, ASCII whitespace and ASCII symbols out, known
-- non-ASCII noise out. CJK punctuation is deliberately kept: tier A.
function ns.Normalize(text)
    if type(text) ~= "string" or text == "" then
        return ""
    end

    local s = text
    for i = 1, #ESCAPES do
        s = gsub(s, ESCAPES[i], "")
    end

    s = s:lower()
    s = gsub(s, "[%s%p%c]", "")

    for i = 1, #NOISE do
        s = gsub(s, NOISE[i], "")
    end

    return s
end

--- Split a keyword into its AND parts. A keyword typed with spaces means "all of
-- these words must be somewhere in the line", in any order; a keyword typed as
-- one run means "this string", and the normaliser already glues "a b" together.
-- The ideographic space is turned into an ASCII one first, because %s does not
-- match U+3000.
function ns.KeywordParts(text)
    local parts = {}
    if type(text) ~= "string" or text == "" then
        return parts
    end

    local spaced = gsub(text, "\227\128\128", " ")

    local seen = {}
    local token
    for token in spaced:gmatch("%S+") do
        local norm = ns.Normalize(token)
        if norm ~= "" and not seen[norm] then
            seen[norm] = true
            parts[#parts + 1] = norm
        end
    end

    return parts
end

--- Count characters, not bytes. `#s` would answer in bytes and every CJK
-- character costs three of them.
function ns.CharCount(s)
    if type(s) ~= "string" or s == "" then
        return 0
    end
    return (select(2, gsub(s, "[^\128-\191]", "")))
end

--- Cut a string to at most `maxChars` characters, appending an ellipsis.
function ns.Truncate(text, maxChars)
    if type(text) ~= "string" then
        return ""
    end

    local total = ns.CharCount(text)
    if total <= maxChars then
        return text
    end

    local counted, i = 0, 1
    while i <= #text do
        local byte = text:byte(i)
        local size = 1
        if byte >= 240 then
            size = 4
        elseif byte >= 224 then
            size = 3
        elseif byte >= 192 then
            size = 2
        end

        counted = counted + 1
        if counted > maxChars then
            return strsub(text, 1, i - 1) .. "..."
        end

        i = i + size
    end

    return text
end

----------------------------------------------------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------------------------------------------------

function ns.Trim(value)
    return (gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1"))
end

--- Secret values (12.x) must never reach a comparison, a length read or tostring.
function ns.IsReadable(value)
    if value == nil then
        return false
    end
    if issecretvalue and issecretvalue(value) then
        return false
    end
    return true
end

function ns.Now()
    if GetServerTime then
        return GetServerTime()
    end
    return time()
end

function ns.Clock(epoch)
    if type(epoch) ~= "number" then
        return "?"
    end
    return date("%m-%d %H:%M", epoch)
end

local playerName = nil

function ns.PlayerName()
    if playerName == nil then
        playerName = UnitName("player") or ""
    end
    return playerName
end

--- Strip the "-Realm" suffix off a cross-realm name.
function ns.NameWithoutRealm(name)
    if type(name) ~= "string" or name == "" then
        return ""
    end
    return (name:match("^([^%-]+)") or name)
end

function ns.IsSelf(sender)
    if type(sender) ~= "string" then
        return false
    end
    local name = ns.PlayerName()
    return name ~= "" and ns.NameWithoutRealm(sender) == name
end

function ns.Print(text)
    local frame = _G.DEFAULT_CHAT_FRAME
    local message = "|cff4fa3ff" .. (ns.ADDON_NAME or "SimpleChatFilter") .. "|r " .. tostring(text or "")
    if frame and frame.AddMessage then
        frame:AddMessage(message)
    else
        print(message)
    end
end

function ns.Clamp(value, low, high)
    if value < low then
        return low
    end
    if value > high then
        return high
    end
    return value
end
