-- Chat DE - Einstellungsfenster, Minikarten-Knopf
-- Lizenz: GNU General Public License v2 oder spaeter, siehe LICENSE.
local ADDON, ns = ...
local C = ns.C

local W, H = 660, 470
local ui
local pages, tabButtons = {}, {}
local refreshers = {}

local function cfg() return WoWChatDE_Config end
local function changed()
    ns.ClearCache()
    for _, fn in ipairs(refreshers) do fn() end
end

local function fmtTime(t)
    if not t then return "noch nie" end
    return date("%d.%m.%Y %H:%M", t)
end

-- Gruppe von Umschaltern, von denen genau einer aktiv ist
local function radio(parent, options, width, getter, setter, x, y, perRow, gap)
    local buttons = {}
    perRow = perRow or #options
    gap = gap or 6
    for i, o in ipairs(options) do
        local b = ns.Toggle(parent, o.label, width, function()
            setter(o.value)
            changed()
        end, o.label, o.tip)
        local col = (i - 1) % perRow
        local row = math.floor((i - 1) / perRow)
        b:SetPoint("TOPLEFT", x + col * (width + gap), y - row * 28)
        b.value = o.value
        buttons[i] = b
    end
    table.insert(refreshers, function()
        local cur = getter()
        for _, b in ipairs(buttons) do b:SetChecked(b.value == cur) end
    end)
    return buttons
end

local function heading(parent, text, y)
    local h = ns.Text(parent, "GameFontNormal", text, C.gold)
    h:SetPoint("TOPLEFT", 16, y)
    return h
end

local function note(parent, text, y, x)
    local n = ns.Text(parent, "GameFontHighlightSmall", text, C.dim)
    n:SetPoint("TOPLEFT", x or 16, y)
    n:SetWidth(W - 60)
    n:SetJustifyH("LEFT")
    return n
end

-- ---------------------------------------------------------------
-- Reiter "Allgemein"
-- ---------------------------------------------------------------
local function buildGeneral(p)
    heading(p, "Übersetzung im Chat", -14)
    local master = ns.Button(p, "", 300, 40, function()
        cfg().enabled = not cfg().enabled
        changed()
    end, true)
    master:SetPoint("TOPLEFT", 16, -36)
    master.label:SetFontObject(GameFontNormalLarge)
    ns.AttachTooltip(master, "Übersetzung an/aus", "Schaltet die Offline-Übersetzung im Chat ein oder aus. Die Claude-Hilfe funktioniert unabhängig davon.")
    table.insert(refreshers, function()
        local on = cfg().enabled
        master:SetText(on and "|cff40ff60AN|r  -  Chat wird übersetzt" or "|cffff5050AUS|r  -  keine Übersetzung")
        master.primary = on
        master:Repaint()
    end)

    heading(p, "Anzeige", -92)
    radio(p, {
        { label = "Original + Übersetzung", value = "append", tip = "Die Übersetzung erscheint hinter der Originalnachricht." },
        { label = "Nur Übersetzung", value = "replace", tip = "Die Originalnachricht wird durch die Übersetzung ersetzt." },
    }, 190, function() return cfg().mode end, function(v) cfg().mode = v end, 16, -112)

    heading(p, "Optionen", -150)
    local own = ns.Toggle(p, "Eigene Nachrichten übersetzen", 230, function(_, on)
        cfg().skipOwn = not on
        changed()
    end, "Eigene Nachrichten", "Auch deine eigenen Chatzeilen übersetzen.")
    own:SetPoint("TOPLEFT", 16, -170)
    table.insert(refreshers, function() own:SetChecked(not cfg().skipOwn) end)

    local mm = ns.Toggle(p, "Minikarten-Knopf zeigen", 200, function(_, on)
        cfg().hideMinimap = not on
        if ns.minimap then ns.minimap:SetShown(on) end
    end)
    mm:SetPoint("LEFT", own, "RIGHT", 8, 0)
    table.insert(refreshers, function() mm:SetChecked(not cfg().hideMinimap) end)

    local ml = ns.Text(p, "GameFontHighlight", "Erst übersetzen ab", C.text)
    ml:SetPoint("TOPLEFT", 16, -206)
    local minus = ns.Button(p, "-", 24, 22, function()
        cfg().minWords = math.max(1, (cfg().minWords or 1) - 1); changed()
    end)
    minus:SetPoint("LEFT", ml, "RIGHT", 10, 0)
    local val = ns.Text(p, "GameFontNormalLarge", "", C.gold)
    val:SetPoint("LEFT", minus, "RIGHT", 10, 0)
    local plus = ns.Button(p, "+", 24, 22, function()
        cfg().minWords = math.min(6, (cfg().minWords or 1) + 1); changed()
    end)
    plus:SetPoint("LEFT", val, "RIGHT", 10, 0)
    local ml2 = ns.Text(p, "GameFontHighlight", "erkannten Wörtern", C.text)
    ml2:SetPoint("LEFT", plus, "RIGHT", 10, 0)
    table.insert(refreshers, function() val:SetText(tostring(cfg().minWords or 1)) end)

    heading(p, "Ausprobieren", -244)
    local box = ns.EditBox(p, 440, 24)
    box:SetPoint("TOPLEFT", 16, -264)
    box:SetText("lfm 1 healer for scholo, pst for inv ty")
    local result = ns.Text(p, "GameFontHighlight", "", { 0.6, 0.84, 1 })
    result:SetPoint("TOPLEFT", 16, -296)
    result:SetWidth(W - 60)
    result:SetJustifyH("LEFT")
    local test = ns.Button(p, "Testen", 100, 24, function()
        local tr = ns.Translate(box:GetText(), cfg().offlineDir)
        result:SetText("» " .. (tr or "(keine Übersetzung)"))
    end)
    test:SetPoint("LEFT", box, "RIGHT", 8, 0)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); test:Click() end)
