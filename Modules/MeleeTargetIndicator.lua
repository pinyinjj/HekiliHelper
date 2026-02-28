-- Modules/MeleeTargetIndicator.lua
-- 近战目标指示器模块
-- 在优先级队列中插入近战目标指示图标
-- 当玩家身边近战范围内（5码）存在敌方存活单位，但玩家没有目标或目标超出近战范围时显示

-- 获取HekiliHelper对象（这个文件在HekiliHelper.lua之后加载，所以对象应该已存在）
local HekiliHelper = _G.HekiliHelper

if not HekiliHelper then
    -- 如果HekiliHelper还不存在，说明加载顺序有问题
    -- 这种情况下，我们延迟创建模块
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
    
    HekiliHelper:DebugPrint("|cFF00FF00[MeleeIndicator]|r 开始Hook Hekili.Update...")
    
    -- Hook Hekili.Update函数
    local success = HekiliHelper.HookUtils.Wrap(Hekili, "Update", function(oldFunc, self, ...)
        -- 调用原函数生成推荐
        local result = oldFunc(self, ...)
        
        -- 在所有推荐生成完成后，为每个激活的显示插入图标
        -- 使用更短的延迟，减少与Hekili更新的竞争
        C_Timer.After(0.001, function()
            Module:InsertMeleeIndicator()
        end)
        
        return result
    end)
    
    if success then
        HekiliHelper:DebugPrint("|cFF00FF00[MeleeIndicator]|r 模块已初始化，Hook成功")
        return true
    else
        HekiliHelper:Print("|cFFFF0000[MeleeIndicator]|r Hook失败")
        return false
    end
end

-- 获取职业图标路径
function Module:GetClassIconPath()
    local class = UnitClassBase("player")
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
-- 只检查是否真的在攻击，而不是仅仅检查目标是否在范围内
function Module:IsInMeleeCombat()
    -- 检查是否在自动攻击
    local isAutoAttacking = IsCurrentSpell(6603) -- 自动攻击
    if isAutoAttacking then
        return true
    end
    
    -- 检查是否在施法
    local isCasting = UnitCastingInfo("player") ~= nil
    local isChanneling = UnitChannelInfo("player") ~= nil
    if isCasting or isChanneling then
        return true
    end
    
    -- 检查Hekili状态系统，看是否在攻击
    if Hekili.State then
        -- 如果正在施法或引导
        if Hekili.State.buff and Hekili.State.buff.casting and Hekili.State.buff.casting.up then
            return true
        end
    end
    
    return false
end

-- 计算近战范围内敌人数量的辅助函数
function Module:CountEnemiesInMeleeRange()
    local RC = LibStub("LibRangeCheck-2.0")
    if not RC then return 0 end
    
    local count = 0
    local unitsToCheck = {}
    local checkedGUIDs = {}
    
    -- 添加标准单位
    table.insert(unitsToCheck, "target")
    table.insert(unitsToCheck, "focus")
    
    -- 添加boss单位
    for i = 1, 5 do
        table.insert(unitsToCheck, "boss" .. i)
    end
    
    -- 添加nameplate单位（从npGUIDs获取）
    -- npGUIDs的结构：key是unit（字符串），value是GUID
    if Hekili.npGUIDs then
        for unit, guid in pairs(Hekili.npGUIDs) do
            if unit and type(unit) == "string" then
                -- 检查是否已经存在（避免重复）
                local exists = false
                for _, u in ipairs(unitsToCheck) do
                    if u == unit or UnitIsUnit(u, unit) then
                        exists = true
                        break
                    end
                end
                if not exists then
                    table.insert(unitsToCheck, unit)
                end
            end
        end
    end
    
    -- 尝试使用C_NamePlate API获取所有nameplate（如果可用）
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local nameplates = C_NamePlate.GetNamePlates()
        if nameplates then
            for _, nameplateFrame in ipairs(nameplates) do
                if nameplateFrame and nameplateFrame.namePlateUnitToken then
                    local unit = nameplateFrame.namePlateUnitToken
                    if unit and UnitExists(unit) and not UnitIsFriend("player", unit) then
                        -- 检查是否已经存在
                        local exists = false
                        for _, u in ipairs(unitsToCheck) do
                            if u == unit or UnitIsUnit(u, unit) then
                                exists = true
                                break
                            end
                        end
                        if not exists then
                            table.insert(unitsToCheck, unit)
                        end
                    end
                end
            end
        end
    end
    
    -- 遍历所有单位，统计近战范围内的敌人
    for _, unit in ipairs(unitsToCheck) do
        if UnitExists(unit) and not UnitIsDead(unit) and UnitCanAttack("player", unit) and UnitInPhase(unit) then
            local guid = UnitGUID(unit)
            -- 避免重复计数同一个单位
            if guid and not checkedGUIDs[guid] then
                checkedGUIDs[guid] = true
                local minRange, maxRange = RC:GetRange(unit)
                if minRange and maxRange then
                    if maxRange <= 5 then
                        count = count + 1
                    end
                end
            end
        end
    end
    
    return count
