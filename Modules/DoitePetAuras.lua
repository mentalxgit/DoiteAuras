---------------------------------------------------------------
-- DoitePetAuras.lua
-- Lightweight pet aura cache/helpers for trackpet aura mode
-- Please respect license note: Ask permission
-- WoW 1.12 | Lua 5.0
---------------------------------------------------------------

local DoitePetAuras = {
  buffs = {},
  debuffs = {},
  buffIds = {},
  debuffIds = {},
  petGuid = nil,
  initialized = false
}

_G["DoitePetAuras"] = DoitePetAuras

local function _ClearMap(t)
  for k in pairs(t) do
    t[k] = nil
  end
end

local function _GetSpellNameById(spellId)
  if not spellId then
    return nil
  end

  if GetSpellNameAndRankForId then
    local ok, name = pcall(GetSpellNameAndRankForId, spellId)
    if ok and type(name) == "string" and name ~= "" then
      return name
    end
  end

  if GetSpellRecField then
    local ok2, recName = pcall(GetSpellRecField, spellId, "name")
    if ok2 and type(recName) == "string" and recName ~= "" then
      return recName
    end
  end

  return nil
end

local function _ScanPetAuras()
  _ClearMap(DoitePetAuras.buffs)
  _ClearMap(DoitePetAuras.debuffs)
  _ClearMap(DoitePetAuras.buffIds)
  _ClearMap(DoitePetAuras.debuffIds)

  if not UnitExists("pet") then
    return
  end

  local i = 1
  while i <= 32 do
    local tex, stacks, spellId = UnitBuff("pet", i)
    if not tex then
      break
    end

    if spellId then
      DoitePetAuras.buffIds[spellId] = stacks or 1
      local name = _GetSpellNameById(spellId)
      if name then
        DoitePetAuras.buffs[name] = stacks or 1
      end
    end

    i = i + 1
  end

  i = 1
  while i <= 32 do
    local tex, stacks, _, spellId = UnitDebuff("pet", i)
    if not tex then
      break
    end

    if spellId then
      DoitePetAuras.debuffIds[spellId] = stacks or 1
      local name = _GetSpellNameById(spellId)
      if name then
        DoitePetAuras.debuffs[name] = stacks or 1
      end
    end

    i = i + 1
  end
end

local function _SetAuraBySpellId(spellId, stacks, wantDebuff)
  local sid = tonumber(spellId) or 0
  if sid <= 0 then
    return
  end

  local byId = wantDebuff and DoitePetAuras.debuffIds or DoitePetAuras.buffIds
  local byName = wantDebuff and DoitePetAuras.debuffs or DoitePetAuras.buffs

  if stacks and stacks > 0 then
    byId[sid] = stacks
  else
    byId[sid] = nil
  end

  local name = _GetSpellNameById(sid)
  if name then
    if stacks and stacks > 0 then
      byName[name] = stacks
    else
      byName[name] = nil
    end
  end
end

local function _ResetForPetChange()
  DoitePetAuras.petGuid = GetUnitGUID and GetUnitGUID("pet") or nil
  _ScanPetAuras()
end

function DoitePetAuras.Refresh()
  DoitePetAuras.petGuid = GetUnitGUID and GetUnitGUID("pet") or nil
  _ScanPetAuras()
end

function DoitePetAuras.CanTrack()
  return UnitExists("pet") and true or false
end

function DoitePetAuras.TargetIsPet()
  return UnitExists("pet") and UnitExists("target") and UnitIsUnit("target", "pet") and true or false
end

function DoitePetAuras.HasAura(auraName, auraSpellId, useSpellIdOnly, wantBuff, wantDebuff)
  if not DoitePetAuras.CanTrack() then
    return false
  end

  if useSpellIdOnly == true then
    local sid = tonumber(auraSpellId) or 0
    if sid <= 0 then
      return false
    end
    if wantBuff and DoitePetAuras.buffIds[sid] then
      return true
    end
    if wantDebuff and DoitePetAuras.debuffIds[sid] then
      return true
    end
    return false
  end

  if not auraName or auraName == "" then
    return false
  end

  if wantBuff and DoitePetAuras.buffs[auraName] then
    return true
  end
  if wantDebuff and DoitePetAuras.debuffs[auraName] then
    return true
  end

  return false
end

