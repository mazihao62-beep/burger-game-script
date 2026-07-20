-- 汉堡游戏自动脚本 v2.5
-- 作者: b站英吉利超入_
-- 修复: 直接用RS.Remotes/Network路径FireServer (基于Cobalt反编译确认)

local P = game:GetService("Players")
local WS = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local CS = game:GetService("CollectionService")
local C = game:GetService("CoreGui")

local LP = nil
for i = 1, 50 do LP = P.LocalPlayer; if LP then break end; task.wait(0.1) end
if not LP then return end

local IM = false
pcall(function() IM = UIS.TouchEnabled and not UIS.KeyboardEnabled end)

-- ============ 远程事件缓存 ============
local MeleeEvent, PickupEvent, DropEvent, OrderEvent
local remotesReady = false

local function loadRemotes()
    local ok = pcall(function()
        local Network = RS:WaitForChild("Network", 10)
        local Remotes = RS:WaitForChild("Remotes", 10)
        MeleeEvent = Network:WaitForChild("MeleeHitEvent", 5)
        PickupEvent = Remotes:WaitForChild("PickupItem", 5)
        DropEvent = Remotes:WaitForChild("DropItem", 5)
        OrderEvent = Network:WaitForChild("LinkPlayerToOrder", 5)
    end)
    if ok and MeleeEvent then
        remotesReady = true
        print("[Burger v2.5] 远程事件就绪: Melee/Pickup/Drop/Order")
    else
        print("[Burger v2.5] ⚠ 远程事件加载失败，用输入模拟")
    end
end
loadRemotes()

-- ============ 清理旧UI ============
local function clean()
    for _, g in ipairs(C:GetChildren()) do
        if g:IsA("ScreenGui") then
            local n = g.Name
            if n == "A" or n:find("BurgerESP") or n == "WindUI" then
                pcall(function() g:Destroy() end)
            end
        end
    end
end
clean()

-- ============ WindUI 加载 ============
local WI, loaded = nil, false
for i = 1, 6 do
    local ok, rv = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
    end)
    if ok and rv then WI = rv; loaded = true; break end
    task.wait(1.5)
end

if not loaded then
    local msg = Instance.new("Message")
    msg.Text = "WindUI 加载失败(已重试6次)"
    msg.Parent = workspace
    task.delay(4, function() msg:Destroy() end)
    return
end

-- ============ 状态 ============
local S = {
    KillNPC = false,
    GrindBodies = false,
    MakeBurgers = false,
    CollectMoney = false,
    AutoMode = false,
    EspEnabled = false,
    EspRange = 200,
    KillRange = 25,
    AkillDamage = 26,
    Particles = true,
    Acrylic = true,
    Transparent = false,
    ParticleColor = Color3.fromRGB(80, 170, 255)
}

local KB = { Window = "RightShift" }
local WN, CT = nil, {}
local PH, PC, PS = nil, nil, {}

-- ============ 关键词 ============
local TOOL_KILL_KEYWORDS = {"spatula","shovel","knife","sword","bat","hammer","axe","weapon","cleaver"}
local TOOL_BAG_KEYWORDS = {"sack","bag","container","box"}

local function findKeyword(name, keywords)
    if not name then return false end
    local lower = name:lower()
    for _, kw in ipairs(keywords) do
        if lower:find(kw:lower(), 1, true) then return true end
    end
    return false
end

-- ============ 工具 ============
local function getBackpackTool(keywords)
    local bp = LP:FindFirstChild("Backpack")
    if not bp then return nil end
    for _, t in ipairs(bp:GetChildren()) do
        if t:IsA("Tool") then
            if findKeyword(t.Name, keywords) then return t end
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
        task.wait(0.1)
    end
    return true
end

-- ============ NPC检测 ============
local function isPlayerChar(m)
    for _, p in ipairs(P:GetPlayers()) do
        if p.Character == m then return true end
    end
    return false
end

