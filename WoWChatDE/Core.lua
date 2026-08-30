-- Chat DE fuer World of Warcraft
-- Entwickelt von Veni_Vidi_Witti gemeinsam mit Claude (Anthropic).
-- Lizenz: GNU General Public License v2 oder spaeter, siehe LICENSE.
--
-- WoWChatDE - Kern
-- Hängt sich per ChatFrame_AddMessageEventFilter in alle Chatkanäle
-- und ergänzt eine deutsche Übersetzung direkt hinter der Chatzeile.
--
-- WoW-Addons haben keinen Netzwerkzugriff - die Lua-Sandbox von Blizzard kennt
-- weder Sockets noch Dateizugriff. Übersetzt wird deshalb ausschließlich aus
-- dem mitgelieferten Wörterbuch, Wort für Wort und Wendung für Wendung.

local ADDON, ns = ...

-- ---------------------------------------------------------------
-- Standardeinstellungen
-- ---------------------------------------------------------------
local defaults = {
    enabled  = true,       -- Übersetzung ein/aus
    mode     = "append",   -- "append" = Original + Übersetzung, "replace" = ersetzen
    minWords = 1,          -- ab wie vielen erkannten Wörtern übersetzt wird
    skipOwn  = true,       -- eigene Nachrichten nicht übersetzen
    color    = "ff9ad6ff", -- Farbe der angehängten Übersetzung
    debug    = false,      -- ausführliche Meldungen zur Fehlersuche
}

local PREFIX = "|cff33ff99[Chat DE]|r "

