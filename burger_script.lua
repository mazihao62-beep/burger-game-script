-- 汉堡游戏自动脚本 v2.3
-- 作者: b站英吉利超入_
-- 修复: 金钱收集改为桌上/地上的直接收集

local P = game:GetService("Players")
local WS = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local VIM = game:GetService("VirtualInputManager")
local CS = game:GetService("CollectionService")
local C = game:GetService("CoreGui")

local LP = nil
for i = 1, 50 do LP = P.LocalPlayer; if LP then break end; task.wait(0.1) end
if not LP then return end

local IM = false
pcall(function() IM = UIS.TouchEnabled and not UIS.KeyboardEnabled end)

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

local S = {
    KillNPC = false,
    GrindBodies = false,
    MakeBurgers = false,
    CollectMoney = false,
    AutoMode = false,
    EspEnabled = false,
    EspRange = 200,
    KillRange = 20,
    Particles = true,
    Acrylic = true,
    Transparent = false,
    ParticleColor = Color3.fromRGB(80, 170, 255)
}

local KB = { Window = "RightShift" }
local WN, CT = nil, {}
local PH, PC, PS = nil, nil, {}

local FOOD_KEYWORDS = {"meat", "patty", "bun", "bread", "cheese", "lettuce", "tomato", "bacon", "onion", "pickle", "sauce", "fries", "drink", "soda", "shake", "plate", "burger", "sandwich", "top", "bottom", "ingredient", "raw", "cooked"}
local MONEY_KEYWORDS = {"money", "cash", "coin", "gold", "dollar", "cent", "buck", "credit", "profit", "revenue", "income", "bill", "note", "tip", "payment", "change", "earn"}
local GRINDER_KEYWORDS = {"grind", "grinder", "shred", "shredder", "mill", "crush", "crusher", "process", "processor", "blend", "blender"}
local POLICE_KEYWORDS = {"police", "cop", "officer", "sheriff", "fbi", "swat", "riot", "shield", "security", "guard", "federal", "agent", "patrol", "detective", "trooper"}

local function findKeyword(name, keywords)
    if not name then return false end
    local lower = name:lower()
    for _, kw in ipairs(keywords) do
        if lower:find(kw:lower(), 1, true) then return true end
    end
    return false
end

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
    if tool.Parent ~= char then hum:EquipTool(tool) end
    return true
end

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
    for _, obj in ipairs(WS:GetDescendants()) do
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
    table.sort(npcs, function(a, b) return a.Distance < b.Distance end)
    return npcs
end

local function getBodies()
    local bodies = {}
    for _, obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("Model") then
            local isPickable = CS:HasTag(obj, "Pickable")
            local n = obj.Name:lower()
            if isPickable or n:find("body") or n:find("corpse") or n:find("dead") or n:find("bag") then
                table.insert(bodies, obj)
            end
        end
    end
    return bodies
end

local function getIngredients()
    local items = {}
    local wp = WS:FindFirstChild("WORLDPARTS")
    if not wp then return items end
    for _, obj in ipairs(wp:GetDescendants()) do
        if obj:IsA("Model") then
            if findKeyword(obj.Name, FOOD_KEYWORDS) then
                if CS:HasTag(obj, "Pickable") then
                    table.insert(items, obj)
                end
            end
        end
    end
    return items
end

local function getMoneyOrbs(range)
    local orbs = {}
    local char = LP.Character
    if not char then return orbs end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return orbs end
    local pos = hrp.Position
    for _, obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("BasePart") then
            if findKeyword(obj.Name, MONEY_KEYWORDS) then
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

local function getGrinder()
    local wp = WS:FindFirstChild("WORLDPARTS")
    if not wp then return nil end
    for _, obj in ipairs(wp:GetDescendants()) do
        if obj:IsA("Model") and findKeyword(obj.Name, GRINDER_KEYWORDS) then
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

