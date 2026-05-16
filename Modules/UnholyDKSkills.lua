-- Modules/UnholyDKSkills.lua
-- 邪恶死亡骑士输出逻辑模块

local HekiliHelper = _G.HekiliHelper
if not HekiliHelper then return end

if not HekiliHelper.UnholyDKSkills then
    HekiliHelper.UnholyDKSkills = {}
end

local Module = HekiliHelper.UnholyDKSkills

-- 状态跟踪
Module.ttdData = { lastHP = 0, lastTime = 0, ttd = 999, guid = nil }
Module.HUDData = {}
Module.LastCastType = "BLOOD" -- 初始设为 BLOOD，使第一个推荐为 FROST
Module.EventFrame = nil
Module.gargoyleSummonTime = 0
Module.armySummonTime = 0
Module.lastPestilenceTime = 0
Module.lastIcyTouchTime = 0
Module.lastPlagueStrikeTime = 0

-- 技能ID定义
local ICY_TOUCH = 49909
local PLAGUE_STRIKE = 49921
local SCOURGE_STRIKE = 55271
local BLOOD_STRIKE = 49930
local BLOOD_BOIL = 49941
local DEATH_COIL = 49895
local DEATH_AND_DECAY = 49938
local PESTILENCE = 50842
local HORN_OF_WINTER = 57623
local BONE_SHIELD = 49222
local SUMMON_GARGOYLE = 49206
local BLOOD_TAP = 45529
local EMPOWER_RUNE_WEAPON = 47568
local ARMY_OF_THE_DEAD = 42650
local GHOUL_FRENZY = 63560
local RAISE_DEAD = 46584

-- 姿态/脸 (Presence)
local BLOOD_PRESENCE = 48263
local FROST_PRESENCE = 48265
local UNHOLY_PRESENCE = 48266

-- Buff/Debuff ID
local FROST_FEVER = 55095
local BLOOD_PLAGUE = 55078
local SUDDEN_DOOM = 49530
local HORN_OF_WINTER_BUFF = 57330
local GHOUL_FRENZY_BUFF = 63560 -- 狂乱BUFF
local DESOLATION_BUFF = 66803   -- 孤寂

-- 类型常量
local TYPE_FROST = "FROST"
local TYPE_UNHOLY = "UNHOLY"
local TYPE_BLOOD = "BLOOD"
local TYPE_FILLER = "FILLER" 

-- 技能与类型映射
local SpellToType = {
    [ICY_TOUCH] = TYPE_FROST,
    [PLAGUE_STRIKE] = TYPE_UNHOLY,
    [GHOUL_FRENZY] = TYPE_FILLER,
    [BONE_SHIELD] = TYPE_FILLER,
    [UNHOLY_PRESENCE] = TYPE_FILLER,
    [SCOURGE_STRIKE] = TYPE_UNHOLY,
    [DEATH_AND_DECAY] = TYPE_UNHOLY,
    [BLOOD_STRIKE] = TYPE_BLOOD,
    [PESTILENCE] = TYPE_BLOOD,
    [BLOOD_BOIL] = TYPE_BLOOD,
    [BLOOD_PRESENCE] = TYPE_FILLER,
    [DEATH_COIL] = TYPE_FILLER,
    [HORN_OF_WINTER] = TYPE_FILLER,
    [BLOOD_TAP] = TYPE_FILLER,
}

-- 序列顺序: 冰(FROST) -> 邪(UNHOLY) -> 血(BLOOD)
local NextTypeMap = {
    [TYPE_FROST] = TYPE_UNHOLY,
    [TYPE_UNHOLY] = TYPE_BLOOD,
    [TYPE_BLOOD] = TYPE_FROST,
}

-- 模块初始化
function Module:Initialize()
    if not Hekili or not Hekili.Update then return false end
    
    self:CreateStatusHUD()
    self:InitializeEvents()

    local success = HekiliHelper.HookUtils.Wrap(Hekili, "Update", function(oldFunc, self, ...)
        local result = oldFunc(self, ...)
        Module:InsertUnholySkills()
        return result
    end)
    
    return success
