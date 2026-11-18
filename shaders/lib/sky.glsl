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

    // Leonida-inspired tropical daylight: saturated blue overhead, pale
    // humid cyan at the horizon, and a warm peach band as the sun gets low.
    vec3 nightZenith = vec3(0.0025, 0.0045, 0.014);
    vec3 dayZenith = vec3(0.105, 0.285, 0.62);
    vec3 nightHorizon = vec3(0.012, 0.019, 0.048);
    vec3 dayHorizon = vec3(0.48, 0.68, 0.80);
    vec3 warmHorizon = vec3(0.88, 0.39, 0.20);

    vec3 zenithColor = mix(nightZenith, dayZenith, daylight);
    vec3 horizonColor = mix(nightHorizon, dayHorizon, daylight);
    horizonColor = mix(horizonColor, warmHorizon, goldenHour * 0.88);
    vec3 sky = mix(horizonColor, zenithColor, pow(clamp(horizon, 0.0, 1.0), 0.62));

    // Atmospheric haze grows toward the horizon and toward the sun.
    float sunAlignment = max(dot(ray, sunDir), 0.0) * sunAvailable;
    float mieGlow = pow(sunAlignment, 8.0);
    float sunAura = pow(sunAlignment, 28.0);
    sky += vec3(1.0, 0.55, 0.32) * mieGlow * (0.026 + goldenHour * 0.095);
    sky += vec3(1.0, 0.76, 0.52) * sunAura * (0.11 + goldenHour * 0.24);

    // Compact Rayleigh + Mie scattering approximation. The stronger path
    // length near the horizon gives the sky its humid coastal haze without
    // a hard colour band.
    float airMass = 1.0 / max(ray.y + 0.14, 0.065);
    airMass = min(airMass, 12.0);
    float rayleighPhase = 0.75 * (1.0 + sunAlignment * sunAlignment);
    float mieG = 0.78;
    float miePhase = (1.0 - mieG * mieG) /
        (12.5663706 * pow(max(1.0 + mieG * mieG - 2.0 * mieG * sunAlignment, 0.055), 1.5));
    float atmosphericAttenuation = exp(-airMass * 0.052);
    vec3 rayleighTint = vec3(0.22, 0.48, 1.0);
    vec3 mieTint = mix(vec3(1.0, 0.58, 0.34), vec3(1.0, 0.84, 0.68), daylight);
    vec3 atmosphericInscatter = (rayleighTint * rayleighPhase * 0.105
                               + mieTint * miePhase * 0.075)
                               * (0.22 + 0.78 * daylight)
                               * atmosphericAttenuation;
    sky += atmosphericInscatter;

    float horizonHaze = (1.0 - smoothstep(0.02, 0.42, ray.y))
                      * (0.12 + 0.12 * daylight);
    vec3 hazeTint = mix(vec3(0.055, 0.070, 0.12),
                        vec3(0.42, 0.62, 0.72), daylight);
    sky = mix(sky, hazeTint, clamp(horizonHaze, 0.0, 0.28));

    // A custom solar disc with a warm atmospheric edge.
    // A solar disc exists only for rays aligned with the sun; the inverse
    // smoothstep paints the entire sky with the solar colour.
    float sunDisc = smoothstep(0.999982, 0.999992, sunAlignment) * sunAvailable;
    float sunCorona = pow(sunAlignment, 180.0) * sunAvailable;
    vec3 sunColor = mix(vec3(1.0, 0.96, 0.82), vec3(1.0, 0.59, 0.34), goldenHour);
    sky += mix(vec3(1.0, 0.68, 0.42), vec3(1.0, 0.88, 0.70), daylight)
         * sunCorona * (0.22 + goldenHour * 0.38);
    sky = mix(sky, sunColor * 7.5, sunDisc);

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
    if (ray.y > 0.012) {
        float cloudBase = max(cloudHeight - 26.0, 170.0);
        float cloudTop = cloudBase + 108.0;
        float enterDistance = (cloudBase - worldOrigin.y) / ray.y;
        float exitDistance = (cloudTop - worldOrigin.y) / ray.y;
        float rayStart = max(enterDistance, 0.0);
        float rayEnd = max(exitDistance, 0.0);

        if (rayEnd > rayStart && rayStart < 14000.0) {
            const int CLOUD_STEPS = 26;
            float stepLength = (rayEnd - rayStart) / float(CLOUD_STEPS);
            float cloudTransmittance = 1.0;
            vec3 cloudScattering = vec3(0.0);

            for (int i = 0; i < CLOUD_STEPS; ++i) {
                float distanceAlongRay = rayStart + (float(i) + 0.5) * stepLength;
                vec3 samplePosition = worldOrigin + ray * distanceAlongRay;
                float heightFraction = clamp((samplePosition.y - cloudBase) / (cloudTop - cloudBase), 0.0, 1.0);
                float verticalProfile = smoothstep(0.012, 0.15, heightFraction)
                                      * (1.0 - smoothstep(0.70, 0.985, heightFraction));

                // Convective cloud bodies: broad bases, swelling upper lobes,
                // wind-sheared edges and a finer erosion layer. The height warp
                // gives the volume changing cross-sections instead of extruded
                // 2-D noise, which is the source of the old sheet-like look.
                vec2 wind = vec2(frameTimeCounter * 0.00034,
                                 frameTimeCounter * 0.00021);
                float verticalBulge = sin(heightFraction * 3.14159265);
                vec2 heightWarp = vec2(
                    sin(heightFraction * 4.2 + cloudBody * 3.0),
                    cos(heightFraction * 3.4 - cloudBody * 2.2)
                ) * (0.018 + 0.026 * verticalBulge);
                vec2 cloudUV = samplePosition.xz * 0.00185 + wind + heightWarp;
                float cloudBody = aetherSkyFbm(cloudUV);
                float cloudDetail = aetherSkyNoise(
                    cloudUV * 6.4 + vec2(12.1, -7.3) + wind * 1.7
                );
                float cloudSignal = cloudBody - (cloudDetail - 0.5) * 0.29;
                float baseThreshold = mix(0.515, 0.585, heightFraction);
                float threshold = mix(baseThreshold, baseThreshold - 0.045, rainStrength);
                float density = smoothstep(threshold, threshold + 0.155, cloudSignal)
                              * verticalProfile;

                float sampleAlpha = 1.0 - exp(-density * stepLength * 0.0050);
                sampleAlpha = clamp(sampleAlpha, 0.0, 0.86);

                float underside = clamp(1.0 - heightFraction, 0.0, 1.0);
                float sunFacing = max(dot(ray, sunDir), 0.0);
                float cloudLighting = clamp(
                    0.16 + 0.60 * daylight + 0.34 * sunFacing
                    + 0.10 * verticalBulge,
                    0.0, 1.0
                );

                vec3 nightShade = vec3(0.026, 0.037, 0.065);
                vec3 dayShade = vec3(0.16, 0.205, 0.28);
                vec3 nightLight = vec3(0.16, 0.20, 0.30);
                vec3 dayLight = vec3(0.82, 0.88, 0.96);
                vec3 sunsetLight = vec3(0.96, 0.52, 0.32);
                vec3 cloudShade = mix(nightShade, dayShade, daylight);
                vec3 cloudLight = mix(nightLight, dayLight, daylight);
                cloudLight = mix(cloudLight, sunsetLight, goldenHour * 0.86);
                cloudShade = mix(cloudShade, vec3(0.12, 0.15, 0.20), rainStrength * 0.72);

                vec3 cloudColor = mix(cloudShade, cloudLight, cloudLighting);
                cloudColor *= 1.0 - underside * (0.16 + 0.16 * (1.0 - daylight));
                float cloudRim = smoothstep(0.43, 0.62, cloudSignal)
                               * (1.0 - smoothstep(0.72, 0.90, cloudSignal));
                float silverLining = (pow(sunFacing, 3.5) * 0.16
                                    + cloudRim * 0.11)
                                   * (0.16 + goldenHour * 0.34);
                cloudColor += vec3(1.0, 0.82, 0.65) * silverLining;

                cloudScattering += cloudTransmittance * sampleAlpha * cloudColor;
                cloudTransmittance *= 1.0 - sampleAlpha;
            }

            sky = sky * cloudTransmittance + cloudScattering;
        }
    }

            // High thin cirrus streaks sit above the cumulus deck. They are
            // kept translucent and sparse so the blue atmosphere remains visible.
            if (ray.y > 0.022 && rainStrength < 0.88) {
                float cirrusAltitude = max(cloudHeight + 245.0, 430.0);
                float cirrusDistance = (cirrusAltitude - worldOrigin.y) / ray.y;
                if (cirrusDistance > 0.0 && cirrusDistance < 48000.0) {
                    vec3 cirrusPosition = worldOrigin + ray * cirrusDistance;
                    vec2 cirrusUV = cirrusPosition.xz * 0.00072
                                  + vec2(frameTimeCounter * 0.00008,
                                         -frameTimeCounter * 0.000045);
                    float broadWisps = aetherSkyFbm(cirrusUV * 1.35);
                    float filament = 0.5 + 0.5 * sin(
                        cirrusUV.x * 8.0 + cirrusUV.y * 2.6 + broadWisps * 5.0
                    );
                    float streakMask = 1.0 - smoothstep(0.18, 0.72, filament);
                    float cirrusDensity = smoothstep(0.43, 0.72, broadWisps)
                                        * streakMask;
                    float cirrusOpacity = cirrusDensity * (1.0 - rainStrength)
                                        * (0.10 + 0.08 * daylight);
                    vec3 cirrusTint = mix(vec3(0.34, 0.40, 0.54),
                                          vec3(0.82, 0.88, 0.96), daylight);
                    cirrusTint = mix(cirrusTint, vec3(1.0, 0.66, 0.49),
                                     goldenHour * 0.72);
                    sky = mix(sky, cirrusTint, clamp(cirrusOpacity, 0.0, 0.17));
                }
            }
#endif

    // Rain and storms mute the blue channel and lower the overall contrast.
    vec3 overcast = vec3(0.095, 0.125, 0.17);
    sky = mix(sky, overcast, rainStrength * 0.58);
    return max(sky, vec3(0.0));
}
