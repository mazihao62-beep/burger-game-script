-- 汉堡游戏自动脚本 v2.9.0
-- 作者: b站英吉利超入_
-- 🔧 v2.9.0: 修复 gf or{}崩溃 + 全局pcall保护 + 重写粉碎逻辑(PickupItem传Model)

print("[Burger v2.9.0] 加载中...")

local P = game:GetService("Players")
local WS = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local CS = game:GetService("CollectionService")
local C = game:GetService("CoreGui")

local LP = nil
for i = 1, 50 do LP = P.LocalPlayer; if LP then break end; wait(0.1) end
if not LP then return end

local IM = false
pcall(function() IM = UIS.TouchEnabled and not UIS.KeyboardEnabled end)

-- ============ 远程事件 ============
local MeleeEvent, PickupEvent, DropEvent, StoreSackEvent, UnstoreSackEvent
local remotesReady = false

local function loadRemotes()
    local ok = pcall(function()
        MeleeEvent = RS.Network.MeleeHitEvent
        PickupEvent = RS.Remotes.PickupItem
        DropEvent = RS.Remotes.DropItem
        StoreSackEvent = RS.Network.StoreInSack
        UnstoreSackEvent = RS.Network.UnstoreFromSack
    end)
    if ok and MeleeEvent and PickupEvent and DropEvent then
        remotesReady = true
        print("[Burger v2.9.0] 远程OK: Melee/Pickup/Drop/StoreSack/UnstoreSack")
    else
        warn("[Burger v2.9.0] ⚠ 远程事件缺失!")
    end
end
loadRemotes()

-- ============ 清理旧UI ============
for _, g in ipairs(C:GetChildren()) do
    if g:IsA("ScreenGui") then
        local n = g.Name
        if n == "A" or n:find("BurgerESP") or n == "WindUI" or n:find("BurgerParticle") then
            pcall(function() g:Destroy() end)
        end
    end
end

-- ============ WindUI ============
local WI, loaded = nil, false
for i = 1, 6 do
    local ok, rv = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
    end)
    if ok and rv then WI = rv; loaded = true; break end
    wait(1.5)
end
if not loaded then return end

print("[Burger v2.9.0] WindUI loaded")

-- ============ 状态 ============
local S = {
    KillNPC = false, GrindBodies = false, CollectMoney = false,
    AutoMode = false, EspEnabled = false, EspRange = 200, KillRange = 50,
    AkillDamage = 26, Particles = true, Acrylic = true, Transparent = false,
    ParticleColor = Color3.fromRGB(80, 170, 255)
}
local KB = { Window = "RightShift" }
local WN, CT = nil, {}
local CF = "default"
local PR = false; local PS = {}; local PC = nil

-- ============ 工具 ============
local function matchKW(name, list)
    if not name then return false end
    local n = name:lower()
    for _, kw in ipairs(list) do if n:find(kw, 1, true) then return true end end
    return false
end

local function getTool(keywords)
    local bp = LP:FindFirstChild("Backpack")
    if not bp then return nil end
    for _, t in ipairs(bp:GetChildren()) do
        if t:IsA("Tool") and matchKW(t.Name, keywords) then return t end
    end
    return nil
end

local function equip(tool)
    if not tool then return false end
    local c = LP.Character
    if not c then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h then return false end
    if tool.Parent ~= c then h:EquipTool(tool); wait(0.15) end
    return true
end

local function isMe(m)
    for _, p in ipairs(P:GetPlayers()) do if p.Character == m then return true end end
    return false
end

