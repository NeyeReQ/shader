#version 330 compatibility

#include "/lib/lighting.glsl"

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform vec3 shadowLightPosition;
uniform float wetness;
uniform float rainStrength;
uniform float frameTimeCounter;
uniform float alphaTestRef;

in vec2 vTexCoord;
in vec2 vLightCoord;
in vec4 vColor;
in vec3 vViewPos;
in vec3 vViewNormal;
in vec4 vShadowCoord;
in float vBlockId;

void main() {
    /* RENDERTARGETS: 0 */
    vec2 waveUV = vTexCoord;
    waveUV += vec2(
        sin(vViewPos.x * 0.035 + frameTimeCounter * 0.75),
        cos(vViewPos.z * 0.030 + frameTimeCounter * 0.58)
    ) * 0.0018;

    vec4 waterTexel = texture2D(gtexture, waveUV) * vColor;
    if (waterTexel.a < 0.015) discard;

    // gbuffers_water also renders glass and other translucent blocks.
    // Only block ID 100 (minecraft:water) receives the custom water material.
    // Iris versions may expose the assigned ID with a one-value encoding offset.
    bool isWaterBlock = (vBlockId > 98.5 && vBlockId < 100.5);
    if (!isWaterBlock) {
        vec3 vanillaLight = texture2D(lightmap, clamp(vLightCoord, vec2(0.0), vec2(1.0))).rgb;
        gl_FragData[0] = vec4(waterTexel.rgb * vanillaLight, waterTexel.a);
        return;
    }

    vec3 baseNormal = normalize(vViewNormal);
    vec3 animatedNormal = normalize(baseNormal + vec3(
        sin(vViewPos.x * 0.075 + frameTimeCounter * 1.15) * 0.10,
        0.0,
        cos(vViewPos.z * 0.065 + frameTimeCounter * 0.92) * 0.10
    ));

    vec3 lightDirection = normalize(shadowLightPosition);
    vec3 viewDirection = normalize(-vViewPos);

    float skyLight = clamp(vLightCoord.y, 0.0, 1.0);
    float blockLight = clamp(vLightCoord.x, 0.0, 1.0);
    float shadow = aetherShadowPCF(vShadowCoord, animatedNormal, lightDirection);

    float diffuse = max(dot(animatedNormal, lightDirection), 0.0) * shadow;
    float fresnel = pow(1.0 - max(dot(animatedNormal, viewDirection), 0.0), 5.0);
    float specular = pow(max(dot(reflect(-lightDirection, animatedNormal), viewDirection), 0.0), 72.0);

    vec3 deepWater = vec3(0.018, 0.105, 0.145);
    vec3 shallowWater = vec3(0.075, 0.285, 0.335);
    vec3 reflectedSky = mix(vec3(0.43, 0.57, 0.68), vec3(0.075, 0.235, 0.315), clamp(skyLight, 0.0, 1.0));

    vec3 waterBase = mix(deepWater, shallowWater, clamp(skyLight * 0.75 + blockLight * 0.12, 0.0, 1.0));
    waterBase = mix(waterBase, waterTexel.rgb, 0.24);
    waterBase *= 0.58 + diffuse * 0.52;

    vec3 reflectedColor = mix(reflectedSky, vec3(0.80, 0.88, 0.96), clamp(specular * 0.45, 0.0, 1.0));
    vec3 finalColor = mix(waterBase, reflectedColor, clamp(0.18 + fresnel * 0.66, 0.0, 0.88));
    finalColor += vec3(0.88, 0.94, 1.0) * specular * (0.65 + wetness * 0.35);

    float alpha = clamp(waterTexel.a * 0.90 + fresnel * 0.08, 0.25, 0.92);
    gl_FragData[0] = vec4(finalColor, alpha);
}
