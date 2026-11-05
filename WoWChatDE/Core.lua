-- Chat DE fuer World of Warcraft
-- Entwickelt von Veni_Vidi_Witti gemeinsam mit Claude (Anthropic).
-- Lizenz: GNU General Public License v2 oder spaeter, siehe LICENSE.
--
-- WoWChatDE - Kern
-- Haengt sich per Chat-Nachrichtenfilter in die Chatkanaele und ergaenzt
-- eine Uebersetzung direkt hinter der Chatzeile (offline, Woerterbuch).
--
-- WoW-Addons haben keinen Netzwerkzugriff. Die Claude-Funktionen laufen
-- deshalb ueber das Begleitprogramm (siehe Companion\ und DATENSCHUTZ.md).

local ADDON, ns = ...

local function meta(field)
    local f = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return f and f(ADDON, field)
end
ns.VERSION = meta("Version") or "?"

-- Andere Dateien haengen hier Funktionen an, die nach dem Laden laufen sollen
ns.onConfigLoaded = {}
ns.onLogin = {}

-- ---------------------------------------------------------------
-- Kanalgruppen
-- ---------------------------------------------------------------
ns.CHANNEL_GROUPS = {
    { key = "say",      label = "Sagen",           events = { "CHAT_MSG_SAY" } },
    { key = "yell",     label = "Rufen",           events = { "CHAT_MSG_YELL" } },
    { key = "emote",    label = "Emotes",          events = { "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" } },
    { key = "party",    label = "Gruppe",          events = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" } },
    { key = "raid",     label = "Schlachtzug",     events = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING" } },
    { key = "instance", label = "Instanz",         events = { "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" } },
    { key = "guild",    label = "Gilde & Offiziere", events = { "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER" } },
    { key = "whisper",  label = "Flüstern",        events = { "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_AFK", "CHAT_MSG_DND" } },
    { key = "channel",  label = "Allgemein, Handel, Suche", events = { "CHAT_MSG_CHANNEL" } },
}
local EVENT_GROUP = {}
for _, g in ipairs(ns.CHANNEL_GROUPS) do
    for _, e in ipairs(g.events) do EVENT_GROUP[e] = g end
end

-- ---------------------------------------------------------------
-- Standardeinstellungen
-- ---------------------------------------------------------------
local defaults = {
    enabled    = true,        -- Offline-Uebersetzung ein/aus
    mode       = "append",    -- "append" = Original + Uebersetzung, "replace" = ersetzen
    minWords   = 1,           -- ab wie vielen erkannten Woertern uebersetzt wird
    skipOwn    = true,        -- eigene Nachrichten nicht uebersetzen
    color      = "ff9ad6ff",  -- Farbe der angehaengten Uebersetzung
    debug      = false,
    offlineDir = "en-de",     -- "en-de" oder "de-en"
    channels   = { say = true, yell = true, emote = true, party = true, raid = true,
                   instance = true, guild = true, whisper = true, channel = true },
    claudeTarget = "Deutsch", -- Zielsprache fuer Claude-Uebersetzungen
    talentGoal   = "Leveln",
    noticeAck    = nil,       -- Version, fuer die der Datenschutz-Hinweis abgeschaltet wurde
    tokensIn     = 0,
    tokensOut    = 0,
    minimapAngle = 200,
    hideMinimap  = false,
}

local PREFIX = "|cff33ff99[Chat DE]|r "
function ns.Print(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg)) end

-- ---------------------------------------------------------------
-- Woerterbuch vorbereiten
-- ---------------------------------------------------------------
local phrases = {}
for _, entry in ipairs(ns.PHRASES) do
    phrases[#phrases + 1] = { entry[1], entry[2] }
end
table.sort(phrases, function(a, b) return #a[1] > #b[1] end)

local words = {}
if ns.BIG then
    for k, v in pairs(ns.BIG) do words[k] = v end
    ns.BIG = nil
end
local curated = {}
for k, v in pairs(ns.WORDS) do words[k] = v; curated[k] = v end
for k, v in pairs(ns.SLANG) do words[k] = v; curated[k] = v end

local german = ns.GERMAN_MARKERS
ns.PHRASES, ns.WORDS, ns.SLANG, ns.GERMAN_MARKERS = nil, nil, nil, nil

-- ---------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------
local sfind, ssub, gsub, lower = string.find, string.sub, string.gsub, string.lower
local concat = table.concat

-- Kleinschreibung inklusive deutscher Umlaute (string.lower kennt nur ASCII)
local function ulower(s)
    s = lower(s)
    s = gsub(s, "\195\132", "\195\164") -- Ä -> ä
    s = gsub(s, "\195\150", "\195\182") -- Ö -> ö
    s = gsub(s, "\195\156", "\195\188") -- Ü -> ü
    return s
end
ns.ulower = ulower

local function isWordChar(c)
    if c == "" or c == nil then return false end
    return c:match("[%w'\128-\255]") ~= nil
end

local function replaceWhole(s, needle, token)
    local out, pos, hits = {}, 1, 0
    while true do
        local a, b = sfind(s, needle, pos, true)
        if not a then break end
        local before = a > 1 and ssub(s, a - 1, a - 1) or " "
        local after  = ssub(s, b + 1, b + 1)
        if not isWordChar(before) and not isWordChar(after) then
            out[#out + 1] = ssub(s, pos, a - 1)
            out[#out + 1] = token
            hits = hits + 1
        else
            out[#out + 1] = ssub(s, pos, b)
        end
        pos = b + 1
    end
    if hits == 0 then return s, 0 end
    out[#out + 1] = ssub(s, pos)
    return concat(out), hits
end

-- WoW-Steuerzeichen (Links, Texturen, Farben) schuetzen
local function protect(text, store)
    local function keep(s)
        store[#store + 1] = s
        return "\002" .. #store .. "\003"
    end
    text = gsub(text, "|T.-|t", keep)
    text = gsub(text, "|H.-|h.-|h", keep)
    text = gsub(text, "|A.-|a", keep)
    text = gsub(text, "|K.-|k", keep)
    text = gsub(text, "|c%x%x%x%x%x%x%x%x", keep)
    text = gsub(text, "|r", keep)
    text = gsub(text, "|n", keep)
    return text
end

local function restore(text, store)
    return (gsub(text, "\002(%d+)\003", function(i) return store[tonumber(i)] or "" end))
end

local function germanScore(lowerText)
    local score = 0
    for w in lowerText:gmatch("[%a\128-\255]+") do
        if german[w] then score = score + 1 end
    end
    if lowerText:find("[\195][\164\182\188\159]") then score = score + 2 end
    return score
end

-- Englische Wortsuche mit einfacher Beugungserkennung
local function lookupEnglish(w)
    local tr = words[w]
    if tr ~= nil then return tr end
    local n = #w
    if n < 4 then return nil end
    local sub = ssub
    if sub(w, -3) == "ies" then
        tr = words[sub(w, 1, n - 3) .. "y"]; if tr ~= nil then return tr end
    end
    if sub(w, -2) == "es" then
        tr = words[sub(w, 1, n - 2)]; if tr ~= nil then return tr end
    end
    if sub(w, -1) == "s" then
        tr = words[sub(w, 1, n - 1)]; if tr ~= nil then return tr end
    end
    if sub(w, -3) == "ing" then
        local stem = sub(w, 1, n - 3)
        tr = words[stem] or words[stem .. "e"]
        if tr == nil and #stem > 2 and sub(stem, -1) == sub(stem, -2, -2) then
            tr = words[sub(stem, 1, #stem - 1)]
        end
        if tr ~= nil then return tr end
    end
    if sub(w, -2) == "ed" then
        local stem = sub(w, 1, n - 2)
        tr = words[stem] or words[sub(w, 1, n - 1)]
        if tr == nil and #stem > 2 and sub(stem, -1) == sub(stem, -2, -2) then
            tr = words[sub(stem, 1, #stem - 1)]
        end
        if tr ~= nil then return tr end
    end
    if sub(w, -2) == "er" and n > 5 then
        tr = words[sub(w, 1, n - 2)]; if tr ~= nil then return tr end
    end
    return nil
end

-- ---------------------------------------------------------------
-- Deutsch -> Englisch: Umkehrung des Woerterbuchs, erst bei Bedarf gebaut
-- ---------------------------------------------------------------
local revWords, revPhrases

local function buildReverse()
    if revWords then return end
    revWords, revPhrases = {}, {}
    -- Grundwortschatz: bei mehreren englischen Woertern gewinnt das kuerzeste
    for en, de in pairs(words) do
        if type(de) == "string" and de ~= "" and not de:find(" ", 1, true) then
            local k = ulower(de)
            local old = revWords[k]
            if not old or #en < #old then revWords[k] = en end
        end
    end
    -- Handgepflegte Eintraege haben Vorrang
    for en, de in pairs(curated) do
        if type(de) == "string" and de ~= "" and not de:find(" ", 1, true) then
            revWords[ulower(de)] = en
        end
    end
    for _, p in ipairs(phrases) do
        local de = ulower(p[2])
        if de:find(" ", 1, true) and not revPhrases[de] then
            revPhrases[#revPhrases + 1] = { de, p[1] }
            revPhrases[de] = true
        end
    end
    table.sort(revPhrases, function(a, b) return #a[1] > #b[1] end)
end

local function lookupGerman(w)
    local tr = revWords[w]
    if tr then return tr end
    -- einfache Endungen: -en, -e, -n, -s, -er
    local n = #w
    if n < 4 then return nil end
    for _, cut in ipairs({ 2, 1 }) do
        tr = revWords[ssub(w, 1, n - cut)]
        if tr then return tr end
    end
    return nil
end

-- ---------------------------------------------------------------
-- Uebersetzung. dir = "en-de" (Standard) oder "de-en"
-- Gibt (text, treffer) zurueck oder nil, wenn nichts zu tun ist.
-- ---------------------------------------------------------------
function ns.Translate(text, dir)
    if not text or text == "" then return nil, 0 end
    dir = dir or (WoWChatDE_Config and WoWChatDE_Config.offlineDir) or "en-de"
    local toEnglish = (dir == "de-en")
    if toEnglish then buildReverse() end

    local store = {}
    local body = protect(text, store)
    local work = ulower(body)
    local gs = germanScore(work)

    local subs, hits = {}, 0
    local function put(replacement)
        subs[#subs + 1] = replacement
        return "\004" .. #subs .. "\005"
    end

    -- 1) Phrasen
    local plist = toEnglish and revPhrases or phrases
    for i = 1, #plist do
        local p = plist[i]
        if sfind(work, p[1], 1, true) then
            local token = put(p[2])
            local n
            work, n = replaceWhole(work, p[1], token)
            if n > 0 then hits = hits + n else subs[#subs] = nil end
        end
    end

    -- 2) Einzelwoerter
    local pattern = toEnglish and "[%a\128-\255][%a'\128-\255]*" or "[%a][%a']*"
    local lookup = toEnglish and lookupGerman or lookupEnglish
    local pieces, pos = {}, 1
    while pos <= #work do
        local a, b = sfind(work, pattern, pos)
        if not a then
            pieces[#pieces + 1] = ssub(work, pos)
            break
        end
        pieces[#pieces + 1] = ssub(work, pos, a - 1)
        local w = ssub(work, a, b)
        local tr = lookup(w)
        if tr == "" then
            -- Fuellwort: ersatzlos streichen
        elseif tr then
            pieces[#pieces + 1] = put(tr)
            hits = hits + 1
        else
            pieces[#pieces + 1] = w
        end
        pos = b + 1
    end
    work = concat(pieces)

    work = gsub(work, "\004(%d+)\005", function(i) return subs[tonumber(i)] or "" end)
    work = gsub(work, "%s%s+", " ")
    work = gsub(work, "^%s+", "")
    work = restore(work, store)

    if toEnglish then
        -- nur Nachrichten anfassen, die nach Deutsch aussehen
        if gs < 1 and hits < 2 then return nil, hits end
    else
        if gs >= 2 and gs >= hits then return nil, hits end
    end
    return work, hits
end

-- ---------------------------------------------------------------
-- Puffer der letzten Chatzeilen (fuer "Mit Claude uebersetzen").
-- Nur Text, Kanal und Uhrzeit - KEINE Absendernamen. Nicht gespeichert.
-- ---------------------------------------------------------------
ns.recent = {}
local RECENT_MAX = 30
local seenLines = {}

local function remember(event, msg, lineID, channelBase)
    local key = lineID or msg
    if seenLines[key] then return end
    seenLines[key] = true
    local g = EVENT_GROUP[event]
    local label = g and g.label or "Chat"
    if event == "CHAT_MSG_CHANNEL" and type(channelBase) == "string" and channelBase ~= "" then
        label = channelBase
    end
    table.insert(ns.recent, 1, { text = msg, channel = label, time = time() })
    while #ns.recent > RECENT_MAX do
        local old = table.remove(ns.recent)
        if old then seenLines[old.lineKey or ""] = nil end
    end
    ns.recent[1].lineKey = key
    if ns.OnRecentChanged then ns.OnRecentChanged() end
end

-- ---------------------------------------------------------------
-- Der Chatfilter
-- ---------------------------------------------------------------
local myName
local errorShown = false
local cache = {}   -- lineID -> fertige Zeile (Chat zeigt dieselbe Nachricht in mehreren Fenstern)
local cacheCount = 0

local function Debug(fmt, ...)
    if WoWChatDE_Config and WoWChatDE_Config.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[Chat DE ?]|r " .. string.format(fmt, ...))
    end
end

local function Filter(self, event, msg, author, ...)
    local cfg = WoWChatDE_Config
    if not cfg then return false end
    if type(msg) ~= "string" or msg == "" then return false end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(author)) then return false end

    local lineID = select(9, ...)
    if type(lineID) ~= "number" then lineID = nil end

    local own = false
    if myName and type(author) == "string" then
        own = (author:match("^[^%-]+") == myName)
    end
    if not own and event ~= "CHAT_MSG_WHISPER_INFORM" and event ~= "CHAT_MSG_BN_WHISPER_INFORM" then
        remember(event, msg, lineID, select(7, ...))
    end

    if not cfg.enabled then return false end
    local g = EVENT_GROUP[event]
    if g and cfg.channels and cfg.channels[g.key] == false then return false end
    if own and cfg.skipOwn then Debug("%s: eigene Nachricht", event); return false end

    if lineID and cache[lineID] ~= nil then
        local c = cache[lineID]
        if c == false then return false end
        return false, c, author, ...
    end

    local ok, translated, hits = pcall(ns.Translate, msg, cfg.offlineDir)
    if not ok then
        if not errorShown then
            errorShown = true
            ns.Print("|cffff5555Fehler beim Übersetzen:|r " .. tostring(translated))
        end
        return false
    end
    hits = hits or 0
    Debug("%s | \"%s\" -> \"%s\" (%d Treffer)", event, msg, tostring(translated), hits)

    local result = false
    if translated and hits >= (cfg.minWords or 1) and ulower(translated) ~= ulower(msg) then
        if cfg.mode == "replace" then
            result = translated
        else
            result = msg .. "  |c" .. (cfg.color or "ff9ad6ff") .. "\194\187 " .. translated .. "|r"
        end
    end
    if lineID then
        cacheCount = cacheCount + 1
        if cacheCount > 400 then wipe(cache); cacheCount = 0 end
        cache[lineID] = result
    end
    if not result then return false end
    return false, result, author, ...
end

local function eventFilterAPI()
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        return ChatFrameUtil.AddMessageEventFilter, ChatFrameUtil.RemoveMessageEventFilter
    end
    return ChatFrame_AddMessageEventFilter, ChatFrame_RemoveMessageEventFilter
end

local function ApplyFilters()
    local add, remove = eventFilterAPI()
    if not add then
        ns.Print("|cffff5555Chatfilter nicht verfügbar - Übersetzung im Chat ist aus.|r")
        return
    end
    for e in pairs(EVENT_GROUP) do
        if remove then remove(e, Filter) end
        add(e, Filter)
    end
end

function ns.ClearCache() wipe(cache); cacheCount = 0 end

-- ---------------------------------------------------------------
-- Laden
-- ---------------------------------------------------------------
local function FillDefaults(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            FillDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            WoWChatDE_Config = WoWChatDE_Config or {}
            FillDefaults(WoWChatDE_Config, defaults)
            for _, fn in ipairs(ns.onConfigLoaded) do fn() end
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        local n = UnitName("player")
        if not (issecretvalue and issecretvalue(n)) then myName = n end
        ApplyFilters()
        for _, fn in ipairs(ns.onLogin) do fn() end
        ns.Print("aktiv - Einstellungen mit |cffffff00/chatde|r, Claude-Hilfe mit |cffffff00/chatde hilfe|r")
    end
end)

-- ---------------------------------------------------------------
-- Slash-Befehle
-- ---------------------------------------------------------------
SLASH_WOWCHATDE1 = "/chatde"
SLASH_WOWCHATDE2 = "/chatdeutsch"
SlashCmdList["WOWCHATDE"] = function(input)
    local cfg = WoWChatDE_Config
    local cmd, rest = (input or ""):lower():match("^(%S*)%s*(.-)$")

    if cmd == "" or cmd == "einstellungen" or cmd == "config" then
        if ns.OpenSettings then ns.OpenSettings() end

    elseif cmd == "hilfe" or cmd == "claude" or cmd == "help" then
        if ns.OpenAssistant then ns.OpenAssistant() end

    elseif cmd == "on" or cmd == "an" then
        cfg.enabled = true; ns.ClearCache(); ns.Print("eingeschaltet.")

    elseif cmd == "off" or cmd == "aus" then
        cfg.enabled = false; ns.ClearCache(); ns.Print("ausgeschaltet.")

    elseif cmd == "mode" or cmd == "modus" then
        cfg.mode = (rest == "replace" or rest == "ersetzen") and "replace" or "append"
        ns.ClearCache()
        ns.Print(cfg.mode == "replace" and "zeigt nur noch die Übersetzung." or "zeigt Original + Übersetzung.")

    elseif cmd == "min" then
        local n = tonumber(rest)
        if n then cfg.minWords = n; ns.ClearCache(); ns.Print("übersetzt ab " .. n .. " erkannten Wörtern.")
        else ns.Print("Zahl angeben, zum Beispiel |cffffff00/chatde min 2|r") end

    elseif cmd == "own" or cmd == "eigene" then
        cfg.skipOwn = not cfg.skipOwn
        ns.ClearCache()
        ns.Print("eigene Nachrichten übersetzen: " .. (cfg.skipOwn and "nein" or "ja"))

    elseif cmd == "test" then
        local text = rest ~= "" and rest or "lfm 1 healer for scholo, need heals, pst for inv ty"
        local tr = ns.Translate(text)
        ns.Print("Test: " .. text)
        ns.Print("  |cff9ad6ff\194\187 " .. (tr or "(keine Übersetzung)") .. "|r")

    elseif cmd == "debug" then
        cfg.debug = not cfg.debug
        ns.Print("Fehlersuche: " .. (cfg.debug and "an - jede Nachricht wird kommentiert" or "aus"))

    elseif cmd == "pruefen" or cmd == "prüfen" or cmd == "check" then
        local nWords = 0
        for _ in pairs(words) do nWords = nWords + 1 end
        local add = eventFilterAPI()
        ns.Print("|cffffff00Selbsttest|r")
        ns.Print(("  an=%s  modus=%s  ab=%s Wörtern  richtung=%s"):format(
            tostring(cfg.enabled), tostring(cfg.mode), tostring(cfg.minWords), tostring(cfg.offlineDir)))
        ns.Print(("  Wörterbuch: %d Wörter, %d Phrasen"):format(nWords, #phrases))
        ns.Print("  Chatfilter verfügbar: " .. tostring(add ~= nil))
        local ok, tr, hits = pcall(ns.Translate, "Hello", "en-de")
        ns.Print(("  Test 'Hello': ok=%s ergebnis=%s treffer=%s"):format(tostring(ok), tostring(tr), tostring(hits)))
        local ok2, _, out = pcall(Filter, nil, "CHAT_MSG_CHANNEL", "hello, i need heals fast", "Testspieler")
        ns.Print(("  Chatzeile: ok=%s -> %s"):format(tostring(ok2), tostring(out)))

    elseif cmd == "info" or cmd == "about" or cmd == "credits" then
        ns.Print("|cffffff00Chat DE|r " .. ns.VERSION)
        ns.Print("  Entwickelt von |cffffd479Veni_Vidi_Witti|r gemeinsam mit |cff33ff99Claude|r von |cff33ff99Anthropic|r.")
        ns.Print("  Wortschatz: Ding-Wörterbuch der TU Chemnitz, Frank Richter, GPL v2.")
        ns.Print("  Lizenz: GNU General Public License v2 oder später.")

    elseif cmd == "status" then
        ns.Print(("Status: %s | Anzeige: %s | ab %d Wörtern | eigene: %s | Richtung: %s"):format(
            cfg.enabled and "an" or "aus",
            cfg.mode == "replace" and "nur Übersetzung" or "Original + Übersetzung",
            cfg.minWords or 1, cfg.skipOwn and "aus" or "an",
            cfg.offlineDir == "de-en" and "Deutsch → Englisch" or "Englisch → Deutsch"))

    elseif cmd == "minimap" then
        cfg.hideMinimap = not cfg.hideMinimap
        if ns.minimap then ns.minimap:SetShown(not cfg.hideMinimap) end
        ns.Print(cfg.hideMinimap and "Minikarten-Knopf ausgeblendet." or "Minikarten-Knopf eingeblendet.")

    else
        ns.Print("Befehle:")
        ns.Print("  |cffffff00/chatde|r - Einstellungen öffnen")
        ns.Print("  |cffffff00/chatde hilfe|r - Claude-Hilfe (Übersetzen, Quests, Talente)")
        ns.Print("  |cffffff00/chatde an||aus|r - Übersetzung ein-/ausschalten")
        ns.Print("  |cffffff00/chatde modus append||ersetzen|r - anhängen oder ersetzen")
        ns.Print("  |cffffff00/chatde test <text>|r - Übersetzung ausprobieren")
        ns.Print("  |cffffff00/chatde pruefen|r - Selbsttest")
        ns.Print("  |cffffff00/chatde status|r - aktuelle Einstellungen")
        ns.Print("  |cffffff00/chatde minimap|r - Minikarten-Knopf ein/aus")
        ns.Print("  |cffffff00/chatde info|r - wer das gemacht hat")
    end
end