end

-- 打印角色状态的辅助函数
function Module:PrintStatus(prefix, shouldShow)
    if not HekiliHelper.DebugEnabled then
        return
    end
    
    local RC = LibStub("LibRangeCheck-2.0")
    
    local hasTarget = UnitExists("target")
    local targetDead = hasTarget and UnitIsDead("target")
    local canAttack = hasTarget and UnitCanAttack("player", "target")
    local minRange, maxRange = nil, nil
    if hasTarget and RC then
        minRange, maxRange = RC:GetRange("target")
    end
    
    local inMeleeCombat = self:IsInMeleeCombat()
    local meleeRangeEnemies = self:CountEnemiesInMeleeRange()
    local inCombat = UnitAffectingCombat("player")
    
    HekiliHelper:DebugPrint(string.format("|cFF00FFFF[%s]|r 战斗:%s 目标存在:%s 可攻击:%s 死亡:%s 距离:%.1f-%.1f 近战:%s 近战范围敌人:%d 显示:%s",
        prefix or "状态",
        inCombat and "是" or "否",
        hasTarget and "是" or "否",
        canAttack and "是" or "否",
        targetDead and "是" or "否",
        minRange or 0,
        maxRange or 0,
        inMeleeCombat and "是" or "否",
        meleeRangeEnemies,
        shouldShow and "|cFF00FF00是|r" or "|cFFFF0000否|r"
    ))
end

-- 检查是否需要显示图标
function Module:ShouldShowMeleeIndicator()
    -- 如果玩家在近战攻击中，不显示
    local inMeleeCombat = self:IsInMeleeCombat()
    if inMeleeCombat then
        self:PrintStatus("近战检查", false)
        return false
    end
    
    -- 检查近战范围内（5码）是否有可攻击的敌人
    -- 使用CountEnemiesInMeleeRange函数来检查
    local meleeRangeEnemyCount = self:CountEnemiesInMeleeRange()
    
    if meleeRangeEnemyCount == 0 then
        self:PrintStatus("敌人检查", false)
        return false
    end
    
    -- 有近战范围内的敌人，且不在近战攻击中，显示图标
    self:PrintStatus("最终检查", true)
    return true
end

-- 插入近战指示器
-- 移除所有显示中的近战指示器
function Module:RemoveMeleeIndicator()
    if not Hekili or not Hekili.DisplayPool then
        return
    end
    
    local displays = Hekili.DisplayPool
    for dispName, UI in pairs(displays) do
        if UI and UI.Recommendations then
            local Queue = UI.Recommendations
            for i = 1, 4 do
                if Queue[i] and Queue[i].isMeleeIndicator then
                    -- 如果有保存的原始推荐，恢复它
                    if Queue[i].originalRecommendation then
                        local original = Queue[i].originalRecommendation
                        -- 清除当前指示器
                        for k, v in pairs(Queue[i]) do
                            Queue[i][k] = nil
                        end
                        -- 恢复原始推荐
                        for k, v in pairs(original) do
                            Queue[i][k] = v
                        end
                    else
                        -- 没有原始推荐，清除指示器
                        Queue[i].actionName = nil
                        Queue[i].actionID = nil
                        Queue[i].texture = nil
                        Queue[i].isMeleeIndicator = nil
                    end
                    UI.NewRecommendations = true
                end
            end
        end
    end
