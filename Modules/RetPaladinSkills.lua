-- Modules/RetPaladinSkills.lua
-- 惩戒骑士技能插入模块


local HekiliHelper = _G.HekiliHelper
if not HekiliHelper then return end

if not HekiliHelper.RetPaladinSkills then
    HekiliHelper.RetPaladinSkills = {}
end

local Module = HekiliHelper.RetPaladinSkills

-- TTD 跟踪数据
Module.ttdData = { lastHP = 0, lastTime = 0, ttd = 999, guid = nil }

-- 模块初始化
function Module:Initialize()
    if not Hekili or not Hekili.Update then return false end
    
    self:CreateStatusHUD()

    local success = HekiliHelper.HookUtils.Wrap(Hekili, "Update", function(oldFunc, self, ...)
        local result = oldFunc(self, ...)
        Module:InsertPaladinSkills()
        return result
    end)
    
    return success
end

-- ============================================
-- 调试 HUD (状态显示)
-- ============================================

Module.HUDData = {}

function Module:CreateStatusHUD()
    if self.HUDFrame then return end

    local frame = CreateFrame("Frame", "HekiliHelperRetHUD", UIParent, "BackdropTemplate")
    frame:SetSize(250, 400)
    frame:SetPoint("CENTER", 300, 0)
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
    frame.title:SetText("惩戒骑逻辑监控 (可拖动)")

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
    
    -- 1. 全局状态
    local righteousnessStacks = self:GetBuffStacks("player", 1299090)
    local minR, maxR = self:GetUnitRange("target")
    local rangeStr = "未知"
    if minR and maxR then rangeStr = string.format("%d-%d码", minR, maxR)
    elseif maxR then rangeStr = string.format("0-%d码", maxR) end

    -- 判定当前模式显示
    local enemyCount5 = self:CountEnemiesInRange(5)
    local enemyCount8 = self:CountEnemiesInRange(8)
    local isBossTarget = self:IsBoss("target")
    local isExecute = self:IsValidEnemy("target") and (UnitHealth("target") / UnitHealthMax("target") * 100) < 20
    local isAOE = enemyCount8 > 1
    local modeStr = "|cFF00FF00单体|r"
    if isExecute then 
        modeStr = "|cFFFF0000斩杀|r"
    elseif isAOE then
        if isBossTarget and righteousnessStacks < 5 then
            modeStr = "|cFFFF8800Boss AOE(叠层)|r"
        else
            modeStr = "|cFFFFFF00AOE|r"
        end
    end

    -- 2. 核心技能同步监控
    local pleaReady, pleaReason, pleaCastID, isCasting = self:IsSpellReady(54428, nil, true)
    local curName, _, _, _, _, _, _, _, curID = UnitCastingInfo("player")
    if not curName then curName, _, _, _, _, _, _, curID = UnitChannelInfo("player") end

    table.insert(lines, string.format("|cFFFFFF00[全局状态]|r"))
    local hpPct = UnitHealth("player") / UnitHealthMax("player") * 100
    local mpPct = UnitPower("player") / UnitPowerMax("player") * 100
    table.insert(lines, string.format("玩家状态: HP %.1f%% / MP %.1f%%", hpPct, mpPct))
    table.insert(lines, string.format("当前模式: %s (5码:%d, 8码:%d)", modeStr, enemyCount5, enemyCount8))
    table.insert(lines, string.format("当前施法: %s(%s)", curName or "无", tostring(curID or "无")))
    table.insert(lines, string.format("恳求状态: %s", pleaReason))
    table.insert(lines, string.format("正义Buff(1299090): %d层", righteousnessStacks))
    table.insert(lines, string.format("目标精确距离: %s", rangeStr))
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
    self.HUDData[actionName] = self.HUDData[actionName] or {}
    self.HUDData[actionName].should = should
    self.HUDData[actionName].reason = reason
end

-- ============================================
-- 核心判定工具
-- ============================================

function Module:GetUnitRange(unit)
    unit = unit or "target"
    if not UnitExists(unit) then return nil, nil end

    -- 使用与 RangeDisplay 相同的 LibRangeCheck-3.0
    local rc = LibStub("LibRangeCheck-3.0", true) or LibStub("LibRangeCheck-2.0", true)
    if rc then
        return rc:GetRange(unit)
    end

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

