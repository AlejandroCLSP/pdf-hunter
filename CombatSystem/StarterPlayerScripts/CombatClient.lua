-- LocalScript: Place inside StarterPlayer > StarterPlayerScripts
-- Name: CombatClient

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local player    = Players.LocalPlayer
local Config    = require(ReplicatedStorage:WaitForChild("CombatConfig"))

-- Wait for server to create the remotes folder
local Remotes           = ReplicatedStorage:WaitForChild("CombatRemotes")
local LightAttackEvent  = Remotes:WaitForChild("LightAttack")
local HeavyAttackEvent  = Remotes:WaitForChild("HeavyAttack")
local BlockEvent        = Remotes:WaitForChild("Block")
local UnblockEvent      = Remotes:WaitForChild("Unblock")
local HitFXEvent        = Remotes:WaitForChild("HitFX")
local StatsEvent        = Remotes:WaitForChild("UpdateStats")
local BlockBrokenEvent  = Remotes:WaitForChild("BlockBroken")

-- ── Local state ───────────────────────────────────────────────────────────────
local isBlocking        = false
local lastLightTime     = 0
local lastHeavyTime     = 0
local comboCount        = 0
local animTracks        = {}

-- ── Character / animator references ──────────────────────────────────────────
local character, humanoid, animator

local function bindCharacter(char)
    character = char
    humanoid  = char:WaitForChild("Humanoid")
    animator  = humanoid:WaitForChild("Animator")

    animTracks = {}
    for name, id in pairs(Config.Animations) do
        if id ~= "rbxassetid://0" then
            local anim = Instance.new("Animation")
            anim.AnimationId = id
            animTracks[name] = animator:LoadAnimation(anim)
        end
    end
end

bindCharacter(player.Character or player.CharacterAdded:Wait())
player.CharacterAdded:Connect(function(char)
    isBlocking  = false
    comboCount  = 0
    lastLightTime = 0
    lastHeavyTime = 0
    bindCharacter(char)
end)

local function playAnim(name)
    local track = animTracks[name]
    if track and not track.IsPlaying then track:Play() end
end

local function stopAnim(name)
    local track = animTracks[name]
    if track and track.IsPlaying then track:Stop() end
end

-- ══════════════════════════════════════════════════════════════════════════════
-- HUD
-- ══════════════════════════════════════════════════════════════════════════════
local gui = Instance.new("ScreenGui")
gui.Name           = "CombatHUD"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.Parent         = player.PlayerGui

-- ── helper: rounded frame ────────────────────────────────────────────────────
local function roundFrame(parent, size, pos, color, radius)
    local f = Instance.new("Frame")
    f.Size                  = size
    f.Position              = pos
    f.BackgroundColor3      = color
    f.BorderSizePixel       = 0
    f.Parent                = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 6)
    c.Parent = f
    return f
end

-- ── Health bar ───────────────────────────────────────────────────────────────
local HUD = roundFrame(gui,
    UDim2.new(0, 420, 0, 110),
    UDim2.new(0.5, -210, 1, -130),
    Color3.fromRGB(20, 20, 20), 10)
HUD.BackgroundTransparency = 0.35

local hpBG = roundFrame(HUD,
    UDim2.new(1, -20, 0, 30),
    UDim2.new(0, 10, 0, 10),
    Color3.fromRGB(40, 40, 40))

local hpBar = roundFrame(hpBG,
    UDim2.new(1, 0, 1, 0),
    UDim2.new(0, 0, 0, 0),
    Color3.fromRGB(215, 50, 50))

local hpLabel = Instance.new("TextLabel")
hpLabel.Size                = UDim2.new(1, 0, 1, 0)
hpLabel.BackgroundTransparency = 1
hpLabel.Text                = "HP  100 / 100"
hpLabel.TextColor3          = Color3.new(1, 1, 1)
hpLabel.TextScaled          = true
hpLabel.Font                = Enum.Font.GothamBold
hpLabel.ZIndex              = 5
hpLabel.Parent              = hpBG

-- ── Stamina bar ──────────────────────────────────────────────────────────────
local stBG = roundFrame(HUD,
    UDim2.new(1, -20, 0, 20),
    UDim2.new(0, 10, 0, 48),
    Color3.fromRGB(40, 40, 40))

local stBar = roundFrame(stBG,
    UDim2.new(1, 0, 1, 0),
    UDim2.new(0, 0, 0, 0),
    Color3.fromRGB(50, 200, 80))

local stLabel = Instance.new("TextLabel")
stLabel.Size                = UDim2.new(1, 0, 1, 0)
stLabel.BackgroundTransparency = 1
stLabel.Text                = "Stamina  100"
stLabel.TextColor3          = Color3.new(1, 1, 1)
stLabel.TextScaled          = true
stLabel.Font                = Enum.Font.Gotham
stLabel.ZIndex              = 5
stLabel.Parent              = stBG

