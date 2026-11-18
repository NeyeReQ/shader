#version 330 compatibility

#include "/lib/pbr.glsl"
#include "/lib/water.glsl"

uniform sampler2D gtexture;
uniform vec3 cameraPosition;
uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform vec3 fogColor;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform float frameTimeCounter;
uniform float alphaTestRef;
uniform float rainStrength;
uniform int isEyeInWater;

in vec2 vTexCoord;
in vec2 vLightCoord;
in vec4 vColor;
in vec3 vViewPos;
in vec3 vPlayerPos;
in vec3 vPlayerNormal;
in float vBlockId;
in float vIsFluid;

vec3 aetherWaterSafeNormalize(vec3 v, vec3 fallbackValue) {
    float l2 = dot(v, v);
    return (l2 > 1e-8 && l2 < 1e20) ? v * inversesqrt(l2) : fallbackValue;
}

void main() {
    /* RENDERTARGETS: 0 */
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    if (texel.a < max(alphaTestRef, 0.001)) discard;

    bool isLava = vIsFluid > 0.5
               && (abs(vBlockId - 199.0) < 0.25
                || abs(vBlockId - 200.0) < 0.25);
    bool isWater = !isLava
                && (vIsFluid > 0.5 || abs(vBlockId - 120.0) < 0.25);
    vec3 albedo = aetherSRGBToLinear(texel.rgb);

    if (!isWater && !isLava) {
        vec3 light = texture2D(lightmap,
            clamp(vLightCoord, vec2(0.0), vec2(1.0))).rgb;
        gl_FragData[0] = vec4(max(albedo * (light + vec3(0.025)), vec3(0.0)), texel.a);
        return;
    }

    if (isLava) {
        float flow = 0.96 + 0.04 * sin(
            (vPlayerPos.x + vPlayerPos.z) * 0.10 + frameTimeCounter * 1.35
        );
        vec3 emission = vec3(1.0, 0.25, 0.075) * (1.05 + flow * 0.20);
        gl_FragData[0] = vec4(emission, max(texel.a, 0.88));
        return;
    }

    vec3 worldPosition = cameraPosition + vPlayerPos;
    vec3 geometricNormal = aetherWaterSafeNormalize(vPlayerNormal, vec3(0.0, 1.0, 0.0));
    vec3 worldNormal = aetherWaterNormal(
        worldPosition.xz, frameTimeCounter, geometricNormal, cameraPosition - worldPosition
    );
    vec3 viewNormal = aetherWaterSafeNormalize(
        mat3(gbufferModelView) * worldNormal, vec3(0.0, 1.0, 0.0)
    );
    vec3 viewDirection = aetherWaterSafeNormalize(-vViewPos, vec3(0.0, 0.0, 1.0));
    if (dot(viewNormal, viewDirection) < 0.0) {
        viewNormal = -viewNormal;
        worldNormal = -worldNormal;
    }

    // Air/water IOR 1.33: F0 ~= 0.0204, with a full grazing-angle reflection.
    float nDotV = clamp(dot(viewNormal, viewDirection), 0.0, 1.0);
    float fresnel = clamp(0.0204 + 0.9796 * pow(1.0 - nDotV, 5.0), 0.0204, 0.98);

    vec3 sunDirectionWorld = aetherWaterSafeNormalize(
        mat3(gbufferModelViewInverse) * sunPosition, vec3(0.0, 1.0, 0.0)
    );
    vec3 lightDirectionWorld = aetherWaterSafeNormalize(
        mat3(gbufferModelViewInverse) * shadowLightPosition, sunDirectionWorld
    );
    float daylight = smoothstep(-0.16, 0.20, sunDirectionWorld.y);
    float goldenHour = 1.0 - smoothstep(0.035, 0.36, abs(sunDirectionWorld.y));

    vec3 reflectedView = reflect(-viewDirection, viewNormal);
    vec3 reflectedWorld = aetherWaterSafeNormalize(
        mat3(gbufferModelViewInverse) * reflectedView, vec3(0.0, 1.0, 0.0)
    );
    vec3 skyReflection = aetherWaterSkyReflection(
        reflectedWorld, sunDirectionWorld, daylight, goldenHour,
        rainStrength, worldPosition, frameTimeCounter
    );

    float pattern = aetherWaterPattern(worldPosition.xz, frameTimeCounter);
    float skyLight = clamp(vLightCoord.y, 0.0, 1.0);
    float blockLight = clamp(vLightCoord.x, 0.0, 1.0);
    vec3 deepWater = vec3(0.0045, 0.014, 0.020);
    vec3 midWater = vec3(0.012, 0.043, 0.050);
    vec3 shallowWater = vec3(0.032, 0.090, 0.086);
    vec3 waterBody = mix(deepWater, midWater, smoothstep(0.03, 0.92, skyLight));
    waterBody = mix(waterBody, shallowWater, smoothstep(0.70, 0.98, skyLight) * 0.58);
    waterBody *= mix(0.90, 1.08, pattern);
    vec3 biomeTint = clamp(albedo, vec3(0.12), vec3(1.0));
    waterBody *= mix(vec3(0.94, 0.99, 0.97), biomeTint, 0.13);
    waterBody *= 1.0 + blockLight * 0.05;
    vec3 surfaceColor = mix(waterBody, skyReflection, fresnel * 0.96);

    vec3 reflectedLight = reflect(-lightDirectionWorld, worldNormal);
    vec3 toCameraWorld = aetherWaterSafeNormalize(
        cameraPosition - worldPosition, vec3(0.0, 1.0, 0.0)
    );
    float specularAlignment = max(dot(reflectedLight, toCameraWorld), 0.0);
    float broadGlint = pow(specularAlignment, 34.0);
    float sharpGlint = pow(specularAlignment, 150.0);
    float glintMask = mix(0.38, 1.0, pattern) * daylight;
    float glint = (broadGlint * 0.12 + sharpGlint * 0.78) * glintMask;
    surfaceColor += vec3(1.0, 0.91, 0.75) * glint;

    float ripple = 0.5 + 0.5 * sin(
        dot(worldPosition.xz, vec2(0.72, 0.41)) * 2.25 + frameTimeCounter * 1.15
    ) * sin(
        dot(worldPosition.xz, vec2(-0.36, 0.93)) * 1.72 - frameTimeCounter * 0.82
    );
    float rippleSheen = smoothstep(0.63, 0.94, ripple) * (0.018 + 0.045 * pattern);
    surfaceColor += vec3(0.13, 0.17, 0.16) * rippleSheen * daylight;

    float crestNoise = aetherWaterNoise(worldPosition.xz * 0.33
                                      + vec2(frameTimeCounter * 0.025,
                                             -frameTimeCounter * 0.018));
    float foam = smoothstep(0.91, 0.985, pattern)
               * smoothstep(0.70, 0.94, crestNoise) * 0.11;
    surfaceColor = mix(surfaceColor, vec3(0.48, 0.53, 0.51), foam);

    float distanceToCamera = length(vViewPos);
    float haze = clamp(1.0 - exp(-distanceToCamera * 0.00048), 0.0, 0.38);
    vec3 hazeColor = aetherSRGBToLinear(clamp(fogColor, vec3(0.0), vec3(1.0)));
    surfaceColor = mix(surfaceColor, hazeColor, haze);

    float waterAlpha = mix(0.60, 0.94, smoothstep(0.025, 0.94, fresnel));
    if (isEyeInWater == 1) {
        surfaceColor = mix(surfaceColor, vec3(0.012, 0.085, 0.105), 0.16);
        waterAlpha = min(waterAlpha, 0.68);
    }
    gl_FragData[0] = vec4(max(surfaceColor, vec3(0.0)), waterAlpha);
}
