-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libdebuff ]]--
-- A pfUI library that detects and saves all ongoing debuffs of players, NPCs and enemies.
-- The functions UnitDebuff is exposed to the modules which allows to query debuffs like you
-- would on later expansions.
--
--  libdebuff:UnitDebuff(unit, id)
--    Returns debuff informations on the given effect of the specified unit.
--    name, rank, texture, stacks, dtype, duration, timeleft

-- return instantly if we're not on a vanilla client
if pfUI.client > 11200 then return end

-- return instantly when another libdebuff is already active
if pfUI.api.libdebuff then return end

-- fix a typo (missing $) in ruRU capture index
if GetLocale() == "ruRU" then
  SPELLREFLECTSELFOTHER = gsub(SPELLREFLECTSELFOTHER, "%%2s", "%%2%$s")
end

local libdebuff = CreateFrame("Frame", "pfdebuffsScanner", UIParent)
local scanner = libtipscan:GetScanner("libdebuff")
local _, class = UnitClass("player")
local lastspell

function libdebuff:GetDuration(effect, rank)
  if L["debuffs"][effect] then
    local rank = rank and tonumber((string.gsub(rank, RANK, ""))) or 0
    local rank = L["debuffs"][effect][rank] and rank or libdebuff:GetMaxRank(effect)
    local duration = L["debuffs"][effect][rank]

    if effect == L["dyndebuffs"]["Rupture"] then
      -- Rupture: +2 sec per combo point
      duration = duration + GetComboPoints()*2
    elseif effect == L["dyndebuffs"]["Kidney Shot"] then
      -- Kidney Shot: +1 sec per combo point
      duration = duration + GetComboPoints()*1
    elseif effect == L["dyndebuffs"]["Demoralizing Shout"] then
      -- Booming Voice: 10% per talent
      local _,_,_,_,count = GetTalentInfo(2,1)
      if count and count > 0 then duration = duration + ( duration / 100 * (count*10)) end
    elseif effect == L["dyndebuffs"]["Shadow Word: Pain"] then
      -- Improved Shadow Word: Pain: +3s per talent
      local _,_,_,_,count = GetTalentInfo(3,4)
      if count and count > 0 then duration = duration + count * 3 end
    elseif effect == L["dyndebuffs"]["Frostbolt"] then
      -- Permafrost: +1s per talent
      local _,_,_,_,count = GetTalentInfo(3,7)
      if count and count > 0 then duration = duration + count end
    elseif effect == L["dyndebuffs"]["Gouge"] then
      -- Improved Gouge: +.5s per talent
      local _,_,_,_,count = GetTalentInfo(2,1)
      if count and count > 0 then duration = duration + (count*.5) end
    end
    return duration
  else
    return 0
  end
end

function libdebuff:UpdateDuration(unit, unitlevel, effect, duration)
  if not unit or not effect or not duration then return end
  unitlevel = unitlevel or 0

  if libdebuff.objects[unit] and libdebuff.objects[unit][unitlevel] and libdebuff.objects[unit][unitlevel][effect] then
    libdebuff.objects[unit][unitlevel][effect].duration = duration
  end
end

function libdebuff:GetMaxRank(effect)
  local max = 0
  for id in pairs(L["debuffs"][effect]) do
    if id > max then max = id end
  end
  return max
end

function libdebuff:UpdateUnits()
  if not pfUI.uf or not pfUI.uf.target then return end
  pfUI.uf:RefreshUnit(pfUI.uf.target, "aura")
end

function libdebuff:AddPending(unit, unitlevel, effect, duration, caster)
  if not unit or duration <= 0 then return end
  if not L["debuffs"][effect] then return end
  if libdebuff.pending[3] then return end

  libdebuff.pending[1] = unit
  libdebuff.pending[2] = unitlevel or 0
  libdebuff.pending[3] = effect
  libdebuff.pending[4] = duration -- or libdebuff:GetDuration(effect)
  libdebuff.pending[5] = caster

  QueueFunction(libdebuff.PersistPending)
end

function libdebuff:RemovePending()
  libdebuff.pending[1] = nil
  libdebuff.pending[2] = nil
  libdebuff.pending[3] = nil
  libdebuff.pending[4] = nil
  libdebuff.pending[5] = nil
end

function libdebuff:PersistPending(effect)
  if not libdebuff.pending[3] then return end

  if libdebuff.pending[3] == effect or ( effect == nil and libdebuff.pending[3] ) then
    libdebuff:AddEffect(libdebuff.pending[1], libdebuff.pending[2], libdebuff.pending[3], libdebuff.pending[4], libdebuff.pending[5])
  end

  libdebuff:RemovePending()
end

