# AETHERIS ULTRA

A physically based, cinematic Minecraft shader pack for **Iris + Sodium**, with a compatibility path for **Vitrail on native Vulkan**.

## Target platform

- Minecraft Java Edition **26.3**
- Fabric Loader
- Iris **1.11.7+26.3-fabric** on OpenGL, or Vitrail on the native Vulkan backend
- Matching Sodium build
- OpenGL 3.3+ for Iris; Vitrail translates the OptiFine/Iris-style shader pack to the game's Vulkan pipeline

This is a shader pack, not a Fabric mod.

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
- Fluid detection using the assigned `mc_Entity.x` material IDs from `block.properties`
- Animated, low-frequency water-surface vertex displacement plus fine analytic ripple normals
- Fresnel reflections, blue-green water absorption and sun glints
- Subtle underwater red absorption and distance fog
- Emissive lava shading
- Conservative contact AO and restrained bloom
- Dedicated terrain, entity, block-entity, first-person hand and translucent terrain programs

## Vulkan setup (Minecraft 26.3)

Use **Vitrail Shaders** to load this OptiFine/Iris-format pack on Minecraft's native Vulkan renderer. Vitrail is a separate client-side Fabric mod; Iris itself does not render on the native Vulkan backend.

1. Install Fabric Loader for Minecraft 26.3.
2. Install Fabric API and a matching Sodium 0.9.x build for Minecraft 26.3.
3. Install the Vitrail Shaders JAR in the instance's `mods/` folder.
4. Leave this AETHERIS ZIP in the instance's `shaderpacks/` folder.
5. In Options → Video Settings → Graphics API, select **Prefer Vulkan (Experimental)** and restart.
6. Open Vitrail's shader selection screen (default key `I`) and select **AETHERIS ULTRA**.

Vitrail is beta software and the Minecraft Vulkan backend is experimental. The pack retains sky geometry as a safety net for the horizon while the composite pass draws the custom Overworld sky. If Vitrail logs that the pack or a particular pass was refused, collect the client log and report the exact message. When running Vulkan, Vitrail handles the shader pack; Iris remains idle. The same instance can use Iris when switched back to OpenGL.

## PBR resource packs

For the full material result, use a **LabPBR 1.3** resource pack. The resource pack must provide:

- A normal map named like the albedo texture with the `_n` suffix
- A specular map named with the `_s` suffix
- A `texture.properties` file in the resource-pack assets declaring:

```properties
format=lab-pbr/1.3
```

Without LabPBR maps, the shader uses conservative neutral material defaults. A resource pack improves surface detail, but it is not required for the custom sky, water shading or wave animation.

## Quality profiles

| Profile | Shadow map | Shadow distance | Fog / AO | Clouds | God rays | Bloom |
| --- | ---: | ---: | --- | --- | --- | --- |
| Performance | 2048 | 96 | Off | Off | Off | Off |
| Balanced | 3072 | 144 | On | On | Off | On |
| Ultra | 4096 | 192 | On | On | On | On |

Ultra is intended as a high-quality starting point for an RTX 5070-class GPU. Actual performance depends on resolution, render distance, resource pack, biome, weather and other mods.

## Visual target and DLSS

AETHERIS ULTRA aims for a natural, high-end, cinematic look inspired by modern real-time game rendering. It does **not** implement NVIDIA DLSS 5; it recreates some of the visual character through its own shader pipeline.

## Validation and status

GitHub Actions expands shader includes, compiles all GLSL stages in both default and LabPBR modes, links vertex/fragment pairs, verifies pack structure, and builds the ZIP. This validates shader syntax and stage interfaces; it does not replace visual testing in a running Minecraft client or Vulkan driver.

## License

MIT. See [LICENSE](LICENSE).
