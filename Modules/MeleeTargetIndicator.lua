-- Modules/MeleeTargetIndicator.lua
-- 近战目标指示器模块
-- 在优先级队列中插入近战目标指示图标
-- 当玩家身边近战范围内（5码）存在敌方存活单位，但玩家没有目标或目标超出近战范围时显示

-- 获取HekiliHelper对象
local HekiliHelper = _G.HekiliHelper

if not HekiliHelper then
    C_Timer.After(0.1, function()
        local HH = _G.HekiliHelper
        if HH and not HH.MeleeTargetIndicator then
            HH.MeleeTargetIndicator = {}
        end
    end)
    return
end

-- 创建模块对象
if not HekiliHelper.MeleeTargetIndicator then
    HekiliHelper.MeleeTargetIndicator = {}
end

local Module = HekiliHelper.MeleeTargetIndicator

-- 停留时间配置 (1秒，防止闪烁)
Module.RecommendationLinger = 0.8
Module.LastRecommendationTime = 0
Module.LastShouldShow = false

-- 模块初始化
function Module:Initialize()
    if not Hekili then
        HekiliHelper:Print("|cFFFF0000[MeleeIndicator]|r 错误: Hekili对象不存在")
        return false
    end
    
    if not Hekili.Update then
        HekiliHelper:Print("|cFFFF0000[MeleeIndicator]|r 错误: Hekili.Update函数不存在")
        return false
    end
    
    -- 使用HookUtils.Wrap + UI OnUpdate 持续覆盖
    local success = HekiliHelper.HookUtils.Wrap(Hekili, "Update", function(oldFunc, self, ...)
        -- 调用原函数生成推荐
        local result = oldFunc(self, ...)

        -- 立即执行插入
        Module:ForceInsertMeleeIndicator()

        -- 启动持续覆盖（如果还没启动）
        if not self.ContinuousOverrideActive then
            self:StartContinuousOverride()
        end

        return result
    end)

    if success then
        return true
    else
        return false
    end
end

-- 持续覆盖函数：Hook UI 的 OnUpdate 实现每帧覆盖
function Module:StartContinuousOverride()
    local displays = Hekili.DisplayPool
    if not displays or not displays.Primary then
        C_Timer.After(0.1, function() Module:StartContinuousOverride() end)
        return
    end

    local UI = displays.Primary
    if self.ContinuousOverrideActive then return end
    self.ContinuousOverrideActive = true

    -- Hook UI 的 OnUpdate
    local originalOnUpdate = UI:GetScript("OnUpdate")
    UI:SetScript("OnUpdate", function(self, elapsed)
        if originalOnUpdate then
            originalOnUpdate(self, elapsed)
        end
        -- 每帧都执行强制插入
        Module:ForceInsertMeleeIndicator()
    end)
end

-- 获取职业图标路径
function Module:GetClassIconPath()
    local _, class = UnitClass("player")
    if not class then return nil end
    
    -- 职业图标映射
    local classIcons = {
        DEATHKNIGHT = "Interface\\AddOns\\Hekili\\Textures\\DEATHKNIGHT.blp",
        DRUID = "Interface\\AddOns\\Hekili\\Textures\\DRUID.blp",
        HUNTER = "Interface\\AddOns\\Hekili\\Textures\\HUNTER.png",
        MAGE = "Interface\\AddOns\\Hekili\\Textures\\MAGE.blp",
        PALADIN = "Interface\\AddOns\\Hekili\\Textures\\PALADIN.blp",
        PRIEST = "Interface\\AddOns\\Hekili\\Textures\\PRIEST.blp",
        ROGUE = "Interface\\AddOns\\Hekili\\Textures\\ROGUE.blp",
        SHAMAN = "Interface\\AddOns\\Hekili\\Textures\\SHAMAN.blp",
        WARLOCK = "Interface\\AddOns\\Hekili\\Textures\\WARLOCK.blp",
        WARRIOR = "Interface\\AddOns\\Hekili\\Textures\\WARRIOR.blp",
    }
    
    return classIcons[class]
end

-- 检查玩家是否在近战攻击中
function Module:IsInMeleeCombat()
    -- 检查是否在自动攻击（SpellID: 6603 是自动攻击）
    if IsCurrentSpell(6603) then return true end
    
    -- 检查施法和引导
    if UnitCastingInfo("player") or UnitChannelInfo("player") then return true end
    
    -- 检查Hekili状态系统
    if Hekili.State and Hekili.State.buff and Hekili.State.buff.casting and Hekili.State.buff.casting.up then
        return true
    end
    
    return false
