#version 330 compatibility

#define AETHER_VOLUMETRIC_FOG // Atmospheric depth and height fog.
#define AETHER_SSAO // Subtle screen-space contact occlusion.
#define FOG_DENSITY 0.0014 // [0.0006 0.0009 0.0012 0.0014 0.0018 0.0022] Base atmospheric density.

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform float fogDensity;
uniform float rainStrength;
uniform float frameTimeCounter;
uniform float viewWidth;
uniform float viewHeight;
uniform int isEyeInWater;

in vec2 vTexCoord;

vec3 reconstructViewPosition(vec2 uv, float depth) {
    vec4 clipPosition = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPosition = gbufferProjectionInverse * clipPosition;
    return viewPosition.xyz / max(viewPosition.w, 0.00001);
}

float aetherHash(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

void main() {
    /* DRAWBUFFERS:1 */
    vec4 scene = texture2D(colortex0, vTexCoord);
    float depth = texture2D(depthtex0, vTexCoord).r;

    // The sky is intentionally left to the game's sky renderer.
    if (depth >= 0.999999) {
        gl_FragData[0] = scene;
        return;
    }

    vec3 viewPosition = reconstructViewPosition(vTexCoord, depth);
    float pixelDistance = length(viewPosition);

#ifdef AETHER_SSAO
    float occlusion = 0.0;
    vec2 pixelSize = 1.0 / vec2(viewWidth, viewHeight);
    const vec2 kernel[8] = vec2[8](
        vec2( 1.0,  0.0), vec2(-1.0,  0.0),
        vec2( 0.0,  1.0), vec2( 0.0, -1.0),
        vec2( 0.707,  0.707), vec2(-0.707,  0.707),
        vec2( 0.707, -0.707), vec2(-0.707, -0.707)
    );

    for (int i = 0; i < 8; ++i) {
        vec2 sampleUV = clamp(vTexCoord + kernel[i] * pixelSize * 3.0, vec2(0.001), vec2(0.999));
        float sampleDepth = texture2D(depthtex0, sampleUV).r;

        if (sampleDepth < 0.999999) {
            float sampleDistance = length(reconstructViewPosition(sampleUV, sampleDepth));
            float separation = pixelDistance - sampleDistance;
            float rangeWeight = exp(-pixelDistance * 0.0045);
            occlusion += smoothstep(0.12, 1.65, separation) * rangeWeight;
        }
    }

    float ao = clamp(1.0 - occlusion * 0.022, 0.82, 1.0);
    scene.rgb *= ao;
#endif

#ifdef AETHER_VOLUMETRIC_FOG
    vec3 playerRelativePosition = (gbufferModelViewInverse * vec4(viewPosition, 1.0)).xyz;
    vec3 worldPosition = cameraPosition + playerRelativePosition;

    float weatherFactor = 1.0 + rainStrength * 1.55;
    float baseDensity = FOG_DENSITY * weatherFactor + clamp(fogDensity, 0.0, 1.0) * 0.0025;
    float opticalDepth = 0.0;

    // Short view-ray integration gives fog visible depth without a full 3D volume texture.
    for (int i = 0; i < 8; ++i) {
        float stepPosition = (float(i) + 0.5) / 8.0;
        vec3 samplePosition = mix(cameraPosition, worldPosition, stepPosition);
        float heightFalloff = exp(-max(samplePosition.y - 62.0, 0.0) * 0.018);
        float noise = 0.91 + 0.09 * aetherHash(floor(samplePosition * 0.075 + frameTimeCounter * 0.012));
        opticalDepth += baseDensity * heightFalloff * noise * (pixelDistance / 8.0);
    }

    vec3 atmosphereColor = mix(fogColor, skyColor, 0.22);
    atmosphereColor = mix(atmosphereColor, vec3(0.66, 0.73, 0.80), rainStrength * 0.30);

    if (isEyeInWater == 1) {
        opticalDepth += pixelDistance * 0.028;
        atmosphereColor = mix(atmosphereColor, vec3(0.025, 0.16, 0.23), 0.88);
    } else if (isEyeInWater == 2) {
        opticalDepth += pixelDistance * 0.085;
        atmosphereColor = mix(atmosphereColor, vec3(0.75, 0.16, 0.025), 0.94);
    } else if (isEyeInWater == 3) {
        opticalDepth += pixelDistance * 0.040;
        atmosphereColor = mix(atmosphereColor, vec3(0.76, 0.83, 0.88), 0.92);
    }

    float fogAmount = clamp(1.0 - exp(-opticalDepth), 0.0, 0.97);
    scene.rgb = mix(scene.rgb, atmosphereColor, fogAmount);
#endif

    gl_FragData[0] = scene;
}
