print("[Burger v2.18] loading...")

local P = game:GetService("Players")
local WS = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local CS = game:GetService("CollectionService")
local C = game:GetService("CoreGui")

local LP = P.LocalPlayer
if not LP then return end

local MeleeEvent, PickupEvent, DropEvent
local remotesReady = false
pcall(function()
    MeleeEvent = RS.Network.MeleeHitEvent
    PickupEvent = RS.Remotes.PickupItem
    DropEvent = RS.Remotes.DropItem
end)
if MeleeEvent and PickupEvent and DropEvent then
    remotesReady = true
    print("[v2.18] remotes OK")
else
    warn("[v2.18] remotes MISS")
end

for _, g in ipairs(C:GetChildren()) do
    if g:IsA("ScreenGui") then
        local n = g.Name
        if n == "A" or n:find("Burger") or n == "WindUI" then
            pcall(function() g:Destroy() end)
        end
    end
end

local WI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
if not WI then return end
print("[v2.18] WindUI OK")

local S = {
    KillNPC = false,
    GrindBodies = false,
    CollectMoney = false,
    AutoMode = false,
    EspEnabled = false,
    EspRange = 200,
    KillRange = 50,
    AkillDamage = 26,
    Particles = true,
    Acrylic = true,
    Transparent = false,
    ParticleColor = Color3.fromRGB(80, 170, 255)
}
local KB = { Window = "RightShift" }
local WN, CT = nil, {}
local PR, PS, PC = false, {}, nil

-- Kill aura state
local killTarget = nil
local npcCache = {}
local npcCacheTime = 0

local function mKW(n, l)
    if not n then return false end
    local ln = n:lower()
    for _, k in ipairs(l) do
        if ln:find(k, 1, true) then return true end
    end
    return false
end

local function gT(kw)
    local c = LP.Character
    if c then
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") and mKW(t.Name, kw) then return t end
        end
    end
    local bp = LP:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and mKW(t.Name, kw) then return t end
        end
    end
    return nil
end

local function eq(t)
    if not t then return false end
    local c = LP.Character
    if not c then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h then return false end
    if t.Parent ~= c then
        h:EquipTool(t)
        wait(0.15)
    end
    return true
end

local function isMe(m)
    for _, p in ipairs(P:GetPlayers()) do
        if p.Character == m then return true end
    end
    return false
end

local function gN(range)
    local npcs = {}
    local c = LP.Character
    if not c then return npcs end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return npcs end
    local pos = hrp.Position
    local seen = {}
    local rr = range + 5
    local gf = WS:FindFirstChild("GAMEFOLDERS")
    if gf then
        for _, fn in ipairs({"Customers", "NPCs"}) do
            local f = gf:FindFirstChild(fn)
            if f then
                for _, m in ipairs(f:GetDescendants()) do
                    if m:IsA("Model") and not seen[m] and not isMe(m) then
                        local h = m:FindFirstChildOfClass("Humanoid")
                        local mp = m:FindFirstChild("HumanoidRootPart")
                        if h and mp and h.Health > 0 then
                            local d = (mp.Position - pos).Magnitude
                            if d <= rr then
                                seen[m] = true
                                table.insert(npcs, {M=m, H=h, P=mp, D=d})
                            end
                        end
                    end
                end
            end
        end
    end
    for _, fn in ipairs({"Customers", "NPCs"}) do
        local f = WS:FindFirstChild(fn)
        if f then
            for _, m in ipairs(f:GetDescendants()) do
                if m:IsA("Model") and not seen[m] and not isMe(m) then
                    local h = m:FindFirstChildOfClass("Humanoid")
                    local mp = m:FindFirstChild("HumanoidRootPart")
                    if h and mp and h.Health > 0 then
                        local d = (mp.Position - pos).Magnitude
                        if d <= rr then
                            seen[m] = true
                            table.insert(npcs, {M=m, H=h, P=mp, D=d})
                        end
                    end
                end
            end
        end
    end
    table.sort(npcs, function(a, b) return a.D < b.D end)
    return npcs
