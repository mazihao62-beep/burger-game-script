-- 汉堡游戏自动脚本 v1.0
-- 功能: 自动杀NPC、粉碎尸体、做汉堡、收集金钱
-- UI: 基于 WindUI 模板

-- ===== 初始化 =====
local P = game:GetService("Players")
local LP = P.LocalPlayer
local WS = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local VIM = game:GetService("VirtualInputManager")
local CS = game:GetService("CollectionService")
local TS = game:GetService("TweenService")

local IM = false
pcall(function() IM = UIS.TouchEnabled and not UIS.KeyboardEnabled end)

-- 清理残留
local function clean()
    for _, g in ipairs(game:GetService("CoreGui"):GetChildren()) do
        if g:IsA("ScreenGui") then
            local n = g.Name
            if n == "A" or n:find("AirportESP") or n:find("BurgerESP") or n == "WindUI" then
                pcall(function() g:Destroy() end)
            end
        end
    end
end
clean()

-- ===== 加载 WindUI =====
local WI = nil
local loaded = false
for i = 1, 6 do
    local ok, rv = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
    end)
    if ok and rv then
        WI = rv
        loaded = true
        break
    end
    task.wait(1.5)
end

if not loaded then
    local msg = Instance.new("Message")
    msg.Text = "WindUI 加载失败(已重试6次)"
    msg.Parent = LP:WaitForChild("PlayerGui", 30)
    task.wait(3)
    msg:Destroy()
    return
end

-- ===== 设置表 =====
local S = {
    KillNPC = false,
    GrindBodies = false,
    MakeBurgers = false,
    CollectMoney = false,
    AutoMode = false,
    KillRange = 20,
    EspEnabled = false,
    EspPlayers = false,
    Particles = true,
    Acrylic = true,
    Transparent = false,
    ParticleColor = Color3.fromRGB(100, 180, 255)
}
local KB = { Window = "RightShift" }

local WN, CT = nil, {}
local PH, PC, PS = nil, nil, {}

-- ===== 工具函数 =====
local function getBackpackTool(name)
    local bp = LP:FindFirstChild("Backpack")
    if not bp then return nil end
    for _, t in ipairs(bp:GetChildren()) do
        if t:IsA("Tool") and t.Name:find(name) then
            return t
        end
    end
    return nil
end

local function equipTool(tool)
    if not tool then return false end
    local char = LP.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    if tool.Parent ~= char then
        hum:EquipTool(tool)
    end
    return true
end

local function getNearbyNPCs(range)
    local npcs = {}
    local char = LP.Character
    if not char then return npcs end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return npcs end
    local pos = hrp.Position
    for _, obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("Humanoid") and obj.Parent and obj.Parent:IsA("Model") then
            local m = obj.Parent
            if P:GetPlayerFromCharacter(m) then continue end
            local mhrp = m:FindFirstChild("HumanoidRootPart")
            if mhrp and obj.Health > 0 then
                local dist = (mhrp.Position - pos).Magnitude
                if dist <= range then
                    table.insert(npcs, {Model = m, Humanoid = obj, Distance = dist})
                end
            end
        end
    end
    table.sort(npcs, function(a, b) return a.Distance < b.Distance end)
    return npcs
end

local function getGrinder()
    for _, obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("Model") and (obj.Name:find("Grinder") or obj.Name:find("GrindCounter")) then
            return obj
        end
    end
    return nil
end

local function getBodyBags()
    local bags = {}
    for _, obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("Model") and CS:HasTag(obj, "Pickable") then
            table.insert(bags, obj)
        end
    end
    return bags
end

local function getMoneyOrbs(range)
    local orbs = {}
    local char = LP.Character
    if not char then return orbs end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return orbs end
    local pos = hrp.Position
    for _, obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("Part") or obj:IsA("MeshPart") then
            local n = obj.Name:lower()
            if n:find("money") or n:find("cash") or n:find("coin") or n:find("orb") then
                local dist = (obj.Position - pos).Magnitude
                if dist <= range then
                    table.insert(orbs, {Part = obj, Distance = dist})
                end
            end
        end
    end
    table.sort(orbs, function(a, b) return a.Distance < b.Distance end)
    return orbs
end

local function getOrders()
    local orders = {}
    local board = WS:FindFirstChild("WORLDPARTS")
    if board then
        board = board:FindFirstChild("OrdersBoard")
    end
    if not board then return orders end
    for _, obj in ipairs(board:GetDescendants()) do
        if obj:IsA("StringValue") and obj.Name == "OrderID" then
            table.insert(orders, obj)
        end
    end
    return orders