end
function Module:InitializeEvents()
    if self.EventFrame then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED") -- 注册脱战事件
    f:SetScript("OnEvent", function(_, event, unit, _, spellID)
        if event == "PLAYER_REGEN_ENABLED" then
            -- 脱离战斗，强制重置所有爆发计时器和符文序列
            self.gargoyleSummonTime = 0
            self.armySummonTime = 0
            self.LastCastType = "BLOOD" -- 重置为血，使得下一个推荐必定是冰
            return
        end
        if event == "PLAYER_TARGET_CHANGED" then

            self.lastPestilenceTime = 0
            self.lastIcyTouchTime = 0
            self.lastPlagueStrikeTime = 0
            return
        end
        if event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then
            local skillType = SpellToType[spellID]
            if skillType and skillType ~= TYPE_FILLER then
                self.LastCastType = skillType
            end
            
            if spellID == PESTILENCE then
                self.lastPestilenceTime = GetTime()
            elseif spellID == ICY_TOUCH then
                self.lastIcyTouchTime = GetTime()
            elseif spellID == PLAGUE_STRIKE then
                self.lastPlagueStrikeTime = GetTime()
            elseif spellID == SUMMON_GARGOYLE then
                self.gargoyleSummonTime = GetTime()
            elseif spellID == ARMY_OF_THE_DEAD then
                self.armySummonTime = GetTime()
            end
            self.LastCastSpellID = spellID
        end
    end)
    self.EventFrame = f
end

-- ============================================
-- 调试 HUD
-- ============================================

function Module:CreateStatusHUD()
    if self.HUDFrame then return end

    local frame = CreateFrame("Frame", "HekiliHelperUnholyHUD", UIParent, "BackdropTemplate")
    frame:SetSize(250, 450)
    frame:SetPoint("CENTER", -300, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.7)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOP", 0, -10)
    frame.title:SetText("邪DK逻辑监控 (可拖动)")

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.text:SetPoint("TOPLEFT", 10, -30)
    frame.text:SetJustifyH("LEFT")
    frame.text:SetJustifyV("TOP")
    frame.text:SetWidth(230)

    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(f) f:StopMovingOrSizing() end)

    self.HUDFrame = frame
    if HekiliHelper.DebugEnabled then frame:Show() else frame:Hide() end
end

function Module:UpdateHUDText()
    if not self.HUDFrame or not self.HUDFrame:IsShown() then return end
    
    local lines = {}
    
    local enemyCount8 = self:CountEnemiesInRange(8)
    local isAOE = enemyCount8 > 1
    local modeStr = isAOE and "|cFFFFFF00AOE|r" or "|cFF00FF00单体|r"
    
    local nextType = NextTypeMap[self.LastCastType] or "未知"
    local typeColor = { [TYPE_FROST] = "|cFF00FFFF冰|r", [TYPE_UNHOLY] = "|cFF00FF00邪|r", [TYPE_BLOOD] = "|cFFFF0000血|r" }

    table.insert(lines, string.format("|cFFFFFF00[全局状态]|r"))
    table.insert(lines, string.format("当前序列: %s -> %s", typeColor[self.LastCastType] or self.LastCastType, typeColor[nextType] or nextType))
    table.insert(lines, string.format("符文能量: %d", UnitPower("player")))
    table.insert(lines, string.format("当前模式: %s (敌人数:%d)", modeStr, enemyCount8))
    table.insert(lines, string.format("预计死亡时间(TTD): %.1fs", self:GetTTD()))
    
    table.insert(lines, "----------------------")

    for _, def in ipairs(self.SkillDefinitions) do
        local data = self.HUDData[def.actionName]
        if data then
            local color = data.should and "|cFF00FF00" or "|cFFFF0000"
            table.insert(lines, string.format("%s%s|r: %s", color, def.displayName, data.reason or "判定中"))
        end
    end

    self.HUDFrame.text:SetText(table.concat(lines, "\n"))
end

function Module:SetHUDReason(actionName, should, reason)
    self.HUDData[actionName] = { should = should, reason = reason }
end

-- ============================================
-- 核心判定工具
-- ============================================

function Module:GetUnitRange(unit)
    unit = unit or "target"
    if not UnitExists(unit) then return nil, nil end
    local rc = LibStub("LibRangeCheck-3.0", true) or LibStub("LibRangeCheck-2.0", true)
    if rc then return rc:GetRange(unit) end
    return nil, nil
end

