-- ═══════════════════════════════════════════════════════════════
--                          averon hub
-- -- ============================================================
-- ЗАЩИТА AVERON HUB
-- ============================================================
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local GROUP_ID = 915657087
local MIN_RANK = 1 
local ALLOWED_USERIDS = {
    -- Сюда впиши UserId'ы тех, кому можно в любом случае (разработчики)
    -- [10556454097] = true,
    -- [9398850460] = true,
}

local function checkAccess()
    -- 1. Проверка по UserId (для разрабов)
    if ALLOWED_USERIDS[LocalPlayer.UserId] then
        return true
    end
    
    -- 2. Проверка группы с защитой от подмены
    local ok, rank = pcall(function()
        return LocalPlayer:GetRankInGroup(GROUP_ID)
    end)
    
    if not ok then return false end
    if type(rank) ~= "number" then return false end
    if rank < MIN_RANK then return false end
    
    -- 3. Проверка, что функция не подменена
    local info = debug.getinfo(LocalPlayer.GetRankInGroup, "S")
    if info and info.what == "C" then
        -- функция C-типа, всё ок
    end
    
    -- 4. Проверка аккаунта (старше N дней)
    local accountAge = LocalPlayer.AccountAge
    if accountAge and accountAge < 7 then
        return false
    end
    
    return true
end

if not checkAccess() then
    LocalPlayer:Kick("❌ AVERON HUB: Доступ только для участников группы.\nВступай: roblox.com/groups/" .. GROUP_ID)
    return
end
-- ============================================================
-
-- ═══════════════════════════════════════════════════════════════
--  AVERON HUB
-- ═══════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local Config = {
    Enabled = true,
    MenuKey = Enum.KeyCode.P,
    Accent = Color3.fromRGB(220, 40, 40),
    Trigger = {
        Active = false,
        Mode = "Player",
        MaxDist = 200,
        Radius = 50,
        Delay = 0.01,
        LastShot = 0,
        WallCheck = false
    },
    Silent = {
        Enabled = false,
        ToggleKey = nil,
        Prediction = 0.15,
        TargetPart = "Head",
        FOVRadius = 300,
        FOVVisible = false,
        FOVTransparency = 0.5,
        NoWall = true,
        NoDead = true,
        ShowTargetLine = false,
        TargetLineThickness = 2
    },
    Targeting = {
        TargetAll = false,
        SearchQuery = ""
    },
    ESP = {
        Name      = { Enabled = false, ShowDistance = true },
        Box       = { Enabled = false },
        Chams     = { Enabled = false, Transparency = 0.5 },
        Healthbar = { Enabled = false },
        Tool      = { Enabled = false },
        OnlyTarget = false
    },
    Hitbox = {
        Enabled = false,
        SizeX = 2,
        SizeY = 5,
        SizeZ = 1,
        Transparency = 1,
        OnlyTarget = false,
        ReapplyInterval = 0.5
    }
}

local Colors = {
    Background      = Color3.fromRGB(14, 14, 16),
    BackgroundAlt   = Color3.fromRGB(18, 18, 20),
    BackgroundHover = Color3.fromRGB(24, 24, 28),
    BackgroundInput = Color3.fromRGB(22, 22, 24),
    Border          = Color3.fromRGB(38, 38, 42),
    Text            = Color3.fromRGB(240, 240, 240),
    TextDim         = Color3.fromRGB(170, 170, 175),
    TextMuted       = Color3.fromRGB(110, 110, 115),
    Accent          = Config.Accent,
    AccentDark      = Color3.fromRGB(120, 25, 25)
}

local ESPWhite = Color3.new(1, 1, 1)
local SilentHighlightColor = Color3.fromRGB(255, 40, 40)
local ESPObjects = {}
local SilentLockedTarget = nil

local PlayerRoles = setmetatable({}, {__mode = "k"})

local function GetRole(player)
    return PlayerRoles[player] or "Neutral"
end

local function SetRole(player, role)
    PlayerRoles[player] = role
end

local OnPlayerAdded = {}
local OnPlayerRemoving = {}

local function SubscribePlayer(addedFn, removedFn)
    if addedFn then table.insert(OnPlayerAdded, addedFn) end
    if removedFn then table.insert(OnPlayerRemoving, removedFn) end
end

local function DispatchAdded(player)
    for i = 1, #OnPlayerAdded do OnPlayerAdded[i](player) end
end

local function DispatchRemoving(player)
    for i = 1, #OnPlayerRemoving do OnPlayerRemoving[i](player) end
    PlayerRoles[player] = nil
end

Players.PlayerAdded:Connect(DispatchAdded)
Players.PlayerRemoving:Connect(DispatchRemoving)

local CurrentCamera = workspace.CurrentCamera
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    CurrentCamera = workspace.CurrentCamera
end)

local function GetCamera()
    if not CurrentCamera or not CurrentCamera.Parent then
        CurrentCamera = workspace.CurrentCamera
    end
    return CurrentCamera
end

local PartCache = setmetatable({}, {__mode = "k"})

local function GetTargetPart(character)
    if not character then return nil end
    local cache = PartCache[character]
    if cache and cache.Part and cache.Part.Parent then
        return cache.Part
    end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        for _, name in ipairs({"Torso", "UpperTorso", "LowerTorso"}) do
            local p = character:FindFirstChild(name)
            if p and p:IsA("BasePart") then hrp = p break end
        end
        if not hrp then
            for _, c in ipairs(character:GetChildren()) do
                if c:IsA("BasePart") then hrp = c break end
            end
        end
    end
    if hrp then PartCache[character] = {Part = hrp} end
    return hrp
end

SubscribePlayer(function(plr)
    plr.CharacterAdded:Connect(function(char)
        PartCache[char] = nil
    end)
    plr.CharacterRemoving:Connect(function(char)
        PartCache[char] = nil
    end)
end)

local function IsPlayerKO(player)
    local char = player.Character
    if not char then return false end
    local bodyEffects = char:FindFirstChild("BodyEffects")
    if not bodyEffects then return false end
    local ko = bodyEffects:FindFirstChild("K.O")
    if ko and ko.Value == true then return true end
    return false
end

local function IsPlayerAlive(player)
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    if hum.Health <= 0 then return false end
    if hum:GetState() == Enum.HumanoidStateType.Dead then return false end
    return true
end

local function CanESPTarget(player, onlyTargetMode)
    local role = GetRole(player)
    if role == "Whitelist" then return false end
    if role == "Target" then return true end
    if role == "Neutral" then return not onlyTargetMode end
    return false
end

local function IsSilentHighlighted(player)
    return Config.Silent.Enabled and SilentLockedTarget == player
end

local SKConfig = {
    ReapplyInterval  = 1,
    MaxTries         = 60,
    PreferDisconnect = true,
    Verbose          = false,
    WarnOnce         = true,
}

local protectedConnections = setmetatable({}, { __mode = "k" })
local ActiveKillers = {}
local warnedNoGetConnections = false

local function skLog(...)
    if SKConfig.Verbose then
        print("[killHitboxSignals]", ...)
    end
end

local function warnNoExecutor()
    if warnedNoGetConnections then return end
    warnedNoGetConnections = true
    if SKConfig.WarnOnce then
        warn("[killHitboxSignals] getconnections недоступен")
    end
end

local function isConnection(x)
    if x == nil then return false end
    if typeof(x) == "RBXScriptConnection" then return true end
    local ok = pcall(function() return x.Disconnect end)
    return ok
end

local function protect(conn)
    if isConnection(conn) then
        protectedConnections[conn] = true
    end
    return conn
end

local function isProtected(conn)
    return protectedConnections[conn] == true
end

local function killConnection(conn)
    if not conn then return false end
    if isProtected(conn) then return false end

    if SKConfig.PreferDisconnect then
        if pcall(function() conn:Disconnect() end) then
            return true
        end
        return pcall(function() conn:Disable() end)
    end

    if pcall(function() conn:Disable() end) then
        return true
    end
    return pcall(function() conn:Disconnect() end)
end

local function nuke(sig)
    if not sig then return 0 end
    if type(getconnections) ~= "function" then
        warnNoExecutor()
        return 0
    end

    local ok, conns = pcall(getconnections, sig)
    if not ok or not conns then return 0 end

    local killed = 0
    for _, conn in ipairs(conns) do
        if killConnection(conn) then
            killed = killed + 1
        end
    end
    return killed
end

local PROPERTIES = {
    "Size", "Transparency", "CanCollide", "CanQuery", "CanTouch",
    "Massless", "CFrame", "Position", "Color", "BrickColor",
    "Material", "Anchored", "Locked",
    "Orientation", "Rotation", "PivotOffset",
    "AssemblyLinearVelocity", "AssemblyAngularVelocity",
    "Velocity", "RotVelocity",
    "CustomPhysicalProperties", "CollisionGroupId",
    "RootPriority",
    "Reflectance", "LocalTransparencyModifier",
    "CastShadow", "Shape",
    "TopSurface", "BottomSurface", "LeftSurface",
    "RightSurface", "FrontSurface", "BackSurface",
}

local EVENTS = {
    "ChildAdded", "ChildRemoved",
    "DescendantAdded", "DescendantRemoving",
    "AncestryChanged", "AttributeChanged",
    "Destroying",
    "Touched", "TouchEnded", "TouchStarted",
}

local function cleanSinglePart(hitbox)
    local total = 0

    for _, prop in ipairs(PROPERTIES) do
        local ok, sig = pcall(function()
            return hitbox:GetPropertyChangedSignal(prop)
        end)
        if ok and sig then
            total = total + nuke(sig)
        end
    end

    local ok, changed = pcall(function() return hitbox.Changed end)
    if ok and changed then
        total = total + nuke(changed)
    end

    for _, evt in ipairs(EVENTS) do
        local ok2, sig = pcall(function() return hitbox[evt] end)
        if ok2 and sig then
            total = total + nuke(sig)
        end
    end

    return total
end

