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
    // Long ocean swells carry the silhouette; shorter crossed waves break up
    // the reflection. All waves use absolute world coordinates so chunk edges
    // remain continuous while the camera moves.
    float height = 0.0;
    height += aetherGerstnerHeight(worldXZ, time * 0.62,
        vec2(0.87, 0.49), 38.0, 0.42);
    height += aetherGerstnerHeight(worldXZ, time * 0.78,
        vec2(-0.31, 0.95), 21.0, 0.23);
    height += aetherGerstnerHeight(worldXZ, time * 0.96,
        vec2(0.55, -0.83), 10.5, 0.105);
    height += aetherGerstnerHeight(worldXZ, time * 1.22,
        vec2(0.98, 0.18), 5.1, 0.034);
    height += aetherGerstnerHeight(worldXZ, time * 1.52,
        vec2(-0.72, -0.69), 2.6, 0.012);
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
    vec2 drift = vec2(time * 0.012, -time * 0.009);
    float broad = aetherWaterFbm(position * 0.052 + drift);
    float fine = aetherWaterNoise(position * 0.21 - drift * 2.4);
    float ribbons = 0.5
        + 0.25 * sin(dot(position, vec2(0.125, 0.071)) + time * 0.22)
        + 0.25 * sin(dot(position, vec2(-0.083, 0.147)) - time * 0.18);
    return clamp(broad * 0.48 + fine * 0.27 + ribbons * 0.25, 0.0, 1.0);
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
    slope += aetherGerstnerSlope(worldXZ, time * 0.62,
        vec2(0.87, 0.49), 38.0, 0.42);
    slope += aetherGerstnerSlope(worldXZ, time * 0.78,
        vec2(-0.31, 0.95), 21.0, 0.23);
    slope += aetherGerstnerSlope(worldXZ, time * 0.96,
        vec2(0.55, -0.83), 10.5, 0.105);
    slope += aetherGerstnerSlope(worldXZ, time * 1.22,
        vec2(0.98, 0.18), 5.1, 0.034);
    slope += aetherWaterMicroSlope(worldXZ, time);
    slope *= 1.12;

    vec3 waveNormal = normalize(vec3(-slope.x, 1.0, -slope.y));
    // Do not fade wave normals out at grazing angles: that is where the
    // ocean needs them most to distort reflections into long moving streaks.
    float facing = abs(dot(upNormal, normalize(directionToCamera)));
    float normalInfluence = mix(0.88, 1.0, smoothstep(0.01, 0.18, facing));
    return normalize(mix(upNormal, waveNormal, normalInfluence));
}
