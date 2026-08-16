--[[
	PallyCue — glanceable paladin blessing reminder + one-button rebuff
	Designed for Steam Deck / ConsolePort. No assignment grid, no mouse-wheel.
]]

PallyCue = PallyCue or {}

local addon = PallyCue
local DB

local isVanilla = (_G.WOW_PROJECT_ID == _G.WOW_PROJECT_CLASSIC)
local isTBC = (_G.WOW_PROJECT_ID == _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC)
local isWrath = (_G.WOW_PROJECT_ID == _G.WOW_PROJECT_WRATH_CLASSIC)

local UnitAura = UnitAura
do
	local lcd = LibStub and LibStub("LibClassicDurations", true)
	if lcd and isVanilla then
		lcd:Register("PallyCue")
		UnitAura = lcd.UnitAuraWrapper or UnitAura
	end
end

BINDING_HEADER_PALLYCUE = "PallyCue"
BINDING_NAME_PALLYCUE_REBUFF = "Rebuff"

local SYMBOLS = 21177
local MAX_ROWS = 5
local SCAN_DELAY = 0.5
local ALERT_COOLDOWN = 8
local ZONE_SUPPRESS = 5

local GREATER_WARN = (isVanilla and 180) or 300
local NORMAL_WARN = (isVanilla and 60) or 120
local SELF_WARN = 30

local MELEE = {
	WARRIOR = true,
	ROGUE = true,
	HUNTER = true,
	DEATHKNIGHT = true,
	PALADIN = true,
}
local CASTER = {
	PRIEST = true,
	MAGE = true,
	WARLOCK = true,
	DRUID = true,
	SHAMAN = true,
}

local COLORS = {
	missing = {1.0, 0.18, 0.14},
	expiring = {1.0, 0.84, 0.18},
	range = {0.30, 0.55, 1.0},
	dead = {0.55, 0.55, 0.55},
	wait = {1.0, 0.55, 0.15},
	ok = {0.10, 0.75, 0.20},
}

local defaults = {
	melee = 2,
	caster = 1,
	tank = 3,
	watchRF = true,
	watchPets = false,
	watchOutsiders = true,
	showHud = false,
	showSolo = true,
	sound = true,
	centerText = true,
	combatOnly = true,
	hideHealthy = true,
	tankAggro = false,
	locked = false,
	point = "CENTER",
	relPoint = "CENTER",
	x = 180,
	y = -40,
	scale = 1.1,
}

local blessingNames = {}
local greaterNames = {}
local blessingIcons = {}
local normalRanks = {}
local greaterRanks = {}
local auraNames = {}
local sealNames = {}
local rfName
local rfIcon = "Interface\\Icons\\Spell_Holy_SealOfFury"

local roster = {}
local partyUnits = { "player" }
local raidUnits = {}
local scanQueued
local zoneAt = 0
local lastAlert = {}
local lastSeal
local lastAura
local armed = {}
local listRows = {}
local setupControls = {}
local enabled

local function CopyDefaults(src, dst)
	dst = dst or {}
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

local function SpellName(id)
	return GetSpellInfo(id)
end

local function Known(id)
	return id and IsSpellKnown(id)
end

local function HasSymbols()
	return (GetItemCount(SYMBOLS) or 0) > 0
end

local function PallyPowerActive()
	return _G.PallyPower and _G.PallyPower.opt and _G.PallyPower.opt.enable
end

local function InRange(spell, unit)
	if not spell or not unit or unit == "player" then
		return true
	end
	local r = IsSpellInRange(spell, unit)
	return r == 1 or r == true
end

local function IsTank(unit)
	if UnitGroupRolesAssigned then
		local role = UnitGroupRolesAssigned(unit)
		if role == "TANK" then
			return true
		end
	end
	return GetPartyAssignment and GetPartyAssignment("MAINTANK", unit)
end

local function FormatTime(remain)
	if not remain or remain < 0 then
		return ""
	end
	remain = math.floor(remain)
	if remain >= 60 then
		return string.format("%d:%02d", math.floor(remain / 60), remain % 60)
	end
	return string.format("%ds", remain)
end

local function ClassColor(class)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then
		return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
	end
	return "|cffffffff"
end

