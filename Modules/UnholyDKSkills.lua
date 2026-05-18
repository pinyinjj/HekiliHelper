-- Modules/UnholyDKSkills.lua
-- 邪恶死亡骑士输出逻辑模块

local HekiliHelper = _G.HekiliHelper
if not HekiliHelper then return end

if not HekiliHelper.UnholyDKSkills then
    HekiliHelper.UnholyDKSkills = {}
end

local Module = HekiliHelper.UnholyDKSkills

-- 状态跟踪
Module.ttdData = {} -- 修改为支持多目标的表 [guid] = { lastHP, lastTime, ttd }
Module.HUDData = {}
Module.LastCastType = "BLOOD" -- 初始设为 BLOOD，使第一个推荐为 FROST
Module.EventFrame = nil
Module.gargoyleSummonTime = 0
Module.armySummonTime = 0
Module.lastPestilenceTime = 0
Module.lastIcyTouchTime = 0
Module.lastPlagueStrikeTime = 0
Module.CurrentQueue = {}
Module.lastBloodTapReason = ""
Module.lastBloodTapLogTime = 0

-- 技能ID定义
local ICY_TOUCH = 49909
local PLAGUE_STRIKE = 49921
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
local MIND_FREEZE = 47528

-- 姿态/脸 (Presence)
local BLOOD_PRESENCE = 48263
local FROST_PRESENCE = 48265
local UNHOLY_PRESENCE = 48266

-- Buff/Debuff ID
local FROST_FEVER = 55095
local BLOOD_PLAGUE = 55078

-- 符文类型常量 (Blizzard API: 1-血, 2-冰, 3-邪, 4-死)
local RUNE_BLOOD = 1
local RUNE_FROST = 2
local RUNE_UNHOLY = 3
local RUNE_DEATH = 4
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
    [DEATH_AND_DECAY] = TYPE_BLOOD,
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
    frame:SetSize(250, 500)
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
    
    local curB = self:GetRuneCount(RUNE_BLOOD)
    local curF = self:GetRuneCount(RUNE_FROST)
    local curU = self:GetRuneCount(RUNE_UNHOLY)

    local nextType = NextTypeMap[self.LastCastType] or TYPE_FROST
    local seqStr = ""
    if nextType == TYPE_FROST then seqStr = "->|cFF00FFFF冰|r  |cFF00FF00邪|r  |cFFFF0000血|r"
    elseif nextType == TYPE_UNHOLY then seqStr = "  |cFF00FFFF冰|r ->|cFF00FF00邪|r  |cFFFF0000血|r"
    elseif nextType == TYPE_BLOOD then seqStr = "  |cFF00FFFF冰|r  |cFF00FF00邪|r ->|cFFFF0000血|r"
    else seqStr = "未知"
    end

    table.insert(lines, string.format("|cFFFFFF00[当前推送 (Queue)]|r"))
    local hasRec = false
    if self.CurrentQueue and #self.CurrentQueue > 0 then
        for i, info in ipairs(self.CurrentQueue) do
            table.insert(lines, string.format("  Slot%d. |cFF00FF00%s|r", info.slot, info.name))
            hasRec = true
        end
    end
    if not hasRec then table.insert(lines, "  |cFF888888Hekili队列为空|r") end

    table.insert(lines, "----------------------")
    table.insert(lines, string.format("|cFFFFFF00[全局状态]|r"))
    table.insert(lines, string.format("|cFF00FFFF冰:%d|r  |cFF00FF00邪:%d|r  |cFFFF0000血:%d|r (含万能)", curF, curU, curB))
    table.insert(lines, string.format("能量: %d  TTD: %.1fs", UnitPower("player"), self:GetTTD()))
    table.insert(lines, string.format("序列: %s (Last:%s)", seqStr, self.LastCastType))
    
    table.insert(lines, "----------------------")
    table.insert(lines, string.format("|cFFFFFF00[所有技能明细]|r"))
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