local function getNearbyNPCs(range)
    local npcs = {}
    local char = LP.Character
    if not char then return npcs end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return npcs end
    local pos = hrp.Position
    local seen = {}

    local searchRoots = {WS}
    local gf = WS:FindFirstChild("GAMEFOLDERS")
    if gf then
        local c = gf:FindFirstChild("Customers")
        if c then table.insert(searchRoots, c) end
        local n = gf:FindFirstChild("NPCs")
        if n then table.insert(searchRoots, n) end
    end

    for _, root in ipairs(searchRoots) do
        for _, obj in ipairs(root:GetDescendants()) do
            if obj:IsA("Humanoid") and obj.Parent and obj.Parent:IsA("Model") then
                local m = obj.Parent
                if not seen[m] and not isPlayerChar(m) then
                    seen[m] = true
                    local mhrp = m:FindFirstChild("HumanoidRootPart")
                    if mhrp and obj.Health > 0 then
                        local dist = (mhrp.Position - pos).Magnitude
                        if dist <= range then
                            table.insert(npcs, {Model = m, Humanoid = obj, HRP = mhrp, Distance = dist})
                        end
                    end
                end
            end
        end
    end

    table.sort(npcs, function(a, b) return a.Distance < b.Distance end)
    return npcs
end

-- ============ 尸体 (Pickable标签) ============
local function getBodies()
    local bodies = {}
    for _, obj in ipairs(CS:GetTagged("Pickable")) do
        if obj:IsA("Model") then
            table.insert(bodies, obj)
        end
    end
    return bodies
end

-- ============ 金钱 (Bill + Cash) ============
local function getMoneyBills()
    local bills = {}
    -- ITEMS.Bill (ProximityPrompt "Collect")
    local items = WS:FindFirstChild("ITEMS")
    if items then
        for _, obj in ipairs(items:GetDescendants()) do
            local pp = obj:FindFirstChildOfClass("ProximityPrompt")
            if pp then
                table.insert(bills, {Model = obj, Prompt = pp})
            end
            if obj:IsA("BasePart") and obj.Name == "Cash" then
                table.insert(bills, {Part = obj})
            end
        end
    end
    for _, obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("MeshPart") and obj.Name == "Cash" then
            local found = false
            for _, b in ipairs(bills) do if b.Part == obj then found = true; break end end
            if not found then table.insert(bills, {Part = obj}) end
        end
    end
    return bills
end

-- ============ 物品查找 ============
local function getGrinder()
    local wp = WS:FindFirstChild("WORLDPARTS")
    if not wp then return nil end
    for _, obj in ipairs(wp:GetDescendants()) do
        if obj:IsA("Part") and obj.Name == "Grinder" then
            return obj
        end
    end
    return nil
end

local function getFoodStands()
    local stands = {}
    local wp = WS:FindFirstChild("WORLDPARTS")
    if not wp then return stands end
    local efs = wp:FindFirstChild("EndlessFoodStands")
    if not efs then return stands end
    for _, stand in ipairs(efs:GetChildren()) do
        if stand:IsA("Model") then
            table.insert(stands, stand)
        end
    end
    return stands
end

local function getGrill()
    local wp = WS:FindFirstChild("WORLDPARTS")
    if not wp then return nil end
    for _, obj in ipairs(wp:GetDescendants()) do
        if obj:IsA("Part") and (obj.Name == "GrillHitbox" or obj.Name == "Grill") then
            return obj
        end
    end
    return nil
end

local function getPrimaryPart(model)
    if not model then return nil end
    local ok, pp = pcall(function() return model.PrimaryPart end)
    if ok and pp then return pp end
    local ok2, bp = pcall(function() return model:FindFirstChildWhichIsA("BasePart") end)
    if ok2 and bp then return bp end
    return nil
end

-- ============ 获取订单 ============
local function getActiveOrder()
    local board = WS:FindFirstChild("WORLDPARTS") and WS.WORLDPARTS:FindFirstChild("OrdersBoard")
    if not board then return nil end
    -- 找BillboardGui上的订单号
    for _, obj in ipairs(board:GetDescendants()) do
        if obj:IsA("BillboardGui") then
            for _, child in ipairs(obj:GetDescendants()) do
                if child:IsA("TextLabel") and child.Text:find("ORDER") then
                    return child.Text
                end
            end
        end
    end
    return nil
end