function Module:UpdateTTD()
    local guid = UnitGUID("target")
    if not guid then 
        self.ttdData.ttd = 999
        self.ttdData.guid = nil
        return 
    end
    local hp = UnitHealth("target")
    local now = GetTime()
    if self.ttdData.guid ~= guid then
        self.ttdData.guid = guid
        self.ttdData.lastHP = hp
        self.ttdData.lastTime = now
        self.ttdData.ttd = 999
    else
        local diff = self.ttdData.lastHP - hp
        local timeDiff = now - self.ttdData.lastTime
        if timeDiff >= 1 and diff > 0 then
            local ps = diff / timeDiff
            self.ttdData.ttd = hp / ps
            self.ttdData.lastHP = hp
            self.ttdData.lastTime = now
        end
    end
end

function Module:GetTTD() return self.ttdData.ttd end

function Module:IsValidEnemy(unit)
    unit = unit or "target"
    return UnitExists(unit) and not UnitIsFriend("player", unit) and not UnitIsDead(unit)
end

function Module:IsBoss(unit)
    unit = unit or "target"
    if not UnitExists(unit) then return false end
    local level = UnitLevel(unit)
    local classification = UnitClassification(unit)
    return level == -1 or classification == "worldboss" or (classification == "elite" and level >= UnitLevel("player") + 3)
end

function Module:CountEnemiesInRange(range)
    local count = 0
    if self:IsValidEnemy("target") then
        local _, maxR = self:GetUnitRange("target")
        if maxR and maxR <= range then count = count + 1 end
    end
    for i = 1, 40 do
        local unit = "nameplate"..i
        if self:IsValidEnemy(unit) and not UnitIsUnit(unit, "target") then
            local _, maxR = self:GetUnitRange(unit)
            if maxR and maxR <= range then count = count + 1 end
        end
    end
    return count
end

function Module:IsSpellReady(id, p, ignoreGCD)
    local s, d = GetSpellCooldown(id)
    local gS, gD = GetSpellCooldown(61304)
    if not s or s == 0 then return true, "已就绪" end
    if not ignoreGCD and gS and gS > 0 and s == gS and d == gD then
        return true, "GCD中"
    end
    local cd = s + d - GetTime()
    if cd <= 0 then return true, "已就绪" end
    return false, string.format("CD(%.1fs)", cd)
end

function Module:HasBuff(unit, spellID)
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, id10, id11 = UnitBuff(unit, i)
        if not name then break end
        if id10 == spellID or id11 == spellID then return true end
    end
    return false
end

function Module:GetDebuffTimeLeft(unit, spellID)
    for i = 1, 40 do
        local name, _, _, _, _, expTime, _, _, _, id10, id11 = UnitDebuff(unit, i)
        if not name then break end
        if id10 == spellID or id11 == spellID then
            local now = GetTime()
            return (expTime > now) and (expTime - now) or 0
        end
    end
    return 0
end

function Module:GetBuffTimeLeft(unit, spellID)
    for i = 1, 40 do
        local name, _, _, _, _, expTime, _, _, _, id10, id11 = UnitBuff(unit, i)
        if not name then break end
        if id10 == spellID or id11 == spellID then
            local now = GetTime()
            return (expTime > now) and (expTime - now) or 0
        end
    end
    return 0
end

function Module:GetRuneCount(runeType)
    local count = 0
    for i = 1, 6 do
        local _, _, ready = GetRuneCooldown(i)
        if ready and (GetRuneType(i) == runeType or GetRuneType(i) == 4) then
            count = count + 1
        end
    end
    return count
end

function Module:IsPoolingForArmy()
    if GetShapeshiftForm() ~= 3 then return false end
    if not self:IsBoss("target") then return false end
    local ready = self:IsSpellReady(ARMY_OF_THE_DEAD, nil, true)
    return ready
end

function Module:CanConsumeRunes(b, u, f)
    local curB = self:GetRuneCount(1)
    local curU = self:GetRuneCount(2)
    local curF = self:GetRuneCount(3)
    
    if curB < b or curU < u or curF < f then return false end
    if not self:IsPoolingForArmy() then return true end
    if self:IsSpellReady(EMPOWER_RUNE_WEAPON, nil, true) then return true end
    
    local leaveB = 1
    if self:IsSpellReady(BLOOD_TAP, nil, true) then leaveB = 0 end
    
    if (curB - b) < leaveB then return false end
    if (curU - u) < 1 then return false end
    if (curF - f) < 1 then return false end
    
    return true
end

-- ============================================
-- 技能定义与逻辑
-- ============================================

