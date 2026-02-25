-- HekiliHelper.lua
-- 独立的Hekili辅助插件

local addonName = "HekiliHelper"
local HekiliHelper = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceEvent-3.0", "AceConsole-3.0")

-- 确保对象在全局命名空间中可用（供模块文件访问）
_G.HekiliHelper = HekiliHelper

HekiliHelper.Version = "1.0.0"

-- 调试开关配置（默认关闭）
HekiliHelper.DebugEnabled = false

-- 调试窗口相关
HekiliHelper.DebugWindow = nil
HekiliHelper.DebugMessages = {}

-- 创建调试窗口
function HekiliHelper:CreateDebugWindow()
    if self.DebugWindow then
        return
    end
    
    -- 创建主窗口
    local frame = CreateFrame("Frame", "HekiliHelperDebugWindow", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(600, 400)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    
    -- 设置标题
    frame.TitleText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.TitleText:SetPoint("LEFT", frame.TitleBg, "LEFT", 5, 0)
    frame.TitleText:SetText("HekiliHelper 调试窗口")
    
    -- 创建滚动框架
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 50)
    
    -- 创建编辑框（用于显示文本）
    local editBox = CreateFrame("EditBox", nil, frame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(scrollFrame:GetWidth() > 0 and scrollFrame:GetWidth() or 560)
    editBox:SetAutoFocus(false)
    editBox:SetTextInsets(5, 5, 5, 5)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        -- 允许编辑框获取焦点用于复制文本
    end)
    editBox:SetScript("OnTextChanged", function(self)
        scrollFrame:UpdateScrollChildRect()
        local min, max = scrollFrame:GetScrollRange()
        if max > 0 then
            scrollFrame:SetScrollOffset(max)
        end
    end)
    
    scrollFrame:SetScrollChild(editBox)
    frame.editBox = editBox
    frame.scrollFrame = scrollFrame
    
    -- 创建关闭按钮
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    local parent = self -- 保存引用
    closeButton:SetScript("OnClick", function()
        -- 彻底关闭调试模式
        parent.DebugEnabled = false
        if parent.DB then
            parent.DB.profile.debugEnabled = false
        end
        
        -- 记录状态并隐藏
        frame.ManuallyClosed = true
        frame:Hide()
        parent:Print("|cFF00FF00[HekiliHelper]|r 调试模式已关闭")
        
        -- 通知 AceConfig 刷新界面
        if LibStub("AceConfigRegistry-3.0") then
            LibStub("AceConfigRegistry-3.0"):NotifyChange("Hekili")
            LibStub("AceConfigRegistry-3.0"):NotifyChange("HekiliHelper")
        end
    end)
    
    -- 创建清空按钮
    local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearButton:SetSize(80, 22)
    clearButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    clearButton:SetText("清空")
    clearButton:SetScript("OnClick", function()
        self.DebugMessages = {}
        editBox:SetText("")
    end)
    
    -- 创建滚动到底部按钮
    local scrollBottomButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    scrollBottomButton:SetSize(100, 22)
    scrollBottomButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    scrollBottomButton:SetText("滚动到底部")
    scrollBottomButton:SetScript("OnClick", function()
        local max = scrollFrame:GetVerticalScrollRange()
        if max > 0 then
            scrollFrame:SetVerticalScroll(max)
        end
    end)
    
    self.DebugWindow = frame
    
    -- 如果有已保存的消息，立即显示
    if #self.DebugMessages > 0 then
        self:UpdateDebugWindow()
    end
end

-- 更新调试窗口内容
function HekiliHelper:UpdateDebugWindow()
    if not self.DebugWindow or not self.DebugWindow.editBox then
        return
    end
    
    local text = table.concat(self.DebugMessages, "\n")
    self.DebugWindow.editBox:SetText(text)
    
    -- 滚动到底部
    C_Timer.After(0.01, function()
        if self.DebugWindow and self.DebugWindow.scrollFrame then
            local max = self.DebugWindow.scrollFrame:GetVerticalScrollRange()
            if max > 0 then
                self.DebugWindow.scrollFrame:SetVerticalScroll(max)
            end
        end
    end)