-- ============ NPC ============
local function getNPCs(range)
    local npcs = {}
    local c = LP.Character
    if not c then return npcs end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return npcs end
    local pos = hrp.Position
    local seen = {}

    local roots = {WS}
    local gf = WS:FindFirstChild("GAMEFOLDERS")
    if gf then
        table.insert(roots, 1, gf)
        for _, folderName in ipairs({"Customers","CustomCustomers","NPCs"}) do
            local f = gf:FindFirstChild(folderName)
            if f then table.insert(roots, 1, f) end
        end
    end
    for _, folderName in ipairs({"Customers","CustomCustomers","NPCs"}) do
        local f = WS:FindFirstChild(folderName)
        if f then table.insert(roots, 1, f) end
    end

    local realRange = range + 5
    for _, root in ipairs(roots) do
        pcall(function()
            for _, obj in ipairs(root:GetDescendants()) do
                if obj:IsA("Humanoid") and obj.Parent and obj.Parent:IsA("Model") then
                    local m = obj.Parent
                    if not seen[m] and not isMe(m) and obj.Health > 0 then
                        seen[m] = true
                        local mhrp = m:FindFirstChild("HumanoidRootPart")
                        if mhrp then
                            local d = (mhrp.Position - pos).Magnitude
                            if d <= realRange then table.insert(npcs, {M = m, H = obj, P = mhrp, D = d}) end
                        end
                    end
                end
            end
        end)
    end
    table.sort(npcs, function(a, b) return a.D < b.D end)
    return npcs
end

-- ============ 尸体 ============
local BODY_KW = {"customer","cop","civilian","police","officer","guard","worker","chef","noob","gun","medic","armor","oil","chefmon","gunslinger","normal","poor","rich","slinger"}
local NOT_BODY_KW = {"onion","tomato","bun","patty","cheese","lettuce","plate","meat","ingredient","food","bread","sauce","pickle","ketchup","mustard","bill","cash","money","coin","stand","grill","box","table","chair","door","wall","floor"}

local function isCorpse(body)
    local n = body.Name:lower()
    for _, kw in ipairs(BODY_KW) do if n:find(kw, 1, true) then return true end end
    for _, kw in ipairs(NOT_BODY_KW) do if n:find(kw, 1, true) then return false end end
    return n:find("body", 1, true) or n:find("corpse", 1, true) or n:find("dead", 1, true)
end

local function getBodies()
    local b = {}
    for _, obj in ipairs(CS:GetTagged("Pickable")) do
        if obj:IsA("Model") and isCorpse(obj) then table.insert(b, obj) end
    end
    return b
end

-- ============ 金钱 ============
local function getMoney()
    local bills = {}
    local items = WS:FindFirstChild("ITEMS")
    if items then
        for _, obj in ipairs(items:GetDescendants()) do
            local pp = obj:FindFirstChildOfClass("ProximityPrompt")
            if pp then table.insert(bills, {M = obj, P = pp}) end
            if obj:IsA("BasePart") and matchKW(obj.Name, {"cash","money","bill","coin"}) then
                if not pp then table.insert(bills, {T = obj}) end
            end
        end
    end
    return bills
end