Module.SkillDefinitions = {
    -- 基础维护 (最高优先级)
    { actionName = "raise_dead",          spellID = RAISE_DEAD,          basePriority = 0.5, checkFunc = function(self, p) return self:CheckRaiseDead(p) end,     displayName = "亡者复生" },
    
    -- 维护 (FILLER / 紧急辅助)
    { actionName = "empower_rune_weapon", spellID = EMPOWER_RUNE_WEAPON, basePriority = 1, checkFunc = function(self, p) return self:CheckERW(p) end, displayName = "符文武器增效" },
    { actionName = "blood_tap",           spellID = BLOOD_TAP,          basePriority = 2, checkFunc = function(self, p) return self:CheckBloodTap(p) end, displayName = "活力分流" },
    
    -- 爆发 (FILLER)
    { actionName = "summon_gargoyle", spellID = SUMMON_GARGOYLE, basePriority = 5, checkFunc = function(self, p) return self:CheckGargoyle(p) end,   displayName = "召唤天鬼" },
    { actionName = "army_of_the_dead", spellID = ARMY_OF_THE_DEAD, basePriority = 6, checkFunc = function(self, p) return self:CheckArmy(p) end,       displayName = "大军" },

    -- 基础 Buff 维护 (高优先级，除非Boss即将死亡)
    { actionName = "bone_shield",    spellID = BONE_SHIELD,    basePriority = 7, checkFunc = function(self, p) return self:CheckBoneShield(p) end,    displayName = "白骨之盾" },
    { actionName = "ghoul_frenzy",   spellID = GHOUL_FRENZY,   basePriority = 8, checkFunc = function(self, p) return self:CheckGhoulFrenzy(p) end,   displayName = "狂乱" },

    -- AOE 核心
    { actionName = "death_and_decay", spellID = DEATH_AND_DECAY, basePriority = 9, checkFunc = function(self, p) return self:CheckDnD(p) end,         displayName = "枯萎凋零" },

    -- 核心序列优先级: 冰触 > 暗打 > 血打
    { actionName = "icy_touch",      spellID = ICY_TOUCH,      basePriority = 10, checkFunc = function(self, p) return self:CheckIcyTouch(p) end,    displayName = "冰冷触摸" },
    { actionName = "plague_strike",  spellID = PLAGUE_STRIKE,  basePriority = 11, checkFunc = function(self, p) return self:CheckPlagueStrike(p) end, displayName = "暗影打击" },
    { actionName = "blood_strike",   spellID = BLOOD_STRIKE,   basePriority = 12, checkFunc = function(self, p) return self:CheckBloodStrike(p) end,   displayName = "血液打击" },
    
    -- 进阶消耗与脸切换
    { actionName = "scourge_strike",  spellID = SCOURGE_STRIKE,  basePriority = 20, checkFunc = function(self, p) return self:CheckScourgeStrike(p) end, displayName = "天灾打击" },
    { actionName = "unholy_presence", spellID = UNHOLY_PRESENCE, basePriority = 25, checkFunc = function(self, p) return self:CheckUnholyPresence(p) end, displayName = "切邪脸" },
    { actionName = "pestilence",      spellID = PESTILENCE,      basePriority = 26, checkFunc = function(self, p) return self:CheckPestilence(p) end,    displayName = "传染" },
    { actionName = "blood_boil",      spellID = BLOOD_BOIL,      basePriority = 27, checkFunc = function(self, p) return self:CheckBloodBoil(p) end,     displayName = "血沸" },
    { actionName = "blood_presence",   spellID = BLOOD_PRESENCE,   basePriority = 28, checkFunc = function(self, p) return self:CheckBloodPresence(p) end,  displayName = "切血脸" },
    
    -- 填充 (FILLER)
    { actionName = "horn_of_winter", spellID = HORN_OF_WINTER, basePriority = 29, checkFunc = function(self, p) return self:CheckHornOfWinter(p) end, displayName = "寒冬号角" },
    { actionName = "death_coil",     spellID = DEATH_COIL,     basePriority = 30, checkFunc = function(self, p) return self:CheckDeathCoil(p) end,    displayName = "凋零缠绕" },
}

function Module:CheckRaiseDead(p)
    if UnitExists("pet") and not UnitIsDead("pet") then self:SetHUDReason("raise_dead", false, "已有宠物"); return false end
    local ready, reason = self:IsSpellReady(RAISE_DEAD, p)
    self:SetHUDReason("raise_dead", ready, ready and "补招" or reason)
    return ready, "player"
