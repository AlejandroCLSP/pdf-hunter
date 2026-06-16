-- Script: Place inside ServerScriptService
-- Name: CombatServer

local Players       = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService    = game:GetService("RunService")
local Debris        = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("CombatConfig"))

-- ── Remote folder setup ───────────────────────────────────────────────────────
local Remotes = Instance.new("Folder")
Remotes.Name  = "CombatRemotes"
Remotes.Parent = ReplicatedStorage

local function makeEvent(name)
    local e = Instance.new("RemoteEvent")
    e.Name   = name
    e.Parent = Remotes
    return e
end

local LightAttackEvent  = makeEvent("LightAttack")
local HeavyAttackEvent  = makeEvent("HeavyAttack")
local BlockEvent        = makeEvent("Block")
local UnblockEvent      = makeEvent("Unblock")
local HitFXEvent        = makeEvent("HitFX")       -- tells clients to spawn VFX
local StatsEvent        = makeEvent("UpdateStats")  -- pushes HP/stamina/combo to owner
local BlockBrokenEvent  = makeEvent("BlockBroken")  -- guard-break notification

-- ── Per-player state ──────────────────────────────────────────────────────────
local playerData = {}

local function newData()
    return {
        stamina      = Config.MaxStamina,
        blocking     = false,
        comboCount   = 0,
        lastComboTime = 0,
        lastHitTime  = 0,
        lastLightTime = 0,
        lastHeavyTime = 0,
    }
end

local function getRoot(char)
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(char)
    return char and char:FindFirstChildWhichIsA("Humanoid")
end

-- ── Knockback ─────────────────────────────────────────────────────────────────
local function applyKnockback(targetChar, sourceChar, force)
    local targetRoot  = getRoot(targetChar)
    local sourceRoot  = getRoot(sourceChar)
    if not targetRoot or not sourceRoot then return end

    local dir = (targetRoot.Position - sourceRoot.Position)
    dir = Vector3.new(dir.X, 0, dir.Z).Unit

    local bv = Instance.new("BodyVelocity")
    bv.Velocity  = dir * force + Vector3.new(0, force * 0.25, 0)
    bv.MaxForce  = Vector3.new(1e5, 1e5, 1e5)
    bv.P         = 1e4
    bv.Parent    = targetRoot
    Debris:AddItem(bv, 0.18)
end

-- ── Hitbox detection ─────────────────────────────────────────────────────────
local function getHitTargets(attackerChar)
    local root = getRoot(attackerChar)
    if not root then return {} end

    local cf      = root.CFrame * CFrame.new(Config.HitboxOffset)
    local params  = OverlapParams.new()
    params.FilterDescendantsInstances = { attackerChar }
    params.FilterType = Enum.RaycastFilterType.Exclude

    local parts = workspace:GetPartBoundsInBox(cf, Config.HitboxSize, params)

    local seen, targets = {}, {}
    for _, part in ipairs(parts) do
        local model  = part:FindFirstAncestorWhichIsA("Model")
        local victim = model and Players:GetPlayerFromCharacter(model)
        if victim and not seen[victim] then
            seen[victim] = true
            table.insert(targets, victim)
        end
    end
    return targets
end

-- ── Damage application ────────────────────────────────────────────────────────
local function applyDamage(attacker, target, rawDamage, knockback)
    local attackerChar = attacker.Character
    local targetChar   = target.Character
    if not attackerChar or not targetChar then return end

    local humanoid = getHumanoid(targetChar)
    if not humanoid or humanoid.Health <= 0 then return end

    local data   = playerData[target]
    if not data  then return end

    local damage = rawDamage
    local blocked = data.blocking and data.stamina > 0

    if blocked then
        damage = rawDamage * (1 - Config.BlockedDamageReduction)
        data.stamina = math.max(0, data.stamina - Config.BlockStaminaOnHit)

        HitFXEvent:FireAllClients("BlockEffect", getRoot(targetChar).Position)

        -- Guard-break when stamina is empty
        if data.stamina <= 0 then
            data.blocking = false
            BlockBrokenEvent:FireClient(target)
        end
    else
        humanoid:TakeDamage(damage)
        data.lastHitTime = tick()
        applyKnockback(targetChar, attackerChar, knockback)
        HitFXEvent:FireAllClients("HitEffect", getRoot(targetChar).Position)
    end

    StatsEvent:FireClient(target, {
        health   = humanoid.Health,
        stamina  = data.stamina,
        blocking = data.blocking,
    })
end