end

-- Cached NPC scan (for kill aura high-frequency calls)
local function gNCached(range)
    local now = tick()
    if now - npcCacheTime < 2 and #npcCache > 0 then
        local c = LP.Character
        if not c then return {} end
        local hrp = c:FindFirstChild("HumanoidRootPart")
        if not hrp then return {} end
        local pos = hrp.Position
        local rr = range + 5
        local result = {}
        for _, t in ipairs(npcCache) do
            if t.P and (t.P.Position - pos).Magnitude <= rr then
                table.insert(result, t)
            end
        end
        return result
    end
    npcCache = gN(range)
    npcCacheTime = now
    return npcCache
end

local BK = {"customer","cop","civilian","police","officer","guard","worker","chef","noob","gun","medic","armor","oil","gunslinger","normal","poor","rich","slinger"}
local NBK = {"onion","tomato","bun","patty","cheese","lettuce","plate","meat","ingredient","food","bread","sauce","stand","grill","box","table","chair","door","wall","floor","bill","cash","money","coin"}

local function iC(body)
    local n = body.Name:lower()
    for _, k in ipairs(BK) do if n:find(k, 1, true) then return true end end
    for _, k in ipairs(NBK) do if n:find(k, 1, true) then return false end end
    return n:find("body", 1, true) or n:find("corpse", 1, true) or n:find("dead", 1, true)
end

local function gB()
    local b = {}
    for _, obj in ipairs(CS:GetTagged("Pickable")) do
        if obj:IsA("Model") and iC(obj) then table.insert(b, obj) end
    end
    return b
end

local function gM()
    local bills = {}
    local items = WS:FindFirstChild("ITEMS")
    if items then
        for _, obj in ipairs(items:GetDescendants()) do
            local pp = obj:FindFirstChildOfClass("ProximityPrompt")
            if pp then table.insert(bills, {M=obj, P=pp}) end
            if obj:IsA("BasePart") and mKW(obj.Name, {"cash","money","bill","coin"}) then
                if not pp then table.insert(bills, {T=obj}) end
            end
        end
    end
    return bills
end