function Module:UpdateTTD(unit)
    unit = unit or "target"
    local guid = UnitGUID(unit)
    if not guid then return end
    
    local hp = UnitHealth(unit)
    local now = GetTime()
    local data = self.ttdData[guid]
    
    if not data then
        self.ttdData[guid] = { lastHP = hp, lastTime = now, ttd = 999 }
    else
        local diff = data.lastHP - hp
        local timeDiff = now - data.lastTime
        if timeDiff >= 1 then
            if diff > 0 then
                local ps = diff / timeDiff
                data.ttd = hp / ps
            end
            data.lastHP = hp
            data.lastTime = now
        end
    end
end

function Module:GetUnitTTD(unit)
    local guid = UnitGUID(unit)
    if not guid or not self.ttdData[guid] then return 999 end
    return self.ttdData[guid].ttd
end

function Module:GetTTD() return self:GetUnitTTD("target") end

function Module:IsValidEnemy(unit)
    unit = unit or "target"
    if not UnitExists(unit) or UnitIsFriend("player", unit) or UnitIsDead(unit) then return false end
    
    -- 图腾过滤：如果名称包含“图腾”，则视为无效敌对目标
    local name = UnitName(unit)
    if name and name:find("图腾") then return false end
    
    return true
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
    -- 清理过期的 TTD 数据 (超过 10 秒没更新的)
    local now = GetTime()
    for guid, data in pairs(self.ttdData) do
        if now - data.lastTime > 10 then self.ttdData[guid] = nil end
    end

    if self:IsValidEnemy("target") then
        local _, maxR = self:GetUnitRange("target")
        if maxR and maxR <= range then 
            self:UpdateTTD("target")
            count = count + 1 
        end
    end
    for i = 1, 40 do
        local unit = "nameplate"..i
        if self:IsValidEnemy(unit) and not UnitIsUnit(unit, "target") then
            local _, maxR = self:GetUnitRange(unit)
            if maxR and maxR <= range then
                self:UpdateTTD(unit)
                count = count + 1
            end
        end
    end
    return count
end

function Module:GetRuneCount(runeType)
    local count = 0
    local now = GetTime()
    for i = 1, 6 do
        local start, duration, ready = GetRuneCooldown(i)
        local rType = GetRuneType(i)
        local isReady = (ready or not start or start == 0 or (start + duration - now) <= 0.1)
        if isReady and (rType == runeType or rType == 4) then
            count = count + 1
        end
    end
    return count
end

function Module:IsSpellReady(id, p, ignoreGCD)
    local s, d = GetSpellCooldown(id)
    local _, gD = GetSpellCooldown(61304)
    
    local isRuneSpell = (id == ICY_TOUCH or id == PLAGUE_STRIKE or 
                         id == BLOOD_STRIKE or id == BLOOD_BOIL or id == PESTILENCE or id == DEATH_AND_DECAY or id == ARMY_OF_THE_DEAD)

    if isRuneSpell then
        if id ~= DEATH_AND_DECAY and id ~= ARMY_OF_THE_DEAD then
            if not ignoreGCD and gD and gD > 0 and d > 0 and d <= gD then
                return true, "GCD中"
            end
            return true, "已就绪"
        else
            if not s or s == 0 or d <= 1.5 or (gD and d <= gD) then return true, "已就绪" end
            if d > 1.5 and d <= 11 then return true, "符文等待" end
            local cd = s + d - GetTime()
            if cd <= 0.1 then return true, "已就绪" end
            return false, string.format("CD(%.1fs)", cd)
        end
    end

    if not s or s == 0 or (d > 0 and gD > 0 and d <= gD) then 
        return true, "已就绪" 
    end
    
    local cd = s + d - GetTime()
    if cd <= 0.1 then return true, "已就绪" end
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

