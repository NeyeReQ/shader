#version 330 compatibility

#define AETHER_GODRAYS // [true false]

uniform sampler2D colortex1;
uniform sampler2D depthtex0;
uniform mat4 gbufferProjection;
uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform float rainStrength;

in vec2 vTexCoord;

void main() {
    /* RENDERTARGETS: 0 */
    vec3 color = texture2D(colortex1, vTexCoord).rgb;

#ifdef AETHER_GODRAYS
    vec4 sunClip = gbufferProjection * vec4(sunPosition, 1.0);
    if (sunClip.w > 0.0) {
        vec2 sunUV = sunClip.xy / sunClip.w * 0.5 + 0.5;
        float sunVisible = step(0.0, sunUV.x) * step(sunUV.x, 1.0)
                         * step(0.0, sunUV.y) * step(sunUV.y, 1.0);

        if (sunVisible > 0.0) {
            float scattering = 0.0;
            vec2 rayStep = (sunUV - vTexCoord) / 20.0;
            for (int i = 0; i < 20; ++i) {
                vec2 sampleUV = clamp(vTexCoord + rayStep * float(i), vec2(0.001), vec2(0.999));
                float depth = texture2D(depthtex0, sampleUV).r;
                float skyMask = smoothstep(0.9990, 1.0, depth);
                scattering += skyMask * (1.0 - float(i) / 20.0);
            }

            scattering /= 20.0;
            vec3 sunDirectionPlayer = normalize(mat3(gbufferModelViewInverse) * sunPosition);
            float daylight = smoothstep(-0.04, 0.16, sunDirectionPlayer.y);
            color += vec3(1.0, 0.79, 0.57)
                   * scattering * sunVisible * daylight * (0.11 - rainStrength * 0.025);
        }
    }
#endif

    gl_FragData[0] = vec4(color, 1.0);
}
