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
    vec3 viewRayPosition = viewPosition.xyz / max(viewPosition.w, 0.00001);
    float distanceToSurface = min(length(viewRayPosition), 180.0);

    // Red wavelengths are absorbed first; distant geometry fades into blue-green water.
    vec3 absorptionTint = vec3(0.60, 0.88, 0.98);
    vec3 waterFogColor = vec3(0.006, 0.072, 0.092);
    float distanceFog = depth >= 0.999999
        ? 0.92
        : 1.0 - exp(-distanceToSurface * 0.021);
    float fogAmount = clamp(distanceFog * 0.88, 0.0, 0.94);

    vec3 color = sourceColor * absorptionTint;
    color = mix(color, waterFogColor, fogAmount);

    // Subtle moving caustic shimmer on nearby surfaces only.
    float nearSurface = (1.0 - smoothstep(8.0, 52.0, distanceToSurface))
                      * (1.0 - step(0.999999, depth));
    float causticWave = sin(vTexCoord.x * 71.0 + frameTimeCounter * 0.34
                         + sin(vTexCoord.y * 53.0 - frameTimeCounter * 0.22) * 1.8);
    float caustic = pow(max(causticWave * 0.5 + 0.5, 0.0), 12.0);
    color += vec3(0.010, 0.035, 0.033) * caustic * nearSurface;

    vec2 centered = (vTexCoord - 0.5) * vec2(1.0, viewHeight / viewWidth);
    float edge = dot(centered, centered);
    color *= 1.0 - smoothstep(0.18, 0.82, edge) * 0.14;

    return color;
}

void main() {
    vec3 color = texture2D(colortex0, vTexCoord).rgb;

#ifdef AETHER_UNDERWATER
    if (isEyeInWater == 1) {
        color = aetherUnderwaterGrade(color);
    } else if (isEyeInWater == 2) {
        color = mix(color * vec3(1.08, 0.46, 0.24), vec3(0.22, 0.018, 0.003), 0.24);
    } else if (isEyeInWater == 3) {
        color = mix(color, vec3(0.62, 0.75, 0.82), 0.30);
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
    color += bloom * (isEyeInWater == 1 ? 0.006 : 0.018);
#endif

    color = aetherACES(color * 1.04);

#ifdef AETHER_VIGNETTE
    vec2 centered = (vTexCoord - 0.5) * vec2(1.0, viewHeight / viewWidth);
    float vignette = dot(centered, centered);
    color *= 1.0 - smoothstep(0.28, 0.88, vignette) * 0.075;
#endif

    color = aetherLinearToSRGB(color);
    gl_FragColor = vec4(color, 1.0);
}
