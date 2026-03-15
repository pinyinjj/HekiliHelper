-- Modules/FeralDruidSkills.lua
-- 野性德鲁伊技能模块
-- 针对WLK版本的野性德鲁伊，提供P2两件套适配等逻辑

local HekiliHelper = _G.HekiliHelper

if not HekiliHelper then
    C_Timer.After(0.1, function()
        local HH = _G.HekiliHelper
        if HH and not HH.FeralDruidSkills then
            HH.FeralDruidSkills = {}
        end
    end)
    return
end

if not HekiliHelper.FeralDruidSkills then
    HekiliHelper.FeralDruidSkills = {}
end

local Module = HekiliHelper.FeralDruidSkills

-- 技能ID定义
local REGROWTH_SPELL_ID = 48443 -- 愈合 (最高等级)
local FAERIE_FIRE_FERAL_ID = 16857 -- 精灵之火 (野性)
local FAERIE_FIRE_ID = 770 -- 精灵之火
local PREDATORY_SWIFTNESS_ID = 69369 -- 掠食者的迅捷 (P2 2pc 相关)

-- 核心逻辑验证函数 (同步/异步逻辑公用)
function Module:ShouldRecommendRegrowth()
    -- 0. 打印调试信息
    local db = HekiliHelper.DB and HekiliHelper.DB.profile
    -- HekiliHelper:DebugPrint(string.format("|cFF00FF00[FeralDruid]|r 开始检查... db=%s, feralDruid=%s", tostring(db), tostring(db and db.feralDruid)))

    -- 1. 检查配置
    if not db then
        -- HekiliHelper:DebugPrint("|cFFFF0000[FeralDruid]|r DB不存在")
        return false, "DB不存在"
    end
    if not db.feralDruid then
        -- 配置不存在时默认为开启
        -- HekiliHelper:DebugPrint("|cFF00FF00[FeralDruid]|r 配置不存在，默认为开启")
    elseif db.feralDruid.enabled == false then
        -- HekiliHelper:DebugPrint("|cFFFF0000[FeralDruid]|r 功能未启用")
        return false, "功能未启用"
    end
    -- HekiliHelper:DebugPrint("|cFF00FF00[FeralDruid]|r 配置检查通过")

    -- 2. 检查法力值
    local currentMana = UnitPower("player", 0)
    if currentMana <= 2500 then
        -- HekiliHelper:DebugPrint(string.format("|cFFFF0000[FeralDruid]|r 法力值不足: %d", currentMana))
        return false, "法力值不足"
    end

    -- 3. 检查Buff (掠食者的迅捷) - 需要检查是玩家自身施放的
    local hasPredatorySwiftness = false
    for i = 1, 40 do
        local name, icon, stacks, dispelType, duration, expirationTime, unitCaster, canStealOrPurge, nameplateShowPersonal, spellId = UnitBuff("player", i)
        if not name then break end
        if spellId == PREDATORY_SWIFTNESS_ID and unitCaster == "player" then
            hasPredatorySwiftness = true
            break
        end
    end
    if not hasPredatorySwiftness then
        -- HekiliHelper:DebugPrint("|cFFFF0000[FeralDruid]|r 没有掠食者的迅捷Buff(玩家自身)")
        return false, "没有掠食者的迅捷Buff"
    end
    -- HekiliHelper:DebugPrint("|cFF00FF00[FeralDruid]|r 有掠食者迅捷Buff(玩家自身)")

    -- 4. 检查精灵之火冷却
    local start, duration = GetSpellCooldown(FAERIE_FIRE_FERAL_ID)
    if not start or start == 0 then
        start, duration = GetSpellCooldown(FAERIE_FIRE_ID)
    end
    local cdLeft = (start and start > 0) and (start + duration - GetTime()) or 0
    -- HekiliHelper:DebugPrint(string.format("|cFF00FF00[FeralDruid]|r 精灵火CD: %.2fs", cdLeft))
    if cdLeft <= 1.5 then
        return false, string.format("精灵火CD不足(%.2fs)", cdLeft)
    end

    -- HekiliHelper:DebugPrint(string.format("|cFF00FF00[FeralDruid]|r 全部条件满足! CD:%.2fs, Mana:%d", cdLeft, currentMana))
    return true, string.format("满足(CD:%.2fs, Mana:%d)", cdLeft, currentMana)
end