end

local function getIngredients()
    local items = {}
    local foodFolder = WS:FindFirstChild("WORLDPARTS")
    if not foodFolder then return items end
    for _, obj in ipairs(foodFolder:GetDescendants()) do
        if obj:IsA("Model") and CS:HasTag(obj, "Pickable") then
            local n = obj.Name:lower()
            if n:find("meat") or n:find("patty") or n:find("bun") or n:find("cheese") or n:find("lettuce") or n:find("tomato") or n:find("bacon") or n:find("plate") then
                table.insert(items, obj)
            end
        end
    end
    return items
end

-- ===== 核心功能 =====

-- 自动杀死NPC
local function doKillNPC()
    local npcs = getNearbyNPCs(S.KillRange)
    if #npcs == 0 then return false, "附近没有NPC" end
    local target = npcs[1]
    local spatula = getBackpackTool("Spatula")
    if spatula then
        equipTool(spatula)
        local char = LP.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local thrp = target.Model:FindFirstChild("HumanoidRootPart")
            if hrp and thrp then
                hrp.CFrame = thrp.CFrame * CFrame.new(0, 0, 2)
            end
        end
        task.wait(0.2)
        VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        task.wait(0.05)
        VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        return true, "攻击 " .. target.Model.Name
    end
    return false, "没有武器 (需要铲子)"
end

-- 自动粉碎尸体
local function doGrindBody()
    local grinder = getGrinder()
    if not grinder then return false, "找不到粉碎机" end
    local bags = getBodyBags()
    if #bags == 0 then return false, "附近没有尸体" end
    local char = LP.Character
    if not char then return false, "角色未加载" end
    local sack = getBackpackTool("Sack")
    if not sack then return false, "没有麻袋" end
    equipTool(sack)
    task.wait(0.3)
    local bag = bags[1]
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local gpos = grinder.PrimaryPart or grinder:FindFirstChildWhichIsA("BasePart")
        local bpos = bag.PrimaryPart or bag:FindFirstChildWhichIsA("BasePart")
        if bpos and gpos then
            hrp.CFrame = bpos.CFrame * CFrame.new(0, 0, 2)
            task.wait(0.2)
            VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            task.wait(0.1)
            VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
            task.wait(0.3)
            hrp.CFrame = gpos.CFrame * CFrame.new(0, 0, 3)
            task.wait(0.3)
            VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            task.wait(0.1)
            VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
            return true, "粉碎尸体: " .. bag.Name
        end
    end
    return false, "无法接近尸体"
end

-- 自动收集金钱
local function doCollectMoney()
    local orbs = getMoneyOrbs(50)
    if #orbs == 0 then return false, "附近没有金钱" end
    local char = LP.Character
    if not char then return false, "角色未加载" end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "角色未加载" end
    for _, orb in ipairs(orbs) do
        hrp.CFrame = orb.Part.CFrame * CFrame.new(0, 2, 0)
        task.wait(0.05)
    end
    return true, "收集了 " .. #orbs .. " 个金钱"
end

-- 自动做汉堡
local function doMakeBurger()
    local ingredients = getIngredients()
    if #ingredients == 0 then return false, "找不到食材" end
    local orders = getOrders()
    if #orders == 0 then return false, "没有订单" end
    local char = LP.Character
    if not char then return false, "角色未加载" end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "角色未加载" end
    for _, item in ipairs(ingredients) do
        local pp = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
        if pp then
            hrp.CFrame = pp.CFrame * CFrame.new(0, 1, 2)
            task.wait(0.1)
            VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            task.wait(0.05)
            VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
            task.wait(0.15)
        end
    end
    return true, "制作汉堡材料: " .. #ingredients .. " 件"
end

-- ===== ESP 透视 =====
local EO = {}

local function classifyNPC(npc, hum)
    local name = npc.Name:lower()
    if name:find("enemy") or name:find("hostile") or name:find("criminal") or name:find("bandit") or name:find("thief") or name:find("gang") or name:find("robber") then
        return "Bad"
    end
    if name:find("customer") or name:find("civilian") or name:find("villager") or name:find("citizen") or name:find("worker") or name:find("chef") then
        return "Good"
    end
    if CS:HasTag(npc, "Enemy") or CS:HasTag(npc, "Hostile") then
        return "Bad"
    end
    return "Good"
