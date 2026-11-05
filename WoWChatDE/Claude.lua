-- Chat DE - Claude-Anfragen: Postausgang, Posteingang, Datensammlung
-- Lizenz: GNU General Public License v2 oder spaeter, siehe LICENSE.
--
-- Ablauf (wie beim WeakAuras Companion):
--  1. Das Addon legt eine Anfrage in WoWChatDE_Outbox ab (gespeicherte Daten).
--  2. /reload - WoW schreibt die gespeicherten Daten auf die Festplatte.
--  3. Das Begleitprogramm liest die Anfrage, fragt Claude und schreibt Inbox.lua.
--  4. /reload - das Addon liest Inbox.lua und zeigt die Antwort an.
--
-- Datenschutz: Es werden NIE Charaktername, Realm, Konto, BattleTag, Gilde,
-- Freunde, Chat-Absender oder die Position uebertragen. Siehe DATENSCHUTZ.md.

local ADDON, ns = ...

ns.SCHEMA = 1
ns.HISTORY_MAX = 30
ns.newAnswers = 0

ns.LANGUAGES = { "Deutsch", "Englisch", "Französisch", "Spanisch", "Italienisch",
                 "Portugiesisch", "Russisch", "Polnisch", "Niederländisch", "Türkisch" }

local function safe(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function outbox()
    WoWChatDE_Outbox = WoWChatDE_Outbox or {}
    WoWChatDE_Outbox.schema = ns.SCHEMA
    WoWChatDE_Outbox.requests = WoWChatDE_Outbox.requests or {}
    return WoWChatDE_Outbox
end

local function history()
    WoWChatDE_History = WoWChatDE_History or {}
    return WoWChatDE_History
end
ns.GetHistory = history

function ns.PendingCount()
    local n = 0
    for _ in pairs(outbox().requests) do n = n + 1 end
    return n
end

function ns.CompanionLastSeen()
    local inbox = WoWChatDE_Inbox
    local t = inbox and tonumber(inbox.written) or 0
    if t <= 0 then return nil end
    return t
end

-- Antworten aus Inbox.lua uebernehmen (nach jedem /reload)
local function processInbox()
    local inbox = WoWChatDE_Inbox
    if type(inbox) ~= "table" or type(inbox.answers) ~= "table" then return end
    local box, hist, cfg = outbox(), history(), WoWChatDE_Config
    local known = {}
    for _, h in ipairs(hist) do known[h.id] = true end
    for id, ans in pairs(inbox.answers) do
        local req = box.requests[id]
        if req and not known[id] and type(ans) == "table" then
            table.insert(hist, 1, {
                id = id,
                kind = req.kind,
                title = req.title,
                asked = req.created,
                answered = tonumber(ans.time) or time(),
                text = tostring(ans.text or ""),
                error = ans.error and tostring(ans.error) or nil,
                tokensIn = tonumber(ans.tokensIn) or 0,
                tokensOut = tonumber(ans.tokensOut) or 0,
                model = ans.model and tostring(ans.model) or nil,
            })
            cfg.tokensIn = (cfg.tokensIn or 0) + (tonumber(ans.tokensIn) or 0)
            cfg.tokensOut = (cfg.tokensOut or 0) + (tonumber(ans.tokensOut) or 0)
            cfg.lastTokensIn = tonumber(ans.tokensIn) or 0
            cfg.lastTokensOut = tonumber(ans.tokensOut) or 0
            box.requests[id] = nil
            ns.newAnswers = ns.newAnswers + 1
        elseif req and known[id] then
            box.requests[id] = nil
        end
    end
    while #hist > ns.HISTORY_MAX do table.remove(hist) end
end

table.insert(ns.onConfigLoaded, processInbox)

table.insert(ns.onLogin, function()
    if ns.newAnswers > 0 then
        ns.Print(("|cff33ff99%d neue Antwort(en) von Claude.|r"):format(ns.newAnswers))
        if ns.OpenAssistant then
            C_Timer.After(1, function() ns.OpenAssistant("answers") end)
        end
    elseif ns.PendingCount() > 0 then
        ns.Print("Eine Claude-Anfrage wartet noch. Sobald das Begleitprogramm 'Antwort bereit' meldet: |cffffff00/chatde hilfe|r -> 'Antwort laden'.")
    end
end)

-- Neu laden (nur durch Klick des Spielers)
function ns.Reload()
    if InCombatLockdown() then
        ns.Print("Im Kampf wird nicht neu geladen. Bitte nach dem Kampf noch einmal klicken.")
        return false
    end
    ReloadUI()
    return true
end

-- Falls WoW das Neuladen aus Addon-Code blockiert: klar sagen, was zu tun ist
local blocked = CreateFrame("Frame")
blocked:RegisterEvent("ADDON_ACTION_BLOCKED")
blocked:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blocked:SetScript("OnEvent", function(_, _, who, what)
    if who == ADDON and type(what) == "string" and what:find("ReloadUI") then
        ns.Print("|cffffd24dWoW hat das automatische Neuladen blockiert.|r Deine Anfrage ist gespeichert - bitte einmal |cffffff00/reload|r eingeben.")
    end
end)

-- Gleiche Anfrage schon unterwegs? Dann nicht noch einmal senden (kostet sonst doppelt Tokens).
local function findDuplicate(req)
    for id, r in pairs(outbox().requests) do
        if r.kind == req.kind and r.title == req.title and (r.question or "") == (req.question or "") then
            if req.kind ~= "translate" then return id end
            local a, b = r.lines or {}, req.lines or {}
            if #a == #b then
                local same = true
                for i = 1, #a do if a[i] ~= b[i] then same = false; break end end
                if same then return id end
            end
        end
    end
end

-- Anfrage ablegen und neu laden. summary: Liste von Zeilen fuer den Hinweis.
local counter = 0
function ns.SendRequest(req, summary)
    if InCombatLockdown() then
        ns.Print("Im Kampf geht das nicht. Bitte nach dem Kampf noch einmal versuchen.")
        return
    end
    if findDuplicate(req) then
        ns.Print("Diese Anfrage ist schon unterwegs und wird nicht doppelt gesendet. Warte auf 'Antwort bereit' und klicke dann auf 'Antwort laden'.")
        if ns.OpenAssistant then ns.OpenAssistant() end
        return
    end
    ns.ConfirmTransfer(summary, function()
        if findDuplicate(req) then return end
        counter = counter + 1
        req.id = ("%d-%d-%d"):format(time(), math.random(1000, 9999), counter)
        req.created = time()
        req.addonVersion = ns.VERSION
        outbox().requests[req.id] = req
    end)
end

function ns.CancelPending()
    wipe(outbox().requests)
end

-- ---------------------------------------------------------------
-- Daten einsammeln
-- ---------------------------------------------------------------
local function playerInfo()
    local className = safe(UnitClass("player"))
    local level = safe(UnitLevel("player"))
    local p = { class = className, level = level }
    if GetSpecialization and GetSpecializationInfo then
        local ok, idx = pcall(GetSpecialization)
        if ok and idx then
            local ok2, _, specName, _, _, role = pcall(GetSpecializationInfo, idx)
            if ok2 then p.spec = safe(specName); p.role = safe(role) end
        end
    end
    return p
end
ns.PlayerInfo = playerInfo

-- Liste der Quests im Questlog
function ns.ListQuests()
    local list = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return list end
    local header
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                header = info.title
            elseif not info.isHidden and info.questID and info.questID > 0 then
                list[#list + 1] = {
                    questID = info.questID,
                    title = info.title or "?",
                    header = header,
                    level = info.level,
                    complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID) or false,
                }
            end
        end
    end
    return list
