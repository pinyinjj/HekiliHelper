-- Modules/Options.lua
-- HekiliHelper选项界面模块
-- 为HekiliHelper创建GUI选项页面，集成到Hekili主界面

local HekiliHelper = _G.HekiliHelper

if not HekiliHelper then
    -- 如果HekiliHelper还不存在，说明加载顺序有问题
    -- 这种情况下，我们延迟创建模块
    C_Timer.After(0.1, function()
        local HH = _G.HekiliHelper
        if HH and not HH.Options then
            HH.Options = {}
        end
    end)
    return
end

-- 创建模块对象
if not HekiliHelper.Options then
    HekiliHelper.Options = {}
end

local Module = HekiliHelper.Options

-- 获取选项表
function Module:GetOptions()
    -- 确保数据库已初始化，如果未初始化则使用默认值
    if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
        -- 如果数据库未初始化，返回一个延迟加载的选项表
        -- 这个函数会在数据库初始化后被重新调用
        return {
            type = "group",
            name = "HekiliHelper",
            order = 87,
            childGroups = "tab",
            args = {
                error = {
                    type = "description",
                    name = "|cFFFF0000错误: 数据库未初始化|r\n请重新加载界面 (/reload)",
                    order = 1,
                    width = "full"
                }
            }
        }
    end
    
    return {
        type = "group",
        name = "HekiliHelper",
        order = 87, -- 放在快照选项之后
        childGroups = "tab",
        args = {
            general = {
                type = "group",
                name = "通用设置",
                order = 1,
                args = {
                    header = {
                        type = "header",
                        name = "HekiliHelper 通用设置",
                        order = 1,
                        width = "full"
                    },
                    
                    desc = {
                        type = "description",
                        name = "HekiliHelper是Hekili的辅助插件，提供额外的功能增强。\n\n" ..
                               "在这里可以配置各个模块的启用状态和参数设置。",
                        fontSize = "medium",
                        order = 2,
                        width = "full"
                    },
                    
                    enabled = {
                        type = "toggle",
                        name = "启用插件",
                        desc = "启用或禁用HekiliHelper插件。",
                        order = 10,
                        width = "full",
                        get = function()
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return true
                            end
                            return HekiliHelper.DB.profile.enabled
                        end,
                        set = function(info, val)
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return
                            end
                            HekiliHelper.DB.profile.enabled = val
                            if val then
                                HekiliHelper:Enable()
                            else
                                HekiliHelper:Disable()
                            end
                        end
                    },
                    
                    debugEnabled = {
                        type = "toggle",
                        name = "调试模式",
                        desc = "启用调试信息输出到调试窗口。使用 /hhdebugwin 也可以显示/隐藏调试窗口。",
                        order = 11,
                        width = "full",
                        get = function()
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return false
                            end
                            return HekiliHelper.DB.profile.debugEnabled or false
                        end,
                        set = function(info, val)
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return
                            end
                            HekiliHelper.DB.profile.debugEnabled = val
                            if HekiliHelper then
                                HekiliHelper.DebugEnabled = val
                                
                                -- 确保调试窗口已创建
                                if val then
                                    if not HekiliHelper.DebugWindow then
                                        HekiliHelper:CreateDebugWindow()
                                    end
                                    if HekiliHelper.DebugWindow then
                                        HekiliHelper.DebugWindow:Show()
                                    end
                                else
                                    if HekiliHelper.DebugWindow then
                                        HekiliHelper.DebugWindow:Hide()
                                    end
                                end
                            end
                        end
                    },
                }
            },
            
            meleeIndicator = {
                type = "group",
                name = "近战目标指示器",
                order = 2,
                args = {
                    header = {
                        type = "header",
                        name = "近战目标指示器设置",
                        order = 1,
                        width = "full"
                    },
                    
                    desc = {
                        type = "description",
                        name = "当玩家身边近战范围内（5码）存在敌方存活单位，但玩家没有目标或目标超出近战范围时，在Hekili显示界面中插入指示图标。",
                        fontSize = "medium",
                        order = 2,
                        width = "full"
                    },
                    
                    enabled = {
                        type = "toggle",
                        name = "启用近战目标指示器",
                        desc = "启用或禁用近战目标指示器功能。",
                        order = 10,
                        width = "full",
                        get = function()
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return true
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.meleeIndicator then
                                db.meleeIndicator = {}
                            end
                            return db.meleeIndicator.enabled ~= false
                        end,
                        set = function(info, val)
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.meleeIndicator then
                                db.meleeIndicator = {}
                            end
                            db.meleeIndicator.enabled = val
                        end
                    },
                    
                    checkRange = {
                        type = "range",
                        name = "检测范围（码）",
                        desc = "检测近战敌人的范围。",
                        order = 11,
                        min = 3,
                        max = 10,
                        step = 1,
                        width = "full",
                        get = function()
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return 5
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.meleeIndicator then
                                db.meleeIndicator = {}
                            end
                            return db.meleeIndicator.checkRange or 5
                        end,
                        set = function(info, val)
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.meleeIndicator then
                                db.meleeIndicator = {}
                            end
                            db.meleeIndicator.checkRange = val
                        end
                    },
                }
            },
            
            healingShaman = {
                type = "group",
                name = "治疗萨满",
                order = 3,
                args = {
                    header = {
                        type = "header",
                        name = "治疗萨满设置",
                        order = 1,
                        width = "full"
                    },
                    
                    desc = {
                        type = "description",
                        name = "为治疗萨满职业提供智能治疗技能推荐，根据队友血量情况自动推荐合适的治疗技能。",
                        fontSize = "medium",
                        order = 2,
                        width = "full"
                    },
                    
                    enabled = {
                        type = "toggle",
                        name = "启用",
                        desc = "启用或禁用治疗萨满技能推荐功能。",
                        order = 10,
                        width = "full",
                        get = function()
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return true
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.healingShaman then
                                db.healingShaman = {}
                            end
                            return db.healingShaman.enabled ~= false
                        end,
                        set = function(info, val)
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.healingShaman then
                                db.healingShaman = {}
                            end
                            db.healingShaman.enabled = val
                        end
                    },
                    enableStoneclawGlyph = {
                        type = "toggle",
                        name = "启用石爪图腾雕文检查",
                        desc = "只有勾选此项且装备了石爪图腾雕文时，才会推荐使用石爪图腾作为减伤。",
                        order = 10.05,
                        width = "full",
                        get = function()
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return false
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.healingShaman then db.healingShaman = {} end
                            return db.healingShaman.enableStoneclawGlyph == true
                        end,
                        set = function(info, val)
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.healingShaman then db.healingShaman = {} end
                            db.healingShaman.enableStoneclawGlyph = val
                        end,
                    },
                    enableHealingWave = {
                        type = "toggle",
                        name = "启用治疗波",
                        desc = "在推荐列表中包含治疗波",
                        order = 10.1, -- 稍微调整顺序以保持整齐
                        width = "full",
                        get = function()
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return true
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.healingShaman then db.healingShaman = {} end
                            return db.healingShaman.enableHealingWave ~= false
                        end,
                        set = function(info, val)
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.healingShaman then db.healingShaman = {} end
                            db.healingShaman.enableHealingWave = val
                        end,
                    },
                    enableLesserHealingWave = {
                        type = "toggle",
                        name = "启用次级治疗波",
                        desc = "在推荐列表中包含次级治疗波",
                        order = 10.2,
                        width = "full",
                        get = function()
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return true
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.healingShaman then db.healingShaman = {} end
                            return db.healingShaman.enableLesserHealingWave ~= false
                        end,
                        set = function(info, val)
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.healingShaman then db.healingShaman = {} end
                            db.healingShaman.enableLesserHealingWave = val
                        end,
                    },
                    riptideThreshold = {
                        type = "range",
                        name = "激流（剩余生命值%）",
                        desc = "当目标剩余生命值低于此百分比时，推荐使用激流。",
                        order = 10.5,
                        min = 1,
                        max = 100,
                        step = 1,
                        width = "full",
                        get = function()
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return 99
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.healingShaman then
                                db.healingShaman = {}
                            end
                            return db.healingShaman.riptideThreshold or 99
                        end,
                        set = function(info, val)
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.healingShaman then
                                db.healingShaman = {}
                            end
                            db.healingShaman.riptideThreshold = val
                        end
                    },
                    
                    tideForceThreshold = {
                        type = "range",
                        name = "潮汐之力（剩余生命值%）",
                        desc = "团队状态：1/3以上成员生命值低于此百分比时触发。小队状态：一半以上成员生命值低于此百分比时触发。",
                        order = 10.7,
                        min = 1,
                        max = 100,
                        step = 1,
                        width = "full",
                        get = function()
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return 50
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.healingShaman then
                                db.healingShaman = {}
                            end
                            return db.healingShaman.tideForceThreshold or 50
                        end,
                        set = function(info, val)
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.healingShaman then
                                db.healingShaman = {}
                            end
                            db.healingShaman.tideForceThreshold = val
                        end
                    },
                    
                    chainHealThreshold = {
                        type = "range",
                        name = "治疗链（剩余生命值%）",
                        desc = "当目标剩余生命值低于此百分比时，推荐使用治疗链。需要至少2个同小队成员也低于相应剩余生命值才触发。",
                        order = 11,
                        min = 1,
                        max = 100,
                        step = 1,
                        width = "full",
                        get = function()
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return 90
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.healingShaman then
                                db.healingShaman = {}
                            end
                            return db.healingShaman.chainHealThreshold or 90
                        end,
                        set = function(info, val)
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.healingShaman then
                                db.healingShaman = {}
                            end
                            db.healingShaman.chainHealThreshold = val
                        end
                    },
                    
                    healingWaveThreshold = {
                        type = "range",
                        name = "治疗波（剩余生命值%）",
                        desc = "当目标剩余生命值低于此百分比时，推荐使用治疗波。",
                        order = 12,
                        min = 1,
                        max = 100,
                        step = 1,
                        width = "full",
                        get = function()
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return 30
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.healingShaman then
                                db.healingShaman = {}
                            end
                            return db.healingShaman.healingWaveThreshold or 30
                        end,
                        set = function(info, val)
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.healingShaman then
                                db.healingShaman = {}
                            end
                            db.healingShaman.healingWaveThreshold = val
                        end
                    },
                    
                    lesserHealingWaveThreshold = {
                        type = "range",
                        name = "次级治疗波（剩余生命值%）",
                        desc = "当目标剩余生命值低于此百分比时，推荐使用次级治疗波。",
                        order = 13,
                        min = 1,
                        max = 100,
                        step = 1,
                        width = "full",
                        get = function()
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return 90
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.healingShaman then
                                db.healingShaman = {}
                            end
                            return db.healingShaman.lesserHealingWaveThreshold or 90
                        end,
                        set = function(info, val)
                            if not HekiliHelper or not HekiliHelper.DB or not HekiliHelper.DB.profile then
                                return
                            end
                            local db = HekiliHelper.DB.profile
                            if not db.healingShaman then
                                db.healingShaman = {}
                            end
                            db.healingShaman.lesserHealingWaveThreshold = val
                        end
                    },
                    
                    earthShieldTip = {
                        type = "description",
                        name = "|cFF00FF00大地之盾说明：|r\n只检查当前|cFFFFD700焦点目标|r的大地之盾buff。当存在|cFFFFD700焦点目标|r且该目标没有大地之盾时，会推荐使用。",
                        fontSize = "medium",
                        order = 14,
                        width = "full"
                    },
                }
            },
            
            healingPriest = {
                type = "group",
                name = "治疗牧师",
                order = 3.2,
                args = {
                    header = {
                        type = "header",
                        name = "治疗牧师设置",
                        order = 1,
                        width = "full"
                    },
                    
                    enabled = {
                        type = "toggle",
                        name = "启用",
                        desc = "启用或禁用治疗牧师技能推荐功能。",
                        order = 10,
                        width = "full",
                        get = function() return HekiliHelper.DB.profile.healingPriest.enabled ~= false end,
                        set = function(info, val) HekiliHelper.DB.profile.healingPriest.enabled = val end
                    },

                    effectiveCoefficient = {
                        type = "range",
                        name = "有效系数",
                        desc = "用于计算推荐阈值。公式: 目标损失生命值 >= 法术强度 * 有效系数。\n系数越小，推荐越频繁。",
                        order = 11,
                        min = 0.1, max = 1.0, step = 0.1,
                        get = function() return HekiliHelper.DB.profile.healingPriest.effectiveCoefficient or 0.8 end,
                        set = function(info, val) HekiliHelper.DB.profile.healingPriest.effectiveCoefficient = val end
                    },
                    
                    desc = {
                        type = "description",
                        name = "\n|cFFFFFF00逻辑说明:|r\n" ..
                               "• 所有单体治疗技能现在基于法术强度推荐。\n" ..
                               "• |cFF00FFFF圣光涌动:|r 具有动态时间衰减系数。剩余10秒时为100%设置系数，剩余1秒时为10%设置系数。",
                        fontSize = "medium",
                        order = 20,
                        width = "full"
                    },
                }
            },
            
            about = {
                type = "group",
                name = "关于",
                order = 4,
                args = {
                    header = {
                        type = "header",
                        name = "关于 HekiliHelper",
                        order = 1,
                        width = "full"
                    },
                    
                    version = {
                        type = "description",
                        name = function()
                            return "版本: |cFF00FF00" .. (HekiliHelper.Version or "未知") .. "|r\n\n"
                        end,
                        fontSize = "medium",
                        order = 2,
                        width = "full"
                    },
                    
                    description = {
                        type = "description",
                        name = "HekiliHelper是Hekili的辅助插件，提供额外的功能增强。\n\n" ..
                               "当前包含的功能模块：\n" ..
                               "• 近战目标指示器\n" ..
                               "• 治疗萨满\n\n" ..
                               "更多功能正在开发中...",
                        fontSize = "medium",
                        order = 3,
                        width = "full"
                    },
                }
            }
        }
    }
end