end

local function makeESP(target, tag)
    if EO[target] then return end
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 200, 0, 50)
    bb.MaxDistance = 200
    bb.AlwaysOnTop = true
    bb.StudsOffset = Vector3.new(0, 4, 0)
    pcall(function() bb.Parent = target end)
    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.new(1, 0, 1, 0)
    tl.Text = tag == "Good" and "👨‍🍳 顾客" or "💀 敌人"
    tl.TextColor3 = tag == "Good" and Color3.fromRGB(0, 255, 80) or Color3.fromRGB(255, 40, 40)
    tl.BackgroundTransparency = 0.7
    tl.BackgroundColor3 = Color3.new(0, 0, 0)
    tl.TextScaled = true
    tl.Font = Enum.Font.SourceSansBold
    tl.Parent = bb
    local hl = Instance.new("Highlight")
    hl.FillColor = tag == "Good" and Color3.fromRGB(0, 255, 80) or Color3.fromRGB(255, 40, 40)
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.3
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    pcall(function() hl.Parent = target end)
    EO[target] = {BB = bb, HL = hl, Tag = tag}
end

local function clearESP(target)
    local e = EO[target]
    if e then
        pcall(function() e.BB:Destroy() end)
        pcall(function() e.HL:Destroy() end)
        EO[target] = nil
    end
end

local function clearAllESP()
    for target, _ in pairs(EO) do
        clearESP(target)
    end
    EO = {}
end

local function doESPScan()
    if not S.EspEnabled then return end
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local pos = hrp and hrp.Position
    for _, obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("Humanoid") and obj.Parent and obj.Parent:IsA("Model") then
            local m = obj.Parent
            if P:GetPlayerFromCharacter(m) then continue end
            if not S.EspPlayers and P:GetPlayerFromCharacter(m) then continue end
            local dist = pos and (m:FindFirstChild("HumanoidRootPart") and (m.HumanoidRootPart.Position - pos).Magnitude or 999) or 999
            if dist > 200 then
                clearESP(m)
            elseif dist <= 200 then
                local nt = classifyNPC(m, obj)
                makeESP(m, nt)
            end
        end
    end
end

-- ===== 粒子系统 =====
local function getThemeColor(themeName)
    local colors = {
        Dark = Color3.fromRGB(80, 170, 255),
        Light = Color3.fromRGB(200, 180, 255),
        Rose = Color3.fromRGB(255, 120, 160),
        Plant = Color3.fromRGB(100, 200, 120),
        Ocean = Color3.fromRGB(80, 180, 230),
        Sunset = Color3.fromRGB(255, 150, 80),
        Midnight = Color3.fromRGB(120, 100, 220),
        Lavender = Color3.fromRGB(180, 130, 255),
        Coral = Color3.fromRGB(255, 130, 100),
        Mint = Color3.fromRGB(100, 220, 180),
        Sky = Color3.fromRGB(130, 180, 255),
        Amber = Color3.fromRGB(255, 180, 80),
        Plum = Color3.fromRGB(180, 120, 200),
        Teal = Color3.fromRGB(80, 200, 180),
        Crimson = Color3.fromRGB(220, 80, 100),
        Azure = Color3.fromRGB(80, 160, 255)
    }
    local c = colors[themeName]
    if c then return c end
    local r = (themeName:byte(1) or 100) * 2.5 % 256
    local g = (themeName:byte(2) or 150) * 2.5 % 256
    local b = (themeName:byte(3) or 200) * 2.5 % 256
    return Color3.fromRGB(r / 255, g / 255, b / 255)
end