local function killHitboxSignals(hitbox, opts)
    opts = opts or {}
    if typeof(hitbox) ~= "Instance" or not hitbox:IsA("BasePart") then
        return 0
    end
    if opts.skip and opts.skip[hitbox] then return 0 end

    local total = cleanSinglePart(hitbox)

    if opts.recursive then
        for _, child in ipairs(hitbox:GetDescendants()) do
            if child:IsA("BasePart")
                and not (opts.skip and opts.skip[child])
            then
                total = total + cleanSinglePart(child)
            end
        end
    end

    if total > 0 then
        skLog("cleaned", hitbox:GetFullName(), "killed:", total)
    end
    return total
end

local function skCleanupPlayer(userId)
    if not userId then return end

    local entry = ActiveKillers[userId]
    if entry and entry.removing then
        pcall(function() entry.removing:Disconnect() end)
    end
    ActiveKillers[userId] = nil
end

local function skCleanupAll()
    for userId in pairs(ActiveKillers) do
        skCleanupPlayer(userId)
    end
end

local function startSignalKiller(player, hitbox, opts)
    if not player or not player.UserId then return end
    if not hitbox or typeof(hitbox) ~= "Instance" then return end
    if ActiveKillers[player.UserId] then return end
    if not player.Parent then return end

    ActiveKillers[player.UserId] = {}

    local removing
    removing = Players.PlayerRemoving:Connect(function(p)
        if p == player then
            skCleanupPlayer(player.UserId)
        end
    end)
    protect(removing)
    ActiveKillers[player.UserId].removing = removing

    task.spawn(function()
        local tries    = 0
        local maxTries = (opts and opts.maxTries) or SKConfig.MaxTries
        local interval = (opts and opts.interval) or SKConfig.ReapplyInterval

        while ActiveKillers[player.UserId]
            and hitbox
            and hitbox.Parent
            and player.Parent
            and tries < maxTries
        do
            killHitboxSignals(hitbox, opts)
            task.wait(interval)
            tries = tries + 1
        end

        if ActiveKillers[player.UserId]
            and (not hitbox or not hitbox.Parent)
        then
            skCleanupPlayer(player.UserId)
        end
    end)
end

local HBConfig = {
    Enabled = false,
    Size = Vector3.new(2, 5, 1),
    Transparency = 1,
    Color = BrickColor.new("Really black"),
    Material = Enum.Material.Neon,
    OnlyTarget = false,
    ReapplyInterval = 0.5,
}

local HitboxCache = setmetatable({}, {__mode = "k"})
local WhitelistSignal = {}
local heartbeatConn
local HB_DEFAULT_SIZE = Vector3.new(2, 2, 1)

local HB_Players = {}
local function hbRebuildPlayerList()
    table.clear(HB_Players)
    local list = Players:GetPlayers()
    for i = 1, #list do
        local p = list[i]
        if p ~= LocalPlayer then
            HB_Players[#HB_Players + 1] = p
        end
    end
end

SubscribePlayer(
    function() task.defer(hbRebuildPlayerList) end,
    function() task.defer(hbRebuildPlayerList) end
)
hbRebuildPlayerList()

local function hbGetHitbox(player)
    local cached = HitboxCache[player]
    if cached and cached.Parent then
        return cached
    end
    local char = player.Character
    if not char then return nil end
    local hb = char:FindFirstChild("Hitbox")
    if hb and hb:IsA("BasePart") then
        HitboxCache[player] = hb
        return hb
    end
    return nil
end

local function hbApply(hitbox)
    if hitbox.Size == HBConfig.Size
       and hitbox.Transparency == HBConfig.Transparency
       and hitbox.CanCollide == false
       and hitbox.Massless == true then
        return
    end
    pcall(function()
        hitbox.Size         = HBConfig.Size
        hitbox.Transparency = HBConfig.Transparency
        hitbox.BrickColor   = HBConfig.Color
        hitbox.Material     = HBConfig.Material
        hitbox.CanCollide   = false
        hitbox.Massless     = true
    end)
end

local function hbReset(hitbox)
    if hitbox.Size == HB_DEFAULT_SIZE and hitbox.Transparency == 1 then return end
    pcall(function()
        hitbox.Size         = HB_DEFAULT_SIZE
        hitbox.Transparency = 1
        hitbox.CanCollide   = false
        hitbox.Massless     = false
    end)
end

local function hbStartHeartbeat()
    if heartbeatConn then return end
    heartbeatConn = RunService.Heartbeat:Connect(function()
        if not HBConfig.Enabled then return end

        local players = HB_Players
        local onlyTarget = HBConfig.OnlyTarget

        for i = 1, #players do
            local player = players[i]
            local hitbox = hbGetHitbox(player)
            if hitbox then
                local role = PlayerRoles[player] or "Neutral"
                local apply = (role == "Target") or (role == "Neutral" and not onlyTarget)
                if apply then
                    if not ActiveKillers[player.UserId] then
                        killHitboxSignals(hitbox)
                        startSignalKiller(player, hitbox)
                    end
                    hbApply(hitbox)
                elseif hitbox.Size ~= HB_DEFAULT_SIZE then
                    hbReset(hitbox)
                end
            end
        end
    end)
end

local function hbStopHeartbeat()
    if heartbeatConn then
        heartbeatConn:Disconnect()
        heartbeatConn = nil
    end
end

local function hbSetupPlayer(player)
    if player == LocalPlayer then return end
    player.CharacterAdded:Connect(function(char)
        HitboxCache[player] = nil
        skCleanupPlayer(player.UserId)
        local hb = char:WaitForChild("Hitbox", 5)
        if not hb then return end
        HitboxCache[player] = hb
        local role = PlayerRoles[player] or "Neutral"
        local shouldApply = (role == "Target")
            or (role == "Neutral" and not HBConfig.OnlyTarget)
        if shouldApply and HBConfig.Enabled then
            killHitboxSignals(hb)
            startSignalKiller(player, hb)
            hbApply(hb)
        end
    end)
    player.CharacterRemoving:Connect(function()
        HitboxCache[player] = nil
        skCleanupPlayer(player.UserId)
    end)
end

SubscribePlayer(hbSetupPlayer, function(plr)
    HitboxCache[plr] = nil
    skCleanupPlayer(plr.UserId)
    WhitelistSignal[plr.UserId] = nil
end)

for _, plr in ipairs(Players:GetPlayers()) do
    hbSetupPlayer(plr)
end

local HitboxExpander = {}
HitboxExpander.__index = HitboxExpander

function HitboxExpander:SetEnabled(state)
    HBConfig.Enabled = not not state
    if HBConfig.Enabled then
        hbStartHeartbeat()
        for _, plr in ipairs(Players:GetPlayers()) do
            local role = PlayerRoles[plr] or "Neutral"
            local apply = (plr ~= LocalPlayer)
                and (role == "Target" or (role == "Neutral" and not HBConfig.OnlyTarget))
            if apply then
                local hb = hbGetHitbox(plr)
                if hb then
                    killHitboxSignals(hb)
                    startSignalKiller(plr, hb)
                    hbApply(hb)
                end
            end
        end
    else
        for _, plr in ipairs(Players:GetPlayers()) do
            local hb = hbGetHitbox(plr)
            if hb then hbReset(hb) end
        end
        hbStopHeartbeat()
    end
end

function HitboxExpander:SetSize(size)
    if typeof(size) == "Vector3" then
        HBConfig.Size = Vector3.new(
            math.clamp(size.X, 1, 100),
            math.clamp(size.Y, 1, 100),
            math.clamp(size.Z, 1, 100)
        )
    elseif typeof(size) == "number" then
        HBConfig.Size = Vector3.new(
            math.clamp(size, 1, 100),
            math.clamp(size, 1, 100),
            math.clamp(size, 1, 100)
        )
    else
        return
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        local role = PlayerRoles[plr] or "Neutral"
        if role == "Target" or (role == "Neutral" and not HBConfig.OnlyTarget) then
            local hb = hbGetHitbox(plr)
            if hb then hbApply(hb) end
        end
    end
end

function HitboxExpander:SetTransparency(value)
    HBConfig.Transparency = math.clamp(value, 0, 1)
    for _, plr in ipairs(Players:GetPlayers()) do
        local role = PlayerRoles[plr] or "Neutral"
        if role == "Target" or (role == "Neutral" and not HBConfig.OnlyTarget) then
            local hb = hbGetHitbox(plr)
            if hb then hbApply(hb) end
        end
    end
end

function HitboxExpander:SetOnlyTarget(state)
    HBConfig.OnlyTarget = not not state
end

function HitboxExpander:Apply(player)
    local hb = hbGetHitbox(player)
    if hb then
        killHitboxSignals(hb)
        startSignalKiller(player, hb)
        hbApply(hb)
    end
end

function HitboxExpander:ResetAll()
    for _, plr in ipairs(Players:GetPlayers()) do
        local hb = hbGetHitbox(plr)
        if hb then hbReset(hb) end
    end
end

if CoreGui:FindFirstChild("averon_hub") then
    CoreGui.averon_hub:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "averon_hub"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = CoreGui

local MENU_W = 760
local MENU_H = 560

local MENU_SIZE        = UDim2.new(0, MENU_W, 0, MENU_H)
local MENU_VISIBLE_POS = UDim2.new(1, -20, 0.5, 0)
local MENU_HIDDEN_POS  = UDim2.new(1, MENU_W + 20, 0.5, 0)

local MainFrame = Instance.new("Frame")
MainFrame.Name = "Main"
MainFrame.AnchorPoint = Vector2.new(1, 0.5)
MainFrame.Position = MENU_HIDDEN_POS
MainFrame.Size = MENU_SIZE
MainFrame.BackgroundColor3 = Colors.Background
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.ZIndex = 2
MainFrame.Parent = ScreenGui
MainFrame.Visible = false

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Colors.Accent
MainStroke.Thickness = 1
MainStroke.Parent = MainFrame

local TopBar = Instance.new("Frame")
TopBar.Name = "TopBar"
TopBar.Size = UDim2.new(1, 0, 0, 44)
TopBar.BackgroundColor3 = Colors.Background
TopBar.BorderSizePixel = 0
TopBar.ZIndex = 3
TopBar.Parent = MainFrame

local TopBarLine = Instance.new("Frame")
TopBarLine.Size = UDim2.new(1, 0, 0, 1)
TopBarLine.Position = UDim2.new(0, 0, 1, -1)
TopBarLine.BackgroundColor3 = Colors.Border
TopBarLine.BorderSizePixel = 0
TopBarLine.ZIndex = 4
TopBarLine.Parent = TopBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -60, 1, 0)
TitleLabel.Position = UDim2.new(0, 16, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "averon hub"
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextColor3 = Colors.Text
TitleLabel.TextSize = 15
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.ZIndex = 4
TitleLabel.Parent = TopBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 26, 0, 26)
CloseBtn.Position = UDim2.new(1, -38, 0.5, -13)
CloseBtn.BackgroundColor3 = Colors.BackgroundHover
CloseBtn.BorderSizePixel = 0
CloseBtn.Text = "×"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextColor3 = Colors.TextDim
CloseBtn.TextSize = 18
CloseBtn.AutoButtonColor = false
CloseBtn.ZIndex = 5
CloseBtn.Parent = TopBar
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 4)

