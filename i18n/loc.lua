local addonName, ns = ...

ns.ADDON_NAME = addonName
ns.defaultLocale = "enUS"
ns.locales = {}
ns.currentLocale = nil

--- Register one language table. Called by each i18n file at load time.
function ns.RegisterLocale(name, tbl)
    ns.locales[name] = tbl
end

--- The locale the UI should speak right now: stored override, else the client locale.
local function ResolveLocale()
    local setting = ns.db and ns.db.settings and ns.db.settings.locale or "auto"
    if setting == "auto" or setting == "" then
        return GetLocale()
    end
    return setting
end

--- Freeze the locale for this session. Changing it needs a /reload, same as CChatNotifier.
function ns.SetLocale()
    ns.currentLocale = ResolveLocale()
    if not ns.locales[ns.currentLocale] then
        ns.currentLocale = ns.defaultLocale
    end
end

--- Look a key up on every call instead of caching the table at file load.
-- Caching at load time would lock the UI into the client locale, because the
-- saved override is not readable until ADDON_LOADED.
function ns.L(key, ...)
    if key == nil then
        return ""
    end

    local fallback = ns.locales[ns.defaultLocale] or {}
    local tbl = ns.locales[ns.currentLocale or ns.defaultLocale] or fallback
    local value = tbl[key]

    if value == nil then
        value = fallback[key]
    end
    if value == nil then
        return tostring(key)
    end

    if select("#", ...) > 0 then
        local ok, res = pcall(string.format, value, ...)
        if ok then
            return res
        end
    end

    return value
end