local function doKillNPC()
    local npcs = getNearbyNPCs(S.KillRange)
    if #npcs == 0 then return false, "附近没有NPC" end
    local target = npcs[1]
    local tool = getBackpackTool({"spatula", "shovel", "knife", "sword", "bat", "hammer", "axe", "weapon"})
    if not tool then return false, "没有武器" end
    equipTool(tool)
    local char = LP.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp and target.HRP then
            hrp.CFrame = target.HRP.CFrame * CFrame.new(0, 0, 2)
        end
    end
    task.wait(0.2)
    for i = 1, 3 do
        pcall(function()
            VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            task.wait(0.05)
            VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        end)
        task.wait(0.08)
    end
    return true, "攻击: " .. target.Model.Name
end

local function doGrindBody()
    local grinder = getGrinder()
    if not grinder then return false, "找不到粉碎机" end
    local bodies = getBodies()
    if #bodies == 0 then return false, "附近没有尸体" end
    local sack = getBackpackTool({"sack", "bag", "container", "box"})
    if not sack then return false, "没有麻袋" end
    equipTool(sack)
    local char = LP.Character
    if not char then return false, "角色未加载" end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local bag = bodies[1]
    local bpos = getPrimaryPart(bag)
    local gpos = getPrimaryPart(grinder)
    if not bpos or not gpos then return false, "无法接近目标" end
    hrp.CFrame = bpos.CFrame * CFrame.new(0, 0, 2)
    task.wait(0.2)
    pcall(function()
        VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        task.wait(0.1)
        VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    end)
    task.wait(0.3)
    hrp.CFrame = gpos.CFrame * CFrame.new(0, 0, 3)
    task.wait(0.3)
    pcall(function()
        VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        task.wait(0.1)
        VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    end)
    return true, "粉碎尸体: " .. bag.Name
end

local function doCollectMoney()
    local char = LP.Character
    if not char then return false, "角色未加载" end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local pos = hrp.Position
    local collected = 0
    for _, obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("BasePart") then
            if findKeyword(obj.Name, MONEY_KEYWORDS) then
                local dist = (obj.Position - pos).Magnitude
                if dist <= 80 then
                    hrp.CFrame = obj.CFrame * CFrame.new(0, 2, 0)
                    task.wait(0.05)
                    collected = collected + 1
                    if collected >= 30 then break end
                end
            end
        end
    end
    if collected > 0 then return true, "收集了 " .. collected .. " 个金钱" end
    return false, "附近没有金钱"
end

local function doMakeBurger()
    local ingredients = getIngredients()
    if #ingredients == 0 then return false, "找不到食材" end
    local char = LP.Character
    if not char then return false, "角色未加载" end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    for _, item in ipairs(ingredients) do
        local pp = getPrimaryPart(item)
        if pp then
            hrp.CFrame = pp.CFrame * CFrame.new(0, 1, 2)
            task.wait(0.1)
            pcall(function()
                VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                task.wait(0.05)
                VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
            end)
            task.wait(0.15)
        end
    end
    return true, "制作汉堡材料: " .. #ingredients .. " 件"
end

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
                if dist > S.EspRange then
                    clearESP(m)
                elseif dist <= S.EspRange and obj.Health > 0 then
                    makeESP(m)
                end
            end
        end
    end
end

local function getThemeColor(themeName)
    local colors = {
        Dark = Color3.fromRGB(80, 170, 255),
        Light = Color3.fromRGB(60, 130, 210),
        Rose = Color3.fromRGB(255, 130, 170),
        Plant = Color3.fromRGB(70, 210, 130),
        Ocean = Color3.fromRGB(60, 190, 240),
        Sunset = Color3.fromRGB(255, 160, 70),
        Midnight = Color3.fromRGB(130, 100, 240),
        Forest = Color3.fromRGB(60, 180, 90),
        Lavender = Color3.fromRGB(190, 140, 255),
        Coral = Color3.fromRGB(255, 140, 90),
        Mint = Color3.fromRGB(80, 230, 190),
        Sky = Color3.fromRGB(100, 190, 255),
        Blood = Color3.fromRGB(230, 90, 80),
        Lemon = Color3.fromRGB(230, 210, 70),
        Cyber = Color3.fromRGB(0, 235, 210)
    }
    local c = colors[themeName]
    if c then return c end
    return Color3.fromRGB(80, 170, 255)
