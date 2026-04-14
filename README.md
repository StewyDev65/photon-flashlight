# Photon — Flashlight Fork

A fork of [sixthsurge/photon](https://github.com/sixthsurge/photon) adding shader-native flashlight support for the [Flashlight Mod](https://github.com/StewyDev65/JohnnyFlashlightMod).

All original Photon features are preserved. This fork adds a directional spotlight system driven by Iris custom uniforms and the Flashlight Mod.

## What's Added

- **Directional flashlight beam** — smooth cone with feathered edges and a bright central hotspot
- **16 beam colors** — driven by which flashlight item variant is held
- **Smooth on/off fade** — beam transitions gracefully when toggling or switching items
- **Beam lag** — slight directional lag for a weighty, realistic feel
- **Volumetric glow** — subtle air brightening along the beam path
- **Dust particles** — animated square 1px particles drifting through the beam, with density scaling based on indoor/outdoor environment
- **Multiplayer beams** — other players' flashlight beams rendered in your world (up to 4 simultaneous)

## Enabling Flashlight Features

All flashlight settings are **off by default**. To enable them, go to:

**Video Settings → Shader Packs → Shader Options → Lighting**

| Setting | Default | Description |
|---------|---------|-------------|
| `FLASHLIGHT` | Off     | Enable/disable the directional beam — **turn this on first** |
| `FLASHLIGHT_INTENSITY` | 2.25    | Beam brightness |
| `FLASHLIGHT_DISTANCE` | 1.50    | How far the beam reaches |
| `FLASHLIGHT_RADIUS` | 1.25    | Cone width |
| `FLASHLIGHT_VOLUMETRIC` | Off     | Volumetric glow + dust particles |
| `FLASHLIGHT_VOL_STEPS` | 8       | Volumetric quality (higher = better, more expensive) |
| `FLASHLIGHT_PARTICLE_DENSITY` | 1.00    | Amount of dust particles |
| `FLASHLIGHT_PARTICLE_CLUSTERING` | 0.80    | How much particles clump together |
| `FLASHLIGHT_MULTIPLAYER` | Off     | Render other players' beams (requires OpenGL 4.3, not supported on macOS) |

## Requirements

- [Iris Shaders](https://modrinth.com/mod/iris) >= 1.5
- [Sodium](https://modrinth.com/mod/sodium) — recommended, ships with Iris by default
- [Flashlight Mod](https://github.com/StewyDev65/JohnnyFlashlightMod) — required for the item, toggle logic, and multiplayer data

## Installation

1. Download the latest zip from [Releases](https://github.com/StewyDev65/photon-flashlight/releases)
2. Place the zip in `.minecraft/shaderpacks`
3. In-game, go to **Video Settings → Shader Packs** and select it
4. Open **Shader Options → Lighting** and enable `FLASHLIGHT` to activate the beam

## Credits

All original work by [sixthsurge](https://github.com/sixthsurge). Flashlight additions built on top of the existing `HANDHELD_LIGHTING` system.

Original project: [github.com/sixthsurge/photon](https://github.com/sixthsurge/photon)

## License

Follows the original Photon license. See [LICENSE](LICENSE).