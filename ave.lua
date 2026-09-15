-- ============================================================
-- AVERON HUB — NO SILENT
-- ============================================================
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")
local UserInputService   = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local CoreGui            = game:GetService("CoreGui")
local Workspace          = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera
local Mouse       = LocalPlayer:GetMouse()

-- ============================================================
-- GROUP CHECK
-- ============================================================
local GROUP_ID = 915657087
local MIN_RANK = 1

local function checkGroupAccess()
    local ok, rank = pcall(function()
        return LocalPlayer:GetRankInGroup(GROUP_ID)
    end)
    if not ok then return false end
    if type(rank) ~= "number" then return false end
    return rank >= MIN_RANK
end

if not checkGroupAccess() then
    pcall(function()
        LocalPlayer:Kick("Access denied")
    end)
    return
end

-- ============================================================
-- CONFIG
-- ============================================================
local Config = {
    Enabled  = true,
    MenuKey  = Enum.KeyCode.P,
    Accent   = Color3.fromRGB(220, 40, 40),
    Trigger  = {
        Active    = false,
        Mode      = "Player",
        MaxDist   = 200,
        Radius    = 50,
        Delay     = 0.01,
        LastShot  = 0,
        WallCheck = false
    },
    Targeting = {
        TargetAll   = false,
        PlayerRoles = {},
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
        Enabled         = false,
        SizeX           = 2,
        SizeY           = 5,
        SizeZ           = 1,
        Transparency    = 1,
        OnlyTarget      = false,
        ReapplyInterval = 0.5
    }
}

local Colors = {
    Background      = Color3.fromRGB(12, 12, 14),
    BackgroundAlt   = Color3.fromRGB(16, 16, 18),
    BackgroundHover = Color3.fromRGB(24, 24, 28),
    BackgroundInput = Color3.fromRGB(20, 20, 22),
    Border          = Color3.fromRGB(40, 40, 44),
    Text            = Color3.fromRGB(240, 240, 240),
    TextDim         = Color3.fromRGB(170, 170, 175),
    TextMuted       = Color3.fromRGB(110, 110, 115),
    Accent          = Config.Accent,
    AccentDark      = Color3.fromRGB(120, 25, 25)
}

local ESPWhite   = Color3.new(1, 1, 1)
local ESPObjects = {}

-- ============================================================
-- HITBOX EXPANDER
-- ============================================================
local HBConfig = {
    Enabled         = false,
    Size            = Vector3.new(2, 5, 1),
    Transparency    = 1,
    Color           = BrickColor.new("Really black"),
    Material        = Enum.Material.Neon,
    OnlyTarget      = false,
    ReapplyInterval = 0.5,
}

local HB_PlayerRoles   = {}
local HitboxCache      = {}
local SignalsDone      = {}
local WhitelistSignal  = {}
local heartbeatConn

local HB_DEFAULT_SIZE = Vector3.new(2, 2, 1)

local function hbGetRole(player)
    return HB_PlayerRoles[player.UserId] or "Neutral"
end

local function hbShouldApply(player)
    if player == LocalPlayer then return false end
    if WhitelistSignal[player.UserId] then return false end
    if not HBConfig.Enabled then return false end
    if not player.Character then return false end
    local role = hbGetRole(player)
    if role == "Whitelist" then return false end
    if role == "Target" then return true end
    if role == "Neutral" then return not HBConfig.OnlyTarget end
    return false
end

local function killHitboxSignals(hitbox)
    if not hitbox or not hitbox:IsA("BasePart") then return end
    local props = {
        "Size", "Transparency", "CanCollide", "CanQuery",
        "Massless", "CFrame", "Position", "Color", "BrickColor",
        "Material", "Anchored", "Locked",
    }
    for _, prop in ipairs(props) do
        local ok, sig = pcall(function()
            return hitbox:GetPropertyChangedSignal(prop)
        end)
        if ok and sig then
            local ok2, conns = pcall(getconnections, sig)
            if ok2 and conns then
                for _, conn in ipairs(conns) do
                    pcall(function() conn:Disable() end)
                end
            end
        end
    end
    local ok, sig = pcall(function() return hitbox.Changed end)
    if ok and sig then
        local ok2, conns = pcall(getconnections, sig)
        if ok2 and conns then
            for _, conn in ipairs(conns) do
                pcall(function() conn:Disable() end)
            end
        end
    end
    for _, evt in ipairs({"ChildAdded", "ChildRemoved", "AncestryChanged", "AttributeChanged"}) do
        local ok, sig = pcall(function() return hitbox[evt] end)
        if ok and sig then
            local ok2, conns = pcall(getconnections, sig)
            if ok2 and conns then
                for _, conn in ipairs(conns) do
                    pcall(function() conn:Disable() end)
                end
            end
        end
    end
end

local function startSignalKiller(player, hitbox)
    if SignalsDone[player.UserId] then return end
    SignalsDone[player.UserId] = true
    task.spawn(function()
        local tries = 0
        while SignalsDone[player.UserId]
          and hitbox
          and hitbox.Parent
          and player.Parent
          and tries < 60
        do
            killHitboxSignals(hitbox)
            task.wait(HBConfig.ReapplyInterval)
            tries = tries + 1
        end
    end)
end

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
    if not hitbox or not hitbox.Parent then return end
    pcall(function()
        if hitbox.Size ~= HBConfig.Size then hitbox.Size = HBConfig.Size end
        if hitbox.Transparency ~= HBConfig.Transparency then hitbox.Transparency = HBConfig.Transparency end
        if hitbox.BrickColor ~= HBConfig.Color then hitbox.BrickColor = HBConfig.Color end
        if hitbox.Material ~= HBConfig.Material then hitbox.Material = HBConfig.Material end
        hitbox.CanCollide = false
        hitbox.Massless   = true
    end)
end

local function hbReset(hitbox)
    if not hitbox or not hitbox.Parent then return end
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
        for _, player in ipairs(Players:GetPlayers()) do
            if player == LocalPlayer then continue end
            local hitbox = hbGetHitbox(player)
            if not hitbox then continue end
            if hbShouldApply(player) then
                if not SignalsDone[player.UserId] then
                    killHitboxSignals(hitbox)
                    startSignalKiller(player, hitbox)
                end
                hbApply(hitbox)
            else
                if hitbox.Size ~= HB_DEFAULT_SIZE then
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
        SignalsDone[player.UserId] = nil
        local hb = char:WaitForChild("Hitbox", 5)
        if not hb then return end
        HitboxCache[player] = hb
        if hbShouldApply(player) then
            killHitboxSignals(hb)
            startSignalKiller(player, hb)
            hbApply(hb)
        end
    end)
    player.CharacterRemoving:Connect(function()
        HitboxCache[player] = nil
        SignalsDone[player.UserId] = nil
    end)