end

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
            p.Sx = p.Sx + p.Vx
            p.Sy = p.Sy + p.Vy
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
            S.KillNPC = false
            S.GrindBodies = false
            S.MakeBurgers = false
            S.CollectMoney = false
            S.AutoMode = false
            S.EspEnabled = false
            clearAllESP()
            for k, ct in pairs(CT) do
                if ct and type(ct.Set) == "function" then
                    pcall(function() ct:Set(false) end)
                end
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

    local t1 = WN:Tab({Title = "主控面板", Icon = "solar:slider-vertical-bold"})
    CT.KillNPC = t1:Toggle({Flag = "KillNPC", Title = "自动杀死NPC", Value = false, Callback = function(v) S.KillNPC = v end})
    CT.GrindBodies = t1:Toggle({Flag = "GrindBodies", Title = "自动粉碎尸体", Value = false, Callback = function(v) S.GrindBodies = v end})
    CT.MakeBurgers = t1:Toggle({Flag = "MakeBurgers", Title = "自动做汉堡", Value = false, Callback = function(v) S.MakeBurgers = v end})
    CT.CollectMoney = t1:Toggle({Flag = "CollectMoney", Title = "自动收集金钱", Value = false, Callback = function(v) S.CollectMoney = v end})
    CT.AutoMode = t1:Toggle({Flag = "AutoMode", Title = "全自动模式", Desc = "杀NPC→粉碎→做汉堡→收钱", Value = false, Callback = function(v) S.AutoMode = v end})
    t1:Divider()
    CT.Esp = t1:Toggle({Flag = "EspEnabled", Title = "NPC透视", Value = false, Callback = function(v) S.EspEnabled = v; if not v then clearAllESP() end end})
    t1:Divider()
    CT.KillRange = t1:Slider({Flag = "KillRange", Title = "攻击范围", Step = 5, Value = {Min = 5, Max = 100, Default = 20}, Width = 200, IsTextbox = true, Callback = function(v) S.KillRange = v end})

    local t2 = WN:Tab({Title = "功能设置", Icon = "solar:settings-bold"})
    t2:Keybind({Flag = "KillKey", Title = "杀NPC快捷键", Value = "", Callback = function(v) KB.Kill = v end})
    t2:Keybind({Flag = "GrindKey", Title = "粉碎快捷键", Value = "", Callback = function(v) KB.Grind = v end})
    t2:Keybind({Flag = "BurgerKey", Title = "做汉堡快捷键", Value = "", Callback = function(v) KB.Burger = v end})
    t2:Keybind({Flag = "MoneyKey", Title = "收钱快捷键", Value = "", Callback = function(v) KB.Money = v end})

    local t3 = WN:Tab({Title = "UI设置", Icon = "solar:monitor-bold"})
    t3:Keybind({Flag = "WindowKey", Title = "窗口快捷键", Value = "RightShift", Callback = function(v) KB.Window = v end})
    CT.Particles = t3:Toggle({Flag = "Particles", Title = "粒子背景", Value = true, Callback = function(v)
        S.Particles = v
        if v then
            task.spawn(function()
                task.wait(0.3)
                local WF = nil
                for _, c in ipairs(WN.Parent:GetChildren()) do
                    if c:IsA("Frame") and c.AbsoluteSize.X > 400 then WF = c; break end
                end
                if WF then mkParts(WF) end
            end)
        else
            killParts()
        end
    end})
    CT.Acrylic = t3:Toggle({Flag = "Acrylic", Title = "毛玻璃", Value = true, Callback = function(v) S.Acrylic = v; pcall(function() WI:ToggleAcrylic(v) end) end})
    CT.Transparent = t3:Toggle({Flag = "Transparent", Title = "透明背景", Value = false, Callback = function(v) S.Transparent = v; pcall(function() WN:ToggleTransparency(v) end) end})
    local themeNames = {"Dark", "Light", "Rose", "Plant", "Ocean", "Sunset", "Midnight", "Forest", "Lavender", "Coral", "Mint", "Sky", "Blood", "Lemon", "Cyber"}
    CT.Theme = t3:Dropdown({Flag = "Theme", Title = "选择主题", Values = themeNames, Value = "Dark", Callback = function(v)
        pcall(function() WI:SetTheme(v) end)
        S.ParticleColor = getThemeColor(v)
    end})

    local t4 = WN:Tab({Title = "信息统计", Icon = "solar:chart-bold"})
    local npcP = t4:Paragraph({Title = "👤 NPC: 0"})
    local bodyP = t4:Paragraph({Title = "🦴 尸体: 0"})
    local moneyP = t4:Paragraph({Title = "💰 金钱: 0"})
    local ingP = t4:Paragraph({Title = "🍔 食材: 0"})

    local t5 = WN:Tab({Title = "配置管理", Icon = "solar:diskette-bold"})
    t5:Input({Flag = "CN", Title = "配置名称", Value = "default", Icon = "solar:file-text-bold", Callback = function(v) end})
    t5:Button({Title = "💾 保存", Icon = "solar:check-circle-bold", Justify = "Center", Color = Color3.fromHex("#305dff"), Callback = function() end})
    t5:Button({Title = "📂 加载", Icon = "solar:refresh-circle-bold", Justify = "Center", Color = Color3.fromHex("#10C550"), Callback = function() end})
    t5:Button({Title = "🗑️ 删除", Icon = "solar:trash-bin-trash-bold", Justify = "Center", Color = Color3.fromHex("#ff3040"), Callback = function() end})

    local t6 = WN:Tab({Title = "关于", Icon = "solar:info-square-bold"})
    t6:Paragraph({Title = "汉堡自动脚本 v2.3"})
    t6:Divider()
    t6:Paragraph({Title = "👤 作者", Desc = "b站英吉利超入_"})
    t6:Divider()
    t6:Paragraph({Title = "💡 使用", Desc = IM and "手机:点击悬浮按钮" or "PC: RightShift打开菜单"})
    t6:Paragraph({Title = "⚠️ 全杀模式", Desc = "所有NPC都是目标，不分类"})

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

