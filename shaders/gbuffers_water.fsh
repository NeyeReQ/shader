#version 330 compatibility

#include "/lib/lighting.glsl"
#include "/lib/pbr.glsl"
#include "/lib/water.glsl"

uniform sampler2D gtexture;
uniform vec3 cameraPosition;
uniform mat4 gbufferModelView;
uniform float frameTimeCounter;
uniform float alphaTestRef;

in vec2 vTexCoord;
in vec2 vLightCoord;
in vec4 vColor;
in vec3 vViewPos;
in vec3 vPlayerPos;
in vec3 vPlayerNormal;
in float vBlockId;

void main() {
    /* RENDERTARGETS: 0,2,3 */
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    if (texel.a < max(alphaTestRef, 0.001)) discard;

    bool isWater = abs(vBlockId - 119.0) < 0.25
                || abs(vBlockId - 120.0) < 0.25;
    bool isLava = abs(vBlockId - 199.0) < 0.25
               || abs(vBlockId - 200.0) < 0.25;

    vec3 albedo = aetherSRGBToLinear(texel.rgb);

    // Ordinary translucent blocks keep their normal alpha-blended scene colour.
    if (!isWater && !isLava) {
        vec3 light = texture2D(lightmap,
            clamp(vLightCoord, vec2(0.0), vec2(1.0))).rgb;
        gl_FragData[0] = vec4(max(albedo * (light + vec3(0.025)), vec3(0.0)), texel.a);
        gl_FragData[1] = vec4(0.0);
        gl_FragData[2] = vec4(0.0);
        return;
    }

    if (isLava) {
        float flow = 0.96 + 0.04 * sin(
            (vPlayerPos.x + vPlayerPos.z) * 0.10 + frameTimeCounter * 1.35
        );
        vec3 emission = vec3(1.0, 0.19, 0.025) * (1.10 + flow * 0.26);
        gl_FragData[0] = vec4(emission, texel.a);
        gl_FragData[1] = vec4(0.0);
        gl_FragData[2] = vec4(0.0);
        return;
    }

    vec3 worldPosition = cameraPosition + vPlayerPos;
    vec3 geometricNormal = normalize(vPlayerNormal);
    vec3 worldNormal = aetherWaterNormal(
        worldPosition.xz,
        frameTimeCounter,
        geometricNormal,
        cameraPosition - worldPosition
    );
    vec3 viewNormal = normalize(mat3(gbufferModelView) * worldNormal);
    vec3 viewDirection = normalize(-vViewPos);
    if (dot(viewNormal, viewDirection) < 0.0) viewNormal = -viewNormal;

    float skyLight = clamp(vLightCoord.y, 0.0, 1.0);
    float pattern = aetherWaterPattern(worldPosition.xz, frameTimeCounter);

    vec3 deepWater = vec3(0.0025, 0.018, 0.029);
    vec3 shallowWater = vec3(0.012, 0.088, 0.108);
    vec3 waterColor = mix(deepWater, shallowWater,
                          smoothstep(0.04, 0.96, skyLight));
    float textureContrast = mix(0.70, 1.24, pattern);
    vec3 sampledTint = clamp(sqrt(max(albedo, vec3(0.0))) * 1.15,
                             vec3(0.68), vec3(1.18));
    waterColor *= textureContrast * mix(vec3(1.0), sampledTint, 0.20);

    float crestHighlight = smoothstep(0.74, 0.91, pattern) * 0.13;
    waterColor = mix(waterColor, vec3(0.105, 0.19, 0.205), crestHighlight);

    // Leave colortex0 untouched at water pixels. The composite stage reads the
    // untouched scene and applies refraction/reflection once using these buffers.
    gl_FragData[0] = vec4(0.0);
    gl_FragData[1] = vec4(viewNormal * 0.5 + 0.5, 1.0);
    gl_FragData[2] = vec4(waterColor, gl_FragCoord.z);
}