-- ============ 场景物品 ============
local function findPart(name)
    local wp = WS:FindFirstChild("WORLDPARTS")
    if not wp then return nil end
    for _, obj in ipairs(wp:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name == name then return obj end
    end
    return nil
end

local function getPosPart(model)
    if not model then return nil end
    if model:IsA("BasePart") then return model end
    if model:IsA("Model") then
        local ok, pp = pcall(function() return model.PrimaryPart end)
        if ok and pp then return pp end
    end
    for _, c in ipairs(model:GetChildren()) do
        if c:IsA("BasePart") then return c end
    end
    return nil
end

local function findHitPart(model)
    if not model then return nil end
    if not model:IsA("Model") then return nil end
    local hh = model:FindFirstChild("HeadHitbox", true)
    if hh and hh:IsA("BasePart") then return hh end
    local parts = {"Head","UpperTorso","Torso","LowerTorso"}
    for _, name in ipairs(parts) do
        local p = model:FindFirstChild(name, true)
        if p and p:IsA("BasePart") then return p end
    end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then return d end
    end
    return nil
end

-- ============ 1. 杀NPC ============
local NORMAL_FRONT = Vector3.new(0, 0, 1)

local function doKillNPC()
    local npcs = getNPCs(S.KillRange)
    if #npcs == 0 then return false, "无NPC" end
    local t = npcs[1]

    local tool = getTool({"spatula","shovel","knife","sword","bat","hammer","axe","weapon","cleaver"})
    if not tool then return false, "无武器" end
    equip(tool)

    local c = LP.Character
    if not c then return false end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp or not t.P then return false end

    hrp.CFrame = t.P.CFrame * CFrame.new(0, 0, 2)
    wait(0.3)

    local hNow = t.M:FindFirstChildOfClass("Humanoid")
    if not hNow or hNow.Health <= 0 then return false, "NPC已死" end

    local hp = findHitPart(t.M)
    if not hp then hp = t.P end

    print("[Kill] 🔪 " .. t.M.Name .. "(" .. hp.Name .. ") @" .. math.floor(t.D) .. "m")

    if remotesReady and MeleeEvent then
        pcall(function() MeleeEvent:FireServer(hp, hp.Position, NORMAL_FRONT, S.AkillDamage) end)
        return true, "击杀: " .. t.M.Name
    end

    return false, "无远程"
end

-- ============ 2. 粉碎尸体 ============
local function doGrindBody()
    local grinder = findPart("Grinder")
    if not grinder then return false, "无Grinder" end

    local bodies = getBodies()
    if #bodies == 0 then return false, "无尸体" end

    local body = bodies[1]
    local c = LP.Character
    if not c then return false end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    print("[Grind] 尸体: " .. body.Name)

    -- 方案1: StoreInSack + UnstoreFromSack
    if remotesReady and StoreSackEvent and UnstoreSackEvent then
        local sack = getTool({"sack","bag","container","box"})
        equip(sack)
        wait(0.2)
        pcall(function() StoreSackEvent:FireServer(sack, body) end)
        print("[Grind] Storesack ✅")
        wait(0.3)

        local bp = getPosPart(body)
        if bp then hrp.CFrame = bp.CFrame * CFrame.new(0, 0, 2); wait(0.2) end
        hrp.CFrame = grinder.CFrame * CFrame.new(0, 0, 2.5)
        wait(0.3)

        local cs = c:FindFirstChild("Sack") or sack
        pcall(function() UnstoreSackEvent:FireServer(cs) end)
        print("[Grind] Unstoresack ✅ → 粉碎完成!")
        return true, "粉碎(SK): " .. body.Name
    end

    -- 方案2: PickupItem+DropItem 传Model
    if remotesReady and PickupEvent and DropEvent then
        local bp = getPosPart(body)
        if bp then hrp.CFrame = bp.CFrame * CFrame.new(0, 0, 2); wait(0.2) end

        pcall(function() PickupEvent:FireServer(body) end)
        print("[Grind] PickupItem(Model) ✅")
        wait(0.5)

        hrp.CFrame = grinder.CFrame * CFrame.new(0, 0, 2.5)
        wait(0.3)

        pcall(function() DropEvent:FireServer(body, grinder.Position) end)
        print("[Grind] DropItem(Model) ✅ → 粉碎完成!")
        return true, "粉碎: " .. body.Name
    end

    return false, "粉碎失败"
end

-- ============ 3. 收钱 ============
local function doCollectMoney()
    local c = LP.Character
    if not c then return false end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local bills = getMoney()
    if #bills == 0 then return false, "无金钱" end

    local n = 0
    for _, b in ipairs(bills) do
        if b.P then
            local target = nil
            if b.M:IsA("BasePart") then target = b.M
            elseif b.M:IsA("Model") then
                for _, d in ipairs(b.M:GetDescendants()) do if d:IsA("BasePart") then target = d; break end end
            end
            local d = target and (target.Position - hrp.Position).Magnitude or 999
            if d <= 80 then
                if target then hrp.CFrame = target.CFrame * CFrame.new(0, 2, 0) end
                wait(0.15)
                pcall(function() fireproximityprompt(b.P) end)
                n = n + 1
            end
        elseif b.T then
            local d = (b.T.Position - hrp.Position).Magnitude
            if d <= 80 then
                hrp.CFrame = b.T.CFrame * CFrame.new(0, 2, 0)
                wait(0.15)
                local pp = b.T:FindFirstChildOfClass("ProximityPrompt")
                if pp then pcall(function() fireproximityprompt(pp) end) end
                n = n + 1
            end
        end
        if n >= 30 then break end
    end
    if n > 0 then return true, "收钱: " .. n end
    return false, "无金钱"
end

-- ============ 粒子系统 (全屏ScreenGui) ============
local function startParticles()
    if PR then return end
    if PC then pcall(function() local p = PC.Parent; if p then p:Destroy() end end); PC = nil end
    PS = {}

    wait(0.3)
    local sg = Instance.new("ScreenGui")
    sg.Name = "BurgerParticle_SG"
    sg.ResetOnSpawn = false; sg.DisplayOrder = 999999; sg.IgnoreGuiInset = true; sg.Parent = C

    PC = Instance.new("Frame")
    PC.Size = UDim2.new(1, 0, 1, 0); PC.BackgroundTransparency = 1; PC.BorderSizePixel = 0; PC.Active = false; PC.Parent = sg

    local col = S.ParticleColor
    for i = 1, 50 do
        local d = Instance.new("Frame")
        local sz = math.random(5, 10)
        d.Size = UDim2.new(0, sz, 0, sz)
        local sx = 0.2 + math.random() * 0.6
        local sy = 0.2 + math.random() * 0.6
        d.Position = UDim2.new(sx, 0, sy, 0)
        d.BackgroundColor3 = col; d.BackgroundTransparency = 0.3 + math.random() * 0.5; d.BorderSizePixel = 0; d.Parent = PC
        Instance.new("UICorner", d).CornerRadius = UDim.new(0, 10)
        local a = math.random() * 6.28; local sp = 0.0008 + math.random() * 0.002
        table.insert(PS, {F = d, Sx = sx, Sy = sy, Vx = math.cos(a) * sp, Vy = math.sin(a) * sp, Ph = math.random() * 6.28, Sz = sz})
    end

    PR = true
    spawn(function()
        local t = 0
        while PR and PC do
            t = t + 0.03
            pcall(function()
                local curCol = S.ParticleColor
                for _, p in ipairs(PS) do
                    if p.F and p.F.Parent then
                        local sx = math.max(0.05, math.min(0.95, p.Sx + p.Vx))
                        local sy = math.max(0.05, math.min(0.95, p.Sy + p.Vy))
                        if sx >= 0.95 or sx <= 0.05 then p.Vx = -p.Vx end
                        if sy >= 0.95 or sy <= 0.05 then p.Vy = -p.Vy end
                        p.Sx = sx; p.Sy = sy
                        p.F.Position = UDim2.new(sx, 0, sy, 0)
                        if curCol ~= p.F.BackgroundColor3 then p.F.BackgroundColor3 = curCol end
                        p.F.BackgroundTransparency = 0.3 + math.sin(t * 0.8 + p.Ph) * 0.4
                        local bs = math.max(2, p.Sz + math.sin(t + p.Ph) * 1.5)
                        p.F.Size = UDim2.new(0, bs, 0, bs)
                    end
                end
            end)
            wait(0.03)
        end
    end)
end

local function stopParticles()
    PR = false
    if PC then pcall(function() local p = PC.Parent; if p then p:Destroy() end end); PC = nil end
    PS = {}
end

-- ============ ESP ============
local EO = {}
local function mESP(t)
    if EO[t] then return end
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 200, 0, 50); bb.MaxDistance = S.EspRange
    bb.AlwaysOnTop = true; bb.StudsOffset = Vector3.new(0, 4, 0)
    pcall(function() bb.Parent = t end)
    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.new(1, 0, 1, 0); tl.Text = "💀 NPC"
    tl.TextColor3 = Color3.fromRGB(255, 40, 40)
    tl.BackgroundTransparency = 0.7; tl.BackgroundColor3 = Color3.new(0, 0, 0)
    tl.TextScaled = true; tl.Font = Enum.Font.SourceSansBold; tl.Parent = bb
    local hl = Instance.new("Highlight")
    hl.FillColor = Color3.fromRGB(255, 40, 40); hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.3; hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    pcall(function() hl.Parent = t end)
    EO[t] = {B = bb, H = hl}
