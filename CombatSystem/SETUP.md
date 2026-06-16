# Roblox Combat System — Setup Guide

## Files

| File | Roblox location | Type |
|------|----------------|------|
| `ReplicatedStorage/CombatConfig.lua`          | ReplicatedStorage          | ModuleScript |
| `ServerScriptService/CombatServer.lua`        | ServerScriptService        | Script       |
| `StarterPlayerScripts/CombatClient.lua`       | StarterPlayer > StarterPlayerScripts | LocalScript |

## Step-by-step install

1. **CombatConfig** — In the Explorer panel, right-click `ReplicatedStorage` → *Insert Object* → `ModuleScript`. Rename it `CombatConfig` and paste the contents of `CombatConfig.lua`.

2. **CombatServer** — Right-click `ServerScriptService` → *Insert Object* → `Script`. Rename it `CombatServer` and paste the contents of `CombatServer.lua`.

3. **CombatClient** — Expand `StarterPlayer`, right-click `StarterPlayerScripts` → *Insert Object* → `LocalScript`. Rename it `CombatClient` and paste the contents of `CombatClient.lua`.

4. **Animations (optional)** — Open `CombatConfig` and replace each `"rbxassetid://0"` with a real animation asset ID uploaded to your Roblox account.

## Controls

| Key | Action |
|-----|--------|
| Left Mouse Button | Light attack / combo |
| Right Mouse Button | Heavy attack (resets combo) |
| F (hold) | Block |

## Features

- **4-hit light combo** — damage scales up on the final hit (×1.6).
- **Heavy attack** — high damage + large knockback; costs more stamina.
- **Block** — reduces incoming damage by 85 %; drains stamina on each blocked hit.
- **Guard break** — block is forcibly dropped when stamina hits 0; "GUARD BROKEN!" appears on screen.
- **Stamina system** — regenerates over time (slower while blocking).
- **Passive health regen** — begins 5 seconds after the last hit.
- **HUD** — health bar (colour-coded), stamina bar, combo counter, blocking badge, control hints.
- **Hit VFX** — yellow spark + "HIT!" billboard on each landed hit; blue ring on blocked hits.
- **Knockback** — physics-based; heavy attack has ~2.5× the force of a light attack.

## Tuning

All numeric values live in `CombatConfig.lua` — damage, cooldowns, stamina costs, hitbox size, knockback force, regen rates, and walk speeds can all be changed without touching the game logic.
