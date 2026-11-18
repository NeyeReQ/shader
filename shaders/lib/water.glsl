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

vec2 aetherGerstnerHorizontal(
    vec2 position,
    float time,
    vec2 direction,
    float wavelength,
    float amplitude,
    float steepness
) {
    direction = normalize(direction);
    float phase = aetherGerstnerPhase(position, time, direction, wavelength);
    return direction * (amplitude * steepness * cos(phase));
}

vec2 aetherWaterDisplacementXZ(vec2 worldXZ, float time) {
    vec2 displacement = vec2(0.0);
    displacement += aetherGerstnerHorizontal(worldXZ, time * 0.62,
        vec2(0.87, 0.49), 38.0, 0.42, 0.30);
    displacement += aetherGerstnerHorizontal(worldXZ, time * 0.78,
        vec2(-0.31, 0.95), 21.0, 0.23, 0.28);
    displacement += aetherGerstnerHorizontal(worldXZ, time * 0.96,
        vec2(0.55, -0.83), 10.5, 0.105, 0.20);
    return displacement;
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
    // Crossed capillary waves break up broad reflections into small moving
    // highlights. Their wavelengths are expressed in world blocks.
    vec2 d1 = normalize(vec2(0.91, 0.41));
    vec2 d2 = normalize(vec2(-0.38, 0.92));
    vec2 d3 = normalize(vec2(0.62, -0.78));
    vec2 d4 = normalize(vec2(-0.82, -0.57));
    vec2 d5 = normalize(vec2(0.18, 0.98));
    float p1 = dot(position, d1) * 1.75 + time * 0.95;
    float p2 = dot(position, d2) * 3.65 - time * 1.32;
    float p3 = dot(position, d3) * 7.20 + time * 1.85;
    float p4 = dot(position, d4) * 12.8 - time * 2.60;
    float p5 = dot(position, d5) * 19.5 + time * 3.25;
    return d1 * (cos(p1) * 0.062)
         + d2 * (cos(p2) * 0.038)
         + d3 * (cos(p3) * 0.018)
         + d4 * (cos(p4) * 0.0065)
         + d5 * (cos(p5) * 0.0028);
}

float aetherWaterPattern(vec2 position, float time) {
    vec2 drift = vec2(time * 0.010, -time * 0.007);
    float broad = aetherWaterFbm(position * 0.043 + drift);
    float middle = aetherWaterFbm(position * 0.145 - drift * 2.2);
    float fine = aetherWaterNoise(position * 0.58 + drift * 3.1);
    float ribbons = 0.5
        + 0.25 * sin(dot(position, vec2(0.105, 0.061)) + time * 0.20)
        + 0.25 * sin(dot(position, vec2(-0.071, 0.131)) - time * 0.17);
    return clamp(broad * 0.30 + middle * 0.30 + fine * 0.18 + ribbons * 0.22,
                 0.0, 1.0);
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


// Analytic environment reflection avoids reading the colour attachment that
// this pass is currently writing to (a framebuffer feedback loop on Vulkan).
vec3 aetherWaterSkyReflection(
    vec3 rayDirection, vec3 sunDirection, float daylight,
    float goldenHour, float rain, vec3 worldPosition, float time
) {
    vec3 ray = normalize(rayDirection);
    vec3 sunDir = normalize(sunDirection);
    vec3 nightZenith = vec3(0.003, 0.006, 0.018);
    vec3 dayZenith = vec3(0.055, 0.125, 0.235);
    vec3 nightHorizon = vec3(0.014, 0.021, 0.043);
    vec3 dayHorizon = vec3(0.34, 0.43, 0.49);
    vec3 sunsetHorizon = vec3(0.55, 0.30, 0.22);
    vec3 zenith = mix(nightZenith, dayZenith, daylight);
    vec3 horizon = mix(nightHorizon, dayHorizon, daylight);
    horizon = mix(horizon, sunsetHorizon, goldenHour * 0.82);
    float horizonBlend = smoothstep(-0.26, 0.38, ray.y);
    float zenithBlend = pow(clamp((ray.y + 0.08) / 1.08, 0.0, 1.0), 0.72);
    vec3 reflection = mix(vec3(0.018, 0.026, 0.034), horizon, horizonBlend);
    reflection = mix(reflection, zenith, zenithBlend);

    if (ray.y > 0.035) {
        float cloudDistance = 205.0 / max(ray.y, 0.12);
        vec2 cloudWorld = worldPosition.xz + ray.xz * cloudDistance;
        vec2 cloudUV = cloudWorld * 0.00165
                     + vec2(time * 0.00031, -time * 0.00019);
        float cloudBody = aetherWaterFbm(cloudUV);
        float cloudDetail = aetherWaterNoise(cloudUV * 5.7 + vec2(8.1, -4.7));
        float cloudSignal = cloudBody - (cloudDetail - 0.5) * 0.21;
        float cloudMask = smoothstep(0.49, 0.68, cloudSignal);
        float cloudHorizonFade = smoothstep(0.035, 0.18, ray.y)
                               * (1.0 - smoothstep(0.72, 0.94, ray.y));
        vec3 cloudShade = mix(vec3(0.055, 0.068, 0.085),
                              vec3(0.23, 0.27, 0.31), daylight);
        vec3 cloudLit = mix(vec3(0.24, 0.27, 0.34),
                            vec3(0.82, 0.87, 0.91), daylight);
        cloudLit = mix(cloudLit, vec3(0.91, 0.49, 0.32), goldenHour * 0.68);
        float cloudLight = clamp(0.28 + 0.54 * daylight
                               + 0.18 * max(dot(ray, sunDir), 0.0), 0.0, 1.0);
        vec3 cloudColor = mix(cloudShade, cloudLit, cloudLight);
        reflection = mix(reflection, cloudColor, cloudMask * cloudHorizonFade * 0.62);
    }

    float sunAlignment = max(dot(ray, sunDir), 0.0) * step(-0.035, sunDir.y);
    float sunHalo = pow(sunAlignment, 52.0);
    float sunDisc = smoothstep(0.99994, 0.999985, sunAlignment);
    vec3 sunGlow = mix(vec3(1.0, 0.69, 0.43), vec3(1.0, 0.91, 0.76), daylight);
    reflection += sunGlow * sunHalo * (0.075 + goldenHour * 0.10);
    reflection = mix(reflection, vec3(5.2, 3.8, 2.35), sunDisc);

    float haze = (1.0 - smoothstep(-0.08, 0.32, ray.y)) * 0.16;
    reflection = mix(reflection, mix(vec3(0.055, 0.066, 0.078),
                                    vec3(0.37, 0.42, 0.46), daylight), haze);
    reflection = mix(reflection, vec3(0.115, 0.135, 0.155), rain * 0.34);
    return max(reflection, vec3(0.0));
}