end

local function clip(s, n)
    s = tostring(s or "")
    if #s > n then return ns.Utf8Sub(s, n) .. " ..." end
    return s
end

-- Questtexte enthalten oft den Charakternamen ("Seid gegruesst, <Name>").
-- Der Name wird vor dem Senden durch einen Platzhalter ersetzt.
local function anonymize(s)
    if type(s) ~= "string" or s == "" then return s end
    local name = safe(UnitName("player"))
    if type(name) == "string" and name ~= "" then
        local pat = name:gsub("(%W)", "%%%1")
        s = s:gsub(pat, "[Spielername]")
    end
    return s
end

-- Alle Angaben zu einer Quest (Titel, Beschreibung, Ziele)
function ns.CollectQuest(entry)
    local q = ns.CollectQuestRaw(entry)
    q.title = anonymize(q.title)
    q.description = anonymize(q.description)
    q.summary = anonymize(q.summary)
    for i, o in ipairs(q.objectives) do q.objectives[i] = anonymize(o) end
    return q
end

function ns.CollectQuestRaw(entry)
    local q = {
        title = entry.title,
        header = entry.header,
        level = entry.level,
        complete = entry.complete and true or false,
        objectives = {},
    }
    local id = entry.questID
    if C_QuestLog.SetSelectedQuest and GetQuestLogQuestText then
        local prev = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
        C_QuestLog.SetSelectedQuest(id)
        local ok, desc, objText = pcall(GetQuestLogQuestText)
        if ok then
            q.description = clip(desc, 1500)
            q.summary = clip(objText, 500)
        end
        if prev and prev ~= id then C_QuestLog.SetSelectedQuest(prev) end
    end
    if C_QuestLog.GetQuestObjectives then
        local objs = C_QuestLog.GetQuestObjectives(id)
        if type(objs) == "table" then
            for _, o in ipairs(objs) do
                if o.text and o.text ~= "" then
                    q.objectives[#q.objectives + 1] = o.text .. (o.finished and " (erledigt)" or "")
                end
            end
        end
    end
    return q
end

-- Talente: moderner Talentbaum (C_ClassTalents/C_Traits) oder klassische Talente
local function spellNameForEntry(configID, entryID)
    local e = C_Traits.GetEntryInfo(configID, entryID)
    if not e or not e.definitionID then return nil end
    local d = C_Traits.GetDefinitionInfo(e.definitionID)
    if not d then return nil end
    if d.overrideName and d.overrideName ~= "" then return d.overrideName end
    local sid = d.spellID or d.overriddenSpellID
    if sid and C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(sid) end
    return nil
end

local function collectModernTalents(t)
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return false end
    local cinfo = C_Traits.GetConfigInfo(configID)
    if not cinfo or not cinfo.treeIDs then return false end
    t.system = "Talentbaum"
    for _, treeID in ipairs(cinfo.treeIDs) do
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
            local n = C_Traits.GetNodeInfo(configID, nodeID)
            if n and n.ID and n.ID ~= 0 and (n.isVisible ~= false) then
                local rank = n.activeRank or n.currentRank or 0
                local maxR = n.maxRanks or 1
                if rank > 0 and n.activeEntry and n.activeEntry.entryID then
                    local name = spellNameForEntry(configID, n.activeEntry.entryID)
                    if name then t.chosen[#t.chosen + 1] = ("%s (%d/%d)"):format(name, rank, maxR) end
                elseif #t.available < 80 then
                    local names = {}
                    for _, eid in ipairs(n.entryIDs or {}) do
                        local name = spellNameForEntry(configID, eid)
                        if name then names[#names + 1] = name end
                    end
                    if #names > 0 then
                        t.available[#t.available + 1] = table.concat(names, " oder ") .. (" (0/%d)"):format(maxR)
                    end
                end
            end
        end
    end
    if C_ClassTalents.HasUnspentTalentPoints then
        local _, numClass, numSpec = C_ClassTalents.HasUnspentTalentPoints()
        t.unspent = ("Klasse: %s, Spezialisierung: %s"):format(tostring(numClass or 0), tostring(numSpec or 0))
    end
    return #t.chosen + #t.available > 0
end

local function collectClassicTalents(t)
    if not (GetNumTalentTabs and GetTalentInfo and GetNumTalents) then return false end
    t.system = "klassische Talente"
    for tab = 1, GetNumTalentTabs() do
        local tabName = GetTalentTabInfo and select(1, GetTalentTabInfo(tab)) or ("Baum " .. tab)
        for i = 1, GetNumTalents(tab) do
            local name, _, tier, _, rank, maxRank = GetTalentInfo(tab, i)
            if name then
                local line = ("%s: %s (%d/%d, Reihe %d)"):format(tostring(tabName), name, rank or 0, maxRank or 0, tier or 0)
                if (rank or 0) > 0 then t.chosen[#t.chosen + 1] = line
                elseif #t.available < 80 then t.available[#t.available + 1] = line end
            end
        end
    end
    if UnitCharacterPoints then t.unspent = tostring(UnitCharacterPoints("player") or 0) end
    return true
end

function ns.CollectTalents()
    local t = { chosen = {}, available = {} }
    local ok, found = false, false
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits then
        ok, found = pcall(collectModernTalents, t)
    end
    if not (ok and found) then
        t.chosen, t.available = {}, {}
        ok, found = pcall(collectClassicTalents, t)
    end
    if not (ok and found) then return nil end
    return t
end