end

-- ---------------------------------------------------------------
-- Reiter "Kanäle"
-- ---------------------------------------------------------------
local function buildChannels(p)
    heading(p, "In welchen Kanälen soll übersetzt werden?", -14)
    local buttons = {}
    for i, g in ipairs(ns.CHANNEL_GROUPS) do
        local b = ns.Toggle(p, g.label, 290, function(_, on)
            cfg().channels[g.key] = on
            changed()
        end)
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        b:SetHeight(26)
        b:SetPoint("TOPLEFT", 16 + col * 300, -40 - row * 32)
        buttons[g.key] = b
    end
    table.insert(refreshers, function()
        for key, b in pairs(buttons) do b:SetChecked(cfg().channels[key] ~= false) end
    end)
    local y = -40 - math.ceil(#ns.CHANNEL_GROUPS / 2) * 32 - 10
    local all = ns.Button(p, "Alle an", 120, 24, function()
        for _, g in ipairs(ns.CHANNEL_GROUPS) do cfg().channels[g.key] = true end
        changed()
    end)
    all:SetPoint("TOPLEFT", 16, y)
    local none = ns.Button(p, "Alle aus", 120, 24, function()
        for _, g in ipairs(ns.CHANNEL_GROUPS) do cfg().channels[g.key] = false end
        changed()
    end)
    none:SetPoint("LEFT", all, "RIGHT", 8, 0)
    note(p, "Für die Claude-Hilfe merkt sich Chat DE die letzten 30 Chatzeilen aller Kanäle - nur den Text, keine Absendernamen, und nur bis zum nächsten Neuladen.", y - 36)
end

-- ---------------------------------------------------------------
-- Reiter "Sprachen"
-- ---------------------------------------------------------------
local function buildLanguages(p)
    heading(p, "Offline-Übersetzung im Chat (ohne Internet)", -14)
    radio(p, {
        { label = "Englisch  →  Deutsch", value = "en-de", tip = "Englische Nachrichten bekommen eine deutsche Übersetzung." },
        { label = "Deutsch  →  Englisch", value = "de-en", tip = "Deutsche Nachrichten bekommen eine englische Übersetzung (einfacher, aus dem umgekehrten Wörterbuch)." },
    }, 220, function() return cfg().offlineDir end, function(v) cfg().offlineDir = v end, 16, -36)
    note(p, "Offline gibt es nur Englisch und Deutsch, weil nur dafür ein freies Wörterbuch vorliegt. Übersetzt wird Wort für Wort - der Sinn kommt an, der Satzbau nicht.", -68)

    heading(p, "Claude-Übersetzung: Zielsprache", -112)
    radio(p, (function()
        local o = {}
        for _, l in ipairs(ns.LANGUAGES) do o[#o + 1] = { label = l, value = l } end
        return o
    end)(), 112, function() return cfg().claudeTarget end, function(v) cfg().claudeTarget = v end, 16, -134, 5)
    note(p, "Die Ausgangssprache erkennt Claude selbst. Claude übersetzt ganze Sätze sinngemäß - nur auf Knopfdruck in der Claude-Hilfe (/chatde hilfe).", -200)
end

-- ---------------------------------------------------------------
-- Reiter "Claude"
-- ---------------------------------------------------------------
local function buildClaude(p)
    heading(p, "Begleitprogramm", -14)
    local status = ns.Text(p, "GameFontHighlight", "")
    status:SetPoint("TOPLEFT", 16, -34)
    status:SetWidth(W - 80)
    status:SetJustifyH("LEFT")
    table.insert(refreshers, function()
        local seen = ns.CompanionLastSeen()
        if seen then
            status:SetText("Zuletzt gemeldet: |cff40ff60" .. fmtTime(seen) .. "|r    Offene Anfragen: " .. ns.PendingCount())
        else
            status:SetText("|cffffd24dNoch nie gemeldet.|r Für die Claude-Funktionen das Begleitprogramm aus dem Ordner Companion installieren (siehe README).")
        end
    end)

    heading(p, "Tokenverbrauch", -66)
    local tok = ns.Text(p, "GameFontHighlight", "")
    tok:SetPoint("TOPLEFT", 16, -86)
    table.insert(refreshers, function()
        local c = cfg()
        tok:SetText(("Letzte Antwort: %d ein / %d aus      Gesamt: %d ein / %d aus"):format(
            c.lastTokensIn or 0, c.lastTokensOut or 0, c.tokensIn or 0, c.tokensOut or 0))
    end)
    local resetTok = ns.Button(p, "Zähler zurücksetzen", 160, 22, function()
        local c = cfg(); c.tokensIn, c.tokensOut, c.lastTokensIn, c.lastTokensOut = 0, 0, 0, 0
        changed()
    end)
    resetTok:SetPoint("TOPLEFT", 16, -108)
    note(p, "Kosten entstehen bei Anthropic pro Token. Jede Anfrage wird nur gesendet, wenn du auf einen Claude-Knopf klickst.", -138)

    heading(p, "Datenschutz-Hinweis", -170)
    local ns2 = ns.Text(p, "GameFontHighlight", "")
    ns2:SetPoint("TOPLEFT", 16, -190)
    table.insert(refreshers, function()
        if cfg().noticeAck == ns.VERSION then
            ns2:SetText("Abgeschaltet für Version " .. ns.VERSION .. " (erscheint nach dem nächsten Update wieder)")
        else
            ns2:SetText("|cff40ff60Wird vor jeder Anfrage angezeigt.|r")
        end
    end)
    local again = ns.Button(p, "Wieder anzeigen", 160, 22, function() ns.ResetNotice(); changed() end)
    again:SetPoint("TOPLEFT", 16, -212)

    heading(p, "Was übertragen wird", -248)
    note(p,
        "Übersetzen: nur die ausgewählten Chattexte und die Zielsprache.\n" ..
        "Questhilfe: Questtitel, Beschreibung, Ziele, Questgebiet, deine Stufe und Klasse.\n" ..
        "Talente: Klasse, Spezialisierung, Stufe, deine Talentwahl und dein Ziel.\n" ..
        "|cff9ad6ffNie:|r Charaktername, Realm, Konto, BattleTag, Gilde, Freunde, Chat-Absender, Position.\n" ..
        "Empfänger: api.anthropic.com (Anthropic, USA), über das Begleitprogramm auf deinem PC.", -268)

    local drop = ns.Button(p, "Offene Anfragen verwerfen", 190, 22, function()
        ns.CancelPending(); changed()
        ns.Print("Offene Anfragen verworfen.")
    end)
    drop:SetPoint("TOPRIGHT", -14, -10)
    ns.AttachTooltip(drop, "Offene Anfragen verwerfen", "Löscht Anfragen, die noch nicht beantwortet wurden. Das Begleitprogramm schickt sie dann nicht mehr ab, falls es sie noch nicht gesendet hat.")
end

-- ---------------------------------------------------------------
-- Fenster
-- ---------------------------------------------------------------
local TABS = {
    { title = "Allgemein", build = buildGeneral },
    { title = "Kanäle", build = buildChannels },
    { title = "Sprachen", build = buildLanguages },
    { title = "Claude", build = buildClaude },
}

local function selectTab(i)
    for j, b in ipairs(tabButtons) do
        b:SetChecked(j == i)
        pages[j]:SetShown(j == i)
    end
end

local function build()
    local f = CreateFrame("Frame", "WoWChatDESettings", UIParent, "BackdropTemplate")
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    ns.Skin(f, C.bg, C.border, true)
    tinsert(UISpecialFrames, "WoWChatDESettings")
    f:Hide()

    local header = f:CreateTexture(nil, "ARTWORK")
    header:SetPoint("TOPLEFT", 5, -5)
    header:SetPoint("TOPRIGHT", -5, -5)
    header:SetHeight(44)
    header:SetTexture("Interface\\Buttons\\WHITE8x8")
    if not pcall(function()
        header:SetGradient("HORIZONTAL", CreateColor(0.15, 0.55, 0.45, 0.95), CreateColor(0.06, 0.08, 0.10, 0.1))
    end) then header:SetVertexColor(0.12, 0.4, 0.33, 0.9) end

    local logo = f:CreateTexture(nil, "OVERLAY")
    logo:SetTexture("Interface\\Icons\\INV_Scroll_03")
    logo:SetSize(34, 34)
    logo:SetPoint("TOPLEFT", 12, -10)
    logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = ns.Text(f, "GameFontNormalHuge", "|cff33ff99Chat DE|r")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -1)
    local sub = ns.Text(f, "GameFontHighlightSmall", "Einstellungen  -  Version " .. ns.VERSION, C.dim)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)

    local close = ns.Button(f, "X", 26, 26, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -12, -14)
    local help = ns.Button(f, "Claude-Hilfe", 110, 26, function() ns.OpenAssistant() end, true)
    help:SetPoint("RIGHT", close, "LEFT", -6, 0)

    local content = ns.Panel(f, C.panel, C.border)
    content:SetPoint("TOPLEFT", 14, -88)
    content:SetPoint("BOTTOMRIGHT", -14, 14)
    for i, t in ipairs(TABS) do
        local b = ns.Toggle(f, t.title, 120, function() selectTab(i) end)
        b:SetHeight(26)
        b:SetPoint("BOTTOMLEFT", content, "TOPLEFT", (i - 1) * 124, 4)
        tabButtons[i] = b
        local page = CreateFrame("Frame", nil, content)
        page:SetAllPoints()
        page:Hide()
        pages[i] = page
        t.build(page)
    end
    f:SetScript("OnShow", function() for _, fn in ipairs(refreshers) do fn() end end)
    selectTab(1)
    return f
