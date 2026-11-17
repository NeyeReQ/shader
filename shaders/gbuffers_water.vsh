#version 330 compatibility

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

float aetherWaterWaveHeight(vec2 worldXZ, float time) {
    float longWave = sin(worldXZ.x * 0.105 + time * 0.62) * 0.050;
    float crossWave = sin(worldXZ.y * 0.083 - time * 0.47) * 0.038;
    float diagonalWave = sin((worldXZ.x + worldXZ.y) * 0.052 + time * 0.34) * 0.026;
    return longWave + crossWave + diagonalWave;
}

void main() {
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLightCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor = gl_Color;
    vBlockId = mc_Entity.x;

    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    vec3 playerPosition = (gbufferModelViewInverse * viewPosition).xyz;
    vec3 worldPosition = cameraPosition + playerPosition;

    // block.100 in block.properties maps water to mc_Entity.x == 99.
    // Move only vertices at the top of water, including the upper edge of side faces,
    // so neighbouring block faces share the same displaced edge.
    if (abs(vBlockId - 99.0) < 0.25) {
        float surfaceMask = smoothstep(0.64, 0.83, fract(worldPosition.y));
        float waveHeight = aetherWaterWaveHeight(worldPosition.xz, frameTimeCounter);
        vec3 worldOffset = vec3(0.0, waveHeight * surfaceMask, 0.0);
        viewPosition.xyz += mat3(gl_ModelViewMatrix) * worldOffset;
    }

    vViewPos = viewPosition.xyz;
    vPlayerPos = (gbufferModelViewInverse * viewPosition).xyz;
    vPlayerNormal = normalize(mat3(gbufferModelViewInverse)
                        * normalize(gl_NormalMatrix * gl_Normal));

    vec4 displacedPlayerPosition = gbufferModelViewInverse * viewPosition;
    vShadowCoord = shadowProjection * shadowModelView * displacedPlayerPosition;

    gl_Position = gl_ProjectionMatrix * viewPosition;
}