-- 模块初始化
function Module:Initialize()
    if not Hekili then return false end
    
    local _, class = UnitClass("player")
    if class ~= "DRUID" then return true end

    HekiliHelper:DebugPrint("|cFF00FF00[FeralDruid]|r 开始Hook Hekili.Update...")
    
    local success = HekiliHelper.HookUtils.Wrap(Hekili, "Update", function(oldFunc, self, ...)
        -- A. 备份阶段：在Hekili重算前记录
        local savedSkills = {}
        if Hekili and Hekili.DisplayPool then
            for dispName, UI in pairs(Hekili.DisplayPool) do
                if UI and UI.Recommendations and UI.Recommendations[1] and UI.Recommendations[1].isFeralDruidSkill then
                    savedSkills[dispName] = {}
                    for k, v in pairs(UI.Recommendations[1]) do savedSkills[dispName][k] = v end
                end
            end
        end

        -- B. 执行原生更新
        local result = oldFunc(self, ...)
        
        -- C. 同步恢复阶段：立即校验并决定是否恢复
        if Hekili and Hekili.DisplayPool then
            local should, reason = Module:ShouldRecommendRegrowth()
            for dispName, savedSlot in pairs(savedSkills) do
                local UI = Hekili.DisplayPool[dispName]
                if UI and UI.Recommendations then
                    if should then
                        -- 如果依然满足条件，强行粘回
                        if not UI.Recommendations[1] or not UI.Recommendations[1].isFeralDruidSkill then
                            UI.Recommendations[1] = UI.Recommendations[1] or {}
                            for k, v in pairs(savedSlot) do UI.Recommendations[1][k] = v end
                            UI.NewRecommendations = true
                        end
                    else
                        -- 如果不再满足条件，确保清除可能残留的愈合
                        if UI.Recommendations[1] and UI.Recommendations[1].isFeralDruidSkill then
                            Module:RemoveRegrowth(dispName, UI, "同步校验-" .. reason)
                        end
                    end
                end
            end
        end

        -- D. 异步二次检查
        C_Timer.After(0.001, function()
            Module:ProcessFeralLogic()
        end)
        
        return result
    end)
    
    return success
end

-- 核心逻辑处理 (异步及主要入口)
function Module:ProcessFeralLogic()
    if not Hekili or not Hekili.DisplayPool then return end

    local should, reason = self:ShouldRecommendRegrowth()
    HekiliHelper:DebugPrint(string.format("|cFF00FF00[FeralDruid]|r ProcessFeralLogic: should=%s, reason=%s", tostring(should), reason))

    for dispName, UI in pairs(Hekili.DisplayPool) do
        if (dispName == "Primary" or dispName == "AOE") and UI.Active and UI.alpha > 0 then
            local Queue = UI.Recommendations
            HekiliHelper:DebugPrint(string.format("|cFF00FF00[FeralDruid]|r 检查队列 %s, Queue[1]=%s", dispName, tostring(Queue and Queue[1])))
            if Queue and Queue[1] then
                local nextAction = Queue[1].actionName or ""
                local nextActionID = Queue[1].actionID or 0
                HekiliHelper:DebugPrint(string.format("|cFF00FF00[FeralDruid]|r 当前推荐: actionName=%s, actionID=%d", nextAction, nextActionID))

                if should then
                    -- 检查当前是否推荐精灵之火
                    if nextAction == "faerie_fire_feral" or nextAction == "faerie_fire" or
                       nextActionID == FAERIE_FIRE_FERAL_ID or nextActionID == FAERIE_FIRE_ID then
                        HekiliHelper:DebugPrint("|cFF00FF00[FeralDruid]|r 满足条件，插入愈合")
                        self:InsertRegrowth(dispName, UI, reason)
                    else
                        HekiliHelper:DebugPrint(string.format("|cFFFF0000[FeralDruid]|r 当前不是精灵火，不插入: %s", nextAction))
                    end
                else
                    -- 不满足条件，如果是愈合则移除
                    if Queue[1].isFeralDruidSkill then
                        self:RemoveRegrowth(dispName, UI, reason)
                    end
                end
            end
        end
    end
end

-- 插入逻辑
function Module:InsertRegrowth(dispName, UI, reason)
    local Queue = UI.Recommendations
    if not Queue or (Queue[1] and Queue[1].actionID == REGROWTH_SPELL_ID) then return end

    local originalSlot = {}
    for k, v in pairs(Queue[1] or {}) do originalSlot[k] = v end

    local _, _, texture = GetSpellInfo(REGROWTH_SPELL_ID)
    Queue[1] = Queue[1] or {}
    local slot = Queue[1]
    
    slot.index = 1
    slot.actionName = "regrowth"
    slot.actionID = REGROWTH_SPELL_ID
    slot.texture = texture
    slot.time = 0
    slot.exact_time = GetTime()
    slot.display = dispName
    slot.isFeralDruidSkill = true
    slot.originalRecommendation = originalSlot
    
    if not Hekili.Class.abilities["regrowth"] then
        Hekili.Class.abilities["regrowth"] = { key = "regrowth", name = "愈合", texture = texture, id = REGROWTH_SPELL_ID, cast = 0, gcd = "spell" }
    end

    UI.NewRecommendations = true
    HekiliHelper:DebugPrint(string.format("|cFF00FF00[FeralDruid]|r 插入愈合: %s", reason))
end

-- 移除逻辑
function Module:RemoveRegrowth(dispName, UI, reason)
    local Queue = UI.Recommendations
    if not Queue or not Queue[1] or not Queue[1].isFeralDruidSkill then return end
    
    if Queue[1].originalRecommendation then
        local original = Queue[1].originalRecommendation
        -- 清除当前内容
        for k, v in pairs(Queue[1]) do Queue[1][k] = nil end
        -- 恢复原始内容
        for k, v in pairs(original) do Queue[1][k] = v end
    else
        Queue[1] = nil
    end
    
    UI.NewRecommendations = true
    HekiliHelper:DebugPrint(string.format("|cFFFF0000[FeralDruid]|r 移除愈合: %s", reason))
end
