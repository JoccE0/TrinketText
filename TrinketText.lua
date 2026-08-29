local ADDON = ...

-- =========================================================================
--  Defaults
-- =========================================================================
local DEFAULTS = {
	message   = "%s is ready!",   -- %s is replaced with the trinket name
	size      = 34,               -- font size
	time      = 3,                -- seconds the message stays on screen
	color     = { r = 1, g = 0.82, b = 0 },
	threshold = 20,               -- ignore cooldowns shorter than this (seconds)
	combatOnly = false,           -- only announce while in combat
	sound     = false,            -- play a sound with the message
	permanent = false,            -- keep text on screen the whole time a trinket is ready
	slot      = "both",           -- which trinket to watch: "both", "1", "2"
	icon      = false,            -- show the trinket's icon to the left of the text
	pos       = nil,              -- { point, relPoint, x, y }
}

local TRINKET_SLOTS = { INVSLOT_TRINKET1 or 13, INVSLOT_TRINKET2 or 14 }

local db           -- filled from SavedVariables on ADDON_LOADED
local state = {}    -- [slot] = { itemID = , onCD = bool }
local unlocked = false

-- =========================================================================
--  Helpers
-- =========================================================================
local PREFIX = "|cff66ccffTrinketText|r: "
local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

local function SafeFormat(fmt, ...)
	local ok, res = pcall(string.format, fmt, ...)
	return ok and res or fmt
end

local function Clamp(v, lo, hi)
	v = tonumber(v)
	if not v then return nil end
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function GetTrinketName(itemID)
	if C_Item and C_Item.GetItemNameByID then
		local n = C_Item.GetItemNameByID(itemID)
		if n then return n end
	end
	local n = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(itemID)
	return n or "Trinket"
end

local function GetTrinketIcon(itemID)
	local tex
	if C_Item and C_Item.GetItemIconByID then
		tex = C_Item.GetItemIconByID(itemID)
	end
	if not tex and GetItemIcon then tex = GetItemIcon(itemID) end
	return tex
end

-- Inline icon for a trinket, sized to the current font so it sits on the text
-- line. Kept to the plain :h:w form -- the crop form needs the texture's real
-- pixel size (256 on retail) or it scales the icon up several times over.
-- Returns "" when icons are off or no texture is available.
local function IconMarkup(itemID)
	if not db.icon then return "" end
	local tex = itemID and GetTrinketIcon(itemID)
	if not tex then return "" end
	local h = math.floor(db.size + 0.5)
	return ("|T%s:%d:%d|t "):format(tostring(tex), h, h)
end

-- =========================================================================
--  Display frame
-- =========================================================================
local frame = CreateFrame("Frame", "TrinketTextFrame", UIParent)
frame:SetSize(420, 60)
frame:SetFrameStrata("HIGH")
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
frame:EnableMouse(false)
frame:Hide()

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.45)
bg:Hide()

local fs = frame:CreateFontString(nil, "OVERLAY")
fs:SetPoint("CENTER")
fs:SetJustifyH("CENTER")   -- keep both lines centred when two trinkets pop together

frame:SetScript("OnDragStart", function(self)
	if unlocked then self:StartMoving() end
end)
frame:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, relPoint, x, y = self:GetPoint()
	db.pos = { point = point, relPoint = relPoint, x = x, y = y }
end)

local FADE_IN, FADE_OUT = 0.15, 0.4
local hideTimer     -- C_Timer handle for the "hold" phase
local permShown = false   -- permanent-mode text currently on screen

-- stop any in-flight fade / pending hide
local function StopFX()
	if hideTimer then hideTimer:Cancel(); hideTimer = nil end
	if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(frame) end
end