function Module:GetTTD()
    return self.ttdData.ttd
end

function Module:IsValidEnemy(unit)
    unit = unit or "target"
    return UnitExists(unit) and not UnitIsFriend("player", unit) and not UnitIsDead(unit)
end

function Module:IsBoss(unit)
    unit = unit or "target"
    if not self:IsValidEnemy(unit) then return false end
    local level = UnitLevel(unit)
    local classification = UnitClassification(unit)
    return level == -1 or level == 83 or classification == "worldboss" or classification == "boss"
end

function Module:IsSpecialType(unit)
    local t = UnitCreatureType(unit)
    return t == "Undead" or t == "Demon" or t == "亡灵" or t == "恶魔"
end

function Module:HasAnySeal()
    return self:HasBuff("player", 20375) or self:HasBuff("player", 31801)
end

function Module:HasSpecialEnemyInRange(range)
    if self:IsValidEnemy("target") and self:IsSpecialType("target") then
        local _, maxR = self:GetUnitRange("target")
        if maxR and maxR <= range then return true end
    end
    for i = 1, 40 do
        local u = "nameplate"..i
        if self:IsValidEnemy(u) and self:IsSpecialType(u) then
            local _, maxR = self:GetUnitRange(u)
            if maxR and maxR <= range then return true end
        end
    end
    return false
end

function Module:CountEnemiesInRange(range)
    local count = 0
    -- 1. 检查当前目标
    if self:IsValidEnemy("target") then
        local minR, maxR = self:GetUnitRange("target")
        if maxR and maxR <= range then count = count + 1 end
    end
    
    -- 2. 扫描姓名板 (最常用)
    for i = 1, 40 do
        local unit = "nameplate"..i
        if self:IsValidEnemy(unit) and not UnitIsUnit(unit, "target") then
            local minR, maxR = self:GetUnitRange(unit)
            if maxR and maxR <= range then count = count + 1 end
        end
    end
    
    return count
end

-- ============================================
-- 基础判定工具
-- ============================================

function Module:IsSpellReady(id, currentPriority, ignoreCastingCD)
    local s, d = GetSpellCooldown(id)
    local gS, gD = GetSpellCooldown(61304)
    local activeCastID = nil
    local isCurrentlyCastingOrChanneling = false

    -- 1. 施法检测
    local name, _, _, startTime, endTime = UnitCastingInfo("player")
    local isChannel = false
    if not name then
        name, _, _, startTime, endTime = UnitChannelInfo("player")
        isChannel = true
    end

    if name then
        isCurrentlyCastingOrChanneling = true
        -- 针对不同 WoW 版本和 Titan 环境的多重判定 (8-11位均尝试)
        local ids = {}
        if isChannel then
            for i = 7, 10 do table.insert(ids, (select(i, UnitChannelInfo("player")))) end
        else
            for i = 7, 11 do table.insert(ids, (select(i, UnitCastingInfo("player")))) end
        end
        
        -- 判定优先级：匹配传入ID > 匹配7位数字ID > 名称匹配
        local foundID = nil
        for _, v in ipairs(ids) do
            if v == id then foundID = v; break end
            if type(v) == "number" and v > 1000000 then foundID = v end
        end
        
        if not foundID and name == GetSpellInfo(id) then
            foundID = id
        end
        activeCastID = foundID or ids[1] -- 兜底取第一个
    end

    -- 2. 如果完全没有 CD
    if not s or s == 0 then return true, "已就绪", activeCastID, isCurrentlyCastingOrChanneling end

    -- 3. 排除正在读条产生的伪 CD
    if ignoreCastingCD and name then
        local remainingCast = (endTime / 1000) - GetTime()
        local cd = s + d - GetTime()
        
        -- 增加容差到 0.5s
        local isSync = math.abs(cd - remainingCast) < 0.5
        if isSync then
            return true, "读条中同步", activeCastID, isCurrentlyCastingOrChanneling
        end
    end

    -- 4. 排除 GCD 影响
    if gS and gS > 0 and s == gS and d == gD then
        return true, "GCD中", activeCastID, isCurrentlyCastingOrChanneling
    end

    -- 5. 计算真实 CD
    local cd = s + d - GetTime()
    if cd <= 0 then return true, "已就绪", activeCastID, isCurrentlyCastingOrChanneling end

    return false, string.format("CD(%.1fs)", cd), activeCastID, isCurrentlyCastingOrChanneling
