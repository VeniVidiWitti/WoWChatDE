-- Chat DE - Datenschutz-Hinweis vor jeder Claude-Anfrage
-- Lizenz: GNU General Public License v2 oder spaeter, siehe LICENSE.
--
-- Der Hinweis erscheint vor jeder Uebertragung. Mit dem Kaestchen
-- "Nicht mehr anzeigen" wird er fuer diese Addon-Version abgeschaltet.
-- Nach einem Update (neue Versionsnummer) erscheint er wieder.

local ADDON, ns = ...
local C = ns.C

local notice

local function build()
    local f = CreateFrame("Frame", "WoWChatDENotice", UIParent, "BackdropTemplate")
    f:SetSize(520, 380)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    ns.Skin(f, C.bg, C.gold, true)
    -- Nicht in UISpecialFrames: das Fenster enthaelt einen sicheren Knopf und
    -- darf deshalb im Kampf nicht von ESC geschlossen werden. Zu Kampfbeginn
    -- (der Moment ist noch erlaubt) wird es automatisch geschlossen.
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:SetScript("OnEvent", function(self)
        if self:IsShown() then
            self:Hide()
            ns.Print("Kampf beginnt - Anfrage abgebrochen, es wurde nichts übertragen.")
        end
    end)

    local icon = f:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", 16, -16)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = ns.Text(f, "GameFontNormalLarge", "Datenübertragung an Claude", C.gold)
    title:SetPoint("LEFT", icon, "RIGHT", 10, 0)

    local intro = ns.Text(f, "GameFontHighlight",
        "Chat DE übergibt diese Anfrage an das Begleitprogramm auf deinem PC. " ..
        "Es stellt eine Verbindung zu |cffffd24dapi.anthropic.com|r (Anthropic, USA) her und sendet:")
    intro:SetPoint("TOPLEFT", 18, -60)
    intro:SetWidth(484)
    intro:SetJustifyH("LEFT")

    local box = ns.Panel(f, C.field, C.border)
    box:SetPoint("TOPLEFT", 18, -104)
    box:SetSize(484, 140)
    f.details = ns.Text(box, "GameFontHighlightSmall", "")
    f.details:SetPoint("TOPLEFT", 8, -8)
    f.details:SetPoint("BOTTOMRIGHT", -8, 8)
    f.details:SetJustifyH("LEFT")
    f.details:SetJustifyV("TOP")

    local never = ns.Text(f, "GameFontHighlightSmall",
        "|cff9ad6ffNie übertragen:|r Charaktername, Realm, Konto, BattleTag, Gilde, Freunde, Absender von Chatnachrichten, deine Position.\n" ..
        "Danach wird das Interface neu geladen (kurzer Ladebildschirm). Details: DATENSCHUTZ.md im Addon-Ordner.", C.dim)
    never:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -8)
    never:SetWidth(484)
    never:SetJustifyH("LEFT")

    f.check = ns.Toggle(f, "Nicht mehr anzeigen (bis zum nächsten Update)", 300, nil,
        "Nicht mehr anzeigen",
        "Der Hinweis erscheint erst nach dem nächsten Update von Chat DE wieder. In den Einstellungen (Reiter Claude) kannst du ihn jederzeit wieder einschalten.")
    f.check:SetPoint("BOTTOMLEFT", 18, 52)

    -- "Senden" ist ein sicherer Knopf: erst wird die Anfrage gespeichert,
    -- dann fuehrt WoW selbst /reload aus (ReloadUI() aus Addon-Code wird hier blockiert).
    f.send = ns.ReloadButton(f, "Senden", 140, 28, function()
        if f.check.checked then WoWChatDE_Config.noticeAck = ns.VERSION end
        if f.onStore then f.onStore() end
        f.onStore = nil
    end, true)
    ns.AttachTooltip(f.send, "Senden", "Speichert die Anfrage und lädt das Interface neu (kurzer Ladebildschirm).")
    f.send:SetPoint("BOTTOMRIGHT", -18, 16)

    local cancel = ns.Button(f, "Abbrechen", 120, 28, function()
        f.onStore = nil
        f:Hide()
        ns.Print("Anfrage abgebrochen - es wurde nichts übertragen.")
    end)
    cancel:SetPoint("RIGHT", f.send, "LEFT", -8, 0)

    f:Hide()
    return f
end

-- Zeigt den Hinweis (falls nicht abgeschaltet).
-- store() speichert die Anfrage; danach wird neu geladen.
function ns.ConfirmTransfer(summary, store)
    if WoWChatDE_Config.noticeAck == ns.VERSION then
        store()
        ns.Reload()
        return
    end
    if InCombatLockdown() then
        ns.Print("Im Kampf geht das nicht. Bitte nach dem Kampf noch einmal versuchen.")
        return
    end
    notice = notice or build()
    local lines = {}
    for _, s in ipairs(summary or {}) do lines[#lines + 1] = "- " .. s end
    notice.details:SetText(table.concat(lines, "\n"))
    notice.check:SetChecked(false)
    notice.onStore = store
    notice:Show()
end

function ns.ResetNotice()
    WoWChatDE_Config.noticeAck = nil
end
