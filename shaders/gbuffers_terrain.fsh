#version 330 compatibility

#include "/lib/lighting.glsl"
#include "/lib/pbr.glsl"

uniform sampler2D gtexture;
uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform mat4 gbufferModelViewInverse;
uniform float wetness;
uniform float rainStrength;
uniform float alphaTestRef;

in vec2 vTexCoord;
in vec2 vLightCoord;
in vec4 vColor;
in vec3 vViewPos;
in vec3 vViewNormal;
in vec3 vViewTangent;
in float vHandedness;
in vec4 vShadowCoord;

void main() {
    /* RENDERTARGETS: 0 */
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    if (texel.a < alphaTestRef) discard;

    vec3 albedo = aetherSRGBToLinear(texel.rgb);
    AetherMaterial material = aetherBuildMaterial(vTexCoord, albedo, vViewNormal, vViewTangent, vHandedness, wetness);

    vec3 N = material.normal;
    vec3 V = normalize(-vViewPos);
    vec3 L = normalize(shadowLightPosition);
    vec3 sunDirectionPlayer = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float dayFactor = smoothstep(-0.06, 0.18, sunDirectionPlayer.y);
    vec3 keyTint = mix(vec3(0.19, 0.25, 0.39), vec3(1.00, 0.93, 0.82), dayFactor);
    float keyEnergy = mix(0.045, 2.15, dayFactor) * (1.0 - rainStrength * 0.20);

    float shadow = aetherShadowPCF(vShadowCoord, N, L);
    float NdotL = max(dot(N, L), 0.0);
    vec3 directLight = aetherEvaluateBRDF(albedo, N, V, L, material.roughness, material.metallic, material.f0)
                     * keyTint * keyEnergy * NdotL * shadow;

    vec3 lightmapSample = texture2D(lightmap, clamp(vLightCoord, vec2(0.0), vec2(1.0))).rgb;
    float skyLight = clamp(vLightCoord.y, 0.0, 1.0);
    float blockLight = clamp(vLightCoord.x, 0.0, 1.0);
    vec3 skyIrradiance = aetherSRGBToLinear(mix(fogColor, skyColor, 0.55));
    vec3 ambientIrradiance = skyIrradiance * (0.025 + 0.16 * skyLight)
                           + lightmapSample * 0.22 + vec3(0.006, 0.008, 0.012);
    vec3 indirectDiffuse = albedo * ambientIrradiance * material.ao;
    vec3 blockIllumination = albedo * vec3(1.00, 0.62, 0.38) * pow(blockLight, 2.0) * 0.12;
    vec3 indirectSpecular = material.f0 * skyIrradiance * (0.018 + 0.055 * skyLight);
    vec3 emission = albedo * material.emission;

    vec3 finalColor = directLight + indirectDiffuse + blockIllumination + indirectSpecular + emission;
    gl_FragData[0] = vec4(max(finalColor, vec3(0.0)), texel.a);
}
