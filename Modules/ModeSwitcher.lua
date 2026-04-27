-- Modules/ModeSwitcher.lua
-- Hekili 模式切换器模块
-- 提供一个可视化的实体按钮来循环切换 Hekili 的显示模式
-- 绑定到 Primary 队列右侧，大小与技能图标完全一致

local HekiliHelper = _G.HekiliHelper
if not HekiliHelper then return end

-- 创建模块对象
if not HekiliHelper.ModeSwitcher then
    HekiliHelper.ModeSwitcher = {}
end

local Module = HekiliHelper.ModeSwitcher

-- 模式显示映射
local MODE_INFO = {
    automatic = { text = "自动", color = {0, 1, 0}, desc = "自动模式" },
    single    = { text = "单体", color = {1, 1, 1}, desc = "单体模式" },
    aoe       = { text = "AOE",  color = {1, 0, 0}, desc = "多目标模式" },
    dual      = { text = "双显", color = {1, 1, 0}, desc = "双目标模式" },
    reactive  = { text = "响应", color = {0, 1, 1}, desc = "响应模式" },
}

-- 模块初始化
function Module:Initialize()
    HekiliHelper:DebugPrint("|cFF00FF00[ModeSwitcher]|r 模块 Initialize 被调用")
    if not Hekili or not Hekili.FireToggle then
        HekiliHelper:DebugPrint("|cFFFF0000[ModeSwitcher]|r 错误: Hekili 或 FireToggle 未找到")
        return false
    end

    -- 使用固定的偏移配置
    self.db = {
        offsetX = 30,
        offsetY = 100
    }

    -- 使用循环检查，直到 Hekili 框架准备就绪
    local checkCount = 0
    local function TryCreate()
        checkCount = checkCount + 1
        HekiliHelper:DebugPrint(string.format("|cFF00FF00[ModeSwitcher]|r 正在尝试寻找父框架 (第 %d 次)...", checkCount))
        
        -- 尝试多种方式寻找 Hekili 的主框架
        local parent = _G["HekiliDisplayPrimary"] 
        
        -- 如果全局变量找不到，尝试从 DisplayPool 中查找名为 "Primary" 的显示对象
        if not parent and Hekili.DisplayPool then
            local primaryDisp = Hekili.DisplayPool.Primary
            if primaryDisp then
                if type(primaryDisp) == "table" and primaryDisp.Buttons then
                    parent = primaryDisp
                    HekiliHelper:DebugPrint("|cFF00FF00[ModeSwitcher]|r 通过 DisplayPool.Primary 找到父框架")
                end
            end
        end
        
        -- 如果还是找不到，尝试遍历所有显示，寻找第一个有效的显示
        if not parent and Hekili.DisplayPool then
            for name, UI in pairs(Hekili.DisplayPool) do
                if type(UI) == "table" and UI.GetLeft and UI.Buttons then
                    parent = UI
                    HekiliHelper:DebugPrint(string.format("|cFF00FF00[ModeSwitcher]|r 通过遍历 DisplayPool 找到父框架: %s", tostring(name)))
                    if name == "Primary" or name == "1" then break end
                end
            end
        end
        
        if parent then
            HekiliHelper:DebugPrint("|cFF00FF00[ModeSwitcher]|r 确定父框架，准备创建 UI")
            self:CreateUI(parent)
            self:SetupHooks()
            self:UpdateUI()
            HekiliHelper:Print("|cFF00FF00[HekiliHelper]|r 模式切换按钮已挂载到 Hekili")
        elseif checkCount < 15 then 
            C_Timer.After(1.0, TryCreate)
        else
            HekiliHelper:Print("|cFFFF0000[ModeSwitcher]|r 错误: 无法找到 Hekili 主显示框架")
        end
    end
    
    TryCreate()
    return true
end

-- 获取 Hekili Primary 的大小
function Module:GetPrimaryIconSize(parent)
    local size = 40 -- 默认大小
    
    -- 1. 优先尝试获取父框架的实际渲染高度（最准确）
    if parent and parent.GetHeight then
        local h = parent:GetHeight()
        if h and h > 10 and h < 200 then
            size = h
        end
    end

    -- 2. 备选：从 Hekili 配置获取
    if size == 40 and Hekili and Hekili.DB and Hekili.DB.profile and Hekili.DB.profile.displays and Hekili.DB.profile.displays.Primary then
        local cfg = Hekili.DB.profile.displays.Primary
        local bSize = cfg.buttonSize or 50
        local zoom = cfg.zoom or 1
        
        -- 纠错：如果 zoom 是百分数（如 100），转换为小数
        if zoom > 10 then zoom = zoom / 100 end
        
        size = bSize * zoom
    end
    
    -- 3. 最终兜底限制：防止尺寸异常
    if size > 100 then size = 50 end -- 如果超过100像素，强制设为50
    if size < 20 then size = 40 end  -- 如果太小，设为40
    
    return size
end
-- 获取最后一个实际显示的按钮
function Module:GetLastButton()
    local displays = Hekili.DisplayPool
    if not displays or not displays.Primary then return nil end

    local UI = displays.Primary
    if not UI.Buttons then return nil end

    -- 找到最后一个可见的按钮
    local lastButton = nil
    for _, button in ipairs(UI.Buttons) do
        if button and button:IsShown() then
            lastButton = button
        end
    end

    return lastButton
end

