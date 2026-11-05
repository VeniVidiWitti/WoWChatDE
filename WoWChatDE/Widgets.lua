-- Chat DE - Bausteine fuer die Oberflaeche (uebernommen aus Makro Magic)
-- Lizenz: GNU General Public License v2 oder spaeter, siehe LICENSE.
local addonName, ns = ...

ns.C = {
    bg     = { 0.06, 0.05, 0.10, 0.97 },
    panel  = { 0.10, 0.08, 0.16, 0.95 },
    panel2 = { 0.17, 0.13, 0.27, 0.95 },
    field  = { 0.03, 0.03, 0.06, 0.95 },
    border = { 0.42, 0.32, 0.68, 1 },
    accent = { 0.55, 0.38, 0.95, 1 },
    gold   = { 1.00, 0.82, 0.30, 1 },
    text   = { 0.93, 0.91, 1.00, 1 },
    dim    = { 0.62, 0.59, 0.72, 1 },
    ok     = { 0.40, 0.88, 0.50, 1 },
    warn   = { 1.00, 0.42, 0.36, 1 },
}
local C = ns.C


local FLAT = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
}
local FANCY = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function clamp(v) if v > 1 then return 1 end return v end

-- Farben setzen (nil = unveraendert lassen)
function ns.Color(f, bg, border)
    if bg then f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1) end
    if border then f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1) end
end

-- Rahmen und Hintergrund setzen. Der Frame muss mit "BackdropTemplate" erstellt sein.
function ns.Skin(f, bg, border, fancy)
    f:SetBackdrop(fancy and FANCY or FLAT)
    ns.Color(f, bg or C.panel, border or C.border)
end

function ns.Panel(parent, bg, border, fancy)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    ns.Skin(f, bg, border, fancy)
    return f
end

function ns.Text(parent, font, text, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    if text then fs:SetText(text) end
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    return fs
end

function ns.AttachTooltip(f, title, body)
    f:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, C.gold[1], C.gold[2], C.gold[3])
        if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    f:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function playClick()
    if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
end

-- Knopf im Makro-Magic-Stil. primary = farbig hervorgehoben.
-- template (optional): zusaetzliches Blizzard-Template, z. B. "SecureActionButtonTemplate".
-- Bei sicheren Knoepfen laeuft onClick als PreClick, damit Blizzards Aktion danach ausgefuehrt wird.
function ns.Button(parent, text, w, h, onClick, primary, template)
    local b = CreateFrame("Button", nil, parent, template and (template .. ",BackdropTemplate") or "BackdropTemplate")
    b:SetSize(w or 120, h or 24)
    b:SetBackdrop(FLAT)
    b.primary = primary
    b.label = ns.Text(b, "GameFontHighlight", text)
    b.label:SetPoint("LEFT", 4, 0)
    b.label:SetPoint("RIGHT", -4, 0)
    b.label:SetWordWrap(false)

    function b:Repaint()
        local base = self.primary and C.accent or C.panel2
        if not self:IsEnabled() then
            ns.Color(self, { 0.12, 0.12, 0.14, 0.9 }, { 0.25, 0.25, 0.30, 1 })
            self.label:SetTextColor(0.5, 0.5, 0.55)
        elseif self.checked then
            ns.Color(self, { C.accent[1] * 0.75, C.accent[2] * 0.75, C.accent[3] * 0.75, 1 }, C.gold)
            self.label:SetTextColor(1, 0.95, 0.7)
        elseif self.hover then
            ns.Color(self, { clamp(base[1] * 1.3), clamp(base[2] * 1.3), clamp(base[3] * 1.3), 1 }, C.gold)
            self.label:SetTextColor(1, 1, 1)
        else
            ns.Color(self, base, self.primary and C.gold or C.border)
            self.label:SetTextColor(C.text[1], C.text[2], C.text[3])
        end
    end
    function b:SetText(t) self.label:SetText(t) end
    function b:GetText() return self.label:GetText() end

    b:SetScript("OnEnter", function(self) self.hover = true; self:Repaint() end)
    b:SetScript("OnLeave", function(self) self.hover = false; self:Repaint() end)
    b:SetScript("OnEnable", function(self) self:Repaint() end)
    b:SetScript("OnDisable", function(self) self:Repaint() end)
    if template then
        -- Je nach Einstellung loest Blizzard die Aktion beim Druecken oder Loslassen aus.
        -- onClick laeuft genau einmal pro Klick, und zwar davor.
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetScript("PreClick", function(self, button)
            if self.ranThisPress then return end
            self.ranThisPress = true
            playClick()
            if onClick then onClick(self, button) end
        end)
        b:SetScript("PostClick", function(self, _, down)
            if not down then self.ranThisPress = nil end
        end)
    else
        b:SetScript("OnClick", function(self, button)
            playClick()
            if onClick then onClick(self, button) end
        end)
    end
    b:Repaint()
    return b