local function fP(name)
    local wp = WS:FindFirstChild("WORLDPARTS")
    if not wp then return nil end
    for _, obj in ipairs(wp:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name == name then return obj end
    end
    return nil
end

local function gPP(model)
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

local function fHP(model)
    if not model then return nil end
    if not model:IsA("Model") then return nil end
    local hh = model:FindFirstChild("HeadHitbox", true)
    if hh and hh:IsA("BasePart") then return hh end
    for _, n in ipairs({"Head","UpperTorso","Torso","LowerTorso"}) do
        local p = model:FindFirstChild(n, true)
        if p and p:IsA("BasePart") then return p end
    end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then return d end
    end
    return nil
end

local NF = Vector3.new(0, 0, 1)

-- === KILL AURA (v2.18) ===
-- No teleport. Lock nearest target, spam FireServer until dead.
local function dK()
    -- Validate current target
    if killTarget then
        local c = LP.Character
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        local h = killTarget.M:FindFirstChildOfClass("Humanoid")
        local inRange = hrp and killTarget.P and
            (killTarget.P.Position - hrp.Position).Magnitude <= S.KillRange + 10
        if not h or h.Health <= 0 or not inRange then
            killTarget = nil
        end
    end

    -- Pick new target
    if not killTarget then
        local npcs = gNCached(S.KillRange)
        if #npcs == 0 then return end
        killTarget = npcs[1]
        print("[Aura] locked: " .. killTarget.M.Name .. " @" .. math.floor(killTarget.D) .. "m")
    end

    -- Equip weapon
    local tool = gT({"spatula","shovel","knife","sword","bat","hammer","axe","weapon","cleaver"})
    if not tool then
        killTarget = nil
        return
    end
    eq(tool)

    -- Hit part (prefer HeadHitbox)
    local hp = fHP(killTarget.M)
    if not hp then hp = killTarget.P end

    -- Burst: 3 hits per cycle
    local hits = 0
    for i = 1, 3 do
        local hNow = killTarget.M:FindFirstChildOfClass("Humanoid")
        if not hNow or hNow.Health <= 0 then
            print("[Aura] " .. killTarget.M.Name .. " DEAD (" .. hits .. " hits)")
            killTarget = nil
            break
        end
        if remotesReady and MeleeEvent then
            MeleeEvent:FireServer(hp, hp.Position, NF, S.AkillDamage)
            hits = hits + 1
        end
        wait(0.06)
    end
end

-- === GRIND (v2.17: PickupItem/DropItem with error print) ===
local function dG()
    local grinder = fP("Grinder")
    if not grinder then return end
    local bodies = gB()
    if #bodies == 0 then return end
    local body = bodies[1]
    local c = LP.Character
    if not c then return end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    print("[Grind] " .. body.Name)
    if remotesReady and PickupEvent and DropEvent then
        local bp = gPP(body)
        if bp then
            hrp.CFrame = bp.CFrame * CFrame.new(0, 0, 2)
            wait(0.2)
        end
        local ok1, err1 = pcall(function() PickupEvent:FireServer(body) end)
        if ok1 then
            print("[Grind] Pickup OK")
        else
            print("[Grind] Pickup ERR:" .. tostring(err1))
            return
        end
        wait(0.5)
        hrp.CFrame = grinder.CFrame * CFrame.new(0, 0, 2.5)
        wait(0.3)
        local ok2, err2 = pcall(function() DropEvent:FireServer(body, grinder.Position) end)
        if ok2 then
            print("[Grind] Drop OK")
        else
            print("[Grind] Drop ERR:" .. tostring(err2))
        end
    end
end

-- === COLLECT MONEY ===
local function dC()
    local c = LP.Character
    if not c then return end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local bills = gM()
    if #bills == 0 then return end
    local n = 0
    for _, b in ipairs(bills) do
        if b.P then
            local target = nil
            if b.M:IsA("BasePart") then target = b.M
            elseif b.M:IsA("Model") then
                for _, d in ipairs(b.M:GetDescendants()) do
                    if d:IsA("BasePart") then target = d; break end
                end
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
end

-- === PARTICLES ===
local function sP()
    if PR then return end
    if PC then pcall(function() local p = PC.Parent if p then p:Destroy() end end) PC = nil end
    PS = {}
    wait(0.3)
    local sg = Instance.new("ScreenGui")
    sg.Name = "BP"; sg.ResetOnSpawn = false; sg.DisplayOrder = 999999
    sg.IgnoreGuiInset = true; sg.Parent = C
    PC = Instance.new("Frame")
    PC.Size = UDim2.new(1,0,1,0); PC.BackgroundTransparency = 1
    PC.BorderSizePixel = 0; PC.Active = false; PC.Parent = sg
    local col = S.ParticleColor
    for i = 1, 50 do
        local d = Instance.new("Frame")
        local sz = math.random(5,10)
        d.Size = UDim2.new(0,sz,0,sz)
        local sx = 0.2 + math.random() * 0.6
        local sy = 0.2 + math.random() * 0.6
        d.Position = UDim2.new(sx,0,sy,0)
        d.BackgroundColor3 = col
        d.BackgroundTransparency = 0.3 + math.random() * 0.5
        d.BorderSizePixel = 0; d.Parent = PC
        Instance.new("UICorner", d).CornerRadius = UDim.new(0,10)
        local a = math.random() * 6.28
        local sp = 0.0008 + math.random() * 0.002
        table.insert(PS, {F=d, Sx=sx, Sy=sy, Vx=math.cos(a)*sp, Vy=math.sin(a)*sp, Ph=math.random()*6.28, Sz=sz})
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
                        p.F.Position = UDim2.new(sx,0,sy,0)
                        if curCol ~= p.F.BackgroundColor3 then p.F.BackgroundColor3 = curCol end
                        p.F.BackgroundTransparency = 0.3 + math.sin(t*0.8+p.Ph)*0.4
                        local bs = math.max(2, p.Sz + math.sin(t+p.Ph)*1.5)
                        p.F.Size = UDim2.new(0,bs,0,bs)
                    end
                end
            end)
            wait(0.03)
        end
    end)