function addon.InitSpells()
	if isWrath then
		blessingNames = {
			[1] = SpellName(19742),
			[2] = SpellName(19740),
			[3] = SpellName(20217),
			[4] = SpellName(20911),
		}
		greaterNames = {
			[1] = SpellName(25894),
			[2] = SpellName(25782),
			[3] = SpellName(25898),
			[4] = SpellName(25899),
		}
		blessingIcons = {
			[1] = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
			[2] = "Interface\\Icons\\Spell_Holy_FistOfJustice",
			[3] = "Interface\\Icons\\Spell_Magic_MageArmor",
			[4] = "Interface\\Icons\\Spell_Nature_LightningShield",
		}
		normalRanks = {
			[1] = {{67, 48936}, {61, 48935}, {55, 27142}, {50, 25290}, {44, 19854}, {34, 19853}, {24, 19852}, {14, 19850}, {4, 19742}},
			[2] = {{69, 48932}, {63, 48931}, {60, 27140}, {50, 25291}, {42, 19838}, {32, 19837}, {22, 19836}, {12, 19835}, {4, 19834}, {0, 19740}},
			[3] = {{10, 20217}},
			[4] = {{20, 20911}},
		}
		greaterRanks = {
			[1] = {{67, 48938}, {61, 48937}, {55, 27143}, {50, 25918}, {44, 25894}},
			[2] = {{69, 48934}, {63, 48933}, {60, 27141}, {50, 25916}, {42, 25782}},
			[3] = {{50, 25898}},
			[4] = {{50, 25899}},
		}
		auraNames = {
			SpellName(465), SpellName(7294), SpellName(19746), SpellName(19876),
			SpellName(19888), SpellName(19891), SpellName(32223),
		}
		sealNames = {
			SpellName(20164), SpellName(20165), SpellName(20166), SpellName(21084),
			SpellName(20375), SpellName(31801), SpellName(31892), SpellName(348700), SpellName(348704),
		}
	else
		blessingNames = {
			[1] = SpellName(19742),
			[2] = SpellName(19740),
			[3] = SpellName(20217),
			[4] = SpellName(1038),
			[5] = SpellName(19977),
			[6] = SpellName(20911),
		}
		greaterNames = {
			[1] = SpellName(25894),
			[2] = SpellName(25782),
			[3] = SpellName(25898),
			[4] = SpellName(25895),
			[5] = SpellName(25890),
			[6] = SpellName(25899),
		}
		blessingIcons = {
			[1] = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
			[2] = "Interface\\Icons\\Spell_Holy_FistOfJustice",
			[3] = "Interface\\Icons\\Spell_Magic_MageArmor",
			[4] = "Interface\\Icons\\Spell_Holy_SealOfSalvation",
			[5] = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02",
			[6] = "Interface\\Icons\\Spell_Nature_LightningShield",
		}
		normalRanks = {
			[1] = {{55, 27142}, {50, 25290}, {44, 19854}, {34, 19853}, {24, 19852}, {14, 19850}, {4, 19742}},
			[2] = {{60, 27140}, {50, 25291}, {42, 19838}, {32, 19837}, {22, 19836}, {12, 19835}, {4, 19834}, {0, 19740}},
			[3] = {{10, 20217}},
			[4] = {{16, 1038}},
			[5] = {{59, 27144}, {50, 19979}, {40, 19978}, {30, 19977}},
			[6] = {{60, 27168}, {50, 20914}, {40, 20913}, {30, 20912}, {20, 20911}},
		}
		greaterRanks = {
			[1] = {{55, 27143}, {50, 25918}, {44, 25894}},
			[2] = {{60, 27141}, {50, 25916}, {42, 25782}},
			[3] = {{50, 25898}},
			[4] = {{50, 25895}},
			[5] = {{59, 27145}, {50, 25890}},
			[6] = {{60, 27169}, {50, 25899}},
		}
		auraNames = {
			SpellName(465), SpellName(7294), SpellName(19746), SpellName(19876),
			SpellName(19888), SpellName(19891), SpellName(20218), SpellName(32223),
		}
		sealNames = {
			SpellName(20164), SpellName(20165), SpellName(20166), SpellName(21084),
			SpellName(21082), SpellName(20375), SpellName(31801), SpellName(31892),
			SpellName(348700), SpellName(348704),
		}
	end
	rfName = SpellName(25780)

	for i = 1, MAX_PARTY_MEMBERS do
		partyUnits[#partyUnits + 1] = "party" .. i
		partyUnits[#partyUnits + 1] = "partypet" .. i
	end
	partyUnits[#partyUnits + 1] = "pet"
	for i = 1, MAX_RAID_MEMBERS do
		raidUnits[#raidUnits + 1] = "raid" .. i
		raidUnits[#raidUnits + 1] = "raidpet" .. i
	end
end

local function BlessingIdFor(class, unit)
	if IsTank(unit) and DB.tank and blessingNames[DB.tank] then
		return DB.tank
	end
	if MELEE[class] then
		return DB.melee
	end
	if CASTER[class] then
		return DB.caster
	end
	return DB.melee
end

local function NameSet(id)
	local set = {}
	if blessingNames[id] then
		set[blessingNames[id]] = true
	end
	if greaterNames[id] then
		set[greaterNames[id]] = true
	end
	return set
end

local function AsLookup(names)
	if not names then
		return nil
	end
	if names[1] then
		local lookup = {}
		for _, n in ipairs(names) do
			if n then
				lookup[n] = true
			end
		end
		return lookup
	end
	return names
end

local function FindAura(unit, names)
	local lookup = AsLookup(names)
	if not lookup then
		return nil
	end
	local i = 1
	while true do
		local name, _, _, _, duration, expiration = UnitAura(unit, i, "HELPFUL")
		if not name then
			break
		end
		if lookup[name] then
			local remain
			if expiration and expiration > 0 then
				remain = expiration - GetTime()
			end
			return name, remain, duration
		end
		i = i + 1
	end
	return nil
end

local function SpellIcon(spell)
	if not spell then
		return "Interface\\Icons\\INV_Misc_QuestionMark"
	end
	local _, _, icon = GetSpellInfo(spell)
	return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function FindBlessing(unit, id)
	local set = NameSet(id)
	local i = 1
	while true do
		local name, _, icon, _, duration, expiration = UnitAura(unit, i, "HELPFUL")
		if not name then
			break
		end
		if set[name] then
			local remain
			if expiration and expiration > 0 then
				remain = expiration - GetTime()
			end
			local isGreater = greaterNames[id] and name == greaterNames[id]
			return name, remain, duration, isGreater, icon
		end
		i = i + 1
	end
	return nil
end

local function BestSpell(id, unit, wantGreater)
	if not id or not blessingNames[id] then
		return nil
	end
	local level = UnitLevel(unit) or 1
	if wantGreater and greaterRanks[id] and level >= 50 and HasSymbols() then
		for _, row in ipairs(greaterRanks[id]) do
			if level >= row[1] and Known(row[2]) then
				return SpellName(row[2]), true
			end
		end
	end
	if normalRanks[id] then
		for _, row in ipairs(normalRanks[id]) do
			if level >= row[1] and Known(row[2]) then
				return SpellName(row[2]), false
			end
		end
	end
	return blessingNames[id], false
end

local function FirstKnownBlessing(unit)
	unit = unit or "player"
	local level = UnitLevel(unit) or 1
	local ids = {}
	for id in pairs(blessingNames) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		if normalRanks[id] then
			for _, row in ipairs(normalRanks[id]) do
				if level >= row[1] and Known(row[2]) then
					return id, SpellName(row[2])
				end
			end
		end
	end
	local _, class = UnitClass(unit)
	local id = BlessingIdFor(class, unit)
	return id, blessingNames[id]
end

local function SkipPetNPC(unit)
	local guid = UnitGUID(unit)
	if not guid then
		return false
	end
	local unitType, _, _, _, _, npcId = strsplit("-", guid)
	if unitType ~= "Pet" and (npcId == "510" or npcId == "19668" or npcId == "1863" or npcId == "26125" or npcId == "185317") then
		return true
	end
	local i = 1
	while true do
		local _, _, _, _, _, _, _, _, _, spellId = UnitAura(unit, i, "HELPFUL")
		if not spellId then
			break
		end
		if spellId == 4511 then
			return true
		end
		i = i + 1
	end
	return false
end

local function RosterHasGUID(guid)
	if not guid then
		return false
	end
	for _, entry in ipairs(roster) do
		if UnitGUID(entry.unit) == guid then
			return true
		end
	end
	return false
end

local function IsSelectUnit(unit)
	return unit == "target" or unit == "focus" or unit == "mouseover"
end

local function CanBless(unit)
	if not unit or not UnitExists(unit) or UnitIsDeadOrGhost(unit) then
		return false
	end
	if UnitCanAttack("player", unit) then
		return false
	end
	if UnitCanAssist then
		return UnitCanAssist("player", unit) and true or false
	end
	return UnitIsFriend("player", unit) and true or false
end

local function IsFriendlyPlayer(unit)
	return CanBless(unit) and UnitIsPlayer(unit)
end

local function SelectedBlessUnit()
	if DB.watchOutsiders then
		local candidates = { "mouseover", "target", "focus", "softfriend" }
		for _, unit in ipairs(candidates) do
			if CanBless(unit) and not UnitIsUnit(unit, "player") then
				return unit
			end
		end
	end
	return "player"
end

local function TryAddOutsider(unit)
	if not IsFriendlyPlayer(unit) then
		return
	end
	if UnitIsUnit(unit, "player") then
		return
	end
	if (UnitInParty and UnitInParty(unit)) or (UnitInRaid and UnitInRaid(unit)) then
		return
	end
	local guid = UnitGUID(unit)
	if RosterHasGUID(guid) then
		return
	end
	local _, class = UnitClass(unit)
	if not class then
		return
	end
	roster[#roster + 1] = {
		unit = unit,
		name = GetUnitName(unit, false) or unit,
		class = class,
		pet = false,
		outsider = true,
	}
end

function addon.BuildRoster()
	wipe(roster)
	local units = IsInRaid() and raidUnits or partyUnits
	local grouped = IsInGroup and IsInGroup() or (GetNumGroupMembers() > 0)
	if not grouped and not DB.showSolo and not DB.watchOutsiders then
		return
	end
	for _, unit in ipairs(units) do
		if UnitExists(unit) then
			local isPet = unit:find("pet")
			if (not isPet or DB.watchPets) and not (isPet and SkipPetNPC(unit)) then
				local _, class = UnitClass(unit)
				if class then
					roster[#roster + 1] = {
						unit = unit,
						name = GetUnitName(unit, false) or unit,
						class = class,
						pet = isPet and true or false,
					}
				end
			end
		end
	end
	if DB.watchOutsiders then
		TryAddOutsider("mouseover")
		TryAddOutsider("target")
		TryAddOutsider("focus")
	end
end

local function ClassifyBlessing(entry)
	local id = BlessingIdFor(entry.class, entry.unit)
	entry.blessingId = id
	if UnitIsDeadOrGhost(entry.unit) then
		entry.state = "dead"
		return
	end
	if not UnitIsConnected(entry.unit) then
		entry.state = "dead"
		return
	end
	local name, remain, _, isGreater = FindBlessing(entry.unit, id)
	entry.remain = remain
	entry.hasGreater = isGreater
	if not name then
		entry.state = "missing"
		return
	end
	local warn = isGreater and GREATER_WARN or NORMAL_WARN
	if remain and remain < warn then
		entry.state = "expiring"
	else
		entry.state = "ok"
	end
end

local function ScanSelfBuff(names, lastName)
	local lookup = {}
	for _, n in ipairs(names) do
		if n then
			lookup[n] = true
		end
	end
	local name, remain = FindAura("player", lookup)
	if name then
		return name, remain, "ok"
	end
	if lastName then
		return lastName, nil, "missing"
	end
	return nil, nil, "missing"
end

function addon.CollectProblems()
	local problems = {}

	if DB.watchRF and rfName then
		local name, remain = FindAura("player", { [rfName] = true })
		if not name then
			problems[#problems + 1] = {
				priority = 1,
				kind = "rf",
				unit = "player",
				spell = rfName,
				icon = rfIcon,
				label = rfName,
				state = "missing",
				count = 1,
			}
		elseif remain and remain < SELF_WARN then
			problems[#problems + 1] = {
				priority = 1,
				kind = "rf",
				unit = "player",
				spell = rfName,
				icon = rfIcon,
				label = rfName,
				state = "expiring",
				remain = remain,
				count = 1,
			}
		end
	end

	local auraName, auraRemain, auraState = ScanSelfBuff(auraNames, lastAura)
	if auraName and auraState == "ok" then
		lastAura = auraName
	end
	if auraState == "missing" or (auraRemain and auraRemain < SELF_WARN) then
		local spell = lastAura or auraNames[1]
		if spell then
			problems[#problems + 1] = {
				priority = 2,
				kind = "aura",
				unit = "player",
				spell = spell,
				icon = SpellIcon(spell),
				label = spell,
				state = auraState == "missing" and "missing" or "expiring",
				remain = auraRemain,
				count = 1,
			}
		end
	end

	local sealName, sealRemain, sealState = ScanSelfBuff(sealNames, lastSeal)
	if sealName and sealState == "ok" then
		lastSeal = sealName
	end
	if sealState == "missing" or (sealRemain and sealRemain < SELF_WARN) then
		local spell = lastSeal or sealNames[4] or sealNames[1]
		if spell then
			problems[#problems + 1] = {
				priority = 3,
				kind = "seal",
				unit = "player",
				spell = spell,
				icon = SpellIcon(spell),
				label = spell,
				state = sealState == "missing" and "missing" or "expiring",
				remain = sealRemain,
				count = 1,
			}
		end
	end

	local byClass = {}
	for _, entry in ipairs(roster) do
		ClassifyBlessing(entry)
		if entry.state == "missing" or entry.state == "expiring" then
			local spell, isGreater = BestSpell(entry.blessingId, entry.unit, not entry.outsider)
			local nSpell = BestSpell(entry.blessingId, entry.unit, false)
			local inRange = InRange(spell or nSpell, entry.unit)
			if not inRange and entry.state ~= "dead" then
				entry.state = "range"
			end
			entry.spell = (inRange and (spell or nSpell)) or nSpell
			entry.useGreater = isGreater and not entry.outsider
			entry.icon = blessingIcons[entry.blessingId]
			if not entry.outsider then
				local class = entry.class
				byClass[class] = byClass[class] or { missing = {}, expiring = {}, id = entry.blessingId }
				if entry.state == "missing" then
					table.insert(byClass[class].missing, entry)
				elseif entry.state == "expiring" then
					table.insert(byClass[class].expiring, entry)
				end
			end
			problems[#problems + 1] = {
				priority = entry.outsider and 20 or 10,
				kind = "blessing",
				unit = entry.unit,
				spell = entry.spell,
				icon = entry.icon,
				label = string.format("%s%s|r", ClassColor(entry.class), entry.name),
				plainName = entry.name,
				state = entry.state,
				remain = entry.remain,
				count = 1,
				class = entry.class,
				blessingId = entry.blessingId,
				useGreater = entry.useGreater,
			}
		end
	end

	-- Promote a class-wide Greater as the next action when several people need it
	local bestClass, bestNeed, bestEntry
	for class, info in pairs(byClass) do
		local need = #info.missing + #info.expiring
		local sample = info.missing[1] or info.expiring[1]
		if sample and sample.useGreater and need >= 1 then
			if not bestNeed or need > bestNeed then
				bestNeed = need
				bestClass = class
				bestEntry = sample
			end
		end
	end
	if bestEntry then
		local classLabel = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[bestClass]) or bestClass
		table.insert(problems, 1, {
			priority = 4,
			kind = "greater",
			unit = bestEntry.unit,
			spell = bestEntry.spell,
			icon = bestEntry.icon,
			label = string.format("%s · %d missing", classLabel, bestNeed),
			state = #byClass[bestClass].missing > 0 and "missing" or "expiring",
			remain = bestEntry.remain,
			count = bestNeed,
			class = bestClass,
		})
	end

	table.sort(problems, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		if a.state ~= b.state then
			return a.state == "missing"
		end
		return (a.remain or 0) < (b.remain or 0)
	end)

	return problems
end

local function InFight()
	if UnitAffectingCombat("player") then
		return true
	end
	for _, entry in ipairs(roster) do
		if UnitAffectingCombat(entry.unit) then
			return true
		end
	end
	return false
end

local function PlayerIsTanking()
	if IsTank("player") then
		return true
	end
	if rfName and FindAura("player", { [rfName] = true }) then
		return true
	end
	return false
end

local function AggroAlert(entry)
	if GetTime() - zoneAt < ZONE_SUPPRESS then
		return
	end
	local key = "aggro:" .. (entry.name or entry.unit)
	local now = GetTime()
	if lastAlert[key] and now - lastAlert[key] < ALERT_COOLDOWN then
		return
	end
	lastAlert[key] = now

	if PallyCueFrame and PallyCueFrame:IsShown() then
		UIFrameFlash(PallyCueRebuff, 0.15, 0.15, 0.9, false, 0, 0)
	end
	if DB.sound then
		PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
	end
	if DB.centerText then
		local text = string.format("%s%s|r has aggro", ClassColor(entry.class), entry.name)
		if RaidNotice_AddMessage and RaidWarningFrame then
			RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
		else
			UIErrorsFrame:AddMessage(text, 1, 0.2, 0.2)
		end
	end
end

local function ConsiderHostile(unit, hostiles)
	if not unit or not UnitExists(unit) then
		return
	end
	if UnitIsDead(unit) or not UnitCanAttack("player", unit) then
		return
	end
	hostiles[UnitGUID(unit) or unit] = unit
end

function addon.ScanHostileAggro()
	if not DB.tankAggro then
		return
	end
	local grouped = IsInGroup and IsInGroup() or (GetNumGroupMembers() > 0)
	if not grouped or not InFight() or not PlayerIsTanking() then
		return
	end

	local members = {}
	for _, entry in ipairs(roster) do
		if not entry.pet and not entry.outsider and entry.unit ~= "player" and not IsTank(entry.unit) then
			members[#members + 1] = entry
		end
	end
	if #members == 0 then
		return
	end

	local hostiles = {}
	ConsiderHostile("target", hostiles)
	ConsiderHostile("focus", hostiles)
	ConsiderHostile("mouseover", hostiles)
	for _, entry in ipairs(roster) do
		ConsiderHostile(entry.unit .. "target", hostiles)
	end
	for i = 1, 40 do
		ConsiderHostile("nameplate" .. i, hostiles)
	end

	local seen = {}
	for _, mob in pairs(hostiles) do
		local tt = mob .. "target"
		if UnitExists(tt) then
			for _, entry in ipairs(members) do
				if not seen[entry.unit] and UnitIsUnit(tt, entry.unit) then
					seen[entry.unit] = entry
				end
			end
		end
	end

	if UnitThreatSituation then
		for _, entry in ipairs(members) do
			if not seen[entry.unit] then
				local s = UnitThreatSituation(entry.unit)
				if s and s >= 2 then
					seen[entry.unit] = entry
				end
			end
		end
	end

	for _, entry in pairs(seen) do
		AggroAlert(entry)
	end
end

local function Alert(problem)
	if GetTime() - zoneAt < ZONE_SUPPRESS then
		return
	end
	if DB.combatOnly and not InFight() then
		return
	end
	if problem.state ~= "missing" then
		return
	end
	local key = (problem.plainName or problem.unit) .. ":" .. (problem.spell or problem.kind)
	local now = GetTime()
	if lastAlert[key] and now - lastAlert[key] < ALERT_COOLDOWN then
		return
	end
	lastAlert[key] = now

	if PallyCueFrame and PallyCueFrame:IsShown() then
		UIFrameFlash(PallyCueRebuff, 0.15, 0.15, 0.9, false, 0, 0)
	end
	if DB.sound then
		PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
	end
	if DB.centerText then
		local text
		if problem.plainName and problem.spell then
			text = problem.spell .. " faded: " .. problem.plainName
		else
			text = (problem.label or "Buff") .. " missing"
		end
		if RaidNotice_AddMessage and RaidWarningFrame then
			RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
		else
			UIErrorsFrame:AddMessage(text, 1, 0.2, 0.2)
		end
	end
end

local function ColorFor(state)
	return unpack(COLORS[state] or COLORS.missing)
end

local function PlaceClicker(onHud)
	if InCombatLockdown() then
		return
	end
	local btn = PallyCueRebuff
	btn:RegisterForClicks("AnyUp", "AnyDown", "LeftButtonDown", "RightButtonDown", "LeftButtonUp", "RightButtonUp")
	if onHud then
		btn:SetParent(PallyCueFrame)
		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT")
		btn:SetSize(72, 72)
		btn:SetAlpha(1)
		btn:EnableMouse(true)
		btn:Show()
	else
		-- Must stay shown or /click does nothing in Classic.
		btn:SetParent(UIParent)
		btn:ClearAllPoints()
		btn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -80, -80)
		btn:SetSize(8, 8)
		btn:SetAlpha(0)
		btn:EnableMouse(false)
		btn:Show()
	end
end

local function ArmButton(problem)
	local btn = PallyCueRebuff
	if InCombatLockdown() then
		return
	end
	if problem and problem.spell and problem.unit and problem.state ~= "range" and problem.state ~= "dead" then
		local unit = problem.unit
		local spell = problem.spell
		if problem.kind == "blessing" or problem.kind == "greater" or problem.outsider then
			unit = SelectedBlessUnit()
			spell = BestSpell(problem.blessingId or BlessingIdFor(select(2, UnitClass(unit)), unit), unit, false) or spell
		end
		-- type=spell (not macro): a bar /click cannot nest into another macro button.
		btn:SetAttribute("type", "spell")
		btn:SetAttribute("spell", spell)
		btn:SetAttribute("unit", unit)
		btn:SetAttribute("type1", "spell")
		btn:SetAttribute("spell1", spell)
		btn:SetAttribute("unit1", unit)
		btn:SetAttribute("type2", "spell")
		btn:SetAttribute("spell2", spell)
		btn:SetAttribute("unit2", unit)
		btn:SetAttribute("macrotext", nil)
		btn:SetAttribute("macrotext1", nil)
		btn:SetAttribute("macrotext2", nil)
		armed.unit = unit
		armed.spell = spell
		armed.macro = "spell:" .. tostring(spell)
	else
		btn:SetAttribute("type", nil)
		btn:SetAttribute("spell", nil)
		btn:SetAttribute("unit", nil)
		btn:SetAttribute("type1", nil)
		btn:SetAttribute("spell1", nil)
		btn:SetAttribute("unit1", nil)
		btn:SetAttribute("type2", nil)
		btn:SetAttribute("spell2", nil)
		btn:SetAttribute("unit2", nil)
		btn:SetAttribute("macrotext", nil)
		armed.unit = nil
		armed.spell = nil
		armed.macro = nil
	end
end

local function SelectOrSelfBlessing()
	local unit = SelectedBlessUnit()
	local _, class = UnitClass(unit)
	local id = BlessingIdFor(class, unit)
	local spell = BestSpell(id, unit, false)
	if id and normalRanks[id] then
		local known
		for _, row in ipairs(normalRanks[id]) do
			if Known(row[2]) then
				known = true
				break
			end
		end
		if not known then
			id, spell = FirstKnownBlessing(unit)
		end
	end
	if not spell then
		return nil
	end
	return {
		kind = "blessing",
		unit = unit,
		spell = spell,
		blessingId = id,
		outsider = unit ~= "player",
		state = "ok",
		icon = blessingIcons[id],
		label = string.format("%s%s|r", ClassColor(class), GetUnitName(unit, false) or unit),
		count = 1,
	}
end

local function EnsureRows()
	if #listRows > 0 then
		return
	end
	for i = 1, MAX_ROWS do
		local row = CreateFrame("Frame", "PallyCueRow" .. i, PallyCueFrame)
		row:SetSize(280, 28)
		if i == 1 then
			row:SetPoint("TOPLEFT", PallyCueFrame, "TOPLEFT", 0, -76)
		else
			row:SetPoint("TOPLEFT", listRows[i - 1], "BOTTOMLEFT", 0, -2)
		end
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		row.bg:SetColorTexture(0, 0, 0, 0.45)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(24, 24)
		row.icon:SetPoint("LEFT", 4, 0)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.text:SetPoint("RIGHT", -8, 0)
		row.text:SetJustifyH("LEFT")
		row:Hide()
		listRows[i] = row
	end
end

local function UpdateList(problems)
	EnsureRows()
	local shown = 0
	for _, p in ipairs(problems) do
		if p.kind == "blessing" or p.kind == "rf" or p.kind == "aura" or p.kind == "seal" then
			shown = shown + 1
			if shown <= MAX_ROWS then
				local row = listRows[shown]
				row.icon:SetTexture(p.icon)
				local extra = ""
				if p.state == "range" then
					extra = "  (range)"
				elseif p.state == "dead" then
					extra = "  (dead)"
				elseif p.remain then
					extra = "  " .. FormatTime(p.remain)
				end
				row.text:SetText((p.label or "") .. extra)
				local r, g, b = ColorFor(p.state)
				row.bg:SetColorTexture(r * 0.25, g * 0.25, b * 0.25, 0.55)
				row:Show()
			end
		end
	end
	local total = 0
	for _, p in ipairs(problems) do
		if p.kind == "blessing" or p.kind == "rf" or p.kind == "aura" or p.kind == "seal" then
			total = total + 1
		end
	end
	if total > MAX_ROWS then
		listRows[MAX_ROWS].icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		listRows[MAX_ROWS].text:SetText(string.format("+%d more", total - MAX_ROWS + 1))
		listRows[MAX_ROWS]:Show()
		shown = MAX_ROWS
	end
	for i = shown + 1, MAX_ROWS do
		listRows[i]:Hide()
	end
	local height = 72 + (shown > 0 and (shown * 30 + 8) or 0)
	if not InCombatLockdown() then
		PallyCueFrame:SetHeight(height)
	end
end

function addon.UpdateHUD(problems)
	local hideForPP = PallyPowerActive()
	local hudAction
	for _, p in ipairs(problems) do
		if p.kind ~= "blessing" or p.state == "missing" or p.state == "expiring" then
			if p.kind == "greater" or p.kind == "rf" or p.kind == "aura" or p.kind == "seal" or p.kind == "blessing" then
				if p.state ~= "dead" then
					hudAction = p
					break
				end
			end
		end
	end
	if not hudAction then
		for _, p in ipairs(problems) do
			if p.state == "range" or p.state == "dead" then
				hudAction = p
				break
			end
		end
	end

	local castAction
	for _, p in ipairs(problems) do
		if (p.kind == "blessing" or p.kind == "greater") and (p.state == "missing" or p.state == "expiring") then
			castAction = p
			break
		end
	end
	castAction = castAction or SelectOrSelfBlessing()
	ArmButton(castAction)

	local healthy = #problems == 0

	if not DB.showHud or hideForPP or not enabled then
		PlaceClicker(false)
		PallyCueFrame:Hide()
		PallyCuePip:Hide()
		return
	end

	if DB.combatOnly and not InFight() then
		PlaceClicker(false)
		PallyCueFrame:Hide()
		PallyCuePip:Hide()
		return
	end

	if healthy then
		PlaceClicker(false)
		PallyCueFrame:Hide()
		if DB.hideHealthy then
			PallyCuePip:Show()
			PallyCuePip:ClearAllPoints()
			PallyCuePip:SetPoint(DB.point, UIParent, DB.relPoint, DB.x, DB.y)
		else
			PallyCuePip:Hide()
			PallyCueFrame:Show()
			PlaceClicker(true)
			PallyCueRebuffIcon:SetTexture("Interface\\Icons\\Spell_Holy_HolyGuidance")
			PallyCueRebuffBorder:SetVertexColor(ColorFor("ok"))
			PallyCueRebuffCount:SetText("")
			PallyCueLabel:SetText("Blessings up")
			PallyCueTimer:SetText("")
			UpdateList({})
		end
		return
	end

	PallyCuePip:Hide()
	PallyCueFrame:Show()
	PlaceClicker(true)
	local nextAction = hudAction or castAction
	if nextAction then
		PallyCueRebuffIcon:SetTexture(nextAction.icon)
		PallyCueRebuffBorder:SetVertexColor(ColorFor(nextAction.state))
		if nextAction.count and nextAction.count > 1 then
			PallyCueRebuffCount:SetText("x" .. nextAction.count)
		else
			PallyCueRebuffCount:SetText("")
		end
		PallyCueLabel:SetText(nextAction.label)
		if nextAction.state == "range" then
			PallyCueTimer:SetText("Out of range")
		elseif nextAction.remain then
			PallyCueTimer:SetText(FormatTime(nextAction.remain))
		elseif nextAction.state == "missing" then
			PallyCueTimer:SetText("Missing")
		else
			PallyCueTimer:SetText("")
		end
		Alert(nextAction)
	end
	UpdateList(problems)
end

function addon.Scan()
	if not enabled or not DB then
		return
	end
	addon.BuildRoster()
	local problems = addon.CollectProblems()
	addon.UpdateHUD(problems)
	addon.ScanHostileAggro()
end

function addon.QueueScan()
	if scanQueued then
		return
	end
	scanQueued = true
	C_Timer.After(SCAN_DELAY, function()
		scanQueued = false
		addon.Scan()
	end)
end

function addon.BindKeys()
	if InCombatLockdown() then
		return
	end
	ClearOverrideBindings(PallyCueRebuff)
	local key1, key2 = GetBindingKey("PALLYCUE_REBUFF")
	if key1 then
		SetOverrideBindingClick(PallyCueRebuff, false, key1, "PallyCueRebuff", "LeftButton")
	end
	if key2 then
		SetOverrideBindingClick(PallyCueRebuff, false, key2, "PallyCueRebuff", "LeftButton")
	end
end

function addon.ApplyPosition()
	if InCombatLockdown() then
		return
	end
	PallyCueFrame:ClearAllPoints()
	PallyCueFrame:SetPoint(DB.point, UIParent, DB.relPoint, DB.x, DB.y)
	PallyCueFrame:SetScale(DB.scale or 1.1)
	PallyCuePip:ClearAllPoints()
	PallyCuePip:SetPoint(DB.point, UIParent, DB.relPoint, DB.x, DB.y)
	PallyCuePip:SetScale(DB.scale or 1.1)
	if DB.locked then
		PallyCueFrame:SetMovable(false)
		PallyCuePip:SetMovable(false)
	else
		PallyCueFrame:SetMovable(true)
		PallyCuePip:SetMovable(true)
	end
end

function addon.OnDragStart(frame)
	if DB.locked or InCombatLockdown() then
		return
	end
	frame:StartMoving()
end

function addon.OnDragStop(frame)
	frame:StopMovingOrSizing()
	local point, _, relPoint, x, y = frame:GetPoint()
	DB.point, DB.relPoint, DB.x, DB.y = point, relPoint, x, y
	addon.ApplyPosition()
end

function addon.SavePipPosition()
	if InCombatLockdown() then
		return
	end
	local point, _, relPoint, x, y = PallyCuePip:GetPoint()
	DB.point, DB.relPoint, DB.x, DB.y = point, relPoint, x, y
	addon.ApplyPosition()
end

-- Setup UI (dark gamepad panel) ----------------------------------

local ROW_H = 30
local ROW_GAP = 3
local PANEL_W = 360
local setupButtons = {}
local setupCursorY = 0

local GOLD = { 0.95, 0.78, 0.28 }
local MUTED = { 0.62, 0.60, 0.56 }
local ONCOL = { 0.35, 0.85, 0.45 }
local OFFCOL = { 0.50, 0.48, 0.46 }
local ROW_IDLE = { 1, 1, 1, 0.045 }
local ROW_HOVER = { 0.95, 0.78, 0.28, 0.16 }

local TOGGLE_ICONS = {
	watchRF = "Interface\\Icons\\Spell_Holy_SealOfFury",
	showSolo = "Interface\\Icons\\Spell_Holy_DevotionAura",
	watchPets = "Interface\\Icons\\Ability_Hunter_BeastTaming",
	watchOutsiders = "Interface\\Icons\\Spell_Holy_FistOfJustice",
	showHud = "Interface\\Icons\\Spell_Holy_HolyGuidance",
	hideHealthy = "Interface\\Icons\\Spell_Holy_PowerWordShield",
	sound = "Interface\\Icons\\Spell_Holy_Silence",
	centerText = "Interface\\Icons\\INV_Misc_Note_01",
	combatOnly = "Interface\\Icons\\Ability_Warrior_OffensiveStance",
	tankAggro = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
	locked = "Interface\\Icons\\INV_Misc_Key_03",
	reset = "Interface\\Icons\\INV_Misc_Map_01",
	close = "Interface\\Icons\\Spell_Holy_HolyBolt",
}

local function BlessingList()
	local list = {}
	for id, name in pairs(blessingNames) do
		if name then
			list[#list + 1] = { id = id, name = name }
		end
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	return list
end

local function CycleBlessing(key)
	local list = BlessingList()
	if #list == 0 then
		return
	end
	local cur = DB[key]
	local idx = 1
	for i, v in ipairs(list) do
		if v.id == cur then
			idx = i
			break
		end
	end
	idx = idx + 1
	if idx > #list then
		idx = 1
	end
	DB[key] = list[idx].id
	addon.RefreshSetup()
	addon.QueueScan()
end

local function Paint(tex, color)
	tex:SetColorTexture(unpack(color))
end

local function MakeHeader(parent, text)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", 16, setupCursorY)
	label:SetText(text)
	label:SetTextColor(unpack(GOLD))
	setupCursorY = setupCursorY - 14
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", 16, setupCursorY + 3)
	line:SetPoint("TOPRIGHT", -16, setupCursorY + 3)
	line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.22)
	setupCursorY = setupCursorY - 4
end

-- col: 0 full width, 1 left, 2 right (same row as previous left)
local function MakeRow(parent, index, kind, key, title, col)
	col = col or 0
	local width, x
	if col == 0 then
		width, x = PANEL_W - 32, 16
	elseif col == 1 then
		width, x = 160, 16
	else
		width, x = 160, 184
	end
	local btn = CreateFrame("Button", "PallyCueSetupBtn" .. index, parent)
	btn:SetSize(width, ROW_H)
	btn:SetPoint("TOPLEFT", x, setupCursorY)
	btn:EnableMouse(true)
	btn:RegisterForClicks("AnyUp")

	btn.bg = btn:CreateTexture(nil, "BACKGROUND")
	btn.bg:SetAllPoints()
	Paint(btn.bg, ROW_IDLE)

	btn.accent = btn:CreateTexture(nil, "BORDER")
	btn.accent:SetWidth(3)
	btn.accent:SetPoint("TOPLEFT")
	btn.accent:SetPoint("BOTTOMLEFT")
	btn.accent:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.0)

	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetSize(22, 22)
	btn.icon:SetPoint("LEFT", 8, 0)
	btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 8, 0)
	btn.label:SetPoint("RIGHT", col == 0 and -100 or -34, 0)
	btn.label:SetJustifyH("LEFT")
	btn.label:SetText(title)

	btn.value = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	btn.value:SetPoint("RIGHT", -10, 0)
	btn.value:SetJustifyH("RIGHT")

	btn.kind, btn.key, btn.title = kind, key, title
	btn.OnCancelClick = function()
		parent:Hide()
	end
	btn:SetScript("OnEnter", function(self)
		Paint(self.bg, ROW_HOVER)
		self.accent:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.95)
	end)
	btn:SetScript("OnLeave", function(self)
		Paint(self.bg, ROW_IDLE)
		self.accent:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.0)
	end)
	btn:SetScript("OnClick", function()
		if kind == "cycle" then
			CycleBlessing(key)
		elseif kind == "toggle" then
			DB[key] = not DB[key]
			if key == "locked" or key == "hideHealthy" then
				addon.ApplyPosition()
			end
			addon.RefreshSetup()
			addon.QueueScan()
		elseif kind == "reset" then
			DB.point, DB.relPoint, DB.x, DB.y = "CENTER", "CENTER", 180, -40
			addon.ApplyPosition()
		elseif kind == "close" then
			parent:Hide()
		end
	end)

	if col ~= 1 then
		setupCursorY = setupCursorY - ROW_H - ROW_GAP
	end
	setupControls[key or ("row" .. index)] = btn
	setupButtons[#setupButtons + 1] = btn
	return btn
end

function addon.SetupConsolePort()
	if not ConsolePort or not ConsolePort.AddInterfaceCursorFrame then
		return
	end
	local f = PallyCueSetup
	if f.cpHooked then
		return
	end
	f.cpHooked = true
	f:HookScript("OnShow", function(frame)
		if PallyCueSetupDim then
			PallyCueSetupDim:Show()
		end
		ConsolePort:AddInterfaceCursorFrame(frame)
		local first = setupButtons[1]
		if first then
			if ConsolePort.SetCursorNode then
				ConsolePort:SetCursorNode(first, nil, true)
			elseif ConsolePort.SetCursorNodeIfActive then
				ConsolePort:SetCursorNodeIfActive(first)
			end
		end
	end)
	f:HookScript("OnHide", function(frame)
		if PallyCueSetupDim then
			PallyCueSetupDim:Hide()
		end
		ConsolePort:RemoveInterfaceCursorFrame(frame)
	end)
end

function addon.BuildSetup()
	local f = PallyCueSetup
	if f.built then
		return
	end
	f.built = true
	f:SetSize(PANEL_W, 380)
	f:SetFrameLevel(20)
	wipe(setupButtons)
	setupCursorY = 0

	if not f.CloseButton then
		local close = CreateFrame("Button", "PallyCueSetupCloseButton", f)
		close:SetSize(22, 22)
		close:SetPoint("TOPRIGHT", -8, -8)
		close:EnableMouse(true)
		close:RegisterForClicks("AnyUp")
		close.bg = close:CreateTexture(nil, "BACKGROUND")
		close.bg:SetAllPoints()
		close.bg:SetColorTexture(1, 1, 1, 0.06)
		close.label = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		close.label:SetPoint("CENTER", 0, 1)
		close.label:SetText("X")
		close.label:SetTextColor(unpack(GOLD))
		close:SetScript("OnEnter", function(self)
			self.bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.22)
			self.label:SetTextColor(1, 1, 1)
		end)
		close:SetScript("OnLeave", function(self)
			self.bg:SetColorTexture(1, 1, 1, 0.06)
			self.label:SetTextColor(unpack(GOLD))
		end)
		close:SetScript("OnClick", function()
			f:Hide()
		end)
		close.OnCancelClick = function()
			f:Hide()
		end
		f.CloseButton = close
	end

	if not _G.PallyCueSetupDim then
		local dim = CreateFrame("Frame", "PallyCueSetupDim", UIParent)
		dim:SetAllPoints()
		dim:SetFrameStrata("DIALOG")
		dim:SetFrameLevel(1)
		dim:EnableMouse(false)
		dim:Hide()
		local shade = dim:CreateTexture(nil, "BACKGROUND")
		shade:SetAllPoints()
		shade:SetColorTexture(0, 0, 0, 0.45)
	end

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.08, 0.08, 0.10, 0.97)

	local function Stroke(p1, p2, w, h)
		local t = f:CreateTexture(nil, "BORDER")
		t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.75)
		t:SetPoint(p1)
		t:SetPoint(p2)
		if w then
			t:SetWidth(w)
		end
		if h then
			t:SetHeight(h)
		end
	end
	Stroke("TOPLEFT", "TOPRIGHT", nil, 2)
	Stroke("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
	Stroke("TOPLEFT", "BOTTOMLEFT", 1, nil)
	Stroke("TOPRIGHT", "BOTTOMRIGHT", 1, nil)

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", 0, -10)
	title:SetText("PallyCue")
	title:SetTextColor(unpack(GOLD))

	local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sub:SetPoint("TOP", title, "BOTTOM", 0, 0)
	sub:SetText("Blessing setup")

	setupCursorY = -36
	MakeHeader(f, "BLESSINGS")
	MakeRow(f, 1, "cycle", "melee", "Melee", 0)
	MakeRow(f, 2, "cycle", "caster", "Caster", 0)
	MakeRow(f, 3, "cycle", "tank", "Tank", 0)

	MakeHeader(f, "OPTIONS")
	MakeRow(f, 4, "toggle", "watchRF", "Righteous Fury", 1)
	MakeRow(f, 5, "toggle", "hideHealthy", "Hide if healthy", 2)
	MakeRow(f, 6, "toggle", "showSolo", "Show solo", 1)
	MakeRow(f, 7, "toggle", "sound", "Sound", 2)
	MakeRow(f, 8, "toggle", "watchPets", "Watch pets", 1)
	MakeRow(f, 9, "toggle", "centerText", "Center text", 2)
	MakeRow(f, 14, "toggle", "watchOutsiders", "Watch target", 1)
	MakeRow(f, 13, "toggle", "tankAggro", "Tank aggro", 2)

	MakeHeader(f, "HUD")
	MakeRow(f, 15, "toggle", "showHud", "Show HUD", 1)
	MakeRow(f, 10, "toggle", "combatOnly", "Only in combat", 2)
	MakeRow(f, 11, "toggle", "locked", "Lock frame", 0)
	MakeRow(f, 12, "reset", "reset", "Reset HUD", 0)

	setupCursorY = setupCursorY - 6
	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOP", 0, setupCursorY)
	hint:SetText("D-pad  ·  A change  ·  B close")

	f:SetHeight(24 - setupCursorY)

	addon.SetupConsolePort()
end

function addon.RefreshSetup()
	if not PallyCueSetup.built then
		return
	end
	for _, btn in ipairs(setupButtons) do
		if btn.kind == "cycle" then
			btn.label:SetText(btn.title)
			btn.value:SetText(blessingNames[DB[btn.key]] or "?")
			btn.value:SetTextColor(unpack(GOLD))
			btn.icon:SetTexture(blessingIcons[DB[btn.key]] or "Interface\\Icons\\INV_Misc_QuestionMark")
		elseif btn.kind == "toggle" then
			local on = DB[btn.key]
			btn.label:SetText(btn.title)
			btn.value:SetText(on and "ON" or "OFF")
			btn.value:SetTextColor(unpack(on and ONCOL or OFFCOL))
			btn.icon:SetTexture(TOGGLE_ICONS[btn.key] or "Interface\\Icons\\INV_Misc_QuestionMark")
		elseif btn.kind == "reset" then
			btn.label:SetText("Reset HUD")
			btn.value:SetText("")
			btn.icon:SetTexture(TOGGLE_ICONS.reset)
		elseif btn.kind == "close" then
			btn.label:SetText("Close")
			btn.value:SetText("")
			btn.icon:SetTexture(TOGGLE_ICONS.close)
		end
	end
end

function addon.ToggleSetup()
	addon.BuildSetup()
	if PallyCueSetup:IsShown() then
		PallyCueSetup:Hide()
	else
		addon.RefreshSetup()
		PallyCueSetup:Show()
		if PallyCueSetupDim then
			PallyCueSetupDim:Show()
		end
		addon.SetupConsolePort()
	end
end

-- Events ---------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, ...)
	addon[event](addon, ...)
