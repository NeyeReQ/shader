// LabPBR 1.3 material decoding and Cook-Torrance / GGX BRDF.
uniform sampler2D lightmap;
#ifdef MC_TEXTURE_FORMAT_LAB_PBR
uniform sampler2D normals;
uniform sampler2D specular;
#endif

const float AETHER_PI = 3.14159265359;

struct AetherMaterial {
    vec3 normal;
    vec3 f0;
    float roughness;
    float metallic;
    float ao;
    float emission;
};

vec3 aetherSRGBToLinear(vec3 color) {
    color = max(color, vec3(0.0));
    vec3 low = color / 12.92;
    vec3 high = pow((color + 0.055) / 1.055, vec3(2.4));
    return mix(high, low, lessThanEqual(color, vec3(0.04045)));
}

vec3 aetherLinearToSRGB(vec3 color) {
    color = max(color, vec3(0.0));
    vec3 low = color * 12.92;
    vec3 high = 1.055 * pow(color, vec3(1.0 / 2.4)) - 0.055;
    return mix(high, low, lessThanEqual(color, vec3(0.0031308)));
}

AetherMaterial aetherBuildMaterial(
    vec2 uv, vec3 albedo, vec3 geometricNormal, vec3 tangent,
    float handedness, float wetnessValue
) {
    AetherMaterial material;
    vec3 N = normalize(geometricNormal);
    vec3 T = normalize(tangent - N * dot(N, tangent));
    vec3 B = normalize(cross(T, N)) * (handedness < 0.0 ? -1.0 : 1.0);

    material.normal = N;
    material.f0 = vec3(0.04);
    material.roughness = 0.84;
    material.metallic = 0.0;
    material.ao = 1.0;
    material.emission = 0.0;

#ifdef MC_TEXTURE_FORMAT_LAB_PBR
    vec4 normalData = texture2D(normals, uv);
    vec4 specData = texture2D(specular, uv);

    vec2 normalXY = normalData.rg * 2.0 - 1.0;
    normalXY.y = -normalXY.y;
    float normalZ = sqrt(max(1.0 - dot(normalXY, normalXY), 0.0));
    material.normal = normalize(mat3(T, B, N) * normalize(vec3(normalXY, normalZ)));

    float smoothness = clamp(specData.r, 0.0, 1.0);
    material.roughness = clamp(pow(1.0 - smoothness, 2.0), 0.045, 1.0);

    float f0Value = clamp(specData.g, 0.0, 0.90);
    material.metallic = smoothstep(0.898, 0.902, specData.g);
    material.f0 = mix(vec3(max(f0Value, 0.02)), albedo, material.metallic);
    material.ao = clamp(normalData.b, 0.0, 1.0);

    float porosity = clamp(specData.b * (255.0 / 64.0), 0.0, 1.0);
    float wetResponse = porosity * clamp(wetnessValue, 0.0, 1.0);
    material.roughness = mix(material.roughness, max(0.075, material.roughness * 0.58), wetResponse);
    material.emission = (specData.a >= 0.999) ? 0.0 : specData.a * 3.0;
#endif
    return material;
}

float aetherDistributionGGX(vec3 N, vec3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float d = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / max(AETHER_PI * d * d, 0.0001);
}

float aetherGeometrySchlickGGX(float NdotV, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / max(NdotV * (1.0 - k) + k, 0.0001);
}

vec3 aetherFresnelSchlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

vec3 aetherEvaluateBRDF(vec3 albedo, vec3 N, vec3 V, vec3 L, float roughness, float metallic, vec3 F0) {
    vec3 H = normalize(V + L);
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.001);
    float D = aetherDistributionGGX(N, H, roughness);
    float G = aetherGeometrySchlickGGX(NdotV, roughness) * aetherGeometrySchlickGGX(NdotL, roughness);
    vec3 F = aetherFresnelSchlick(max(dot(H, V), 0.0), F0);
    vec3 specularBRDF = (D * G * F) / max(4.0 * NdotV * max(NdotL, 0.001), 0.001);
    vec3 diffuseWeight = (vec3(1.0) - F) * (1.0 - metallic);
    return diffuseWeight * albedo / AETHER_PI + specularBRDF;
}