-- ── Combo label ──────────────────────────────────────────────────────────────
local comboLabel = Instance.new("TextLabel")
comboLabel.Size                = UDim2.new(1, -20, 0, 32)
comboLabel.Position            = UDim2.new(0, 10, 0, 74)
comboLabel.BackgroundTransparency = 1
comboLabel.Text                = ""
comboLabel.TextColor3          = Color3.fromRGB(255, 215, 50)
comboLabel.TextScaled          = true
comboLabel.Font                = Enum.Font.GothamBold
comboLabel.ZIndex              = 5
comboLabel.Parent              = HUD

-- ── BLOCKING badge ────────────────────────────────────────────────────────────
local blockBadge = roundFrame(gui,
    UDim2.new(0, 140, 0, 36),
    UDim2.new(0.5, -70, 1, -50),
    Color3.fromRGB(40, 90, 200), 8)
blockBadge.BackgroundTransparency = 0.25
blockBadge.Visible = false

local blockText = Instance.new("TextLabel")
blockText.Size                = UDim2.new(1, 0, 1, 0)
blockText.BackgroundTransparency = 1
blockText.Text                = "BLOCKING"
blockText.TextColor3          = Color3.new(1, 1, 1)
blockText.TextScaled          = true
blockText.Font                = Enum.Font.GothamBold
blockText.Parent              = blockBadge

-- ── Controls hint ─────────────────────────────────────────────────────────────
local hintBG = roundFrame(gui,
    UDim2.new(0, 210, 0, 80),
    UDim2.new(0, 14, 1, -94),
    Color3.fromRGB(0, 0, 0), 8)
hintBG.BackgroundTransparency = 0.5

local hintText = Instance.new("TextLabel")
hintText.Size                = UDim2.new(1, -12, 1, -12)
hintText.Position            = UDim2.new(0, 6, 0, 6)
hintText.BackgroundTransparency = 1
hintText.Text                = "[ LMB ]  Light Attack / Combo\n[ RMB ]  Heavy Attack\n[ F ]      Block"
hintText.TextColor3          = Color3.fromRGB(220, 220, 220)
hintText.TextScaled          = true
hintText.Font                = Enum.Font.Gotham
hintText.TextXAlignment      = Enum.TextXAlignment.Left
hintText.Parent              = hintBG

-- ── GUARD BREAK flash ────────────────────────────────────────────────────────
local guardBreakLabel = Instance.new("TextLabel")
guardBreakLabel.Size                = UDim2.new(0, 260, 0, 50)
guardBreakLabel.Position            = UDim2.new(0.5, -130, 0.35, 0)
guardBreakLabel.BackgroundTransparency = 1
guardBreakLabel.Text                = "GUARD BROKEN!"
guardBreakLabel.TextColor3          = Color3.fromRGB(255, 60, 60)
guardBreakLabel.TextTransparency    = 1
guardBreakLabel.TextScaled          = true
guardBreakLabel.Font                = Enum.Font.GothamBold
guardBreakLabel.ZIndex              = 10
guardBreakLabel.Parent              = gui