end

function Module:IsLearned(name, id)
    local cleanName = name:match("^(.-)%s*%(") or name
    return IsSpellKnown(id) or GetSpellInfo(cleanName) ~= nil
end

function Module:HasBuff(unit, spellID)
    if not unit or not spellID then return false end
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, _, sID = UnitBuff(unit, i)
        if not name then break end
        -- 兼容性处理：尝试第10个和第11个返回值作为 spellId
        local id10 = select(10, UnitBuff(unit, i))
        local id11 = select(11, UnitBuff(unit, i))
        if id10 == spellID or id11 == spellID then return true end
        
        -- 按名称回退 (仅当能够获取名称时)
        local targetName = GetSpellInfo(spellID)
        if targetName and name == targetName then return true end
    end
    return false
end

function Module:GetBuffStacks(unit, spellID)
    if not unit or not spellID then return 0 end
    for i = 1, 40 do
        local name = UnitBuff(unit, i)
        if not name then break end
        
        local id10 = select(10, UnitBuff(unit, i))
        local id11 = select(11, UnitBuff(unit, i))
        
        if id10 == spellID or id11 == spellID then
            -- count 在第3(Retail)或第4(Classic)位
            local count3 = select(3, UnitBuff(unit, i))
            local count4 = select(4, UnitBuff(unit, i))
            -- 逻辑：通常 count 是个数字，如果是 0 或更大则返回
            if type(count4) == "number" then return count4 end
            if type(count3) == "number" then return count3 end
            return 0
        end
    end
    return 0
end

function Module:GetBuffTimeLeft(unit, spellID)
    if not unit or not spellID then return 0 end
    for i = 1, 40 do
        local name = UnitBuff(unit, i)
        if not name then break end
        
        local id10 = select(10, UnitBuff(unit, i))
        local id11 = select(11, UnitBuff(unit, i))
        
        if id10 == spellID or id11 == spellID then
            -- expirationTime 在第6(Retail)或第7(Classic)位
            local exp6 = select(6, UnitBuff(unit, i))
            local exp7 = select(7, UnitBuff(unit, i))
            local expTime = type(exp7) == "number" and exp7 or (type(exp6) == "number" and exp6 or 0)
            
            local now = GetTime()
            return (expTime > now) and (expTime - now) or 0
        end
    end
    return 0
end

function Module:HasDebuff(unit, spellID)
    if not unit or not spellID then return false end
    for i = 1, 40 do
        local name = UnitDebuff(unit, i)
        if not name then break end
        
        local id10 = select(10, UnitDebuff(unit, i))
        local id11 = select(11, UnitDebuff(unit, i))
        if id10 == spellID or id11 == spellID then return true end
        
        local targetName = GetSpellInfo(spellID)
        if targetName and name == targetName then return true end
    end
    return false
end

function Module:CheckSealOfVengeance(p)
    -- 如果已经有任何圣印，则不推荐
    if self:HasAnySeal() then return false end
    
    local ready, reason = self:IsSpellReady(31801, p)
    if not ready then return false end
    
    self:SetHUDReason("seal_of_vengeance", true, "缺失圣印")
    return true, "player"
end

-- ============================================
-- 技能定义与逻辑
-- ============================================

