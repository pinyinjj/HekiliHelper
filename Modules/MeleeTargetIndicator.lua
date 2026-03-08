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
    
    -- 使用HookUtils.Hook在Hekili.Update之后执行我们的逻辑
    local success = HekiliHelper.HookUtils.Hook(Hekili, "Update", function()
        Module:InsertMeleeIndicator()
    end, "after")
    
    if success then
        return true
    else
        return false
    end
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

-- 插入逻辑
function Module:InsertMeleeIndicator()
    -- 频率限制：Hekili.Update调用极其频繁，在这里做个简单限制或只在调试时打印
    -- self:PrintDetailedDebug()

    -- 检查开关
    local db = HekiliHelper.DB and HekiliHelper.DB.profile and HekiliHelper.DB.profile.meleeIndicator
    if not db or not db.enabled then
        self:RemoveMeleeIndicator()
        return
    end
    
    -- 只要开关开了，我们就检查是否需要显示
    local inMelee = self:IsInMeleeCombat()
    local enemies = self:CountEnemiesInMeleeRange()
    local shouldShow = (not inMelee) and (enemies > 0)
    
    local displays = Hekili.DisplayPool
    if not displays or not displays.Primary then return end
    
    local UI = displays.Primary
    if not UI.Recommendations then return end
    local Queue = UI.Recommendations
    
    -- 如果不应该显示，移除
    if not shouldShow then
        -- 仅当队列中确实有指示器时才执行移除，避免频繁清理
        if Queue[1] and Queue[1].isMeleeIndicator then
            self:RemoveMeleeIndicator()
        end
        return
    end
    
    -- 如果已经有指示器且在位置1，跳过
    if Queue[1] and Queue[1].isMeleeIndicator then
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
end

-- 移除逻辑
function Module:RemoveMeleeIndicator()
    local displays = Hekili.DisplayPool
    if not displays or not displays.Primary then return end
    
    local UI = displays.Primary
    local Queue = UI.Recommendations
    if not Queue then return end
    
    if Queue[1] and Queue[1].isMeleeIndicator then
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