-- ── HUD update functions ──────────────────────────────────────────────────────
local function setHP(hp)
    local ratio = math.clamp(hp / Config.MaxHealth, 0, 1)
    TweenService:Create(hpBar, TweenInfo.new(0.2), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
    hpLabel.Text = string.format("HP  %d / %d", math.floor(hp), Config.MaxHealth)

    if ratio > 0.5 then
        hpBar.BackgroundColor3 = Color3.fromRGB(215, 50, 50)
    elseif ratio > 0.25 then
        hpBar.BackgroundColor3 = Color3.fromRGB(215, 150, 30)
    else
        hpBar.BackgroundColor3 = Color3.fromRGB(170, 25, 25)
    end
end

local function setStamina(st)
    local ratio = math.clamp(st / Config.MaxStamina, 0, 1)
    TweenService:Create(stBar, TweenInfo.new(0.15), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
    stLabel.Text = string.format("Stamina  %d", math.floor(st))
    stBar.BackgroundColor3 = ratio < 0.25
        and Color3.fromRGB(200, 75, 50)
        or  Color3.fromRGB(50, 200, 80)
end

local comboTween
local function setCombo(count)
    comboCount = count or 0
    if comboCount > 1 then
        comboLabel.Text = string.format("COMBO  x%d", comboCount)
        comboLabel.TextTransparency = 0
        if comboTween then comboTween:Cancel() end
        comboTween = TweenService:Create(comboLabel, TweenInfo.new(1.4), { TextTransparency = 1 })
        comboTween:Play()
    else
        comboLabel.Text = ""
    end
end

-- ── Hit VFX ───────────────────────────────────────────────────────────────────
local function spawnHitEffect(pos)
    if not pos then return end

    local spark = Instance.new("Part")
    spark.Size        = Vector3.new(0.4, 0.4, 0.4)
    spark.Position    = pos
    spark.Anchored    = true
    spark.CanCollide  = false
    spark.Material    = Enum.Material.Neon
    spark.Color       = Color3.fromRGB(255, 230, 80)
    spark.CastShadow  = false
    spark.Parent      = workspace

    -- Billboard "HIT!" popup
    local bb = Instance.new("BillboardGui")
    bb.Size         = UDim2.new(0, 70, 0, 35)
    bb.StudsOffset  = Vector3.new(0, 1.2, 0)
    bb.AlwaysOnTop  = true
    bb.Parent       = spark

    local lbl = Instance.new("TextLabel")
    lbl.Size                = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                = "HIT!"
    lbl.TextColor3          = Color3.fromRGB(255, 225, 50)
    lbl.TextScaled          = true
    lbl.Font                = Enum.Font.GothamBold
    lbl.Parent              = bb

    TweenService:Create(spark, TweenInfo.new(0.35), {
        Size         = Vector3.new(2, 2, 2),
        Transparency = 1,
    }):Play()

    game:GetService("Debris"):AddItem(spark, 0.4)
end

local function spawnBlockEffect(pos)
    if not pos then return end

    local ring = Instance.new("Part")
    ring.Size        = Vector3.new(1, 0.1, 1)
    ring.Position    = pos
    ring.Anchored    = true
    ring.CanCollide  = false
    ring.Material    = Enum.Material.Neon
    ring.Color       = Color3.fromRGB(80, 140, 255)
    ring.CastShadow  = false
    ring.Parent      = workspace

    TweenService:Create(ring, TweenInfo.new(0.3), {
        Size         = Vector3.new(5, 0.1, 5),
        Transparency = 1,
    }):Play()

    game:GetService("Debris"):AddItem(ring, 0.35)

    -- Flash the block badge red
    blockBadge.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
    task.delay(0.2, function()
        blockBadge.BackgroundColor3 = Color3.fromRGB(40, 90, 200)
    end)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Input
-- ══════════════════════════════════════════════════════════════════════════════
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    -- Light Attack  ──  Left Mouse Button
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        local now = tick()
        if isBlocking then return end
        if now - lastLightTime < Config.LightAttackCooldown then return end

        lastLightTime = now
        LightAttackEvent:FireServer()

        local animName = "LightAttack" .. tostring(
            (comboCount % Config.MaxComboCount) + 1
        )
        playAnim(animName)
    end

    -- Heavy Attack  ──  Right Mouse Button
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        local now = tick()
        if isBlocking then return end
        if now - lastHeavyTime < Config.HeavyAttackCooldown then return end

        lastHeavyTime = now
        HeavyAttackEvent:FireServer()
        playAnim("HeavyAttack")
    end

    -- Block  ──  F key
    if input.KeyCode == Enum.KeyCode.F then
        if isBlocking then return end
        isBlocking = true
        BlockEvent:FireServer()
        blockBadge.Visible = true
        playAnim("Block")
        if humanoid then humanoid.WalkSpeed = Config.BlockWalkSpeed end
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if input.KeyCode == Enum.KeyCode.F then
        isBlocking = false
        UnblockEvent:FireServer()
        blockBadge.Visible = false
        stopAnim("Block")
        if humanoid then humanoid.WalkSpeed = Config.NormalWalkSpeed end
    end
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- Server → Client events
-- ══════════════════════════════════════════════════════════════════════════════
StatsEvent.OnClientEvent:Connect(function(stats)
    if stats.health  ~= nil then setHP(stats.health)           end
    if stats.stamina ~= nil then setStamina(stats.stamina)     end
    if stats.combo   ~= nil then setCombo(stats.combo)         end

    -- Server forcibly removed block (guard break from stamina drain)
    if stats.blocking == false and isBlocking then
        isBlocking = false
        blockBadge.Visible = false
        stopAnim("Block")
        if humanoid then humanoid.WalkSpeed = Config.NormalWalkSpeed end
    end
end)

HitFXEvent.OnClientEvent:Connect(function(fxType, position)
    if fxType == "HitEffect"   then spawnHitEffect(position)  end
    if fxType == "BlockEffect" then spawnBlockEffect(position) end
end)

BlockBrokenEvent.OnClientEvent:Connect(function()
    isBlocking = false
    blockBadge.Visible = false
    stopAnim("Block")
    if humanoid then humanoid.WalkSpeed = Config.NormalWalkSpeed end

    -- "GUARD BROKEN!" flash on screen
    guardBreakLabel.TextTransparency = 0
    TweenService:Create(guardBreakLabel, TweenInfo.new(1.5, Enum.EasingStyle.Quad), {
        TextTransparency = 1,
    }):Play()
    playAnim("Stagger")
end)
