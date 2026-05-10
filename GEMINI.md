# Hekili Helper - Project Mandates & Architecture

## Project Overview
**Hekili Helper** is a World of Warcraft addon designed to augment the **Hekili** rotation helper. It provides specialized logic for specific classes and specs (primarily Retribution Paladin, Death Knight, and various Healing specs) that requires precise timing, custom buff tracking, or target-specific conditions not natively covered by Hekili's default simulations.

- **Primary Technologies:** Lua, Blizzard WoW API, Hekili API.
- **Key Dependencies:** `Hekili`, `LibRangeCheck-2.0/3.0`.
- **Target Environment:** Titan / Latest WLK (WotLK Classic) clients (Interface 30400+).

## Architecture & Modular Design
The project follows a modular singleton pattern where `HekiliHelper.lua` acts as the orchestrator.
- **Core Orchestrator:** Initializes the database (`AceDB`) and manages the lifecycle of individual modules.
- **Skill Modules (`Modules/*Skills.lua`):** Each module handles a specific class/spec. They hook into `Hekili:Update` via `HekiliHelper.HookUtils` to inject custom recommendations into the `Hekili.DisplayPool`.
- **UI & Utility Modules:** Components like `ModeSwitcher`, `BlankIcon`, and `UIModifier` handle visual adjustments and global state toggles.
- **Options (`Modules/Options.lua`):** Centralized configuration using `AceConfig-3.0`.

## Engineering Standards

### 1. Development Mandate (User Priority)
**"我很清楚我在干什么。我不需要你做我没有要求的任何事情。"**
- **Strict Adherence:** Only implement logic explicitly requested. Do not add "just-in-case" safety checks, fallback schemes, or redundancy.
- **Trust Intent:** Assume the user has full technical knowledge of spell IDs, priority logic, and game mechanics.

### 2. Distance Checking
- **Standard:** Use **LibRangeCheck** exclusively.
- **Consistency:** Align range thresholds with `RangeDisplay` standards.
- **Prohibition:** Never use `IsSpellInRange` as a fallback or primary check unless specifically instructed for a unique scenario.

### 3. Cooldown & GCD Logic
- **Real-Time Accuracy:** Recommendations must be "what you see is what you get." 
- **No Buffering:** Do not use time-based buffering (e.g., `cd < 1.5s`) for readiness checks.
- **GCD Filtering:** Always filter out the Global Cooldown (GCD) using spell ID `61304`. A skill is considered "Ready" if its cooldown matches the GCD start and duration.

### 4. Buff/Debuff Detection
- **Client Compatibility:** Due to index shifts in different WoW versions, use robust detection helpers.
- **Dual Index Check:** Use `select(10, UnitBuff(...))` and `select(11, ...)` to identify `spellId`.
- **High ID Support:** Logic must correctly handle 7-digit spell IDs (e.g., `1299090`).

### 5. Target Validation
- **TTD (Time To Die):** Use the internal TTD calculator for logic involving long-cooldown items (e.g., `Lionheart`) or execute-phase transitions.
- **Target Selection:** Healing modules should prioritize `mouseover` > `target` > `player` with distance validation.

## Building and Running
1. **Installation:** Place the `HekiliHelper` folder in `Interface/AddOns/`.
2. **Reload UI:** Use `/reload` in-game to apply changes.
3. **Debug Mode:** Enable via `/hh debug` to show the logic monitor (HUD).

## Code Style
- **Naming:** CamelCase for functions and PascalCase for Module names. Localize `HekiliHelper` as `HH` where appropriate.
- **Stability:** Ensure `Hekili` and `Hekili.Update` existence checks are performed during module initialization.
