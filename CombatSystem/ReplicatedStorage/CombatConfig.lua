-- ModuleScript: Place inside ReplicatedStorage
-- Name: CombatConfig

local CombatConfig = {

    -- ── Player Stats ──────────────────────────────────────────────────────────
    MaxHealth           = 100,
    MaxStamina          = 100,
    StaminaRegen        = 15,   -- per second
    HealthRegen         = 2,    -- per second (only when out of combat)
    HealthRegenDelay    = 5,    -- seconds after last hit before regen starts

    -- ── Attack Damage ─────────────────────────────────────────────────────────
    LightAttackDamage   = 10,
    HeavyAttackDamage   = 28,
    FinalComboDamageMultiplier = 1.6, -- bonus on the last hit in a combo

    -- ── Stamina Costs ─────────────────────────────────────────────────────────
    LightAttackStaminaCost  = 8,
    HeavyAttackStaminaCost  = 22,
    BlockStaminaDrainRate   = 6,  -- per second while actively blocking
    BlockStaminaOnHit       = 18, -- extra drain when a blocked hit lands

    -- ── Block ─────────────────────────────────────────────────────────────────
    BlockedDamageReduction  = 0.85,  -- 85 % damage negated on a successful block

    -- ── Combo ─────────────────────────────────────────────────────────────────
    MaxComboCount       = 4,
    ComboResetTime      = 1.5,  -- seconds of inactivity that resets the combo

    -- ── Cooldowns (seconds) ───────────────────────────────────────────────────
    LightAttackCooldown = 0.4,
    HeavyAttackCooldown = 1.0,

    -- ── Hitbox ────────────────────────────────────────────────────────────────
    HitboxSize          = Vector3.new(5, 5, 5),
    HitboxOffset        = Vector3.new(0, 0, -3.5), -- offset in front of the root part

    -- ── Knockback force ───────────────────────────────────────────────────────
    LightKnockback      = 22,
    HeavyKnockback      = 55,

    -- ── Walk speed ────────────────────────────────────────────────────────────
    NormalWalkSpeed     = 16,
    BlockWalkSpeed      = 7,

    -- ── Animation asset IDs ──────────────────────────────────────────────────
    -- Replace the zeros with real Roblox animation asset IDs.
    Animations = {
        LightAttack1 = "rbxassetid://0",
        LightAttack2 = "rbxassetid://0",
        LightAttack3 = "rbxassetid://0",
        LightAttack4 = "rbxassetid://0",
        HeavyAttack  = "rbxassetid://0",
        Block        = "rbxassetid://0",
        Stagger      = "rbxassetid://0",
    },
}

return CombatConfig