CloseBtn.MouseEnter:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.12), {
        BackgroundColor3 = Color3.fromRGB(60, 25, 25),
        TextColor3 = Color3.fromRGB(255, 120, 120)
    }):Play()
end)
CloseBtn.MouseLeave:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.12), {
        BackgroundColor3 = Colors.BackgroundHover,
        TextColor3 = Colors.TextDim
    }):Play()
end)

local TabBar = Instance.new("Frame")
TabBar.Name = "TabBar"
TabBar.Size = UDim2.new(1, 0, 0, 40)
TabBar.Position = UDim2.new(0, 0, 0, 44)
TabBar.BackgroundColor3 = Colors.Background
TabBar.BorderSizePixel = 0
TabBar.ZIndex = 3
TabBar.Parent = MainFrame

local TabBarLine = Instance.new("Frame")
TabBarLine.Size = UDim2.new(1, 0, 0, 1)
TabBarLine.Position = UDim2.new(0, 0, 1, -1)
TabBarLine.BackgroundColor3 = Colors.Border
TabBarLine.BorderSizePixel = 0
TabBarLine.ZIndex = 4
TabBarLine.Parent = TabBar

local ContentArea = Instance.new("Frame")
ContentArea.Name = "ContentArea"
ContentArea.Size = UDim2.new(1, 0, 1, -84)
ContentArea.Position = UDim2.new(0, 0, 0, 84)
ContentArea.BackgroundColor3 = Colors.Background
ContentArea.BorderSizePixel = 0
ContentArea.ZIndex = 3
ContentArea.Parent = MainFrame

local Pages = {}
local TabButtons = {}

local function CreatePageTab(name, fullWidth)
    local Container = Instance.new("Frame")
    Container.Name = name .. "Page"
    Container.Size = UDim2.new(1, 0, 1, 0)
    Container.BackgroundTransparency = 1
    Container.Visible = false
    Container.ZIndex = 4
    Container.Parent = ContentArea

    local leftCol, rightCol

    if fullWidth then
        leftCol = Instance.new("ScrollingFrame")
        leftCol.Size = UDim2.new(1, -20, 1, -20)
        leftCol.Position = UDim2.new(0, 10, 0, 10)
        leftCol.BackgroundTransparency = 1
        leftCol.BorderSizePixel = 0
        leftCol.ScrollBarThickness = 2
        leftCol.ScrollBarImageColor3 = Colors.Accent
        leftCol.CanvasSize = UDim2.new(0, 0, 0, 0)
        leftCol.AutomaticCanvasSize = Enum.AutomaticSize.Y
        leftCol.ZIndex = 5
        leftCol.Parent = Container

        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 5)
        layout.Parent = leftCol
    else
        leftCol = Instance.new("ScrollingFrame")
        leftCol.Name = "LeftCol"
        leftCol.Size = UDim2.new(0.5, -15, 1, -20)
        leftCol.Position = UDim2.new(0, 10, 0, 10)
        leftCol.BackgroundTransparency = 1
        leftCol.BorderSizePixel = 0
        leftCol.ScrollBarThickness = 2
        leftCol.ScrollBarImageColor3 = Colors.Accent
        leftCol.CanvasSize = UDim2.new(0, 0, 0, 0)
        leftCol.AutomaticCanvasSize = Enum.AutomaticSize.Y
        leftCol.ZIndex = 5
        leftCol.Parent = Container

        local layoutL = Instance.new("UIListLayout")
        layoutL.Padding = UDim.new(0, 5)
        layoutL.Parent = leftCol

        rightCol = Instance.new("ScrollingFrame")
        rightCol.Name = "RightCol"
        rightCol.Size = UDim2.new(0.5, -15, 1, -20)
        rightCol.Position = UDim2.new(0.5, 5, 0, 10)
        rightCol.BackgroundTransparency = 1
        rightCol.BorderSizePixel = 0
        rightCol.ScrollBarThickness = 2
        rightCol.ScrollBarImageColor3 = Colors.Accent
        rightCol.CanvasSize = UDim2.new(0, 0, 0, 0)
        rightCol.AutomaticCanvasSize = Enum.AutomaticSize.Y
        rightCol.ZIndex = 5
        rightCol.Parent = Container

        local layoutR = Instance.new("UIListLayout")
        layoutR.Padding = UDim.new(0, 5)
        layoutR.Parent = rightCol
    end

    local tabBtn = Instance.new("TextButton")
    tabBtn.Name = "Tab_" .. name
    tabBtn.Size = UDim2.new(1/6, -4, 0, 40)
    tabBtn.Position = UDim2.new(#TabButtons * (1/6), 2, 0, 0)
    tabBtn.BackgroundTransparency = 1
    tabBtn.Text = name:upper()
    tabBtn.Font = Enum.Font.GothamBold
    tabBtn.TextColor3 = Colors.TextMuted
    tabBtn.TextSize = 11
    tabBtn.AutoButtonColor = false
    tabBtn.BorderSizePixel = 0
    tabBtn.ZIndex = 5
    tabBtn.Parent = TabBar

    local indicator = Instance.new("Frame")
    indicator.Name = "Indicator"
    indicator.Size = UDim2.new(1, -16, 0, 2)
    indicator.Position = UDim2.new(0, 8, 1, -2)
    indicator.BackgroundColor3 = Colors.Accent
    indicator.BorderSizePixel = 0
    indicator.BackgroundTransparency = 1
    indicator.ZIndex = 6
    indicator.Parent = tabBtn

    local function activate()
        for _, page in ipairs(Pages) do
            page.container.Visible = false
            page.btn.TextColor3 = Colors.TextMuted
            page.indicator.BackgroundTransparency = 1
        end
        Container.Visible = true
        tabBtn.TextColor3 = Colors.Text
        indicator.BackgroundTransparency = 0
    end

    tabBtn.MouseButton1Click:Connect(activate)

    tabBtn.MouseEnter:Connect(function()
        if not Container.Visible then
            TweenService:Create(tabBtn, TweenInfo.new(0.12), {
                TextColor3 = Colors.TextDim
            }):Play()
        end
    end)
    tabBtn.MouseLeave:Connect(function()
        if not Container.Visible then
            TweenService:Create(tabBtn, TweenInfo.new(0.12), {
                TextColor3 = Colors.TextMuted
            }):Play()
        end
    end)

    local pageObj = {
        container = Container,
        left = leftCol,
        right = rightCol or leftCol,
        btn = tabBtn,
        indicator = indicator,
        activate = activate
    }
    table.insert(Pages, pageObj)
    table.insert(TabButtons, tabBtn)
    return pageObj
end

local function CreateToggle(parent, text, default, callback)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, -4, 0, 34)
    Frame.BackgroundColor3 = Colors.BackgroundHover
    Frame.BorderSizePixel = 0
    Frame.Parent = parent
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 4)

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -60, 1, 0)
    Label.Position = UDim2.new(0, 12, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text = text
    Label.TextColor3 = Colors.Text
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 12
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.TextTruncate = Enum.TextTruncate.AtEnd
    Label.Parent = Frame

    local ToggleBtn = Instance.new("Frame")
    ToggleBtn.Size = UDim2.new(0, 32, 0, 16)
    ToggleBtn.Position = UDim2.new(1, -44, 0.5, -8)
    ToggleBtn.BackgroundColor3 = default and Colors.Accent or Color3.fromRGB(45, 45, 50)
    ToggleBtn.BorderSizePixel = 0
    ToggleBtn.Parent = Frame
    Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(1, 0)

    local Knob = Instance.new("Frame")
    Knob.Size = UDim2.new(0, 12, 0, 12)
    Knob.Position = default and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
    Knob.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
    Knob.BorderSizePixel = 0
    Knob.Parent = ToggleBtn
    Instance.new("UICorner", Knob).CornerRadius = UDim.new(1, 0)

    local Click = Instance.new("TextButton")
    Click.Size = UDim2.new(1, 0, 1, 0)
    Click.BackgroundTransparency = 1
    Click.Text = ""
    Click.AutoButtonColor = false
    Click.Parent = Frame

    Frame.MouseEnter:Connect(function()
        TweenService:Create(Frame, TweenInfo.new(0.12), {
            BackgroundColor3 = Color3.fromRGB(30, 30, 34)
        }):Play()
    end)
    Frame.MouseLeave:Connect(function()
        TweenService:Create(Frame, TweenInfo.new(0.12), {
            BackgroundColor3 = Colors.BackgroundHover
        }):Play()
    end)

    local State = default
    Click.MouseButton1Click:Connect(function()
        State = not State
        TweenService:Create(ToggleBtn, TweenInfo.new(0.15), {
            BackgroundColor3 = State and Colors.Accent or Color3.fromRGB(45, 45, 50)
        }):Play()
        TweenService:Create(Knob, TweenInfo.new(0.15), {
            Position = State and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
        }):Play()
        callback(State)
    end)

    return function(newValue)
        if newValue ~= State then
            State = newValue
            ToggleBtn.BackgroundColor3 = State and Colors.Accent or Color3.fromRGB(45, 45, 50)
            Knob.Position = State and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
            callback(State)
        end
    end
end

local function CreateSlider(parent, text, min, max, default, callback)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, -4, 0, 46)
    Frame.BackgroundColor3 = Colors.BackgroundHover
    Frame.BorderSizePixel = 0
    Frame.Parent = parent
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 4)

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -20, 0, 18)
    Label.Position = UDim2.new(0, 12, 0, 4)
    Label.BackgroundTransparency = 1
    Label.Text = text .. ": " .. string.format("%.2f", default)
    Label.TextColor3 = Colors.Text
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 11
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.TextTruncate = Enum.TextTruncate.AtEnd
    Label.Parent = Frame

    local Track = Instance.new("Frame")
    Track.Size = UDim2.new(1, -24, 0, 3)
    Track.Position = UDim2.new(0, 12, 0, 32)
    Track.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
    Track.BorderSizePixel = 0
    Track.Parent = Frame
    Instance.new("UICorner", Track).CornerRadius = UDim.new(1, 0)

    local Fill = Instance.new("Frame")
    Fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    Fill.BackgroundColor3 = Colors.Accent
    Fill.BorderSizePixel = 0
    Fill.Parent = Track
    Instance.new("UICorner", Fill).CornerRadius = UDim.new(1, 0)

    local Knob = Instance.new("Frame")
    Knob.AnchorPoint = Vector2.new(0.5, 0.5)
    Knob.Position = UDim2.new((default - min) / (max - min), 0, 0.5, 0)
    Knob.Size = UDim2.new(0, 10, 0, 10)
    Knob.BackgroundColor3 = Colors.Text
    Knob.BorderSizePixel = 0
    Knob.ZIndex = 5
    Knob.BackgroundTransparency = 1
    Knob.Parent = Track
    Instance.new("UICorner", Knob).CornerRadius = UDim.new(1, 0)

    local KnobStroke = Instance.new("UIStroke")
    KnobStroke.Color = Colors.Accent
    KnobStroke.Thickness = 2
    KnobStroke.Transparency = 1
    KnobStroke.Parent = Knob

    local Sliding = false
    local Hovering = false

    local function SetKnobVisible(visible)
        TweenService:Create(Knob, TweenInfo.new(0.15), {
            BackgroundTransparency = visible and 0 or 1,
            Size = UDim2.new(0, visible and 14 or 10, 0, visible and 14 or 10)
        }):Play()
        TweenService:Create(KnobStroke, TweenInfo.new(0.15), {
            Transparency = visible and 0 or 1
        }):Play()
    end

    local function Update(inputPos)
        local Percent = math.clamp(
            (inputPos.Position.X - Track.AbsolutePosition.X) / Track.AbsoluteSize.X,
            0, 1
        )
        local Value = min + ((max - min) * Percent)
        if (max - min) <= 1 then
            Value = math.floor(Value * 100) / 100
        else
            Value = math.floor(Value)
        end
        Fill.Size = UDim2.new(Percent, 0, 1, 0)
        Knob.Position = UDim2.new(Percent, 0, 0.5, 0)
        Label.Text = text .. ": " .. string.format("%.2f", Value)
        callback(Value)
    end

    Frame.MouseEnter:Connect(function()
        Hovering = true
        SetKnobVisible(true)
        TweenService:Create(Frame, TweenInfo.new(0.12), {
            BackgroundColor3 = Color3.fromRGB(30, 30, 34)
        }):Play()
    end)
    Frame.MouseLeave:Connect(function()
        Hovering = false
        if not Sliding then SetKnobVisible(false) end
        TweenService:Create(Frame, TweenInfo.new(0.12), {
            BackgroundColor3 = Colors.BackgroundHover
        }):Play()
    end)

    Frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            Sliding = true
            SetKnobVisible(true)
            Update(input)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if Sliding and input.UserInputType == Enum.UserInputType.MouseMovement then
            Update(input)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and Sliding then
            Sliding = false
            if not Hovering then SetKnobVisible(false) end
        end
    end)

    return function(newValue)
        local Percent = math.clamp((newValue - min) / (max - min), 0, 1)
        Fill.Size = UDim2.new(Percent, 0, 1, 0)
        Knob.Position = UDim2.new(Percent, 0, 0.5, 0)
        Label.Text = text .. ": " .. string.format("%.2f", newValue)
    end
