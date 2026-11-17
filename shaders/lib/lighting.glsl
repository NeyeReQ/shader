// Shared AETHERIS lighting helpers.
// Iris reads these constants to configure its native shadow renderer.
const int shadowMapResolution = 4096; // [1024 2048 3072 4096] Shadow map resolution.
const float shadowDistance = 192.0; // [96.0 128.0 160.0 192.0] Shadow rendering distance.
// Manual PCF compares raw depth values, so hardware comparison sampling stays disabled.
const bool shadowHardwareFiltering = false;

uniform sampler2D shadowtex0;

float aetherShadowPCF(vec4 shadowCoord, vec3 normal, vec3 lightDirection) {
    if (shadowCoord.w <= 0.0) return 1.0;

    vec3 projected = shadowCoord.xyz / shadowCoord.w;
    projected = projected * 0.5 + 0.5;

    if (projected.x < 0.001 || projected.x > 0.999 ||
        projected.y < 0.001 || projected.y > 0.999 ||
        projected.z > 1.0) {
        return 1.0;
    }

    float ndl = max(dot(normalize(normal), normalize(lightDirection)), 0.0);
    float bias = max(0.00025, 0.00125 * (1.0 - ndl));
    vec2 texel = vec2(1.0 / float(shadowMapResolution));

    float visibility = 0.0;
    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            float storedDepth = texture2D(shadowtex0, projected.xy + vec2(float(x), float(y)) * texel).r;
            visibility += (projected.z - bias <= storedDepth) ? 1.0 : 0.0;
        }
    }

    // Keep a small ambient contribution in shadow to avoid crushed blacks.
    return mix(0.30, 1.0, visibility / 9.0);
}