end

Players.PlayerAdded:Connect(hbSetupPlayer)
Players.PlayerRemoving:Connect(function(plr)
    HitboxCache[plr]          = nil
    SignalsDone[plr.UserId]   = nil
    HB_PlayerRoles[plr.UserId] = nil
    WhitelistSignal[plr.UserId] = nil
end)

for _, plr in ipairs(Players:GetPlayers()) do
    hbSetupPlayer(plr)
end

local HitboxExpander = {}

function HitboxExpander:SetEnabled(state)
    HBConfig.Enabled = not not state
    if HBConfig.Enabled then
        hbStartHeartbeat()
        for _, plr in ipairs(Players:GetPlayers()) do
            if hbShouldApply(plr) then
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
        if hbShouldApply(plr) then
            local hb = hbGetHitbox(plr)
            if hb then hbApply(hb) end
        end
    end
end

function HitboxExpander:SetTransparency(value)
    HBConfig.Transparency = math.clamp(value, 0, 1)
    for _, plr in ipairs(Players:GetPlayers()) do
        if hbShouldApply(plr) then
            local hb = hbGetHitbox(plr)
            if hb then hbApply(hb) end
        end
    end
end

function HitboxExpander:SetOnlyTarget(state)
    HBConfig.OnlyTarget = not not state
end

function HitboxExpander:SetRole(player, role)
    if typeof(player) == "Instance" and player:IsA("Player") then
        HB_PlayerRoles[player.UserId] = role
    elseif typeof(player) == "number" then
        HB_PlayerRoles[player] = role
    end
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

-- ============================================================
-- GUI
-- ============================================================
if CoreGui:FindFirstChild("averon_hub") then
    CoreGui.averon_hub:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "averon_hub"
ScreenGui.ResetOnSpawn   = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent         = CoreGui

local MainFrame = Instance.new("Frame")
MainFrame.Name                 = "Main"
MainFrame.AnchorPoint          = Vector2.new(0.5, 0.5)
MainFrame.Position             = UDim2.new(0.5, 0, 0.5, 0)
MainFrame.Size                 = UDim2.new(0, 520, 0, 640)
MainFrame.BackgroundColor3     = Colors.Background
MainFrame.BorderSizePixel      = 0
MainFrame.ClipsDescendants     = true
MainFrame.ZIndex               = 2
MainFrame.Parent               = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 6)

local MainStroke = Instance.new("UIStroke")
MainStroke.Color     = Colors.Accent
MainStroke.Thickness = 1.5
MainStroke.Parent    = MainFrame

local TopBar = Instance.new("Frame")
TopBar.Size             = UDim2.new(1, 0, 0, 40)
TopBar.BackgroundColor3 = Colors.BackgroundAlt
TopBar.BorderSizePixel  = 0
TopBar.ZIndex           = 3
TopBar.Parent           = MainFrame
Instance.new("UICorner", TopBar).CornerRadius = UDim.new(0, 6)