function Module:IsArmyTime()
    if not self:IsBoss("target") then return false, "非Boss" end
    local ready = self:IsSpellReady(ARMY_OF_THE_DEAD, nil, true)
    if not ready then return false, "条件不足" end
    if self:GetTTD() < 40 then return false, "条件不足" end
    if GetShapeshiftForm() ~= 3 then return false, "等待绿脸" end
    if not self:HasBuff("player", 2825) and not self:HasBuff("player", 32182) then return false, "等待嗜血" end
    
    local db = HekiliHelper.DB.profile.unholyDK
    local buffs = self:GetBuffList(db and db.armySnapshotBuffs or "")
    for _, b in ipairs(buffs) do
        if b ~= "" and not (tonumber(b) and self:HasBuff("player", tonumber(b)) or self:HasBuffByName("player", b)) then
            return false, "等待快照:"..b
        end
    end
    return true, "时机已到"
end

function Module:CanConsumeRunes(b, u, f)
    if b > 0 and self:GetRuneCount(RUNE_BLOOD) < b then return false end
    if u > 0 and self:GetRuneCount(RUNE_UNHOLY) < u then return false end
    if f > 0 and self:GetRuneCount(RUNE_FROST) < f then return false end
    return true
end

-- ============================================
-- 技能定义与逻辑
-- ============================================

