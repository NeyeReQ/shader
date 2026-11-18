#version 330 compatibility

#include "/lib/water.glsl"

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;

in vec2 mc_Entity;

out vec2 vTexCoord;
out vec2 vLightCoord;
out vec4 vColor;
out vec3 vViewPos;
out vec3 vPlayerPos;
out vec3 vPlayerNormal;
out vec4 vShadowCoord;
out float vBlockId;
out float vIsFluid;

vec3 aetherWaterVertexSafeNormalize(vec3 value, vec3 fallbackValue) {
    float magnitudeSquared = dot(value, value);
    return (magnitudeSquared > 1e-8 && magnitudeSquared < 1e20)
        ? value * inversesqrt(magnitudeSquared)
        : fallbackValue;
}

void main() {
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLightCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor = gl_Color;

    vBlockId = mc_Entity.x;
    vIsFluid = mc_Entity.y;

    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    vec4 playerPosition = gbufferModelViewInverse * viewPosition;

    // Vitrail gives fluid quads a dedicated low bit. Keep the block id as a
    // second route so mapped water remains identifiable if that bit is absent.
    bool isLava = abs(vBlockId - 200.0) < 0.25
               || abs(vBlockId - 199.0) < 0.25;
    bool isWater = !isLava
                && (vIsFluid > 0.5 || abs(vBlockId - 120.0) < 0.25);

    vec3 sourceNormal = gl_NormalMatrix * gl_Normal;
    float normalLength = dot(sourceNormal, sourceNormal);
    if (!(normalLength > 1e-8) || !(normalLength < 1e20)) {
        sourceNormal = vec3(0.0, 1.0, 0.0);
    }

    // Convert the real fluid face normal to world space before deciding
    // whether it is a top surface. Side faces must not be displaced vertically.
    vPlayerNormal = aetherWaterVertexSafeNormalize(
        mat3(gbufferModelViewInverse) * sourceNormal, vec3(0.0, 1.0, 0.0)
    );

    if (isWater && vPlayerNormal.y > 0.65) {
        vec2 worldXZ = cameraPosition.xz + playerPosition.xz;
        float waveHeight = aetherWaterHeight(worldXZ, frameTimeCounter);
        vec2 waveOffsetXZ = aetherWaterDisplacementXZ(worldXZ, frameTimeCounter);
        vec3 worldOffset = vec3(waveOffsetXZ.x, waveHeight, waveOffsetXZ.y);

        // Displace only the top water surface. Shared world-space phase keeps
        // adjoining chunk vertices aligned while the camera crosses sections.
        viewPosition.xyz += mat3(gbufferModelView) * worldOffset;
        playerPosition = gbufferModelViewInverse * viewPosition;
    }

    vViewPos = viewPosition.xyz;
    vPlayerPos = playerPosition.xyz;
    vShadowCoord = shadowProjection * shadowModelView * playerPosition;
    gl_Position = gl_ProjectionMatrix * viewPosition;
}
