# AETHERIS ULTRA

A physically based, cinematic Minecraft shader pack for **Iris + Sodium**.

## Target platform

- Minecraft Java Edition **26.3**
- Fabric Loader
- Iris **1.11.7+26.3-fabric**
- Matching Sodium build
- OpenGL 3.3+

This is an Iris shader pack, not a Fabric mod.

## Rendering features

- Cook-Torrance BRDF with GGX microfacet distribution
- LabPBR 1.3 normal, roughness, reflectance, metallic, AO and emission maps
- Tangent-space normal mapping via Iris vertex tangents
- Linear-light material shading and filmic ACES output transform
- Soft PCF shadow filtering with up to 4096-pixel shadow maps
- Weather-aware, height-dependent atmospheric fog with subtle forward scattering
- Procedural atmospheric sky with a custom solar disc, golden-hour glow, night stars and phase-aware moon
- Animated procedural cumulus clouds with weather-responsive coverage and warm sunset lighting
- Water reflections that use the same custom sky and sun as the main view
- Animated water normals, Fresnel reflections and sun glints
- Emissive lava shading
- Conservative contact AO and restrained bloom
- Dedicated terrain, entity, block-entity, first-person hand and translucent terrain programs

## PBR resource packs

For the full material result, use a **LabPBR 1.3** resource pack. The resource pack must provide:

- A normal map named like the albedo texture with the `_n` suffix
- A specular map named with the `_s` suffix
- A `texture.properties` file in the resource-pack assets declaring:

```properties
format=lab-pbr/1.3
```

Iris exposes these as `normals` and `specular` atlases and defines `MC_TEXTURE_FORMAT_LAB_PBR` when the format is declared. Without LabPBR maps, the shader uses conservative neutral material defaults. The shader changes lighting and material response; it cannot invent surface detail that is absent from the resource pack.

## Quality profiles

| Profile | Shadow map | Shadow distance | Fog / AO | Clouds | God rays | Bloom |
| --- | ---: | ---: | --- | --- | --- | --- |
| Performance | 2048 | 96 | Off | Off | Off | Off |
| Balanced | 3072 | 144 | On | On | Off | On |
| Ultra | 4096 | 192 | On | On | On | On |

Ultra is intended as a high-quality starting point for an RTX 5070-class GPU. Actual performance depends on resolution, render distance, resource pack, biome, weather and other mods. Use the Performance or Balanced profile if you prefer higher frame rates.

## Visual target and DLSS

AETHERIS ULTRA aims for a natural, high-end, cinematic look inspired by modern real-time game rendering: physically based materials, atmospheric perspective, a custom sky, detailed clouds, strong but controlled sunlight, and filmic tonemapping.

It does **not** implement NVIDIA DLSS 5. DLSS is not a GLSL shader-pack feature exposed by Minecraft/Iris; the shader recreates some of the visual character through its own rendering pipeline. It does not require DLSS to run.

## Install

1. Install Fabric for Minecraft 26.3.
2. Install Iris for 26.3 and its matching Sodium dependency.
3. Download the latest successful `AETHERIS-ULTRA` artifact from the repository's **Actions** tab.
4. Put the downloaded ZIP directly in `.minecraft/shaderpacks/`.
5. Select **AETHERIS ULTRA** in Video Settings → Shader Packs.
6. Choose the **ULTRA** profile in Shader Pack Settings.
7. Enable a LabPBR resource pack for the full material workflow.

## Validation and status

GitHub Actions expands shader includes, compiles all GLSL stages in both default and LabPBR modes, links vertex/fragment pairs, verifies pack structure, and builds the artifact. This validates shader syntax and stage interfaces; it does not replace visual testing in a running Minecraft client and GPU driver.

## License

MIT. See [LICENSE](LICENSE).