local function mkParts(WF)
    if not WF or not WF:IsA("Frame") then
        for _, c in ipairs(WN and WN.Parent and WN.Parent:GetChildren() or {}) do
            if c:IsA("Frame") and c.AbsoluteSize.X > 400 then
                WF = c
                break
            end
        end
    end
    if not WF or not WF:IsA("Frame") then return end
    if PC then pcall(function() PC:Destroy() end) end
    PC = Instance.new("Frame")
    pcall(function() PC.Parent = WF end)
    PS = {}
    for i = 1, 35 do
        local dot = Instance.new("Frame")
        dot.Size = UDim2.new(0, math.random(5, 9), 0, math.random(5, 9))
        dot.BackgroundColor3 = S.ParticleColor
        dot.BorderSizePixel = 0
        dot.ZIndex = 5
        local x, y = 0.05 + math.random() * 0.9, 0.05 + math.random() * 0.9
        dot.Position = UDim2.new(x, 0, y, 0)
        pcall(function() dot.Parent = PC end)
        table.insert(PS, {
            F = dot,
            Sx = x,
            Sy = y,
            Vx = (math.random() - 0.5) * 0.002,
            Vy = (math.random() - 0.5) * 0.002,
            Bt = math.random() * 0.5 + 0.3,
            Dr = (math.random() - 0.5) * 0.0003
        })
    end
    if PH then PH:Disconnect() end
    PH = game:GetService("RunService").Heartbeat:Connect(function()
        for _, p in ipairs(PS) do
            if not p.F or not p.F.Parent then continue end
            p.Sx = p.Sx + p.Vx
            p.Sy = p.Sy + p.Vy
            if p.Sx < 0.05 or p.Sx > 0.95 then p.Vx = -p.Vx end
            if p.Sy < 0.05 or p.Sy > 0.95 then p.Vy = -p.Vy end
            p.F.Position = UDim2.new(math.max(0.05, math.min(0.95, p.Sx)), 0, math.max(0.05, math.min(0.95, p.Sy)), 0)
            p.Bt = p.Bt + p.Dr
            if p.Bt < 0.2 or p.Bt > 0.8 then p.Dr = -p.Dr end
            p.F.BackgroundTransparency = p.Bt
            p.F.BackgroundColor3 = S.ParticleColor
        end
    end)
end

local function killParts()
    if PH then PH:Disconnect(); PH = nil end
    for _, p in ipairs(PS) do pcall(function() p.F:Destroy() end) end
    PS = {}
    pcall(function() PC:Destroy() end)
    PC = nil
end

