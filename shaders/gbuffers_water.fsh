#version 330 compatibility

#include "/lib/lighting.glsl"
#include "/lib/pbr.glsl"

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

void main() {
    /* RENDERTARGETS: 0 */
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    if (texel.a < 0.015) discard;

    // Iris 1.8+ stores the assigned block ID minus one in mc_Entity.x.
    bool isWaterBlock = abs(vBlockId - 99.0) < 0.25;
    vec3 albedo = aetherSRGBToLinear(texel.rgb);

    // The translucent pass also contains glass and modded transparent blocks.
    if (!isWaterBlock) {
        vec3 light = texture2D(lightmap, clamp(vLightCoord, vec2(0.0), vec2(1.0))).rgb;
        gl_FragData[0] = vec4(albedo * (light + vec3(0.035)), texel.a);
        return;
    }

    vec3 worldPos = cameraPosition + vPlayerPos;
    vec3 waveNormal = normalize(vPlayerNormal + vec3(
        sin(worldPos.x * 0.085 + frameTimeCounter * 0.72) * 0.065
          + sin(worldPos.z * 0.047 - frameTimeCounter * 0.41) * 0.035,
        0.0,
        cos(worldPos.z * 0.073 + frameTimeCounter * 0.61) * 0.065
          + cos(worldPos.x * 0.051 - frameTimeCounter * 0.36) * 0.035
    ));

    vec3 N = normalize(mat3(gbufferModelView) * waveNormal);
    vec3 V = normalize(-vViewPos);
    vec3 L = normalize(shadowLightPosition);
    vec3 sunDirectionPlayer = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float dayFactor = smoothstep(-0.06, 0.18, sunDirectionPlayer.y);
    vec3 keyTint = mix(vec3(0.16, 0.22, 0.34), vec3(1.00, 0.92, 0.80), dayFactor);
    float keyEnergy = mix(0.035, 1.8, dayFactor);

    float shadow = aetherShadowPCF(vShadowCoord, N, L);
    float NdotV = max(dot(N, V), 0.0);
    float fresnel = 0.020 + 0.980 * pow(1.0 - NdotV, 5.0);

    vec3 reflectionDirPlayer = normalize(mat3(gbufferModelViewInverse) * reflect(-V, N));
    float skyHeight = smoothstep(-0.16, 0.76, reflectionDirPlayer.y);
    vec3 skyReflection = mix(
        aetherSRGBToLinear(fogColor),
        aetherSRGBToLinear(skyColor),
        skyHeight
    );

    vec3 waterTint = mix(
        vec3(0.008, 0.055, 0.075),
        vec3(0.028, 0.19, 0.23),
        clamp(vLightCoord.y, 0.0, 1.0)
    );
    waterTint = mix(waterTint, albedo, 0.22);

    float NdotL = max(dot(N, L), 0.0);
    vec3 waterBRDF = aetherEvaluateBRDF(waterTint, N, V, L, 0.075, 0.0, vec3(0.020));
    vec3 direct = waterBRDF * keyTint * keyEnergy * NdotL * shadow;

    float sunGlint = pow(max(dot(reflect(-L, N), V), 0.0), 180.0);
    vec3 glint = vec3(1.0, 0.93, 0.78) * sunGlint * keyEnergy * shadow * 0.85;

    vec3 lightmapSample = texture2D(lightmap, clamp(vLightCoord, vec2(0.0), vec2(1.0))).rgb;
    vec3 diffuseWater = waterTint * (lightmapSample * 0.20 + vec3(0.006, 0.018, 0.024));
    vec3 reflectedWater = skyReflection * (0.88 + 0.12 * dayFactor);
    vec3 finalColor = mix(diffuseWater + direct, reflectedWater + glint, clamp(fresnel, 0.02, 0.94));

    float alpha = clamp(0.62 + fresnel * 0.25 + length(vViewPos) * 0.00008, 0.62, 0.88);
    gl_FragData[0] = vec4(max(finalColor, vec3(0.0)), alpha);
}