end

local function cESP(t)
    local e = EO[t]
    if e then pcall(function() e.B:Destroy() end); pcall(function() e.H:Destroy() end); EO[t] = nil end
end

local function cAll()
    for t, _ in pairs(EO) do cESP(t) end; EO = {}
end

local function doESP()
    if not S.EspEnabled then return end
    local c = LP.Character
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    local pos = hrp and hrp.Position
    for _, obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("Humanoid") and obj.Parent and obj.Parent:IsA("Model") then
            local m = obj.Parent
            if not isMe(m) then
                local mhrp = m:FindFirstChild("HumanoidRootPart")
                local d = pos and mhrp and (mhrp.Position - pos).Magnitude or 999
                if d > S.EspRange then cESP(m)
                elseif d <= S.EspRange and obj.Health > 0 then mESP(m) end
            end
        end
    end
end

-- ============ 主题 ============
local function tc(n)
    local c = {
        Dark = Color3.fromRGB(80, 170, 255), Light = Color3.fromRGB(60, 130, 210),
        Rose = Color3.fromRGB(255, 130, 170), Plant = Color3.fromRGB(70, 210, 130),
        Ocean = Color3.fromRGB(60, 190, 240), Sunset = Color3.fromRGB(255, 160, 70),
        Midnight = Color3.fromRGB(130, 100, 240), Forest = Color3.fromRGB(60, 180, 90),
        Lavender = Color3.fromRGB(190, 140, 255), Coral = Color3.fromRGB(255, 140, 90),
        Mint = Color3.fromRGB(80, 230, 190), Sky = Color3.fromRGB(100, 190, 255),
        Blood = Color3.fromRGB(230, 90, 80), Lemon = Color3.fromRGB(230, 210, 70),
        Cyber = Color3.fromRGB(0, 235, 210)
    }
    return c[n] or Color3.fromRGB(80, 170, 255)
