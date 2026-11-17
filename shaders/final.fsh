#version 330 compatibility

#include "/lib/pbr.glsl"

#define AETHER_BLOOM // [true false]
#define AETHER_VIGNETTE // [true false]
#define AETHER_UNDERWATER // [true false]

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform mat4 gbufferProjectionInverse;
uniform float viewWidth;
uniform float viewHeight;
uniform float frameTimeCounter;
uniform int isEyeInWater;

in vec2 vTexCoord;

vec3 aetherACES(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

vec3 aetherUnderwaterGrade(vec3 sourceColor) {
    float depth = texture2D(depthtex0, vTexCoord).r;
    vec4 clipPosition = vec4(vTexCoord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPosition = gbufferProjectionInverse * clipPosition;
    vec3 viewPosition3 = viewPosition.xyz / max(viewPosition.w, 0.00001);
    float sceneDistance = min(length(viewPosition3), 150.0);

    // A restrained underwater look: absorb reds and fade distant objects into blue-green.
    vec3 absorption = vec3(0.78, 0.93, 0.98);
    vec3 deepWaterColor = vec3(0.009, 0.075, 0.095);
    float distanceFog = depth >= 0.999999
        ? 0.80
        : 1.0 - exp(-sceneDistance * 0.010);
    float fogAmount = clamp(distanceFog * 0.68, 0.0, 0.78);

    vec3 color = sourceColor * absorption;
    color = mix(color, deepWaterColor, fogAmount);
    return color;
}

void main() {
    vec3 color = texture2D(colortex0, vTexCoord).rgb;

#ifdef AETHER_UNDERWATER
    if (isEyeInWater == 1) {
        color = aetherUnderwaterGrade(color);
    } else if (isEyeInWater == 2) {
        color = mix(color * vec3(1.06, 0.55, 0.30), vec3(0.17, 0.014, 0.002), 0.20);
    } else if (isEyeInWater == 3) {
        color = mix(color, vec3(0.66, 0.77, 0.84), 0.22);
    }
#endif

#ifdef AETHER_BLOOM
    vec2 texel = 1.0 / vec2(viewWidth, viewHeight);
    vec3 bloom = vec3(0.0);
    const vec2 offsets[8] = vec2[8](
        vec2( 1.0,  0.0), vec2(-1.0,  0.0),
        vec2( 0.0,  1.0), vec2( 0.0, -1.0),
        vec2( 1.0,  1.0), vec2(-1.0,  1.0),
        vec2( 1.0, -1.0), vec2(-1.0, -1.0)
    );
    for (int i = 0; i < 8; ++i) {
        vec3 sampleColor = texture2D(colortex0, vTexCoord + offsets[i] * texel * 2.0).rgb;
        float luminance = dot(sampleColor, vec3(0.2126, 0.7152, 0.0722));
        bloom += sampleColor * smoothstep(1.10, 2.10, luminance);
    }
    color += bloom * (isEyeInWater == 1 ? 0.002 : 0.006);
#endif

    color = aetherACES(color * 0.78);

#ifdef AETHER_VIGNETTE
    vec2 centered = (vTexCoord - 0.5) * vec2(1.0, viewHeight / viewWidth);
    float vignette = dot(centered, centered);
    color *= 1.0 - smoothstep(0.28, 0.88, vignette) * 0.075;
#endif

    color = aetherLinearToSRGB(color);
    gl_FragColor = vec4(color, 1.0);
}