end)

function addon:ADDON_LOADED(name)
	if name ~= "PallyCue" then
		return
	end
	PallyCueDB = CopyDefaults(defaults, PallyCueDB)
	DB = PallyCueDB
	addon.InitSpells()
	events:RegisterEvent("PLAYER_LOGIN")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("GROUP_ROSTER_UPDATE")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("UNIT_AURA")
	events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	events:RegisterEvent("SPELLS_CHANGED")
	events:RegisterEvent("UPDATE_BINDINGS")
	pcall(events.RegisterEvent, events, "PLAYER_ROLES_ASSIGNED")
	events:RegisterEvent("UNIT_TARGET")
	events:RegisterEvent("PLAYER_TARGET_CHANGED")
	events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	pcall(events.RegisterEvent, events, "PLAYER_FOCUS_CHANGED")
	pcall(events.RegisterEvent, events, "UNIT_THREAT_SITUATION_UPDATE")
end

function addon:PLAYER_LOGIN()
	enabled = select(2, UnitClass("player")) == "PALADIN"
	addon.ApplyPosition()
	addon.BindKeys()
	if enabled then
		PallyCueRebuff:SetScript("PreClick", function()
			if InCombatLockdown() then
				return
			end
			if not armed.spell or armed.unit == "player" or IsSelectUnit(armed.unit) then
				ArmButton(SelectOrSelfBlessing())
			end
		end)
		addon.QueueScan()
		C_Timer.NewTicker(1, function()
			if enabled then
				addon.Scan()
			end
		end)
	else
		PallyCueFrame:Hide()
		PallyCuePip:Hide()
	end