end

local function xP()
    PR = false
    if PC then pcall(function() local p = PC.Parent if p then p:Destroy() end end) PC = nil end
    PS = {}
end

-- === ESP ===
local EO = {}
local function mE(t)
    if EO[t] then return end
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0,200,0,50); bb.MaxDistance = S.EspRange
    bb.AlwaysOnTop = true; bb.StudsOffset = Vector3.new(0,4,0)
    pcall(function() bb.Parent = t end)
    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.new(1,0,1,0); tl.Text = "NPC"
    tl.TextColor3 = Color3.fromRGB(255,40,40)
    tl.BackgroundTransparency = 0.7; tl.BackgroundColor3 = Color3.new(0,0,0)
    tl.TextScaled = true; tl.Font = Enum.Font.SourceSansBold; tl.Parent = bb
    local hl = Instance.new("Highlight")
    hl.FillColor = Color3.fromRGB(255,40,40); hl.OutlineColor = Color3.fromRGB(255,255,255)
    hl.FillTransparency = 0.3; hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    pcall(function() hl.Parent = t end)
    EO[t] = {B=bb, H=hl}
end
local function cE(t)
    local e = EO[t]
    if e then pcall(function() e.B:Destroy() end) pcall(function() e.H:Destroy() end) EO[t] = nil end
end
local function cA() for t,_ in pairs(EO) do cE(t) end EO = {} end
local function dE()
    if not S.EspEnabled then return end
    local c = LP.Character
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    local pos = hrp and hrp.Position
    for _, obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("Humanoid") and obj.Parent and obj.Parent:IsA("Model") then
            local m = obj.Parent
            if not isMe(m) then
                local mp = m:FindFirstChild("HumanoidRootPart")
                local d = pos and mp and (mp.Position-pos).Magnitude or 999
                if d > S.EspRange then cE(m)
                elseif d <= S.EspRange and obj.Health > 0 then mE(m) end
            end
        end
    end
end

local function tc(n)
    local t = {Dark=Color3.fromRGB(80,170,255),Light=Color3.fromRGB(60,130,210),Rose=Color3.fromRGB(255,130,170),Plant=Color3.fromRGB(70,210,130),Ocean=Color3.fromRGB(60,190,240),Sunset=Color3.fromRGB(255,160,70),Midnight=Color3.fromRGB(130,100,240),Forest=Color3.fromRGB(60,180,90),Lavender=Color3.fromRGB(190,140,255),Coral=Color3.fromRGB(255,140,90),Mint=Color3.fromRGB(80,230,190),Sky=Color3.fromRGB(100,190,255),Blood=Color3.fromRGB(230,90,80),Lemon=Color3.fromRGB(230,210,70),Cyber=Color3.fromRGB(0,235,210)}
    return t[n] or Color3.fromRGB(80,170,255)
end