function libdebuff:RevertLastAction()
  lastspell.start = lastspell.start_old
  lastspell.start_old = nil
  libdebuff:UpdateUnits()
end

function libdebuff:AddEffect(unit, unitlevel, effect, duration, caster)
  if not unit or not effect then return end
  unitlevel = unitlevel or 0
  if not libdebuff.objects[unit] then libdebuff.objects[unit] = {} end
  if not libdebuff.objects[unit][unitlevel] then libdebuff.objects[unit][unitlevel] = {} end
  if not libdebuff.objects[unit][unitlevel][effect] then libdebuff.objects[unit][unitlevel][effect] = {} end

  -- save current effect as lastspell
  lastspell = libdebuff.objects[unit][unitlevel][effect]

  libdebuff.objects[unit][unitlevel][effect].effect = effect
  libdebuff.objects[unit][unitlevel][effect].start_old = libdebuff.objects[unit][unitlevel][effect].start
  libdebuff.objects[unit][unitlevel][effect].start = GetTime()
  libdebuff.objects[unit][unitlevel][effect].duration = duration or libdebuff:GetDuration(effect)
  libdebuff.objects[unit][unitlevel][effect].caster = caster

  libdebuff:UpdateUnits()
end

-- scan for debuff application
libdebuff:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
libdebuff:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
libdebuff:RegisterEvent("CHAT_MSG_SPELL_FAILED_LOCALPLAYER")
libdebuff:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
libdebuff:RegisterEvent("PLAYER_TARGET_CHANGED")
libdebuff:RegisterEvent("SPELLCAST_STOP")
libdebuff:RegisterEvent("UNIT_AURA")

-- register seal handler
if class == "PALADIN" then
  libdebuff:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
end

-- Remove Pending
libdebuff.rp = { SPELLIMMUNESELFOTHER, IMMUNEDAMAGECLASSSELFOTHER,
  SPELLMISSSELFOTHER, SPELLRESISTSELFOTHER, SPELLEVADEDSELFOTHER,
  SPELLDODGEDSELFOTHER, SPELLDEFLECTEDSELFOTHER, SPELLREFLECTSELFOTHER,
  SPELLPARRIEDSELFOTHER, SPELLLOGABSORBSELFOTHER, SPELLFAILCASTSELF }

libdebuff.objects = {}
libdebuff.pending = {}

-- Gather Data by Events
libdebuff:SetScript("OnEvent", function()
  -- paladin seal refresh
  if event == "CHAT_MSG_COMBAT_SELF_HITS" then
    local hit = cmatch(arg1, COMBATHITSELFOTHER)
    local crit = cmatch(arg1, COMBATHITCRITSELFOTHER)
    if hit or crit then
      for seal in L["judgements"] do
        local name = UnitName("target")
        local level = UnitLevel("target")
        if name and libdebuff.objects[name] then
          if level and libdebuff.objects[name][level] and libdebuff.objects[name][level][seal] then
            libdebuff:AddEffect(name, level, seal)
          elseif libdebuff.objects[name][0] and libdebuff.objects[name][0][seal] then
            libdebuff:AddEffect(name, 0, seal)
          end
        end
      end
    end

  -- Add Combat Log
  elseif event == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE" or event == "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE" then
    local unit, effect = cmatch(arg1, AURAADDEDOTHERHARMFUL)
    if unit and effect then
      local unitlevel = UnitName("target") == unit and UnitLevel("target") or 0
      if not libdebuff.objects[unit] or not libdebuff.objects[unit][unitlevel] or not libdebuff.objects[unit][unitlevel][effect] then
        libdebuff:AddEffect(unit, unitlevel, effect)
      end
    end

  -- Add Missing Buffs by Iteration
  elseif ( event == "UNIT_AURA" and arg1 == "target" ) or event == "PLAYER_TARGET_CHANGED" then
    for i=1, 16 do
      local effect, rank, texture, stacks, dtype, duration, timeleft = libdebuff:UnitDebuff("target", i)

      -- abort when no further debuff was found
      if not texture then return end

      if texture and effect and effect ~= "" then
        -- don't overwrite existing timers
        local unitlevel = UnitLevel("target") or 0
        local unit = UnitName("target")
        if not libdebuff.objects[unit] or not libdebuff.objects[unit][unitlevel] or not libdebuff.objects[unit][unitlevel][effect] then
          libdebuff:AddEffect(unit, unitlevel, effect)
        end
      end
    end

  -- Update Pending Spells
  elseif event == "CHAT_MSG_SPELL_FAILED_LOCALPLAYER" or event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
    -- Remove pending spell
    for _, msg in pairs(libdebuff.rp) do
      local effect = cmatch(arg1, msg)
      if effect and libdebuff.pending[3] == effect then
        -- instant removal of the pending spell
        libdebuff:RemovePending()
        return
      elseif effect and lastspell and lastspell.start_old and lastspell.effect == effect then
        -- late removal of debuffs (e.g hunter arrows as they hit late)
        libdebuff:RevertLastAction()
        return
      end
    end
  elseif event == "SPELLCAST_STOP" then
    libdebuff:PersistPending()
  end
end)

