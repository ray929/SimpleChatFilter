local addonName, ns = ...

local W = ns.W

local LABEL_X = 14
local CONTROL_X = 190
local LABEL_WIDTH = CONTROL_X - LABEL_X

local page

local function LanguageOptions()
    return {
        { value = "auto", text = ns.L("OPT_LOCALE_AUTO", GetLocale()) },
        { value = "enUS", text = "English" },
        { value = "zhCN", text = "简体中文" },
        { value = "zhTW", text = "正體中文" },
    }
end

local function ResolveLocale(code)
    if code == nil or code == "auto" or code == "" then
        return GetLocale()
    end
    return code
end

--- Offer a reload when the picked language is not the one on screen. The value
-- is already saved, so "later" only postpones the switch.
local function PromptReload(locale)
    if ResolveLocale(locale) == (ns.currentLocale or GetLocale()) then
        return false
    end

    local dialogs = _G.StaticPopupDialogs
    local show = _G.StaticPopup_Show

    -- Registered lazily: the popup table belongs to Blizzard and may not exist
    -- yet when this file loads.
    if dialogs and show then
        dialogs["SCF_RELOAD"] = {
            text = ns.L("MSG_RELOAD_PROMPT"),
            button1 = ns.L("BTN_RELOAD"),
            button2 = ns.L("BTN_LATER"),
            OnAccept = function()
                if _G.ReloadUI then
                    _G.ReloadUI()
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        if pcall(show, "SCF_RELOAD") then
            return true
        end
    end

    ns.Print(ns.L("MSG_RELOAD_REQUIRED"))
    return true
end

local function BindCheck(box, getter, setter)
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

function ns.CreateOptionPage(parent)
    if page then
        return page
    end

    page = CreateFrame("Frame", "SimpleChatFilterOptionsPanel", parent)
    page:SetSize(600, 520)

    local y = -8

    page.heading = W.Heading(page, ns.L("PAGE_OVERVIEW"))
    page.heading:SetPoint("TOPLEFT", page, "TOPLEFT", 10, y)

    page.version = W.Small(page, "")
    page.version:SetPoint("TOPRIGHT", page, "TOPRIGHT", -14, -12)
    page.version:SetTextColor(0.62, 0.62, 0.62, 1)

    y = y - 28

    page.desc = W.Dim(page, nil)
    page.desc:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
    page.desc:SetWidth(560)
    page.desc:SetJustifyH("LEFT")
    page.desc:SetText(ns.L("OVERVIEW_DESC"))
    y = y - math.max(page.desc:GetStringHeight() or 0, 28) - 10

    page.status = W.Text(page, "", "GameFontNormal")
    page.status:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
    y = y - 22

    page.summary = W.Dim(page, "")
    page.summary:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
    y = y - 26

    page.headingSwitch = W.Heading(page, ns.L("OPT_HEAD_SWITCH"))
    page.headingSwitch:SetPoint("TOPLEFT", page, "TOPLEFT", 10, y)
    y = y - 26

    local function AddBox(key, labelKey, setter)
        local box = BindCheck(W.Checkbox(page, ns.L(labelKey)),
            function()
                return ns.db and ns.db.settings[key]
            end,
            setter)
        box:SetPoint("TOPLEFT", page, "TOPLEFT", LABEL_X, y)
        y = y - 24
        return box
    end

    page.enabled = AddBox("enabled", "OPT_ENABLED", function(value)
        ns.db.settings.enabled = value
        page:Refresh()
    end)

    page.logOnly = AddBox("logOnly", "OPT_LOGONLY", function(value)
        ns.db.settings.logOnly = value
    end)

    page.showRealm = AddBox("showRealm", "OPT_SHOWREALM", function(value)
        ns.db.settings.showRealm = value
        if ns.pages and ns.pages.log then
            ns.pages.log:Refresh()
        end
    end)

    page.showMinimap = AddBox("showMinimap", "OPT_MINIMAP", function(value)
        ns.db.settings.showMinimap = value
        if ns.UpdateMinimapButton then
            ns.UpdateMinimapButton()
        end
    end)

    -- Off by default: it hides lines that no keyword asked for, so it has to be a
    -- deliberate choice. Turning it off drops the remembered burst so re-enabling it
    -- starts from a clean state.
    page.antiSpam = AddBox("antiSpam", "OPT_ANTISPAM", function(value)
        ns.db.settings.antiSpam = value
        if not value and ns.ResetSpam then
            ns.ResetSpam()
        end
    end)

    y = y - 6

    page.headingKeyword = W.Heading(page, ns.L("OPT_HEAD_KEYWORD"))
    page.headingKeyword:SetPoint("TOPLEFT", page, "TOPLEFT", 10, y)
    y = y - 28

    page.minLenLabel = W.Text(page, ns.L("OPT_MINLEN"), "GameFontHighlight")
    page.minLenLabel:SetPoint("TOPLEFT", page, "TOPLEFT", LABEL_X, y)

    page.minLenEdit = W.EditBox(page, 50, 22)
    page.minLenEdit:SetNumeric(true)
    page.minLenEdit:SetPoint("TOPLEFT", page, "TOPLEFT", CONTROL_X, y + 4)

    page.minLenUnit = W.Dim(page, ns.L("OPT_MINLEN_UNIT"))
    page.minLenUnit:SetPoint("LEFT", page.minLenEdit, "RIGHT", 6, 0)
    y = y - 32

    page.headingLang = W.Heading(page, ns.L("OPT_HEAD_LANG"))
    page.headingLang:SetPoint("TOPLEFT", page, "TOPLEFT", 10, y)
    y = y - 28

    page.localePicker = W.Picker(page, ns.L("OPT_LOCALE"), 200, LABEL_WIDTH)
    page.localePicker:SetOptions(LanguageOptions)
    page.localePicker:SetValue(ns.db.settings.locale)
    page.localePicker:SetPoint("TOPLEFT", page, "TOPLEFT", CONTROL_X, y)
    page.localePicker:SetOnSelect(function(value)
        ns.db.settings.locale = value
        PromptReload(value)
    end)
    y = y - 30

    page.reloadHint = W.Dim(page, ns.L("OPT_RELOAD_HINT"))
    page.reloadHint:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
    y = y - 26

    page.note = W.Dim(page, nil)
    page.note:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
    page.note:SetWidth(560)
    page.note:SetJustifyH("LEFT")
    page.note:SetText(ns.L("OPT_SECRET_NOTE"))

    local function CommitMinLen()
        local value = tonumber(page.minLenEdit:GetText())
        if not value then
            page.minLenEdit:SetText(tostring(ns.db.settings.minLen))
            return
        end
        ns.db.settings.minLen = ns.Clamp(math.floor(value + 0.5), 2, 6)
        page.minLenEdit:SetText(tostring(ns.db.settings.minLen))
        ns.RefreshKeywordIndex()
        page:Refresh()
    end

    page.minLenEdit:SetScript("OnEnterPressed", function(self)
        CommitMinLen()
        self:ClearFocus()
    end)
    page.minLenEdit:SetScript("OnEditFocusLost", CommitMinLen)

    function page:Refresh()
        self.enabled:Sync()
        self.logOnly:Sync()
        self.antiSpam:Sync()
        self.showRealm:Sync()
        self.showMinimap:Sync()

        local settings = ns.db.settings
        local stateText = settings.enabled and ns.L("STATE_ON") or ns.L("STATE_OFF")
        self.status:SetText(ns.L("OVERVIEW_STATUS", stateText))
        if settings.enabled then
            self.status:SetTextColor(0.4, 0.9, 0.5, 1)
        else
            self.status:SetTextColor(1, 0.35, 0.35, 1)
        end

        local active = ns.activeKeywords and #ns.activeKeywords or 0
        self.summary:SetText(ns.L("OVERVIEW_COUNT", tostring(active), tostring(ns.GetLogCount())))

        self.minLenEdit:SetText(tostring(settings.minLen))
        self.version:SetText(ns.L("OPT_VERSION", ns.VERSION or ns.L("VERSION_LOCAL")))
        self.localePicker:SetValue(settings.locale)
    end

    page:SetScript("OnShow", function(self)
        self:Refresh()
    end)

    ns.pages = ns.pages or {}
    ns.pages.options = page

    return page
end