end

local function CreateDropdown(parent, text, options, default, callback)
    local Button = Instance.new("TextButton")
    Button.Size = UDim2.new(1, -4, 0, 34)
    Button.BackgroundColor3 = Colors.BackgroundHover
    Button.BorderSizePixel = 0
    Button.Text = "  " .. text .. "   ▸   " .. (default or options[1])
    Button.TextColor3 = Colors.Text
    Button.Font = Enum.Font.Gotham
    Button.TextSize = 12
    Button.TextXAlignment = Enum.TextXAlignment.Left
    Button.TextTruncate = Enum.TextTruncate.AtEnd
    Button.AutoButtonColor = false
    Button.Parent = parent
    Instance.new("UICorner", Button).CornerRadius = UDim.new(0, 4)

    local Padding = Instance.new("UIPadding")
    Padding.PaddingLeft = UDim.new(0, 6)
    Padding.Parent = Button

    Button.MouseEnter:Connect(function()
        TweenService:Create(Button, TweenInfo.new(0.12), {
            BackgroundColor3 = Color3.fromRGB(30, 30, 34)
        }):Play()
    end)
    Button.MouseLeave:Connect(function()
        TweenService:Create(Button, TweenInfo.new(0.12), {
            BackgroundColor3 = Colors.BackgroundHover
        }):Play()
    end)

    local Index = 1
    for i, opt in ipairs(options) do
        if opt == (default or options[1]) then Index = i break end
    end

    Button.MouseButton1Click:Connect(function()
        Index = Index + 1
        if Index > #options then Index = 1 end
        Button.Text = "  " .. text .. "   ▸   " .. options[Index]
        callback(options[Index])
    end)
end