-- ── Stat broadcast helper ─────────────────────────────────────────────────────
local function pushStats(player, extra)
    local char = player.Character
    local hp   = char and getHumanoid(char) and getHumanoid(char).Health or 0
    local data = playerData[player]
    if not data then return end

    local payload = {
        health   = hp,
        stamina  = data.stamina,
        combo    = data.comboCount,
        blocking = data.blocking,
    }
    if extra then
        for k, v in pairs(extra) do payload[k] = v end
    end
    StatsEvent:FireClient(player, payload)
end

-- ── Light Attack ─────────────────────────────────────────────────────────────
LightAttackEvent.OnServerEvent:Connect(function(player)
    local data = playerData[player]
    if not data then return end

    local now = tick()
    if now - data.lastLightTime < Config.LightAttackCooldown then return end
    if data.stamina < Config.LightAttackStaminaCost then return end
    if data.blocking then return end

    data.lastLightTime = now

    -- Combo tracking
    if now - data.lastComboTime > Config.ComboResetTime then
        data.comboCount = 0
    end
    data.comboCount   = math.min(data.comboCount + 1, Config.MaxComboCount)
    data.lastComboTime = now

    data.stamina = math.max(0, data.stamina - Config.LightAttackStaminaCost)

    local char = player.Character
    if not char then return end

    for _, target in ipairs(getHitTargets(char)) do
        local damage = Config.LightAttackDamage
        if data.comboCount >= Config.MaxComboCount then
            damage = damage * Config.FinalComboDamageMultiplier
        end
        applyDamage(player, target, damage, Config.LightKnockback)
    end

    pushStats(player)
end)

-- ── Heavy Attack ─────────────────────────────────────────────────────────────
HeavyAttackEvent.OnServerEvent:Connect(function(player)
    local data = playerData[player]
    if not data then return end

    local now = tick()
    if now - data.lastHeavyTime < Config.HeavyAttackCooldown then return end
    if data.stamina < Config.HeavyAttackStaminaCost then return end
    if data.blocking then return end

    data.lastHeavyTime = now
    data.lastLightTime = now  -- shares light cooldown slot to prevent overlap
    data.comboCount    = 0
    data.lastComboTime = 0

    data.stamina = math.max(0, data.stamina - Config.HeavyAttackStaminaCost)

    local char = player.Character
    if not char then return end

    for _, target in ipairs(getHitTargets(char)) do
        applyDamage(player, target, Config.HeavyAttackDamage, Config.HeavyKnockback)
    end

    pushStats(player)
end)

-- ── Block ─────────────────────────────────────────────────────────────────────
BlockEvent.OnServerEvent:Connect(function(player)
    local data = playerData[player]
    if data then data.blocking = true end
end)

UnblockEvent.OnServerEvent:Connect(function(player)
    local data = playerData[player]
    if data then data.blocking = false end
end)

-- ── Regen loop ────────────────────────────────────────────────────────────────
RunService.Heartbeat:Connect(function(dt)
    for player, data in pairs(playerData) do
        local char = player.Character
        if not char then continue end

        local humanoid = getHumanoid(char)
        if not humanoid then continue end

        -- Stamina regen (reduced while blocking)
        local sr = data.blocking and Config.StaminaRegen * 0.25 or Config.StaminaRegen
        data.stamina = math.min(Config.MaxStamina, data.stamina + sr * dt)

        -- Force-unblock if stamina is fully drained
        if data.blocking and data.stamina <= 0 then
            data.blocking = false
            BlockBrokenEvent:FireClient(player)
        end

        -- Passive health regen when out of combat long enough
        if tick() - data.lastHitTime > Config.HealthRegenDelay
            and humanoid.Health > 0
            and humanoid.Health < Config.MaxHealth
        then
            humanoid.Health = math.min(Config.MaxHealth, humanoid.Health + Config.HealthRegen * dt)
        end

        StatsEvent:FireClient(player, {
            health   = humanoid.Health,
            stamina  = data.stamina,
            blocking = data.blocking,
        })
    end
end)

-- ── Player lifecycle ──────────────────────────────────────────────────────────
local function onPlayerAdded(player)
    playerData[player] = newData()

    player.CharacterAdded:Connect(function()
        local d = playerData[player]
        if d then
            d.stamina      = Config.MaxStamina
            d.blocking     = false
            d.comboCount   = 0
            d.lastHitTime  = 0
            d.lastLightTime = 0
            d.lastHeavyTime = 0
        end
    end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(p) playerData[p] = nil end)

for _, p in ipairs(Players:GetPlayers()) do
    onPlayerAdded(p)
end