end

function addon:PLAYER_ENTERING_WORLD()
	zoneAt = GetTime()
	addon.QueueScan()
end

function addon:GROUP_ROSTER_UPDATE()
	addon.QueueScan()
end

function addon:PLAYER_REGEN_ENABLED()
	addon.Scan()
	addon.BindKeys()
	addon.ApplyPosition()
end

function addon:PLAYER_REGEN_DISABLED()
	addon.QueueScan()
end

function addon:UNIT_AURA(unit)
	if not unit then
		return
	end
	if unit == "player" or unit:find("^party") or unit:find("^raid") or unit:find("pet") then
		addon.QueueScan()
		return
	end
	if DB and DB.watchOutsiders and (unit == "target" or unit == "focus" or unit == "mouseover") then
		addon.QueueScan()
	end
end

function addon:UNIT_SPELLCAST_SUCCEEDED(unit)
	if unit == "player" then
		addon.QueueScan()
	end
end

function addon:SPELLS_CHANGED()
	addon.QueueScan()
end

function addon:UPDATE_BINDINGS()
	addon.BindKeys()
end

function addon:PLAYER_ROLES_ASSIGNED()
	addon.QueueScan()
end

function addon:UNIT_TARGET()
	if DB and (DB.tankAggro or DB.watchOutsiders) then
		addon.QueueScan()
	end
