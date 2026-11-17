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

#include "/lib/sky.glsl"

void main() {
    /* RENDERTARGETS: 0 */
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    if (texel.a < 0.015) discard;

    // block.properties assigns 100 to water and 101 to lava.
    // Iris exposes the assigned ID minus one through mc_Entity.x.
    bool isWaterBlock = abs(vBlockId - 99.0) < 0.25;
    bool isLavaBlock = abs(vBlockId - 100.0) < 0.25;
    vec3 albedo = aetherSRGBToLinear(texel.rgb);

    // Keep ordinary glass and other non-fluid translucent blocks intact.
    if (!isWaterBlock && !isLavaBlock) {
        vec3 light = texture2D(lightmap, clamp(vLightCoord, vec2(0.0), vec2(1.0))).rgb;
        vec3 glassColor = albedo * (light + vec3(0.025));
        gl_FragData[0] = vec4(max(glassColor, vec3(0.0)), texel.a);
        return;
    }

    if (isLavaBlock) {
        float flowLight = 0.96 + 0.04 * sin(
            (vPlayerPos.x + vPlayerPos.z) * 0.10 + frameTimeCounter * 1.35
        );
        vec3 lavaColor = mix(albedo, vec3(1.0, 0.19, 0.025), 0.18);
        vec3 lavaEmission = lavaColor * (1.35 + flowLight * 0.42);
        gl_FragData[0] = vec4(max(lavaEmission, vec3(0.0)), texel.a);
        return;
    }

    vec3 worldPos = cameraPosition + vPlayerPos;

    // Fine-scale analytic ripples supplement the low-frequency vertex displacement.
    float t = frameTimeCounter;
    float waveDx =
        cos(worldPos.x * 0.105 + t * 0.62) * 0.105 * 0.050
        + cos((worldPos.x + worldPos.z) * 0.052 + t * 0.34) * 0.052 * 0.026
        + cos(worldPos.x * 0.31 - worldPos.z * 0.19 + t * 0.85) * 0.31 * 0.009;
    float waveDz =
        cos(worldPos.z * 0.083 - t * 0.47) * 0.083 * 0.038
        + cos((worldPos.x + worldPos.z) * 0.052 + t * 0.34) * 0.052 * 0.026
        - cos(worldPos.x * 0.31 - worldPos.z * 0.19 + t * 0.85) * 0.19 * 0.009;

    vec3 waveNormal = normalize(vec3(-waveDx, 1.0, -waveDz));
    // Preserve vertical normals on the sides of water volumes.
    if (vPlayerNormal.y < 0.45) {
        waveNormal = normalize(vPlayerNormal);
    }

    vec3 N = normalize(mat3(gbufferModelView) * waveNormal);
    vec3 V = normalize(-vViewPos);
    vec3 L = normalize(shadowLightPosition);

    float dayFactor = smoothstep(-0.06, 0.18,
        normalize(mat3(gbufferModelViewInverse) * sunPosition).y);
    float NdotV = max(dot(N, V), 0.0);
    float fresnel = 0.035 + 0.965 * pow(1.0 - NdotV, 5.0);

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

    // Deep, clean blue-green absorption; the vanilla atlas contributes only a subtle tint.
    vec3 deepWater = vec3(0.004, 0.035, 0.052);
    vec3 shallowWater = vec3(0.014, 0.105, 0.125);
    vec3 waterBase = mix(deepWater, shallowWater, skyLight);
    waterBase = mix(waterBase, albedo * vec3(0.18, 0.28, 0.34), 0.12);
    waterBase *= 0.78 + lightmapSample * 0.30;

    float shadow = aetherShadowPCF(vShadowCoord, N, L);
    float sunSpecular = pow(max(dot(reflect(-L, N), V), 0.0), 128.0);
    vec3 sunHighlight = vec3(1.0, 0.93, 0.80) * sunSpecular
                      * mix(0.10, 1.0, dayFactor) * shadow * 0.82;

    vec3 reflectedWater = skyReflection * (0.78 + 0.12 * dayFactor);
    vec3 finalColor = mix(waterBase, reflectedWater, clamp(fresnel * 0.92, 0.035, 0.91));
    finalColor += sunHighlight;

    float alpha = mix(0.70, 0.86, fresnel);
    gl_FragData[0] = vec4(max(finalColor, vec3(0.0)), alpha);
}