end

-- Sicherer Knopf, der das Interface neu laedt (wie /reload eintippen).
-- Funktioniert auch dort, wo WoW ReloadUI() aus Addon-Code blockiert.
-- Nur ausserhalb des Kampfes erstellen und anzeigen.
function ns.ReloadButton(parent, text, w, h, beforeReload, primary)
    local b = ns.Button(parent, text, w, h, beforeReload, primary, "SecureActionButtonTemplate")
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", "/reload")
    return b
end

-- Umschalter ("Chip"), an oder aus
function ns.Toggle(parent, text, w, onChange, tipTitle, tipBody)
    local b
    b = ns.Button(parent, text, w, 22, function(self)
        self:SetChecked(not self.checked)
        if onChange then onChange(self, self.checked) end
    end)
    b.checked = false
    function b:SetChecked(v)
        self.checked = v and true or false
        self:Repaint()
    end
    if tipTitle then ns.AttachTooltip(b, tipTitle, tipBody) end
    return b
end

-- Einzeiliges Eingabefeld
function ns.EditBox(parent, w, h, maxLetters)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(w, h)
    e:SetAutoFocus(false)
    e:SetFontObject(ChatFontNormal)
    e:SetTextInsets(6, 6, 2, 2)
    if maxLetters then e:SetMaxLetters(maxLetters) end
    ns.Skin(e, C.field, C.border)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusGained", function(self) ns.Color(self, nil, C.gold) end)
    e:SetScript("OnEditFocusLost", function(self) ns.Color(self, nil, C.border) end)
    return e
end

-- Rollbarer Bereich mit schmaler Leiste rechts
function ns.Scroll(parent, w, h)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetSize(w, h)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(w - 10, 1)
    sf:SetScrollChild(child)

    local bar = sf:CreateTexture(nil, "OVERLAY")
    bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
    bar:SetWidth(4)
    bar:Hide()

    function sf:UpdateBar()
        local range = self:GetVerticalScrollRange() or 0
        if range <= 0 then bar:Hide(); return end
        local vh = self:GetHeight()
        local bh = math.max(20, vh * vh / (vh + range))
        local off = (self:GetVerticalScroll() / range) * (vh - bh)
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -off)
        bar:SetHeight(bh)
        bar:Show()
    end

    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        local v = self:GetVerticalScroll() - delta * 40
        if v < 0 then v = 0 elseif v > range then v = range end
        self:SetVerticalScroll(v)
        self:UpdateBar()
    end)
    sf:SetScript("OnScrollRangeChanged", function(self) self:UpdateBar() end)
    sf:SetScript("OnVerticalScroll", function(self) self:UpdateBar() end)
    return sf, child
end

-- UTF-8-sicher kuerzen (Umlaute nicht zerschneiden)
function ns.Utf8Sub(s, maxChars)
    if not s then return "" end
    local out, n = {}, 0
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        n = n + 1
        if n > maxChars then break end
        out[n] = ch
    end
    return table.concat(out)
end