local PP = false
pcall(function() WI:SetTheme("Dark") end)
S.ParticleColor = getThemeColor("Dark")
WI:Popup({
    Title = "🍔 汉堡自动脚本 v2.3",
    Content = "⚔️ 自动杀死NPC(全杀模式)\n🧹 自动粉碎尸体\n🍔 自动做汉堡\n💰 自动收集金钱(桌上/地上)\n👁 NPC透视\n\n⚠️ 所有功能默认关闭",
    Buttons = {{Title = "确认加载", Callback = function() PP = true end, Variant = "Primary"}}
})
while not PP do task.wait(0.1) end

local function mainLoop()
    local npcP, bodyP, moneyP, ingP = makeWindow()
    WI:Notify({Title = "🍔 汉堡脚本", Content = "已加载! 按RightShift开窗口", Duration = 3, Icon = "solar:bell-bold"})
    local lastInfoUpdate = 0
    while true do
        local now = tick()
        if S.AutoMode then
            doKillNPC()
            task.wait(0.3)
            doGrindBody()
            task.wait(0.3)
            doMakeBurger()
            task.wait(0.3)
            doCollectMoney()
            task.wait(1)
        else
            if S.KillNPC then doKillNPC(); task.wait(0.3) end
            if S.GrindBodies then doGrindBody(); task.wait(0.3) end
            if S.MakeBurgers then doMakeBurger(); task.wait(0.3) end
            if S.CollectMoney then doCollectMoney(); task.wait(0.3) end
        end
        doESPScan()
        if now - lastInfoUpdate > 3 then
            lastInfoUpdate = now
            local npcs = getNearbyNPCs(100)
            local bodies = getBodies()
            local orbs = getMoneyOrbs(100)
            local ingredients = getIngredients()
            if npcP then pcall(function() npcP:SetTitle("👤 NPC: " .. #npcs) end) end
            if bodyP then pcall(function() bodyP:SetTitle("🦴 尸体: " .. #bodies) end) end
            if moneyP then pcall(function() moneyP:SetTitle("💰 金钱: " .. #orbs) end) end
            if ingP then pcall(function() ingP:SetTitle("🍔 食材: " .. #ingredients) end) end
        end
        task.wait(2)
    end
end

task.spawn(mainLoop)