-- === UI ===
local function mW()
    WN = WI:CreateWindow({
        Title = "Burger", Author = "bilibili", Icon = "solar:hamburger-bold",
        Size = UDim2.fromOffset(750,520), ToggleKey = Enum.KeyCode.RightShift,
        Folder = "burger-script", Acrylic = true, Resizable = false,
        ScrollBarEnabled = true, HideSearchBar = true,
        OnClose = function()
            xP() S.KillNPC=false S.GrindBodies=false S.CollectMoney=false
            S.AutoMode=false S.EspEnabled=false cA() killTarget=nil
            for _, ct in pairs(CT) do
                if ct and type(ct.Set) == "function" then pcall(function() ct:Set(false) end) end
            end
        end,
        OnOpen = function() if S.Particles then sP() end end
    })
    spawn(function() wait(0.8) pcall(function() if WN and WN.Parent then WN.Parent.ClipsDescendants = true end end) end)
    spawn(function() wait(0.5) pcall(function() WN:SetToggleKey(Enum.KeyCode.RightShift) end) end)

    local t1 = WN:Tab({Title="Main", Icon="solar:slider-vertical-bold"})
    CT.KillNPC = t1:Toggle({Flag="KillNPC", Title="Kill Aura (no tp)", Value=false, Callback=function(v) print("[Toggle] KillNPC="..tostring(v)) S.KillNPC=v if not v then killTarget=nil end end})
    CT.GrindBodies = t1:Toggle({Flag="GrindBodies", Title="Auto Grind", Value=false, Callback=function(v) S.GrindBodies=v end})
    CT.CollectMoney = t1:Toggle({Flag="CollectMoney", Title="Auto Collect Money", Value=false, Callback=function(v) S.CollectMoney=v end})
    CT.AutoMode = t1:Toggle({Flag="AutoMode", Title="Full Auto", Value=false, Callback=function(v) S.AutoMode=v end})
    t1:Divider()
    CT.Esp = t1:Toggle({Flag="EspEnabled", Title="NPC ESP", Value=false, Callback=function(v) S.EspEnabled=v if not v then cA() end end})
    t1:Divider()
    CT.KillRange = t1:Slider({Flag="KillRange", Title="Aura Range", Step=5, Value={Min=5,Max=200,Default=50}, Width=200, IsTextbox=true, Callback=function(v) S.KillRange=v end})

    local t2 = WN:Tab({Title="Keys", Icon="solar:settings-bold"})
    t2:Keybind({Flag="KillKey", Title="Kill Key", Value="", Callback=function(v) KB.Kill=v end})
    t2:Keybind({Flag="GrindKey", Title="Grind Key", Value="", Callback=function(v) KB.Grind=v end})
    t2:Keybind({Flag="MoneyKey", Title="Money Key", Value="", Callback=function(v) KB.Money=v end})

    local t3 = WN:Tab({Title="UI", Icon="solar:monitor-bold"})
    t3:Keybind({Flag="WindowKey", Title="Toggle Key", Value="RightShift", Callback=function(v) KB.Window=v end})
    t3:Divider()
    CT.Particles = t3:Toggle({Flag="Particles", Title="Particles", Value=true, Callback=function(v) S.Particles=v if v then sP() else xP() end end})
    t3:Toggle({Flag="Acrylic", Title="Acrylic", Value=true, Callback=function(v) S.Acrylic=v pcall(function() WI:ToggleAcrylic(v) end) end})
    t3:Toggle({Flag="Transparent", Title="Transparent", Value=false, Callback=function(v) S.Transparent=v pcall(function() WN:ToggleTransparency(v) end) end})
    local tns = {"Dark","Light","Rose","Plant","Ocean","Sunset","Midnight","Forest","Lavender","Coral","Mint","Sky","Blood","Lemon","Cyber"}
    t3:Dropdown({Flag="Theme", Title="Theme", Values=tns, Value="Dark", Callback=function(v) pcall(function() WI:SetTheme(v) end) S.ParticleColor=tc(v) end})

    local t4 = WN:Tab({Title="Stats", Icon="solar:chart-bold"})
    local npcP = t4:Paragraph({Title="NPC:0"})
    local bodyP = t4:Paragraph({Title="Bodies:0"})
    local moneyP = t4:Paragraph({Title="Money:0"})

    local t5 = WN:Tab({Title="Config", Icon="solar:diskette-bold"})
    pcall(function()
        local CM = WN.ConfigManager
        if not CM then return end
        local cni = t5:Input({Flag="CN", Title="Config Name", Value="default", Icon="solar:file-text-bold", Callback=function(v) end})
        t5:Space()
        local AC = {} pcall(function() AC = CM:AllConfigs() end)
        local DV = nil pcall(function() for _,v in ipairs(AC) do if v=="default" then DV="default" break end end end)
        local ACD = t5:Dropdown({Title="Saved", Values=AC, Value=DV, Callback=function(v) if v then pcall(function() cni:Set(v) end) end end})
        t5:Space()
        t5:Button({Title="Save", Icon="solar:check-circle-bold", Justify="Center", Color=Color3.fromHex("#305dff"), Callback=function() if not CM then return end local c=CM:Config("default") if c and c:Save() then WI:Notify({Title="Saved",Content="OK",Duration=3,Icon="solar:check-circle-bold"}) pcall(function() ACD:Refresh(CM:AllConfigs()) end) end end})
        t5:Space()
        t5:Button({Title="Load", Icon="solar:refresh-circle-bold", Justify="Center", Color=Color3.fromHex("#10C550"), Callback=function() if not CM then return end local c=CM:CreateConfig("default",false) if c and c:Load() then WI:Notify({Title="Loaded",Content="OK",Duration=3,Icon="solar:refresh-circle-bold"}) end end})
        t5:Space()
        t5:Button({Title="Delete", Icon="solar:trash-bin-trash-bold", Justify="Center", Color=Color3.fromHex("#ff3040"), Callback=function() if not CM then return end local c=CM:Config("default") if c and c:Delete() then WI:Notify({Title="Deleted",Content="OK",Duration=3,Icon="solar:trash-bin-trash-bold"}) pcall(function() ACD:Refresh(CM:AllConfigs()) end) end end})
        spawn(function() wait(1) pcall(function() CM:CreateConfig("default",true) end) end)
    end)

    local t6 = WN:Tab({Title="About", Icon="solar:info-square-bold"})
    t6:Paragraph({Title="Burger Script v2.18"})
    t6:Divider()
    t6:Paragraph({Title="Author", Desc="bilibili"})
    t6:Paragraph({Title="v2.18", Desc="Kill Aura - no tp, locks target until dead"})

    UIS.InputBegan:Connect(function(input, gpe)
        if gpe or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local kn = input.KeyCode and input.KeyCode.Name or ""
        if kn==KB.Kill then S.KillNPC=not S.KillNPC if CT.KillNPC then CT.KillNPC:Set(S.KillNPC) end if not S.KillNPC then killTarget=nil end end
        if kn==KB.Grind then S.GrindBodies=not S.GrindBodies if CT.GrindBodies then CT.GrindBodies:Set(S.GrindBodies) end end
        if kn==KB.Money then S.CollectMoney=not S.CollectMoney if CT.CollectMoney then CT.CollectMoney:Set(S.CollectMoney) end end
    end)
    return npcP, bodyP, moneyP