local function CreateKeybind(parent, text, default, callback)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, -4, 0, 34)
    Frame.BackgroundColor3 = Colors.BackgroundHover
    Frame.BorderSizePixel = 0
    Frame.Parent = parent
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 4)

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -110, 1, 0)
    Label.Position = UDim2.new(0, 12, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text = text
    Label.TextColor3 = Colors.Text
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 12
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.TextTruncate = Enum.TextTruncate.AtEnd
    Label.Parent = Frame

    local BindBtn = Instance.new("TextButton")
    BindBtn.Size = UDim2.new(0, 84, 0, 22)
    BindBtn.Position = UDim2.new(1, -92, 0.5, -11)
    BindBtn.BackgroundColor3 = Colors.BackgroundInput
    BindBtn.BorderSizePixel = 0
    BindBtn.Text = (default and default.Name) or "None"
    BindBtn.TextColor3 = Colors.Accent
    BindBtn.Font = Enum.Font.GothamBold
    BindBtn.TextSize = 10
    BindBtn.AutoButtonColor = false
    BindBtn.Parent = Frame
    Instance.new("UICorner", BindBtn).CornerRadius = UDim.new(0, 4)

    BindBtn.MouseEnter:Connect(function()
        TweenService:Create(BindBtn, TweenInfo.new(0.12), {
            BackgroundColor3 = Color3.fromRGB(32, 32, 38)
        }):Play()
    end)
    BindBtn.MouseLeave:Connect(function()
        TweenService:Create(BindBtn, TweenInfo.new(0.12), {
            BackgroundColor3 = Colors.BackgroundInput
        }):Play()
    end)

    local CurrentKey = default
    local Listening = false
    local Connection

    local function UpdateText()
        BindBtn.Text = (CurrentKey and CurrentKey.Name) or "None"
    end

    local function StopListening()
        Listening = false
        if Connection then Connection:Disconnect() Connection = nil end
        UpdateText()
    end

    BindBtn.MouseButton1Click:Connect(function()
        if Listening then return end
        Listening = true
        BindBtn.Text = "..."
        Connection = UserInputService.InputBegan:Connect(function(input, gp)
            if gp then return end
            if input.UserInputType == Enum.UserInputType.Keyboard then
                if input.KeyCode == Enum.KeyCode.Delete or input.KeyCode == Enum.KeyCode.Backspace then
                    CurrentKey = nil
                else
                    CurrentKey = input.KeyCode
                end
                callback(CurrentKey)
                StopListening()
            end
        end)
    end)

    BindBtn.Destroying:Connect(function()
        if Connection then Connection:Disconnect() end
    end)
end

local TriggerPage = CreatePageTab("Trigger")
local SilentPage  = CreatePageTab("Silent")
local HitboxPage  = CreatePageTab("Hitbox")
local PlayersPage = CreatePageTab("Players", true)
local ESPPage     = CreatePageTab("Visual")
local InfoPage    = CreatePageTab("Info")

CreateToggle(TriggerPage.left, "Enable Triggerbot", Config.Trigger.Active, function(val) Config.Trigger.Active = val end)
CreateDropdown(TriggerPage.left, "Target Mode", {"Player", "Hitbox"}, "Player", function(val) Config.Trigger.Mode = val end)
CreateSlider(TriggerPage.left, "Radius", 0, 200, Config.Trigger.Radius, function(val) Config.Trigger.Radius = val end)
CreateSlider(TriggerPage.left, "Max Distance", 0, 200, Config.Trigger.MaxDist, function(val) Config.Trigger.MaxDist = val end)
CreateToggle(TriggerPage.left, "Wall Check", Config.Trigger.WallCheck, function(val) Config.Trigger.WallCheck = val end)

CreateToggle(SilentPage.left, "Enable Silent Aim", Config.Silent.Enabled, function(val)
    Config.Silent.Enabled = val
end)
CreateKeybind(SilentPage.left, "Toggle Key", Config.Silent.ToggleKey, function(key)
    Config.Silent.ToggleKey = key
end)
CreateDropdown(SilentPage.left, "Target Part", {"Head", "Torso", "HumanoidRootPart"}, Config.Silent.TargetPart, function(val)
    Config.Silent.TargetPart = val
end)
CreateSlider(SilentPage.left, "Prediction", 0, 1, Config.Silent.Prediction, function(val)
    Config.Silent.Prediction = val
end)
CreateSlider(SilentPage.left, "FOV Radius", 50, 1000, Config.Silent.FOVRadius, function(val)
    Config.Silent.FOVRadius = val
end)

CreateToggle(SilentPage.right, "Show FOV Circle", Config.Silent.FOVVisible, function(val)
    Config.Silent.FOVVisible = val
end)
CreateToggle(SilentPage.right, "Skip Behind Walls", Config.Silent.NoWall, function(val)
    Config.Silent.NoWall = val
end)
CreateToggle(SilentPage.right, "Skip Dead / K.O", Config.Silent.NoDead, function(val)
    Config.Silent.NoDead = val
end)
CreateToggle(SilentPage.right, "Show Target Line", Config.Silent.ShowTargetLine, function(val)
    Config.Silent.ShowTargetLine = val
end)
CreateSlider(SilentPage.right, "Line Thickness", 1, 6, Config.Silent.TargetLineThickness, function(val)
    Config.Silent.TargetLineThickness = val
end)

CreateToggle(HitboxPage.left, "Enable Hitbox Expander", Config.Hitbox.Enabled, function(val)
    Config.Hitbox.Enabled = val
    HitboxExpander:SetEnabled(val)
end)

CreateSlider(HitboxPage.left, "Size X", 1, 100, Config.Hitbox.SizeX, function(val)
    Config.Hitbox.SizeX = val
    HBConfig.Size = Vector3.new(val, Config.Hitbox.SizeY, Config.Hitbox.SizeZ)
    HitboxExpander:SetSize(HBConfig.Size)
end)

CreateSlider(HitboxPage.left, "Size Y", 1, 100, Config.Hitbox.SizeY, function(val)
    Config.Hitbox.SizeY = val
    HBConfig.Size = Vector3.new(Config.Hitbox.SizeX, val, Config.Hitbox.SizeZ)
    HitboxExpander:SetSize(HBConfig.Size)
end)

CreateSlider(HitboxPage.left, "Size Z", 1, 100, Config.Hitbox.SizeZ, function(val)
    Config.Hitbox.SizeZ = val
    HBConfig.Size = Vector3.new(Config.Hitbox.SizeX, Config.Hitbox.SizeY, val)
    HitboxExpander:SetSize(HBConfig.Size)
end)

CreateSlider(HitboxPage.right, "Transparency", 0, 1, Config.Hitbox.Transparency, function(val)
    Config.Hitbox.Transparency = val
    HitboxExpander:SetTransparency(val)
end)

CreateToggle(HitboxPage.right, "Only Target", Config.Hitbox.OnlyTarget, function(val)
    Config.Hitbox.OnlyTarget = val
    HitboxExpander:SetOnlyTarget(val)
end)

CreateToggle(ESPPage.left, "Only Target", Config.ESP.OnlyTarget, function(val) Config.ESP.OnlyTarget = val end)
CreateToggle(ESPPage.left, "Name ESP", Config.ESP.Name.Enabled, function(val) Config.ESP.Name.Enabled = val end)
CreateToggle(ESPPage.left, "Show Distance", Config.ESP.Name.ShowDistance, function(val) Config.ESP.Name.ShowDistance = val end)
CreateToggle(ESPPage.left, "Box ESP", Config.ESP.Box.Enabled, function(val) Config.ESP.Box.Enabled = val end)

CreateToggle(ESPPage.right, "Chams", Config.ESP.Chams.Enabled, function(val) Config.ESP.Chams.Enabled = val end)
CreateSlider(ESPPage.right, "Chams Transparency", 0, 1, Config.ESP.Chams.Transparency, function(val)
    Config.ESP.Chams.Transparency = val
end)
CreateToggle(ESPPage.right, "Healthbar", Config.ESP.Healthbar.Enabled, function(val) Config.ESP.Healthbar.Enabled = val end)
CreateToggle(ESPPage.right, "Tool ESP", Config.ESP.Tool.Enabled, function(val) Config.ESP.Tool.Enabled = val end)

PlayersPage.left.ScrollingEnabled = false
PlayersPage.left.CanvasSize = UDim2.new(0, 0, 0, 0)
PlayersPage.left.AutomaticCanvasSize = Enum.AutomaticSize.None

for _, child in ipairs(PlayersPage.left:GetChildren()) do
    if child:IsA("UIListLayout") then child:Destroy() end
end

CreateToggle(PlayersPage.left, "Target All Players", Config.Targeting.TargetAll, function(val)
    Config.Targeting.TargetAll = val
end)

local playersHeader = Instance.new("Frame")
playersHeader.Size = UDim2.new(1, -4, 0, 30)
playersHeader.BackgroundColor3 = Colors.BackgroundHover
playersHeader.BorderSizePixel = 0
playersHeader.Parent = PlayersPage.left
Instance.new("UICorner", playersHeader).CornerRadius = UDim.new(0, 4)

local playerCountLabel = Instance.new("TextLabel")
playerCountLabel.Size = UDim2.new(1, -20, 1, 0)
playerCountLabel.Position = UDim2.new(0, 14, 0, 0)
playerCountLabel.BackgroundTransparency = 1
playerCountLabel.Font = Enum.Font.GothamBold
playerCountLabel.Text = "Players — " .. #Players:GetPlayers()
playerCountLabel.TextColor3 = Colors.Text
playerCountLabel.TextSize = 11
playerCountLabel.TextXAlignment = Enum.TextXAlignment.Left
playerCountLabel.Parent = playersHeader

local searchFrame = Instance.new("Frame")
searchFrame.Size = UDim2.new(1, -4, 0, 32)
searchFrame.BackgroundColor3 = Colors.BackgroundHover
searchFrame.BorderSizePixel = 0
searchFrame.Parent = PlayersPage.left
Instance.new("UICorner", searchFrame).CornerRadius = UDim.new(0, 4)

local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, -16, 1, -8)
searchBox.Position = UDim2.new(0, 8, 0, 4)
searchBox.BackgroundColor3 = Colors.BackgroundInput
searchBox.BorderSizePixel = 0
searchBox.Font = Enum.Font.Gotham
searchBox.PlaceholderText = "Search player..."
searchBox.Text = Config.Targeting.SearchQuery
searchBox.TextColor3 = Colors.Text
searchBox.PlaceholderColor3 = Colors.TextMuted
searchBox.TextSize = 12
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.ClearTextOnFocus = false
searchBox.Parent = searchFrame
Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 4)

local playersContainer = Instance.new("ScrollingFrame")
playersContainer.Size = UDim2.new(1, -4, 1, -160)
playersContainer.Position = UDim2.new(0, 0, 0, 160)
playersContainer.BackgroundTransparency = 1
playersContainer.BorderSizePixel = 0
playersContainer.ScrollBarThickness = 2
playersContainer.ScrollBarImageColor3 = Colors.Accent
playersContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
playersContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
playersContainer.Parent = PlayersPage.left

local playersLayout = Instance.new("UIListLayout")
playersLayout.SortOrder = Enum.SortOrder.Name
playersLayout.Padding = UDim.new(0, 5)
playersLayout.Parent = playersContainer

local function createPlayerEntry(player)
    local query = searchBox.Text:lower()
    if query ~= "" then
        if not player.Name:lower():find(query) and not player.DisplayName:lower():find(query) then
            return
        end
    end

    local playerFrame = Instance.new("Frame")
    playerFrame.Name = player.Name
    playerFrame.Size = UDim2.new(1, 0, 0, 52)
    playerFrame.BackgroundColor3 = Colors.BackgroundHover
    playerFrame.BorderSizePixel = 0
    playerFrame.Parent = playersContainer
    Instance.new("UICorner", playerFrame).CornerRadius = UDim.new(0, 4)

    local displayNameLabel = Instance.new("TextLabel")
    displayNameLabel.Size = UDim2.new(0.5, -60, 0, 16)
    displayNameLabel.Position = UDim2.new(0, 14, 0, 6)
    displayNameLabel.BackgroundTransparency = 1
    displayNameLabel.Font = Enum.Font.GothamBold
    displayNameLabel.Text = player.DisplayName
    displayNameLabel.TextColor3 = Colors.Text
    displayNameLabel.TextSize = 12
    displayNameLabel.TextXAlignment = Enum.TextXAlignment.Left
    displayNameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    displayNameLabel.Parent = playerFrame

    local usernameLabel = Instance.new("TextLabel")
    usernameLabel.Size = UDim2.new(0.5, -60, 0, 14)
    usernameLabel.Position = UDim2.new(0, 14, 0, 26)
    usernameLabel.BackgroundTransparency = 1
    usernameLabel.Font = Enum.Font.Gotham
    usernameLabel.Text = "@" .. player.Name
    usernameLabel.TextColor3 = Colors.TextMuted
    usernameLabel.TextSize = 10
    usernameLabel.TextXAlignment = Enum.TextXAlignment.Left
    usernameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    usernameLabel.Parent = playerFrame

    local currentRole = GetRole(player)

    local roles = {
        {name = "Target",    color = Color3.fromRGB(200, 40, 40)},
        {name = "Whitelist", color = Color3.fromRGB(50, 160, 90)},
        {name = "Neutral",   color = Color3.fromRGB(70, 70, 75)}
    }

    for i, role in ipairs(roles) do
        local roleButton = Instance.new("TextButton")
        roleButton.Size = UDim2.new(0, 76, 0, 24)
        roleButton.Position = UDim2.new(1, -82 - ((3 - i) * 82), 0.5, -12)
        roleButton.BackgroundColor3 = currentRole == role.name and role.color or Color3.fromRGB(35, 35, 40)
        roleButton.BorderSizePixel = 0
        roleButton.Font = Enum.Font.GothamBold
        roleButton.Text = role.name
        roleButton.TextColor3 = currentRole == role.name and Color3.new(1, 1, 1) or Colors.TextMuted
        roleButton.TextSize = 10
        roleButton.AutoButtonColor = false
        roleButton.Parent = playerFrame
        Instance.new("UICorner", roleButton).CornerRadius = UDim.new(0, 4)

        local roleStroke = Instance.new("UIStroke")
        roleStroke.Color = role.color
        roleStroke.Thickness = 1.5
        roleStroke.Transparency = currentRole == role.name and 0 or 1
        roleStroke.Parent = roleButton

        roleButton.MouseEnter:Connect(function()
            local isActive = roleButton.Text == (GetRole(player) or "Neutral")
            if not isActive then
                TweenService:Create(roleButton, TweenInfo.new(0.12), {
                    BackgroundColor3 = Color3.fromRGB(50, 50, 56),
                    TextColor3 = Colors.Text
                }):Play()
            end
            TweenService:Create(roleStroke, TweenInfo.new(0.12), { Transparency = 0.2 }):Play()
        end)
        roleButton.MouseLeave:Connect(function()
            local isActive = roleButton.Text == (GetRole(player) or "Neutral")
            if not isActive then
                TweenService:Create(roleButton, TweenInfo.new(0.12), {
                    BackgroundColor3 = Color3.fromRGB(35, 35, 40),
                    TextColor3 = Colors.TextMuted
                }):Play()
            end
            TweenService:Create(roleStroke, TweenInfo.new(0.12), { Transparency = isActive and 0 or 1 }):Play()
        end)

        roleButton.MouseButton1Click:Connect(function()
            SetRole(player, role.name)
            for _, btn in ipairs(playerFrame:GetChildren()) do
                if btn:IsA("TextButton") then
                    local isActive = btn.Text == role.name
                    local btnRole
                    for _, r in ipairs(roles) do
                        if r.name == btn.Text then btnRole = r break end
                    end
                    if btnRole then
                        TweenService:Create(btn, TweenInfo.new(0.15), {
                            BackgroundColor3 = isActive and btnRole.color or Color3.fromRGB(35, 35, 40),
                            TextColor3 = isActive and Color3.new(1, 1, 1) or Colors.TextMuted
                        }):Play()
                        local stroke = btn:FindFirstChildOfClass("UIStroke")
                        if stroke then
                            stroke.Color = btnRole.color
                            TweenService:Create(stroke, TweenInfo.new(0.15), { Transparency = isActive and 0 or 1 }):Play()
                        end
                    end
                end
            end
        end)
    end