end

function ns.OpenSettings(tab)
    ui = ui or build()
    ui:Show()
    if tab then selectTab(tab) end
end

-- ---------------------------------------------------------------
-- Minikarten-Knopf und Addon-Sammelknopf
-- ---------------------------------------------------------------
local function tooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("Chat DE", C.gold[1], C.gold[2], C.gold[3])
    GameTooltip:AddLine("Linksklick: Einstellungen", 1, 1, 1)
    GameTooltip:AddLine("Rechtsklick: Claude-Hilfe", 1, 1, 1)
    GameTooltip:AddLine("Übersetzung: " .. (cfg().enabled and "|cff40ff60an|r" or "|cffff5050aus|r"), 1, 1, 1)
    GameTooltip:Show()
end

local function createMinimapButton()
    if ns.minimap or not Minimap then return end
    local b = CreateFrame("Button", "WoWChatDEMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Scroll_03")
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    local function place()
        local a = math.rad(cfg().minimapAngle or 200)
        local r = (Minimap:GetWidth() / 2) + 5
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
    end
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            cfg().minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            place()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then ns.OpenAssistant() else ns.OpenSettings() end
    end)
    b:SetScript("OnEnter", tooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    place()
    if cfg().hideMinimap then b:Hide() end
    ns.minimap = b
end
table.insert(ns.onLogin, createMinimapButton)

function WoWChatDE_OnCompartmentClick(_, button)
    if button == "RightButton" then ns.OpenAssistant() else ns.OpenSettings() end
end
function WoWChatDE_OnCompartmentEnter(_, button) tooltip(button or UIParent) end
function WoWChatDE_OnCompartmentLeave() GameTooltip:Hide() end
