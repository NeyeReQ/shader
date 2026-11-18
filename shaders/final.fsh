#version 330 compatibility

#include "/lib/pbr.glsl"

#define AETHER_BLOOM // [true false]
#define AETHER_VIGNETTE // [true false]
#define AETHER_UNDERWATER // [true false]

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform float viewWidth;
uniform float viewHeight;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform int isEyeInWater;

in vec2 vTexCoord;

vec3 aetherFinalSafeNormalize(vec3 value, vec3 fallbackValue) {
    float magnitudeSquared = dot(value, value);
    return (magnitudeSquared > 1e-8 && magnitudeSquared < 1e20)
        ? value * inversesqrt(magnitudeSquared)
        : fallbackValue;
}

vec3 aetherACES(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

float aetherUnderwaterHash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float aetherUnderwaterNoise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = aetherUnderwaterHash(cell);
    float b = aetherUnderwaterHash(cell + vec2(1.0, 0.0));
    float c = aetherUnderwaterHash(cell + vec2(0.0, 1.0));
    float d = aetherUnderwaterHash(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float aetherCaustics(vec3 worldPosition, float time) {
    vec2 p = worldPosition.xz * 0.18;
    vec2 warp = vec2(
        aetherUnderwaterNoise(p * 0.56 + vec2(time * 0.11, -time * 0.07)),
        aetherUnderwaterNoise(p * 0.56 + vec2(17.0 - time * 0.08, 9.0 + time * 0.10))
    ) - 0.5;
    p += warp * 1.45;
    float waveA = sin(dot(p, vec2(1.00, 0.73)) * 3.15
                    + sin(dot(p, vec2(-0.42, 1.0)) * 2.1 + time * 1.15) * 1.25
                    + time * 1.35);
    float waveB = sin(dot(p, vec2(-0.68, 1.08)) * 3.55
                    + sin(dot(p, vec2(1.0, 0.24)) * 1.9 - time * 0.95) * 1.10
                    - time * 1.18);
    float lattice = 1.0 - abs(waveA * waveB);
    return pow(clamp(lattice, 0.0, 1.0), 7.0);
}

vec2 aetherUnderwaterRefraction(vec2 uv, float time) {
    vec2 p = uv * vec2(29.0, 20.0);
    float waveA = sin(p.x * 0.91 + sin(p.y * 0.67 + time * 0.74) * 1.45 + time * 0.62);
    float waveB = cos(p.y * 1.07 + sin(p.x * 0.58 - time * 0.61) * 1.25 - time * 0.51);
    vec2 distortion = vec2(waveA, waveB) * vec2(0.0019, 0.0027);
    return clamp(uv + distortion, vec2(0.001), vec2(0.999));
}

vec3 aetherUnderwaterGrade(vec3 sourceColor, vec2 sampleUV) {
    float depth = texture2D(depthtex0, sampleUV).r;
    vec4 clipPosition = vec4(sampleUV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPosition4 = gbufferProjectionInverse * clipPosition;
    vec3 viewPosition = viewPosition4.xyz / max(abs(viewPosition4.w), 0.00001);
    float sceneDistance = min(length(viewPosition), 190.0);
    vec3 absorption = vec3(0.73, 0.90, 0.94);
    vec3 deepWaterColor = vec3(0.006, 0.050, 0.064);
    float distanceFog = depth >= 0.999999 ? 0.92 : 1.0 - exp(-sceneDistance * 0.0078);
    float fogAmount = clamp(distanceFog * 0.78, 0.0, 0.84);
    vec3 color = mix(sourceColor * absorption, deepWaterColor, fogAmount);

    vec3 playerRelativePosition = (gbufferModelViewInverse * vec4(viewPosition, 1.0)).xyz;
    vec3 worldPosition = cameraPosition + playerRelativePosition;
    vec3 sunDirection = aetherFinalSafeNormalize(
        mat3(gbufferModelViewInverse) * sunPosition, vec3(0.0, 1.0, 0.0)
    );
    float daylight = smoothstep(-0.08, 0.22, sunDirection.y);
    float caustic = aetherCaustics(worldPosition, frameTimeCounter);
    float causticFade = exp(-sceneDistance * 0.015);
    float causticStrength = daylight * (1.0 - rainStrength * 0.48)
                          * causticFade * smoothstep(0.5, 8.0, worldPosition.y + 64.0);
    color += vec3(0.035, 0.16, 0.145) * caustic * causticStrength;

    float rayPattern = aetherUnderwaterNoise(
        vec2(sampleUV.x * 8.5 + sampleUV.y * 2.2,
             sampleUV.y * 7.0 - frameTimeCounter * 0.045)
    );
    float lightShafts = smoothstep(0.53, 0.82, rayPattern)
                      * smoothstep(0.0, 0.75, sampleUV.y)
                      * exp(-sceneDistance * 0.009);
    color += vec3(0.012, 0.045, 0.050) * lightShafts * daylight
           * (1.0 - rainStrength * 0.55);

    vec2 particleGrid = sampleUV * vec2(34.0, 22.0)
                      + vec2(frameTimeCounter * 0.025, -frameTimeCounter * 0.038);
    vec2 particleCell = floor(particleGrid);
    vec2 particleLocal = fract(particleGrid);
    float particleSeed = aetherUnderwaterHash(particleCell);
    vec2 particleOffset = vec2(
        aetherUnderwaterHash(particleCell + vec2(13.0, 4.0)),
        aetherUnderwaterHash(particleCell + vec2(5.0, 19.0))
    );
    float particleShape = 1.0 - smoothstep(0.018, 0.045,
                                           length(particleLocal - particleOffset));
    float particles = step(0.985, particleSeed) * particleShape
                    * exp(-sceneDistance * 0.012);
    color += vec3(0.12, 0.22, 0.22) * particles * 0.14;

    vec2 centered = (sampleUV - 0.5) * vec2(1.0, viewHeight / viewWidth);
    float underwaterVignette = smoothstep(0.20, 0.80, dot(centered, centered));
    color *= 1.0 - underwaterVignette * 0.10;
    return color;
}

void main() {
    vec2 sampleUV = vTexCoord;
    if (isEyeInWater == 1) sampleUV = aetherUnderwaterRefraction(vTexCoord, frameTimeCounter);
    vec3 color = texture2D(colortex0, sampleUV).rgb;

#ifdef AETHER_UNDERWATER
    if (isEyeInWater == 1) {
        color = aetherUnderwaterGrade(color, sampleUV);
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

    color = aetherACES(color);

    // Subtle teal shadows and warm daylight highlights create a restrained
    // cinematic split tone without crushing Minecraft's natural block colours.
    vec3 sunDirection = aetherFinalSafeNormalize(
        mat3(gbufferModelViewInverse) * sunPosition, vec3(0.0, 1.0, 0.0)
    );
    float daylight = smoothstep(-0.16, 0.20, sunDirection.y);
    float goldenHour = 1.0 - smoothstep(0.035, 0.36, abs(sunDirection.y));
    float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
    float shadowWeight = 1.0 - smoothstep(0.045, 0.42, luminance);
    float highlightWeight = smoothstep(0.48, 0.92, luminance) * daylight;

    vec3 coolShadowTint = vec3(0.965, 0.990, 1.035);
    vec3 warmHighlightTint = mix(
        vec3(1.025, 1.010, 0.985),
        vec3(1.060, 1.010, 0.955),
        goldenHour * 0.78
    );
    color *= mix(vec3(1.0), coolShadowTint, shadowWeight * 0.16);
    color *= mix(vec3(1.0), warmHighlightTint, highlightWeight * 0.28);

    luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(luminance), color, mix(1.015, 1.04, daylight));
    color = clamp((color - 0.18) * 1.04 + 0.18, 0.0, 1.0);

#ifdef AETHER_VIGNETTE
    vec2 centered = (vTexCoord - 0.5) * vec2(1.0, viewHeight / viewWidth);
    float vignette = dot(centered, centered);
    color *= 1.0 - smoothstep(0.28, 0.88, vignette) * 0.075;
#endif
    color = aetherLinearToSRGB(color);
    gl_FragColor = vec4(color, 1.0);
}
