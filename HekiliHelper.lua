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
    editBox:SetFont("Fonts\\FRIZQT__.TTF", 12)
    editBox:SetWidth(scrollFrame:GetWidth())
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
    closeButton:SetScript("OnClick", function()
        frame:Hide()
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
        local min, max = scrollFrame:GetScrollRange()
        if max > 0 then
            scrollFrame:SetScrollOffset(max)
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
    C_Timer.After(0.1, function()
        if self.DebugWindow and self.DebugWindow.scrollFrame then
            local min, max = self.DebugWindow.scrollFrame:GetScrollRange()
            if max > 0 then
                self.DebugWindow.scrollFrame:SetScrollOffset(max)
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
    if self.DebugEnabled then
        -- 确保调试窗口已创建
        if not self.DebugWindow then
            self:CreateDebugWindow()
        end
        
        -- 添加消息
        self:AddDebugMessage(message)
        
        -- 显示窗口
        if self.DebugWindow then
            self.DebugWindow:Show()
        end
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
end

-- 显示/隐藏调试窗口的命令
function HekiliHelper:ShowDebugWindow(input)
    if not self.DebugWindow then
        self:CreateDebugWindow()
    end
    
    if self.DebugWindow:IsShown() then
        self.DebugWindow:Hide()
        self:Print("|cFF00FF00[HekiliHelper]|r 调试窗口已隐藏")
    else
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