-- ============ 1. 杀NPC — RS.Network.MeleeHitEvent:FireServer ============
local function doKillNPC()
    local npcs = getNearbyNPCs(S.KillRange)
    if #npcs == 0 then return false, "附近没有NPC" end

    local target = npcs[1]
    local tool = getBackpackTool(TOOL_KILL_KEYWORDS)
    if not tool then return false, "没有武器" end
    equipTool(tool)

    local char = LP.Character
    if not char then return false, "角色未加载" end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp or not target.HRP then return false end

    -- 传送到NPC面前
    hrp.CFrame = target.HRP.CFrame * CFrame.new(0, 0, 2.5)
    task.wait(0.15)

    -- 找NPC身上的任意Part来作为hitPart
    local hitPart = target.HRP
    -- 尝试找更具体的Part (身体部位优先)
    for _, part in ipairs(target.Model:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            hitPart = part
            break
        end
    end

    if remotesReady and MeleeEvent then
        for i = 1, 3 do
            pcall(function()
                MeleeEvent:FireServer(
                    hitPart,
                    hitPart.Position,
                    Vector3.new(0, 0.06, -0.998),  -- 大致朝向正前方
                    S.AkillDamage
                )
            end)
            task.wait(0.15)
        end
        return true, "击杀: " .. target.Model.Name
    end

    -- 备用: VIM模拟
    pcall(function()
        local VIM = game:GetService("VirtualInputManager")
        for i = 1, 3 do
            VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            task.wait(0.05)
            VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
            task.wait(0.1)
        end
    end)
    return true, "击杀(VIM): " .. target.Model.Name
end

-- ============ 2. 粉碎尸体 — PickupItem + DropItem ============
local function doGrindBody()
    local grinder = getGrinder()
    if not grinder then return false, "找不到粉碎机" end

    local bodies = getBodies()
    if #bodies == 0 then return false, "附近没有尸体" end

    local char = LP.Character
    if not char then return false, "角色未加载" end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local body = bodies[1]
    local bpos = getPrimaryPart(body)
    if not bpos then return false, "无法接近尸体" end

    -- 走到尸体旁
    hrp.CFrame = bpos.CFrame * CFrame.new(0, 0, 2)
    task.wait(0.2)

    if remotesReady and PickupEvent then
        -- 装备Sack
        local sack = getBackpackTool(TOOL_BAG_KEYWORDS)
        if sack then equipTool(sack); task.wait(0.15) end

        -- FireServer捡起尸体
        local ok = pcall(function()
            PickupEvent:FireServer(body)
        end)
        if ok then
            task.wait(0.3)
            -- 走到Grinder前
            hrp.CFrame = grinder.CFrame * CFrame.new(0, 0, 3)
            task.wait(0.3)
            -- FireServer丢到Grinder位置
            pcall(function()
                DropEvent:FireServer(body, grinder.Position)
            end)
            return true, "粉碎: " .. body.Name
        end
    end

    -- 备用: F键模拟
    local sack = getBackpackTool(TOOL_BAG_KEYWORDS)
    if sack then equipTool(sack); task.wait(0.15) end
    pcall(function()
        local VIM = game:GetService("VirtualInputManager")
        VIM:SendKeyEvent(true, Enum.KeyCode.F, false, game)
        task.wait(0.1)
        VIM:SendKeyEvent(false, Enum.KeyCode.F, false, game)
    end)
    task.wait(0.3)
    hrp.CFrame = grinder.CFrame * CFrame.new(0, 0, 3)
    task.wait(0.3)
    pcall(function()
        local VIM = game:GetService("VirtualInputManager")
        VIM:SendKeyEvent(true, Enum.KeyCode.F, false, game)
        task.wait(0.1)
        VIM:SendKeyEvent(false, Enum.KeyCode.F, false, game)
    end)
    return true, "粉碎(F键): " .. body.Name
end

-- ============ 3. 收钱 — fireproximityprompt ============
local function doCollectMoney()
    local char = LP.Character
    if not char then return false, "角色未加载" end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local bills = getMoneyBills()
    if #bills == 0 then return false, "附近没有金钱" end

    local collected = 0
    for _, bill in ipairs(bills) do
        if bill.Prompt then
            local ppPart = getPrimaryPart(bill.Model)
            local dist = ppPart and (ppPart.Position - hrp.Position).Magnitude or 999
            if dist <= 80 then
                if ppPart then hrp.CFrame = ppPart.CFrame * CFrame.new(0, 2, 0) end
                task.wait(0.1)
                pcall(function() fireproximityprompt(bill.Prompt) end)
                collected = collected + 1
            end
        elseif bill.Part then
            local dist = (bill.Part.Position - hrp.Position).Magnitude
            if dist <= 80 then
                hrp.CFrame = bill.Part.CFrame * CFrame.new(0, 2, 0)
                task.wait(0.1)
                local pp = bill.Part:FindFirstChildOfClass("ProximityPrompt")
                if pp then pcall(function() fireproximityprompt(pp) end) end
                collected = collected + 1
            end
        end
        if collected >= 30 then break end
    end

    if collected > 0 then return true, "收集了 " .. collected .. " 个金钱" end
    return false, "附近没有可收集的金钱"
end

-- ============ 4. 做汉堡 — PickupItem食材 + DropItem到Grill + LinkPlayerToOrder ============
local function doMakeBurger()
    local char = LP.Character
    if not char then return false, "角色未加载" end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    -- 先接单
    if remotesReady and OrderEvent then
        local order = getActiveOrder()
        if order then
            pcall(function() OrderEvent:FireServer(order) end)
            task.wait(0.2)
        end
    end

    -- 拿食材
    local stands = getFoodStands()
    if #stands > 0 then
        local stand = stands[1]  -- 取第一个食材站
        local pp = getPrimaryPart(stand)
        if pp then
            hrp.CFrame = pp.CFrame * CFrame.new(0, 1, 2)
            task.wait(0.15)

            if remotesReady and PickupEvent then
                pcall(function() PickupEvent:FireServer(stand) end)
            else
                pcall(function()
                    local VIM = game:GetService("VirtualInputManager")
                    VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                    task.wait(0.05)
                    VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                end)
            end
            task.wait(0.3)
        end

        -- 放到Grill上
        local grill = getGrill()
        if grill then
            hrp.CFrame = grill.CFrame * CFrame.new(0, 1, 2)
            task.wait(0.15)

            if remotesReady and DropEvent then
                pcall(function()
                    DropEvent:FireServer(stand, grill.Position)
                end)
            else
                pcall(function()
                    local VIM = game:GetService("VirtualInputManager")
                    VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                    task.wait(0.05)
                    VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                end)
            end
            return true, "做汉堡: 食材→Grill"
        end
    end

    return false, "找不到食材站"
end

-- ============ ESP ============
local EO = {}

local function makeESP(target)
    if EO[target] then return end
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 200, 0, 50)
    bb.MaxDistance = S.EspRange
    bb.AlwaysOnTop = true
    bb.StudsOffset = Vector3.new(0, 4, 0)
    pcall(function() bb.Parent = target end)
    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.new(1, 0, 1, 0)
    tl.Text = "💀 NPC"
    tl.TextColor3 = Color3.fromRGB(255, 40, 40)
    tl.BackgroundTransparency = 0.7
    tl.BackgroundColor3 = Color3.new(0, 0, 0)
    tl.TextScaled = true
    tl.Font = Enum.Font.SourceSansBold
    tl.Parent = bb
    local hl = Instance.new("Highlight")
    hl.FillColor = Color3.fromRGB(255, 40, 40)
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.3
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    pcall(function() hl.Parent = target end)
    EO[target] = {BB = bb, HL = hl}
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
    for target, _ in pairs(EO) do clearESP(target) end
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
            if not isPlayerChar(m) then
                local mhrp = m:FindFirstChild("HumanoidRootPart")
                local dist = pos and mhrp and (mhrp.Position - pos).Magnitude or 999
                if dist > S.EspRange then clearESP(m)
                elseif dist <= S.EspRange and obj.Health > 0 then makeESP(m) end
            end
        end
    end