local function ApplySettings()
	fs:SetFont(STANDARD_TEXT_FONT, db.size, "OUTLINE")
	fs:SetTextColor(db.color.r, db.color.g, db.color.b)
	frame:ClearAllPoints()
	if db.pos then
		frame:SetPoint(db.pos.point, UIParent, db.pos.relPoint, db.pos.x, db.pos.y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
	end
end

local function ShowMessage(text)
	if unlocked then return end
	StopFX()
	fs:SetText(text)
	frame:Show()
	UIFrameFadeIn(frame, FADE_IN, frame:GetAlpha(), 1)
	hideTimer = C_Timer.NewTimer(db.time, function()
		hideTimer = nil
		if unlocked or permShown then return end
		UIFrameFadeOut(frame, FADE_OUT, frame:GetAlpha(), 0)
		C_Timer.After(FADE_OUT + 0.05, function()
			if not unlocked and not permShown then frame:Hide() end
		end)
	end)
end

-- permanent mode: text stays up untimed until told to hide
local function ShowPermanent(text)
	if unlocked then return end
	StopFX()
	if fs:GetText() ~= text then fs:SetText(text) end
	frame:SetAlpha(1)
	if not frame:IsShown() then frame:Show() end
	permShown = true
end

local function HidePermanent()
	if permShown and not unlocked then
		StopFX()
		frame:Hide()
		permShown = false
	end
end

local function SetUnlocked(on)
	unlocked = on and true or false
	StopFX()
	permShown = false
	frame:EnableMouse(unlocked)
	if unlocked then
		bg:Show()
		fs:SetText("TrinketText \226\128\148 drag to move")
		frame:SetAlpha(1)
		frame:Show()
		Print("frame |cff00ff00unlocked|r. Drag it, then |cffffff00/tt lock|r.")
	else
		bg:Hide()
		frame:Hide()
		Print("frame |cffff0000locked|r.")
	end
end

-- =========================================================================
--  Cooldown tracking
-- =========================================================================
-- Build the on-screen text for one or more ready trinkets. Each trinket gets
-- its own line, prefixed with its icon when /tt icon is on. Identical lines
-- collapse so a no-%s message with icons off shows only once.
local function BuildText(itemIDs)
	local msg = db.message
	local named = msg:find("%%s") ~= nil
	local seen, lines = {}, {}
	for _, itemID in ipairs(itemIDs) do
		local body = named and SafeFormat(msg, GetTrinketName(itemID)) or msg
		local line = IconMarkup(itemID) .. body
		if not seen[line] then
			seen[line] = true
			lines[#lines + 1] = line
		end
	end
	return table.concat(lines, "\n")
end

local function Announce(itemIDs)
	if db.combatOnly and not InCombatLockdown() then return end
	ShowMessage(BuildText(itemIDs))
	if db.sound then
		PlaySound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master")
	end
end

local slotSpell = {}   -- [slot] = use-spell id, resolved once then remembered

-- ref must be an itemID or an item link (NOT an ItemLocation table)
local function LookupItemSpell(ref)
	if not ref then return end
	if C_Item and C_Item.GetItemSpell then
		local ok, _, spellID = pcall(C_Item.GetItemSpell, ref)
		if ok and spellID then return spellID end
	end
	if GetItemSpell then
		local _, spellID = GetItemSpell(ref)
		return spellID
	end
end

-- Resolve (and cache) the on-use spell for a trinket slot. The equipped item
-- link always carries full data, so it resolves reliably; once found we keep
-- it so the cooldown check never flickers if a later lookup returns nil.
local function GetSlotSpell(slot, itemID)
	if slotSpell[slot] then return slotSpell[slot] end
	local sid = LookupItemSpell(GetInventoryItemLink("player", slot))
		or LookupItemSpell(itemID)
	if sid then slotSpell[slot] = sid end
	return sid
end

local MAX_USE_CD = 3600   -- ignore "cooldowns" longer than this (daily timers, tinkers, etc.)

-- C_Spell.GetSpellCooldown may return "secret" numbers that tainted addon
-- code can't compare, so we only read the plain boolean fields.
local function SpellCDActive(spellID)
	if not spellID then return false end
	local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
	if ok and type(info) == "table" then
		if info.isActive ~= nil then
			return info.isActive == true
		end
		-- older clients: numbers are safe here
		local ok2, active = pcall(function()
			return (info.startTime or 0) > 0 and (info.duration or 0) > db.threshold
		end)
		return ok2 and active or false
	end
	return false
end

-- Is the trinket in this slot currently on a real use-cooldown?
local function SlotOnCooldown(slot, itemID)
	local start, duration = GetInventoryItemCooldown("player", slot)
	start, duration = start or 0, duration or 0
	if start > 0 and duration > db.threshold and duration < MAX_USE_CD then
		return true
	end
	return SpellCDActive(GetSlotSpell(slot, itemID))
end

local function WatchingSlot(slot)
	if db.slot == "1" then return slot == TRINKET_SLOTS[1] end
	if db.slot == "2" then return slot == TRINKET_SLOTS[2] end
	return true
end

local seenCD = {}   -- [slot] = true once a real cooldown has been observed this session

local function CheckAll()
	local justReady = {}   -- itemIDs that went on-CD -> ready in this pass (flash mode)
	local readyNow  = {}   -- itemIDs of every watched on-use trinket currently ready (permanent mode)

	for _, slot in ipairs(TRINKET_SLOTS) do
		local itemID = GetInventoryItemID("player", slot)
		local st = state[slot]
		if not (itemID and WatchingSlot(slot)) then
			state[slot] = nil
		else
			local onCD = SlotOnCooldown(slot, itemID)
			if onCD then seenCD[slot] = true end

			-- flash mode: fire once on the on-CD -> ready transition
			-- (a passive trinket can't create this edge, so no on-use filter needed)
			if not db.permanent and st and st.itemID == itemID and st.onCD and not onCD then
				justReady[#justReady + 1] = itemID
			end

			-- permanent mode only: skip trinkets that are never on cooldown
			local onUse = seenCD[slot] or GetSlotSpell(slot, itemID) ~= nil
			if onUse and not onCD then
				readyNow[#readyNow + 1] = itemID
			end

			state[slot] = { itemID = itemID, onCD = onCD }
		end
	end

	-- flash mode: one message covering every trinket that just became ready,
	-- so two trinkets coming off cooldown together are both shown
	if not db.permanent and #justReady > 0 then
		Announce(justReady)
	end

	-- permanent mode: text is shown for as long as a trinket is ready
	if db.permanent and not unlocked then
		local allowed = not db.combatOnly or InCombatLockdown()
		if #readyNow > 0 and allowed then
			ShowPermanent(BuildText(readyNow))
		else
			HidePermanent()
		end
	end
end

-- poll on a light throttle so the "ready" moment is caught precisely
local acc = 0
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(_, e)
	acc = acc + e
	if acc < 0.2 then return end
	acc = 0
	CheckAll()
end)

-- =========================================================================
--  Slash command
-- =========================================================================
local function PrintHelp()
	Print("commands:")
	Print("  |cffffff00/tt|r                  show these settings")
	Print("  |cffffff00/tt test|r             preview the message")
	Print("  |cffffff00/tt lock|r / |cffffff00unlock|r     lock / move the frame")
	Print("  |cffffff00/tt reset|r            reset position")
	Print("  |cffffff00/tt text <message>|r   set text (|cffffff00%s|r = trinket name)")
	Print("  |cffffff00/tt size <8-72>|r      font size")
	Print("  |cffffff00/tt time <1-30>|r      seconds on screen")
	Print("  |cffffff00/tt color <r> <g> <b>|r  0-1 each, e.g. 1 0.82 0")
	Print("  |cffffff00/tt threshold <sec>|r  ignore cooldowns shorter than this")
	Print("  |cffffff00/tt combat on|off|r    only announce in combat")
	Print("  |cffffff00/tt sound on|off|r     play a sound too")
	Print("  |cffffff00/tt permanent on|off|r keep text up the whole time a trinket is ready")
	Print("  |cffffff00/tt slot both|1|2|r   which trinket slot to watch")
	Print("  |cffffff00/tt icon on|off|r     show the trinket's icon left of the text")
end

local function PrintStatus()
	Print(("text = |cffffffff%s|r"):format(db.message))
	Print(("size = %d   time = %ss   threshold = %ss"):format(db.size, db.time, db.threshold))
	Print(("color = %.2f %.2f %.2f   combatOnly = %s   sound = %s")
		:format(db.color.r, db.color.g, db.color.b, tostring(db.combatOnly), tostring(db.sound)))
	Print(("permanent = %s   slot = %s   icon = %s")
		:format(tostring(db.permanent), db.slot, tostring(db.icon)))
end

SLASH_TRINKETTEXT1 = "/trinkettext"
SLASH_TRINKETTEXT2 = "/tt"
SlashCmdList.TRINKETTEXT = function(input)
	local cmd, rest = (input or ""):match("^(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()

	if cmd == "" then
		PrintStatus()
		PrintHelp()

	elseif cmd == "help" then
		PrintHelp()

	elseif cmd == "debug" then
		for i, slot in ipairs(TRINKET_SLOTS) do
			local itemID = GetInventoryItemID("player", slot)
			if not itemID then
				Print(("slot %d (%d): empty"):format(i, slot))
			else
				local is, id = GetInventoryItemCooldown("player", slot)
				is, id = is or 0, id or 0
				local sid = GetSlotSpell(slot, itemID)
				local ok, info = pcall(C_Spell.GetSpellCooldown, sid)
				local isActive = (ok and type(info) == "table") and tostring(info.isActive) or "n/a"
				Print(("slot %d: |cffffffff%s|r (item %d)"):format(i, GetTrinketName(itemID), itemID))
				Print(("  itemCD: start=%.1f dur=%.1f  (max allowed %ds)"):format(is, id, MAX_USE_CD))
				Print(("  useSpell=%s  spell.isActive=%s"):format(tostring(sid), isActive))
				Print(("  -> onCD=%s   threshold=%ss"):format(tostring(SlotOnCooldown(slot, itemID)), db.threshold))
			end
		end

	elseif cmd == "test" then
		-- preview with whatever is actually equipped, so both slots show
		local ids = {}
		for _, slot in ipairs(TRINKET_SLOTS) do
			ids[#ids + 1] = GetInventoryItemID("player", slot)
		end
		local sample
		if #ids > 0 then
			sample = BuildText(ids)
		else
			sample = db.message:find("%%s")
				and SafeFormat(db.message, "Test Trinket") or db.message
		end
		if db.permanent then ShowPermanent(sample) else ShowMessage(sample) end

	elseif cmd == "unlock" then
		SetUnlocked(true)

	elseif cmd == "lock" then
		SetUnlocked(false)

	elseif cmd == "reset" then
		db.pos = nil
		ApplySettings()
		Print("position reset.")

	elseif cmd == "text" then
		if rest == "" then
			Print(("text = |cffffffff%s|r"):format(db.message))
		else
			db.message = rest
			Print(("text set to |cffffffff%s|r"):format(rest))
		end

	elseif cmd == "size" then
		local v = Clamp(rest, 8, 72)
		if v then db.size = v; ApplySettings(); Print("size = " .. v)
		else Print("usage: /tt size <8-72>") end

	elseif cmd == "time" then
		local v = Clamp(rest, 1, 30)
		if v then db.time = v; Print("time = " .. v .. "s")
		else Print("usage: /tt time <1-30>") end

	elseif cmd == "threshold" then
		local v = Clamp(rest, 0, 600)
		if v then db.threshold = v; Print("threshold = " .. v .. "s")
		else Print("usage: /tt threshold <seconds>") end

	elseif cmd == "color" then
		local r, g, b = rest:match("([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)")
		r, g, b = Clamp(r, 0, 1), Clamp(g, 0, 1), Clamp(b, 0, 1)
		if r and g and b then
			db.color.r, db.color.g, db.color.b = r, g, b
			ApplySettings()
			Print(("color = %.2f %.2f %.2f"):format(r, g, b))
		else
			Print("usage: /tt color <r> <g> <b>   (0-1 each)")
		end

	elseif cmd == "combat" then
		db.combatOnly = (rest:lower() == "on")
		Print("combatOnly = " .. tostring(db.combatOnly))

	elseif cmd == "sound" then
		db.sound = (rest:lower() == "on")
		Print("sound = " .. tostring(db.sound))

	elseif cmd == "permanent" or cmd == "sticky" then
		db.permanent = (rest:lower() == "on")
		if not db.permanent then HidePermanent() end
		CheckAll()
		Print("permanent = " .. tostring(db.permanent))

	elseif cmd == "slot" then
		local v = rest:lower():gsub("%s+", "")
		if v == "both" or v == "1" or v == "2" then
			db.slot = v
			wipe(state)
			wipe(seenCD)
			HidePermanent()
			CheckAll()
			Print("slot = " .. v)
		else
			Print("usage: /tt slot both|1|2")
		end

	elseif cmd == "icon" then
		db.icon = (rest:lower() == "on")
		CheckAll()
		Print("icon = " .. tostring(db.icon))

	else
		Print("unknown command '" .. cmd .. "'")
		PrintHelp()
	end
end

-- =========================================================================
--  Lifecycle
-- =========================================================================
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
boot:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		TrinketTextDB = TrinketTextDB or {}
		db = TrinketTextDB
		for k, v in pairs(DEFAULTS) do
			if db[k] == nil then
				if type(v) == "table" then
					db[k] = CopyTable(v)
				else
					db[k] = v
				end
			end
		end
		ApplySettings()
		Print("loaded. Type |cffffff00/tt|r for options.")

	elseif event == "PLAYER_ENTERING_WORLD" then
		wipe(state)
		CheckAll()          -- seed current cooldown state, no announce
		driver:Show()

	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		wipe(seenCD)     -- trinkets may have been swapped
		wipe(slotSpell)
		CheckAll()
	end
end)