Module.SkillDefinitions = {
    -- 工具类 (最高优先级)
    { actionName = "mind_freeze",         spellID = MIND_FREEZE,         basePriority = 0.1, checkFunc = function(self, p) return self:CheckMindFreeze(p) end,     displayName = "心灵冰冻" },

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

function Module:CheckMindFreeze(p)
    if not self:IsBoss("target") then self:SetHUDReason("mind_freeze", false, "非Boss"); return false end
    
    local ready, reason = self:IsSpellReady(MIND_FREEZE, p, true) -- 忽略GCD，因为心灵冰冻不在GCD内
    if not ready then self:SetHUDReason("mind_freeze", false, reason); return false end

    -- 检查是否正在施法且可打断
    local name, _, _, _, _, _, _, notInterruptible = UnitCastingInfo("target")
    if not name then
        name, _, _, _, _, _, _, notInterruptible = UnitChannelInfo("target")
    end

    if name and not notInterruptible then
        self:SetHUDReason("mind_freeze", true, "打断 Boss: "..name)
        return true, "target"
    end

    self:SetHUDReason("mind_freeze", false, "无施法/不可打断")
    return false
end

function Module:CheckRaiseDead(p)
    if UnitExists("pet") and not UnitIsDead("pet") then self:SetHUDReason("raise_dead", false, "已有宠物"); return false end
    local ready, reason = self:IsSpellReady(RAISE_DEAD, p)
    self:SetHUDReason("raise_dead", ready, ready and "补招" or reason)
    return ready, "player"
end

function Module:CheckERW(p)
    local ready, reason = self:IsSpellReady(EMPOWER_RUNE_WEAPON, p)
    if not ready then self:SetHUDReason("empower_rune_weapon", false, reason); return false end

    if self:IsArmyTime() then
        if self:GetRuneCount(RUNE_BLOOD) < 1 or self:GetRuneCount(RUNE_UNHOLY) < 1 or self:GetRuneCount(RUNE_FROST) < 1 then
            self:SetHUDReason("empower_rune_weapon", true, "大军时机-使用增效")
            return true, "player"
        end
    end

    self:SetHUDReason("empower_rune_weapon", false, "非大军/无需补")
    return false
end
function Module:LogBloodTap(reason)
    local now = GetTime()
    if reason ~= self.lastBloodTapReason or (now - self.lastBloodTapLogTime > 2) then
        self.lastBloodTapReason = reason
        self.lastBloodTapLogTime = now
        
        local curB = self:GetRuneCount(RUNE_BLOOD)
        local curF = self:GetRuneCount(RUNE_FROST)
        local curU = self:GetRuneCount(RUNE_UNHOLY)
        local form = GetShapeshiftForm()
        local lastType = self.LastCastType
        
        local msg = string.format("活力分流推荐: %s | 姿态: %d | 符文: B%d F%d U%d | 上次类型: %s", 
            reason, form, curB, curF, curU, lastType)
        
        -- 如果是补Buff或补病，追加双病时间
        if reason:find("补Buff") or reason:find("补病") then
            local ffTime = self:GetDebuffTimeLeft("target", FROST_FEVER)
            local bpTime = self:GetDebuffTimeLeft("target", BLOOD_PLAGUE)
            msg = msg .. string.format(" | 双病: F%.1fs B%.1fs", ffTime, bpTime)
        end
        
        HekiliHelper:AddDebugMessage(msg)
    end
end

function Module:CheckBloodTap(p)
    if not self:IsBoss("target") then self:SetHUDReason("blood_tap", false, "非Boss禁用"); return false end
    local ready, reason = self:IsSpellReady(BLOOD_TAP, p)
    if not ready then self:SetHUDReason("blood_tap", false, reason); return false end

    local should = false
    local recReason = ""

    -- 1. 大军时机 (缺任何一个符文都可以分流来救急)
    if self:IsArmyTime() then
        if self:GetRuneCount(RUNE_BLOOD) < 1 or self:GetRuneCount(RUNE_FROST) < 1 or self:GetRuneCount(RUNE_UNHOLY) < 1 then
            should = true
            recReason = "大军时机-分流"
        end
    end

    -- 2. 补Buff
    if not should and self:GetRuneCount(RUNE_UNHOLY) == 0 then
        if not self:HasBuff("player", BONE_SHIELD) then
            should = true
            recReason = "润滑-补骨盾"
        elseif self:GetBuffTimeLeft("pet", GHOUL_FRENZY_BUFF) <= 3 then
            should = true
            recReason = "润滑-补狂乱"
        end
    end

    -- 3. 补病润滑 (仅在疾病断掉且没符文补时触发)
    if not should then
        local ffTime = self:GetDebuffTimeLeft("target", FROST_FEVER)
        local bpTime = self:GetDebuffTimeLeft("target", BLOOD_PLAGUE)
        if (ffTime <= 0 and self:GetRuneCount(RUNE_FROST) == 0) then
            should = true
            recReason = "润滑-补病-冰"
        elseif (bpTime <= 0 and self:GetRuneCount(RUNE_UNHOLY) == 0) then
            should = true
            recReason = "润滑-补病-邪"
        end
    end

    -- 4. 切脸润滑
    if not should then
        local isUnholyWanted = self:CheckUnholyPresence(p)
        local isBloodWanted = self:CheckBloodPresence(p)

        if isBloodWanted and GetShapeshiftForm() ~= 1 and self:GetRuneCount(RUNE_BLOOD) == 0 then
            should = true
            recReason = "润滑-切红脸"
            self.BoostPresencePriority = "BLOOD" 
        elseif isUnholyWanted and GetShapeshiftForm() ~= 3 and self:GetRuneCount(RUNE_UNHOLY) == 0 then
            should = true
            recReason = "润滑-切绿脸"
            self.BoostPresencePriority = "UNHOLY" 
        end
    end

    if should then
        self:SetHUDReason("blood_tap", true, recReason)
        if HekiliHelper.DebugEnabled then
            self:LogBloodTap(recReason)
        end
        return true, "player"
    end

    self.BoostPresencePriority = nil
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
    if self:GetBuffTimeLeft("pet", GHOUL_FRENZY_BUFF) > 3 then self:SetHUDReason("ghoul_frenzy", false, "狂乱充足"); return false end
    if self:IsBoss("target") and self:GetTTD() < 5 then self:SetHUDReason("ghoul_frenzy", false, "斩杀期跳过"); return false end
    local ready, reason = self:IsSpellReady(GHOUL_FRENZY, p)
    if not ready or not self:CanConsumeRunes(0, 1, 0) then self:SetHUDReason("ghoul_frenzy", false, "冷却/没符文"); return false end
    self:SetHUDReason("ghoul_frenzy", true, "补狂乱")
    return true, "pet"
end

function Module:CheckDnD(p)
    local ready, reason = self:IsSpellReady(DEATH_AND_DECAY, p)
    if not ready then self:SetHUDReason("death_and_decay", false, reason); return false end
    if not self:CanConsumeRunes(1, 1, 1) then self:SetHUDReason("death_and_decay", false, "缺少符文"); return false end
    
    -- 距离检查：确保目标在近战范围内 (LibRangeCheck 近战 bucket 的 maxR 通常为 5)
    if self:IsValidEnemy("target") then
        local _, maxR = self:GetUnitRange("target")
        if maxR and maxR > 5 then
            self:SetHUDReason("death_and_decay", false, "距离过远(>5码)")
            return false
        end
    end

    if self:CountEnemiesInRange(8) > 1 and not self:IsBoss("target") then 
        self:SetHUDReason("death_and_decay", true, "AOE优先")
        return true, "player" 
    end
    
    -- 单体/Boss战序列逻辑：必须双病齐全 且 孤寂Buff存在，且都有一定剩余时间
    local frostFeverLeft = self:GetDebuffTimeLeft("target", FROST_FEVER)
    local bloodPlagueLeft = self:GetDebuffTimeLeft("target", BLOOD_PLAGUE)
    local desolationLeft = self:GetBuffTimeLeft("player", DESOLATION_BUFF)

    if frostFeverLeft <= 1.5 or bloodPlagueLeft <= 1.5 then
        self:SetHUDReason("death_and_decay", false, "疾病即将到期/缺失")
        return false
    end

    if desolationLeft <= 1.5 then
        self:SetHUDReason("death_and_decay", false, "孤寂即将到期/缺失")
        return false
    end

    -- 移除序列检查，好了就用
    self:SetHUDReason("death_and_decay", true, "好了就用")
    return true, "player"
end

function Module:CheckIcyTouch(p)
    local ready, reason = self:IsSpellReady(ICY_TOUCH, p)
    local hasRunes = self:CanConsumeRunes(0, 0, 1)

    if self:GetDebuffTimeLeft("target", FROST_FEVER) <= 0 then
        if ready and hasRunes then 
            self:SetHUDReason("icy_touch", true, "无疾病强制")
            return true, "target" 
        elseif not hasRunes then
            self:SetHUDReason("icy_touch", false, "需强制-缺符文")
            return false
        end
    end

    if NextTypeMap[self.LastCastType] ~= TYPE_FROST then 
        self:SetHUDReason("icy_touch", false, "等待序列")
        return false 
    end

    local canCast = ready and hasRunes
    self:SetHUDReason("icy_touch", canCast, canCast and "序列就绪" or "无符文/CD")
    return canCast, "target"
end

function Module:CheckPlagueStrike(p)
    local ready, reason = self:IsSpellReady(PLAGUE_STRIKE, p)
    local hasRunes = self:CanConsumeRunes(0, 1, 0)

    if NextTypeMap[self.LastCastType] ~= TYPE_UNHOLY then 
        self:SetHUDReason("plague_strike", false, "等待序列")
        return false 
    end

    local canCast = ready and hasRunes
    self:SetHUDReason("plague_strike", canCast, canCast and "序列就绪" or "无符文/CD")
    return canCast, "target"
end

function Module:CheckBloodStrike(p)
    if NextTypeMap[self.LastCastType] ~= TYPE_BLOOD then self:SetHUDReason("blood_strike", false, "等待序列"); return false end
    -- 核心逻辑：如果没有孤寂，或者孤寂即将到期，则必须打血打（即使在 AOE 情况下）
    if self:GetBuffTimeLeft("player", DESOLATION_BUFF) > 5 then self:SetHUDReason("blood_strike", false, "孤寂充足"); return false end
    
    local ready, reason = self:IsSpellReady(BLOOD_STRIKE, p)
    local canCast = ready and self:CanConsumeRunes(1, 0, 0)
    self:SetHUDReason("blood_strike", canCast, canCast and "维持孤寂" or "无符文/CD")
    return canCast, "target"
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
    
    local should = false
    local reason = ""
    local priority = 25

    if self.gargoyleSummonTime > 0 and timeSinceGargoyle < 32 then
        should = true
        if timeSinceGargoyle <= 2.5 then
            priority = 4
            reason = "天鬼快照-紧急切绿"
        else
            priority = 25
            reason = "天鬼存在-保持绿脸"
        end
    end

    -- 动态优先级提升：如果活力分流是为了切绿脸而交的
    if self.BoostPresencePriority == "UNHOLY" then
        should = true
        priority = 3 -- 提升至极高优先级，确保死符文被用于切脸
        reason = "分流润滑-强制切绿"
    end

    if def then def.basePriority = priority end
    self:SetHUDReason("unholy_presence", should, reason ~= "" and reason or "无天鬼-无需绿脸")
    return should, "player"
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

    local should = false
    local reason = ""
    local priority = 28

    if self.gargoyleSummonTime == 0 or timeSinceGargoyle >= 32 then
        should = true
        priority = 11.5 -- 优先级高于血打(12)，确保尽快切回红脸
        reason = "无天鬼-切红脸"
    end

    -- 动态优先级提升：如果活力分流是为了切红脸而交的
    if self.BoostPresencePriority == "BLOOD" then
        should = true
        priority = 3 -- 提升至极高优先级
        reason = "分流润滑-强制切红"
    end

    if def then def.basePriority = priority end
    self:SetHUDReason("blood_presence", should, reason ~= "" and reason or "天鬼存在-无需红脸")
    return should, "player"
end

function Module:CheckPestilence(p)
    -- 1. 范围检查 (严格按照要求设为 8 码)
    if self:CountEnemiesInRange(8) <= 1 then self:SetHUDReason("pestilence", false, "单体禁用"); return false end
    
    -- 2. 检查主目标是否有病可传 (必须双病齐全)
    local tFF = self:GetDebuffTimeLeft("target", FROST_FEVER)
    local tBP = self:GetDebuffTimeLeft("target", BLOOD_PLAGUE)
    if tFF <= 1.5 or tBP <= 1.5 then self:SetHUDReason("pestilence", false, "主目标缺病/快到期"); return false end

    -- 必须孤寂安全 (降低为 3s)
    if self:GetBuffTimeLeft("player", DESOLATION_BUFF) <= 3 then self:SetHUDReason("pestilence", false, "需优先血打补孤寂"); return false end

    -- 3. 序列检查
    if NextTypeMap[self.LastCastType] ~= TYPE_BLOOD then self:SetHUDReason("pestilence", false, "等待血阶段"); return false end
    
    -- 4. 扫描周边敌人，寻找“值得传染”的目标
    local foundValidSecondary = false
    for i = 1, 40 do
        local u = "nameplate"..i
        if self:IsValidEnemy(u) and not UnitIsUnit(u, "target") then
            local _, maxR = self:GetUnitRange(u)
            if maxR and maxR <= 8 then -- 严格 8 码
                local ff = self:GetDebuffTimeLeft(u, FROST_FEVER)
                local bp = self:GetDebuffTimeLeft(u, BLOOD_PLAGUE)
                
                if ff <= 1.5 or bp <= 1.5 then
                    -- 存活判定：非 Boss 必须判断 TTD > 5s
                    if self:IsBoss(u) or (self:GetUnitTTD(u) > 5) then
                        foundValidSecondary = true
                        break
                    end
                end
            end
        end
    end
    
    if not foundValidSecondary then self:SetHUDReason("pestilence", false, "无需扩散/周边将死"); return false end

    -- 5. 资源检查
    local ready, reason = self:IsSpellReady(PESTILENCE, p)
    local canCast = ready and self:CanConsumeRunes(1, 0, 0)
    self:SetHUDReason("pestilence", canCast, canCast and "扩散疾病" or "无符文/CD")
    return canCast, "target"
end

function Module:CheckBloodBoil(p)
    if NextTypeMap[self.LastCastType] ~= TYPE_BLOOD then self:SetHUDReason("blood_boil", false, "等待序列"); return false end
    
    -- 核心逻辑：只有在孤寂 Buff 充足时 (降低为 3s)，才把血符文花在血沸上
    if self:GetBuffTimeLeft("player", DESOLATION_BUFF) <= 3 then self:SetHUDReason("blood_boil", false, "需优先打血打"); return false end

    local ready, reason = self:IsSpellReady(BLOOD_BOIL, p)
    local canCast = ready and self:CanConsumeRunes(1, 0, 0)
    self:SetHUDReason("blood_boil", canCast, canCast and "消耗血符文" or "无符文/CD")
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
    local empty = self:GetRuneCount(RUNE_BLOOD) == 0 and self:GetRuneCount(RUNE_UNHOLY) == 0 and self:GetRuneCount(RUNE_FROST) == 0
    self:SetHUDReason("horn_of_winter", empty, empty and "能量填充" or "尚有符文")
    return empty, "player"
end

function Module:CheckGargoyle(p)
    if not self:IsBoss("target") then self:SetHUDReason("summon_gargoyle", false, "非Boss"); return false end
    local ready, reason = self:IsSpellReady(SUMMON_GARGOYLE, p)
    if not ready or UnitPower("player") < 60 or self:GetTTD() < 20 then self:SetHUDReason("summon_gargoyle", false, reason or "条件不足"); return false end
    
    -- 嗜血/英勇强制逻辑：如果嗜血剩余时间 <= 30秒，无视快照直接召唤
    local bloodlustTime = math.max(self:GetBuffTimeLeft("player", 2825), self:GetBuffTimeLeft("player", 32182))
    if bloodlustTime > 0 and bloodlustTime <= 30 then
        self:SetHUDReason("summon_gargoyle", true, "嗜血即将结束-强制")
        return true, "player"
    end

    local db = HekiliHelper.DB.profile.unholyDK
    local buffs = self:GetBuffList(db and db.gargoyleSnapshotBuffs or "")
    for _, b in ipairs(buffs) do
        if b ~= "" and not (tonumber(b) and self:HasBuff("player", tonumber(b)) or self:HasBuffByName("player", b)) then
            self:SetHUDReason("summon_gargoyle", false, "等待快照:"..b); return false
        end
    end
    self:SetHUDReason("summon_gargoyle", true, "快照完成"); return true, "player"
end

function Module:CheckArmy(p)
    local isTime, reason = self:IsArmyTime()
    if not isTime then self:SetHUDReason("army_of_the_dead", false, reason); return false end
    
    if self:GetRuneCount(RUNE_BLOOD) >= 1 and self:GetRuneCount(RUNE_UNHOLY) >= 1 and self:GetRuneCount(RUNE_FROST) >= 1 then
        self:SetHUDReason("army_of_the_dead", true, "快照完成"); return true, "player"
    else
        self:SetHUDReason("army_of_the_dead", false, "等待增效/符文"); return false
    end
end

function Module:CheckDeathCoil(p)
    local def
    for _, d in ipairs(self.SkillDefinitions) do
        if d.actionName == "death_coil" then def = d; break end
    end

    local ready, reason = self:IsSpellReady(DEATH_COIL, p)
    if not ready then 
        if def then def.basePriority = 30 end
        self:SetHUDReason("death_coil", false, reason)
        return false 
    end
    
    local rp = UnitPower("player")
    
    if rp >= 100 then
        if def then def.basePriority = 9.5 end
        self:SetHUDReason("death_coil", true, "高能泄泻")
        return true, "target"
    end
    
    if def then def.basePriority = 30 end
    
    local isVacuum = self:GetRuneCount(RUNE_BLOOD) == 0 and self:GetRuneCount(RUNE_UNHOLY) == 0 and self:GetRuneCount(RUNE_FROST) == 0
    if not isVacuum then
        self:SetHUDReason("death_coil", false, "尚有符文")
        return false
    end

    local s, d = GetSpellCooldown(SUMMON_GARGOYLE)
    local gOnCD = (s and s > 0 and d > 1.5)
    
    local threshold = 80
    if gOnCD then
        if self:IsBoss("target") then
            threshold = 60
        else
            threshold = 40
        end
    end

    if rp >= threshold then
        self:SetHUDReason("death_coil", true, "真空填充(>="..threshold..")")
        return true, "target"
    end
    
    self:SetHUDReason("death_coil", false, "能量不足(<"..threshold..")")
    return false
end

function Module:HasBuffByName(unit, name)
    for i = 1, 40 do local n = UnitBuff(unit, i); if n == name then return true end end
    return false
end

function Module:GetBuffList(str)
    if not str or str == "" then return {} end
    local buffs = {}
    if str:find(",") then
        for s in str:gmatch("[^,]+") do
            s = s:gsub("^%s*(.-)%s*$", "%1")
            if s ~= "" then table.insert(buffs, s) end
        end
    else
        for s in str:gmatch("%S+") do
            table.insert(buffs, s)
        end
    end
    return buffs
end

-- ============================================
-- 插入队列
-- ============================================

function Module:InsertUnholySkills()
    if self.HUDFrame then if HekiliHelper.DebugEnabled then self.HUDFrame:Show() else self.HUDFrame:Hide() end end
    if not Hekili or not Hekili.DisplayPool then return end
    
    -- 每帧开始计算前，必须重置动态优先级标记，防止切脸死循环
    self.BoostPresencePriority = nil
    
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
    
    -- 记录当前推送给 Hekili 的队列，用于 HUD 显示
    self.CurrentQueue = {}
    table.sort(activeSkills, function(a, b) return a.basePriority < b.basePriority end)
    
    local hudPopulated = false
    if isEnabled then
        for dispName, UI in pairs(Hekili.DisplayPool) do
            local lowerName = dispName:lower()
            if (lowerName == "primary" or lowerName == "aoe") and UI.Active and UI.alpha > 0 then
                local Queue = UI.Recommendations
                if Queue then
                    -- 清理旧的推荐
                    for i = 1, 10 do if Queue[i] and Queue[i].isUnholySkill then Queue[i] = nil end end
                    
                    local skillsFound = 0
                    for _, skillDef in ipairs(activeSkills) do
                        if skillsFound < 4 then
                            skillsFound = skillsFound + 1
                            local ability = Hekili.Class.abilities[skillDef.actionName]
                            if not ability then
                                local n, _, t = GetSpellInfo(skillDef.spellID)
                                if n then 
                                    Hekili.Class.abilities[skillDef.actionName] = { 
                                        key = skillDef.actionName, name = n, texture = t, id = skillDef.spellID, cast = 0, gcd = "off" 
                                    }
                                    ability = Hekili.Class.abilities[skillDef.actionName]
                                end
                            end
                            if ability then
                                local slot = Queue[skillsFound] or {}
                                slot.actionName = skillDef.actionName
                                slot.actionID = skillDef.spellID
                                slot.texture = ability.texture
                                slot.isUnholySkill = true
                                slot.display = dispName
                                slot.time = 0
                                slot.exact_time = GetTime()
                                slot.resources = nil 
                                
                                Queue[skillsFound] = slot
                                UI.NewRecommendations = true
                                
                                if not hudPopulated then
                                    table.insert(self.CurrentQueue, { slot = skillsFound, name = skillDef.displayName })
                                end
                            end
                        end
                    end
                    hudPopulated = true
                end
            end
        end
    end
    
    self:UpdateHUDText()
end
