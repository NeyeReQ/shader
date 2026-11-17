#version 330 compatibility

#define AETHER_BLOOM // [true false]
#define AETHER_VIGNETTE // [true false]

uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;

in vec2 vTexCoord;

vec3 aetherACES(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

void main() {
    vec3 color = texture2D(colortex0, vTexCoord).rgb;

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
    color += bloom * 0.018;
#endif

    color = aetherACES(color * 1.08);

#ifdef AETHER_VIGNETTE
    vec2 centered = (vTexCoord - 0.5) * vec2(1.0, viewHeight / viewWidth);
    float vignette = dot(centered, centered);
    color *= 1.0 - smoothstep(0.28, 0.88, vignette) * 0.075;
#endif

    color = aetherLinearToSRGB(color);
    gl_FragColor = vec4(color, 1.0);
}