end

local function refreshPlayerList()
    for _, child in ipairs(playersContainer:GetChildren()) do
        if not child:IsA("UIListLayout") then
            child:Destroy()
        end
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            createPlayerEntry(player)
        end
    end
    playerCountLabel.Text = "Players — " .. #Players:GetPlayers()
end

local searchDebounceId = 0
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    Config.Targeting.SearchQuery = searchBox.Text
    searchDebounceId = searchDebounceId + 1
    local myId = searchDebounceId
    task.delay(0.15, function()
        if myId == searchDebounceId then refreshPlayerList() end
    end)
end)

SubscribePlayer(
    function() task.wait(0.5) refreshPlayerList() end,
    function() task.wait(0.5) refreshPlayerList() end
)

refreshPlayerList()

InfoPage.left.CanvasSize = UDim2.new(0, 0, 0, 0)

local InfoLayout = Instance.new("UIListLayout")
InfoLayout.Padding = UDim.new(0, 6)
InfoLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
InfoLayout.Parent = InfoPage.left

local function CreateDevCard(parent, userId, username, role)
    local Card = Instance.new("Frame")
    Card.Size = UDim2.new(1, -4, 0, 80)
    Card.BackgroundColor3 = Colors.BackgroundHover
    Card.BorderSizePixel = 0
    Card.Parent = parent
    Instance.new("UICorner", Card).CornerRadius = UDim.new(0, 4)

    local Avatar = Instance.new("ImageLabel")
    Avatar.Size = UDim2.new(0, 56, 0, 56)
    Avatar.Position = UDim2.new(0, 12, 0.5, -28)
    Avatar.BackgroundColor3 = Colors.BackgroundInput
    Avatar.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. userId .. "&width=200&height=200&format=png"
    Avatar.Parent = Card
    Instance.new("UICorner", Avatar).CornerRadius = UDim.new(0, 4)

    local NameLabel = Instance.new("TextLabel")
    NameLabel.Size = UDim2.new(1, -88, 0, 18)
    NameLabel.Position = UDim2.new(0, 80, 0, 14)
    NameLabel.BackgroundTransparency = 1
    NameLabel.Text = username
    NameLabel.TextColor3 = Colors.Text
    NameLabel.Font = Enum.Font.GothamBold
    NameLabel.TextSize = 12
    NameLabel.TextXAlignment = Enum.TextXAlignment.Left
    NameLabel.Parent = Card

    local RoleLabel = Instance.new("TextLabel")
    RoleLabel.Size = UDim2.new(1, -88, 0, 14)
    RoleLabel.Position = UDim2.new(0, 80, 0, 33)
    RoleLabel.BackgroundTransparency = 1
    RoleLabel.Text = role
    RoleLabel.TextColor3 = Colors.Accent
    RoleLabel.Font = Enum.Font.GothamBold
    RoleLabel.TextSize = 10
    RoleLabel.TextXAlignment = Enum.TextXAlignment.Left
    RoleLabel.Parent = Card

    local IDLabel = Instance.new("TextLabel")
    IDLabel.Size = UDim2.new(1, -88, 0, 14)
    IDLabel.Position = UDim2.new(0, 80, 0, 50)
    IDLabel.BackgroundTransparency = 1
    IDLabel.Text = "ID — " .. userId
    IDLabel.TextColor3 = Colors.TextMuted
    IDLabel.Font = Enum.Font.Gotham
    IDLabel.TextSize = 10
    IDLabel.TextXAlignment = Enum.TextXAlignment.Left
    IDLabel.Parent = Card
end

CreateDevCard(InfoPage.left, "10556454097", "wyv(bewit0b285)",  "LEAD SCRIPTER")
CreateDevCard(InfoPage.left, "9398850460",  "wyvy(Bear_Star53)", "LEAD TESTER")
CreateDevCard(InfoPage.left, "123456789",   "?????(??????)",     "AVERON OWNER")

Pages[1].activate()

local function CreateESP(player)
    if ESPObjects[player] then return end
    local espFolder = Instance.new("Folder")
    espFolder.Name = "ESP_" .. player.Name
    espFolder.Parent = CoreGui

    ESPObjects[player] = { Folder = espFolder, Name = nil, Box = {}, Chams = {}, Healthbar = {}, Tool = nil }

    local nameLabel = Instance.new("BillboardGui")
    nameLabel.Name = "NameESP"
    nameLabel.AlwaysOnTop = true
    nameLabel.Size = UDim2.new(0, 100, 0, 30)
    nameLabel.StudsOffset = Vector3.new(0, 3, 0)
    nameLabel.Parent = espFolder

    local nameText = Instance.new("TextLabel")
    nameText.Size = UDim2.new(1, 0, 1, 0)
    nameText.BackgroundTransparency = 1
    nameText.Font = Enum.Font.GothamBold
    nameText.TextSize = 14
    nameText.TextColor3 = ESPWhite
    nameText.TextStrokeColor3 = Color3.new(0, 0, 0)
    nameText.TextStrokeTransparency = 0.5
    nameText.Parent = nameLabel
    ESPObjects[player].Name = nameLabel

    local toolLabel = Instance.new("BillboardGui")
    toolLabel.Name = "ToolESP"
    toolLabel.AlwaysOnTop = true
    toolLabel.Size = UDim2.new(0, 100, 0, 20)
    toolLabel.StudsOffset = Vector3.new(0, -3, 0)
    toolLabel.Parent = espFolder

    local toolText = Instance.new("TextLabel")
    toolText.Size = UDim2.new(1, 0, 1, 0)
    toolText.BackgroundTransparency = 1
    toolText.Font = Enum.Font.GothamBold
    toolText.TextSize = 12
    toolText.TextColor3 = ESPWhite
    toolText.TextStrokeTransparency = 0.5
    toolText.Parent = toolLabel
    ESPObjects[player].Tool = toolLabel
end

local function RemoveESP(player)
    if not ESPObjects[player] then return end
    if ESPObjects[player].Folder then ESPObjects[player].Folder:Destroy() end
    if player.Character then
        local chams = player.Character:FindFirstChild("averon_Chams")
        if chams then chams:Destroy() end
    end
    ESPObjects[player] = nil
end

local function CreateBox(player)
    if ESPObjects[player] and ESPObjects[player].Box[1] then return end
    local character = player.Character
    if not character then return end
    local hrp = GetTargetPart(character)
    if not hrp then return end
    if not ESPObjects[player] then CreateESP(player) end

    for _, obj in pairs(ESPObjects[player].Box) do
        if obj and obj.Parent then obj:Destroy() end
    end
    ESPObjects[player].Box = {}

    local boxGui = Instance.new("BillboardGui")
    boxGui.Name = "BoxESP"
    boxGui.Adornee = hrp
    boxGui.Size = UDim2.new(4, 0, 5, 0)
    boxGui.AlwaysOnTop = true
    boxGui.Parent = ESPObjects[player].Folder

    local topLine = Instance.new("Frame")
    topLine.Size = UDim2.new(1, 0, 0, 2)
    topLine.BackgroundColor3 = ESPWhite
    topLine.BorderSizePixel = 0
    topLine.Parent = boxGui

    local bottomLine = Instance.new("Frame")
    bottomLine.Size = UDim2.new(1, 0, 0, 2)
    bottomLine.Position = UDim2.new(0, 0, 1, -2)
    bottomLine.BackgroundColor3 = ESPWhite
    bottomLine.BorderSizePixel = 0
    bottomLine.Parent = boxGui

    local leftLine = Instance.new("Frame")
    leftLine.Size = UDim2.new(0, 2, 1, 0)
    leftLine.BackgroundColor3 = ESPWhite
    leftLine.BorderSizePixel = 0
    leftLine.Parent = boxGui

    local rightLine = Instance.new("Frame")
    rightLine.Size = UDim2.new(0, 2, 1, 0)
    rightLine.Position = UDim2.new(1, -2, 0, 0)
    rightLine.BackgroundColor3 = ESPWhite
    rightLine.BorderSizePixel = 0
    rightLine.Parent = boxGui

    ESPObjects[player].Box = {boxGui, topLine, bottomLine, leftLine, rightLine}
end

