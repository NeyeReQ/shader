// AETHERIS ULTRA render targets and PCF shadows.
/*
const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16F;
*/
const int shadowMapResolution = 4096; // [1024 2048 3072 4096]
const float shadowDistance = 192.0; // [96.0 128.0 160.0 192.0]
const bool shadowHardwareFiltering = false;

uniform sampler2D shadowtex0;

float aetherShadowPCF(vec4 shadowCoord, vec3 normal, vec3 lightDirection) {
    if (shadowCoord.w <= 0.0) return 1.0;
    vec3 projected = shadowCoord.xyz / shadowCoord.w;
    projected = projected * 0.5 + 0.5;
    if (projected.x <= 0.001 || projected.x >= 0.999 ||
        projected.y <= 0.001 || projected.y >= 0.999 ||
        projected.z <= 0.0 || projected.z >= 1.0) return 1.0;

    float NdotL = max(dot(normalize(normal), normalize(lightDirection)), 0.0);
    float bias = max(0.00012, 0.00065 * (1.0 - NdotL));
    vec2 texel = vec2(1.0 / float(shadowMapResolution));
    float visibility = 0.0;

    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            vec2 offset = vec2(float(x), float(y)) * texel;
            float storedDepth = texture2D(shadowtex0, projected.xy + offset).r;
            visibility += (projected.z - bias <= storedDepth) ? 1.0 : 0.0;
        }
    }
    return mix(0.20, 1.0, visibility / 9.0);
}
