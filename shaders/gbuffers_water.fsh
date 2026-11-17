#version 330 compatibility

#include "/lib/lighting.glsl"
#include "/lib/pbr.glsl"
#include "/lib/water.glsl"

uniform sampler2D gtexture;
uniform vec3 shadowLightPosition;
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
in vec4 vShadowCoord;
in float vBlockId;

void main() {
    /* RENDERTARGETS: 0,2 */
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    if (texel.a < max(alphaTestRef, 0.001)) discard;

    // The IDs deliberately accept both direct and ID-minus-one conventions.
    bool isWater = abs(vBlockId - 119.0) < 0.25
                || abs(vBlockId - 120.0) < 0.25;
    bool isLava = abs(vBlockId - 199.0) < 0.25
               || abs(vBlockId - 200.0) < 0.25;

    vec3 albedo = aetherSRGBToLinear(texel.rgb);

    // Glass and unrelated translucent blocks keep a conservative vanilla-like path.
    if (!isWater && !isLava) {
        vec3 light = texture2D(lightmap,
            clamp(vLightCoord, vec2(0.0), vec2(1.0))).rgb;
        gl_FragData[0] = vec4(max(albedo * (light + vec3(0.025)), vec3(0.0)), texel.a);
        gl_FragData[1] = vec4(0.0);
        return;
    }

    if (isLava) {
        float flow = 0.96 + 0.04 * sin(
            (vPlayerPos.x + vPlayerPos.z) * 0.10 + frameTimeCounter * 1.35
        );
        vec3 emission = vec3(1.0, 0.19, 0.025) * (1.45 + flow * 0.38);
        gl_FragData[0] = vec4(emission, texel.a);
        gl_FragData[1] = vec4(0.0);
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
    vec3 lightDirection = normalize(shadowLightPosition);

    float nDotV = clamp(dot(viewNormal, viewDirection), 0.0, 1.0);
    float fresnel = 0.02 + 0.98 * pow(1.0 - nDotV, 5.0);
    float skyLight = clamp(vLightCoord.y, 0.0, 1.0);

    vec3 deepWater = vec3(0.0035, 0.027, 0.043);
    vec3 shallowWater = vec3(0.010, 0.095, 0.112);
    vec3 waterColor = mix(deepWater, shallowWater, smoothstep(0.05, 0.95, skyLight));

    float shadow = aetherShadowPCF(vShadowCoord, worldNormal, lightDirection);
    float sunSpecular = pow(max(dot(reflect(-lightDirection, worldNormal),
                                    normalize(cameraPosition - worldPosition)), 0.0), 96.0);
    vec3 sunGlint = vec3(1.0, 0.91, 0.73) * sunSpecular * shadow * 0.9;
    vec3 litWater = waterColor + sunGlint;

    // Alpha blending accumulates the water mask without glass clearing an existing pixel.
    float waterAlpha = mix(0.62, 0.90, fresnel);
    gl_FragData[0] = vec4(max(litWater, vec3(0.0)), waterAlpha);
    gl_FragData[1] = vec4(viewNormal * 0.5 + 0.5, 1.0);
}