-- ===== 创建窗口 =====
local function makeWindow()
    local wc = 0
    for _, g in ipairs(game:GetService("CoreGui"):GetChildren()) do
        if g:IsA("ScreenGui") and g.Name == "WindUI" then wc = wc + 1 end
    end

    WN = WI:CreateWindow({
        Title = "🍔 汉堡自动脚本",
        Author = "b站英吉利超入_",
        Icon = "rbxassetid://",
        Size = UDim2.fromOffset(750, 520),
        ToggleKey = "RightShift",
        Folder = "burger-script",
        Acrylic = true,
        Resizable = true,
        OnClose = function()
            killParts()
            S.KillNPC = false
            S.GrindBodies = false
            S.MakeBurgers = false
            S.CollectMoney = false
            S.AutoMode = false
            S.EspEnabled = false
            clearAllESP()
            for k, _ in pairs(CT) do
                local ct = CT[k]
                if ct and type(ct.Set) == "function" then
                    pcall(function() ct:Set(false) end)
                end
            end
        end,
        OnOpen = function()
            task.spawn(function()
                task.wait(0.8)
                if S.Particles then
                    local WF = nil
                    for _, c in ipairs(WN.Parent:GetChildren()) do
                        if c:IsA("Frame") and c.AbsoluteSize.X > 400 then
                            WF = c
                            break
                        end
                    end
                    mkParts(WF)
                end
            end)
        end
    })

    -- Tab 1: 主控面板
    local t1 = WN:Tab({Title = "主控面板", Icon = "home"})

    CT.KillNPC = t1:Toggle({Flag = "KillNPC", Title = "自动杀死NPC", Desc = "自动攻击附近NPC", Value = false, Callback = function(v) S.KillNPC = v end})
    CT.GrindBodies = t1:Toggle({Flag = "GrindBodies", Title = "自动粉碎尸体", Desc = "将尸体放入粉碎机", Value = false, Callback = function(v) S.GrindBodies = v end})
    CT.MakeBurgers = t1:Toggle({Flag = "MakeBurgers", Title = "自动做汉堡", Desc = "自动制作和送汉堡", Value = false, Callback = function(v) S.MakeBurgers = v end})
    CT.CollectMoney = t1:Toggle({Flag = "CollectMoney", Title = "自动收集金钱", Desc = "自动捡起附近金钱", Value = false, Callback = function(v) S.CollectMoney = v end})
    CT.AutoMode = t1:Toggle({Flag = "AutoMode", Title = "全自动模式", Desc = "杀NPC→粉碎→做汉堡→收钱 一键全自动", Value = false, Callback = function(v) S.AutoMode = v end})

    t1:Slider({Flag = "KillRange", Title = "攻击范围", Step = 1, Value = {Min = 5, Max = 50, Default = 20}, Width = 200, Callback = function(v) S.KillRange = v end})
    t1:Divider()

    CT.Esp = t1:Toggle({Flag = "EspEnabled", Title = "NPC透视", Desc = "显示附近NPC", Value = false, Callback = function(v) S.EspEnabled = v; if not v then clearAllESP() end end})
    CT.EspPlayers = t1:Toggle({Flag = "EspPlayers", Title = "显示玩家", Value = false, Callback = function(v) S.EspPlayers = v end})

    local statusP = t1:Paragraph({Title = "📊 状态: 待机中"})

    -- Tab 2: 功能设置
    local t2 = WN:Tab({Title = "功能设置", Icon = "settings"})

    t2:Keybind({Flag = "KillKey", Title = "杀NPC快捷键", Value = "None", Callback = function(v) KB.Kill = v end})
    t2:Keybind({Flag = "GrindKey", Title = "粉碎快捷键", Value = "None", Callback = function(v) KB.Grind = v end})
    t2:Keybind({Flag = "BurgerKey", Title = "做汉堡快捷键", Value = "None", Callback = function(v) KB.Burger = v end})
    t2:Keybind({Flag = "MoneyKey", Title = "收钱快捷键", Value = "None", Callback = function(v) KB.Money = v end})

    -- Tab 3: UI设置
    local t3 = WN:Tab({Title = "UI设置", Icon = "palette"})

    t3:Keybind({Flag = "WindowKey", Title = "窗口快捷键", Value = "RightShift", Callback = function(v) KB.Window = v end})

    CT.Particles = t3:Toggle({Flag = "Particles", Title = "粒子背景", Value = true, Callback = function(v)
        S.Particles = v
        if v then
            task.spawn(function()
                task.wait(0.3)
                local WF = nil
                for _, c in ipairs(WN.Parent:GetChildren()) do
                    if c:IsA("Frame") and c.AbsoluteSize.X > 400 then
                        WF = c
                        break
                    end
                end
                mkParts(WF)
            end)
        else
            killParts()
        end
    end})

    CT.Acrylic = t3:Toggle({Flag = "Acrylic", Title = "毛玻璃效果", Value = true, Callback = function(v) S.Acrylic = v; pcall(function() WI:ToggleAcrylic(v) end) end})
    CT.Transparent = t3:Toggle({Flag = "Transparent", Title = "透明背景", Value = false, Callback = function(v) S.Transparent = v; pcall(function() WN:ToggleTransparency(v) end) end})

    local themeNames = {"Dark", "Light", "Rose", "Plant", "Ocean", "Sunset", "Midnight", "Lavender", "Coral", "Mint", "Sky", "Amber", "Plum", "Teal", "Crimson", "Azure"}
    CT.Theme = t3:Dropdown({Flag = "Theme", Title = "选择主题", Values = themeNames, Value = "Dark", Callback = function(v) pcall(function() WI:SetTheme(v) end); S.ParticleColor = getThemeColor(v) end})

    -- Tab 4: 信息
    local t4 = WN:Tab({Title = "信息", Icon = "info"})

    local npcCountP = t4:Paragraph({Title = "👤 NPC数量: 0"})
    local bodyCountP = t4:Paragraph({Title = "🦴 尸体数量: 0"})
    local moneyCountP = t4:Paragraph({Title = "💰 金钱数量: 0"})
    local orderCountP = t4:Paragraph({Title = "📋 订单数量: 0"})

    -- Tab 5: 配置管理
    local t5 = WN:Tab({Title = "配置管理", Icon = "save"})

    t5:Input({Flag = "ConfigName", Title = "配置名称", Placeholder = "输入配置名...", Value = "default"})
    t5:Dropdown({Flag = "ConfigSelect", Title = "已有配置", Values = {"default"}, Value = "default", Callback = function(v) end})
    t5:Button({Title = "💾 保存配置", Callback = function() pcall(function() WN.ConfigManager:Config("default"):Save() end) end})
    t5:Button({Title = "📂 加载配置", Callback = function() pcall(function() WN.ConfigManager:Config("default"):Load() end) end})
    t5:Button({Title = "🗑️ 删除配置", Callback = function() pcall(function() WN.ConfigManager:Config("default"):Delete() end) end})

    -- Tab 6: 关于
    local t6 = WN:Tab({Title = "关于", Icon = "help-circle"})
    t6:Paragraph({Title = "版本: v1.0"})
    t6:Paragraph({Title = "作者: b站英吉利超入_"})
    t6:Paragraph({Title = "游戏: 汉堡烹饪"})
    t6:Divider()
    t6:Paragraph({Title = "功能: 自动杀NPC | 粉碎尸体 | 做汉堡 | 收钱"})
    t6:Paragraph({Title = "关闭窗口停止所有功能 | 按RightShift开关窗口"})

    -- 快捷键监听
    UIS.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        local keyName = input.KeyCode and input.KeyCode.Name or ""
        if keyName == KB.Window and not IM then return end
        if keyName == KB.Kill then S.KillNPC = not S.KillNPC; if CT.KillNPC then CT.KillNPC:Set(S.KillNPC) end end
        if keyName == KB.Grind then S.GrindBodies = not S.GrindBodies; if CT.GrindBodies then CT.GrindBodies:Set(S.GrindBodies) end end
        if keyName == KB.Burger then S.MakeBurgers = not S.MakeBurgers; if CT.MakeBurgers then CT.MakeBurgers:Set(S.MakeBurgers) end end
        if keyName == KB.Money then S.CollectMoney = not S.CollectMoney; if CT.CollectMoney then CT.CollectMoney:Set(S.CollectMoney) end end
    end)

    return statusP, npcCountP, bodyCountP, moneyCountP, orderCountP
