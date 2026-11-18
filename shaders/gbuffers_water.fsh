#version 330 compatibility

#include "/lib/pbr.glsl"
#include "/lib/water.glsl"

uniform sampler2D gtexture;
uniform vec3 cameraPosition;
uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelView;
uniform vec3 fogColor;
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
    /* RENDERTARGETS: 0 */
    vec4 texel = texture2D(gtexture, vTexCoord) * vColor;
    if (texel.a < max(alphaTestRef, 0.001)) discard;

    bool isLava = vIsFluid > 0.5
               && (abs(vBlockId - 199.0) < 0.25
                || abs(vBlockId - 200.0) < 0.25);
    bool isWater = !isLava
                && (vIsFluid > 0.5 || abs(vBlockId - 120.0) < 0.25);

    vec3 albedo = aetherSRGBToLinear(texel.rgb);

    // The translucent terrain pass also contains glass and other blocks.
    // They retain ordinary alpha blending and never write water-only data.
    if (!isWater && !isLava) {
        vec3 light = texture2D(lightmap,
            clamp(vLightCoord, vec2(0.0), vec2(1.0))).rgb;
        gl_FragData[0] = vec4(max(albedo * (light + vec3(0.025)), vec3(0.0)), texel.a);
        return;
    }

    if (isLava) {
        float flow = 0.96 + 0.04 * sin(
            (vPlayerPos.x + vPlayerPos.z) * 0.10 + frameTimeCounter * 1.35
        );
        vec3 emission = vec3(1.0, 0.25, 0.075) * (1.05 + flow * 0.20);
        gl_FragData[0] = vec4(emission, max(texel.a, 0.88));
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

    float nDotV = clamp(dot(viewNormal, viewDirection), 0.0, 1.0);
    float fresnel = 0.025 + 0.78 * pow(1.0 - nDotV, 5.0);
    float pattern = aetherWaterPattern(worldPosition.xz, frameTimeCounter);
    float skyLight = clamp(vLightCoord.y, 0.0, 1.0);

    // A restrained natural ocean palette: deep blue-green in open water,
    // lighter only where the surface catches daylight. Avoid the old neon cyan.
    vec3 deepWater = vec3(0.008, 0.022, 0.033);
    vec3 midWater = vec3(0.018, 0.054, 0.068);
    vec3 sunlitWater = vec3(0.050, 0.105, 0.112);
    vec3 waterBody = mix(deepWater, midWater, smoothstep(0.08, 0.92, skyLight));
    waterBody = mix(waterBody, sunlitWater, smoothstep(0.58, 0.96, pattern) * 0.34);
    waterBody *= mix(0.82, 1.12, pattern);

    // Preserve a little of the biome tint, but do not let Minecraft's flat
    // colour wash the whole ocean into a single saturated blue.
    vec3 biomeTint = clamp(albedo, vec3(0.0), vec3(1.0));
    waterBody *= mix(vec3(1.0), mix(vec3(0.90, 0.98, 0.97), biomeTint, 0.35), 0.16);

    vec3 reflectionTint = mix(
        vec3(0.035, 0.060, 0.078),
        vec3(0.115, 0.155, 0.175),
        skyLight
    );
    vec3 surfaceColor = mix(waterBody, reflectionTint, clamp(fresnel, 0.0, 0.78));

    // Crossed moving wavelets create visible surface texture even on Vitrail
    // configurations that do not expose additional colour attachments.
    float crest = smoothstep(0.76, 0.94, pattern);
    float ripple = 0.5 + 0.5 * sin(
        dot(worldPosition.xz, vec2(0.72, 0.41)) * 2.25
        + frameTimeCounter * 1.15
    ) * sin(
        dot(worldPosition.xz, vec2(-0.36, 0.93)) * 1.72
        - frameTimeCounter * 0.82
    );
    float rippleSheen = smoothstep(0.56, 0.90, ripple) * (0.035 + crest * 0.055);
    surfaceColor += vec3(0.20, 0.24, 0.23) * rippleSheen;

    vec3 lightDirection = normalize(shadowLightPosition);
    float reflectedSun = max(dot(reflect(-lightDirection, viewNormal), viewDirection), 0.0);
    float sharpGlint = pow(reflectedSun, 92.0);
    float broadGlint = pow(reflectedSun, 27.0);
    float glint = (sharpGlint * 0.62 + broadGlint * 0.045)
                * mix(0.42, 1.0, pattern);
    surfaceColor += vec3(0.82, 0.84, 0.80) * glint;

    // Fine foam-like streaks are sparse and subtle, not a blanket cyan noise.
    float foam = smoothstep(0.91, 0.985, pattern) * 0.10;
    surfaceColor = mix(surfaceColor, vec3(0.36, 0.40, 0.38), foam);

    float distanceToCamera = length(vViewPos);
    float haze = clamp(1.0 - exp(-distanceToCamera * 0.00055), 0.0, 0.42);
    vec3 hazeColor = aetherSRGBToLinear(clamp(fogColor, vec3(0.0), vec3(1.0)));
    surfaceColor = mix(surfaceColor, hazeColor, haze);

    // Crucial fallback: water is blended into the main scene right here.
    // It no longer becomes invisible when a secondary MRT/composite path is
    // unavailable or behaves differently on a Vulkan driver.
    float waterAlpha = mix(0.80, 0.94, clamp(fresnel, 0.0, 1.0));
    gl_FragData[0] = vec4(max(surfaceColor, vec3(0.0)), waterAlpha);
}