end

-- 添加调试消息
function HekiliHelper:AddDebugMessage(message)
    -- 移除颜色代码，保留纯文本（EditBox不支持颜色代码）
    local cleanMessage = message:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    
    -- 添加时间戳
    local timeStr = date("%H:%M:%S")
    local formattedMessage = string.format("[%s] %s", timeStr, cleanMessage)
    
    table.insert(self.DebugMessages, formattedMessage)
    
    -- 限制消息数量（保留最近500条）
    if #self.DebugMessages > 500 then
        table.remove(self.DebugMessages, 1)
    end
    
    -- 如果调试窗口已创建且显示中，更新内容
    if self.DebugWindow and self.DebugWindow:IsShown() then
        self:UpdateDebugWindow()
    end
end

-- 调试打印函数（只有在DebugEnabled为true时才打印到窗口）
function HekiliHelper:DebugPrint(message)
    -- 强力检查：如果数据库中是关闭的，强制同步变量并拒绝任何操作
    if self.DB and self.DB.profile and self.DB.profile.debugEnabled == false then
        self.DebugEnabled = false
    end

    if not self.DebugEnabled then
        if self.DebugWindow and self.DebugWindow:IsShown() then
            self.DebugWindow:Hide()
        end
        return
    end

    -- 确保调试窗口已创建
    if not self.DebugWindow then
        self:CreateDebugWindow()
    end
    
    -- 添加消息
    self:AddDebugMessage(message)
    
    -- 最终显示检查
    if self.DebugWindow and not self.DebugWindow.ManuallyClosed then
        self.DebugWindow:Show()
    end
end

-- 检查Hekili是否已加载
local function CheckHekiliLoaded()
    if not Hekili then
        return false
    end
    
    -- 等待Hekili完全初始化
    if not Hekili.Update then
        return false
    end
    
    return true
end

function HekiliHelper:OnInitialize()
    self:Print("|cFF00FF00[HekiliHelper]|r 插件已加载，版本 " .. self.Version)
    
    -- 初始化数据库
    local defaults = {
        profile = {
            enabled = true,
            debugEnabled = false,
            meleeIndicator = {
                enabled = true,
                checkRange = 5,
            },
            healingShaman = {
                enabled = true,
                riptideThreshold = 99,
                tideForceThreshold = 50,
                chainHealThreshold = 90,
                healingWaveThreshold = 30,
                lesserHealingWaveThreshold = 90,
            },
            healingPriest = {
                enabled = true,
                shieldThreshold = 95,
                pomThreshold = 99,
                penanceThreshold = 80,
                renewThreshold = 90,
                flashHealThreshold = 70,
                greaterHealThreshold = 40,
                cohThreshold = 85,
            },
        }
    }
    
    self.DB = LibStub("AceDB-3.0"):New("HekiliHelperDB", defaults, true)
    
    -- 同步调试设置
    self.DebugEnabled = self.DB.profile.debugEnabled or false
    
    -- 如果调试模式已启用，创建并显示调试窗口
    if self.DebugEnabled then
        C_Timer.After(0.5, function()
            if not self.DebugWindow then
                self:CreateDebugWindow()
            end
            if self.DebugWindow then
                self.DebugWindow:Show()
            end
        end)
    end
    
    -- 注册控制台命令
    self:RegisterChatCommand("hhdebug", "ToggleDebug")
    self:RegisterChatCommand("hekilihelperdebug", "ToggleDebug")
    self:RegisterChatCommand("hhdebugwin", "ShowDebugWindow")
    self:RegisterChatCommand("hhlist", "PrintRecommendationQueue")
    
    -- 创建模块对象（如果模块文件已加载）
    if not self.MeleeTargetIndicator then
        self.MeleeTargetIndicator = {}
        self:DebugPrint("|cFF00FF00[HekiliHelper]|r 创建MeleeTargetIndicator模块对象")
    else
        self:DebugPrint("|cFF00FF00[HekiliHelper]|r MeleeTargetIndicator模块对象已存在")
    end
    
    if not self.HealingShamanSkills then
        self.HealingShamanSkills = {}
        self:DebugPrint("|cFF00FF00[HekiliHelper]|r 创建HealingShamanSkills模块对象")
    else
        self:DebugPrint("|cFF00FF00[HekiliHelper]|r HealingShamanSkills模块对象已存在")
    end

    if not self.HealingPriestSkills then
        self.HealingPriestSkills = {}
        self:DebugPrint("|cFF00FF00[HekiliHelper]|r 创建HealingPriestSkills模块对象")
    else
        self:DebugPrint("|cFF00FF00[HekiliHelper]|r HealingPriestSkills模块对象已存在")
    end
    
    if not self.BlankIcon then
        self.BlankIcon = {}
        self:DebugPrint("|cFF00FF00[HekiliHelper]|r 创建BlankIcon模块对象")
    else
        self:DebugPrint("|cFF00FF00[HekiliHelper]|r BlankIcon模块对象已存在")
    end