Module.SkillDefinitions = {
    -- 基础维护 (最高优先级)
    { actionName = "seal_of_vengeance", spellID = 31801, basePriority = 0.5, checkFunc = function(self, p) return self:CheckSealOfVengeance(p) end, displayName = "复仇圣印" },

    -- 爆发 (固定极高优先级)
    { actionName = "avenging_wrath", spellID = 31884, basePriority = 1, checkFunc = function(self, p) return self:CheckAvengingWrath(p) end, displayName = "复仇之怒" },
    { actionName = "lights_plea", spellID = 1298728, basePriority = 1.1, checkFunc = function(self, p) return self:CheckLightsPlea(p) end, displayName = "祈求圣光" },
    { actionName = "divine_plea",      spellID = 54428, basePriority = 1.2, checkFunc = function(self, p) return self:CheckDivinePlea(p) end, displayName = "神圣恳求" },

    -- 核心技能 (优先级动态计算)
    { actionName = "hammer_of_wrath", spellID = 48806, basePriority = 10, checkFunc = function(self, p) return self:CheckHammerOfWrath(p) end, displayName = "愤怒之锤" },
    { actionName = "crusader_strike", spellID = 35395, basePriority = 20, checkFunc = function(self, p) return self:CheckCrusaderStrike(p) end, displayName = "十字军打击" },
    { actionName = "judgement",       spellID = 20271, basePriority = 30, checkFunc = function(self, p) return self:CheckJudgement(p) end, displayName = "审判" },
    { actionName = "divine_storm",    spellID = 53385, basePriority = 40, checkFunc = function(self, p) return self:CheckDivineStorm(p) end, displayName = "神圣风暴" },
    { actionName = "consecration",    spellID = 48819, basePriority = 50, checkFunc = function(self, p) return self:CheckConsecration(p) end, displayName = "奉献" },
    { actionName = "exorcism",        spellID = 48801, basePriority = 60, checkFunc = function(self, p) return self:CheckExorcism(p) end, displayName = "驱邪术" },
    { actionName = "holy_wrath",      spellID = 48817, basePriority = 70, checkFunc = function(self, p) return self:CheckHolyWrath(p) end, displayName = "神圣愤怒" },
    
    -- 额外补充
    { actionName = "lionheart",      spellID = 20599, basePriority = 80, checkFunc = function(self, p) return self:CheckLionheart(p) end, displayName = "狮心" },
    
    -- 斩杀阶段填充 (仅限斩杀阶段且无其他推荐时)
    { actionName = "hammer_of_wrath_fill",  spellID = 48806, basePriority = 85, checkFunc = function(self, p) return self:CheckHammerOfWrathFill(p) end, displayName = "愤怒之锤(填充)" },
    { actionName = "divine_storm_fill",     spellID = 53385, basePriority = 86, checkFunc = function(self, p) return self:CheckDivineStormFill(p) end, displayName = "神圣风暴(填充)" },
    { actionName = "crusader_strike_fill",  spellID = 35395, basePriority = 87, checkFunc = function(self, p) return self:CheckCrusaderStrikeFill(p) end, displayName = "十字军打击(填充)" },

    -- 兜底 (固定极低优先级)
    { actionName = "divine_storm_fallback",   spellID = 53385, basePriority = 90, checkFunc = function(self, p) return self:CheckDivineStormFallback(p) end, displayName = "神圣风暴(兜底)" },
    { actionName = "crusader_strike_fallback", spellID = 35395, basePriority = 99, checkFunc = function(self, p) return self:CheckCrusaderStrikeFallback(p) end, displayName = "十字军打击(兜底)" },
}

