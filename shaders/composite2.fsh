#version 330 compatibility

#define AETHER_GODRAYS // Soft screen-space sunlight scattering.

uniform sampler2D colortex1;
uniform sampler2D depthtex0;
uniform mat4 gbufferProjection;
uniform vec3 sunPosition;
uniform float rainStrength;

in vec2 vTexCoord;

void main() {
    /* DRAWBUFFERS:0 */
    vec3 color = texture2D(colortex1, vTexCoord).rgb;

#ifdef AETHER_GODRAYS
    vec3 sunDirection = normalize(sunPosition);
    vec4 sunClip = gbufferProjection * vec4(sunDirection * 1000.0, 1.0);

    if (sunClip.w > 0.0 && sunDirection.z < 0.0) {
        vec2 sunUV = sunClip.xy / sunClip.w * 0.5 + 0.5;
        float inFrame = step(0.0, sunUV.x) * step(sunUV.x, 1.0)
                      * step(0.0, sunUV.y) * step(sunUV.y, 1.0);

        if (inFrame > 0.0) {
            float scattering = 0.0;
            vec2 rayStep = (sunUV - vTexCoord) / 14.0;

            for (int i = 0; i < 14; ++i) {
                vec2 sampleUV = clamp(vTexCoord + rayStep * float(i), vec2(0.001), vec2(0.999));
                float depth = texture2D(depthtex0, sampleUV).r;
                float skyMask = smoothstep(0.9988, 1.0, depth);
                vec3 sampleColor = texture2D(colortex1, sampleUV).rgb;
                float luminance = dot(sampleColor, vec3(0.2126, 0.7152, 0.0722));
                float brightness = 0.45 + smoothstep(0.38, 0.95, luminance) * 0.55;
                scattering += skyMask * brightness * (1.0 - float(i) / 14.0);
            }

            scattering /= 14.0;
            float shaftStrength = scattering * inFrame * (0.18 + rainStrength * 0.08);
            color += vec3(1.00, 0.78, 0.55) * shaftStrength;
        }
    }
#endif

    gl_FragData[0] = vec4(color, 1.0);
}
