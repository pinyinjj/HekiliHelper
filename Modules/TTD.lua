-- Modules/TTD.lua
-- TTD (Time To Die) 计算模块
-- 优化版：支持多目标、高性能采样、使用循环队列避免垃圾回收压力

local HekiliHelper = _G.HekiliHelper

if not HekiliHelper then
    C_Timer.After(0.1, function()
        local HH = _G.HekiliHelper
        if HH and not HH.TTD then
            HH.TTD = {}
        end
    end)
    return
end

-- 创建模块对象
if not HekiliHelper.TTD then
    HekiliHelper.TTD = {}
end

local Module = HekiliHelper.TTD

-- 配置常量
local MAX_SAMPLES = 15       -- 样本数，15个足够平衡精度和响应速度
local SAMPLE_THROTTLE = 0.2  -- 采样节流（秒），同一单位0.2秒内只记一次
local SAMPLE_WINDOW = 12     -- 采样窗口（秒）
local MIN_TIME_FOR_TTD = 1.5 -- 开始计算所需的最小观测时间

-- 内部变量
-- unitData 以 GUID 为键，确保单位追踪的唯一性
local unitData = {} 

-- 模块初始化
function Module:Initialize()
    -- 防止重复初始化（即使Initialize崩溃也要标记，避免无限重试）
    if self.initialized == true then
        return true
    end

    if not self.frame then
        self.frame = CreateFrame("Frame")
        self.frame:SetScript("OnEvent", function(_, event, ...)
            if event == "UNIT_HEALTH" or event == "UNIT_MAX_HEALTH" then
                local unit = ...
                if unit then
                    self:UpdateUnitData(unit)
                end
            elseif event == "PLAYER_TARGET_CHANGED" then
                self:UpdateUnitData("target")
            elseif event == "PLAYER_REGEN_ENABLED" then
                -- 战斗结束清空缓存，释放内存
                self:ClearAllData()
            end
        end)
    end

    -- 立即标记为已初始化，防止重复调用时崩溃
    self.initialized = true

    local ok, err = pcall(function()
        self.frame:RegisterEvent("UNIT_HEALTH")
        self.frame:RegisterEvent("UNIT_MAX_HEALTH")
        self.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
        self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end)
    if not ok then
        HekiliHelper:DebugPrint(string.format("[TTD] RegisterEvent错误: %s", tostring(err)))
        self.initialized = false
        return false
    end

    return true
end

-- 清空所有数据
function Module:ClearAllData()
    unitData = {}
end

-- 更新单位数据
function Module:UpdateUnitData(unit)
    -- 仅追踪敌方存活单位
    if not UnitExists(unit) or UnitIsDead(unit) or UnitIsFriend("player", unit) then
        return
    end

    local guid = UnitGUID(unit)
    if not guid then return end

    local now = GetTime()
    local data = unitData[guid]

    -- 初始化新单位数据
    if not data then
        data = {
            guid = guid,
            samples = {},
            ptr = 1,      -- 循环队列指针
            count = 0,    -- 当前样本数量
            lastUpdate = 0
        }
        unitData[guid] = data
    end

    -- 节流检查：避免过快采样（同一单位0.2秒内不重复记录）
    if now - data.lastUpdate < SAMPLE_THROTTLE then
        return
    end

    local currentHealth = UnitHealth(unit)
    
    -- 如果是第一个样本，或者血量发生了变化，则记录
    local lastIdx = data.ptr - 1
    if lastIdx < 1 then lastIdx = MAX_SAMPLES end
    
    if data.count == 0 or data.samples[lastIdx].health ~= currentHealth then
        -- 循环队列写入
        data.samples[data.ptr] = {
            time = now,
            health = currentHealth
        }
        
        -- 更新指针
        data.ptr = (data.ptr % MAX_SAMPLES) + 1
        data.count = math.min(data.count + 1, MAX_SAMPLES)
        data.lastUpdate = now
    end
end

-- 获取 TTD（秒）
function Module:GetTTD(unit)
    if not UnitExists(unit) or UnitIsDead(unit) then
        return nil
    end

    local guid = UnitGUID(unit)
    local data = unitData[guid]
    
    -- 如果缓存中没有，尝试立即更新一次
    if not data then
        self:UpdateUnitData(unit)
        return nil
    end

    if data.count < 2 then
        return nil
    end

    -- 获取循环队列中最旧和最新的样本
    local firstIdx = 1
    if data.count == MAX_SAMPLES then
        firstIdx = data.ptr -- 在满队列中，指针指向的就是最旧的
    end
    
    local lastIdx = data.ptr - 1
    if lastIdx < 1 then lastIdx = MAX_SAMPLES end
    
    local first = data.samples[firstIdx]
    local last = data.samples[lastIdx]
    
    local timeDiff = last.time - first.time
    local healthDiff = first.health - last.health

    -- 检查观测时间是否足够，以及血量是否在下降
    if timeDiff < MIN_TIME_FOR_TTD or healthDiff <= 0 then
        return nil
    end

    local dps = healthDiff / timeDiff
    local currentHealth = UnitHealth(unit)
    
    -- 计算预计剩余时间
    local ttd = currentHealth / dps
    
    -- 如果 TTD 异常大（比如木桩或正在回血的目标），返回 nil
    if ttd > 3600 then return nil end
    
    return ttd
end

-- 获取格式化的 TTD 字符串
function Module:GetTTDString(unit)
    local ttd = self:GetTTD(unit)
    if not ttd then
        return "--:--"
    end

    if ttd > 600 then 
        return ">10m"
    end

    local minutes = math.floor(ttd / 60)
    local seconds = math.floor(ttd % 60)
    
    if minutes > 0 then
        return string.format("%dm %02ds", minutes, seconds)
    else
        return string.format("%ds", seconds)
    end
end