function Module:GetDynamicPriority(actionName, isAOE, isExecute, ttd, enemyCount, hasSpecial)
    -- 基础逻辑变量
    local manaPct = (UnitPower("player") / UnitPowerMax("player") * 100)
    local righteousnessStacks = self:GetBuffStacks("player", 1299090)
    local isBossTarget = self:IsBoss("target")

    -- Boss AOE 拦截: 必须叠满5层正义，否则降级为单体
    if isAOE and isBossTarget and righteousnessStacks < 5 then
        isAOE = false
    end

    -- 1. 斩杀阶段: 逻辑镜像单体，但加入愤怒之锤(2)
    if isExecute then
        -- 基础序列：愤怒之锤(2) > 十字军(3) > 风暴(4) > 审判(5) > 奉献(6) > 驱邪(7) > 神圣愤怒(8)
        local map = { hammer_of_wrath = 2, crusader_strike = 3, divine_storm = 4, judgement = 5, consecration = 6, exorcism = 7, holy_wrath = 8 }
        
        if righteousnessStacks >= 5 then
            map.divine_storm = 3
            map.crusader_strike = 4
        end

        if manaPct < 20 then
            map.judgement = 3 -- 仅次于愤怒之锤
            if righteousnessStacks >= 5 then
                map.divine_storm = 4
                map.crusader_strike = 5
            else
                map.crusader_strike = 4
                map.divine_storm = 5
            end
        end
        return map[actionName] or 100

    -- 2. AOE 阶段
    elseif isAOE then
        -- 基础 AOE 序列: 风暴(2) > 审判(2.5) > 奉献(3) > 十字军(4) > 神圣愤怒(7) > 驱邪(8)
        local map = { divine_storm = 2, judgement = 2.5, consecration = 3, crusader_strike = 4, holy_wrath = 7, exorcism = 8 }
        
        -- 如果身边有亡灵/恶魔，神圣愤怒优先级提到十字军打击(4)之前
        if hasSpecial then
            map.holy_wrath = 3.5
        end

        -- 如果目标进入斩杀线 (如 Boss + 小怪场景)，依然优先打出愤怒之锤
        local targetHP = self:IsValidEnemy("target") and (UnitHealth("target") / UnitHealthMax("target") * 100) or 100
        if targetHP < 20 then
            map.hammer_of_wrath = 1.5
        end

        -- 低价值 AOE: TTD <= 5s 时，奉献降级
        if actionName == "consecration" and enemyCount > 1 and ttd <= 5 then
            return 7.5 -- 确保在神圣愤怒(7)之后，但在驱邪(8)之前
        end
        return map[actionName] or 100

    -- 3. 单体阶段
    else
        local map
        if hasSpecial then
            -- 方案 B (亡灵/恶魔): 十字军(2) > 神圣风暴(3) > 审判(4) > 驱邪术(4.5) > 奉献(5) > 神圣愤怒(6.5)
            map = { crusader_strike = 2, divine_storm = 3, judgement = 4, exorcism = 4.5, consecration = 5, holy_wrath = 6.5 }
        else
            -- 常规目标: 审判在奉献后 (十字军(2) > 风暴(3) > 奉献(4) > 审判(5) > 驱邪(6) > 神圣愤怒(7))
            map = { crusader_strike = 2, divine_storm = 3, consecration = 4, judgement = 5, exorcism = 6, holy_wrath = 7 }
        end
        
        -- 调整 1: 5层正义时，神圣风暴优先级大于十字军打击
        if righteousnessStacks >= 5 then
            local oldDS = map.divine_storm
            local oldCS = map.crusader_strike
            map.divine_storm = oldCS
            map.crusader_strike = oldDS
        end

        -- 调整 2: 蓝量低于 20% 时，审判优先级升至最高 (2) 确保回蓝
        if manaPct < 20 then
            map.judgement = 2
            if righteousnessStacks >= 5 then
                map.divine_storm = 3
                map.crusader_strike = 4
            else
                map.crusader_strike = 3
                map.divine_storm = 4
            end
        end
        
        return map[actionName] or 100
    end
end

function Module:CheckHolyWrath(p)
    -- 检测 10 码内是否有亡灵/恶魔
    if not self:HasSpecialEnemyInRange(10) then
        self:SetHUDReason("holy_wrath", false, "10码内无亡灵/恶魔目标")
        return false
    end

    -- 单体情况下的蓝量检查
    local isAOE = self:CountEnemiesInRange(8) > 1
    local manaPct = (UnitPower("player") / UnitPowerMax("player") * 100)
    if not isAOE and manaPct <= 50 then
        self:SetHUDReason("holy_wrath", false, string.format("单体蓝量低(%.1f%% <= 50%%)", manaPct))
        return false
    end

    local ready, reason = self:IsSpellReady(48817, p)
    if not ready then self:SetHUDReason("holy_wrath", false, reason); return false end
    
    self:SetHUDReason("holy_wrath", true, "就绪"); return true, "player"
end

function Module:CheckBurstConditions()
    if not self:IsBoss("target") or UnitIsDead("target") then return false end
    local minR, maxR = self:GetUnitRange("target")
    if not maxR or maxR > 10 then return false end
    return true
end

function Module:IsInBurstPhase()
    -- 爆发期定义：拥有复仇之怒 或 拥有圣光裁决
    return self:HasBuff("player", 31884) or self:HasBuff("player", 1298723)
end

function Module:CheckAvengingWrath(p)
    if not self:IsSpellReady(31884, p) then return false end
    
    -- 圣光裁决 (1298723) 存在
    if not self:HasBuff("player", 1298723) then 
        self:SetHUDReason("avenging_wrath", false, "缺失圣光裁决")
        return false 
    end

    if self:CheckBurstConditions() then
        self:SetHUDReason("avenging_wrath", true, "爆发开启")
        return true, "target"
    end
    return false