end

function Module:CheckERW(p)
    local ready, reason = self:IsSpellReady(EMPOWER_RUNE_WEAPON, p)
    if not ready then self:SetHUDReason("empower_rune_weapon", false, reason); return false end
    
    if self:IsPoolingForArmy() then
        if self:GetRuneCount(1) < 1 or self:GetRuneCount(2) < 1 or self:GetRuneCount(3) < 1 then
            self:SetHUDReason("empower_rune_weapon", true, "大军蓄能-使用增效")
            return true, "player"
        end
    end
    
    local should = self:GetRuneCount(1) == 0 and self:GetRuneCount(2) == 0 and self:GetRuneCount(3) == 0
    self:SetHUDReason("empower_rune_weapon", should, should and "符文全空-补" or "尚有符文")
    return should, "player"
end

function Module:CheckBloodTap(p)
    local ready, reason = self:IsSpellReady(BLOOD_TAP, p)
    if not ready then self:SetHUDReason("blood_tap", false, reason); return false end

    if self:IsPoolingForArmy() then
        if self:GetRuneCount(1) < 1 then
            self:SetHUDReason("blood_tap", true, "大军蓄能-分流")
            return true, "player"
        end
    end

    if self:GetRuneCount(2) == 0 and (not self:HasBuff("player", BONE_SHIELD) or not self:HasBuff("pet", GHOUL_FRENZY_BUFF)) then
        self:SetHUDReason("blood_tap", true, "润滑-补Buff")
        return true, "player"
    end
    local nextType = NextTypeMap[self.LastCastType]
    if nextType == TYPE_UNHOLY and GetShapeshiftForm() ~= 3 and self:GetRuneCount(2) == 0 then
        self:SetHUDReason("blood_tap", true, "润滑-切脸")
        return true, "player"
    end
    self:SetHUDReason("blood_tap", false, "无需分流")
    return false
end

function Module:CheckBoneShield(p)
    if self:HasBuff("player", BONE_SHIELD) then self:SetHUDReason("bone_shield", false, "已有BUFF"); return false end
    if self:IsBoss("target") and self:GetTTD() < 5 then self:SetHUDReason("bone_shield", false, "斩杀期跳过"); return false end
    local ready, reason = self:IsSpellReady(BONE_SHIELD, p)
    if not ready or not self:CanConsumeRunes(0, 1, 0) then self:SetHUDReason("bone_shield", false, "冷却/没符文"); return false end
    self:SetHUDReason("bone_shield", true, "补BUFF")
    return true, "player"
end

function Module:CheckGhoulFrenzy(p)
    if self:HasBuff("pet", GHOUL_FRENZY_BUFF) then self:SetHUDReason("ghoul_frenzy", false, "已有狂乱"); return false end
    if self:IsBoss("target") and self:GetTTD() < 5 then self:SetHUDReason("ghoul_frenzy", false, "斩杀期跳过"); return false end
    local ready, reason = self:IsSpellReady(GHOUL_FRENZY, p)
    if not ready or not self:CanConsumeRunes(0, 1, 0) then self:SetHUDReason("ghoul_frenzy", false, "冷却/没符文"); return false end
    self:SetHUDReason("ghoul_frenzy", true, "补狂乱")
    return true, "pet"
end

function Module:CheckDnD(p)
    local ready, reason = self:IsSpellReady(DEATH_AND_DECAY, p)
    if not ready then self:SetHUDReason("death_and_decay", false, reason); return false end
    if not self:CanConsumeRunes(1, 1, 1) then self:SetHUDReason("death_and_decay", false, "缺少符文/大军蓄能"); return false end
    
    if self:CountEnemiesInRange(8) > 1 and not self:IsBoss("target") then 
        self:SetHUDReason("death_and_decay", true, "AOE优先")
        return true, "player" 
    end
    
    -- 单体/Boss战序列逻辑：必须双病齐全才能打凋零
    local frostFeverLeft = self:GetDebuffTimeLeft("target", FROST_FEVER)
    local bloodPlagueLeft = self:GetDebuffTimeLeft("target", BLOOD_PLAGUE)
    if frostFeverLeft <= 0 or bloodPlagueLeft <= 0 then
        self:SetHUDReason("death_and_decay", false, "等待双病")
        return false
    end

    local should = NextTypeMap[self.LastCastType] == TYPE_UNHOLY
    self:SetHUDReason("death_and_decay", should, should and "序列推荐" or "等待序列")
    return should, "player"