end

-- === MAIN LOOP (fast cycle for kill aura) ===
local PP = false
pcall(function() WI:SetTheme("Dark") end)
S.ParticleColor = tc("Dark")
WI:Popup({
    Title = "Burger v2.18",
    Content = "Kill Aura: no teleport, locks target until dead",
    Buttons = {{Title="Load", Callback=function() PP=true end, Variant="Primary"}}
})
while not PP do wait(0.1) end

spawn(function()
    local npcP, bodyP, moneyP = mW()
    print("[v2.18] loop start")
    local last = 0
    while true do
        if S.AutoMode then
            pcall(function() dK() end)
            wait(0.2)
            pcall(function() dG() end)
            wait(0.2)
            pcall(function() dC() end)
            wait(0.3)
        else
            if S.KillNPC then
                pcall(function() dK() end)
                wait(0.2)
            end
            if S.GrindBodies then
                pcall(function() dG() end)
                wait(0.2)
            end
            if S.CollectMoney then
                pcall(function() dC() end)
                wait(0.5)
            end
        end
        pcall(function() dE() end)
        local now = tick()
        if now - last > 3 then
            last = now
            -- Force refresh cache for stats
            npcCacheTime = 0
            if npcP then pcall(function() npcP:SetTitle("NPC:"..#gN(100)) end) end
            if bodyP then pcall(function() bodyP:SetTitle("Bodies:"..#gB()) end) end
            if moneyP then pcall(function() moneyP:SetTitle("Money:"..#gM()) end) end
        end
        wait(0.3)
    end
end)
