#version 330 compatibility

#include "/lib/lighting.glsl"
#include "/lib/pbr.glsl"
#include "/lib/water.glsl"

uniform sampler2D gtexture;
uniform vec3 cameraPosition;
uniform vec3 shadowLightPosition;
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
in float vIsFluid;

void main() {
    /* RENDERTARGETS: 0,2,3 */
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    if (texel.a < max(alphaTestRef, 0.001)) discard;

    // Vitrail/Iris encode fluid geometry in mc_Entity.y. This avoids relying
    // solely on a material ID when a pack is used on a new backend.
    bool isWater = vIsFluid > 0.5;
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

    vec3 deepWater = vec3(0.006, 0.031, 0.046);
    vec3 shallowWater = vec3(0.019, 0.115, 0.137);
    vec3 waterColor = mix(deepWater, shallowWater,
                          smoothstep(0.04, 0.96, skyLight));
    float textureContrast = mix(0.58, 1.42, pattern);
    vec3 sampledTint = clamp(sqrt(max(albedo, vec3(0.0))) * 1.15,
                             vec3(0.68), vec3(1.18));
    waterColor *= textureContrast * mix(vec3(1.0), sampledTint, 0.20);

    float crestHighlight = smoothstep(0.70, 0.90, pattern) * 0.19;
    waterColor = mix(waterColor, vec3(0.12, 0.23, 0.25), crestHighlight);

    // Direct moving sun glints keep the water visibly alive even where SSR
    // cannot find a hit in the scene.
    vec3 lightDirection = normalize(shadowLightPosition);
    float reflectedSun = max(dot(reflect(-lightDirection, viewNormal),
                                 viewDirection), 0.0);
    float sharpGlint = pow(reflectedSun, 96.0);
    float broadGlint = pow(reflectedSun, 28.0);
    float glintModulation = mix(0.55, 1.0, pattern);
    vec3 sunGlint = vec3(1.0, 0.91, 0.76)
                  * (sharpGlint * 0.75 + broadGlint * 0.055)
                  * glintModulation;
    waterColor += sunGlint;

    // Leave colortex0 untouched at water pixels. The composite stage reads the
    // untouched scene and applies refraction/reflection once using these buffers.
    gl_FragData[0] = vec4(0.0);
    gl_FragData[1] = vec4(viewNormal * 0.5 + 0.5, 1.0);
    gl_FragData[2] = vec4(waterColor, gl_FragCoord.z);
}