end

function Module:CheckIcyTouch(p)
    if self:GetDebuffTimeLeft("target", FROST_FEVER) <= 2 then
        local ready, reason = self:IsSpellReady(ICY_TOUCH, p)
        if ready and self:CanConsumeRunes(0, 0, 1) then self:SetHUDReason("icy_touch", true, "补疾病"); return true, "target" end
    end
    if NextTypeMap[self.LastCastType] ~= TYPE_FROST then self:SetHUDReason("icy_touch", false, "等待序列"); return false end
    local ready, reason = self:IsSpellReady(ICY_TOUCH, p)
    local canCast = ready and self:CanConsumeRunes(0, 0, 1)
    self:SetHUDReason("icy_touch", canCast, canCast and "已就绪" or "大军蓄能/CD")
    return canCast, "target"
end

function Module:CheckPlagueStrike(p)
    if self:GetDebuffTimeLeft("target", BLOOD_PLAGUE) <= 2 then
        local ready, reason = self:IsSpellReady(PLAGUE_STRIKE, p)
        if ready and self:CanConsumeRunes(0, 1, 0) then self:SetHUDReason("plague_strike", true, "补疾病"); return true, "target" end
    end
    if NextTypeMap[self.LastCastType] ~= TYPE_UNHOLY then self:SetHUDReason("plague_strike", false, "等待序列"); return false end
    local ready, reason = self:IsSpellReady(PLAGUE_STRIKE, p)
    local canCast = ready and self:CanConsumeRunes(0, 1, 0)
    self:SetHUDReason("plague_strike", canCast, canCast and "已就绪" or "大军蓄能/CD")
    return canCast, "target"
end

function Module:CheckBloodStrike(p)
    if NextTypeMap[self.LastCastType] ~= TYPE_BLOOD then self:SetHUDReason("blood_strike", false, "等待序列"); return false end
    if self:CountEnemiesInRange(8) > 1 then self:SetHUDReason("blood_strike", false, "AOE禁用"); return false end
    if self:GetBuffTimeLeft("player", DESOLATION_BUFF) > 5 then self:SetHUDReason("blood_strike", false, "孤寂充足"); return false end
    local ready, reason = self:IsSpellReady(BLOOD_STRIKE, p)
    local canCast = ready and self:CanConsumeRunes(1, 0, 0)
    self:SetHUDReason("blood_strike", canCast, canCast and "已就绪" or "大军蓄能/CD")
    return canCast, "target"
end

function Module:CheckScourgeStrike(p)
    if NextTypeMap[self.LastCastType] ~= TYPE_UNHOLY then self:SetHUDReason("scourge_strike", false, "等待序列"); return false end
    local ready, reason = self:IsSpellReady(SCOURGE_STRIKE, p)
    local should = ready and self:CanConsumeRunes(0, 1, 1)
    self:SetHUDReason("scourge_strike", should, should and "泄符文" or reason)
    return should, "target"
end

function Module:CheckUnholyPresence(p)
    local def
    for _, d in ipairs(self.SkillDefinitions) do
        if d.actionName == "unholy_presence" then def = d; break end
    end

    local timeSinceGargoyle = GetTime() - self.gargoyleSummonTime

    if GetShapeshiftForm() == 3 then 
        if def then def.basePriority = 25 end
        self:SetHUDReason("unholy_presence", false, "已在绿脸")
        return false 
    end
    
    if self.gargoyleSummonTime > 0 and timeSinceGargoyle < 30 then
        if timeSinceGargoyle <= 2.5 then
            if def then def.basePriority = 4 end
            self:SetHUDReason("unholy_presence", true, "天鬼快照-紧急切绿")
        else
            if def then def.basePriority = 25 end
            self:SetHUDReason("unholy_presence", true, "天鬼存在-保持绿脸")
        end
        return true, "player"
    end

    if def then def.basePriority = 25 end
    self:SetHUDReason("unholy_presence", false, "无天鬼-无需绿脸")
    return false
end