end

-- ============ 主题 ============
local function getThemeColor(themeName)
    local colors = {
        Dark = Color3.fromRGB(80, 170, 255), Light = Color3.fromRGB(60, 130, 210),
        Rose = Color3.fromRGB(255, 130, 170), Plant = Color3.fromRGB(70, 210, 130),
        Ocean = Color3.fromRGB(60, 190, 240), Sunset = Color3.fromRGB(255, 160, 70),
        Midnight = Color3.fromRGB(130, 100, 240), Forest = Color3.fromRGB(60, 180, 90),
        Lavender = Color3.fromRGB(190, 140, 255), Coral = Color3.fromRGB(255, 140, 90),
        Mint = Color3.fromRGB(80, 230, 190), Sky = Color3.fromRGB(100, 190, 255),
        Blood = Color3.fromRGB(230, 90, 80), Lemon = Color3.fromRGB(230, 210, 70),
        Cyber = Color3.fromRGB(0, 235, 210)
    }
    return colors[themeName] or Color3.fromRGB(80, 170, 255)
end

-- ============ 粒子 ============
local function mkParts(WF)
    if PC then pcall(function() PC:Destroy() end) end
    PS = {}
    for i = 1, 50 do
        local dot = Instance.new("Frame")
        local sz = math.random(5, 10)
        dot.Size = UDim2.new(0, sz, 0, sz)
        local x, y = 0.05 + math.random() * 0.9, 0.05 + math.random() * 0.9
        dot.Position = UDim2.new(x, 0, y, 0)
        dot.BackgroundColor3 = S.ParticleColor
        dot.BorderSizePixel = 0
        dot.ZIndex = 5
        pcall(function() dot.Parent = PC end)
        table.insert(PS, {
            F = dot, Sx = x, Sy = y,
            Vx = (math.random() - 0.5) * 0.0015,
            Vy = (math.random() - 0.5) * 0.0015,
            Bt = math.random() * 0.4 + 0.3
        })
    end
    if PH then PH:Disconnect() end
    PH = game:GetService("RunService").Heartbeat:Connect(function()
        for _, p in ipairs(PS) do
            if not p.F or not p.F.Parent then continue end
            p.Sx = p.Sx + p.Vx; p.Sy = p.Sy + p.Vy
            if p.Sx < 0.05 or p.Sx > 0.95 then p.Vx = -p.Vx end
            if p.Sy < 0.05 or p.Sy > 0.95 then p.Vy = -p.Vy end
            p.F.Position = UDim2.new(math.max(0.05, math.min(0.95, p.Sx)), 0, math.max(0.05, math.min(0.95, p.Sy)), 0)
            p.F.BackgroundColor3 = S.ParticleColor
            p.F.BackgroundTransparency = 0.3 + math.sin(tick() * 2) * 0.2
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

-- ============ UI ============
local function makeWindow()
    WN = WI:CreateWindow({
        Title = "🍔 汉堡自动脚本",
        Author = "b站英吉利超入_",
        Icon = "solar:hamburger-bold",
        Size = UDim2.fromOffset(750, 520),
        ToggleKey = Enum.KeyCode.RightShift,
        Folder = "burger-script",
        Acrylic = true,
        Resizable = false,
        ScrollBarEnabled = true,
        HideSearchBar = true,
        OnClose = function()
            killParts()
            S.KillNPC = false; S.GrindBodies = false; S.MakeBurgers = false
            S.CollectMoney = false; S.AutoMode = false; S.EspEnabled = false
            clearAllESP()
            for _, ct in pairs(CT) do
                if ct and type(ct.Set) == "function" then pcall(function() ct:Set(false) end) end
            end
        end,
        OnOpen = function()
            task.spawn(function()
                task.wait(0.5)
                if S.Particles then
                    local WF = nil
                    for _, c in ipairs(WN.Parent:GetChildren()) do
                        if c:IsA("Frame") and c.AbsoluteSize.X > 400 then WF = c; break end
                    end
                    if WF then mkParts(WF) end
                end
            end)
        end
    })

    task.spawn(function()
        task.wait(0.5)
        pcall(function() WN:SetToggleKey(Enum.KeyCode.RightShift) end)
    end)

    -- Tab1: 主控面板
    local t1 = WN:Tab({Title = "主控面板", Icon = "solar:slider-vertical-bold"})
    CT.KillNPC = t1:Toggle({Flag = "KillNPC", Title = "自动杀死NPC", Value = false, Callback = function(v) S.KillNPC = v end})
    CT.GrindBodies = t1:Toggle({Flag = "GrindBodies", Title = "自动粉碎尸体", Value = false, Callback = function(v) S.GrindBodies = v end})
    CT.MakeBurgers = t1:Toggle({Flag = "MakeBurgers", Title = "自动做汉堡", Value = false, Callback = function(v) S.MakeBurgers = v end})
    CT.CollectMoney = t1:Toggle({Flag = "CollectMoney", Title = "自动收集金钱", Value = false, Callback = function(v) S.CollectMoney = v end})
    CT.AutoMode = t1:Toggle({Flag = "AutoMode", Title = "全自动模式", Desc = "接单→杀NPC→粉碎→做汉堡→收钱", Value = false, Callback = function(v) S.AutoMode = v end})
    t1:Divider()
    CT.Esp = t1:Toggle({Flag = "EspEnabled", Title = "NPC透视", Value = false, Callback = function(v) S.EspEnabled = v; if not v then clearAllESP() end end})
    t1:Divider()
    CT.KillRange = t1:Slider({Flag = "KillRange", Title = "攻击范围", Step = 5, Value = {Min = 5, Max = 100, Default = 25}, Width = 200, IsTextbox = true, Callback = function(v) S.KillRange = v end})

    -- Tab2: 功能设置
    local t2 = WN:Tab({Title = "功能设置", Icon = "solar:settings-bold"})
    t2:Keybind({Flag = "KillKey", Title = "杀NPC快捷键", Value = "", Callback = function(v) KB.Kill = v end})
    t2:Keybind({Flag = "GrindKey", Title = "粉碎快捷键", Value = "", Callback = function(v) KB.Grind = v end})
    t2:Keybind({Flag = "BurgerKey", Title = "做汉堡快捷键", Value = "", Callback = function(v) KB.Burger = v end})
    t2:Keybind({Flag = "MoneyKey", Title = "收钱快捷键", Value = "", Callback = function(v) KB.Money = v end})

    -- Tab3: UI设置
    local t3 = WN:Tab({Title = "UI设置", Icon = "solar:monitor-bold"})
    t3:Keybind({Flag = "WindowKey", Title = "窗口快捷键", Value = "RightShift", Callback = function(v) KB.Window = v end})
    CT.Particles = t3:Toggle({Flag = "Particles", Title = "粒子背景", Value = true, Callback = function(v)
        S.Particles = v
        if v then task.spawn(function() task.wait(0.3); local WF = nil; for _, c in ipairs(WN.Parent:GetChildren()) do if c:IsA("Frame") and c.AbsoluteSize.X > 400 then WF = c; break end end; if WF then mkParts(WF) end end)
        else killParts() end
    end})
    CT.Acrylic = t3:Toggle({Flag = "Acrylic", Title = "毛玻璃", Value = true, Callback = function(v) S.Acrylic = v; pcall(function() WI:ToggleAcrylic(v) end) end})
    CT.Transparent = t3:Toggle({Flag = "Transparent", Title = "透明背景", Value = false, Callback = function(v) S.Transparent = v; pcall(function() WN:ToggleTransparency(v) end) end})
    local themeNames = {"Dark","Light","Rose","Plant","Ocean","Sunset","Midnight","Forest","Lavender","Coral","Mint","Sky","Blood","Lemon","Cyber"}
    CT.Theme = t3:Dropdown({Flag = "Theme", Title = "选择主题", Values = themeNames, Value = "Dark", Callback = function(v)
        pcall(function() WI:SetTheme(v) end); S.ParticleColor = getThemeColor(v)
    end})

    -- Tab4: 信息统计
    local t4 = WN:Tab({Title = "信息统计", Icon = "solar:chart-bold"})
    local npcP = t4:Paragraph({Title = "👤 NPC: 0"})
    local bodyP = t4:Paragraph({Title = "🦴 尸体: 0"})
    local moneyP = t4:Paragraph({Title = "💰 金钱: 0"})
    local ingP = t4:Paragraph({Title = "🍔 食材站: 0"})

    -- Tab5: 配置管理
    local t5 = WN:Tab({Title = "配置管理", Icon = "solar:diskette-bold"})
    t5:Input({Flag = "CN", Title = "配置名称", Value = "default", Icon = "solar:file-text-bold", Callback = function(v) end})
    t5:Button({Title = "💾 保存", Icon = "solar:check-circle-bold", Justify = "Center", Color = Color3.fromHex("#305dff"), Callback = function() end})
    t5:Button({Title = "📂 加载", Icon = "solar:refresh-circle-bold", Justify = "Center", Color = Color3.fromHex("#10C550"), Callback = function() end})
    t5:Button({Title = "🗑️ 删除", Icon = "solar:trash-bin-trash-bold", Justify = "Center", Color = Color3.fromHex("#ff3040"), Callback = function() end})

    -- Tab6: 关于
    local t6 = WN:Tab({Title = "关于", Icon = "solar:info-square-bold"})
    t6:Paragraph({Title = "汉堡自动脚本 v2.5"})
    t6:Divider()
    t6:Paragraph({Title = "👤 作者", Desc = "b站英吉利超入_"})
    t6:Divider()
    t6:Paragraph({Title = "💡 使用", Desc = IM and "手机:点击悬浮按钮" or "PC: RightShift打开菜单"})
    t6:Paragraph({Title = "🔧 v2.5更新", Desc = "直接FireServer远程事件\nMeleeHit/Pickup/Drop/Order\n基于Cobalt反编译确认路径"})

    UIS.InputBegan:Connect(function(input, gpe)
        if gpe or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local keyName = input.KeyCode and input.KeyCode.Name or ""
        if keyName == KB.Kill then S.KillNPC = not S.KillNPC; if CT.KillNPC then CT.KillNPC:Set(S.KillNPC) end end
        if keyName == KB.Grind then S.GrindBodies = not S.GrindBodies; if CT.GrindBodies then CT.GrindBodies:Set(S.GrindBodies) end end
        if keyName == KB.Burger then S.MakeBurgers = not S.MakeBurgers; if CT.MakeBurgers then CT.MakeBurgers:Set(S.MakeBurgers) end end
        if keyName == KB.Money then S.CollectMoney = not S.CollectMoney; if CT.CollectMoney then CT.CollectMoney:Set(S.CollectMoney) end end
    end)

    return npcP, bodyP, moneyP, ingP
end

-- ============ 主循环 ============
local PP = false
pcall(function() WI:SetTheme("Dark") end)
S.ParticleColor = getThemeColor("Dark")
WI:Popup({
    Title = "🍔 汉堡自动脚本 v2.5",
    Content = "⚔️ 自动杀死NPC\n🧹 自动粉碎尸体\n🍔 自动做汉堡(含接单)\n💰 自动收集金钱\n👁 NPC透视\n\n🔧 v2.5: FireServer直连远程事件",
    Buttons = {{Title = "确认加载", Callback = function() PP = true end, Variant = "Primary"}}
})
while not PP do task.wait(0.1) end

local function mainLoop()
    local npcP, bodyP, moneyP, ingP = makeWindow()
    WI:Notify({
        Title = "🍔 汉堡脚本 v2.5",
        Content = "已加载! RightShift开窗口\n远程:" .. (remotesReady and "✅ FireServer" or "⚠ 模拟输入"),
        Duration = 3,
        Icon = "solar:bell-bold"
    })
    local lastInfoUpdate = 0
    while true do
        local now = tick()
        if S.AutoMode then
            doKillNPC(); task.wait(0.3)
            doGrindBody(); task.wait(0.3)
            doMakeBurger(); task.wait(0.3)
            doCollectMoney(); task.wait(1)
        else
            if S.KillNPC then doKillNPC(); task.wait(0.3) end
            if S.GrindBodies then doGrindBody(); task.wait(0.3) end
            if S.MakeBurgers then doMakeBurger(); task.wait(0.3) end
            if S.CollectMoney then doCollectMoney(); task.wait(0.3) end
        end
        doESPScan()
        if now - lastInfoUpdate > 3 then
            lastInfoUpdate = now
            if npcP then pcall(function() npcP:SetTitle("👤 NPC: " .. #getNearbyNPCs(100)) end) end
            if bodyP then pcall(function() bodyP:SetTitle("🦴 尸体: " .. #getBodies()) end) end
            if moneyP then pcall(function() moneyP:SetTitle("💰 金钱: " .. #getMoneyBills()) end) end
            if ingP then pcall(function() ingP:SetTitle("🍔 食材站: " .. #getFoodStands()) end) end
        end
        task.wait(2)
    end
end

task.spawn(mainLoop)