end

function HekiliHelper:OnEnable()
    self:DebugPrint("|cFF00FF00[HekiliHelper]|r 插件已启用，等待Hekili加载...")
    
    -- 使用定时器检查Hekili是否已加载（因为ADDON_LOADED事件可能已经触发）
    local checkCount = 0
    local maxChecks = 20  -- 最多检查20次（10秒）
    
    local function CheckAndInit()
        checkCount = checkCount + 1
        
        if CheckHekiliLoaded() then
            self:DebugPrint("|cFF00FF00[HekiliHelper]|r 检测到Hekili已加载，初始化模块...")
            self:InitializeModules()
        elseif checkCount < maxChecks then
            -- 继续等待
            C_Timer.After(0.5, CheckAndInit)
        else
            self:Print("|cFFFF0000[HekiliHelper]|r 超时: 无法检测到Hekili加载")
        end
    end
    
    -- 立即检查一次
    C_Timer.After(0.5, CheckAndInit)
end


function HekiliHelper:OnDisable()
    -- 插件禁用时的逻辑
end

-- 切换调试开关的控制台命令
function HekiliHelper:ToggleDebug(input)
    self.DebugEnabled = not self.DebugEnabled
    if self.DB then
        self.DB.profile.debugEnabled = self.DebugEnabled
    end
    
    if self.DebugEnabled then
        -- 确保调试窗口已创建
        if not self.DebugWindow then
            self:CreateDebugWindow()
        end
        
        -- 显示调试窗口
        if self.DebugWindow then
            self.DebugWindow.ManuallyClosed = false
            self.DebugWindow:Show()
        end
        
        self:Print("|cFF00FF00[HekiliHelper]|r 调试模式已开启 - 调试窗口已显示")
    else
        -- 隐藏调试窗口
        if self.DebugWindow then
            self.DebugWindow:Hide()
        end
        
        self:Print("|cFF00FF00[HekiliHelper]|r 调试模式已关闭 - 调试窗口已隐藏")
    end
    
    -- 同步 UI 状态
    if LibStub("AceConfigRegistry-3.0") then
        LibStub("AceConfigRegistry-3.0"):NotifyChange("Hekili")
        LibStub("AceConfigRegistry-3.0"):NotifyChange("HekiliHelper")
    end
end

-- 显示/隐藏调试窗口的命令
function HekiliHelper:ShowDebugWindow(input)
    if not self.DebugWindow then
        self:CreateDebugWindow()
    end
    
    if self.DebugWindow:IsShown() then
        self.DebugWindow:Hide()
        self.DebugWindow.ManuallyClosed = true
        self:Print("|cFF00FF00[HekiliHelper]|r 调试窗口已隐藏")
    else
        self.DebugWindow.ManuallyClosed = false
        self.DebugWindow:Show()
        self:Print("|cFF00FF00[HekiliHelper]|r 调试窗口已显示")
    end
end

