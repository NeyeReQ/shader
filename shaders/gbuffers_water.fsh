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

void main() {
    /* RENDERTARGETS: 0,2,3 */
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    if (texel.a < max(alphaTestRef, 0.001)) discard;

    // block.properties assigns water ID 120. Check the material ID directly;
    // mc_Entity.y is block metadata, not a reliable fluid flag.
    bool isWater = abs(vBlockId - 120.0) < 0.25
                || abs(vBlockId - 119.0) < 0.25;
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

    // Tropical coastal palette: darker blue offshore, brighter cyan where
    // the water receives more skylight. Depth absorption is added later in
    // the composite pass, where the actual scene depth is known.
    vec3 deepWater = vec3(0.010, 0.052, 0.104);
    vec3 shallowWater = vec3(0.050, 0.285, 0.335);
    vec3 waterColor = mix(deepWater, shallowWater,
                          smoothstep(0.025, 0.98, skyLight));
    float textureContrast = mix(0.78, 1.24, pattern);
    vec3 sampledTint = clamp(sqrt(max(albedo, vec3(0.0))) * 1.10,
                             vec3(0.76), vec3(1.12));
    waterColor *= textureContrast * mix(vec3(1.0), sampledTint, 0.12);

    // Fine bright crests give the sunlit surface a broken, moving highlight
    // rather than the flat, uniform blue of vanilla water.
    float crestHighlight = smoothstep(0.76, 0.94, pattern) * 0.26;
    waterColor = mix(waterColor, vec3(0.24, 0.48, 0.52), crestHighlight);

    // Direct moving sun glints keep the water visibly alive even where SSR
    // cannot find a hit in the scene.
    vec3 lightDirection = normalize(shadowLightPosition);
    float reflectedSun = max(dot(reflect(-lightDirection, viewNormal),
                                 viewDirection), 0.0);
    float sharpGlint = pow(reflectedSun, 96.0);
    float broadGlint = pow(reflectedSun, 28.0);
    float glintModulation = mix(0.55, 1.0, pattern);
    vec3 sunGlint = vec3(1.0, 0.94, 0.82)
                  * (sharpGlint * 0.86 + broadGlint * 0.085)
                  * glintModulation;
    waterColor += sunGlint;

    // Leave colortex0 untouched at water pixels. The composite stage reads the
    // untouched scene and applies refraction/reflection once using these buffers.
    gl_FragData[0] = vec4(0.0);
    gl_FragData[1] = vec4(viewNormal * 0.5 + 0.5, 1.0);
    gl_FragData[2] = vec4(waterColor, gl_FragCoord.z);
}
