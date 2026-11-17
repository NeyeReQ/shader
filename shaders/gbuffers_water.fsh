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

    bool waterId = abs(vBlockId - 119.0) < 0.25
                || abs(vBlockId - 120.0) < 0.25;
    bool lavaId = abs(vBlockId - 199.0) < 0.25
               || abs(vBlockId - 200.0) < 0.25;
    bool isFluid = vFluidType > 0.5 || waterId || lavaId;
    vec3 albedo = aetherSRGBToLinear(texel.rgb);

    // Glass and other non-fluid translucent blocks remain separate from the water path.
    if (!isFluid) {
        vec3 light = texture2D(lightmap, clamp(vLightCoord, vec2(0.0), vec2(1.0))).rgb;
        gl_FragData[0] = vec4(max(albedo * (light + vec3(0.025)), vec3(0.0)), texel.a);
        return;
    }

    if (lavaId) {
        float flowLight = 0.96 + 0.04 * sin(
            (vPlayerPos.x + vPlayerPos.z) * 0.10 + frameTimeCounter * 1.35
        );
        vec3 lavaEmission = vec3(1.0, 0.19, 0.025) * (1.45 + flowLight * 0.38);
        gl_FragData[0] = vec4(lavaEmission, texel.a);
        return;
    }

    vec3 worldPos = cameraPosition + vPlayerPos;
    float t = frameTimeCounter;

    float waveDx = 0.32 * (
        cos(worldPos.x * 0.105 + t * 0.62) * 0.105 * 0.115
        + cos((worldPos.x + worldPos.z) * 0.052 + t * 0.34) * 0.052 * 0.055
        + cos(worldPos.x * 0.31 - worldPos.z * 0.19 + t * 0.85) * 0.31 * 0.018
    );
    float waveDz = 0.32 * (
        cos(worldPos.z * 0.083 - t * 0.47) * 0.083 * 0.085
        + cos((worldPos.x + worldPos.z) * 0.052 + t * 0.34) * 0.052 * 0.055
        - cos(worldPos.x * 0.31 - worldPos.z * 0.19 + t * 0.85) * 0.19 * 0.018
    );

    vec3 geometricNormal = aetherSafeNormalize(vPlayerNormal, vec3(0.0, 1.0, 0.0));
    vec3 waveNormal = aetherSafeNormalize(vec3(-waveDx, 1.0, -waveDz), geometricNormal);
    if (geometricNormal.y < 0.45) {
        waveNormal = geometricNormal;
    }

    vec3 N = aetherSafeNormalize(mat3(gbufferModelView) * waveNormal, vec3(0.0, 1.0, 0.0));
    vec3 V = aetherSafeNormalize(-vViewPos, vec3(0.0, 0.0, 1.0));
    vec3 L = aetherSafeNormalize(shadowLightPosition, vec3(0.0, 1.0, 0.0));
    vec3 sunDirectionPlayer = aetherSafeNormalize(
        mat3(gbufferModelViewInverse) * sunPosition, vec3(0.0, 1.0, 0.0)
    );
    float dayFactor = smoothstep(-0.06, 0.18, sunDirectionPlayer.y);

    float NdotV = max(dot(N, V), 0.0);
    float fresnel = 0.035 + 0.965 * pow(1.0 - NdotV, 5.0);
    vec3 reflectedDirection = aetherSafeNormalize(
        mat3(gbufferModelViewInverse) * reflect(-V, N), vec3(0.0, 1.0, 0.0)
    );
    vec3 skyReflection = aetherRenderSky(reflectedDirection, worldPos);

    float skyLight = clamp(vLightCoord.y, 0.0, 1.0);
    vec3 waterBase = mix(
        vec3(0.004, 0.034, 0.052),
        vec3(0.014, 0.105, 0.128),
        skyLight
    );

    float shadow = aetherShadowPCF(vShadowCoord, N, L);
    float specularPower = pow(max(dot(reflect(-L, N), V), 0.0), 128.0);
    vec3 sunGlint = vec3(1.0, 0.94, 0.80) * specularPower
                  * mix(0.10, 1.0, dayFactor) * shadow * 0.85;
    vec3 reflection = skyReflection * (0.78 + 0.12 * dayFactor);
    vec3 result = mix(waterBase, reflection, clamp(fresnel * 0.92, 0.035, 0.91));
    result += sunGlint;

    gl_FragData[0] = vec4(max(result, vec3(0.0)), mix(0.60, 0.84, fresnel));
}