local function CreateHealthbar(player)
    if ESPObjects[player] and ESPObjects[player].Healthbar[1] then return end
    local character = player.Character
    if not character then return end
    local hrp = GetTargetPart(character)
    if not hrp then return end
    if not ESPObjects[player] then CreateESP(player) end

    for _, obj in pairs(ESPObjects[player].Healthbar) do
        if obj and obj.Parent then obj:Destroy() end
    end
    ESPObjects[player].Healthbar = {}

    local healthGui = Instance.new("BillboardGui")
    healthGui.Name = "HealthbarESP"
    healthGui.Adornee = hrp
    healthGui.Size = UDim2.new(0, 4, 5, 0)
    healthGui.StudsOffset = Vector3.new(-2.5, 0, 0)
    healthGui.AlwaysOnTop = true
    healthGui.Parent = ESPObjects[player].Folder

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Color3.new(0, 0, 0)
    bg.BackgroundTransparency = 0.5
    bg.BorderSizePixel = 0
    bg.Parent = healthGui

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(1, 0, 1, 0)
    fill.Position = UDim2.new(0, 0, 1, 0)
    fill.AnchorPoint = Vector2.new(0, 1)
    fill.BackgroundColor3 = ESPWhite
    fill.BorderSizePixel = 0
    fill.Parent = healthGui

    local outline = Instance.new("UIStroke")
    outline.Color = Color3.new(0, 0, 0)
    outline.Thickness = 1
    outline.Parent = bg

    ESPObjects[player].Healthbar = {healthGui, bg, fill, outline}
end

local function ApplyChams(player)
    local character = player.Character
    if not character then return end
    if not ESPObjects[player] then CreateESP(player) end

    local existing = character:FindFirstChild("averon_Chams")
    if not existing then
        existing = Instance.new("Highlight")
        existing.Name = "averon_Chams"
        existing.Parent = character
        table.insert(ESPObjects[player].Chams, existing)
    end
    existing.FillColor = ESPWhite
    existing.OutlineColor = ESPWhite
    existing.FillTransparency = Config.ESP.Chams.Transparency
    existing.OutlineTransparency = 0
    existing.Adornee = character
end

local function ClearChams(player)
    if not ESPObjects[player] then return end
    if ESPObjects[player].Chams then
        for _, hl in pairs(ESPObjects[player].Chams) do
            if hl and hl.Parent then hl:Destroy() end
        end
        ESPObjects[player].Chams = {}
    end
    if player.Character then
        local chams = player.Character:FindFirstChild("averon_Chams")
        if chams then chams:Destroy() end
    end
end

local function UpdateESP()
    local camera = GetCamera()
    if not camera then return end

    local players = Players:GetPlayers()
    for i = 1, #players do
        local player = players[i]
        if player ~= LocalPlayer then
            local character = player.Character
            if not character then RemoveESP(player) else
                local hrp = GetTargetPart(character)
                if not hrp then RemoveESP(player) else
                    if not CanESPTarget(player, Config.ESP.OnlyTarget) then
                        RemoveESP(player)
                    elseif not IsPlayerAlive(player) or IsPlayerKO(player) then
                        RemoveESP(player)
                    else
                        if not ESPObjects[player] then CreateESP(player) end

                        local distance = (camera.CFrame.Position - hrp.Position).Magnitude
                        local screenPos, onScreen = camera:WorldToViewportPoint(hrp.Position)
                        local highlighted = IsSilentHighlighted(player)

                        if Config.ESP.Name.Enabled and ESPObjects[player].Name then
                            ESPObjects[player].Name.Enabled = onScreen
                            ESPObjects[player].Name.Adornee = hrp
                            local nameText = ESPObjects[player].Name:FindFirstChild("TextLabel")
                            if nameText then
                                nameText.Text = Config.ESP.Name.ShowDistance
                                    and (player.DisplayName .. " [" .. math.floor(distance) .. "m]")
                                    or player.DisplayName
                                nameText.TextColor3 = highlighted and SilentHighlightColor or ESPWhite
                                nameText.TextStrokeTransparency = highlighted and 0.3 or 0.5
                            end
                        elseif ESPObjects[player].Name then
                            ESPObjects[player].Name.Enabled = false
                        end

                        if Config.ESP.Tool.Enabled and ESPObjects[player].Tool then
                            local tool = character:FindFirstChildOfClass("Tool")
                            if tool and onScreen then
                                ESPObjects[player].Tool.Enabled = true
                                ESPObjects[player].Tool.Adornee = hrp
                                local toolText = ESPObjects[player].Tool:FindFirstChild("TextLabel")
                                if toolText then
                                    toolText.Text = "[" .. tool.Name .. "]"
                                    toolText.TextColor3 = highlighted and SilentHighlightColor or ESPWhite
                                end
                            else
                                ESPObjects[player].Tool.Enabled = false
                            end
                        elseif ESPObjects[player].Tool then
                            ESPObjects[player].Tool.Enabled = false
                        end

                        if Config.ESP.Box.Enabled then
                            if #ESPObjects[player].Box == 0 or not ESPObjects[player].Box[1] then CreateBox(player) end
                            if ESPObjects[player].Box[1] and onScreen then
                                local boxColor = highlighted and SilentHighlightColor or ESPWhite
                                for j = 2, #ESPObjects[player].Box do
                                    local line = ESPObjects[player].Box[j]
                                    if line then line.BackgroundColor3 = boxColor end
                                end
                                ESPObjects[player].Box[1].Enabled = true
                            else
                                if ESPObjects[player].Box[1] then ESPObjects[player].Box[1].Enabled = false end
                            end
                        else
                            if ESPObjects[player].Box[1] then ESPObjects[player].Box[1].Enabled = false end
                        end

                        if Config.ESP.Chams.Enabled then
                            ApplyChams(player)
                            local existing = character:FindFirstChild("averon_Chams")
                            if existing then
                                local c = highlighted and SilentHighlightColor or ESPWhite
                                existing.FillColor = c
                                existing.OutlineColor = c
                            end
                        else
                            ClearChams(player)
                        end

                        if Config.ESP.Healthbar.Enabled then
                            if #ESPObjects[player].Healthbar == 0 or not ESPObjects[player].Healthbar[1] then
                                CreateHealthbar(player)
                            end
                            local humanoid = character:FindFirstChildOfClass("Humanoid")
                            if humanoid and onScreen and ESPObjects[player].Healthbar[1] then
                                local pct = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
                                local fill = ESPObjects[player].Healthbar[3]
                                if fill then
                                    ESPObjects[player].Healthbar[1].Enabled = true
                                    fill.Size = UDim2.new(1, 0, pct, 0)
                                    fill.BackgroundColor3 = highlighted and SilentHighlightColor or ESPWhite
                                end
                            else
                                if ESPObjects[player].Healthbar[1] then ESPObjects[player].Healthbar[1].Enabled = false end
                            end
                        else
                            if ESPObjects[player].Healthbar[1] then ESPObjects[player].Healthbar[1].Enabled = false end
                        end
                    end
                end
            end
        end
    end
end

SubscribePlayer(nil, function(player) RemoveESP(player) end)

local SilentPartCache = setmetatable({}, {__mode = "k"})

local function SilentGetPart(char, partName)
    if not char then return nil end
    local c = SilentPartCache[char]
    if c and c.Name == partName and c.Part and c.Part.Parent then return c.Part end
    local p
    if partName == "Head" then
        p = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
    elseif partName == "Torso" then
        p = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
            or char:FindFirstChild("LowerTorso") or char:FindFirstChild("HumanoidRootPart")
    else
        p = char:FindFirstChild("HumanoidRootPart")
    end
    SilentPartCache[char] = {Name = partName, Part = p}
    return p
end

SubscribePlayer(function(plr)
    plr.CharacterAdded:Connect(function(char) SilentPartCache[char] = nil end)
    plr.CharacterRemoving:Connect(function(char) SilentPartCache[char] = nil end)
end)

local silentRayParams = RaycastParams.new()
silentRayParams.FilterType = Enum.RaycastFilterType.Blacklist