-- Gather Data by User Actions
hooksecurefunc("CastSpell", function(id, bookType)
  local rawEffect, rank = libspell.GetSpellInfo(id, bookType)
  local duration = libdebuff:GetDuration(rawEffect, rank)
  libdebuff:AddPending(UnitName("target"), UnitLevel("target"), rawEffect, duration, "player")
end)

hooksecurefunc("CastSpellByName", function(effect, target)
  local rawEffect, rank = libspell.GetSpellInfo(effect)
  local duration = libdebuff:GetDuration(rawEffect, rank)
  libdebuff:AddPending(UnitName("target"), UnitLevel("target"), rawEffect, duration, "player")
end)

hooksecurefunc("UseAction", function(slot, target, button)
  if GetActionText(slot) or not IsCurrentAction(slot) then return end
  scanner:SetAction(slot)
  local rawEffect, rank = scanner:Line(1)
  local duration = libdebuff:GetDuration(rawEffect, rank)
  libdebuff:AddPending(UnitName("target"), UnitLevel("target"), rawEffect, duration, "player")
end)

function libdebuff:UnitDebuff(unit, id)
  local unitname = UnitName(unit)
  local unitlevel = UnitLevel(unit)
  local texture, stacks, dtype = UnitDebuff(unit, id)
  local duration, timeleft = nil, -1
  local rank = nil -- no backport
  local caster = nil -- experimental
  local effect

  if texture then
    scanner:SetUnitDebuff(unit, id)
    effect = scanner:Line(1) or ""
  end

  -- read level based debuff table
  local data = libdebuff.objects[unitname] and libdebuff.objects[unitname][unitlevel]
  data = data or libdebuff.objects[unitname] and libdebuff.objects[unitname][0]

  if data and data[effect] then
    if data[effect].duration and data[effect].start and data[effect].duration + data[effect].start > GetTime() then
      -- read valid debuff data
      duration = data[effect].duration
      timeleft = duration + data[effect].start - GetTime()
      caster = data[effect].caster
    else
      -- clean up invalid values
      data[effect] = nil
    end
  end

  return effect, rank, texture, stacks, dtype, duration, timeleft, caster
end

-- Pre-allocated cache for UnitOwnDebuff: scan once per unit, index O(1) thereafter
local owndebuff_results = {}
local owndebuff_count = 0
local owndebuff_unit = nil
local owndebuff_seen = {}

for i = 1, 16 do owndebuff_results[i] = {} end

function libdebuff:InvalidateOwnDebuffCache()
  owndebuff_unit = nil
end

function libdebuff:UnitOwnDebuff(unit, id)
  -- scan once per unit, cache filtered results for subsequent id lookups
  if owndebuff_unit ~= unit then
    owndebuff_unit = unit
    owndebuff_count = 0

    -- clear seen table (next-based iteration avoids pairs closure on some runtimes)
    for k in next, owndebuff_seen do owndebuff_seen[k] = nil end

    for i = 1, 16 do
      local effect, rank, texture, stacks, dtype, duration, timeleft, caster = libdebuff:UnitDebuff(unit, i)
      if effect and caster and caster == "player" and not owndebuff_seen[effect] then
        owndebuff_seen[effect] = true
        owndebuff_count = owndebuff_count + 1
        local r = owndebuff_results[owndebuff_count]
        r.effect = effect
        r.rank = rank
        r.texture = texture
        r.stacks = stacks
        r.dtype = dtype
        r.duration = duration
        r.timeleft = timeleft
        r.caster = caster
      end
    end
  end

  if id <= owndebuff_count then
    local r = owndebuff_results[id]
    return r.effect, r.rank, r.texture, r.stacks, r.dtype, r.duration, r.timeleft, r.caster
  end
end

function libdebuff:HasPlayerDebuffs(unitname, unitlevel)
  local data = libdebuff.objects[unitname]
  if not data then return false end

  local leveldata = data[unitlevel or 0]
  if not leveldata and data[0] then leveldata = data[0] end
  if not leveldata then return false end

  local now = GetTime()
  for _, info in pairs(leveldata) do
    if info.caster == "player" and info.start and info.duration
       and info.start + info.duration > now then
      return true
    end
  end
  return false
end

-- add libdebuff to pfUI API
pfUI.api.libdebuff = libdebuff
