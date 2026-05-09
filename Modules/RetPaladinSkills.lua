-- Modules/RetPaladinSkills.lua
-- 惩戒骑士技能插入模块
-- 优化点：精准测距、智能缓冲让位、圣印叠层判定修复

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

    table.insert(lines, string.format("|cFFFFFF00[全局状态]|r"))
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

function Module:IsBoss(unit)
    unit = unit or "target"
    if not UnitExists(unit) then return false end
    local level = UnitLevel(unit)
    local classification = UnitClassification(unit)
    return level == -1 or level == 83 or classification == "worldboss" or classification == "boss"
end

-- ============================================
-- 基础判定工具
-- ============================================

function Module:IsSpellReady(id, currentPriority)
    local s, d = GetSpellCooldown(id)
    -- GCD 判定参考 (使用 61304 作为标准 GCD 锚点)
    local gS, gD = GetSpellCooldown(61304)

    -- 1. 如果完全没有 CD
    if not s or s == 0 then return true, "已就绪" end

    -- 2. 排除 GCD 影响：
    -- 如果当前技能的持续时间 d 与 GCD 持续时间 gD 相同，且起始时间一致，说明这只是 GCD
    if gS and gS > 0 and s == gS and d == gD then
        return true, "GCD中"
    end

    -- 3. 计算真实 CD
    local cd = s + d - GetTime()
    if cd <= 0 then return true, "已就绪" end

    return false, string.format("CD(%.1fs)", cd)
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

-- ============================================
-- 技能定义与逻辑
-- ============================================

Module.SkillDefinitions = {
    -- 爆发
    { actionName = "avenging_wrath", spellID = 31884, priority = 1, checkFunc = function(self, p) return self:CheckAvengingWrath(p) end, displayName = "复仇之怒" },
    { actionName = "lights_plea", spellID = 1298728, priority = 1.1, checkFunc = function(self, p) return self:CheckLightsPlea(p) end, displayName = "祈求圣光" },

    { actionName = "hammer_of_wrath", spellID = 48806, priority = 2, checkFunc = function(self, p) return self:CheckHammerOfWrath(p) end, displayName = "愤怒之锤" },
    
    -- 十字军优先模式 (正义 < 5层时)
    { actionName = "crusader_strike_high", spellID = 35395, priority = 3, checkFunc = function(self, p) return self:CheckCrusaderStrike(true, p) end, displayName = "十字军打击(叠层优先)" },
    { actionName = "divine_storm_low",    spellID = 53385, priority = 3.1, checkFunc = function(self, p) return self:CheckDivineStorm(false, p) end, displayName = "神圣风暴(填充)" },

    -- 神圣风暴优先模式 (正义 >= 5层时)
    { actionName = "divine_storm_high",   spellID = 53385, priority = 3.5, checkFunc = function(self, p) return self:CheckDivineStorm(true, p) end, displayName = "神圣风暴(爆发优先)" },
    { actionName = "crusader_strike_low",  spellID = 35395, priority = 3.6, checkFunc = function(self, p) return self:CheckCrusaderStrike(false, p) end, displayName = "十字军打击(填充)" },

    { actionName = "exorcism_high",    spellID = 48801, priority = 4.5, checkFunc = function(self, p) return self:CheckExorcism(true, p) end, displayName = "驱邪术(特殊)" },
    { actionName = "judgement_of_light", spellID = 20271, priority = 5, checkFunc = function(self, p) return self:CheckJudgement(20271, p) end, displayName = "圣光审判" },
    { actionName = "judgement_of_wisdom", spellID = 53408, priority = 5.1, checkFunc = function(self, p) return self:CheckJudgement(53408, p) end, displayName = "智慧审判" },
    { actionName = "exorcism",        spellID = 48801, priority = 6, checkFunc = function(self, p) return self:CheckExorcism(false, p) end, displayName = "驱邪术" },
    { actionName = "consecration",    spellID = 48819, priority = 7, checkFunc = function(self, p) return self:CheckConsecration(p) end, displayName = "奉献" },
    
    -- 额外补充
    { actionName = "lionheart",      spellID = 20599, priority = 8, checkFunc = function(self, p) return self:CheckLionheart(p) end, displayName = "狮心" },
}

function Module:CheckBurstConditions()
    if not self:IsBoss("target") or UnitIsDead("target") then return false end
    local minR, maxR = self:GetUnitRange("target")
    if not maxR or maxR > 10 then return false end
    return true
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

function Module:CheckLightsPlea(p)
    if not self:IsSpellReady(1298728, p) then return false end
    if not self:CheckBurstConditions() then return false end
    
    -- 祈求圣光特有要求：不移动，正义5层且>5s，无圣光重担
    if GetUnitSpeed("player") > 0 then self:SetHUDReason("lights_plea", false, "移动中"); return false end
    if self:GetBuffStacks("player", 1299090) < 5 then self:SetHUDReason("lights_plea", false, "正义未满5层"); return false end
    if self:GetBuffTimeLeft("player", 1299090) <= 5 then self:SetHUDReason("lights_plea", false, "正义时间不足"); return false end
    if self:HasDebuff("player", 1299086) then self:SetHUDReason("lights_plea", false, "已有圣光重担"); return false end
    
    self:SetHUDReason("lights_plea", true, "触发祈求")
    return true, "player"
end

function Module:CheckHammerOfWrath(p)
    if not UnitExists("target") or UnitIsDead("target") then self:SetHUDReason("hammer_of_wrath", false, "无目标"); return false end
    local ready, reason = self:IsSpellReady(48806, p)
    if not ready then self:SetHUDReason("hammer_of_wrath", false, reason); return false end
    if UnitHealth("target") / UnitHealthMax("target") * 100 >= 20 then self:SetHUDReason("hammer_of_wrath", false, "血量>20%"); return false end
    self:SetHUDReason("hammer_of_wrath", true, "斩杀期"); return true, "target"
