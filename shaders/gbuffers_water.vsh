#version 330 compatibility

#include "/lib/water.glsl"

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

void main() {
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLightCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor = gl_Color;
    vBlockId = mc_Entity.x;
    // Vitrail packs mc_Entity.y as the definitive fluid flag (1 for every
    // fluid quad, including fluids not explicitly listed in block.properties).
    vIsFluid = mc_Entity.y;

    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    vec4 playerPosition = gbufferModelViewInverse * viewPosition;

    // Use the fluid bit for the water path; use the pack material id only to
    // distinguish lava. This avoids silently treating water as ordinary glass
    // when its block id table is absent, changed, or mapped differently.
    bool isLava = abs(vBlockId - 200.0) < 0.25
               || abs(vBlockId - 199.0) < 0.25;
    bool isWater = vIsFluid > 0.5 && !isLava;
    if (isWater) {
        vec2 worldXZ = cameraPosition.xz + playerPosition.xz;
        float waveHeight = aetherWaterHeight(worldXZ, frameTimeCounter);
        vec2 waveOffsetXZ = aetherWaterDisplacementXZ(worldXZ, frameTimeCounter);
        vec3 worldOffset = vec3(waveOffsetXZ.x, waveHeight, waveOffsetXZ.y);
        // Apply the Gerstner displacement in world axes, then let the view
        // transform carry it to clip space. World-space phase keeps chunk
        // boundaries welded even as the camera crosses sections.
        viewPosition.xyz += mat3(gl_ModelViewMatrix) * worldOffset;
        playerPosition = gbufferModelViewInverse * viewPosition;
    }

    vViewPos = viewPosition.xyz;
    vPlayerPos = playerPosition.xyz;

    // Some fluid faces can arrive without a usable normal in the compact
    // translucent mesh. Never normalise a zero vector: use the top-surface
    // normal as a safe fallback, then transform it back to world space.
    vec3 sourceNormal = gl_NormalMatrix * gl_Normal;
    float sourceNormalLength = dot(sourceNormal, sourceNormal);
    if (!(sourceNormalLength > 1e-8)) {
        sourceNormal = vec3(0.0, 1.0, 0.0);
    }
    vPlayerNormal = normalize(mat3(gbufferModelViewInverse) * sourceNormal);

    vShadowCoord = shadowProjection * shadowModelView * playerPosition;
    gl_Position = gl_ProjectionMatrix * viewPosition;
}