end

function Module:CheckLightsPlea(p, dryRun)
    local ready, reason, castID = self:IsSpellReady(1298728, p, true)
    
    -- 如果正在施放祈求圣光 (支持 1298728 和 1298724)，且还没有获得圣光裁决BUFF，则强制保持推荐
    if (castID == 1298728 or castID == 1298724) and not self:HasBuff("player", 1298723) then
        if not dryRun then self:SetHUDReason("lights_plea", true, "引导中(等待裁决)") end
        return true, "player"
    end

    if not ready then return false end
    if not self:CheckBurstConditions() then return false end
    
    -- 祈求圣光特有要求：不移动，正义5层且>5s，无圣光重担
    if GetUnitSpeed("player") > 0 then if not dryRun then self:SetHUDReason("lights_plea", false, "移动中") end; return false end
    if self:GetBuffStacks("player", 1299090) < 5 then if not dryRun then self:SetHUDReason("lights_plea", false, "正义未满5层") end; return false end
    if self:GetBuffTimeLeft("player", 1299090) <= 5 then if not dryRun then self:SetHUDReason("lights_plea", false, "正义时间不足") end; return false end
    if self:HasDebuff("player", 1299086) then if not dryRun then self:SetHUDReason("lights_plea", false, "已有圣光重担") end; return false end
    
    if not dryRun then self:SetHUDReason("lights_plea", true, "触发祈求") end
    return true, "player"
end

function Module:CheckDivinePlea(p)
    local ready, reason = self:IsSpellReady(54428, p, true)
    if not ready then self:SetHUDReason("divine_plea", false, reason); return false end

    local manaPct = (UnitPower("player") / UnitPowerMax("player") * 100)
    local stacks = self:GetBuffStacks("player", 1299090)
    local activeBurst = self:IsInBurstPhase()

    -- 1. 紧急回蓝：蓝量 < 30% (无视条件)
    if manaPct < 30 then
        self:SetHUDReason("divine_plea", true, string.format("紧急回蓝(%.0f%%)", manaPct))
        return true, "player"
    end

    -- 2. 常规回蓝：蓝量 < 80% 且 满足5层正义 且 不在爆发期
    -- 不在爆发期定义：既没有复仇之怒，也没有圣光裁决
    if manaPct < 80 and stacks >= 5 and not activeBurst then
        self:SetHUDReason("divine_plea", true, string.format("常规回蓝(%.0f%%)", manaPct))
        return true, "player"
    end

    self:SetHUDReason("divine_plea", false, string.format("蓝量%.0f%%/正义%d/爆发Buff%s", manaPct, stacks, tostring(activeBurst)))
    return false
end

function Module:CheckHammerOfWrath(p)
    if not self:IsValidEnemy("target") then self:SetHUDReason("hammer_of_wrath", false, "无有效敌人目标"); return false end
    local ready, reason = self:IsSpellReady(48806, p)
    if not ready then self:SetHUDReason("hammer_of_wrath", false, reason); return false end
    if UnitHealth("target") / UnitHealthMax("target") * 100 >= 20 then self:SetHUDReason("hammer_of_wrath", false, "血量>20%"); return false end
    self:SetHUDReason("hammer_of_wrath", true, "就绪"); return true, "target"
end

function Module:CheckCrusaderStrike(p)
    if not self:IsValidEnemy("target") then self:SetHUDReason("crusader_strike", false, "无有效敌人目标"); return false end
    local minR, maxR = self:GetUnitRange("target")
    if not maxR or maxR > 5 then self:SetHUDReason("crusader_strike", false, "超出5码"); return false end
    local ready, reason = self:IsSpellReady(35395, p)
    if not ready then self:SetHUDReason("crusader_strike", false, reason); return false end
    self:SetHUDReason("crusader_strike", true, "就绪"); return true, "target"
end

