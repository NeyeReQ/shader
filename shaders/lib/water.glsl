// AETHERIS ULTRA — animated multi-scale Gerstner waves and procedural water detail.
// The fluid mesh stays native; all motion is expressed through stable surface normals.
const float AETHER_WATER_G = 9.81;
const float AETHER_WATER_TAU = 6.28318530718;

float aetherWaterHash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float aetherWaterNoise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = aetherWaterHash(cell);
    float b = aetherWaterHash(cell + vec2(1.0, 0.0));
    float c = aetherWaterHash(cell + vec2(0.0, 1.0));
    float d = aetherWaterHash(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float aetherWaterFbm(vec2 p) {
    float sum = 0.0;
    float amplitude = 0.56;
    for (int octave = 0; octave < 4; ++octave) {
        sum += aetherWaterNoise(p) * amplitude;
        p = p * 2.07 + vec2(13.7, -8.3);
        amplitude *= 0.48;
    }
    return sum;
}

vec2 aetherGerstnerSlope(
    vec2 position,
    float time,
    vec2 direction,
    float wavelength,
    float amplitude,
    float sharpness
) {
    direction = normalize(direction);
    float waveNumber = AETHER_WATER_TAU / max(wavelength, 0.25);
    float angularFrequency = sqrt(AETHER_WATER_G * waveNumber);
    float phase = angularFrequency * time - waveNumber * dot(direction, position);
    float crest = max(0.5 + 0.5 * sin(phase), 0.0001);
    float derivative = -0.5 * amplitude * sharpness
                     * pow(crest, sharpness - 1.0)
                     * waveNumber * cos(phase);
    return direction * derivative;
}

vec2 aetherWaterMicroSlope(vec2 position, float time) {
    vec2 d1 = normalize(vec2(0.91, 0.41));
    vec2 d2 = normalize(vec2(-0.38, 0.92));
    vec2 d3 = normalize(vec2(0.62, -0.78));
    float p1 = dot(position, d1) * 2.35 + time * 1.15;
    float p2 = dot(position, d2) * 4.70 - time * 1.72;
    float p3 = dot(position, d3) * 8.90 + time * 2.25;
    return d1 * (cos(p1) * 0.050)
         + d2 * (cos(p2) * 0.020)
         + d3 * (cos(p3) * 0.008);
}

float aetherWaterPattern(vec2 position, float time) {
    vec2 drift = vec2(time * 0.018, -time * 0.012);
    float broad = aetherWaterFbm(position * 0.105 + drift);
    float fine = aetherWaterNoise(position * 0.39 - drift * 2.1);
    float ribbons = 0.5 + 0.25 * sin(dot(position, vec2(0.21, 0.11)) + time * 0.28)
                        + 0.25 * sin(dot(position, vec2(-0.13, 0.24)) - time * 0.23);
    return clamp(broad * 0.52 + fine * 0.28 + ribbons * 0.20, 0.0, 1.0);
}

vec3 aetherWaterNormal(
    vec2 worldXZ,
    float time,
    vec3 geometricNormal,
    vec3 directionToCamera
) {
    vec3 upNormal = normalize(geometricNormal);
    if (abs(upNormal.y) < 0.45) return upNormal;

    vec2 slope = vec2(0.0);
    slope += aetherGerstnerSlope(worldXZ, time * 0.82,
        vec2(0.91, 0.41), 19.0, 0.43, 1.18);
    slope += aetherGerstnerSlope(worldXZ, time * 1.03,
        vec2(-0.36, 0.93), 10.5, 0.24, 1.25);
    slope += aetherGerstnerSlope(worldXZ, time * 1.31,
        vec2(0.58, -0.81), 4.6, 0.095, 1.05);
    slope += aetherGerstnerSlope(worldXZ, time * 1.57,
        vec2(0.98, 0.18), 2.15, 0.033, 1.0);
    slope += aetherGerstnerSlope(worldXZ, time * 1.91,
        vec2(-0.72, -0.69), 1.08, 0.012, 1.0);
    slope += aetherWaterMicroSlope(worldXZ, time);

    vec3 waveNormal = normalize(vec3(-slope.x, 1.0, -slope.y));
    float facing = abs(dot(upNormal, normalize(directionToCamera)));
    float normalInfluence = smoothstep(0.025, 0.22, facing);
    return normalize(mix(upNormal, waveNormal, normalInfluence));
}