-- ---------------------------------------------------------------
-- Wörterbuch vorbereiten
-- ---------------------------------------------------------------
local phrases = {}
do
    for _, entry in ipairs(ns.PHRASES) do
        phrases[#phrases + 1] = { entry[1], entry[2] }
    end
    -- längste Phrasen zuerst, damit "looking for group" vor "looking for" greift
    table.sort(phrases, function(a, b) return #a[1] > #b[1] end)
end

-- Reihenfolge = Rangfolge: der Grundwortschatz bildet die Grundlage,
-- die kuratierte Liste und der WoW-Slang ueberschreiben ihn.
local words = {}
if ns.BIG then
    for k, v in pairs(ns.BIG) do words[k] = v end
    ns.BIG = nil                       -- Speicher wieder freigeben
end
for k, v in pairs(ns.WORDS) do words[k] = v end
for k, v in pairs(ns.SLANG) do words[k] = v end

local german = ns.GERMAN_MARKERS

-- Die Quelltabellen werden nach dem Zusammenbau nicht mehr gebraucht.
-- Freigeben spart rund die Haelfte des Speichers.
ns.PHRASES, ns.WORDS, ns.SLANG, ns.GERMAN_MARKERS = nil, nil, nil, nil

-- ---------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------
local sfind, ssub, gsub, lower = string.find, string.sub, string.gsub, string.lower
local concat = table.concat

-- Buchstabe? (inkl. Apostroph, damit "don't" nicht mitten drin getroffen wird)
local function isWordChar(c)
    if c == "" or c == nil then return false end
    return c:match("[%w']") ~= nil
end

-- Ersetzt alle Vorkommen von needle (nur als ganzes Wort) durch einen Platzhalter
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

-- WoW-Steuerzeichen (Links, Texturen, Farben) aus dem Text nehmen,
-- damit sie nicht zerstört werden. Sie kommen unverändert zurück.
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

-- Zählt deutsche Marker, um schon deutsche Nachrichten in Ruhe zu lassen
local function germanScore(lowerText)
    local score = 0
    for w in lowerText:gmatch("[%a]+") do
        if german[w] then score = score + 1 end
    end
    -- Umlaute und ss sind starke Hinweise
    if lowerText:find("[\195][\164\182\188\159]") then score = score + 2 end
    return score
end

-- ---------------------------------------------------------------
-- Wortsuche mit einfacher Beugungserkennung.
-- Das Woerterbuch kennt Grundformen; im Chat stehen "potions",
-- "selling", "hits". Findet die direkte Suche nichts, probieren wir
-- die gaengigen englischen Endungen ab.
-- ---------------------------------------------------------------
local function lookupWord(w)
    local tr = words[w]
    if tr ~= nil then return tr end

    local n = #w
    if n < 4 then return nil end
    local sub = string.sub

    if sub(w, -3) == "ies" then                      -- bodies -> body
        tr = words[sub(w, 1, n - 3) .. "y"]
        if tr ~= nil then return tr end
    end
    if sub(w, -2) == "es" then                       -- boxes -> box
        tr = words[sub(w, 1, n - 2)]
        if tr ~= nil then return tr end
    end
    if sub(w, -1) == "s" then                        -- potions -> potion
        tr = words[sub(w, 1, n - 1)]
        if tr ~= nil then return tr end
    end
    if sub(w, -3) == "ing" then                      -- selling -> sell
        local stem = sub(w, 1, n - 3)
        tr = words[stem] or words[stem .. "e"]       -- casting / making
        if tr == nil and #stem > 2 and sub(stem, -1) == sub(stem, -2, -2) then
            tr = words[sub(stem, 1, #stem - 1)]      -- running -> run
        end
        if tr ~= nil then return tr end
    end
    if sub(w, -2) == "ed" then                       -- pulled -> pull
        local stem = sub(w, 1, n - 2)
        tr = words[stem] or words[sub(w, 1, n - 1)]  -- moved -> move
        if tr == nil and #stem > 2 and sub(stem, -1) == sub(stem, -2, -2) then
            tr = words[sub(stem, 1, #stem - 1)]      -- stopped -> stop
        end
        if tr ~= nil then return tr end
    end
    if sub(w, -2) == "er" and n > 5 then             -- faster -> fast
        tr = words[sub(w, 1, n - 2)]
        if tr ~= nil then return tr end
    end
    return nil
end

-- ---------------------------------------------------------------
-- Übersetzung
-- ---------------------------------------------------------------
function ns.Translate(text)
    if not text or text == "" then return nil, 0 end

    local store = {}
    local body = protect(text, store)

    local work = lower(body)
    local gs = germanScore(work)

    local subs = {}
    local hits = 0

    local function put(replacement)
        subs[#subs + 1] = replacement
        return "\004" .. #subs .. "\005"
    end

    -- 1) Phrasen
    for i = 1, #phrases do
        local p = phrases[i]
        if sfind(work, p[1], 1, true) then
            local token = put(p[2])
            local n
            work, n = replaceWhole(work, p[1], token)
            if n > 0 then
                hits = hits + n
            else
                subs[#subs] = nil   -- Token doch nicht gebraucht
            end
        end
    end

    -- 2) Einzelwörter
    local pieces, pos = {}, 1
    while pos <= #work do
        local a, b = sfind(work, "[%a][%a']*", pos)
        if not a then
            pieces[#pieces + 1] = ssub(work, pos)
            break
        end
        pieces[#pieces + 1] = ssub(work, pos, a - 1)
        local w = ssub(work, a, b)
        local tr = lookupWord(w)
        if tr == "" then
            -- Artikel/Füllwort: ersatzlos streichen, zählt nicht als Treffer
        elseif tr then
            pieces[#pieces + 1] = put(tr)
            hits = hits + 1
        else
            pieces[#pieces + 1] = w
        end
        pos = b + 1
    end
    work = concat(pieces)

    -- Platzhalter zurückschreiben
    work = gsub(work, "\004(%d+)\005", function(i) return subs[tonumber(i)] or "" end)
    work = gsub(work, "%s%s+", " ")          -- doppelte Leerzeichen von gestrichenen Artikeln
    work = gsub(work, "^%s+", "")
    work = restore(work, store)

    -- schon deutsch? Dann lieber nichts tun.
    if gs >= 2 and gs >= hits then return nil, hits end

    return work, hits
end

-- ---------------------------------------------------------------
-- Kanäle, in denen übersetzt wird
-- ---------------------------------------------------------------
local EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_AFK", "CHAT_MSG_DND",
}

local myName
local errorShown = false

local function Debug(fmt, ...)
    if WoWChatDE_Config and WoWChatDE_Config.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[Chat DE ?]|r " .. string.format(fmt, ...))
    end
end

-- ---------------------------------------------------------------
-- Der Chatfilter: hängt die Übersetzung hinter die Nachricht
-- ---------------------------------------------------------------
local function Filter(self, event, msg, author, ...)
    local cfg = WoWChatDE_Config
    if not cfg then return false end
    if not cfg.enabled then return false end
    if not msg or msg == "" then return false end

    if cfg.skipOwn and myName then
        local short = author and author:match("^[^%-]+") or nil
        if short == myName then Debug("%s: eigene Nachricht", event); return false end
    end

    local ok, translated, hits = pcall(ns.Translate, msg)
    if not ok then
        -- WoW blendet Lua-Fehler standardmäßig aus; diesen zeigen wir,
        -- sonst scheitert die Übersetzung stumm.
        if not errorShown then
            errorShown = true
            DEFAULT_CHAT_FRAME:AddMessage(PREFIX
                .. "|cffff5555Fehler beim Übersetzen:|r " .. tostring(translated))
        end
        return false
    end

    hits = hits or 0
    Debug("%s | %s | \"%s\" -> \"%s\" (%d Treffer)", event, tostring(author),
          msg, tostring(translated), hits)

    if not translated then return false end
    if hits < (cfg.minWords or 1) then
        Debug("  zu wenige Treffer (%d < %d)", hits, cfg.minWords or 1); return false
    end
    if lower(translated) == lower(msg) then
        Debug("  Übersetzung gleich dem Original"); return false
    end

    if cfg.mode == "replace" then
        return false, translated, author, ...
    end
    return false, msg .. "  |c" .. (cfg.color or "ff9ad6ff") .. "\194\187 " .. translated .. "|r",
           author, ...
end

-- ---------------------------------------------------------------
-- Laden
-- ---------------------------------------------------------------
local function ApplyFilters()
    for _, e in ipairs(EVENTS) do
        ChatFrame_RemoveMessageEventFilter(e, Filter)
        ChatFrame_AddMessageEventFilter(e, Filter)
    end
end

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end

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
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        myName = UnitName("player")
        ApplyFilters()
        Print("aktiv - von |cffffd479Veni_Vidi_Witti|r und |cff33ff99Claude|r. Hilfe mit |cffffff00/chatde|r")
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

    if cmd == "on" or cmd == "an" then
        cfg.enabled = true;  Print("eingeschaltet.")

    elseif cmd == "off" or cmd == "aus" then
        cfg.enabled = false; Print("ausgeschaltet.")

    elseif cmd == "mode" or cmd == "modus" then
        if rest == "replace" or rest == "ersetzen" then
            cfg.mode = "replace"; Print("zeigt nur noch die Übersetzung.")
        else
            cfg.mode = "append";  Print("zeigt Original + Übersetzung.")
        end

    elseif cmd == "min" then
        local n = tonumber(rest)
        if n then cfg.minWords = n; Print("übersetzt ab " .. n .. " erkannten Wörtern.")
        else Print("Zahl angeben, zum Beispiel |cffffff00/chatde min 2|r") end

    elseif cmd == "own" or cmd == "eigene" then
        cfg.skipOwn = not cfg.skipOwn
        Print("eigene Nachrichten übersetzen: " .. (cfg.skipOwn and "nein" or "ja"))

    elseif cmd == "test" then
        local text = rest ~= "" and rest or "lfm 1 healer for scholo, need heals, pst for inv ty"
        local tr = ns.Translate(text)
        Print("Test: " .. text)
        Print("  |cff9ad6ff\194\187 " .. (tr or "(keine Übersetzung)") .. "|r")

    elseif cmd == "debug" then
        cfg.debug = not cfg.debug
        Print("Fehlersuche: " .. (cfg.debug and "an - jede Nachricht wird kommentiert" or "aus"))

    elseif cmd == "pruefen" or cmd == "prüfen" or cmd == "check" then
        local nWords = 0
        for _ in pairs(words) do nWords = nWords + 1 end
        Print("|cffffff00Selbsttest|r")
        Print(("  an=%s  modus=%s  ab=%s Woertern  eigene aus=%s")
              :format(tostring(cfg.enabled), tostring(cfg.mode),
                      tostring(cfg.minWords), tostring(cfg.skipOwn)))
        Print(("  Woerterbuch: %d Woerter, %d Phrasen"):format(nWords, #phrases))
        Print(("  Kanaele gefiltert: %d"):format(#EVENTS))
        Print("  ns.Translate ist ein " .. type(ns.Translate))
        local ok, tr, hits = pcall(ns.Translate, "Hello")
        Print(("  Test 'Hello': ok=%s ergebnis=%s treffer=%s")
              :format(tostring(ok), tostring(tr), tostring(hits)))
        local probe = "hello, i need heals fast"
        local ok2, _, out = pcall(Filter, nil, "CHAT_MSG_CHANNEL", probe, "Testspieler")
        Print(("  Chatzeile: ok=%s -> %s"):format(tostring(ok2), tostring(out)))
        if ok2 and not out then
            Print("    (nichts angehaengt - pruefe |cffffff00/chatde an|r und |cffffff00/chatde min 1|r)")
        end
        Print("  eigener Name: " .. tostring(myName))

    elseif cmd == "info" or cmd == "about" or cmd == "credits" then
        -- Seit Patch 11.0 liegt die Funktion unter C_AddOns; der globale
        -- Name gilt als veraltet. Beide Wege abdecken.
        local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
        local version = meta and meta(ADDON, "Version") or "?"
        Print("|cffffff00Chat DE|r " .. version)
        Print("  Entwickelt von |cffffd479Veni_Vidi_Witti|r gemeinsam mit")
        Print("  |cff33ff99Claude|r von |cff33ff99Anthropic|r.")
        Print("  Wortschatz: Ding-Woerterbuch der TU Chemnitz, Frank Richter, GPL v2.")
        Print("  Lizenz: GNU General Public License v2 oder spaeter.")

    elseif cmd == "status" then
        Print(("Status: %s | Anzeige: %s | ab %d Wörtern | eigene: %s")
            :format(cfg.enabled and "an" or "aus",
                    cfg.mode == "replace" and "nur Übersetzung" or "Original + Übersetzung",
                    cfg.minWords or 1, cfg.skipOwn and "aus" or "an"))

    else
        Print("Befehle:")
        Print("  |cffffff00/chatde an|aus|r - Übersetzung ein-/ausschalten")
        Print("  |cffffff00/chatde modus append|ersetzen|r - anhängen oder ersetzen")
        Print("  |cffffff00/chatde min <zahl>|r - ab wie vielen erkannten Wörtern")
        Print("  |cffffff00/chatde eigene|r - eigene Nachrichten mitübersetzen")
        Print("  |cffffff00/chatde test <text>|r - Übersetzung ausprobieren")
        Print("  |cffffff00/chatde pruefen|r - Selbsttest, zeigt wo es klemmt")
        Print("  |cffffff00/chatde debug|r - jede Nachricht kommentieren")
        Print("  |cffffff00/chatde status|r - aktuelle Einstellungen")
        Print("  |cffffff00/chatde info|r - wer das gemacht hat")
    end
end