function DoitePetAuras.GetStacks(auraName, wantDebuff, auraSpellId, useSpellIdOnly)
  if not DoitePetAuras.CanTrack() then
    return nil
  end

  if useSpellIdOnly == true then
    local sid = tonumber(auraSpellId) or 0
    if sid <= 0 then
      return nil
    end
    if wantDebuff then
      return DoitePetAuras.debuffIds[sid]
    end
    return DoitePetAuras.buffIds[sid]
  end

  if not auraName or auraName == "" then
    return nil
  end

  if wantDebuff then
    return DoitePetAuras.debuffs[auraName]
  end
  return DoitePetAuras.buffs[auraName]
end

function DoitePetAuras.GetAuraRemainingSeconds(auraName, auraSpellId, useSpellIdOnly)
  if not DoiteTrack then
    return nil
  end

  if useSpellIdOnly == true then
    if DoiteTrack.GetAuraRemainingSecondsBySpellId then
      local rem = DoiteTrack:GetAuraRemainingSecondsBySpellId(auraSpellId, "pet")
      if rem and rem > 0 then
        return rem
      end
    end
  else
    if DoiteTrack.GetAuraRemainingSecondsByName then
      local rem2 = DoiteTrack:GetAuraRemainingSecondsByName(auraName, "pet")
      if rem2 and rem2 > 0 then
        return rem2
      end
    end
  end

  return nil
end

local f = CreateFrame("Frame", "DoitePetAurasEvents")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("UNIT_PET_GUID")
f:RegisterEvent("UNIT_PET")
f:RegisterEvent("BUFF_ADDED_OTHER")
f:RegisterEvent("DEBUFF_ADDED_OTHER")
f:RegisterEvent("BUFF_REMOVED_OTHER")
f:RegisterEvent("DEBUFF_REMOVED_OTHER")
f:RegisterEvent("UNIT_DIED")
f:RegisterEvent("PLAYER_DEAD")

f:SetScript("OnEvent", function()
  local evt = event
  local unit = arg1
  local guid = arg1
  local spellId = arg3
  local stackCount = tonumber(arg4) or 0
  local needsEval = false

  if evt == "PLAYER_ENTERING_WORLD" then
    _ResetForPetChange()
    needsEval = true
  elseif evt == "UNIT_PET_GUID" then
    local isPlayer = arg2
    if isPlayer == 1 and guid then
      local currentPetGuid = GetUnitGUID and GetUnitGUID("pet") or nil
      if currentPetGuid ~= DoitePetAuras.petGuid then
        _ResetForPetChange()
        needsEval = true
      end
    end
  elseif evt == "UNIT_PET" then
    if unit == "player" then
      _ResetForPetChange()
      needsEval = true
    end
  elseif evt == "BUFF_ADDED_OTHER" or evt == "DEBUFF_ADDED_OTHER" then
    if DoitePetAuras.petGuid and guid and guid == DoitePetAuras.petGuid then
      if stackCount <= 0 then
        stackCount = 1
      end
      _SetAuraBySpellId(spellId, stackCount, evt == "DEBUFF_ADDED_OTHER")
      needsEval = true
    end
  elseif evt == "BUFF_REMOVED_OTHER" or evt == "DEBUFF_REMOVED_OTHER" then
    if DoitePetAuras.petGuid and guid and guid == DoitePetAuras.petGuid then
      _SetAuraBySpellId(spellId, stackCount, evt == "DEBUFF_REMOVED_OTHER")
      needsEval = true
    end
  elseif evt == "UNIT_DIED" then
    if DoitePetAuras.petGuid and guid and guid == DoitePetAuras.petGuid then
      DoitePetAuras.petGuid = nil
      _ClearMap(DoitePetAuras.buffs)
      _ClearMap(DoitePetAuras.debuffs)
      _ClearMap(DoitePetAuras.buffIds)
      _ClearMap(DoitePetAuras.debuffIds)
      needsEval = true
    end
  elseif evt == "PLAYER_DEAD" then
    DoitePetAuras.petGuid = nil
    _ClearMap(DoitePetAuras.buffs)
    _ClearMap(DoitePetAuras.debuffs)
    _ClearMap(DoitePetAuras.buffIds)
    _ClearMap(DoitePetAuras.debuffIds)
    needsEval = true
  end

  if needsEval and DoiteConditions and DoiteConditions.EvaluateAll then
    DoiteConditions:EvaluateAll()
  end
end)

DoitePetAuras.initialized = true
_ResetForPetChange()
