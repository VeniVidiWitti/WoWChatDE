-- Chat DE - Fenster "Claude-Hilfe": Uebersetzen, Questhilfe, Talente, Antworten
-- Lizenz: GNU General Public License v2 oder spaeter, siehe LICENSE.
local ADDON, ns = ...
local C = ns.C

local W, H = 720, 520
local CW, CH = W - 28, H - 88 - 58   -- Inhaltsbereich
local ui
local pages, tabButtons, tabIndex = {}, {}, {}
local onShowFns = {}

local function cfg() return WoWChatDE_Config end

-- Text fuer die Uebertragung saeubern: Links lesbar machen, Farben und
-- Battle.net-Namen (|K...|k) entfernen
local function clean(s)
    s = tostring(s or "")
    s = s:gsub("|K.-|k", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|n", " ")
    return s
end

-- Fuer die Anzeige in FontStrings: "|" darstellbar machen
local function show(s) return (tostring(s or ""):gsub("|", "||")) end

local function fmtTime(t) return t and date("%d.%m. %H:%M", t) or "-" end

-- Liste mit Umschaltern in einem rollbaren Bereich
local function toggleList(parent, w, h, rowH)
    local sf, child = ns.Scroll(parent, w, h)
    local rows = {}
    local list = {}
    function list:Set(items, labelFn, onClick, isChecked)
        for i, item in ipairs(items) do
            local r = rows[i]
            if not r then
                r = ns.Toggle(child, "", w - 16, function(self) if self.onClick then self.onClick(self) end end)
                r:SetHeight(rowH - 3)
                r.label:ClearAllPoints()
                r.label:SetPoint("LEFT", 8, 0)
                r.label:SetPoint("RIGHT", -6, 0)
                r.label:SetJustifyH("LEFT")
                r:SetPoint("TOPLEFT", 2, -(i - 1) * rowH - 2)
                rows[i] = r
            end
            r.item = item
            r:SetText(labelFn(item))
            r.onClick = function(self) onClick(self.item, self) end
            r:SetChecked(isChecked and isChecked(item) or false)
            r:Show()
        end
        for i = #items + 1, #rows do rows[i]:Hide() end
        child:SetHeight(math.max(1, #items * rowH + 4))
        sf:UpdateBar()
    end
    function list:Rows() return rows end
    return sf, list
end

-- ---------------------------------------------------------------
-- Reiter "Übersetzen"
-- ---------------------------------------------------------------
local selected = {}
local MAX_LINES = 15

local function buildTranslate(p)
    local info = ns.Text(p, "GameFontHighlightSmall",
        "Wähle Chatzeilen aus, die Claude sinngemäß übersetzen soll. Gesendet werden nur die Texte - keine Namen.", C.dim)
    info:SetPoint("TOPLEFT", 12, -10)
    info:SetWidth(CW - 24)
    info:SetJustifyH("LEFT")

    local sf, list = toggleList(p, CW - 20, CH - 82, 24)
    sf:SetPoint("TOPLEFT", 10, -30)

    local target = ns.Text(p, "GameFontHighlight", "")
    target:SetPoint("BOTTOMLEFT", 12, 16)

    local function refresh()
        local items = ns.recent
        local valid = {}
        for _, it in ipairs(items) do valid[it] = true end
        for it in pairs(selected) do if not valid[it] then selected[it] = nil end end
        if #items == 0 then
            list:Set({ { empty = true } }, function() return "|cff9a96b8Noch keine Chatzeilen seit dem letzten Neuladen.|r" end, function() end)
        else
            list:Set(items, function(it)
                return ("|cffffd24d%s|r  |cff9a96b8[%s]|r  %s"):format(date("%H:%M", it.time), show(it.channel), show(clean(it.text)))
            end, function(it, row)
                if selected[it] then selected[it] = nil
                else
                    local n = 0
                    for _ in pairs(selected) do n = n + 1 end
                    if n >= MAX_LINES then
                        ns.Print(("Höchstens %d Zeilen auf einmal."):format(MAX_LINES))
                    else
                        selected[it] = true
                    end
                end
                row:SetChecked(selected[it] and true or false)
            end, function(it) return selected[it] end)
        end
        target:SetText("Zielsprache: |cffffd24d" .. (cfg().claudeTarget or "Deutsch") .. "|r  (ändern unter Einstellungen > Sprachen)")
    end
    ns.OnRecentChanged = function() if p:IsVisible() then refresh() end end
    onShowFns[p] = refresh

    local send = ns.Button(p, "Mit Claude übersetzen", 190, 26, function()
        local lines = {}
        for i = #ns.recent, 1, -1 do               -- aelteste zuerst
            local it = ns.recent[i]
            if selected[it] then lines[#lines + 1] = clean(it.text) end
        end
        if #lines == 0 then ns.Print("Bitte zuerst Zeilen auswählen."); return end
        local tgt = cfg().claudeTarget or "Deutsch"
        local summary = { ("%d Chattext(e), ohne Absender:"):format(#lines) }
        for i = 1, math.min(3, #lines) do summary[#summary + 1] = "   \"" .. show(ns.Utf8Sub(lines[i], 60)) .. "\"" end
        if #lines > 3 then summary[#summary + 1] = "   ..." end
        summary[#summary + 1] = "Zielsprache: " .. tgt
        ns.SendRequest({
            kind = "translate",
            title = ("Übersetzung (%d Zeilen) nach %s"):format(#lines, tgt),
            target = tgt,
            lines = lines,
        }, summary)
    end, true)
    send:SetPoint("BOTTOMRIGHT", -10, 10)
    local clear = ns.Button(p, "Auswahl leeren", 130, 26, function() wipe(selected); refresh() end)
    clear:SetPoint("RIGHT", send, "LEFT", -8, 0)
end

-- ---------------------------------------------------------------
-- Reiter "Quest"
-- ---------------------------------------------------------------
local function buildQuest(p)
    local quests, chosen = {}, nil

    local sf, list = toggleList(p, 280, CH - 20, 24)
    sf:SetPoint("TOPLEFT", 10, -10)

    local x = 304
    local title = ns.Text(p, "GameFontNormalLarge", "", C.gold)
    title:SetPoint("TOPLEFT", x, -12)
    title:SetWidth(CW - x - 12)
    title:SetJustifyH("LEFT")
    local detail = ns.Text(p, "GameFontHighlightSmall", "")
    detail:SetPoint("TOPLEFT", x, -38)
    detail:SetWidth(CW - x - 12)
    detail:SetJustifyH("LEFT")

    local ql = ns.Text(p, "GameFontNormal", "Deine Frage (freiwillig)", C.gold)
    ql:SetPoint("TOPLEFT", x, -(CH - 110))
    local question = ns.EditBox(p, CW - x - 12, 24, 200)
    question:SetPoint("TOPLEFT", x, -(CH - 90))
    ns.AttachTooltip(question, "Deine Frage", "Zum Beispiel: Wo finde ich den Questgeber? Wie besiege ich den Gegner? Ohne Frage gibt Claude allgemeine Tipps zu dieser Quest.")

    local function showQuest(entry)
        chosen = entry
        if not entry then
            title:SetText("Wähle links eine Quest")
            detail:SetText("")
            return
        end
        local q = ns.CollectQuest(entry)
        title:SetText(show(q.title))
        local lines = {}
        if q.header then lines[#lines + 1] = "|cff9a96b8Gebiet:|r " .. show(q.header) end
        if q.level then lines[#lines + 1] = "|cff9a96b8Stufe:|r " .. q.level end
        for _, o in ipairs(q.objectives) do lines[#lines + 1] = "- " .. show(o) end
        if q.summary and q.summary ~= "" then lines[#lines + 1] = "\n" .. show(ns.Utf8Sub(q.summary, 220)) end
        detail:SetText(table.concat(lines, "\n"))
    end

    local function refresh()
        quests = ns.ListQuests()
        if #quests == 0 then
            list:Set({ {} }, function() return "|cff9a96b8Keine Quests im Questlog.|r" end, function() end)
            showQuest(nil)
            return
        end
        list:Set(quests, function(q)
            return show(q.title) .. (q.complete and "  |cff40ff60(fertig)|r" or "")
        end, function(q)
            showQuest(q)
            for _, r in ipairs(list:Rows()) do r:SetChecked(r.item == q) end
        end, function(q) return chosen and chosen.questID == q.questID end)
        if chosen then
            local still
            for _, q in ipairs(quests) do if q.questID == chosen.questID then still = q end end
            showQuest(still)
        else
            showQuest(nil)
        end
    end
    onShowFns[p] = refresh

    local send = ns.Button(p, "Claude fragen", 160, 26, function()
        if not chosen then ns.Print("Bitte zuerst eine Quest auswählen."); return end
        local q = ns.CollectQuest(chosen)
        local pl = ns.PlayerInfo()
        local ask = question:GetText() or ""
        local summary = {
            "Quest: " .. show(q.title) .. (q.header and (" (" .. show(q.header) .. ")") or ""),
            "Questbeschreibung und Questziele",
            ("Deine Stufe (%s) und Klasse (%s)"):format(tostring(pl.level or "?"), tostring(pl.class or "?")),
        }
        if ask ~= "" then summary[#summary + 1] = "Deine Frage: \"" .. show(ask) .. "\"" end
        ns.SendRequest({
            kind = "quest",
            title = "Quest: " .. tostring(q.title),
            quest = q,
            player = { level = pl.level, class = pl.class },
            question = ask,
        }, summary)
    end, true)
    send:SetPoint("BOTTOMRIGHT", -10, 10)
end

-- ---------------------------------------------------------------
-- Reiter "Talente"
-- ---------------------------------------------------------------
local GOALS = { "Leveln", "Dungeons", "Schlachtzug", "PvP", "Solo & Farmen" }

local function buildTalents(p)
    local head = ns.Text(p, "GameFontNormalLarge", "", C.gold)
    head:SetPoint("TOPLEFT", 14, -12)
    local stat = ns.Text(p, "GameFontHighlight", "")
    stat:SetPoint("TOPLEFT", 14, -38)
    stat:SetWidth(CW - 28)
    stat:SetJustifyH("LEFT")

    local gl = ns.Text(p, "GameFontNormal", "Wofür sollen die Talente sein?", C.gold)
    gl:SetPoint("TOPLEFT", 14, -96)
    local goalButtons = {}
    for i, g in ipairs(GOALS) do
        local b = ns.Toggle(p, g, 124, function()
            cfg().talentGoal = g
            for _, o in ipairs(goalButtons) do o:SetChecked(o.goal == g) end
        end)
        b.goal = g
        b:SetPoint("TOPLEFT", 14 + (i - 1) * 130, -116)
        goalButtons[i] = b
    end

    local ql = ns.Text(p, "GameFontNormal", "Wünsche oder Frage (freiwillig)", C.gold)
    ql:SetPoint("TOPLEFT", 14, -156)
    local question = ns.EditBox(p, CW - 28, 24, 200)
    question:SetPoint("TOPLEFT", 14, -176)
    ns.AttachTooltip(question, "Wünsche", "Zum Beispiel: Ich spiele lieber auf Abstand. Oder: Ich habe wenig Ausrüstung. Oder: Wohin mit meinen freien Punkten?")

    local hint = ns.Text(p, "GameFontHighlightSmall",
        "Claude sieht deine aktuelle Talentwahl und schlägt vor, wohin die nächsten Punkte gehen sollen. " ..
        "Verteilen musst du sie selbst - Addons dürfen Talente nicht automatisch setzen.", C.dim)
    hint:SetPoint("TOPLEFT", 14, -212)
    hint:SetWidth(CW - 28)
    hint:SetJustifyH("LEFT")

    local talents
    local function refresh()
        local pl = ns.PlayerInfo()
        head:SetText(("%s  -  Stufe %s"):format(show(pl.class or "?"), tostring(pl.level or "?")) ..
            (pl.spec and ("  -  " .. show(pl.spec)) or ""))
        talents = ns.CollectTalents()
        if talents then
            stat:SetText(("Talentsystem: %s\nGewählt: %d    Noch verfügbar (Auswahl): %d    Freie Punkte: %s"):format(
                talents.system or "?", #talents.chosen, #talents.available, tostring(talents.unspent or "?")))
        else
            stat:SetText("|cffff8040Die Talente konnten nicht gelesen werden.|r Claude kann trotzdem allgemeine Tipps für Klasse und Stufe geben.")
        end
        for _, o in ipairs(goalButtons) do o:SetChecked(o.goal == (cfg().talentGoal or "Leveln")) end
    end
    onShowFns[p] = refresh

    local send = ns.Button(p, "Talentvorschlag holen", 190, 26, function()
        refresh()
        local pl = ns.PlayerInfo()
        local goal = cfg().talentGoal or "Leveln"
        local ask = question:GetText() or ""
        local summary = {
            ("Klasse (%s), Spezialisierung (%s), Stufe (%s)"):format(tostring(pl.class or "?"), tostring(pl.spec or "-"), tostring(pl.level or "?")),
            talents and ("Deine Talentwahl (%d gewählt) und verfügbare Talente"):format(#talents.chosen) or "keine Talentdaten (nicht lesbar)",
            "Ziel: " .. goal,
        }
        if ask ~= "" then summary[#summary + 1] = "Deine Wünsche: \"" .. show(ask) .. "\"" end
        ns.SendRequest({
            kind = "talents",
            title = ("Talente: %s (%s)"):format(tostring(pl.class or "?"), goal),
            player = pl,
            goal = goal,
            question = ask,
            talents = talents,
        }, summary)
    end, true)
    send:SetPoint("BOTTOMRIGHT", -10, 10)
end

-- ---------------------------------------------------------------
-- Reiter "Antworten"
-- ---------------------------------------------------------------
local function buildAnswers(p)
    local current
    local sf, list = toggleList(p, 250, CH - 56, 34)
    sf:SetPoint("TOPLEFT", 10, -10)

    local x = 272
    local box = ns.Panel(p, C.field, C.border)
    box:SetPoint("TOPLEFT", x, -10)
    box:SetSize(CW - x - 10, CH - 20)
    local tsf, tchild = ns.Scroll(box, CW - x - 18, CH - 30)
    tsf:SetPoint("TOPLEFT", 4, -5)
    local text = ns.Text(tchild, "GameFontHighlight", "")
    text:SetPoint("TOPLEFT", 6, -4)
    text:SetWidth(CW - x - 40)
    text:SetJustifyH("LEFT")
    text:SetSpacing(2)

    local function showAnswer(h)
        current = h
        if not h then
            text:SetText("|cff9a96b8Noch keine Antworten. Stelle in den anderen Reitern eine Frage an Claude.|r")
        else
            local head = ("|cffffd24d%s|r\n|cff9a96b8gefragt %s, beantwortet %s%s|r\n\n"):format(
                show(h.title or "?"), fmtTime(h.asked), fmtTime(h.answered),
                (h.tokensIn and h.tokensIn > 0) and ("  -  Tokens %d/%d"):format(h.tokensIn, h.tokensOut or 0) or "")
            local body = h.error and ("|cffff5050Fehler:|r " .. show(h.error)) or show(h.text)
            text:SetText(head .. body)
        end
        tchild:SetHeight(text:GetStringHeight() + 12)
        tsf:SetVerticalScroll(0)
        tsf:UpdateBar()
    end

    local function refresh()
        local hist = ns.GetHistory()
        if #hist == 0 then
            list:Set({ {} }, function() return "|cff9a96b8(leer)|r" end, function() end)
            showAnswer(nil)
            return
        end
        if not current then current = hist[1] end
        list:Set(hist, function(h)
            return show(ns.Utf8Sub(h.title or "?", 30)) .. "\n|cff9a96b8" .. fmtTime(h.answered) .. "|r"
        end, function(h)
            showAnswer(h)
            for _, r in ipairs(list:Rows()) do r:SetChecked(r.item == h) end
        end, function(h) return h == current end)
        for _, r in ipairs(list:Rows()) do r.label:SetWordWrap(true) end
        showAnswer(current)
    end
    onShowFns[p] = refresh

    local clear = ns.Button(p, "Verlauf leeren", 120, 22, function()
        wipe(ns.GetHistory()); current = nil; refresh()
    end)
    clear:SetPoint("BOTTOMLEFT", 10, 10)
end

-- ---------------------------------------------------------------
-- Fenster
-- ---------------------------------------------------------------
local TABS = {
    { id = "translate", title = "Übersetzen", build = buildTranslate },
    { id = "quest", title = "Questhilfe", build = buildQuest },
    { id = "talents", title = "Talente", build = buildTalents },
    { id = "answers", title = "Antworten", build = buildAnswers },
}

local function updateStatus()
    if not ui then return end
    local pending = ns.PendingCount()
    local seen = ns.CompanionLastSeen()
    if pending > 0 then
        ui.status:SetText(("|cffffd24d%d Anfrage(n) unterwegs.|r Wenn das Begleitprogramm 'Antwort bereit' meldet, klicke auf 'Antwort laden'."):format(pending))
        ui.load:Show()
    else
        ui.status:SetText(seen and ("Begleitprogramm zuletzt gemeldet: " .. date("%d.%m.%Y %H:%M", seen))
            or "|cffff8040Begleitprogramm noch nie gemeldet|r - ohne es kommen keine Antworten an (siehe README).")
        ui.load:Hide()
    end
end

local function selectTab(i)
    for j, b in ipairs(tabButtons) do
        b:SetChecked(j == i)
        pages[j]:SetShown(j == i)
    end
    local fn = onShowFns[pages[i]]
    if fn then fn() end
    updateStatus()
end

local function build()
    local f = CreateFrame("Frame", "WoWChatDEAssistant", UIParent, "BackdropTemplate")
    ui = f
    f:SetSize(W, H)
    f:SetPoint("CENTER", 40, 0)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    ns.Skin(f, C.bg, C.border, true)
    tinsert(UISpecialFrames, "WoWChatDEAssistant")
    f:Hide()

    local header = f:CreateTexture(nil, "ARTWORK")
    header:SetPoint("TOPLEFT", 5, -5)
    header:SetPoint("TOPRIGHT", -5, -5)
    header:SetHeight(44)
    header:SetTexture("Interface\\Buttons\\WHITE8x8")
    if not pcall(function()
        header:SetGradient("HORIZONTAL", CreateColor(0.80, 0.45, 0.25, 0.95), CreateColor(0.08, 0.06, 0.10, 0.1))
    end) then header:SetVertexColor(0.6, 0.35, 0.2, 0.9) end

    local logo = f:CreateTexture(nil, "OVERLAY")
    logo:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
    logo:SetSize(34, 34)
    logo:SetPoint("TOPLEFT", 12, -10)
    logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = ns.Text(f, "GameFontNormalHuge", "|cffffb070Claude-Hilfe|r")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -1)
    local sub = ns.Text(f, "GameFontHighlightSmall", "Nur auf Knopfdruck  -  über das Begleitprogramm  -  Chat DE " .. ns.VERSION, C.dim)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)

    local close = ns.Button(f, "X", 26, 26, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -12, -14)
    local settings = ns.Button(f, "Einstellungen", 110, 26, function() ns.OpenSettings(4) end)
    settings:SetPoint("RIGHT", close, "LEFT", -6, 0)

    local content = ns.Panel(f, C.panel, C.border)
    content:SetPoint("TOPLEFT", 14, -88)
    content:SetSize(CW, CH)
    for i, t in ipairs(TABS) do
        local b = ns.Toggle(f, t.title, 130, function() selectTab(i) end)
        b:SetHeight(26)
        b:SetPoint("BOTTOMLEFT", content, "TOPLEFT", (i - 1) * 134, 4)
        tabButtons[i] = b
        tabIndex[t.id] = i
        local page = CreateFrame("Frame", nil, content)
        page:SetAllPoints()
        page:Hide()
        pages[i] = page
        t.build(page)
    end

    local bar = ns.Panel(f, C.panel, C.border)
    bar:SetPoint("TOPLEFT", content, "BOTTOMLEFT", 0, -6)
    bar:SetPoint("BOTTOMRIGHT", -14, 14)
    f.status = ns.Text(bar, "GameFontHighlightSmall", "")
    f.status:SetPoint("LEFT", 10, 0)
    f.status:SetPoint("RIGHT", -160, 0)
    f.status:SetJustifyH("LEFT")
    f.load = ns.Button(bar, "Antwort laden", 140, 26, function() ns.Reload() end, true)
    f.load:SetPoint("RIGHT", -8, 0)
    ns.AttachTooltip(f.load, "Antwort laden", "Lädt das Interface neu (kurzer Ladebildschirm). Danach steht Claudes Antwort im Reiter 'Antworten'.")

    f:SetScript("OnShow", updateStatus)
    selectTab(1)
    return f
end

function ns.OpenAssistant(tabId)
    if not ui then build() end
    ui:Show()
    selectTab(tabIndex[tabId] or tabIndex.translate)
end