-- 计算 Hekili 队列的总偏移量
function Module:CalculateQueueOffset()
    -- 优先尝试直接获取最后一个按钮的位置
    local lastButton = self:GetLastButton()
    if lastButton and lastButton.GetRight then
        -- 获取最后一个按钮的右边缘相对于 Primary 框架的位置
        local lastButtonRight = lastButton:GetRight()
        local parentRight = nil

        local displays = Hekili.DisplayPool
        if displays and displays.Primary then
            parentRight = displays.Primary:GetRight()
        end

        if lastButtonRight and parentRight then
            -- 返回最后一个按钮右边缘相对于 Primary 右边缘的偏移
            -- 正值表示在 Primary 右边缘的右侧
            local offsetX = lastButtonRight - parentRight
            if offsetX > -100 and offsetX < 200 then
                return offsetX
            end
        end
    end

    -- 回退方案：使用配置计算
    if not Hekili or not Hekili.DB or not Hekili.DB.profile then return 0 end

    local cfg = Hekili.DB.profile.displays.Primary
    if not cfg then return 0 end

    -- 使用 numIcons（正确的配置字段名）
    local numIcons = cfg.numIcons or 1
    local buttonSize = cfg.buttonSize or 50
    local spacing = cfg.spacing or 5
    local zoom = cfg.zoom or 1
    if zoom > 10 then zoom = zoom / 100 end

    -- 偏移量 = (图标数量 - 1) * (缩放后的图标大小 + 间距)
    return (numIcons - 1) * (buttonSize * zoom + spacing)
end

-- 创建 UI 按钮
function Module:CreateUI(parent)
    if self.frame then return end

    local size = self:GetPrimaryIconSize(parent)

    -- 父框架设为 UIParent，避免随 Hekili 隐藏而隐藏
    local frame = CreateFrame("Button", "HekiliHelperModeButton", UIParent, "BackdropTemplate")
    frame:SetSize(size, size)

    -- 初始位置，稍后会在 OnUpdate 中动态调整
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)


    -- 背景设置
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    -- 增加一个内部图标纹理（可选，这里先用文字）
    frame.Icon = frame:CreateTexture(nil, "BACKGROUND")
    frame.Icon:SetAllPoints()
    frame.Icon:SetColorTexture(0, 0, 0, 0.5)

    -- 模式文字
    frame.Text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.Text:SetPoint("CENTER", 0, 0)
    local font, _, flags = frame.Text:GetFont()
    frame.Text:SetFont(font, 13, "OUTLINE")

    -- 保存父框架引用，用于重新对齐
    frame.hekiliParent = parent
    frame.module = self  -- 保存模块引用以便在 OnUpdate 中访问

    -- 点击事件
    frame:RegisterForClicks("LeftButtonUp")
    frame:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if Hekili and Hekili.FireToggle then
                Hekili:FireToggle("mode")
            end
        end
    end)

    -- 注册更新事件，动态锚定到最后一个显示的图标
    frame:SetScript("OnUpdate", function(self, elapsed)
        -- 检查整体开关
        if not HekiliHelper.DB or not HekiliHelper.DB.profile or not HekiliHelper.DB.profile.modeSwitcher or not HekiliHelper.DB.profile.modeSwitcher.enabled then
            if self:IsShown() then self:Hide() end
            return
        end

        if not self.lastUpdate then self.lastUpdate = 0 end
        self.lastUpdate = self.lastUpdate + elapsed
        if self.lastUpdate > 0.1 then -- 每0.1秒校准一次位置
            self.lastUpdate = 0

            -- 获取最后一个可见的按钮
            local displays = Hekili.DisplayPool
            if displays and displays.Primary and displays.Primary.Buttons then
                local lastButton = nil
                for _, btn in ipairs(displays.Primary.Buttons) do
                    if btn and btn:IsShown() and btn:IsVisible() then
                        lastButton = btn
                    end
                end

                if lastButton then
                    -- 直接设置到最后一个按钮的右侧，垂直居中
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", lastButton, "RIGHT", self.module.db.offsetX, self.module.db.offsetY)
                end
            end

            if self.hekiliParent and self.hekiliParent.IsShown and self.hekiliParent:IsShown() then
                self:SetAlpha(1)
            end
        end
    end)

    -- 悬停提示
    frame:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 1, 0, 1)
        GameTooltip:SetOwner(self, "ANKOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("点击切换模式")
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        GameTooltip:Hide()
    end)

    self.frame = frame
end

-- 挂钩同步逻辑
function Module:SetupHooks()
    -- 重要：使用系统安全的 hooksecurefunc 来同步 UI 状态
    -- 这绝对不会导致协程崩溃或功能阻断
    hooksecurefunc(Hekili, "FireToggle", function(self, name)
        if name == "mode" then
            -- 延迟一小会儿，确保 Hekili 已经更新完它的内部变量
            C_Timer.After(0.05, function()
                Module:UpdateUI()
            end)
        end
    end)
end

-- 更新 UI 显示
function Module:UpdateUI()
    if not self.frame or not Hekili or not Hekili.DB or not Hekili.DB.profile then return end
    
    -- 直接从 Hekili 的设置中读取当前生效的模式
    local modeValue = Hekili.DB.profile.toggles.mode.value
    local info = MODE_INFO[modeValue] or { text = modeValue:sub(1,4):upper(), color = {1, 1, 1} }
    
    self.frame.Text:SetText(info.text)
    self.frame.Text:SetTextColor(unpack(info.color))
end
