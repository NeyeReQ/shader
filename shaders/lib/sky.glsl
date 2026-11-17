// AETHERIS ULTRA — procedural Overworld atmosphere, sun, moon and cloud layer.
// All colors are in linear light; final.fsh applies the display transform.
uniform vec3 moonPosition;
uniform int moonPhase;
uniform float cloudHeight;

float aetherSkyHash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float aetherSkyNoise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = aetherSkyHash(cell);
    float b = aetherSkyHash(cell + vec2(1.0, 0.0));
    float c = aetherSkyHash(cell + vec2(0.0, 1.0));
    float d = aetherSkyHash(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float aetherSkyFbm(vec2 p) {
    float sum = 0.0;
    float amplitude = 0.5;
    for (int octave = 0; octave < 4; ++octave) {
        sum += aetherSkyNoise(p) * amplitude;
        p = p * 2.03 + vec2(17.1, 9.2);
        amplitude *= 0.5;
    }
    return sum * 1.0666667;
}

// Vulkan can expose an unset optional direction as a zero vector. Normalizing
// that vector is undefined and can poison the entire sky/reflection with NaNs.
vec3 aetherSafeNormalize(vec3 value, vec3 fallbackValue) {
    float magnitudeSquared = dot(value, value);
    if (!(magnitudeSquared > 1e-8) || !(magnitudeSquared < 1e20)) {
        return fallbackValue;
    }
    return value * inversesqrt(magnitudeSquared);
}

float aetherDirectionAvailable(vec3 value) {
    float magnitudeSquared = dot(value, value);
    return (magnitudeSquared > 1e-8 && magnitudeSquared < 1e20) ? 1.0 : 0.0;
}

vec3 aetherRenderSky(vec3 rayDirection, vec3 worldOrigin) {
    vec3 ray = aetherSafeNormalize(rayDirection, vec3(0.0, 1.0, 0.0));
    vec3 sunVector = mat3(gbufferModelViewInverse) * sunPosition;
    vec3 moonVector = mat3(gbufferModelViewInverse) * moonPosition;
    float sunAvailable = aetherDirectionAvailable(sunVector);
    float moonAvailable = aetherDirectionAvailable(moonVector);
    vec3 sunDir = aetherSafeNormalize(sunVector, vec3(0.0, 1.0, 0.0));
    vec3 moonDir = aetherSafeNormalize(moonVector, vec3(0.0, -1.0, 0.0));

    float sunElevation = sunDir.y;
    float daylight = smoothstep(-0.16, 0.20, sunElevation);
    float goldenHour = 1.0 - smoothstep(0.035, 0.36, abs(sunElevation));
    float horizon = smoothstep(-0.16, 0.28, ray.y);

    vec3 nightZenith = vec3(0.0025, 0.0045, 0.014);
    vec3 dayZenith = vec3(0.105, 0.265, 0.56);
    vec3 nightHorizon = vec3(0.012, 0.019, 0.048);
    vec3 dayHorizon = vec3(0.47, 0.64, 0.82);
    vec3 warmHorizon = vec3(0.82, 0.28, 0.105);

    vec3 zenithColor = mix(nightZenith, dayZenith, daylight);
    vec3 horizonColor = mix(nightHorizon, dayHorizon, daylight);
    horizonColor = mix(horizonColor, warmHorizon, goldenHour * 0.88);
    vec3 sky = mix(horizonColor, zenithColor, pow(clamp(horizon, 0.0, 1.0), 0.62));

    // Atmospheric haze grows toward the horizon and toward the sun.
    float sunAlignment = max(dot(ray, sunDir), 0.0) * sunAvailable;
    float mieGlow = pow(sunAlignment, 10.0);
    float sunAura = pow(sunAlignment, 34.0);
    sky += vec3(1.0, 0.46, 0.22) * mieGlow * (0.018 + goldenHour * 0.075);
    sky += vec3(1.0, 0.70, 0.40) * sunAura * (0.08 + goldenHour * 0.20);

    // Compact Rayleigh + Mie scattering approximation, kept analytic for Vulkan portability.
    float airMass = 1.0 / max(ray.y + 0.16, 0.12);
    float rayleighPhase = 0.0596831 * (1.0 + sunAlignment * sunAlignment);
    float mieG = 0.76;
    float miePhase = (1.0 - mieG * mieG) /
        (12.5663706 * pow(max(1.0 + mieG * mieG - 2.0 * mieG * sunAlignment, 0.06), 1.5));
    float atmosphericAttenuation = exp(-min(airMass, 7.0) * 0.075);
    vec3 rayleighTint = vec3(0.18, 0.42, 1.0);
    vec3 mieTint = mix(vec3(1.0, 0.62, 0.35), vec3(1.0, 0.82, 0.64), daylight);
    vec3 atmosphericInscatter = (rayleighTint * rayleighPhase * 0.26
                               + mieTint * miePhase * 0.10)
                               * (0.25 + 0.75 * daylight)
                               * atmosphericAttenuation;
    sky += atmosphericInscatter;

    // A custom solar disc with a warm atmospheric edge.
    float sunDisc = (1.0 - smoothstep(0.999985, 0.999994, sunAlignment)) * sunAvailable;
    vec3 sunColor = mix(vec3(1.0, 0.91, 0.72), vec3(1.0, 0.53, 0.27), goldenHour);
    sky = mix(sky, sunColor * 18.0, sunDisc);

    // Sparse, softly twinkling stars on the night side of the sky.
    if (daylight < 0.98 && ray.y > 0.0) {
        vec2 starProjection = ray.xz / max(ray.y, 0.055) * 235.0;
        vec2 starCell = floor(starProjection);
        vec2 starLocal = fract(starProjection);
        float starSeed = aetherSkyHash(starCell);
        vec2 starOffset = vec2(
            aetherSkyHash(starCell + vec2(7.0, 19.0)),
            aetherSkyHash(starCell + vec2(31.0, 11.0))
        );
        float starShape = 1.0 - smoothstep(0.012, 0.040, length(starLocal - starOffset));
        float stars = step(0.9972, starSeed) * starShape;
        float twinkle = 0.76 + 0.24 * sin(frameTimeCounter * 1.65 + starSeed * 31.0);
        sky += vec3(0.56, 0.68, 1.0) * stars * twinkle * (1.0 - daylight);
    }

    // Procedural moon disc with a phase-aware illuminated hemisphere.
    vec3 moonAxis = abs(moonDir.y) < 0.96 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 moonRight = aetherSafeNormalize(cross(moonAxis, moonDir), vec3(1.0, 0.0, 0.0));
    vec3 moonUp = aetherSafeNormalize(cross(moonDir, moonRight), vec3(0.0, 0.0, 1.0));
    vec2 moonPlane = vec2(dot(ray, moonRight), dot(ray, moonUp)) / 0.0047;
    float moonMask = (1.0 - smoothstep(1.0, 1.04, length(moonPlane))) * step(0.0, moonDir.y);
    float moonDepth = sqrt(max(1.0 - dot(moonPlane, moonPlane), 0.0));
    vec3 moonNormal = aetherSafeNormalize(vec3(moonPlane, -moonDepth), vec3(0.0, 0.0, -1.0));
    vec3 sunInMoonSpace = aetherSafeNormalize(vec3(
        dot(sunDir, moonRight),
        dot(sunDir, moonUp),
        dot(sunDir, moonDir)
    ), vec3(0.0, 0.0, 1.0));
    float moonIllumination = max(dot(moonNormal, sunInMoonSpace), 0.0);
    float phaseFromFull = 0.5 + 0.5 * cos(float(moonPhase) * 0.78539816);
    vec3 moonColor = vec3(0.58, 0.67, 0.79) * (0.12 + 0.88 * moonIllumination);
    float moonVisibility = (1.0 - daylight) * moonMask * moonAvailable * mix(0.25, 1.0, phaseFromFull);
    sky += moonColor * moonVisibility * 1.15;

    // Multi-sample cloud slab. Density is integrated front-to-back along the sky ray.
#ifdef AETHER_CLOUDS
    if (ray.y > 0.018) {
        float cloudBase = max(cloudHeight - 22.0, 112.0);
        float cloudTop = cloudBase + 56.0;
        float enterDistance = (cloudBase - worldOrigin.y) / ray.y;
        float exitDistance = (cloudTop - worldOrigin.y) / ray.y;
        float rayStart = max(enterDistance, 0.0);
        float rayEnd = max(exitDistance, 0.0);

        if (rayEnd > rayStart && rayStart < 14000.0) {
            const int CLOUD_STEPS = 8;
            float stepLength = (rayEnd - rayStart) / float(CLOUD_STEPS);
            float cloudTransmittance = 1.0;
            vec3 cloudScattering = vec3(0.0);

            for (int i = 0; i < CLOUD_STEPS; ++i) {
                float distanceAlongRay = rayStart + (float(i) + 0.5) * stepLength;
                vec3 samplePosition = worldOrigin + ray * distanceAlongRay;
                float heightFraction = clamp((samplePosition.y - cloudBase) / (cloudTop - cloudBase), 0.0, 1.0);
                float verticalProfile = smoothstep(0.015, 0.20, heightFraction)
                                      * (1.0 - smoothstep(0.72, 1.0, heightFraction));

                vec2 cloudUV = samplePosition.xz * 0.00115
                             + vec2(frameTimeCounter * 0.00062, frameTimeCounter * 0.00037);
                float cloudBody = aetherSkyFbm(cloudUV);
                float cloudDetail = aetherSkyNoise(cloudUV * 4.0 + vec2(12.1, -7.3));
                float cloudSignal = cloudBody - (cloudDetail - 0.5) * 0.19;
                float threshold = mix(0.485, 0.395, rainStrength);
                float density = smoothstep(threshold, threshold + 0.15, cloudSignal)
                              * verticalProfile;

                float sampleAlpha = 1.0 - exp(-density * stepLength * 0.010);
                sampleAlpha = clamp(sampleAlpha, 0.0, 0.88);

                float underside = clamp(1.0 - heightFraction, 0.0, 1.0);
                float cloudLighting = clamp(
                    0.30 + 0.52 * daylight + 0.22 * max(dot(ray, sunDir), 0.0)
                    + 0.12 * underside,
                    0.0, 1.0
                );

                vec3 nightShade = vec3(0.035, 0.047, 0.078);
                vec3 dayShade = vec3(0.22, 0.26, 0.32);
                vec3 nightLight = vec3(0.14, 0.17, 0.25);
                vec3 dayLight = vec3(0.92, 0.96, 1.0);
                vec3 sunsetLight = vec3(1.15, 0.48, 0.24);
                vec3 cloudShade = mix(nightShade, dayShade, daylight);
                vec3 cloudLight = mix(nightLight, dayLight, daylight);
                cloudLight = mix(cloudLight, sunsetLight, goldenHour * 0.82);
                cloudShade = mix(cloudShade, vec3(0.13, 0.15, 0.19), rainStrength * 0.72);

                vec3 cloudColor = mix(cloudShade, cloudLight, cloudLighting);
                float silverLining = pow(max(dot(ray, sunDir), 0.0), 5.0)
                                   * (0.10 + goldenHour * 0.20);
                cloudColor += vec3(1.0, 0.72, 0.45) * silverLining;

                cloudScattering += cloudTransmittance * sampleAlpha * cloudColor;
                cloudTransmittance *= 1.0 - sampleAlpha;
            }

            sky = sky * cloudTransmittance + cloudScattering;
        }
    }
#endif

    // Rain and storms mute the blue channel and lower the overall contrast.
    vec3 overcast = vec3(0.19, 0.225, 0.275);
    sky = mix(sky, overcast, rainStrength * 0.58);
    return max(sky, vec3(0.0));
}
