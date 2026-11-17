#version 330 compatibility

#include "/lib/lighting.glsl"
#include "/lib/pbr.glsl"

#define AETHER_CLOUDS // [true false]

uniform sampler2D gtexture;
uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform float wetness;
uniform float rainStrength;
uniform float frameTimeCounter;
uniform float alphaTestRef;

in vec2 vTexCoord;
in vec2 vLightCoord;
in vec4 vColor;
in vec3 vViewPos;
in vec3 vPlayerPos;
in vec3 vPlayerNormal;
in vec4 vShadowCoord;
in float vBlockId;
in float vFluidType;

#include "/lib/sky.glsl"

void main() {
    /* RENDERTARGETS: 0 */
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    if (texel.a < 0.015) discard;

    // Iris marks fluid geometry with mc_Entity.y = 1.0. This is more robust
    // than relying only on block.properties IDs for identifying water.
    bool isFluid = vFluidType > 0.5;
    bool isLavaBlock = isFluid && abs(vBlockId - 100.0) < 0.25;
    bool isWaterBlock = isFluid && !isLavaBlock;
    vec3 albedo = aetherSRGBToLinear(texel.rgb);

    // Preserve glass and other non-fluid translucent blocks.
    if (!isFluid) {
        vec3 light = texture2D(lightmap, clamp(vLightCoord, vec2(0.0), vec2(1.0))).rgb;
        vec3 glassColor = albedo * (light + vec3(0.025));
        gl_FragData[0] = vec4(max(glassColor, vec3(0.0)), texel.a);
        return;
    }

    // Lava gets a stable warm emission instead of entering the water reflection path.
    if (isLavaBlock) {
        float flowLight = 0.96 + 0.04 * sin(
            (vPlayerPos.x + vPlayerPos.z) * 0.10 + frameTimeCounter * 1.35
        );
        vec3 lavaColor = mix(albedo, vec3(1.0, 0.19, 0.025), 0.18);
        vec3 lavaEmission = lavaColor * (1.35 + flowLight * 0.42);
        gl_FragData[0] = vec4(max(lavaEmission, vec3(0.0)), texel.a);
        return;
    }

    if (!isWaterBlock) {
        vec3 light = texture2D(lightmap, clamp(vLightCoord, vec2(0.0), vec2(1.0))).rgb;
        gl_FragData[0] = vec4(albedo * (light + vec3(0.035)), texel.a);
        return;
    }

    vec3 worldPos = cameraPosition + vPlayerPos;
    vec3 waveOffset = vec3(
        sin(worldPos.x * 0.071 + frameTimeCounter * 0.48) * 0.026
          + sin(worldPos.z * 0.039 - frameTimeCounter * 0.29) * 0.018,
        0.0,
        cos(worldPos.z * 0.063 + frameTimeCounter * 0.41) * 0.026
          + cos(worldPos.x * 0.043 - frameTimeCounter * 0.23) * 0.018
    );
    vec3 waveNormal = normalize(vPlayerNormal + waveOffset);
    vec3 N = normalize(mat3(gbufferModelView) * waveNormal);
    vec3 V = normalize(-vViewPos);
    vec3 L = normalize(shadowLightPosition);

    float dayFactor = smoothstep(-0.06, 0.18,
        normalize(mat3(gbufferModelViewInverse) * sunPosition).y);
    float NdotV = max(dot(N, V), 0.0);
    float fresnel = 0.025 + 0.975 * pow(1.0 - NdotV, 5.0);

    vec3 reflectionDirPlayer = normalize(
        mat3(gbufferModelViewInverse) * reflect(-V, N)
    );
    vec3 skyReflection = hasSkylight
        ? aetherRenderSky(reflectionDirPlayer, worldPos)
        : aetherSRGBToLinear(mix(fogColor, skyColor, 0.70));

    vec3 lightmapSample = texture2D(
        lightmap, clamp(vLightCoord, vec2(0.0), vec2(1.0))
    ).rgb;
    float skyLight = clamp(vLightCoord.y, 0.0, 1.0);

    // Keep water naturally blue/teal. Texture RGB only contributes a small tint,
    // preventing the water atlas color from turning the whole surface pink.
    vec3 deepWater = vec3(0.006, 0.050, 0.070);
    vec3 shallowWater = vec3(0.018, 0.115, 0.135);
    vec3 waterBase = mix(deepWater, shallowWater, skyLight);
    waterBase = mix(waterBase, albedo * vec3(0.22, 0.34, 0.38), 0.16);
    waterBase *= 0.70 + lightmapSample * 0.42;

    float NdotL = max(dot(N, L), 0.0);
    float shadow = aetherShadowPCF(vShadowCoord, N, L);
    float sunSpecular = pow(max(dot(reflect(-L, N), V), 0.0), 112.0);
    vec3 sunHighlight = vec3(1.0, 0.91, 0.74) * sunSpecular
                      * mix(0.12, 1.0, dayFactor) * shadow * 0.72;

    vec3 reflectedWater = skyReflection * (0.76 + 0.12 * dayFactor);
    vec3 finalColor = mix(waterBase, reflectedWater, clamp(fresnel * 0.88, 0.025, 0.90));
    finalColor += sunHighlight;
    finalColor = max(finalColor, vec3(0.0));

    // Moderate translucency, with extra transparency when looking nearly straight down.
    float alpha = mix(0.68, 0.84, fresnel);
    gl_FragData[0] = vec4(finalColor, alpha);
}
