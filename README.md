# Photon — Flashlight Fork

A fork of [sixthsurge/photon](https://github.com/sixthsurge/photon) adding shader-native flashlight support for the [Flashlight Mod](https://github.com/StewyDev65/JohnnyFlashlightMod).

All original Photon features are preserved. This fork adds a directional spotlight system driven by Iris custom uniforms and the Flashlight Mod.

## What's Added

- **Directional flashlight beam** — smooth cone with feathered edges and a bright central hotspot
- **16 beam colors** — driven by which flashlight item variant is held
- **Smooth on/off fade** — beam transitions gracefully via `shaders.properties` custom uniforms
- **Beam lag** — slight directional lag for a weighty, realistic feel
- **Volumetric glow** — subtle air brightening along the beam path
- **Dust particles** — animated square 1px particles drifting through the beam, with density scaling based on indoor/outdoor environment

## New Shader Settings (under Lighting)

| Setting | Description |
|---------|-------------|
| `FLASHLIGHT` | Enable/disable the beam |
| `FLASHLIGHT_INTENSITY` | Brightness |
| `FLASHLIGHT_DISTANCE` | Reach |
| `FLASHLIGHT_RADIUS` | Cone width |
| `FLASHLIGHT_VOLUMETRIC` | Volumetric glow + particles |
| `FLASHLIGHT_VOL_STEPS` | Volumetric quality |
| `FLASHLIGHT_PARTICLE_DENSITY` | Particle count |
| `FLASHLIGHT_PARTICLE_CLUSTERING` | Particle clustering amount |

## Requirements

- [Iris Shaders](https://modrinth.com/mod/iris) >= 1.5
- [Flashlight Mod](https://github.com/StewyDev65/JohnnyFlashlightMod) for the item and toggle logic

## Installation

1. Download the latest zip from [Releases](https://github.com/StewyDev65/photon-flashlight/releases)
2. Place it in `.minecraft/shaderpacks`
3. Select it in **Video Settings → Shader Packs**

## Credits

All original work by [sixthsurge](https://github.com/sixthsurge). Flashlight additions built on top of the existing `HANDHELD_LIGHTING` system.

Original project: [github.com/sixthsurge/photon](https://github.com/sixthsurge/photon)

## License

Follows the original Photon license. See [LICENSE](LICENSE).