function Module:CheckDivineStorm(p)
    if not self:IsValidEnemy("target") then self:SetHUDReason("divine_storm", false, "无有效敌人目标"); return false end
    local minR, maxR = self:GetUnitRange("target")
    if not maxR or maxR > 5 then self:SetHUDReason("divine_storm", false, "超出5码"); return false end
    local ready, reason = self:IsSpellReady(53385, p)
    if not ready then self:SetHUDReason("divine_storm", false, reason); return false end
    self:SetHUDReason("divine_storm", true, "就绪"); return true, "player"
end

function Module:CheckExorcism(p)
    if not self:IsValidEnemy("target") then self:SetHUDReason("exorcism", false, "无有效敌人目标"); return false end
    if not self:HasBuff("player", 59578) then self:SetHUDReason("exorcism", false, "无战争艺术"); return false end
    local ready, reason = self:IsSpellReady(48801, p)
    if not ready then self:SetHUDReason("exorcism", false, reason); return false end
    self:SetHUDReason("exorcism", true, "就绪"); return true, "target"
end

function Module:CheckJudgement(p)
    if not self:IsValidEnemy("target") then self:SetHUDReason("judgement", false, "无有效敌人目标"); return false end
    -- 审判逻辑：如果有智慧审判技能且蓝量低，使用智慧审判，否则圣光审判
    local spellID = 20271 -- 默认圣光
    if IsSpellKnown(53408) and (UnitPower("player") / UnitPowerMax("player") * 100) < 80 then
        spellID = 53408
    end
    
    local ready, reason = self:IsSpellReady(spellID, p)
    if not ready then self:SetHUDReason("judgement", false, reason); return false end
    self:SetHUDReason("judgement", true, "就绪(" .. (spellID == 53408 and "智慧" or "圣光") .. ")"); 
    return true, "target", spellID
end

function Module:CheckConsecration(p)
    if not self:IsValidEnemy("target") then self:SetHUDReason("consecration", false, "无有效敌人目标"); return false end
    
    -- 站定检测
    if GetUnitSpeed("player") > 0 then
        self:SetHUDReason("consecration", false, "移动中")
        return false
    end

    local manaPct = (UnitPower("player") / UnitPowerMax("player") * 100)
    if manaPct < 40 then
        self:SetHUDReason("consecration", false, string.format("蓝量低(%.1f%% < 40%%)", manaPct))
        return false
    end

    local ready, reason = self:IsSpellReady(48819, p)
    if not ready then self:SetHUDReason("consecration", false, reason); return false end
    local minR, maxR = self:GetUnitRange("target")
    if not maxR or maxR > 5 then self:SetHUDReason("consecration", false, "超出5码"); return false end
    self:SetHUDReason("consecration", true, "就绪"); return true, "player"
end

function Module:CheckLionheart(p)
    if not self:IsBoss("target") or self:GetTTD() < 10 then return false end
    local count = GetItemCount(20599)
    if count > 0 then
        local start, duration = GetItemCooldown(20599)
        if start == 0 then
            self:SetHUDReason("lionheart", true, "推荐使用")
            return true, "player"
        end
    end
    return false
end

function Module:CheckHammerOfWrathFill(p)
    if not self.lastIsExecute then return false end
    return self:CheckHammerOfWrath(p)
end

function Module:CheckDivineStormFill(p)
    if not self.lastIsExecute then return false end
    return self:CheckDivineStorm(p)
end

function Module:CheckCrusaderStrikeFill(p)
    if not self.lastIsExecute then return false end
    return self:CheckCrusaderStrike(p)
end

function Module:CheckDivineStormFallback(p)
    if not self:IsValidEnemy("target") then return false end
    local minR, maxR = self:GetUnitRange("target")
    if not maxR or maxR > 5 then return false end
    self:SetHUDReason("divine_storm_fallback", true, "兜底(无视CD)")
    return true, "player"
end

function Module:CheckCrusaderStrikeFallback(p)
    if not self:IsValidEnemy("target") then return false end
    local minR, maxR = self:GetUnitRange("target")
    if not maxR or maxR > 5 then return false end
    self:SetHUDReason("crusader_strike_fallback", true, "兜底(无视CD)")
    return true, "target"
end

-- ============================================
-- 插入队列
-- ============================================

