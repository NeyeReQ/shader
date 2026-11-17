# AETHERIS ULTRA

A cinematic, high-fidelity Minecraft shader pack built for **Iris + Sodium**.

> Project status: first public development build. The pack is being developed for Minecraft Java 26.3 on Fabric. It has not yet been compiled and visually tested inside a running Minecraft client.

## Target setup

- Minecraft Java Edition **26.3**
- Fabric Loader
- Iris **1.11.7+26.3-fabric**
- A matching Sodium build
- OpenGL 3.3 or newer

This repository is a shader pack, not a Fabric mod. The shader files live in `shaders/`; `shaders.properties` exposes the in-game quality controls.

## Visual direction

- Atmospheric distance and height fog, with weather-aware density
- High-resolution PCF shadow filtering
- Warm direct sunlight and cooler ambient fill
- Procedural animated water highlights and Fresnel reflections
- Screen-space ambient occlusion
- Subtle screen-space sun shafts
- Filmic ACES tonemapping, restrained bloom and vignette

## Quality profiles

| Profile | Shadow map | Fog | SSAO | Sun shafts | Bloom |
| --- | ---: | --- | --- | --- | --- |
| Performance | 2048 | Off | Off | Off | Off |
| Balanced | 3072 | On | On | Off | On |
| Ultra | 4096 | On | On | On | On |

The Ultra profile is intended for high-end GPUs such as the RTX 5070. Actual FPS depends on render distance, resolution, resource packs, other mods and the world.

## Install

1. Install Fabric for Minecraft 26.3.
2. Install Iris for 26.3 and its required Sodium dependency.
3. Download the shader pack ZIP from the repository's **Actions → Package shader pack** workflow artifact, or package the two items `shaders/` and `shaders.properties` into a ZIP.
4. Place the ZIP in `.minecraft/shaderpacks/`.
5. Select **AETHERIS ULTRA** in Video Settings → Shader Packs.
6. Open Shader Pack Settings and choose **ULTRA**.

## Development

The pack uses the Iris/OptiFine shader-pack pipeline and GLSL 330 compatibility shaders. No Minecraft core-shader overrides or custom client mod are required.

For debugging, enable Iris shader debug mode with **Ctrl + D** on the shader selection screen.

## Important testing note

The repository's first implementation is a development baseline. It must still be tested in a real Minecraft 26.3 client with Iris/Sodium. Driver-specific GLSL behavior, water transparency, shadow bias and visual tuning should be validated in-game before calling the pack production-ready.

## License

MIT. See [LICENSE](LICENSE).
