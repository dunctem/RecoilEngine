# RecoilEngine Fork Guide

This guide covers how to work with a fork of the RecoilEngine, build custom
engine versions, and deploy them for use with Beyond All Reason (BAR).

## Repository Architecture Overview

RecoilEngine is a C++23 real-time strategy game engine, forked from Spring RTS
engine 105.0. The codebase is organized into several major subsystems:

### Main Source Areas (`rts/`)

| Directory | Purpose |
|-----------|---------|
| `rts/System/` | Core utilities: math, threading, file I/O, logging, config |
| `rts/Game/` | Game state, loading, replay, version info |
| `rts/Sim/` | **Synced simulation**: units, projectiles, pathfinding, weapons |
| `rts/Rendering/` | OpenGL rendering, shaders, shadows, effects |
| `rts/Lua/` | Lua API bindings for widgets/gadgets |
| `rts/Map/` | Map loading and terrain |
| `rts/Net/` | Networking and multiplayer sync |
| `rts/Rml/` | RmlUI integration for modern UI |
| `rts/aGui/` | Legacy GUI components |
| `rts/lib/` | Vendored libraries (lua, asio, fmt, etc.) |

### Key Subsystems

**Simulation (`rts/Sim/`)**: The deterministic game logic. Changes here affect
multiplayer sync - all players must run identical simulation code. Contains:
- `Units/` - Unit definitions, scripts, commands
- `Weapons/` - Weapon behavior and targeting
- `Projectiles/` - Projectile physics
- `Path/` - Pathfinding (QTPFS and HAPFS)
- `MoveTypes/` - Movement physics

**Rendering (`rts/Rendering/`)**: Graphics pipeline, completely unsynced. Safe
to modify without affecting multiplayer compatibility. Contains:
- `GL/` - OpenGL abstractions
- `Shaders/` - GLSL shader programs
- `Models/` - 3D model loading/rendering
- `Map/` - Terrain rendering
- `Env/` - Environment effects (sky, water, grass)

**Lua API (`rts/Lua/`)**: Bindings that games use to script behavior.
- `LuaSyncedRead.cpp` / `LuaSyncedCtrl.cpp` - Synced game state access
- `LuaUnsyncedRead.cpp` / `LuaUnsyncedCtrl.cpp` - Unsynced (rendering, UI)
- `LuaConstEngine.cpp` - Engine constants exposed to Lua

**Tools (`tools/`):**
- `unitsync/` - Library for reading game/map archives (used by lobbies)
- `pr-downloader/` - Content download tool
- `DemoTool/` - Replay file utilities

### Build System

The engine uses CMake with Docker-based cross-compilation for reproducible builds.

**Main files:**
- `CMakeLists.txt` - Root CMake configuration
- `docker-build-v2/` - Docker build scripts and images
- `rts/build/cmake/` - CMake modules (version detection, compiler flags)

**Version System:**
- `VERSION.template` - Version file template
- `rts/System/VersionGenerated.h.template` - C++ header template
- `rts/Game/GameVersion.cpp` - Runtime version accessors

The version string format is: `Major.Minor.PatchSet[-Commits-gHash branch] (Additional)`

Example: `105.0.1-847-g61dee311 develop (dunctem)` indicates a dev build with
the "dunctem" custom suffix.

## Building for Windows

### Using GitHub Actions (Recommended for Forks)

This fork includes a workflow that builds Windows artifacts without needing
upstream infrastructure:

1. Push to a branch matching `dev/*` or `cursor/*`, OR
2. Manually trigger via Actions → "Fork Windows Build" → "Run workflow"

The workflow:
- Uses public GHCR docker images (no authentication needed)
- Builds Windows x64 engine with `-dunctem` version suffix
- Creates a GitHub Release with the `.7z` artifact
- Release tag format: `fork-build-{branch}-{shortsha}`

### Local Docker Build

```bash
# Initialize submodules (required)
git submodule update --init --recursive

# Build Windows cross-compile
docker-build-v2/build.sh windows

# Output is in: build-amd64-windows/install/
```

### Build Configuration

Common CMake options (pass to `docker-build-v2/build.sh` or `cmake`):

```bash
# Custom version suffix (visible in Engine.versionFull in Lua)
-DVERSION_ADDITIONAL=myversion

# Build types
-DCMAKE_BUILD_TYPE=DEBUG           # Full debug, no optimization
-DCMAKE_BUILD_TYPE=RELEASE         # Optimized, no debug info
-DCMAKE_BUILD_TYPE=RELWITHDEBINFO  # Optimized + debug (default)

# Feature toggles
-DTRACY_ENABLE=ON                  # Enable Tracy profiler
-DBUILD_spring-headless=OFF        # Skip headless build
```

## Deploying to Beyond All Reason (Windows)

### Engine Directory Structure