function Module:CheckBloodPresence(p)
    local def
    for _, d in ipairs(self.SkillDefinitions) do
        if d.actionName == "blood_presence" then def = d; break end
    end

    local timeSinceGargoyle = GetTime() - self.gargoyleSummonTime

    if GetShapeshiftForm() == 1 then 
        if def then def.basePriority = 28 end
        self:SetHUDReason("blood_presence", false, "已在红脸")
        return false 
    end

    if self.gargoyleSummonTime == 0 or timeSinceGargoyle >= 30 then
        if def then def.basePriority = 28 end
        self:SetHUDReason("blood_presence", true, "无天鬼-切红脸")
        return true, "player"
    end

    if def then def.basePriority = 28 end
    self:SetHUDReason("blood_presence", false, "天鬼存在-无需红脸")
    return false
end

function Module:CheckPestilence(p)
    if self:CountEnemiesInRange(8) <= 1 then self:SetHUDReason("pestilence", false, "单体禁用"); return false end
    if NextTypeMap[self.LastCastType] ~= TYPE_BLOOD then self:SetHUDReason("pestilence", false, "等待血阶段"); return false end
    if self.lastPestilenceTime > math.max(self.lastIcyTouchTime, self.lastPlagueStrikeTime) then self:SetHUDReason("pestilence", false, "已传染"); return false end
    local ready, reason = self:IsSpellReady(PESTILENCE, p)
    local canCast = ready and self:CanConsumeRunes(1, 0, 0)
    self:SetHUDReason("pestilence", canCast, canCast and "已就绪" or "大军蓄能/CD")
    return canCast, "target"
end

function Module:CheckBloodBoil(p)
    local e8 = self:CountEnemiesInRange(8)
    if e8 <= 1 and self:GetBuffTimeLeft("player", DESOLATION_BUFF) <= 5 then self:SetHUDReason("blood_boil", false, "需优先打血打"); return false end
    if NextTypeMap[self.LastCastType] ~= TYPE_BLOOD then self:SetHUDReason("blood_boil", false, "等待序列"); return false end
    local ready, reason = self:IsSpellReady(BLOOD_BOIL, p)
    local canCast = ready and self:CanConsumeRunes(1, 0, 0)
    self:SetHUDReason("blood_boil", canCast, canCast and "已就绪" or "大军蓄能/CD")
    return canCast, "player"
end

function Module:CheckHornOfWinter(p)
    local ready, reason = self:IsSpellReady(HORN_OF_WINTER, p)
    if not ready then self:SetHUDReason("horn_of_winter", false, reason); return false end
    if not UnitAffectingCombat("player") then
        local h = self:HasBuff("player", HORN_OF_WINTER_BUFF)
        self:SetHUDReason("horn_of_winter", not h, h and "已有BUFF" or "脱战补")
        return not h, "player"
    end
    local empty = self:GetRuneCount(1) == 0 and self:GetRuneCount(2) == 0 and self:GetRuneCount(3) == 0
    self:SetHUDReason("horn_of_winter", empty, empty and "能量填充" or "尚有符文")
    return empty, "player"
end

function Module:CheckGargoyle(p)
    if not self:IsBoss("target") then self:SetHUDReason("summon_gargoyle", false, "非Boss"); return false end
    local ready, reason = self:IsSpellReady(SUMMON_GARGOYLE, p)
    if not ready or UnitPower("player") < 60 or self:GetTTD() < 20 then self:SetHUDReason("summon_gargoyle", false, reason or "条件不足"); return false end
    local db = HekiliHelper.DB.profile.unholyDK
    local buffs = { strsplit(",", (db and db.gargoyleSnapshotBuffs or ""):gsub("%s+", "")) }
    for _, b in ipairs(buffs) do
        if b ~= "" and not (tonumber(b) and self:HasBuff("player", tonumber(b)) or self:HasBuffByName("player", b)) then
            self:SetHUDReason("summon_gargoyle", false, "等待快照:"..b); return false
        end
    end
    self:SetHUDReason("summon_gargoyle", true, "快照完成"); return true, "player"
end