end

function Module:CheckCrusaderStrike(highMode, p)
    local action = highMode and "crusader_strike_high" or "crusader_strike_low"
    if not UnitExists("target") or UnitIsDead("target") then self:SetHUDReason(action, false, "无目标"); return false end
    
    local stacks = self:GetBuffStacks("player", 1299090)
    local should = highMode and (stacks < 5) or (stacks >= 5)
    if not should then return false end

    local minR, maxR = self:GetUnitRange("target")
    if not maxR or maxR > 5 then self:SetHUDReason(action, false, "超出5码"); return false end
    local ready, reason = self:IsSpellReady(35395, p)
    if not ready then self:SetHUDReason(action, false, reason); return false end
    
    self:SetHUDReason(action, true, "就绪")
    return true, "target"
end

function Module:CheckDivineStorm(highMode, p)
    local action = highMode and "divine_storm_high" or "divine_storm_low"
    if not UnitExists("target") or UnitIsDead("target") then self:SetHUDReason(action, false, "无目标"); return false end

    local stacks = self:GetBuffStacks("player", 1299090)
    local should = highMode and (stacks >= 5) or (stacks < 5)
    if not should then return false end

    local minR, maxR = self:GetUnitRange("target")
    if not maxR or maxR > 5 then self:SetHUDReason(action, false, "超出5码"); return false end
    local ready, reason = self:IsSpellReady(53385, p)
    if not ready then self:SetHUDReason(action, false, reason); return false end
    
    self:SetHUDReason(action, true, "就绪")
    return true, "player"
end

function Module:CheckExorcism(high, p)
    local action = high and "exorcism_high" or "exorcism"
    if not self:HasBuff("player", 59578) then self:SetHUDReason(action, false, "无战争艺术"); return false end
    local ready, reason = self:IsSpellReady(48801, p)
    if not ready then self:SetHUDReason(action, false, reason); return false end
    local type = UnitCreatureType("target")
    local isSpecial = (type == "Undead" or type == "Demon" or type == "亡灵" or type == "恶魔")
    local should = high and isSpecial or (not high and not isSpecial)
    self:SetHUDReason(action, should, isSpecial and "亡灵/恶魔" or "普通目标")
    return should, "target"
end

function Module:CheckJudgement(id, p)
    local action = id == 20271 and "judgement_of_light" or "judgement_of_wisdom"
    local ready, reason = self:IsSpellReady(id, p)
    if not ready then self:SetHUDReason(action, false, reason); return false end
    local manaPct = (UnitPower("player") / UnitPowerMax("player") * 100)
    local should = (id == 20271 and manaPct >= 80) or (id == 53408 and manaPct < 80)
    self:SetHUDReason(action, should, string.format("蓝量%.0f%%", manaPct))
    return should, "target"
end

function Module:CheckConsecration(p)
    local ready, reason = self:IsSpellReady(48819, p)
    if not ready then self:SetHUDReason("consecration", false, reason); return false end
    local minR, maxR = self:GetUnitRange("target")
    if not maxR or maxR > 5 then self:SetHUDReason("consecration", false, "超出5码"); return false end
    self:SetHUDReason("consecration", true, "地毯填充"); return true, "player"
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

-- ============================================
-- 插入队列
-- ============================================

function Module:InsertPaladinSkills()
    if not Hekili or not Hekili.DisplayPool then return end
    
    self:UpdateTTD()

    if self.HUDFrame then if HekiliHelper.DebugEnabled then self.HUDFrame:Show() else self.HUDFrame:Hide() end end
    if not HekiliHelper.DB or not HekiliHelper.DB.profile or not HekiliHelper.DB.profile.retPaladin or not HekiliHelper.DB.profile.retPaladin.enabled then return end

    for dispName, UI in pairs(Hekili.DisplayPool) do
        local lowerName = dispName:lower()
        if (lowerName == "primary" or lowerName == "aoe") and UI.Active and UI.alpha > 0 then
            local Queue = UI.Recommendations
            if not Queue then return end
            for i = 1, 10 do if Queue[i] and Queue[i].isRetPaladinSkill then Queue[i] = nil end end

            local skillsFound = 0
            for _, skillDef in ipairs(self.SkillDefinitions) do
                local isLearned = self:IsLearned(skillDef.displayName, skillDef.spellID)
                if skillDef.actionName == "lionheart" then
                    isLearned = GetItemCount(20599) > 0
                end

                if isLearned then
                    local should, target = skillDef.checkFunc(self, skillDef.priority)
                    if should and skillsFound < 4 then
                        skillsFound = skillsFound + 1
                        local ability = Hekili.Class.abilities[skillDef.actionName]
                        if not ability then
                            local n, _, t
                            if skillDef.actionName == "lionheart" then
                                n, _, _, _, _, _, _, _, _, t = GetItemInfo(20599)
                            else
                                n, _, t = GetSpellInfo(skillDef.spellID)
                            end
                            if n then Hekili.Class.abilities[skillDef.actionName] = { key = skillDef.actionName, name = n, texture = t, id = skillDef.spellID, cast = 0, gcd = "off" }; ability = Hekili.Class.abilities[skillDef.actionName] end
                        end
                        if ability then
                            Queue[skillsFound] = Queue[skillsFound] or {}
                            local slot = Queue[skillsFound]
                            slot.actionName = skillDef.actionName; slot.actionID = skillDef.spellID; slot.texture = ability.texture; slot.isRetPaladinSkill = true; slot.display = dispName; slot.time = 0; slot.exact_time = GetTime(); UI.NewRecommendations = true
                        end
                    end
                end
            end
        end
    end
    self:UpdateHUDText()
end