-- 初始化所有模块
function HekiliHelper:InitializeModules()
    if not CheckHekiliLoaded() then
        self:Print("|cFFFF0000[HekiliHelper]|r 错误: Hekili未加载，无法初始化模块")
        -- 再次尝试延迟初始化
        C_Timer.After(2.0, function()
            if CheckHekiliLoaded() then
                self:InitializeModules()
            else
                self:Print("|cFFFF0000[HekiliHelper]|r 错误: 延迟初始化失败，Hekili仍未加载")
            end
        end)
        return
    end
    
    self:DebugPrint("|cFF00FF00[HekiliHelper]|r 正在初始化模块...")
    self:DebugPrint("|cFF00FF00[HekiliHelper]|r Hekili.Update存在: " .. (Hekili.Update and "是" or "否"))
    
    -- 集成选项到Hekili
    self:IntegrateOptions()
    
    -- 检查模块是否存在并初始化
    if self.MeleeTargetIndicator then
        self:DebugPrint("|cFF00FF00[HekiliHelper]|r 找到MeleeTargetIndicator模块，开始初始化...")
        local success = self.MeleeTargetIndicator:Initialize()
        if success then
            self:DebugPrint("|cFF00FF00[HekiliHelper]|r MeleeTargetIndicator模块初始化成功")
        else
            self:Print("|cFFFF0000[HekiliHelper]|r MeleeTargetIndicator模块初始化失败")
        end
    else
        self:Print("|cFFFF0000[HekiliHelper]|r 错误: MeleeTargetIndicator模块未找到")
    end
    
        if self.HealingShamanSkills then
            self:DebugPrint("|cFF00FF00[HekiliHelper]|r 找到HealingShamanSkills模块，开始初始化...")
            local success = self.HealingShamanSkills:Initialize()
            if success then
                self:DebugPrint("|cFF00FF00[HekiliHelper]|r HealingShamanSkills模块初始化成功")
            else
                self:Print("|cFFFF0000[HekiliHelper]|r HealingShamanSkills模块初始化失败")
            end
        else
            self:DebugPrint("|cFFFF0000[HekiliHelper]|r 警告: HealingShamanSkills模块未找到（可能未加载）")
        end
    
        if self.HealingPriestSkills then
            self:DebugPrint("|cFF00FF00[HekiliHelper]|r 找到HealingPriestSkills模块，开始初始化...")
            local success = self.HealingPriestSkills:Initialize()
            if success then
                self:DebugPrint("|cFF00FF00[HekiliHelper]|r HealingPriestSkills模块初始化成功")
            else
                self:Print("|cFFFF0000[HekiliHelper]|r HealingPriestSkills模块初始化失败")
            end
        else
            self:DebugPrint("|cFFFF0000[HekiliHelper]|r 警告: HealingPriestSkills模块未找到（可能未加载）")
        end
        
        if self.BlankIcon then        self:DebugPrint("|cFF00FF00[HekiliHelper]|r 找到BlankIcon模块，开始初始化...")
        local success = self.BlankIcon:Initialize()
        if success then
            self:DebugPrint("|cFF00FF00[HekiliHelper]|r BlankIcon模块初始化成功")
        else
            self:Print("|cFFFF0000[HekiliHelper]|r BlankIcon模块初始化失败")
        end
    else
        self:DebugPrint("|cFFFF0000[HekiliHelper]|r 警告: BlankIcon模块未找到（可能未加载）")
    end
    
    -- Hook Hekili.Update 来自动打印队列（仅在调试模式开启时）
    HekiliHelper.HookUtils.Hook(Hekili, "Update", function()
        if self.DebugEnabled then
            -- 延迟执行，确保其他模块已经完成了它们的插入
            C_Timer.After(0.02, function()
                self:PrintRecommendationQueue()
            end)
        end
    end, "after")
end