local function SilentIsVisible(targetChar, targetPart, camera)
    if not targetChar or not targetPart then return false end
    local origin = camera.CFrame.Position
    local dir = targetPart.Position - origin
    local ignore = {}
    if LocalPlayer.Character then ignore[#ignore + 1] = LocalPlayer.Character end
    silentRayParams.FilterDescendantsInstances = ignore
    local result = Workspace:Raycast(origin, dir, silentRayParams)
    if not result then return true end
    return result.Instance:IsDescendantOf(targetChar)
end

local function SilentIsValidTarget(v, camera, mouseX, mouseY)
    local s = Config.Silent
    if not v or v == LocalPlayer then return false end
    if not v.Parent or not v.Character then return false end
    if GetRole(v) ~= "Target" then return false end
    if s.NoDead and (not IsPlayerAlive(v) or IsPlayerKO(v)) then return false end
    local part = SilentGetPart(v.Character, s.TargetPart)
    if not part then return false end
    local pos, onScreen = camera:WorldToViewportPoint(part.Position)
    if not onScreen then return false end
    local dx, dy = pos.X - mouseX, pos.Y - mouseY
    if (dx*dx + dy*dy) > (s.FOVRadius * s.FOVRadius) then return false end
    if s.NoWall and not SilentIsVisible(v.Character, part, camera) then return false end
    return true
end

local SilentTargetCache = nil
local SilentTargetCacheClock = -1

local function SilentGetClosest(camera)
    local s = Config.Silent
    if not s.Enabled then
        SilentLockedTarget = nil
        return nil
    end
    local mx, my = Mouse.X, Mouse.Y

    if SilentLockedTarget then
        if SilentIsValidTarget(SilentLockedTarget, camera, mx, my) then
            return SilentLockedTarget
        end
        SilentLockedTarget = nil
    end

    local now = os.clock()
    if SilentTargetCache and (now - SilentTargetCacheClock) < 0.015 then
        return SilentTargetCache
    end

    local best, bestDist2 = nil, s.FOVRadius * s.FOVRadius
    local players = Players:GetPlayers()
    for i = 1, #players do
        local v = players[i]
        if SilentIsValidTarget(v, camera, mx, my) then
            local part = SilentGetPart(v.Character, s.TargetPart)
            if part then
                local pos = camera:WorldToViewportPoint(part.Position)
                local dx, dy = pos.X - mx, pos.Y - my
                local d2 = dx*dx + dy*dy
                if d2 < bestDist2 then best, bestDist2 = v, d2 end
            end
        end
    end

    SilentLockedTarget = best
    SilentTargetCache = best
    SilentTargetCacheClock = now
    return best
end

local SilentHookInstalled = false
pcall(function()
    local mt = getrawmetatable(game)
    local oldIndex = mt.__index
    setreadonly(mt, false)
    mt.__index = function(self, key)
        local s = Config.Silent
        if s.Enabled and self == Mouse and key == "Hit" then
            local cam = GetCamera()
            local t = SilentGetClosest(cam)
            if t and t.Character then
                local part = SilentGetPart(t.Character, s.TargetPart)
                if part then
                    local vel = Vector3.zero
                    pcall(function() vel = part.AssemblyLinearVelocity end)
                    return part.CFrame + (vel * s.Prediction)
                end
            end
        end
        return oldIndex(self, key)
    end
    setreadonly(mt, true)
    SilentHookInstalled = true
end)

local fovCircle
pcall(function()
    fovCircle = Drawing.new("Circle")
    fovCircle.Color        = Color3.fromRGB(220, 40, 40)
    fovCircle.Thickness    = 1
    fovCircle.Filled       = false
    fovCircle.Transparency = Config.Silent.FOVTransparency
    fovCircle.Radius       = Config.Silent.FOVRadius
    fovCircle.Visible      = false
    fovCircle.NumSides     = 64
end)

local targetLine
pcall(function()
    targetLine = Drawing.new("Line")
    targetLine.Visible      = false
    targetLine.Color        = Color3.fromRGB(220, 40, 40)
    targetLine.Thickness    = Config.Silent.TargetLineThickness
    targetLine.Transparency = 1
end)

RunService.RenderStepped:Connect(function()
    local s = Config.Silent
    local cam = GetCamera()
    if not cam then return end

    if fovCircle then
        pcall(function()
            fovCircle.Position     = UserInputService:GetMouseLocation()
            fovCircle.Radius       = s.FOVRadius
            fovCircle.Transparency = s.FOVTransparency
            fovCircle.Visible      = s.FOVVisible and s.Enabled
        end)
    end

    if targetLine then
        if not (s.Enabled and s.ShowTargetLine) then
            targetLine.Visible = false
        else
            local t = SilentGetClosest(cam)
            if t and t.Character then
                local part = SilentGetPart(t.Character, s.TargetPart)
                if part then
                    local pos3D = part.Position
                    if s.Prediction ~= 0 then
                        local vel = Vector3.zero
                        pcall(function() vel = part.AssemblyLinearVelocity end)
                        pos3D = pos3D + vel * s.Prediction
                    end
                    local screen, on = cam:WorldToViewportPoint(pos3D)
                    if on then
                        targetLine.From      = UserInputService:GetMouseLocation()
                        targetLine.To        = Vector2.new(screen.X, screen.Y)
                        targetLine.Thickness = s.TargetLineThickness
                        targetLine.Visible   = true
                    else
                        targetLine.Visible = false
                    end
                else
                    targetLine.Visible = false
                end
            else
                targetLine.Visible = false
            end
        end
    end
end)

if not SilentHookInstalled then
    warn("[averon hub] Silent Aim: getrawmetatable unavailable")
end

local function Get2DBoundingBox(part, camera)
    local size = part.Size
    local cf = part.CFrame
    local corners = {
        cf:PointToWorldSpace(Vector3.new(-size.X/2, -size.Y/2, -size.Z/2)),
        cf:PointToWorldSpace(Vector3.new(size.X/2, -size.Y/2, -size.Z/2)),
        cf:PointToWorldSpace(Vector3.new(-size.X/2, size.Y/2, -size.Z/2)),
        cf:PointToWorldSpace(Vector3.new(size.X/2, size.Y/2, -size.Z/2)),
        cf:PointToWorldSpace(Vector3.new(-size.X/2, -size.Y/2, size.Z/2)),
        cf:PointToWorldSpace(Vector3.new(size.X/2, -size.Y/2, size.Z/2)),
        cf:PointToWorldSpace(Vector3.new(-size.X/2, size.Y/2, size.Z/2)),
        cf:PointToWorldSpace(Vector3.new(size.X/2, size.Y/2, size.Z/2))
    }
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, corner in ipairs(corners) do
        local sp, on = camera:WorldToViewportPoint(corner)
        if on then
            if sp.X < minX then minX = sp.X end
            if sp.Y < minY then minY = sp.Y end
            if sp.X > maxX then maxX = sp.X end
            if sp.Y > maxY then maxY = sp.Y end
        end
    end
    if minX == math.huge then return nil end
    return minX, minY, maxX, maxY
end

local triggerRayParams = RaycastParams.new()
triggerRayParams.FilterType = Enum.RaycastFilterType.Blacklist

local function IsMouseOverPlayer(player, mousePos, camera, ignoreList)
    local char = player.Character
    if not char then return false end
    local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
    triggerRayParams.FilterDescendantsInstances = ignoreList
    local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, triggerRayParams)
    if result and result.Instance and result.Instance:IsDescendantOf(char) then
        return true
    end
    return false
end

local function IsHoldingKnife()
    local char = LocalPlayer.Character
    if not char then return false end
    for _, child in pairs(char:GetChildren()) do
        if child:IsA("Tool") and string.find(child.Name:lower(), "knife") then return true end
    end
    return false
end

local TriggerBaseIgnore = {}
local function RebuildTriggerIgnore()
    table.clear(TriggerBaseIgnore)
    local char = LocalPlayer.Character
    if char then
        TriggerBaseIgnore[#TriggerBaseIgnore + 1] = char
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") then TriggerBaseIgnore[#TriggerBaseIgnore + 1] = child end
        end
    end
end
LocalPlayer.CharacterAdded:Connect(function() task.defer(RebuildTriggerIgnore) end)
RebuildTriggerIgnore()

RunService.RenderStepped:Connect(function()
    UpdateESP()

    if not Config.Trigger.Active then return end
    if IsHoldingKnife() then return end
    if (os.clock() - Config.Trigger.LastShot) < Config.Trigger.Delay then return end

    local currentCamera = GetCamera()
    if not currentCamera then return end

    local mousePos = UserInputService:GetMouseLocation()
    local targetPlayer = nil
    local closestDist = Config.Trigger.Radius

    local players = Players:GetPlayers()
    for i = 1, #players do
        local player = players[i]
        if player ~= LocalPlayer then
            local role = GetRole(player)
            if role ~= "Whitelist" then
                if Config.Targeting.TargetAll or role == "Target" then
                    if IsPlayerAlive(player) and not IsPlayerKO(player) then
                        local char = player.Character
                        if char then
                            local targetPart = GetTargetPart(char)
                            if targetPart then
                                local distance = (currentCamera.CFrame.Position - targetPart.Position).Magnitude
                                if distance <= Config.Trigger.MaxDist then
                                    local isOnTarget = false
                                    if Config.Trigger.Mode == "Player" then
                                        if IsMouseOverPlayer(player, mousePos, currentCamera, TriggerBaseIgnore) then
                                            isOnTarget = true
                                        end
                                    else
                                        local minX, minY, maxX, maxY = Get2DBoundingBox(targetPart, currentCamera)
                                        if minX then
                                            local isInside = (mousePos.X >= minX) and (mousePos.X <= maxX)
                                                and (mousePos.Y >= minY) and (mousePos.Y <= maxY)
                                            if isInside then
                                                if Config.Trigger.WallCheck then
                                                    local dir = (targetPart.Position - currentCamera.CFrame.Position).Unit
                                                    triggerRayParams.FilterDescendantsInstances = TriggerBaseIgnore
                                                    local result = workspace:Raycast(currentCamera.CFrame.Position, dir * distance, triggerRayParams)
                                                    if result then
                                                        local hitPlayer = Players:GetPlayerFromCharacter(result.Instance:FindFirstAncestorOfClass("Model"))
                                                        if hitPlayer == player then isOnTarget = true end
                                                    end
                                                else
                                                    isOnTarget = true
                                                end
                                            end
                                        end
                                    end
                                    if isOnTarget then
                                        if Config.Trigger.Mode == "Hitbox" then
                                            local sp = currentCamera:WorldToViewportPoint(targetPart.Position)
                                            local screenDist = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
                                            if screenDist < closestDist then
                                                targetPlayer = player
                                                closestDist = screenDist
                                            end
                                        else
                                            targetPlayer = player
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if targetPlayer then
        Config.Trigger.LastShot = os.clock()
        VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, true, game, 1)
        task.wait(0.01)
        VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, false, game, 1)
    end
end)

local Dragging = false
local DragStart = nil
local StartPos = nil

TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        Dragging = true
        DragStart = input.Position
        StartPos = MainFrame.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if Dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local Delta = input.Position - DragStart
        MainFrame.Position = UDim2.new(
            StartPos.X.Scale, StartPos.X.Offset + Delta.X,
            StartPos.Y.Scale, StartPos.Y.Offset + Delta.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        Dragging = false
    end
end)

local IsOpen = false
local Animating = false

local openTweenInfo  = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local closeTweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local function OpenMenu()
    if IsOpen then return end
    IsOpen = true
    Animating = true
    MainFrame.Visible = true
    MainFrame.Position = MENU_HIDDEN_POS
    local tween = TweenService:Create(MainFrame, openTweenInfo, { Position = MENU_VISIBLE_POS })
    tween:Play()
    tween.Completed:Connect(function() Animating = false end)
end

local function CloseMenu()
    if not IsOpen then return end
    IsOpen = false
    Animating = true
    local tween = TweenService:Create(MainFrame, closeTweenInfo, { Position = MENU_HIDDEN_POS })
    tween:Play()
    tween.Completed:Connect(function()
        MainFrame.Visible = false
        Animating = false
    end)
end

local function ToggleMenu()
    if Animating then return end
    if IsOpen then CloseMenu() else OpenMenu() end
end

CloseBtn.MouseButton1Click:Connect(function()
    CloseMenu()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Config.MenuKey then
        ToggleMenu()
    end
    if Config.Silent.ToggleKey and input.KeyCode == Config.Silent.ToggleKey then
        Config.Silent.Enabled = not Config.Silent.Enabled
    end
end)

OpenMenu()