end

function Module:InsertMeleeIndicator()
    if not Hekili then
        return
    end
    
    -- 检查开关是否启用
    local db = HekiliHelper and HekiliHelper.DB and HekiliHelper.DB.profile
    if not db or not db.meleeIndicator or db.meleeIndicator.enabled == false then
        -- 开关关闭，移除已存在的指示器
        self:RemoveMeleeIndicator()
        return
    end

    -- 默认不对远程职业开启
    -- 如果是远程职业且没有在配置中明确强制开启（目前配置只有全局开关），则跳过
    local class = UnitClassBase("player")
    local isRanged = (class == "HUNTER" or class == "MAGE" or class == "WARLOCK" or class == "PRIEST")
    
    -- 德鲁伊和萨满比较特殊，检查当前天赋/姿态
    if class == "DRUID" then
        -- 检查姿态：只有在猎豹或熊形态下才认为是近战
        local form = GetShapeshiftForm()
        if form ~= 1 and form ~= 3 then -- 1: 熊, 3: 猎豹
            isRanged = true
        end
    elseif class == "SHAMAN" then
        -- 萨满检查：如果是元素或恢复，视为远程
        -- 在怀旧服中通过检查天赋点数来简单判断
        local _, _, _, _, points1 = GetTalentTabInfo(1) -- 元素
        local _, _, _, _, points3 = GetTalentTabInfo(3) -- 恢复
        if (points1 and points1 > 20) or (points3 and points3 > 20) then
            isRanged = true
        end
    end

    if isRanged then
        self:RemoveMeleeIndicator()
        return
    end
    
    -- 使用Hekili.DisplayPool访问displays对象（这是ns.UI.Displays的别名）
    local displays = Hekili.DisplayPool
    if not displays then
        -- 尝试通过Hekili访问ns（如果可用）
        -- ns通常在Hekili插件的命名空间中，但可能不在全局作用域
        -- 如果Hekili.DisplayPool不存在，说明Hekili可能还没完全初始化
        return
    end
    
    -- 调试：检查是否有激活的显示
    local activeCount = 0
    for dispName, UI in pairs(displays) do
        if UI and UI.Active and UI.alpha > 0 then
            activeCount = activeCount + 1
        end
    end
    
    if activeCount == 0 then
        -- 没有激活的显示，不需要插入
        return
    end
    
    -- 遍历所有激活的显示
    local processedCount = 0
    for dispName, UI in pairs(displays) do
        -- 彻底忽略 AOE 和其他非 Primary 显示
        if dispName == "Primary" and UI and UI.Active and UI.alpha > 0 then
            processedCount = processedCount + 1
            self:InsertIndicatorForDisplay(dispName, UI)
        end
    end
    
    if processedCount > 0 then
        HekiliHelper:DebugPrint(string.format("|cFF00FFFF[MeleeIndicator]|r 处理了 %d 个激活的显示", processedCount))
    end
end

