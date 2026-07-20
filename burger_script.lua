-- 汉堡游戏自动脚本 v2.5.9
-- 作者: b站英吉利超入_
-- 修复: 强化调试模式，打印尸体/食材站内部结构，PickupItem用PrimaryPart(不限类型)，Kill修复等

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

-- ============ 远程事件 ============
local MeleeEvent, PickupEvent, DropEvent, OrderEvent, StoreSackEvent, UnstoreSackEvent
local SackStorage = nil
local remotesReady = false

local function loadRemotes()
    local ok = pcall(function()
        MeleeEvent = RS.Network.MeleeHitEvent
        PickupEvent = RS.Remotes.PickupItem
        DropEvent = RS.Remotes.DropItem
        OrderEvent = RS.Network.LinkPlayerToOrder
        StoreSackEvent = RS.Network.StoreInSack
        UnstoreSackEvent = RS.Network.UnstoreFromSack
        local igo = RS:FindFirstChild("InGameObjects")
        if igo then SackStorage = igo:FindFirstChild("SackStorage") end
    end)
    if ok and MeleeEvent and PickupEvent and DropEvent then
        remotesReady = true
        print("[Burger v2.5.9] 远程OK: Melee/Pickup/Drop/Order/Sack/Unstore")
        if SackStorage then
            local names = {}
            for _, v in ipairs(SackStorage:GetChildren()) do table.insert(names, v.Name) end
            print("[Burger v2.5.9] SackStorage:" .. (#names > 0 and table.concat(names, ", ") or " (空-等NPC出现后动态生成)"))
        end
    else
        warn("[Burger v2.5.9] ⚠ 远程事件缺失!")
    end
end
loadRemotes()

-- ============ 清理旧UI ============
for _, g in ipairs(C:GetChildren()) do
    if g:IsA("ScreenGui") then
        local n = g.Name
        if n == "A" or n:find("BurgerESP") or n == "WindUI" then pcall(function() g:Destroy() end) end
    end
end

-- ============ WindUI ============
local WI, loaded = nil, false
for i = 1, 6 do
    local ok, rv = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
    end)
    if ok and rv then WI = rv; loaded = true; break end
    task.wait(1.5)
end
if not loaded then return end

-- ============ 状态 ============
local S = {
    KillNPC = false, GrindBodies = false, MakeBurgers = false, CollectMoney = false,
    AutoMode = false, EspEnabled = false, EspRange = 200, KillRange = 35,
    AkillDamage = 26, Particles = true, Acrylic = true, Transparent = false,
    ParticleColor = Color3.fromRGB(80, 170, 255)
}
local KB = { Window = "RightShift" }
local WN, CT = nil, {}
local PH, PC, PS = nil, nil, {}

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
    if tool.Parent ~= c then h:EquipTool(tool); task.wait(0.2) end
    return true
end

-- ============ 玩家判断 ============
local function isMe(m)
    for _, p in ipairs(P:GetPlayers()) do if p.Character == m then return true end end
    return false
end

-- ============ NPC v2.5.9: killFirst跟踪 + 默认35m ============
local gfPrinted = false

local function getNPCs(range)
    local npcs = {}
    local c = LP.Character
    if not c then return npcs end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return npcs end
    local pos = hrp.Position
    local seen = {}

    if not gfPrinted then
        gfPrinted = true
        local gf = WS:FindFirstChild("GAMEFOLDERS")
        if gf then
            local children = {}
            for _, child in ipairs(gf:GetChildren()) do table.insert(children, child.Name .. "(" .. child.ClassName .. ")") end
            print("[Debug] GAMEFOLDERS: " .. table.concat(children, ", "))
        end
    end

    local roots = {WS}
    local gf = WS:FindFirstChild("GAMEFOLDERS")
    if gf then table.insert(roots, 1, gf) end
    for _, folderName in ipairs({"Customers","CustomCustomers","NPCs"}) do
        for _, parent in ipairs({WS, gf or {}}) do
            local f = parent:FindFirstChild(folderName)
            if f then table.insert(roots, 1, f) end
        end
    end

    local realRange = range + 3
    for _, root in ipairs(roots) do
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
    end
    table.sort(npcs, function(a, b) return a.D < b.D end)
    return npcs
end

-- ============ 尸体 v2.5.9: 打印内部结构 ============
local BODY_KEYWORDS = {"customer","cop","civilian","police","officer","guard","worker","chef","noob","gun","medic","armor","oil","chefmon","gunslinger"}
local NOT_BODY_KEYWORDS = {"onion","tomato","bun","patty","cheese","lettuce","plate","meat","ingredient","food","bread","sauce","pickle","ketchup","mustard","bill","cash","money","coin","stand","grill","box","table","chair","door","wall","floor"}

local function isCorpse(body)
    local n = body.Name:lower()
    for _, kw in ipairs(BODY_KEYWORDS) do
        if n:find(kw, 1, true) then return true end
    end
    for _, kw in ipairs(NOT_BODY_KEYWORDS) do
        if n:find(kw, 1, true) then return false end
    end
    return n:find("body", 1, true) or n:find("corpse", 1, true) or n:find("dead", 1, true) or n:find("remains", 1, true)
end

local function getBodies()
    local b = {}
    for _, obj in ipairs(CS:GetTagged("Pickable")) do
        if obj:IsA("Model") and isCorpse(obj) then table.insert(b, obj) end
    end
    return b
end

local function bodyQuality(body)
    if not body or not SackStorage then return nil end
    local children = SackStorage:GetChildren()
    if #children == 0 then return nil end
    local n = body.Name:lower()
    for _, q in ipairs(children) do
        if n:find(q.Name:lower(), 1, true) then return q end
    end
    return children[1]
end

-- 🔑 v2.5.9: 打印模型结构 — 不假设任何Part类型
local printedDebug = {} -- 只打印每个模型名一次

local function getPickupPart(model, label)
    if not model then return nil end
    -- 直接取PrimaryPart(不限类型)
    local ok, pp = pcall(function() return model.PrimaryPart end)
    if ok and pp then
        if not printedDebug[model.Name] then
            printedDebug[model.Name] = true
            print("[" .. label .. "] " .. model.Name .. " → PrimaryPart: " .. pp.Name .. "(" .. pp.ClassName .. ")")
        end
        return pp
    end
    -- 兜底: Handle
    local h = model:FindFirstChild("Handle", true)
    if h then
        if not printedDebug[model.Name] then
            printedDebug[model.Name] = true
            print("[" .. label .. "] " .. model.Name .. " → Handle: " .. h.Name .. "(" .. h.ClassName .. ")")
        end
        return h
    end
    -- 最后: 第一个直系子Part
    for _, c in ipairs(model:GetChildren()) do
        if c:IsA("BasePart") then
            if not printedDebug[model.Name] then
                printedDebug[model.Name] = true
                print("[" .. label .. "] " .. model.Name .. " → FirstChild: " .. c.Name .. "(" .. c.ClassName .. ")")
            end
            return c
        end
    end
    -- 全量扫描
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            if not printedDebug[model.Name] then
                printedDebug[model.Name] = true
                print("[" .. label .. "] " .. model.Name .. " → Descendant: " .. d.Name .. "(" .. d.ClassName .. ")")
            end
            return d
        end
    end
    -- 绝境: 打印全部子对象
    if not printedDebug[model.Name] then
        printedDebug[model.Name] = true
        local parts = {}
        for _, c in ipairs(model:GetChildren()) do table.insert(parts, c.Name .. "(" .. c.ClassName .. ")") end
        print("[" .. label .. "] " .. model.Name .. " 无BasePart! 子项: " .. table.concat(parts, ", "))
    end
    return nil
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

local function getStands()
    local s = {}
    local wp = WS:FindFirstChild("WORLDPARTS")
    if not wp then return s end
    local efs = wp:FindFirstChild("EndlessFoodStands")
    if not efs then return s end
    for _, x in ipairs(efs:GetChildren()) do if x:IsA("Model") then table.insert(s, x) end end
    return s
end

local function getOrder()
    local b = WS:FindFirstChild("WORLDPARTS") and WS.WORLDPARTS:FindFirstChild("OrdersBoard")
    if not b then return nil end
    for _, obj in ipairs(b:GetDescendants()) do
        if obj:IsA("BillboardGui") then
            for _, c in ipairs(obj:GetDescendants()) do
                if c:IsA("TextLabel") and c.Text:find("ORDER") then return c.Text end
            end
        end
    end
    return nil
end

local function findHitPart(model)
    if not model then return nil end
    local hh = model:FindFirstChild("HeadHitbox", true)
    if hh and hh:IsA("BasePart") then return hh end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") and d.Name:find("Hitbox") then return d end
    end
    local parts = {"Head","UpperTorso","LowerTorso","LeftUpperArm","RightUpperArm","LeftLowerArm","RightLowerArm","LeftUpperLeg","RightUpperLeg","LeftLowerLeg","RightLowerLeg","Torso","LeftArm","RightArm","LeftLeg","RightLeg"}
    for _, name in ipairs(parts) do
        local p = model:FindFirstChild(name, true)
        if p and p:IsA("BasePart") then return p end
    end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then return d end
    end
    return nil
end

-- ============ 1. 杀NPC v2.5.9: 默认35m, 调试打印 ============
local NORMAL_FRONT = Vector3.new(0, 0, 1)

local function doKillNPC()
    local npcs = getNPCs(S.KillRange)
    if #npcs == 0 then
        local allNpcs = getNPCs(9999)
        if #allNpcs > 0 then
            local info = {}
            for _, n in ipairs(allNpcs) do table.insert(info, n.M.Name .. "@" .. math.floor(n.D) .. "m") end
            print("[Kill] " .. #allNpcs .. "个NPC超出" .. S.KillRange .. "m: " .. table.concat(info, ", "))
            print("[Kill] 💡 最近: " .. allNpcs[1].M.Name .. "@" .. math.floor(allNpcs[1].D) .. "m → 调范围到" .. math.ceil(allNpcs[1].D + 3) .. "+")
        end
        return false, "无NPC"
    end
    local t = npcs[1]

    local tool = getTool({"spatula","shovel","knife","sword","bat","hammer","axe","weapon","cleaver"})
    if not tool then return false, "无武器" end
    equip(tool)

    local c = LP.Character
    if not c then return false end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp or not t.P then return false end

    -- 传送到NPC正前方
    hrp.CFrame = t.P.CFrame * CFrame.new(0, 0, 3)
    task.wait(0.35)

    -- 再次确认NPC还活着(可能在等传送时死了/消失了)
    local refreshed = t.M:FindFirstChildOfClass("Humanoid")
    if not refreshed or refreshed.Health <= 0 then
        print("[Kill] ⚠ NPC已死亡: " .. t.M.Name)
        return false, "NPC已死"
    end

    local hp = findHitPart(t.M)
    if not hp then hp = t.P end

    local dmg = S.AkillDamage
    print("")
    print("[Kill] 🔪 " .. t.M.Name .. "(" .. hp.Name .. ") @" .. math.floor(t.D) .. "m | 剩" .. (#npcs - 1) .. "个")

    if remotesReady and MeleeEvent then
        for i = 1, 3 do
            local ok, err = pcall(function()
                MeleeEvent:FireServer(hp, hp.Position, NORMAL_FRONT, dmg)
            end)
            if ok then
                -- 成功无输出(减少刷屏)
            else
                print("[Kill] ❌ FS#" .. i .. ": " .. tostring(err):sub(1, 60))
            end
            task.wait(0.25)
        end
        return true, "击杀: " .. t.M.Name
    end

    -- 降级: VIM
    pcall(function()
        local V = game:GetService("VirtualInputManager")
        V:SendMouseButtonEvent(960, 540, 0, true, game, 0); task.wait(0.05)
        V:SendMouseButtonEvent(960, 540, 0, false, game, 0); task.wait(0.1)
    end)
    return true, "击杀(VIM): " .. t.M.Name
end

-- ============ 2. 粉碎 v2.5.9: getPickupPart不限类型 ============
local function doGrindBody()
    local grinder = findPart("Grinder")
    if not grinder then return false, "无Grinder" end

    local bodies = getBodies()
    if #bodies == 0 then return false, "无尸体" end

    local body = bodies[1]
    local sack = getTool({"sack","bag","container","box"})
    local c = LP.Character
    if not c then return false end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    print("[Grind] 尸体: " .. body.Name)

    -- 方式1: Sack系统
    if remotesReady and StoreSackEvent and UnstoreSackEvent and SackStorage then
        equip(sack)
        task.wait(0.2)

        local q = bodyQuality(body)
        if q then
            local bp = getPickupPart(body, "Grind")
            if bp then
                hrp.CFrame = bp.CFrame * CFrame.new(0, 0, 2)
                task.wait(0.25)
            end
            pcall(function() StoreSackEvent:FireServer(sack, q) end)
            print("[Grind] ✅ StoreInSack → " .. q.Name)
            task.wait(0.5)
            hrp.CFrame = grinder.CFrame * CFrame.new(0, 0, 2.5)
            task.wait(0.3)
            local cs = c:FindFirstChild("Sack") or sack
            pcall(function() UnstoreSackEvent:FireServer(cs) end)
            print("[Grind] ✅ UnstoreFromSack → Grinder")
            return true, "粉碎: " .. body.Name .. "[" .. q.Name .. "]"
        end
        print("[Grind] SackStorage空,用备用")
    end

    -- 方式2: PickupItem → DropItem
    if remotesReady and PickupEvent and DropEvent then
        local bp = getPickupPart(body, "Grind")
        if not bp then
            print("[Grind] ⚠ " .. body.Name .. " 无可用Part,跳过")
            return false, "无可用Part"
        end

        hrp.CFrame = bp.CFrame * CFrame.new(0, 0, 1.5)
        task.wait(0.25)

        local ok, err = pcall(function() PickupEvent:FireServer(bp) end)
        print("[Grind] PickupItem → " .. bp.Name .. "(" .. bp.ClassName .. ") " .. (ok and "✅" or "❌" .. tostring(err):sub(1,50)))
        task.wait(0.4)

        hrp.CFrame = grinder.CFrame * CFrame.new(0, 0, 2.5)
        task.wait(0.3)

        ok, err = pcall(function() DropEvent:FireServer(bp, grinder.Position) end)
        print("[Grind] DropItem → Grinder " .. (ok and "✅" or "❌" .. tostring(err):sub(1,50)))
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
            else
                for _, d in ipairs(b.M:GetDescendants()) do if d:IsA("BasePart") then target = d; break end end
            end
            local d = target and (target.Position - hrp.Position).Magnitude or 999
            if d <= 80 then
                if target then hrp.CFrame = target.CFrame * CFrame.new(0, 2, 0) end
                task.wait(0.1)
                pcall(function() fireproximityprompt(b.P) end)
                n = n + 1
            end
        elseif b.T then
            local d = (b.T.Position - hrp.Position).Magnitude
            if d <= 80 then
                hrp.CFrame = b.T.CFrame * CFrame.new(0, 2, 0)
                task.wait(0.1)
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

-- ============ 4. 做汉堡 v2.5.9: getPickupPart + 更近距离 ============
local function doMakeBurger()
    local c = LP.Character
    if not c then return false end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    if remotesReady and OrderEvent then
        local order = getOrder()
        if order then
            pcall(function() OrderEvent:FireServer(order) end)
            print("[Burger] 接单: " .. order)
            task.wait(0.2)
        end
    end

    local stands = getStands()
    if #stands == 0 then return false, "无食材站" end

    local stand = stands[1]
    local sPart = getPickupPart(stand, "Burger")
    if not sPart then
        print("[Burger] ⚠ " .. stand.Name .. " 无PickupPart(见上方Debug)")
        return false, "无PickupPart"
    end

    -- 走到食材站(近距离)
    hrp.CFrame = sPart.CFrame * CFrame.new(0, 0, 1.5)
    task.wait(0.25)

    -- 捡食材
    if remotesReady and PickupEvent then
        local ok, err = pcall(function() PickupEvent:FireServer(sPart) end)
        print("[Burger] PickupItem → " .. sPart.Name .. "(" .. sPart.ClassName .. ") " .. (ok and "✅" or "❌" .. tostring(err):sub(1,50)))
        if not ok then return false, "PickupItem失败" end
    else
        local V = game:GetService("VirtualInputManager")
        V:SendKeyEvent(true, Enum.KeyCode.E, false, game); task.wait(0.05)
        V:SendKeyEvent(false, Enum.KeyCode.E, false, game)
        print("[Burger] E键捡食材")
    end
    task.wait(0.5)

    -- 走到烤架
    local grill = findPart("GrillHitbox") or findPart("Grill")
    if not grill then return false, "无烤架" end

    hrp.CFrame = grill.CFrame * CFrame.new(0, 0, 1.5)
    task.wait(0.25)

    -- 放烤架
    if remotesReady and DropEvent then
        local ok, err = pcall(function() DropEvent:FireServer(sPart, grill.Position) end)
        print("[Burger] DropItem → Grill " .. (ok and "✅" or "❌" .. tostring(err):sub(1,50)))
    else
        local V = game:GetService("VirtualInputManager")
        V:SendKeyEvent(true, Enum.KeyCode.E, false, game); task.wait(0.05)
        V:SendKeyEvent(false, Enum.KeyCode.E, false, game)
        print("[Burger] E键放烤架")
    end
    return true, "做汉堡: " .. stand.Name
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

-- ============ 粒子 ============
local function mkP(WF)
    if PC then pcall(function() PC:Destroy() end) end
    PS = {}
    for i = 1, 50 do
        local dot = Instance.new("Frame")
        local sz = math.random(5, 10)
        dot.Size = UDim2.new(0, sz, 0, sz)
        dot.Position = UDim2.new(0.05 + math.random() * 0.9, 0, 0.05 + math.random() * 0.9, 0)
        dot.BackgroundColor3 = S.ParticleColor; dot.BorderSizePixel = 0; dot.ZIndex = 5
        pcall(function() dot.Parent = PC end)
        table.insert(PS, {
            F = dot, Sx = dot.Position.X.Scale, Sy = dot.Position.Y.Scale,
            Vx = (math.random() - 0.5) * 0.0015, Vy = (math.random() - 0.5) * 0.0015
        })
    end
    if PH then PH:Disconnect() end
    PH = game:GetService("RunService").Heartbeat:Connect(function()
        for _, p in ipairs(PS) do
            if not p.F or not p.F.Parent then continue end
            p.Sx = p.Sx + p.Vx; p.Sy = p.Sy + p.Vy
            if p.Sx < 0.05 or p.Sx > 0.95 then p.Vx = -p.Vx end
            if p.Sy < 0.05 or p.Sy > 0.95 then p.Vy = -p.Vy end
            p.F.Position = UDim2.new(p.Sx, 0, p.Sy, 0)
            p.F.BackgroundColor3 = S.ParticleColor
            p.F.BackgroundTransparency = 0.3 + math.sin(tick() * 2) * 0.2
        end
    end)
end

local function kP()
    if PH then PH:Disconnect(); PH = nil end
    for _, p in ipairs(PS) do pcall(function() p.F:Destroy() end) end
    PS = {}; pcall(function() PC:Destroy() end); PC = nil
end

-- ============ UI ============
local function makeWindow()
    WN = WI:CreateWindow({
        Title = "🍔 汉堡自动脚本", Author = "b站英吉利超入_", Icon = "solar:hamburger-bold",
        Size = UDim2.fromOffset(750, 520), ToggleKey = Enum.KeyCode.RightShift,
        Folder = "burger-script", Acrylic = true, Resizable = false,
        ScrollBarEnabled = true, HideSearchBar = true,
        OnClose = function()
            kP()
            S.KillNPC = false; S.GrindBodies = false; S.MakeBurgers = false
            S.CollectMoney = false; S.AutoMode = false; S.EspEnabled = false
            cAll()
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
                    if WF then mkP(WF) end
                end
            end)
        end
    })

    task.spawn(function() task.wait(0.5); pcall(function() WN:SetToggleKey(Enum.KeyCode.RightShift) end) end)

    local t1 = WN:Tab({Title = "主控面板", Icon = "solar:slider-vertical-bold"})
    CT.KillNPC = t1:Toggle({Flag = "KillNPC", Title = "自动杀死NPC(爆头)", Value = false, Callback = function(v) S.KillNPC = v end})
    CT.GrindBodies = t1:Toggle({Flag = "GrindBodies", Title = "自动粉碎尸体", Value = false, Callback = function(v) S.GrindBodies = v end})
    CT.MakeBurgers = t1:Toggle({Flag = "MakeBurgers", Title = "自动做汉堡", Value = false, Callback = function(v) S.MakeBurgers = v end})
    CT.CollectMoney = t1:Toggle({Flag = "CollectMoney", Title = "自动收集金钱", Value = false, Callback = function(v) S.CollectMoney = v end})
    CT.AutoMode = t1:Toggle({Flag = "AutoMode", Title = "全自动模式", Desc = "杀NPC→粉碎→做汉堡→收钱", Value = false, Callback = function(v) S.AutoMode = v end})
    t1:Divider()
    CT.Esp = t1:Toggle({Flag = "EspEnabled", Title = "NPC透视", Value = false, Callback = function(v) S.EspEnabled = v; if not v then cAll() end end})
    t1:Divider()
    CT.KillRange = t1:Slider({Flag = "KillRange", Title = "攻击范围", Step = 5, Value = {Min = 5, Max = 200, Default = 35}, Width = 200, IsTextbox = true, Callback = function(v) S.KillRange = v end})

    local t2 = WN:Tab({Title = "功能设置", Icon = "solar:settings-bold"})
    t2:Keybind({Flag = "KillKey", Title = "杀NPC快捷键", Value = "", Callback = function(v) KB.Kill = v end})
    t2:Keybind({Flag = "GrindKey", Title = "粉碎快捷键", Value = "", Callback = function(v) KB.Grind = v end})
    t2:Keybind({Flag = "BurgerKey", Title = "做汉堡快捷键", Value = "", Callback = function(v) KB.Burger = v end})
    t2:Keybind({Flag = "MoneyKey", Title = "收钱快捷键", Value = "", Callback = function(v) KB.Money = v end})

    local t3 = WN:Tab({Title = "UI设置", Icon = "solar:monitor-bold"})
    t3:Keybind({Flag = "WindowKey", Title = "窗口快捷键", Value = "RightShift", Callback = function(v) KB.Window = v end})
    CT.Particles = t3:Toggle({Flag = "Particles", Title = "粒子背景", Value = true, Callback = function(v)
        S.Particles = v
        if v then task.spawn(function() task.wait(0.3); local WF; for _, c in ipairs(WN.Parent:GetChildren()) do if c:IsA("Frame") and c.AbsoluteSize.X > 400 then WF = c; break end end; if WF then mkP(WF) end end)
        else kP() end
    end})
    CT.Acrylic = t3:Toggle({Flag = "Acrylic", Title = "毛玻璃", Value = true, Callback = function(v) S.Acrylic = v; pcall(function() WI:ToggleAcrylic(v) end) end})
    CT.Transparent = t3:Toggle({Flag = "Transparent", Title = "透明背景", Value = false, Callback = function(v) S.Transparent = v; pcall(function() WN:ToggleTransparency(v) end) end})
    local tns = {"Dark","Light","Rose","Plant","Ocean","Sunset","Midnight","Forest","Lavender","Coral","Mint","Sky","Blood","Lemon","Cyber"}
    CT.Theme = t3:Dropdown({Flag = "Theme", Title = "选择主题", Values = tns, Value = "Dark", Callback = function(v)
        pcall(function() WI:SetTheme(v) end); S.ParticleColor = tc(v)
    end})

    local t4 = WN:Tab({Title = "信息统计", Icon = "solar:chart-bold"})
    local npcP = t4:Paragraph({Title = "👤 NPC: 0"})
    local bodyP = t4:Paragraph({Title = "🦴 尸体: 0"})
    local moneyP = t4:Paragraph({Title = "💰 金钱: 0"})
    local ingP = t4:Paragraph({Title = "🍔 食材站: 0"})

    local t5 = WN:Tab({Title = "配置管理", Icon = "solar:diskette-bold"})
    t5:Input({Flag = "CN", Title = "配置名称", Value = "default", Icon = "solar:file-text-bold", Callback = function(v) end})
    t5:Button({Title = "💾 保存", Icon = "solar:check-circle-bold", Justify = "Center", Color = Color3.fromHex("#305dff"), Callback = function() end})
    t5:Button({Title = "📂 加载", Icon = "solar:refresh-circle-bold", Justify = "Center", Color = Color3.fromHex("#10C550"), Callback = function() end})
    t5:Button({Title = "🗑️ 删除", Icon = "solar:trash-bin-trash-bold", Justify = "Center", Color = Color3.fromHex("#ff3040"), Callback = function() end})

    local t6 = WN:Tab({Title = "关于", Icon = "solar:info-square-bold"})
    t6:Paragraph({Title = "汉堡自动脚本 v2.5.9"})
    t6:Divider()
    t6:Paragraph({Title = "👤 作者", Desc = "b站英吉利超入_"})
    t6:Paragraph({Title = "💡 使用", Desc = IM and "手机:点击悬浮按钮" or "PC: RightShift打开菜单"})
    t6:Paragraph({Title = "🔧 v2.5.9更新", Desc = "默认35m攻击范围\n强化调试:打印模型结构\nPickupItem不限Part类型\nKillConfirm二次验证\n💡超范围提示调滑块"})

    UIS.InputBegan:Connect(function(input, gpe)
        if gpe or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local keyName = input.KeyCode and input.KeyCode.Name or ""
        if keyName == KB.Kill then S.KillNPC = not S.KillNPC; if CT.KillNPC then CT.KillNPC:Set(S.KillNPC) end end
        if keyName == KB.Grind then S.GrindBodies = not S.GrindBodies; if CT.GrindBodies then CT.GrindBodies:Set(S.GrindBodies) end end
        if keyName == KB.Burger then S.MakeBurgers = not S.MakeBurgers; if CT.MakeBurgers then CT.MakeBurgers:Set(S.MakeBurgers) end end
        if keyName == KB.Money then S.CollectMoney = not S.CollectMoney; if CT.MakeBurgers then CT.MakeBurgers:Set(S.MakeBurgers) end end
    end)

    return npcP, bodyP, moneyP, ingP
end

-- ============ 主循环 ============
local PP = false
pcall(function() WI:SetTheme("Dark") end)
S.ParticleColor = tc("Dark")
WI:Popup({
    Title = "🍔 汉堡自动脚本 v2.5.9",
    Content = "默认35m攻击范围\n强化调试输出\nPickupItem不限Part类型\n\n杀NPC | 粉碎 | 做汉堡 | 收钱\n💡 超范围提示直接看到距离",
    Buttons = {{Title = "确认加载", Callback = function() PP = true end, Variant = "Primary"}}
})
while not PP do task.wait(0.1) end

local function mainLoop()
    local npcP, bodyP, moneyP, ingP = makeWindow()
    WI:Notify({
        Title = "🍔 汉堡 v2.5.9",
        Content = "已加载!范围默认35m\n远程:" .. (remotesReady and "✅" : "⚠"),
        Duration = 3, Icon = "solar:bell-bold"
    })
    local last = 0
    while true do
        local now = tick()
        if S.AutoMode then
            doKillNPC(); task.wait(0.3)
            doGrindBody(); task.wait(0.3)
            doMakeBurger(); task.wait(0.3)
            doCollectMoney(); task.wait(1)
        else
            if S.KillNPC then doKillNPC(); task.wait(0.5) end
            if S.GrindBodies then doGrindBody(); task.wait(0.5) end
            if S.MakeBurgers then doMakeBurger(); task.wait(0.5) end
            if S.CollectMoney then doCollectMoney(); task.wait(0.5) end
        end
        doESP()
        if now - last > 3 then
            last = now
            if npcP then pcall(function() npcP:SetTitle("👤 NPC: " .. #getNPCs(100)) end) end
            if bodyP then pcall(function() bodyP:SetTitle("🦴 尸体: " .. #getBodies()) end) end
            if moneyP then pcall(function() moneyP:SetTitle("💰 金钱: " .. #getMoney()) end) end
            if ingP then pcall(function() ingP:SetTitle("🍔 食材站: " .. #getStands()) end) end
        end
        task.wait(2)
    end
end

task.spawn(mainLoop)
