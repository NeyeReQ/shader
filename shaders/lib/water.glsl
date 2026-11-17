// AETHERIS ULTRA — animated multi-scale Gerstner waves and procedural water detail.
// Low-amplitude vertex displacement gives the surface real motion; matching normal
// perturbation, reflection and refraction add the fine-scale detail.
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

float aetherGerstnerPhase(
    vec2 position,
    float time,
    vec2 direction,
    float wavelength
) {
    direction = normalize(direction);
    float waveNumber = AETHER_WATER_TAU / max(wavelength, 0.25);
    float angularFrequency = sqrt(AETHER_WATER_G * waveNumber);
    return angularFrequency * time - waveNumber * dot(direction, position);
}

float aetherGerstnerHeight(
    vec2 position,
    float time,
    vec2 direction,
    float wavelength,
    float amplitude
) {
    return amplitude * sin(aetherGerstnerPhase(
        position, time, direction, wavelength
    ));
}

vec2 aetherGerstnerSlope(
    vec2 position,
    float time,
    vec2 direction,
    float wavelength,
    float amplitude
) {
    direction = normalize(direction);
    float waveNumber = AETHER_WATER_TAU / max(wavelength, 0.25);
    float phase = aetherGerstnerPhase(position, time, direction, wavelength);
    return -direction * amplitude * waveNumber * cos(phase);
}

float aetherWaterHeight(vec2 worldXZ, float time) {
    float height = 0.0;
    height += aetherGerstnerHeight(worldXZ, time * 0.82,
        vec2(0.91, 0.41), 24.0, 0.14);
    height += aetherGerstnerHeight(worldXZ, time * 1.03,
        vec2(-0.36, 0.93), 13.0, 0.075);
    height += aetherGerstnerHeight(worldXZ, time * 1.31,
        vec2(0.58, -0.81), 6.0, 0.030);
    height += aetherGerstnerHeight(worldXZ, time * 1.57,
        vec2(0.98, 0.18), 3.0, 0.009);
    return height;
}

vec2 aetherWaterMicroSlope(vec2 position, float time) {
    vec2 d1 = normalize(vec2(0.91, 0.41));
    vec2 d2 = normalize(vec2(-0.38, 0.92));
    vec2 d3 = normalize(vec2(0.62, -0.78));
    float p1 = dot(position, d1) * 2.35 + time * 1.15;
    float p2 = dot(position, d2) * 4.70 - time * 1.72;
    float p3 = dot(position, d3) * 8.90 + time * 2.25;
    return d1 * (cos(p1) * 0.075)
         + d2 * (cos(p2) * 0.032)
         + d3 * (cos(p3) * 0.012);
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
        vec2(0.91, 0.41), 24.0, 0.14);
    slope += aetherGerstnerSlope(worldXZ, time * 1.03,
        vec2(-0.36, 0.93), 13.0, 0.075);
    slope += aetherGerstnerSlope(worldXZ, time * 1.31,
        vec2(0.58, -0.81), 6.0, 0.030);
    slope += aetherGerstnerSlope(worldXZ, time * 1.57,
        vec2(0.98, 0.18), 3.0, 0.009);
    slope += aetherWaterMicroSlope(worldXZ, time);
    slope *= 1.30;

    vec3 waveNormal = normalize(vec3(-slope.x, 1.0, -slope.y));
    float facing = abs(dot(upNormal, normalize(directionToCamera)));
    float normalInfluence = smoothstep(0.025, 0.22, facing);
    return normalize(mix(upNormal, waveNormal, normalInfluence));
}