-- 为特定显示插入指示器
function Module:InsertIndicatorForDisplay(dispName, UI)
    -- 只对 Primary 显示插入图标，不处理 AOE
    if dispName ~= "Primary" then
        return
    end
    
    if not UI or not UI.Recommendations then
        return
    end
    
    local Queue = UI.Recommendations
    
    -- 检查是否需要显示图标
    local shouldShow = self:ShouldShowMeleeIndicator()
    
    -- 调试信息
    HekiliHelper:DebugPrint(string.format("|cFF00FFFF[MeleeIndicator]|r 检查显示: %s, 应该显示: %s", dispName, shouldShow and "是" or "否"))
    
    -- 检查队列中是否已经有指示器（参考Hekili - Copy的实现）
    local alreadyHasIcon = false
    local indicatorSlot = nil
    for i = 1, 4 do
        if Queue[i] and Queue[i].isMeleeIndicator then
            alreadyHasIcon = true
            indicatorSlot = i
            break
        end
    end
    
    -- 如果应该显示且已经存在，检查是否需要更新
    if shouldShow and alreadyHasIcon then
        -- 检查指示器是否完整且正确，且已经在位置1
        if indicatorSlot == 1 and Queue[1].actionName == "melee_target_indicator" and Queue[1].texture then
            -- 指示器已在位置1且完整，不需要更新
            return
        end
        -- 如果指示器不在位置1或不完整，需要移动到位置1或更新
    end
    
    -- 如果不需要显示且没有指示器，直接返回
    if not shouldShow and not alreadyHasIcon then
        return
    end
    
    -- 状态需要变化，执行更新
    if not shouldShow then
        -- 移除可能存在的指示器，恢复原始推荐
        if indicatorSlot and Queue[indicatorSlot] and Queue[indicatorSlot].isMeleeIndicator then
            -- 如果有保存的原始推荐，恢复它
            if Queue[indicatorSlot].originalRecommendation then
                local original = Queue[indicatorSlot].originalRecommendation
                -- 清除当前指示器
                for k, v in pairs(Queue[indicatorSlot]) do
                    Queue[indicatorSlot][k] = nil
                end
                -- 恢复原始推荐
                for k, v in pairs(original) do
                    Queue[indicatorSlot][k] = v
                end
            else
                -- 没有原始推荐，清除指示器
                Queue[indicatorSlot].actionName = nil
                Queue[indicatorSlot].actionID = nil
                Queue[indicatorSlot].texture = nil
                Queue[indicatorSlot].isMeleeIndicator = nil
            end
            -- 只在真正移除时才触发UI更新
            UI.NewRecommendations = true
        end
        return
    end
    
    -- 应该显示指示器
    local classIcon = self:GetClassIconPath()
    if not classIcon then
        return
    end
    
    -- 始终插入到位置1（最优先显示）
    local insertIndex = 1
    
    -- 如果指示器已经在位置1，直接更新即可
    if indicatorSlot == 1 then
        -- 指示器已在位置1，直接更新
        local slot = Queue[1]
        slot.actionName = "melee_target_indicator"
        slot.actionID = 0
        slot.texture = classIcon
        slot.isMeleeIndicator = true
        -- 保持其他属性不变
        UI.NewRecommendations = true
        return
    end
    
    -- 如果指示器在其他位置，需要移动到位置1
    if indicatorSlot and indicatorSlot > 1 then
        -- 清除原位置的指示器
        Queue[indicatorSlot] = nil
    end
    
    -- 保存位置1的原始推荐（如果不是指示器）
    local originalSlot = nil
    if Queue[1] and Queue[1].actionName and not Queue[1].isMeleeIndicator then
        originalSlot = {}
        for k, v in pairs(Queue[1]) do
            originalSlot[k] = v
        end
    end
    
    -- 创建或更新slot（参考Hekili - Copy的实现）
    Queue[insertIndex] = Queue[insertIndex] or {}
    local slot = Queue[insertIndex]
    
    -- 设置图标信息（参考Hekili - Copy的时间属性设置方式）
    slot.index = 1  -- 始终是位置1
    slot.actionName = "melee_target_indicator"
    slot.actionID = 0
    slot.texture = classIcon
    slot.caption = nil
    slot.indicator = nil
    -- 使用当前时间而不是固定0值（参考Hekili - Copy使用state.now + state.offset的方式）
    local currentTime = GetTime()
    slot.time = 0  -- 指示器不需要延迟
    slot.exact_time = currentTime
    slot.delay = 0  -- 位置1不需要延迟
    slot.since = 0  -- 位置1的since为0
    slot.resources = {}
    slot.depth = 0
    slot.keybind = nil
    slot.keybindFrom = nil
    slot.resource_type = nil
    slot.scriptType = nil
    slot.script = nil
    slot.hook = nil
    slot.display = dispName
    slot.pack = nil
    slot.list = nil
    slot.listName = nil
    slot.action = nil
    
    -- 标记为特殊指示器，并保存原始推荐
    slot.isMeleeIndicator = true
    slot.originalRecommendation = originalSlot
    
    -- 在class.abilities中创建一个虚拟ability，以便UI能正确显示
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
    
    -- 只在真正插入/更新时才触发UI更新
    UI.NewRecommendations = true
end
