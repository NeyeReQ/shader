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

void main() {
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLightCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor = gl_Color;
    vBlockId = mc_Entity.x;

    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    vec4 playerPosition = gbufferModelViewInverse * viewPosition;

    // block.properties assigns 120 to water. The same material ID is present
    // on every vertex of a fluid surface, so displacement remains continuous
    // across neighbouring water blocks and does not depend on mc_Entity.y.
    bool isWater = abs(vBlockId - 120.0) < 0.25
                || abs(vBlockId - 119.0) < 0.25;
    if (isWater) {
        vec2 worldXZ = cameraPosition.xz + playerPosition.xz;
        float waveHeight = aetherWaterHeight(worldXZ, frameTimeCounter);
        vec3 viewUp = normalize(mat3(gl_ModelViewMatrix) * vec3(0.0, 1.0, 0.0));
        viewPosition.xyz += viewUp * waveHeight;
        playerPosition = gbufferModelViewInverse * viewPosition;
    }

    vViewPos = viewPosition.xyz;
    vPlayerPos = playerPosition.xyz;
    vPlayerNormal = normalize(mat3(gbufferModelViewInverse)
                       * normalize(gl_NormalMatrix * gl_Normal));

    vShadowCoord = shadowProjection * shadowModelView * playerPosition;
    gl_Position = gl_ProjectionMatrix * viewPosition;
}