end

-- 计算近战范围内敌人数量
function Module:CountEnemiesInMeleeRange()
    local RC = LibStub("LibRangeCheck-2.0")
    if not RC then return 0 end
    
    local count = 0
    local checkedGUIDs = {}
    
    -- 检查目标
    if UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target") then
        local minRange, maxRange = RC:GetRange("target")
        if maxRange and maxRange <= 5 then
            count = count + 1
            checkedGUIDs[UnitGUID("target")] = true
        end
    end
    
    -- 检查姓名板（这是最实用的逻辑）
    if Hekili.npGUIDs then
        for unit, _ in pairs(Hekili.npGUIDs) do
            if unit and UnitExists(unit) and not UnitIsDead(unit) and UnitCanAttack("player", unit) then
                local guid = UnitGUID(unit)
                if guid and not checkedGUIDs[guid] then
                    local minRange, maxRange = RC:GetRange(unit)
                    if maxRange and maxRange <= 5 then
                        count = count + 1
                        checkedGUIDs[guid] = true
                    end
                end
            end
        end
    end
    
    return count
end

-- 打印详细调试信息
function Module:PrintDetailedDebug()
    if not HekiliHelper.DebugEnabled then return end
    
    local inMelee = self:IsInMeleeCombat()
    local enemies = self:CountEnemiesInMeleeRange()
    local hasTarget = UnitExists("target")
    local db = (HekiliHelper.DB and HekiliHelper.DB.profile and HekiliHelper.DB.profile.meleeIndicator)
    local enabled = db and db.enabled
    
    HekiliHelper:DebugPrint(string.format("|cFFFFFF00[近战指示器]|r 开关:%s 正在近战:%s 5码敌人:%d 目标存在:%s",
        enabled and "开" or "关",
        inMelee and "是" or "否",
        enemies,
        hasTarget and "是" or "否"
    ))
end

-- 获取用户设置的显示图标数量（1-10）
function Module:GetNumIcons()
    local profile = Hekili.DB and Hekili.DB.profile
    if profile and profile.displays and profile.displays.Primary then
        return profile.displays.Primary.numIcons or 3
    end
    return 3  -- 默认值（适配1-10）
end

-- 强制插入逻辑（用于每个Update周期后强制覆盖队列）
function Module:ForceInsertMeleeIndicator()
    -- 检查开关
    local db = HekiliHelper.DB and HekiliHelper.DB.profile and HekiliHelper.DB.profile.meleeIndicator
    if not db or not db.enabled then
        if self.IsActive then
            self:RemoveMeleeIndicator()
            self.IsActive = false
        end
        return
    end

    -- 检查是否应该显示
    local inMelee = self:IsInMeleeCombat()
    local enemies = self:CountEnemiesInMeleeRange()
    local shouldShow = (not inMelee) and (enemies > 0)

    local displays = Hekili.DisplayPool
    if not displays or not displays.Primary then return end

    local UI = displays.Primary
    if not UI.Recommendations then return end
    local Queue = UI.Recommendations

    -- 如果不应该显示但之前是活跃状态，需要移除
    if not shouldShow then
        if self.IsActive then
            -- 恢复原始推荐
            if Queue[1] and Queue[1].originalRecommendation then
                local original = Queue[1].originalRecommendation
                for k, v in pairs(Queue[1]) do Queue[1][k] = nil end
                for k, v in pairs(original) do Queue[1][k] = v end
            else
                Queue[1] = nil
            end
            UI.NewRecommendations = true
            self.IsActive = false
        end
        return
    end

    -- 如果已经有指示器在位置1，也认为是活跃状态
    if Queue[1] and Queue[1].isMeleeIndicator then
        self.IsActive = true
        return
    end

    -- 准备插入图标
    local classIcon = self:GetClassIconPath()
    if not classIcon then return end

    -- 准备插入图标
    local classIcon = self:GetClassIconPath()
    if not classIcon then return end

    -- 动态获取用户设置的显示数量
    local numIcons = self:GetNumIcons()

    -- 方案：将原队列向后移动，保持原推荐不丢失
    -- 保存原始队列以便恢复
    local originalQueue = {}
    -- 只保存用户设置的数量
    for i = 1, numIcons do
        if Queue[i] then
            originalQueue[i] = {}
            for k, v in pairs(Queue[i]) do
                originalQueue[i][k] = v
            end
        end
    end

    -- 将队列向后移动
    -- 根据 numIcons 动态处理
    for i = numIcons, 2, -1 do
        Queue[i] = originalQueue[i - 1]
    end

    -- 在位置1插入近战指示器
    Queue[1] = {}
    local slot = Queue[1]
    slot.index = 1
    slot.actionName = "melee_target_indicator"
    slot.texture = classIcon
    slot.isMeleeIndicator = true
    slot.originalRecommendation = originalQueue[1]  -- 保存原始位置1的内容
    slot.time = 0
    slot.exact_time = GetTime()
    slot.delay = 0
    slot.display = "Primary"

    -- 注册虚拟技能
    if not Hekili.Class.abilities["melee_target_indicator"] then
        Hekili.Class.abilities["melee_target_indicator"] = {
            key = "melee_target_indicator",
            name = "近战目标",
            texture = classIcon,
            id = 0,
            cast = 0,
            gcd = "off",
        }
    end

    UI.NewRecommendations = true
    self.IsActive = true