local TopBarLine = Instance.new("Frame")
TopBarLine.Size             = UDim2.new(1, 0, 0, 1)
TopBarLine.Position         = UDim2.new(0, 0, 1, -1)
TopBarLine.BackgroundColor3 = Colors.Border
TopBarLine.BorderSizePixel  = 0
TopBarLine.ZIndex           = 4
TopBarLine.Parent           = TopBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size             = UDim2.new(1, -20, 1, 0)
TitleLabel.Position         = UDim2.new(0, 16, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text             = "averon hub"
TitleLabel.Font             = Enum.Font.GothamBold
TitleLabel.TextColor3       = Colors.Text
TitleLabel.TextSize         = 14
TitleLabel.TextXAlignment   = Enum.TextXAlignment.Left
TitleLabel.ZIndex           = 4
TitleLabel.Parent           = TopBar

local Dragging, DragStart, StartPos
TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        Dragging  = true
        DragStart = input.Position
        StartPos  = MainFrame.Position
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

local Sidebar = Instance.new("Frame")
Sidebar.Size             = UDim2.new(0, 130, 1, -40)
Sidebar.Position         = UDim2.new(0, 0, 0, 40)
Sidebar.BackgroundColor3 = Colors.BackgroundAlt
Sidebar.BorderSizePixel  = 0
Sidebar.ZIndex           = 3
Sidebar.Parent           = MainFrame
Instance.new("UICorner", Sidebar).CornerRadius = UDim.new(0, 6)

local SidebarLine = Instance.new("Frame")
SidebarLine.Size             = UDim2.new(0, 1, 1, 0)
SidebarLine.Position         = UDim2.new(1, -1, 0, 0)
SidebarLine.BackgroundColor3 = Colors.Border
SidebarLine.BorderSizePixel  = 0
SidebarLine.ZIndex           = 4
SidebarLine.Parent           = Sidebar

local SidebarHeader = Instance.new("TextLabel")
SidebarHeader.Size             = UDim2.new(1, -20, 0, 20)
SidebarHeader.Position         = UDim2.new(0, 12, 0, 10)
SidebarHeader.BackgroundTransparency = 1
SidebarHeader.Text             = "AVERON HUB"
SidebarHeader.Font             = Enum.Font.GothamBold
SidebarHeader.TextColor3       = Colors.TextMuted
SidebarHeader.TextSize         = 10
SidebarHeader.TextXAlignment   = Enum.TextXAlignment.Left
SidebarHeader.ZIndex           = 4
SidebarHeader.Parent           = Sidebar

local ContentArea = Instance.new("Frame")
ContentArea.Size                 = UDim2.new(1, -144, 1, -56)
ContentArea.Position             = UDim2.new(0, 138, 0, 50)
ContentArea.BackgroundTransparency = 1
ContentArea.ZIndex               = 3
ContentArea.Parent               = MainFrame

local Pages       = {}
local PageButtons = {}
local TabCount    = 0

local function CreatePage(name)
    local Page = Instance.new("ScrollingFrame")
    Page.Name                 = name .. "Page"
    Page.Size                 = UDim2.new(1, 0, 1, 0)
    Page.BackgroundTransparency = 1
    Page.Visible              = false
    Page.ScrollBarThickness   = 2
    Page.ScrollBarImageColor3 = Colors.Accent
    Page.CanvasSize           = UDim2.new(0, 0, 0, 0)
    Page.AutomaticCanvasSize  = Enum.AutomaticSize.Y
    Page.ZIndex               = 4
    Page.BorderSizePixel      = 0
    Page.Parent               = ContentArea

    local Layout = Instance.new("UIListLayout")
    Layout.Padding = UDim.new(0, 5)
    Layout.Parent  = Page

    TabCount = TabCount + 1
    local tabY = 40 + ((TabCount - 1) * 40)

    local Tab = Instance.new("Frame")
    Tab.Name                 = "Tab_" .. name
    Tab.Size                 = UDim2.new(1, -16, 0, 36)
    Tab.Position             = UDim2.new(0, 8, 0, tabY)
    Tab.BackgroundColor3     = Colors.BackgroundHover
    Tab.BackgroundTransparency = 1
    Tab.BorderSizePixel      = 0
    Tab.ZIndex               = 4
    Tab.Parent               = Sidebar
    Instance.new("UICorner", Tab).CornerRadius = UDim.new(0, 4)

    local Indicator = Instance.new("Frame")
    Indicator.Name             = "Indicator"
    Indicator.Size             = UDim2.new(0, 3, 0, 0)
    Indicator.Position         = UDim2.new(0, 0, 0.5, 0)
    Indicator.AnchorPoint      = Vector2.new(0, 0.5)
    Indicator.BackgroundColor3 = Colors.Accent
    Indicator.BorderSizePixel  = 0
    Indicator.ZIndex           = 6
    Indicator.Parent           = Tab
    Instance.new("UICorner", Indicator).CornerRadius = UDim.new(0, 2)

    local Button = Instance.new("TextButton")
    Button.Size                 = UDim2.new(1, 0, 1, 0)
    Button.BackgroundTransparency = 1
    Button.Text                 = name:upper()
    Button.TextColor3           = Colors.TextDim
    Button.Font                 = Enum.Font.GothamMedium
    Button.TextSize             = 12
    Button.ZIndex               = 5
    Button.BorderSizePixel      = 0
    Button.AutoButtonColor      = false
    Button.TextXAlignment       = Enum.TextXAlignment.Left
    Button.Parent               = Tab

    local Pad = Instance.new("UIPadding")
    Pad.PaddingLeft = UDim.new(0, 16)
    Pad.Parent      = Button

    local TabData = { Frame = Tab, Button = Button, Indicator = Indicator, Page = Page }

    Button.MouseButton1Click:Connect(function()
        for _, data in pairs(PageButtons) do
            data.Page.Visible               = false
            data.Button.TextColor3          = Colors.TextDim
            data.Frame.BackgroundTransparency = 1
            data.Indicator.Size             = UDim2.new(0, 3, 0, 0)
        end
        Page.Visible                 = true
        Button.TextColor3            = Colors.Text
        Tab.BackgroundTransparency   = 0
        Indicator.Size               = UDim2.new(0, 3, 0, 20)
    end)

    Button.MouseEnter:Connect(function()
        if not Page.Visible then
            Button.TextColor3          = Colors.Text
            Tab.BackgroundTransparency = 0.5
        end
    end)
    Button.MouseLeave:Connect(function()
        if not Page.Visible then
            Button.TextColor3          = Colors.TextDim
            Tab.BackgroundTransparency = 1
        end
    end)

    table.insert(Pages, Page)
    table.insert(PageButtons, TabData)
    return Page
end

local function CreateToggle(parent, text, default, callback)
    local Frame = Instance.new("Frame")
    Frame.Size             = UDim2.new(1, -8, 0, 36)
    Frame.BackgroundColor3 = Colors.BackgroundHover
    Frame.BorderSizePixel  = 0
    Frame.Parent           = parent
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 4)

    local Label = Instance.new("TextLabel")
    Label.Size             = UDim2.new(1, -70, 1, 0)
    Label.Position         = UDim2.new(0, 14, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text             = text
    Label.TextColor3       = Colors.Text
    Label.Font             = Enum.Font.Gotham
    Label.TextSize         = 12
    Label.TextXAlignment   = Enum.TextXAlignment.Left
    Label.Parent           = Frame

    local ToggleBtn = Instance.new("Frame")
    ToggleBtn.Size             = UDim2.new(0, 32, 0, 16)
    ToggleBtn.Position         = UDim2.new(1, -46, 0.5, -8)
    ToggleBtn.BackgroundColor3 = default and Colors.Accent or Color3.fromRGB(45, 45, 50)
    ToggleBtn.BorderSizePixel  = 0
    ToggleBtn.Parent           = Frame
    Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(1, 0)

    local Knob = Instance.new("Frame")
    Knob.Size             = UDim2.new(0, 12, 0, 12)
    Knob.Position         = default and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
    Knob.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
    Knob.BorderSizePixel  = 0
    Knob.Parent           = ToggleBtn
    Instance.new("UICorner", Knob).CornerRadius = UDim.new(1, 0)

    local Click = Instance.new("TextButton")
    Click.Size                 = UDim2.new(1, 0, 1, 0)
    Click.BackgroundTransparency = 1
    Click.Text                 = ""
    Click.AutoButtonColor      = false
    Click.Parent               = Frame

    local State = default
    Click.MouseButton1Click:Connect(function()
        State = not State
        ToggleBtn.BackgroundColor3 = State and Colors.Accent or Color3.fromRGB(45, 45, 50)
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
    Frame.Size             = UDim2.new(1, -8, 0, 48)
    Frame.BackgroundColor3 = Colors.BackgroundHover
    Frame.BorderSizePixel  = 0
    Frame.Parent           = parent
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 4)

    local Label = Instance.new("TextLabel")
    Label.Size             = UDim2.new(1, -20, 0, 20)
    Label.Position         = UDim2.new(0, 14, 0, 4)
    Label.BackgroundTransparency = 1
    Label.Text             = text .. ": " .. string.format("%.2f", default)
    Label.TextColor3       = Colors.Text
    Label.Font             = Enum.Font.Gotham
    Label.TextSize         = 12
    Label.TextXAlignment   = Enum.TextXAlignment.Left
    Label.Parent           = Frame

    local Track = Instance.new("Frame")
    Track.Size             = UDim2.new(1, -28, 0, 3)
    Track.Position         = UDim2.new(0, 14, 0, 34)
    Track.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
    Track.BorderSizePixel  = 0
    Track.Parent           = Frame
    Instance.new("UICorner", Track).CornerRadius = UDim.new(1, 0)

    local Fill = Instance.new("Frame")
    Fill.Size             = UDim2.new((default - min) / (max - min), 0, 1, 0)
    Fill.BackgroundColor3 = Colors.Accent
    Fill.BorderSizePixel  = 0
    Fill.Parent           = Track
    Instance.new("UICorner", Fill).CornerRadius = UDim.new(1, 0)

    local Sliding = false
    local function Update(inputPos)
        local Percent = math.clamp((inputPos.Position.X - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
        local Value = min + ((max - min) * Percent)
        if (max - min) <= 1 then
            Value = math.floor(Value * 100) / 100
        else
            Value = math.floor(Value)
        end
        Fill.Size  = UDim2.new(Percent, 0, 1, 0)
        Label.Text = text .. ": " .. string.format("%.2f", Value)
        callback(Value)
    end

    Frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            Sliding = true
            Update(input)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if Sliding and input.UserInputType == Enum.UserInputType.MouseMovement then
            Update(input)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            Sliding = false
        end
    end)
end

local function CreateDropdown(parent, text, options, default, callback)
    local Button = Instance.new("TextButton")
    Button.Size             = UDim2.new(1, -8, 0, 36)
    Button.BackgroundColor3 = Colors.BackgroundHover
    Button.BorderSizePixel  = 0
    Button.Text             = "  " .. text .. "   >   " .. (default or options[1])
    Button.TextColor3       = Colors.Text
    Button.Font             = Enum.Font.Gotham
    Button.TextSize         = 12
    Button.TextXAlignment   = Enum.TextXAlignment.Left
    Button.AutoButtonColor  = false
    Button.Parent           = parent
    Instance.new("UICorner", Button).CornerRadius = UDim.new(0, 4)

    local Padding = Instance.new("UIPadding")
    Padding.PaddingLeft = UDim.new(0, 8)
    Padding.Parent      = Button

    Button.MouseEnter:Connect(function()
        Button.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
    end)
    Button.MouseLeave:Connect(function()
        Button.BackgroundColor3 = Colors.BackgroundHover
    end)

    local Index = 1
    for i, opt in ipairs(options) do
        if opt == (default or options[1]) then
            Index = i
            break
        end
    end

    Button.MouseButton1Click:Connect(function()
        Index = Index + 1
        if Index > #options then Index = 1 end
        Button.Text = "  " .. text .. "   >   " .. options[Index]
        callback(options[Index])
    end)
end

local TriggerPage = CreatePage("Trigger")
local HitboxPage  = CreatePage("Hitbox")
local PlayersPage = CreatePage("Players")
local ESPPage     = CreatePage("Visual")
local InfoPage    = CreatePage("Info")

-- TRIGGER
CreateToggle(TriggerPage, "Enable Triggerbot", Config.Trigger.Active, function(val) Config.Trigger.Active = val end)
CreateDropdown(TriggerPage, "Target Mode", {"Player", "Hitbox"}, "Player", function(val) Config.Trigger.Mode = val end)
CreateSlider(TriggerPage, "Radius", 0, 200, Config.Trigger.Radius, function(val) Config.Trigger.Radius = val end)
CreateSlider(TriggerPage, "Max Distance", 0, 200, Config.Trigger.MaxDist, function(val) Config.Trigger.MaxDist = val end)
CreateToggle(TriggerPage, "Wall Check", Config.Trigger.WallCheck, function(val) Config.Trigger.WallCheck = val end)

-- HITBOX
CreateToggle(HitboxPage, "Enable Hitbox Expander", Config.Hitbox.Enabled, function(val)
    Config.Hitbox.Enabled = val
    HitboxExpander:SetEnabled(val)
end)

CreateSlider(HitboxPage, "Hitbox X-Size (1-100)", 1, 100, Config.Hitbox.SizeX, function(val)
    Config.Hitbox.SizeX = val
    HBConfig.Size = Vector3.new(val, Config.Hitbox.SizeY, Config.Hitbox.SizeZ)
    HitboxExpander:SetSize(HBConfig.Size)
end)

CreateSlider(HitboxPage, "Hitbox Y-Size (1-100)", 1, 100, Config.Hitbox.SizeY, function(val)
    Config.Hitbox.SizeY = val
    HBConfig.Size = Vector3.new(Config.Hitbox.SizeX, val, Config.Hitbox.SizeZ)
    HitboxExpander:SetSize(HBConfig.Size)
end)

CreateSlider(HitboxPage, "Hitbox Z-Size (1-100)", 1, 100, Config.Hitbox.SizeZ, function(val)
    Config.Hitbox.SizeZ = val
    HBConfig.Size = Vector3.new(Config.Hitbox.SizeX, Config.Hitbox.SizeY, val)
    HitboxExpander:SetSize(HBConfig.Size)
end)

CreateSlider(HitboxPage, "Transparency", 0, 1, Config.Hitbox.Transparency, function(val)
    Config.Hitbox.Transparency = val
    HitboxExpander:SetTransparency(val)
end)

CreateToggle(HitboxPage, "Only Target", Config.Hitbox.OnlyTarget, function(val)
    Config.Hitbox.OnlyTarget = val
    HitboxExpander:SetOnlyTarget(val)
end)

-- PLAYERS
PlayersPage.ScrollingEnabled = false
PlayersPage.CanvasSize       = UDim2.new(0, 0, 0, 0)
PlayersPage.AutomaticCanvasSize = Enum.AutomaticSize.None

for _, child in ipairs(PlayersPage:GetChildren()) do
    if child:IsA("UIListLayout") then
        child:Destroy()
    end
end

CreateToggle(PlayersPage, "Target All Players", Config.Targeting.TargetAll, function(val)
    Config.Targeting.TargetAll = val
end)

local headerFrame = Instance.new("Frame")
headerFrame.Size             = UDim2.new(1, -8, 0, 32)
headerFrame.Position         = UDim2.new(0, 4, 0, 42)
headerFrame.BackgroundColor3 = Colors.BackgroundHover
headerFrame.BorderSizePixel  = 0
headerFrame.Parent           = PlayersPage
Instance.new("UICorner", headerFrame).CornerRadius = UDim.new(0, 4)

local playerCountLabel = Instance.new("TextLabel")
playerCountLabel.Size             = UDim2.new(1, -20, 1, 0)
playerCountLabel.Position         = UDim2.new(0, 14, 0, 0)
playerCountLabel.BackgroundTransparency = 1
playerCountLabel.Font             = Enum.Font.GothamBold
playerCountLabel.Text             = "Players - " .. #Players:GetPlayers()
playerCountLabel.TextColor3       = Colors.Text
playerCountLabel.TextSize         = 12
playerCountLabel.TextXAlignment   = Enum.TextXAlignment.Left
playerCountLabel.Parent           = headerFrame

local searchFrame = Instance.new("Frame")
searchFrame.Size             = UDim2.new(1, -8, 0, 34)
searchFrame.Position         = UDim2.new(0, 4, 0, 78)
searchFrame.BackgroundColor3 = Colors.BackgroundHover
searchFrame.BorderSizePixel  = 0
searchFrame.Parent           = PlayersPage
Instance.new("UICorner", searchFrame).CornerRadius = UDim.new(0, 4)

local searchBox = Instance.new("TextBox")
searchBox.Size                 = UDim2.new(1, -16, 1, -8)
searchBox.Position             = UDim2.new(0, 8, 0, 4)
searchBox.BackgroundColor3     = Colors.BackgroundInput
searchBox.BorderSizePixel      = 0
searchBox.Font                 = Enum.Font.Gotham
searchBox.PlaceholderText      = "Search player..."
searchBox.Text                 = Config.Targeting.SearchQuery
searchBox.TextColor3           = Colors.Text
searchBox.PlaceholderColor3    = Colors.TextMuted
searchBox.TextSize             = 12
searchBox.TextXAlignment       = Enum.TextXAlignment.Left
searchBox.ClearTextOnFocus     = false
searchBox.Parent               = searchFrame
Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 4)

local playersContainer = Instance.new("ScrollingFrame")
playersContainer.Size                 = UDim2.new(1, -8, 1, -120)
playersContainer.Position             = UDim2.new(0, 4, 0, 118)
playersContainer.BackgroundTransparency = 1
playersContainer.BorderSizePixel      = 0
playersContainer.ScrollBarThickness   = 2
playersContainer.ScrollBarImageColor3 = Colors.Accent
playersContainer.CanvasSize           = UDim2.new(0, 0, 0, 0)
playersContainer.AutomaticCanvasSize  = Enum.AutomaticSize.Y
playersContainer.Parent               = PlayersPage

local playersLayout = Instance.new("UIListLayout")
playersLayout.SortOrder = Enum.SortOrder.Name
playersLayout.Padding   = UDim.new(0, 5)
playersLayout.Parent    = playersContainer

local function createPlayerEntry(player)
    local query = searchBox.Text:lower()
    if query ~= "" then
        if not player.Name:lower():find(query) and not player.DisplayName:lower():find(query) then
            return
        end
    end

    local playerFrame = Instance.new("Frame")
    playerFrame.Name             = player.Name
    playerFrame.Size             = UDim2.new(1, 0, 0, 54)
    playerFrame.BackgroundColor3 = Colors.BackgroundHover
    playerFrame.BorderSizePixel  = 0
    playerFrame.Parent           = playersContainer
    Instance.new("UICorner", playerFrame).CornerRadius = UDim.new(0, 4)

    local displayNameLabel = Instance.new("TextLabel")
    displayNameLabel.Size             = UDim2.new(0.5, -60, 0, 16)
    displayNameLabel.Position         = UDim2.new(0, 14, 0, 8)
    displayNameLabel.BackgroundTransparency = 1
    displayNameLabel.Font             = Enum.Font.GothamBold
    displayNameLabel.Text             = player.DisplayName
    displayNameLabel.TextColor3       = Colors.Text
    displayNameLabel.TextSize         = 12
    displayNameLabel.TextXAlignment   = Enum.TextXAlignment.Left
    displayNameLabel.TextTruncate     = Enum.TextTruncate.AtEnd
    displayNameLabel.Parent           = playerFrame

    local usernameLabel = Instance.new("TextLabel")
    usernameLabel.Size             = UDim2.new(0.5, -60, 0, 14)
    usernameLabel.Position         = UDim2.new(0, 14, 0, 28)
    usernameLabel.BackgroundTransparency = 1
    usernameLabel.Font             = Enum.Font.Gotham
    usernameLabel.Text             = "@" .. player.Name
    usernameLabel.TextColor3       = Colors.TextMuted
    usernameLabel.TextSize         = 10
    usernameLabel.TextXAlignment   = Enum.TextXAlignment.Left
    usernameLabel.TextTruncate     = Enum.TextTruncate.AtEnd
    usernameLabel.Parent           = playerFrame

    local currentRole = Config.Targeting.PlayerRoles[player.UserId] or "Neutral"

    local roles = {
        {name = "Target",    color = Color3.fromRGB(200, 40, 40)},
        {name = "Whitelist", color = Color3.fromRGB(50, 160, 90)},
        {name = "Neutral",   color = Color3.fromRGB(70, 70, 75)}
    }

    for i, role in ipairs(roles) do
        local roleButton = Instance.new("TextButton")
        roleButton.Size             = UDim2.new(0, 68, 0, 24)
        roleButton.Position         = UDim2.new(1, -74 - ((3 - i) * 74), 0.5, -12)
        roleButton.BackgroundColor3 = currentRole == role.name and role.color or Color3.fromRGB(35, 35, 40)
        roleButton.BorderSizePixel  = 0
        roleButton.Font             = Enum.Font.GothamBold
        roleButton.Text             = role.name
        roleButton.TextColor3       = currentRole == role.name and Color3.new(1, 1, 1) or Colors.TextMuted
        roleButton.TextSize         = 10
        roleButton.AutoButtonColor  = false
        roleButton.Parent           = playerFrame
        Instance.new("UICorner", roleButton).CornerRadius = UDim.new(0, 3)

        roleButton.MouseButton1Click:Connect(function()
            Config.Targeting.PlayerRoles[player.UserId] = role.name
            HB_PlayerRoles[player.UserId] = role.name

            for _, btn in ipairs(playerFrame:GetChildren()) do
                if btn:IsA("TextButton") then
                    local isActive = btn.Text == role.name
                    local btnRole
                    for _, r in ipairs(roles) do
                        if r.name == btn.Text then
                            btnRole = r
                            break
                        end
                    end
                    if btnRole then
                        btn.BackgroundColor3 = isActive and btnRole.color or Color3.fromRGB(35, 35, 40)
                        btn.TextColor3       = isActive and Color3.new(1, 1, 1) or Colors.TextMuted
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

    playerCountLabel.Text = "Players - " .. #Players:GetPlayers()
end

local searchDebounce = 0
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    Config.Targeting.SearchQuery = searchBox.Text
    searchDebounce = tick()
    task.delay(0.15, function()
        if tick() - searchDebounce >= 0.14 then
            refreshPlayerList()
        end
    end)
end)

Players.PlayerAdded:Connect(function()
    task.wait(0.5)
    refreshPlayerList()
end)

Players.PlayerRemoving:Connect(function(player)
    Config.Targeting.PlayerRoles[player.UserId] = nil
    HB_PlayerRoles[player.UserId] = nil
    task.wait(0.5)
    refreshPlayerList()
end)

refreshPlayerList()

-- VISUAL
CreateToggle(ESPPage, "Only Target", Config.ESP.OnlyTarget, function(val) Config.ESP.OnlyTarget = val end)
CreateToggle(ESPPage, "Name ESP", Config.ESP.Name.Enabled, function(val) Config.ESP.Name.Enabled = val end)
CreateToggle(ESPPage, "Show Distance", Config.ESP.Name.ShowDistance, function(val) Config.ESP.Name.ShowDistance = val end)
CreateToggle(ESPPage, "Box ESP", Config.ESP.Box.Enabled, function(val) Config.ESP.Box.Enabled = val end)
CreateToggle(ESPPage, "Chams", Config.ESP.Chams.Enabled, function(val) Config.ESP.Chams.Enabled = val end)
CreateSlider(ESPPage, "Chams Transparency", 0, 1, Config.ESP.Chams.Transparency, function(val)
    Config.ESP.Chams.Transparency = val
end)
CreateToggle(ESPPage, "Healthbar", Config.ESP.Healthbar.Enabled, function(val) Config.ESP.Healthbar.Enabled = val end)
CreateToggle(ESPPage, "Tool ESP", Config.ESP.Tool.Enabled, function(val) Config.ESP.Tool.Enabled = val end)

-- INFO
local InfoScroll = Instance.new("ScrollingFrame")
InfoScroll.Size                 = UDim2.new(1, 0, 1, 0)
InfoScroll.BackgroundTransparency = 1
InfoScroll.ScrollBarThickness   = 2
InfoScroll.ScrollBarImageColor3 = Colors.Accent
InfoScroll.CanvasSize           = UDim2.new(0, 0, 0, 0)
InfoScroll.AutomaticCanvasSize  = Enum.AutomaticSize.Y
InfoScroll.Parent               = InfoPage

local InfoLayout = Instance.new("UIListLayout")
InfoLayout.Padding            = UDim.new(0, 6)
InfoLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
InfoLayout.Parent              = InfoScroll

local function CreateDevCard(parent, userId, username, role)
    local Card = Instance.new("Frame")
    Card.Size             = UDim2.new(1, -8, 0, 88)
    Card.BackgroundColor3 = Colors.BackgroundHover
    Card.BorderSizePixel  = 0
    Card.Parent           = parent
    Instance.new("UICorner", Card).CornerRadius = UDim.new(0, 4)

    local Avatar = Instance.new("ImageLabel")
    Avatar.Size             = UDim2.new(0, 64, 0, 64)
    Avatar.Position         = UDim2.new(0, 12, 0.5, -32)
    Avatar.BackgroundColor3 = Colors.BackgroundInput
    Avatar.Image            = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. userId .. "&width=200&height=200&format=png"
    Avatar.Parent           = Card
    Instance.new("UICorner", Avatar).CornerRadius = UDim.new(0, 4)

    local NameLabel = Instance.new("TextLabel")
    NameLabel.Size             = UDim2.new(1, -96, 0, 18)
    NameLabel.Position         = UDim2.new(0, 88, 0, 16)
    NameLabel.BackgroundTransparency = 1
    NameLabel.Text             = username
    NameLabel.TextColor3       = Colors.Text
    NameLabel.Font             = Enum.Font.GothamBold
    NameLabel.TextSize         = 12
    NameLabel.TextXAlignment   = Enum.TextXAlignment.Left
    NameLabel.Parent           = Card

    local RoleLabel = Instance.new("TextLabel")
    RoleLabel.Size             = UDim2.new(1, -96, 0, 14)
    RoleLabel.Position         = UDim2.new(0, 88, 0, 36)
    RoleLabel.BackgroundTransparency = 1
    RoleLabel.Text             = role
    RoleLabel.TextColor3       = Colors.Accent
    RoleLabel.Font             = Enum.Font.GothamBold
    RoleLabel.TextSize         = 10
    RoleLabel.TextXAlignment   = Enum.TextXAlignment.Left
    RoleLabel.Parent           = Card

    local IDLabel = Instance.new("TextLabel")
    IDLabel.Size             = UDim2.new(1, -96, 0, 14)
    IDLabel.Position         = UDim2.new(0, 88, 0, 54)
    IDLabel.BackgroundTransparency = 1
    IDLabel.Text             = "ID - " .. userId
    IDLabel.TextColor3       = Colors.TextMuted
    IDLabel.Font             = Enum.Font.Gotham
    IDLabel.TextSize         = 10
    IDLabel.TextXAlignment   = Enum.TextXAlignment.Left
    IDLabel.Parent           = Card
end

CreateDevCard(InfoScroll, "10556454097", "wyv(bewit0b285)",  "LEAD SCRIPTER")
CreateDevCard(InfoScroll, "9398850460",  "wyvy(Bear_Star53)", "LEAD TESTER")
CreateDevCard(InfoScroll, "123456789",   "?????(??????)",     "AVERON OWNER")

-- ============================================================
-- SHARED HELPERS
-- ============================================================
local function GetTargetPart(character)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp then return hrp end
    local parts = {"Torso", "UpperTorso", "LowerTorso", "HumanoidRootPart"}
    for _, name in ipairs(parts) do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") then return part end
    end
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("BasePart") then return child end
    end
    return nil
end

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

local function GetPlayerRole(player)
    return Config.Targeting.PlayerRoles[player.UserId] or "Neutral"
end

local function CanESPTarget(player, onlyTargetMode)
    local role = GetPlayerRole(player)
    if role == "Whitelist" then return false end
    if role == "Target" then return true end
    if role == "Neutral" then return not onlyTargetMode end
    return false
end

-- ============================================================
-- ESP
-- ============================================================
local function CreateESP(player)
    if ESPObjects[player] then return end

    local espFolder = Instance.new("Folder")
    espFolder.Name   = "ESP_" .. player.Name
    espFolder.Parent = CoreGui

    ESPObjects[player] = {
        Folder    = espFolder,
        Name      = nil,
        Box       = {},
        Chams     = {},
        Healthbar = {},
        Tool      = nil
    }

    local nameLabel = Instance.new("BillboardGui")
    nameLabel.Name         = "NameESP"
    nameLabel.AlwaysOnTop  = true
    nameLabel.Size         = UDim2.new(0, 100, 0, 30)
    nameLabel.StudsOffset  = Vector3.new(0, 3, 0)
    nameLabel.Parent       = espFolder

    local nameText = Instance.new("TextLabel")
    nameText.Size                = UDim2.new(1, 0, 1, 0)
    nameText.BackgroundTransparency = 1
    nameText.Font                = Enum.Font.GothamBold
    nameText.TextSize            = 14
    nameText.TextColor3          = ESPWhite
    nameText.TextStrokeColor3    = Color3.new(0, 0, 0)
    nameText.TextStrokeTransparency = 0.5
    nameText.Parent              = nameLabel

    ESPObjects[player].Name = nameLabel

    local toolLabel = Instance.new("BillboardGui")
    toolLabel.Name         = "ToolESP"
    toolLabel.AlwaysOnTop  = true
    toolLabel.Size         = UDim2.new(0, 100, 0, 20)
    toolLabel.StudsOffset  = Vector3.new(0, -3, 0)
    toolLabel.Parent       = espFolder

    local toolText = Instance.new("TextLabel")
    toolText.Size                = UDim2.new(1, 0, 1, 0)
    toolText.BackgroundTransparency = 1
    toolText.Font                = Enum.Font.GothamBold
    toolText.TextSize            = 12
    toolText.TextColor3          = ESPWhite
    toolText.TextStrokeTransparency = 0.5
    toolText.Parent              = toolLabel

    ESPObjects[player].Tool = toolLabel
end

local function RemoveESP(player)
    if not ESPObjects[player] then return end

    if ESPObjects[player].Folder then
        ESPObjects[player].Folder:Destroy()
    end

    if ESPObjects[player].Chams then
        for _, hl in pairs(ESPObjects[player].Chams) do
            if hl and hl.Parent then hl:Destroy() end
        end
    end

    if player.Character then
        local chams = player.Character:FindFirstChild("averon_Chams")
        if chams then chams:Destroy() end
    end

    ESPObjects[player] = nil
end

local function CreateBox(player)
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
    boxGui.Name        = "BoxESP"
    boxGui.Adornee     = hrp
    boxGui.Size        = UDim2.new(4, 0, 5, 0)
    boxGui.AlwaysOnTop = true
    boxGui.Parent      = ESPObjects[player].Folder

    local topLine = Instance.new("Frame")
    topLine.Size             = UDim2.new(1, 0, 0, 2)
    topLine.Position         = UDim2.new(0, 0, 0, 0)
    topLine.BackgroundColor3 = ESPWhite
    topLine.BorderSizePixel  = 0
    topLine.Parent           = boxGui

    local bottomLine = Instance.new("Frame")
    bottomLine.Size             = UDim2.new(1, 0, 0, 2)
    bottomLine.Position         = UDim2.new(0, 0, 1, -2)
    bottomLine.BackgroundColor3 = ESPWhite
    bottomLine.BorderSizePixel  = 0
    bottomLine.Parent           = boxGui

    local leftLine = Instance.new("Frame")
    leftLine.Size             = UDim2.new(0, 2, 1, 0)
    leftLine.Position         = UDim2.new(0, 0, 0, 0)
    leftLine.BackgroundColor3 = ESPWhite
    leftLine.BorderSizePixel  = 0
    leftLine.Parent           = boxGui

    local rightLine = Instance.new("Frame")
    rightLine.Size             = UDim2.new(0, 2, 1, 0)
    rightLine.Position         = UDim2.new(1, -2, 0, 0)
    rightLine.BackgroundColor3 = ESPWhite
    rightLine.BorderSizePixel  = 0
    rightLine.Parent           = boxGui

    ESPObjects[player].Box = {boxGui, topLine, bottomLine, leftLine, rightLine}
end

local function CreateHealthbar(player)
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
    healthGui.Name        = "HealthbarESP"
    healthGui.Adornee     = hrp
    healthGui.Size        = UDim2.new(0, 4, 5, 0)
    healthGui.StudsOffset = Vector3.new(-2.5, 0, 0)
    healthGui.AlwaysOnTop = true
    healthGui.Parent      = ESPObjects[player].Folder

    local bg = Instance.new("Frame")
    bg.Size                 = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3     = Color3.new(0, 0, 0)
    bg.BackgroundTransparency = 0.5
    bg.BorderSizePixel      = 0
    bg.Parent               = healthGui

    local fill = Instance.new("Frame")
    fill.Size             = UDim2.new(1, 0, 1, 0)
    fill.Position         = UDim2.new(0, 0, 1, 0)
    fill.AnchorPoint      = Vector2.new(0, 1)
    fill.BackgroundColor3 = ESPWhite
    fill.BorderSizePixel  = 0
    fill.Parent           = healthGui

    local outline = Instance.new("UIStroke")
    outline.Color     = Color3.new(0, 0, 0)
    outline.Thickness = 1
    outline.Parent    = bg

    ESPObjects[player].Healthbar = {healthGui, bg, fill, outline}
end

local function ApplyChams(player)
    local character = player.Character
    if not character then return end
    if not ESPObjects[player] then CreateESP(player) end

    local existing = character:FindFirstChild("averon_Chams")
    if not existing then
        existing = Instance.new("Highlight")
        existing.Name   = "averon_Chams"
        existing.Parent = character
        table.insert(ESPObjects[player].Chams, existing)
    end

    existing.FillColor          = ESPWhite
    existing.OutlineColor       = ESPWhite
    existing.FillTransparency   = Config.ESP.Chams.Transparency
    existing.OutlineTransparency = 0
    existing.Adornee            = character
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
    local camera = workspace.CurrentCamera
    if not camera then return end

    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end

        local character = player.Character
        if not character then RemoveESP(player); continue end

        local hrp = GetTargetPart(character)
        if not hrp then RemoveESP(player); continue end

        if not CanESPTarget(player, Config.ESP.OnlyTarget) then
            RemoveESP(player); continue
        end

        if not IsPlayerAlive(player) or IsPlayerKO(player) then
            RemoveESP(player); continue
        end

        if not ESPObjects[player] then CreateESP(player) end

        local distance = (camera.CFrame.Position - hrp.Position).Magnitude
        local screenPos, onScreen = camera:WorldToViewportPoint(hrp.Position)

        if Config.ESP.Name.Enabled and ESPObjects[player].Name then
            ESPObjects[player].Name.Enabled = onScreen
            ESPObjects[player].Name.Adornee = hrp
            local nameText = ESPObjects[player].Name:FindFirstChild("TextLabel")
            if nameText then
                nameText.Text = Config.ESP.Name.ShowDistance
                    and (player.DisplayName .. " [" .. math.floor(distance) .. "m]")
                    or player.DisplayName
                nameText.TextColor3          = ESPWhite
                nameText.TextStrokeTransparency = 0.5
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
                    toolText.Text      = "[" .. tool.Name .. "]"
                    toolText.TextColor3 = ESPWhite
                end
            else
                ESPObjects[player].Tool.Enabled = false
            end
        elseif ESPObjects[player].Tool then
            ESPObjects[player].Tool.Enabled = false
        end

        if Config.ESP.Box.Enabled then
            if #ESPObjects[player].Box == 0 or not ESPObjects[player].Box[1] then
                CreateBox(player)
            end
            if ESPObjects[player].Box[1] and onScreen then
                for i = 2, #ESPObjects[player].Box do
                    local line = ESPObjects[player].Box[i]
                    if line then line.BackgroundColor3 = ESPWhite end
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
                existing.FillColor    = ESPWhite
                existing.OutlineColor = ESPWhite
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
                local healthPercent = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
                local fill = ESPObjects[player].Healthbar[3]
                if fill then
                    ESPObjects[player].Healthbar[1].Enabled = true
                    fill.Size             = UDim2.new(1, 0, healthPercent, 0)
                    fill.BackgroundColor3 = ESPWhite
                end
            else
                if ESPObjects[player].Healthbar[1] then
                    ESPObjects[player].Healthbar[1].Enabled = false
                end
            end
        else
            if ESPObjects[player].Healthbar[1] then
                ESPObjects[player].Healthbar[1].Enabled = false
            end
        end
    end
end

Players.PlayerRemoving:Connect(function(player)
    RemoveESP(player)
end)

-- ============================================================
-- TRIGGERBOT
-- ============================================================
local function Get2DBoundingBox(part, camera)
    local size = part.Size
    local cf = part.CFrame
    local corners = {
        cf:PointToWorldSpace(Vector3.new(-size.X / 2, -size.Y / 2, -size.Z / 2)),
        cf:PointToWorldSpace(Vector3.new( size.X / 2, -size.Y / 2, -size.Z / 2)),
        cf:PointToWorldSpace(Vector3.new(-size.X / 2,  size.Y / 2, -size.Z / 2)),
        cf:PointToWorldSpace(Vector3.new( size.X / 2,  size.Y / 2, -size.Z / 2)),
        cf:PointToWorldSpace(Vector3.new(-size.X / 2, -size.Y / 2,  size.Z / 2)),
        cf:PointToWorldSpace(Vector3.new( size.X / 2, -size.Y / 2,  size.Z / 2)),
        cf:PointToWorldSpace(Vector3.new(-size.X / 2,  size.Y / 2,  size.Z / 2)),
        cf:PointToWorldSpace(Vector3.new( size.X / 2,  size.Y / 2,  size.Z / 2))
    }
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, corner in ipairs(corners) do
        local screenPos, onScreen = camera:WorldToViewportPoint(corner)
        if onScreen then
            minX = math.min(minX, screenPos.X)
            minY = math.min(minY, screenPos.Y)
            maxX = math.max(maxX, screenPos.X)
            maxY = math.max(maxY, screenPos.Y)
        end
    end
    if minX == math.huge then return nil end
    return minX, minY, maxX, maxY
end

local function IsMouseOverPlayer(player, mousePos, camera, ignoreList)
    local char = player.Character
    if not char then return false end
    local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignoreList
    local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
    if result and result.Instance then
        if result.Instance:IsDescendantOf(char) then
            return true
        end
    end
    return false
end

local function IsHoldingKnife()
    local char = LocalPlayer.Character
    if not char then return false end
    for _, child in pairs(char:GetChildren()) do
        if child:IsA("Tool") and string.find(child.Name:lower(), "knife") then
            return true
        end
    end
    return false
end

RunService.RenderStepped:Connect(function()
    UpdateESP()

    if not Config.Trigger.Active then return end
    if IsHoldingKnife() then return end
    if (tick() - Config.Trigger.LastShot) < Config.Trigger.Delay then return end

    local currentCamera = workspace.CurrentCamera
    if not currentCamera then return end

    local mousePos = UserInputService:GetMouseLocation()
    local targetPlayer = nil
    local closestDist  = math.huge

    local baseIgnore = {LocalPlayer.Character}
    if LocalPlayer.Character then
        for _, child in ipairs(LocalPlayer.Character:GetChildren()) do
            if child:IsA("Tool") then table.insert(baseIgnore, child) end
        end
    end

    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local role = Config.Targeting.PlayerRoles[player.UserId]
        if role == "Whitelist" then continue end
        if not Config.Targeting.TargetAll and role ~= "Target" then continue end
        if not IsPlayerAlive(player) then continue end
        if IsPlayerKO(player) then continue end
        local char = player.Character
        if not char then continue end
        local targetPart = GetTargetPart(char)
        if not targetPart then continue end
        local distance = (currentCamera.CFrame.Position - targetPart.Position).Magnitude
        if distance > Config.Trigger.MaxDist then continue end
        local ignoreList = table.clone(baseIgnore)
        local isOnTarget = false
        if Config.Trigger.Mode == "Player" then
            if IsMouseOverPlayer(player, mousePos, currentCamera, ignoreList) then
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
                        local ray = Ray.new(currentCamera.CFrame.Position, dir * distance)
                        local hit = workspace:FindPartOnRayWithIgnoreList(ray, ignoreList)
                        if hit then
                            local hitPlayer = Players:GetPlayerFromCharacter(hit:FindFirstAncestorOfClass("Model"))
                            if hitPlayer == player then isOnTarget = true end
                        end
                    else
                        isOnTarget = true
                    end
                end
            end
        end
        if isOnTarget then
            local screenPos  = currentCamera:WorldToViewportPoint(targetPart.Position)
            local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
            if screenDist < closestDist then
                targetPlayer = player
                closestDist  = screenDist
            end
        end
    end

    if targetPlayer then
        Config.Trigger.LastShot = tick()
        VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, true, game, 1)
        task.wait(0.01)
        VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, false, game, 1)
    end
end)

-- ============================================================
-- MENU ANIM
-- ============================================================
local MENU_SIZE   = UDim2.new(0, 520, 0, 640)
local MENU_HIDDEN = UDim2.new(0, 0, 0, 0)
local IsOpen      = true
local Animating   = false

local openTweenInfo  = TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local closeTweenInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In)

local function OpenMenu()
    if IsOpen then return end
    IsOpen    = true
    Animating = true
    MainFrame.Visible = true
    MainFrame.Size    = MENU_HIDDEN
    local tween = TweenService:Create(MainFrame, openTweenInfo, { Size = MENU_SIZE })
    tween:Play()
    tween.Completed:Connect(function() Animating = false end)
end

local function CloseMenu()
    if not IsOpen then return end
    IsOpen    = false
    Animating = true
    local tween = TweenService:Create(MainFrame, closeTweenInfo, { Size = MENU_HIDDEN })
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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Config.MenuKey then
        ToggleMenu()
    end
end)

Pages[1].Visible                 = true
PageButtons[1].Button.TextColor3 = Colors.Text
PageButtons[1].Frame.BackgroundTransparency = 0
PageButtons[1].Indicator.Size    = UDim2.new(0, 3, 0, 20)
