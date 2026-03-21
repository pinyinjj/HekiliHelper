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
    -- 1. 检查配置
    local db = HekiliHelper.DB and HekiliHelper.DB.profile
    if not db then
        return false, "DB不存在"
    end
    if not db.feralDruid or db.feralDruid.enabled == false then
        return false, "功能未启用"
    end

    -- 2. 检查法力值
    local currentMana = UnitPower("player", 0)
    if currentMana <= 2500 then
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
        return false, "没有掠食者的迅捷Buff"
    end

    -- 4. 检查精灵之火冷却
    local start, duration = GetSpellCooldown(FAERIE_FIRE_FERAL_ID)
    if not start or start == 0 then
        start, duration = GetSpellCooldown(FAERIE_FIRE_ID)
    end
    local cdLeft = (start and start > 0) and (start + duration - GetTime()) or 0
    if cdLeft <= 1.5 then
        return false, string.format("精灵火CD不足(%.2fs)", cdLeft)
    end

    return true, string.format("满足(CD:%.2fs, Mana:%d)", cdLeft, currentMana)
end

-- 模块初始化
function Module:Initialize()
    if not Hekili then return false end
    
    local _, class = UnitClass("player")
    if class ~= "DRUID" then return true end

    -- Hook Hekili.Update
    local success = HekiliHelper.HookUtils.Wrap(Hekili, "Update", function(oldFunc, self, ...)
        local result = oldFunc(self, ...)
        
        -- 在 Hekili 计算完后介入
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

    for dispName, UI in pairs(Hekili.DisplayPool) do
        local lowerName = dispName:lower()
        if (lowerName == "primary" or lowerName == "aoe") and UI.Active and UI.alpha > 0 then
            local Queue = UI.Recommendations
            if Queue and Queue[1] then
                local nextAction = Queue[1].actionName or ""
                local nextActionID = Queue[1].actionID or 0

                if should then
                    -- 检查当前是否推荐精灵之火
                    if nextAction == "faerie_fire_feral" or nextAction == "faerie_fire" or
                       nextActionID == FAERIE_FIRE_FERAL_ID or nextActionID == FAERIE_FIRE_ID then
                        self:InsertRegrowth(dispName, UI, reason)
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
end