end

-- ============ UI ============
local function makeWindow()
    WN = WI:CreateWindow({
        Title = "🍔 汉堡自动脚本", Author = "b站英吉利超入_", Icon = "solar:hamburger-bold",
        Size = UDim2.fromOffset(750, 520), ToggleKey = Enum.KeyCode.RightShift,
        Folder = "burger-script", Acrylic = true,
        Resizable = false, ScrollBarEnabled = true, HideSearchBar = true,
        OnClose = function()
            stopParticles()
            S.KillNPC = false; S.GrindBodies = false
            S.CollectMoney = false; S.AutoMode = false; S.EspEnabled = false
            cAll()
            for _, ct in pairs(CT) do
                if ct and type(ct.Set) == "function" then pcall(function() ct:Set(false) end) end
            end
        end,
        OnOpen = function()
            if S.Particles then startParticles() end
        end
    })

    spawn(function()
        wait(0.8)
        pcall(function()
            if WN and WN.Parent then
                WN.Parent.ClipsDescendants = true
                print("[Burger v2.9.0] ✅ ClipsDescendants(毛玻璃裁剪)")
            end
        end)
    end)

    spawn(function() wait(0.5); pcall(function() WN:SetToggleKey(Enum.KeyCode.RightShift) end) end)

    -- Tab 1: 主控面板
    local t1 = WN:Tab({Title = "主控面板", Icon = "solar:slider-vertical-bold"})
    CT.KillNPC = t1:Toggle({Flag = "KillNPC", Title = "自动杀死NPC(爆头)", Value = false, Callback = function(v) S.KillNPC = v end})
    CT.GrindBodies = t1:Toggle({Flag = "GrindBodies", Title = "自动粉碎尸体", Value = false, Callback = function(v) S.GrindBodies = v end})
    CT.CollectMoney = t1:Toggle({Flag = "CollectMoney", Title = "自动收集金钱", Value = false, Callback = function(v) S.CollectMoney = v end})
    CT.AutoMode = t1:Toggle({Flag = "AutoMode", Title = "⚡ 全自动模式", Desc = "杀NPC→粉碎→收钱 全链", Value = false, Callback = function(v) S.AutoMode = v end})
    t1:Divider()
    CT.Esp = t1:Toggle({Flag = "EspEnabled", Title = "NPC透视", Value = false, Callback = function(v) S.EspEnabled = v; if not v then cAll() end end})
    t1:Divider()
    CT.KillRange = t1:Slider({Flag = "KillRange", Title = "攻击范围", Step = 5, Value = {Min = 5, Max = 200, Default = 50}, Width = 200, IsTextbox = true, Callback = function(v) S.KillRange = v end})

    -- Tab 2: 功能设置
    local t2 = WN:Tab({Title = "功能设置", Icon = "solar:settings-bold"})
    t2:Keybind({Flag = "KillKey", Title = "杀NPC快捷键", Value = "", Callback = function(v) KB.Kill = v end})
    t2:Keybind({Flag = "GrindKey", Title = "粉碎快捷键", Value = "", Callback = function(v) KB.Grind = v end})
    t2:Keybind({Flag = "MoneyKey", Title = "收钱快捷键", Value = "", Callback = function(v) KB.Money = v end})

    -- Tab 3: UI设置
    local t3 = WN:Tab({Title = "UI设置", Icon = "solar:monitor-bold"})
    t3:Keybind({Flag = "WindowKey", Title = "窗口快捷键", Value = "RightShift", Callback = function(v) KB.Window = v end})
    t3:Divider()
    CT.Particles = t3:Toggle({Flag = "Particles", Title = "粒子背景(全屏)", Value = true, Callback = function(v)
        S.Particles = v
        if v then startParticles() else stopParticles() end
    end})
    CT.Acrylic = t3:Toggle({Flag = "Acrylic", Title = "毛玻璃", Value = true, Callback = function(v) S.Acrylic = v; pcall(function() WI:ToggleAcrylic(v) end) end})
    CT.Transparent = t3:Toggle({Flag = "Transparent", Title = "透明背景", Value = false, Callback = function(v) S.Transparent = v; pcall(function() WN:ToggleTransparency(v) end) end})
    local tns = {"Dark","Light","Rose","Plant","Ocean","Sunset","Midnight","Forest","Lavender","Coral","Mint","Sky","Blood","Lemon","Cyber"}
    CT.Theme = t3:Dropdown({Flag = "Theme", Title = "选择主题", Values = tns, Value = "Dark", Callback = function(v)
        pcall(function() WI:SetTheme(v) end); S.ParticleColor = tc(v)
    end})

    -- Tab 4: 信息统计
    local t4 = WN:Tab({Title = "信息统计", Icon = "solar:chart-bold"})
    local npcP = t4:Paragraph({Title = "👤 NPC: 0"})
    local bodyP = t4:Paragraph({Title = "🦴 尸体: 0"})
    local moneyP = t4:Paragraph({Title = "💰 金钱: 0"})

    -- Tab 5: 配置管理
    local t5 = WN:Tab({Title = "配置管理", Icon = "solar:diskette-bold"})
    pcall(function()
        local CM = WN.ConfigManager
        if not CM then return end
        local cni = t5:Input({Flag = "CN", Title = "配置名称", Value = CF, Icon = "solar:file-text-bold", Callback = function(v) CF = v end})
        t5:Space()
        local AC = {}
        pcall(function() AC = CM:AllConfigs() end)
        local DV = nil
        pcall(function() for _, v in ipairs(AC) do if v == CF then DV = CF; break end end end)
        local ACD = t5:Dropdown({Title = "已有配置", Values = AC, Value = DV, Callback = function(v) if v then CF = v; pcall(function() cni:Set(v) end) end end})
        t5:Space()
        t5:Button({Title = "💾 保存", Icon = "solar:check-circle-bold", Justify = "Center", Color = Color3.fromHex("#305dff"),
            Callback = function()
                if not CM then return end
                local c = CM:Config(CF)
                if c and c:Save() then
                    WI:Notify({Title = "✅ 已保存", Content = "配置 '" .. CF .. "'", Duration = 3, Icon = "solar:check-circle-bold"})
                    pcall(function() ACD:Refresh(CM:AllConfigs()) end)
                end
            end})
        t5:Space()
        t5:Button({Title = "📂 加载", Icon = "solar:refresh-circle-bold", Justify = "Center", Color = Color3.fromHex("#10C550"),
            Callback = function()
                if not CM then return end
                local c = CM:CreateConfig(CF, false)
                if c and c:Load() then
                    WI:Notify({Title = "✅ 已加载", Content = "配置 '" .. CF .. "'", Duration = 3, Icon = "solar:refresh-circle-bold"})
                end
            end})
        t5:Space()
        t5:Button({Title = "🗑️ 删除", Icon = "solar:trash-bin-trash-bold", Justify = "Center", Color = Color3.fromHex("#ff3040"),
            Callback = function()
                if not CM then return end
                local c = CM:Config(CF)
                if c and c:Delete() then
                    WI:Notify({Title = "🗑️ 已删除", Content = "配置 '" .. CF .. "'", Duration = 3, Icon = "solar:trash-bin-trash-bold"})
                    pcall(function() ACD:Refresh(CM:AllConfigs()) end)
                end
            end})
        spawn(function() wait(1); pcall(function() CM:CreateConfig("default", true) end) end)
    end)

    -- Tab 6: 关于
    local t6 = WN:Tab({Title = "关于", Icon = "solar:info-square-bold"})
    t6:Paragraph({Title = "汉堡自动脚本 v2.9.0"})
    t6:Divider()
    t6:Paragraph({Title = "👤 作者", Desc = "b站英吉利超入_"})
    t6:Paragraph({Title = "💡 使用", Desc = IM and "手机:点击悬浮按钮" or "PC: RightShift打开菜单"})
    t6:Paragraph({Title = "🔧 v2.9.0", Desc = "🐛 彻底重写getNPCs(移除空表崩溃)\n🛡 全功能pcall保护\n🔪 单发FireServer精简击杀\n🦴 粉碎重写(Model直传)"})

    UIS.InputBegan:Connect(function(input, gpe)
        if gpe or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local keyName = input.KeyCode and input.KeyCode.Name or ""
        if keyName == KB.Kill then S.KillNPC = not S.KillNPC; if CT.KillNPC then CT.KillNPC:Set(S.KillNPC) end end
        if keyName == KB.Grind then S.GrindBodies = not S.GrindBodies; if CT.GrindBodies then CT.GrindBodies:Set(S.GrindBodies) end end
        if keyName == KB.Money then S.CollectMoney = not S.CollectMoney; if CT.CollectMoney then CT.CollectMoney:Set(S.CollectMoney) end end
    end)

    return npcP, bodyP, moneyP