function Module:InsertPaladinSkills()
    if not Hekili or not Hekili.DisplayPool then return end
    
    self:UpdateTTD()
    local ttd = self:GetTTD()
    local enemyCount8 = self:CountEnemiesInRange(8)
    local enemyCount20 = self:CountEnemiesInRange(20)
    
    local targetHP = self:IsValidEnemy("target") and (UnitHealth("target") / UnitHealthMax("target") * 100) or 100
    local isExecute = false
    
    -- 斩杀判定：20码内只有一个敌对目标，且该目标血量 < 20%
    if enemyCount20 == 1 and targetHP < 20 then
        isExecute = true
    end
    
    self.lastIsExecute = isExecute
    local isAOE = enemyCount8 > 1
    local hasSpecial8 = self:HasSpecialEnemyInRange(10)
    
    -- 准备排序列表
    local activeSkills = {}
    for _, def in ipairs(self.SkillDefinitions) do
        local isLearned = self:IsLearned(def.displayName, def.spellID)
        if def.actionName == "lionheart" then isLearned = GetItemCount(20599) > 0 end
        
        if isLearned then
            local currentPriority = def.basePriority
            -- 动态优先级调整
            if currentPriority >= 10 and currentPriority < 80 then
                currentPriority = self:GetDynamicPriority(def.actionName, isAOE, isExecute, ttd, enemyCount8, hasSpecial8)
            end
            
            table.insert(activeSkills, {
                actionName = def.actionName,
                spellID = def.spellID,
                priority = currentPriority,
                checkFunc = def.checkFunc,
                displayName = def.displayName
            })
        end
    end
    
    -- 按优先级排序 (数值越小越靠前)
    table.sort(activeSkills, function(a, b) return a.priority < b.priority end)

    if self.HUDFrame then if HekiliHelper.DebugEnabled then self.HUDFrame:Show() else self.HUDFrame:Hide() end end
    if not HekiliHelper.DB or not HekiliHelper.DB.profile or not HekiliHelper.DB.profile.retPaladin or not HekiliHelper.DB.profile.retPaladin.enabled then return end

    for dispName, UI in pairs(Hekili.DisplayPool) do
        local lowerName = dispName:lower()
        if (lowerName == "primary" or lowerName == "aoe") and UI.Active and UI.alpha > 0 then
            local Queue = UI.Recommendations
            if not Queue then return end
            for i = 1, 10 do if Queue[i] and Queue[i].isRetPaladinSkill then Queue[i] = nil end end

            local skillsFound = 0
            local hasNormalSkill = false
            for _, skillDef in ipairs(activeSkills) do
                -- 兜底逻辑：如果已有正常技能，则跳过兜底
                if skillDef.priority >= 90 and hasNormalSkill then
                    -- Skip
                else
                    local should, target, customSpellID = skillDef.checkFunc(self, skillDef.priority)
                    if should and skillsFound < 4 then
                        skillsFound = skillsFound + 1
                        if skillDef.priority < 90 then hasNormalSkill = true end
                        
                        local displayID = customSpellID or skillDef.spellID
                        local ability = Hekili.Class.abilities[skillDef.actionName]
                        
                        -- 如果有自定义 ID 且与默认 ID 不同，我们需要确保图标也更新
                        local texture = ability and ability.texture
                        if customSpellID and customSpellID ~= skillDef.spellID then
                            _, _, texture = GetSpellInfo(customSpellID)
                        end

                        if not ability then
                            local n, _, t
                            if skillDef.actionName == "lionheart" then n, _, _, _, _, _, _, _, _, t = GetItemInfo(20599)
                            else n, _, t = GetSpellInfo(displayID) end
                            if n then 
                                Hekili.Class.abilities[skillDef.actionName] = { key = skillDef.actionName, name = n, texture = t, id = displayID, cast = 0, gcd = "off" }
                                ability = Hekili.Class.abilities[skillDef.actionName]
                                texture = t
                            end
                        end

                        if ability then
                            Queue[skillsFound] = Queue[skillsFound] or {}
                            local slot = Queue[skillsFound]
                            slot.actionName = skillDef.actionName; 
                            slot.actionID = displayID; 
                            slot.texture = texture or ability.texture; 
                            slot.isRetPaladinSkill = true; 
                            slot.display = dispName; 
                            slot.time = 0; 
                            slot.exact_time = GetTime(); 
                            UI.NewRecommendations = true
                        end
                    end
                end
            end
        end
    end
    self:UpdateHUDText()
end