BAR stores engines in:
```
C:\Program Files\Beyond-All-Reason\data\engine\
├── recoil_2025.06.19\
│   ├── spring.exe
│   ├── unitsync.dll
│   └── ...
├── recoil_2026.07.04\
└── recoil_custom\          ← Your custom build goes here
```

### Manual Installation

1. Download the latest release artifact (`.7z` file) from your fork's Releases
2. Extract to a new folder under `data\engine\`
3. Name the folder descriptively, e.g., `recoil_dunctem_dev`

### Automated Deployment (PowerShell)

The repository includes a deploy script at `tools/scripts/deploy-engine-windows.ps1`.
It automatically downloads a portable 7-Zip extractor if needed (no installation required).

**Quick start:**
```powershell
# Download the script and run it
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/dunctem/RecoilEngine/master/tools/scripts/deploy-engine-windows.ps1" -OutFile deploy-engine.ps1
.\deploy-engine.ps1

# Or with custom folder name
.\deploy-engine.ps1 -EngineFolder "recoil_test"

# Or specific release
.\deploy-engine.ps1 -ReleaseTag "fork-build-cursor-fork-setup-workflow-388c-214c038"
```

**What it does:**
1. Finds/downloads portable 7zr.exe if 7-Zip isn't installed
2. Fetches the latest release from the fork
3. Downloads the Windows `.7z` artifact
4. Extracts to the BAR engine directory
5. Verifies spring.exe exists

### Running Your Custom Engine

**Option 1: BAR Debug Launcher (Recommended)**

1. Download [BAR Debug Launcher](https://github.com/beyond-all-reason/bar_debug_launcher)
2. It auto-detects engines in `data\engine\` and lets you select which to use

**Option 2: Direct Launch**

Create a batch file (`run-custom-engine.bat`):

```batch
@echo off
set BAR_PATH=C:\Program Files\Beyond-All-Reason
set ENGINE=recoil_dunctem_dev

cd /d "%BAR_PATH%\data\engine\%ENGINE%"
spring.exe --write-dir "%BAR_PATH%\data" --isolation %*
```

**Option 3: Skylobby**

[Skylobby](https://github.com/skynet-gh/skylobby) is a generic Spring lobby
that supports selecting custom engine versions.

### Verifying Your Build

Once running, check the version string:

1. **In-game console**: Press `Enter`, type `/version`
2. **Lua widgets**: `Spring.Echo(Engine.versionFull)`
3. **infolog.txt**: Search for "Spring engine version" at the top

Custom builds show the suffix in parentheses:
```
Spring engine version: 105.0.1-850-gabcdef0 cursor/fork-setup (dunctem)
```

## Making Changes

### Common Change Locations

| What to change | Where |
|----------------|-------|
| Lua API (new function) | `rts/Lua/LuaSyncedCtrl.cpp`, `LuaUnsyncedCtrl.cpp`, etc. |
| Engine constants to Lua | `rts/Lua/LuaConstEngine.cpp` |
| Unit behavior | `rts/Sim/Units/` |
| Pathfinding | `rts/Sim/Path/` |
| Rendering/graphics | `rts/Rendering/` |
| Configuration vars | `rts/System/Config/` |
| Version string | `rts/Game/GameVersion.cpp`, or `-DVERSION_ADDITIONAL` |

### Synced vs Unsynced

**Critical**: Code in `rts/Sim/` affects game state and must be deterministic
across all clients. Changes here will cause desyncs with official engine
versions.

Unsynced code (`rts/Rendering/`, UI code) only affects the local client and is
safe to modify freely.

### Testing Changes

1. **Local headless test**: Build headless and run synctests
2. **Manual test**: Launch with a game and verify behavior
3. **Multiplayer test**: Both players need identical engine builds

## CI Workflows

### Fork Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `fork-windows-build.yml` | Push to `dev/*`, `cursor/*`, or manual | Build Windows artifacts |

### Upstream Workflows (Disabled on Forks)

These workflows only run on `beyond-all-reason/RecoilEngine`:

| Workflow | Purpose |
|----------|---------|
| `engine-build.yml` | Full multi-platform build with ccache |
| `release-build.yml` | Create official releases |
| `bar-cdn-publish.yml` | Publish to BAR CDN |
| `docker-images-build.yml` | Build/push docker images |

## Keeping Up with Upstream

```bash
# Add upstream remote (once)
git remote add upstream https://github.com/beyond-all-reason/RecoilEngine.git

# Fetch and merge upstream changes
git fetch upstream
git merge upstream/master

# Or rebase if you prefer
git rebase upstream/master
```

## Resources

- [RecoilEngine Docs](https://recoilengine.org/docs/)
- [Building Guide](https://recoilengine.org/development/building-with-docker/)
- [Lua API Reference](https://recoilengine.org/docs/)
- [BAR Wiki: Testing Engine Releases](https://github.com/beyond-all-reason/Beyond-All-Reason/wiki/Testing-New-Engine-Releases-in-BAR)
- [Discord](https://discord.gg/GUpRg6Wz3e)