end

function addon:PLAYER_TARGET_CHANGED()
	if DB and DB.watchOutsiders then
		addon.QueueScan()
	end
end

function addon:UPDATE_MOUSEOVER_UNIT()
	if DB and DB.watchOutsiders then
		addon.QueueScan()
	end
end

function addon:PLAYER_FOCUS_CHANGED()
	if DB and DB.watchOutsiders then
		addon.QueueScan()
	end
end

function addon:UNIT_THREAT_SITUATION_UPDATE()
	if DB and DB.tankAggro then
		addon.QueueScan()
	end
end

SLASH_PALLYCUE1 = "/pallycue"
SLASH_PALLYCUE2 = "/pc"
SlashCmdList.PALLYCUE = function(msg)
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
	if msg == "scan" then
		addon.Scan()
	elseif msg == "status" then
		print("PallyCue enabled=", tostring(enabled),
			"watchOutsiders=", DB and tostring(DB.watchOutsiders),
			"armed=", armed.spell, "on", armed.unit,
			"macro=", armed.macro,
			"btnShown=", PallyCueRebuff and PallyCueRebuff:IsShown(),
			"attr=", PallyCueRebuff and PallyCueRebuff:GetAttribute("macrotext"))
	elseif msg == "reset" then
		DB.point, DB.relPoint, DB.x, DB.y = "CENTER", "CENTER", 180, -40
		addon.ApplyPosition()
	else
		addon.ToggleSetup()
	end
end
