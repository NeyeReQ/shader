#version 330 compatibility

#define AETHER_BLOOM // Restrained highlight bloom.
#define AETHER_VIGNETTE // Subtle cinematic lens falloff.
#define AETHER_GRAIN // Fine film grain.

uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;
uniform int frameCounter;

in vec2 vTexCoord;

vec3 aetherACES(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

float aetherNoise(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec3 color = texture2D(colortex0, vTexCoord).rgb;

#ifdef AETHER_BLOOM
    vec2 texel = 1.0 / vec2(viewWidth, viewHeight);
    vec3 bloom = vec3(0.0);
    const vec2 bloomOffsets[8] = vec2[8](
        vec2( 1.0,  0.0), vec2(-1.0,  0.0),
        vec2( 0.0,  1.0), vec2( 0.0, -1.0),
        vec2( 1.0,  1.0), vec2(-1.0,  1.0),
        vec2( 1.0, -1.0), vec2(-1.0, -1.0)
    );

    for (int i = 0; i < 8; ++i) {
        vec3 sampleColor = texture2D(colortex0, vTexCoord + bloomOffsets[i] * texel * 2.0).rgb;
        float luma = dot(sampleColor, vec3(0.2126, 0.7152, 0.0722));
        bloom += sampleColor * smoothstep(0.70, 1.25, luma);
    }

    color += bloom * 0.010;
#endif

    // Gentle warm highlights and cool shadows, without crushing Minecraft's palette.
    float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(luminance), color, 1.055);
    color *= vec3(1.018, 1.000, 0.982);
    color = aetherACES(color * 1.08);

#ifdef AETHER_VIGNETTE
    vec2 centered = vTexCoord - 0.5;
    float vignette = dot(centered, centered);
    color *= 1.0 - smoothstep(0.18, 0.78, vignette) * 0.17;
#endif

#ifdef AETHER_GRAIN
    float grain = aetherNoise(gl_FragCoord.xy + vec2(float(frameCounter) * 0.37, float(frameCounter) * 0.19));
    color += (grain - 0.5) * 0.006;
#endif

    color = pow(max(color, vec3(0.0)), vec3(1.0 / 2.2));
    gl_FragColor = vec4(color, 1.0);
}