end

-- ===== 加载确认弹窗 =====
local PP = false
WI:Popup({
    Title = "🍔 汉堡自动脚本",
    Content = "⚔️ 自动杀死NPC\n🧹 自动粉碎尸体\n🍔 自动制作汉堡\n💰 自动收集金钱\n👁 NPC透视\n\n⚠️ 加载后所有功能默认关闭",
    Buttons = {{Title = "确认加载", Callback = function() PP = true end, Variant = "Primary"}}
})

while not PP do task.wait(0.1) end

-- ===== 启动主循环 =====
local function mainLoop()
    local statusP, npcCountP, bodyCountP, moneyCountP, orderCountP = makeWindow()
    if S.Particles then
        killParts()
        task.wait(0.5)
        local WF = nil
        for _, c in ipairs(WN.Parent:GetChildren()) do
            if c:IsA("Frame") and c.AbsoluteSize.X > 400 then
                WF = c
                break
            end
        end
        mkParts(WF)
    end
    WI:Notify({Title = "汉堡脚本", Content = "已加载! 按RightShift开窗口", Duration = 3})
    local lastInfoUpdate = 0
    while true do
        local now = tick()
        if S.AutoMode then
            doKillNPC()
            task.wait(0.5)
            doGrindBody()
            task.wait(0.5)
            doMakeBurger()
            task.wait(0.5)
            doCollectMoney()
            if statusP then pcall(function() statusP:SetTitle("🤖 全自动模式运行中") end) end
            task.wait(1)
        else
            if S.KillNPC then doKillNPC(); task.wait(0.5) end
            if S.GrindBodies then doGrindBody(); task.wait(0.5) end
            if S.MakeBurgers then doMakeBurger(); task.wait(0.5) end
            if S.CollectMoney then doCollectMoney(); task.wait(0.5) end
        end
        doESPScan()
        if now - lastInfoUpdate > 3 then
            lastInfoUpdate = now
            local npcs = getNearbyNPCs(100)
            local bags = getBodyBags()
            local orbs = getMoneyOrbs(100)
            local orders = getOrders()
            if npcCountP then pcall(function() npcCountP:SetTitle("👤 NPC数量: " .. #npcs) end) end
            if bodyCountP then pcall(function() bodyCountP:SetTitle("🦴 尸体数量: " .. #bags) end) end
            if moneyCountP then pcall(function() moneyCountP:SetTitle("💰 金钱数量: " .. #orbs) end) end
            if orderCountP then pcall(function() orderCountP:SetTitle("📋 订单数量: " .. #orders) end) end
        end
        if not (S.KillNPC or S.GrindBodies or S.MakeBurgers or S.CollectMoney or S.AutoMode or S.EspEnabled) then
            if statusP then pcall(function() statusP:SetTitle("📊 状态: 待机中 (开启功能自动运行)") end) end
        end
        task.wait(S.AutoMode and 3 or 2)
    end
end

task.spawn(mainLoop)