end

-- 插入逻辑（带停留时间，用于备用）
function Module:InsertMeleeIndicator()
    local now = GetTime()

    -- 检查开关
    local db = HekiliHelper.DB and HekiliHelper.DB.profile and HekiliHelper.DB.profile.meleeIndicator
    if not db or not db.enabled then
        self:RemoveMeleeIndicator()
        self.LastShouldShow = false
        self.LastRecommendationTime = now
        return
    end

    -- 检查是否需要显示
    local inMelee = self:IsInMeleeCombat()
    local enemies = self:CountEnemiesInMeleeRange()
    local shouldShow = (not inMelee) and (enemies > 0)

    local displays = Hekili.DisplayPool
    if not displays or not displays.Primary then return end

    local UI = displays.Primary
    if not UI.Recommendations then return end
    local Queue = UI.Recommendations

    -- 停留时间判断：如果条件不再满足，但仍在停留时间内，保持显示
    if not shouldShow then
        local lingerExpired = (now - self.LastRecommendationTime) >= self.RecommendationLinger

        -- 如果指示器存在且停留时间已过，移除
        if Queue[1] and Queue[1].isMeleeIndicator and lingerExpired then
            self:RemoveMeleeIndicator()
            self.LastShouldShow = false
        end
        -- 更新状态，但不立即移除
        self.LastShouldShow = shouldShow
        return
    end

    -- 如果已经有指示器且在位置1，更新时间戳并返回
    if Queue[1] and Queue[1].isMeleeIndicator then
        self.LastRecommendationTime = now
        self.LastShouldShow = shouldShow
        return
    end

    -- 准备插入图标
    local classIcon = self:GetClassIconPath()
    if not classIcon then return end

    -- 保存原位1的推荐内容
    local originalSlot = nil
    if Queue[1] and not Queue[1].isMeleeIndicator then
        originalSlot = {}
        for k, v in pairs(Queue[1]) do originalSlot[k] = v end
    end
    
    -- 插入到位置1
    Queue[1] = Queue[1] or {}
    local slot = Queue[1]
    slot.index = 1
    slot.actionName = "melee_target_indicator"
    slot.texture = classIcon
    slot.isMeleeIndicator = true
    slot.originalRecommendation = originalSlot
    slot.time = 0
    slot.exact_time = GetTime()
    slot.delay = 0
    slot.display = "Primary"
    
    -- 注册虚拟技能，防止报错
    if not Hekili.Class.abilities["melee_target_indicator"] then
        Hekili.Class.abilities["melee_target_indicator"] = {
            key = "melee_target_indicator",
            name = "近战目标",
            texture = classIcon,
            id = 0,
            cast = 0,
            gcd = "off",
        }
    end
    
    UI.NewRecommendations = true

    -- 更新状态
    self.LastRecommendationTime = GetTime()
    self.LastShouldShow = true
end

-- 移除逻辑
function Module:RemoveMeleeIndicator()
    local displays = Hekili.DisplayPool
    if not displays or not displays.Primary then return end

    local UI = displays.Primary
    local Queue = UI.Recommendations
    if not Queue then return end

    if Queue[1] and Queue[1].isMeleeIndicator then
        -- 恢复原始推荐
        if Queue[1].originalRecommendation then
            local original = Queue[1].originalRecommendation
            for k, v in pairs(Queue[1]) do Queue[1][k] = nil end
            for k, v in pairs(original) do Queue[1][k] = v end
        else
            Queue[1] = nil
        end

        UI.NewRecommendations = true
    end
end