-- 打印当前推荐队列（调试用）
function HekiliHelper:PrintRecommendationQueue()
    if not Hekili or not Hekili.DisplayPool then
        return
    end
    
    local found = false
    local displayStrings = {}
    
    for dispName, UI in pairs(Hekili.DisplayPool) do
        -- 检查显示是否激活且可见
        if UI and UI.Active and UI.alpha > 0 and UI.Recommendations then
            local queue = UI.Recommendations
            local actions = {}
            -- 检查前10个推荐位
            for i = 1, 10 do
                if queue[i] and queue[i].actionName and queue[i].actionName ~= "" then
                    local name = queue[i].actionName
                    
                    -- 尝试从Hekili技能数据库获取更友好的显示名称
                    if Hekili.Class and Hekili.Class.abilities and Hekili.Class.abilities[name] then
                        local ability = Hekili.Class.abilities[name]
                        if ability.name then
                            name = ability.name
                        end
                    end
                    
                    -- 如果是我们的辅助插件插入的，添加特殊标记
                    if queue[i].isMeleeIndicator then
                        name = name .. "(近战)"
                    elseif queue[i].isHealingShamanSkill then
                        name = name .. "(治疗)"
                    end
                    
                    table.insert(actions, string.format("[%d]%s", i, name))
                end
            end
            
            if #actions > 0 then
                found = true
                table.insert(displayStrings, string.format("%s: %s", dispName, table.concat(actions, " -> ")))
            end
        end
    end
    
    if found then
        local fullString = table.concat(displayStrings, " | ")
        -- 只有当内容发生变化时才打印，避免在静止状态下刷屏
        if fullString ~= self.LastQueueString then
            self:DebugPrint("|cFFFFFF00[推荐队列]|r " .. fullString)
            self.LastQueueString = fullString
        end
    elseif self.LastQueueString ~= "empty" then
        self:DebugPrint("|cFFFFFF00[推荐队列]|r 当前没有激活的推荐")
        self.LastQueueString = "empty"
    end
end

-- 集成选项到Hekili主界面
function HekiliHelper:IntegrateOptions()
    -- 确保数据库已初始化
    if not self.DB then
        self:DebugPrint("|cFFFF0000[HekiliHelper]|r 警告: 数据库未初始化，稍后重试...")
        C_Timer.After(0.5, function()
            if self.DB then
                self:IntegrateOptions()
            end
        end)
        return
    end
    
    if not Hekili or not Hekili.Options or not Hekili.Options.args then
        self:DebugPrint("|cFFFF0000[HekiliHelper]|r 警告: Hekili.Options未准备好，稍后重试...")
        C_Timer.After(1.0, function()
            if Hekili and Hekili.Options and Hekili.Options.args and self.DB then
                self:IntegrateOptions()
            end
        end)
        return
    end
    
    if not self.Options then
        self:DebugPrint("|cFFFF0000[HekiliHelper]|r 警告: Options模块未加载")
        return
    end
    
    local optionsTable = self.Options:GetOptions()
    if optionsTable then
        Hekili.Options.args.hekiliHelper = optionsTable
        self:DebugPrint("|cFF00FF00[HekiliHelper]|r 选项已集成到Hekili主界面")
    else
        self:Print("|cFFFF0000[HekiliHelper]|r 错误: 无法获取选项表")
    end
end

-- Hook工具函数（类似PatchUtils）
HekiliHelper.HookUtils = {
    -- Hook函数（在函数执行前后添加逻辑）
    Hook = function(target, funcName, hookFunc, position)
        position = position or "after"  -- "before" 或 "after"
        
        if not target[funcName] then
            HekiliHelper:Print("|cFFFF0000[HekiliHelper]|r 错误: 函数 " .. funcName .. " 不存在")
            return false
        end
        
        local originalFunc = target[funcName]
        
        if position == "after" then
            target[funcName] = function(...)
                local result = originalFunc(...)
                hookFunc(originalFunc, ...)
                return result
            end
        else
            target[funcName] = function(...)
                hookFunc(originalFunc, ...)
                return originalFunc(...)
            end
        end
        
        return true
    end,
    
    -- 包装函数（完全控制函数执行）
    Wrap = function(target, funcName, wrapperFunc)
        if not target[funcName] then
            HekiliHelper:Print("|cFFFF0000[HekiliHelper]|r 错误: 函数 " .. funcName .. " 不存在")
            return false
        end
        
        local originalFunc = target[funcName]
        target[funcName] = function(self, ...)
            return wrapperFunc(originalFunc, self, ...)
        end
        
        return true
    end
}

