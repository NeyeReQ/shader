#version 330 compatibility

#include "/lib/pbr.glsl"

#define AETHER_SSAO // [true false]
#define AETHER_VOLUMETRIC_FOG // [true false]
#define AETHER_CLOUDS // [true false]
#define FOG_DENSITY 0.00038 // [0.00010 0.00018 0.00028 0.00038 0.00050 0.00065]

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform float fogDensity;
uniform float rainStrength;
uniform float frameTimeCounter;
uniform float viewWidth;
uniform float viewHeight;
uniform int isEyeInWater;

in vec2 vTexCoord;

#include "/lib/sky.glsl"

vec3 aetherReconstructViewPosition(vec2 uv, float depth) {
    vec4 clipPosition = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPosition = gbufferProjectionInverse * clipPosition;
    return viewPosition.xyz / max(viewPosition.w, 0.00001);
}

float aetherFogNoise(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

void main() {
    /* RENDERTARGETS: 1 */
    vec4 scene = texture2D(colortex0, vTexCoord);
    float depth = texture2D(depthtex0, vTexCoord).r;

    if (depth >= 0.999999) {
        if (hasSkylight && isEyeInWater == 0) {
            vec2 ndc = vTexCoord * 2.0 - 1.0;
            vec4 farPoint = gbufferProjectionInverse * vec4(ndc, 1.0, 1.0);
            vec3 viewRay = normalize(farPoint.xyz);
            vec3 playerRay = normalize(mat3(gbufferModelViewInverse) * viewRay);
            scene = vec4(aetherRenderSky(playerRay, cameraPosition), 1.0);
        }
        gl_FragData[0] = scene;
        return;
    }

    vec3 viewPosition = aetherReconstructViewPosition(vTexCoord, depth);
    float pixelDistance = length(viewPosition);

#ifdef AETHER_SSAO
    float occlusion = 0.0;
    vec2 pixelSize = 1.0 / vec2(viewWidth, viewHeight);
    const vec2 taps[8] = vec2[8](
        vec2( 1.0,  0.0), vec2(-1.0,  0.0),
        vec2( 0.0,  1.0), vec2( 0.0, -1.0),
        vec2( 0.707,  0.707), vec2(-0.707,  0.707),
        vec2( 0.707, -0.707), vec2(-0.707, -0.707)
    );

    for (int i = 0; i < 8; ++i) {
        vec2 sampleUV = clamp(vTexCoord + taps[i] * pixelSize * 3.5, vec2(0.001), vec2(0.999));
        float sampleDepth = texture2D(depthtex0, sampleUV).r;

        if (sampleDepth < 0.999999) {
            vec3 samplePosition = aetherReconstructViewPosition(sampleUV, sampleDepth);
            float closerDelta = samplePosition.z - viewPosition.z;
            float distanceWeight = 1.0 - smoothstep(10.0, 34.0, pixelDistance);
            occlusion += smoothstep(0.08, 0.90, closerDelta) * distanceWeight;
        }
    }

    float ao = clamp(1.0 - occlusion * 0.010, 0.88, 1.0);
    scene.rgb *= ao;
#endif

#ifdef AETHER_VOLUMETRIC_FOG
    vec3 playerRelativePosition = (gbufferModelViewInverse * vec4(viewPosition, 1.0)).xyz;
    vec3 worldPosition = cameraPosition + playerRelativePosition;
    vec3 viewRayPlayer = normalize(playerRelativePosition);
    vec3 sunDirectionPlayer = normalize(mat3(gbufferModelViewInverse) * sunPosition);

    float density = FOG_DENSITY + clamp(fogDensity, 0.0, 1.0) * 0.00032;
    density *= 1.0 + rainStrength * 1.45;
    if (isEyeInWater == 1) density *= 3.2;
    if (isEyeInWater == 2) density *= 8.0;
    if (isEyeInWater == 3) density *= 2.4;

    float opticalDepth = 0.0;
    const int FOG_STEPS = 12;
    float stepLength = pixelDistance / float(FOG_STEPS);

    for (int i = 0; i < FOG_STEPS; ++i) {
        float stepFraction = (float(i) + 0.5) / float(FOG_STEPS);
        vec3 samplePosition = mix(cameraPosition, worldPosition, stepFraction);
        float heightDensity = exp(-max(samplePosition.y - 68.0, 0.0) * 0.014);
        heightDensity *= 1.0 + min(max(58.0 - samplePosition.y, 0.0) * 0.004, 0.18);

        vec3 noisePosition = floor(samplePosition * vec3(0.055, 0.035, 0.055)
                                + vec3(frameTimeCounter * 0.012, 0.0, frameTimeCounter * 0.009));
        float densityNoise = mix(0.94, 1.06, aetherFogNoise(noisePosition));
        opticalDepth += density * heightDensity * densityNoise * stepLength;
    }

    vec3 atmosphereColor = mix(aetherSRGBToLinear(fogColor), aetherSRGBToLinear(skyColor), 0.18);
    if (isEyeInWater == 1) {
        atmosphereColor = vec3(0.018, 0.105, 0.145);
    } else if (isEyeInWater == 2) {
        atmosphereColor = vec3(0.42, 0.095, 0.018);
    } else if (isEyeInWater == 3) {
        atmosphereColor = vec3(0.52, 0.66, 0.73);
    } else {
        float cosTheta = dot(viewRayPlayer, sunDirectionPlayer);
        float g = 0.58;
        float phase = (1.0 - g * g) /
            (4.0 * AETHER_PI * pow(max(1.0 + g * g - 2.0 * g * cosTheta, 0.001), 1.5));
        float sunElevation = smoothstep(-0.04, 0.18, sunDirectionPlayer.y);
        atmosphereColor += vec3(1.0, 0.78, 0.56) * phase * sunElevation * 0.025;
        atmosphereColor = mix(atmosphereColor, vec3(0.64, 0.69, 0.73), rainStrength * 0.22);
    }

    float fogAmount = clamp(1.0 - exp(-opticalDepth), 0.0, 0.90);
    scene.rgb = mix(scene.rgb, atmosphereColor, fogAmount);
#endif

    gl_FragData[0] = scene;
}