function Module:CheckArmy(p)
    if not self:IsBoss("target") then self:SetHUDReason("army_of_the_dead", false, "非Boss"); return false end
    local ready, reason = self:IsSpellReady(ARMY_OF_THE_DEAD, p)
    if not ready or self:GetTTD() < 40 then self:SetHUDReason("army_of_the_dead", false, reason or "条件不足"); return false end
    if GetShapeshiftForm() ~= 3 then self:SetHUDReason("army_of_the_dead", false, "等待绿脸"); return false end
    if not self:HasBuff("player", 2825) and not self:HasBuff("player", 32182) then self:SetHUDReason("army_of_the_dead", false, "等待嗜血"); return false end
    local db = HekiliHelper.DB.profile.unholyDK
    local buffs = { strsplit(",", (db and db.armySnapshotBuffs or ""):gsub("%s+", "")) }
    for _, b in ipairs(buffs) do
        if b ~= "" and not (tonumber(b) and self:HasBuff("player", tonumber(b)) or self:HasBuffByName("player", b)) then
            self:SetHUDReason("army_of_the_dead", false, "等待快照:"..b); return false
        end
    end
    self:SetHUDReason("army_of_the_dead", true, "快照完成"); return true, "player"
end

function Module:CheckDeathCoil(p)
    local ready, reason = self:IsSpellReady(DEATH_COIL, p)
    if not ready then self:SetHUDReason("death_coil", false, reason); return false end
    
    if self:HasBuff("player", SUDDEN_DOOM) then self:SetHUDReason("death_coil", true, "触发末日"); return true, "target" end
    local rp = UnitPower("player")
    if rp < 40 then self:SetHUDReason("death_coil", false, "能量不足"); return false end
    if self:GetRuneCount(1) == 0 and self:GetRuneCount(2) == 0 and self:GetRuneCount(3) == 0 then self:SetHUDReason("death_coil", true, "真空填充"); return true, "target" end
    local _, maxR = self:GetUnitRange("target")
    if rp > 80 and maxR and maxR > 8 then self:SetHUDReason("death_coil", true, "远程泄能"); return true, "target" end
    if rp >= 110 then self:SetHUDReason("death_coil", true, "能量溢出"); return true, "target" end
    self:SetHUDReason("death_coil", false, "低优先级"); return false
end

function Module:HasBuffByName(unit, name)
    for i = 1, 40 do local n = UnitBuff(unit, i); if n == name then return true end end
    return false
end

-- ============================================
-- 插入队列
-- ============================================

function Module:InsertUnholySkills()
    if self.HUDFrame then if HekiliHelper.DebugEnabled then self.HUDFrame:Show() else self.HUDFrame:Hide() end end
    if not Hekili or not Hekili.DisplayPool then return end
    self:UpdateTTD()
    local db = HekiliHelper.DB and HekiliHelper.DB.profile and HekiliHelper.DB.profile.unholyDK
    local isEnabled = db and db.enabled

    local activeSkills = {}
    for _, def in ipairs(self.SkillDefinitions) do
        local isKnown = IsSpellKnown(def.spellID) or def.actionName:find("presence")
        if isKnown then
            local should, target = def.checkFunc(self, def.basePriority)
            if isEnabled and should then table.insert(activeSkills, def) end
        end
    end
    self:UpdateHUDText()
    if not isEnabled then return end
    table.sort(activeSkills, function(a, b) return a.basePriority < b.basePriority end)
    for dispName, UI in pairs(Hekili.DisplayPool) do
        local lowerName = dispName:lower()
        if (lowerName == "primary" or lowerName == "aoe") and UI.Active and UI.alpha > 0 then
            local Queue = UI.Recommendations
            if Queue then
                for i = 1, 10 do if Queue[i] and Queue[i].isUnholySkill then Queue[i] = nil end end
                local skillsFound = 0
                for _, skillDef in ipairs(activeSkills) do
                    if skillsFound < 4 then
                        skillsFound = skillsFound + 1
                        local ability = Hekili.Class.abilities[skillDef.actionName]
                        if not ability then
                            local n, _, t = GetSpellInfo(skillDef.spellID)
                            if n then Hekili.Class.abilities[skillDef.actionName] = { key = skillDef.actionName, name = n, texture = t, id = skillDef.spellID, cast = 0, gcd = "off" }; ability = Hekili.Class.abilities[skillDef.actionName] end
                        end
                        if ability then
                            local slot = Queue[skillsFound] or {}
                            slot.actionName, slot.actionID, slot.texture, slot.isUnholySkill, slot.display, slot.time, slot.exact_time = skillDef.actionName, skillDef.spellID, ability.texture, true, dispName, 0, GetTime()
                            Queue[skillsFound] = slot; UI.NewRecommendations = true
                        end
                    end
                end
            end
        end
    end
end