end

-- ============ 主循环 ============
local PP = false
pcall(function() WI:SetTheme("Dark") end)
S.ParticleColor = tc("Dark")
WI:Popup({
    Title = "🍔 汉堡自动脚本 v2.9.0",
    Content = "🐛 重写核心 | 杀NPC | 粉碎 | 收钱",
    Buttons = {{Title = "确认加载", Callback = function() PP = true end, Variant = "Primary"}}
})
while not PP do wait(0.1) end

local function mainLoop()
    local npcP, bodyP, moneyP = makeWindow()
    WI:Notify({
        Title = "🍔 汉堡 v2.9.0",
        Content = "远程:" .. (remotesReady and "✅" or "⚠") .. " | 杀NPC | 粉碎 | 收钱",
        Duration = 3, Icon = "solar:bell-bold"
    })
    local last = 0
    while true do
        if S.AutoMode then
            pcall(function() doKillNPC() end); wait(0.3)
            pcall(function() doGrindBody() end); wait(0.3)
            pcall(function() doCollectMoney() end); wait(1)
        else
            if S.KillNPC then pcall(function() doKillNPC() end); wait(0.5) end
            if S.GrindBodies then pcall(function() doGrindBody() end); wait(0.5) end
            if S.CollectMoney then pcall(function() doCollectMoney() end); wait(0.5) end
        end
        pcall(function() doESP() end)
        local now = tick()
        if now - last > 3 then
            last = now
            if npcP then pcall(function() npcP:SetTitle("👤 NPC: " .. #getNPCs(100)) end) end
            if bodyP then pcall(function() bodyP:SetTitle("🦴 尸体: " .. #getBodies()) end) end
            if moneyP then pcall(function() moneyP:SetTitle("💰 金钱: " .. #getMoney()) end) end
        end
        wait(2)
    end
end

spawn(mainLoop)
