// AETHERIS ULTRA — original multi-scale Gerstner water normals.
// Inspired by established real-time water shading methods; no source code copied.
const float AETHER_WATER_G = 9.81;
const float AETHER_WATER_TAU = 6.28318530718;

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

vec3 aetherWaterNormal(
    vec2 worldXZ,
    float time,
    vec3 geometricNormal,
    vec3 directionToCamera
) {
    vec3 upNormal = normalize(geometricNormal);
    vec2 slope = vec2(0.0);

    // Long swells define the broad surface; shorter components add fine ripples.
    slope += aetherGerstnerSlope(worldXZ, time * 0.82,
        vec2(0.91, 0.41), 19.0, 0.20, 1.18);
    slope += aetherGerstnerSlope(worldXZ, time * 1.03,
        vec2(-0.36, 0.93), 10.5, 0.105, 1.25);
    slope += aetherGerstnerSlope(worldXZ, time * 1.31,
        vec2(0.58, -0.81), 4.6, 0.034, 1.05);
    slope += aetherGerstnerSlope(worldXZ, time * 1.57,
        vec2(0.98, 0.18), 2.15, 0.012, 1.0);
    slope += aetherGerstnerSlope(worldXZ, time * 1.91,
        vec2(-0.72, -0.69), 1.08, 0.0045, 1.0);

    vec3 waveNormal = normalize(vec3(-slope.x, 1.0, -slope.y));
    // Keep vertical water faces and grazing-angle silhouettes stable.
    float facing = abs(dot(upNormal, normalize(directionToCamera)));
    float normalInfluence = smoothstep(0.025, 0.22, facing);
    return normalize(mix(upNormal, waveNormal, normalInfluence));
}
