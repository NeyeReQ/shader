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
out float vFluidType;

float aetherWaterHeight(vec2 xz, float time) {
    return sin(xz.x * 0.105 + time * 0.62) * 0.115
         + sin(xz.y * 0.083 - time * 0.47) * 0.085
         + sin((xz.x + xz.y) * 0.052 + time * 0.34) * 0.055;
}

void main() {
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLightCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor = gl_Color;

    // IDs 120 (water) and 200 (lava) are spaced apart to support both
    // OptiFine direct IDs and Iris 1.8+ ID-minus-one conventions.
    vBlockId = mc_Entity.x;
    vFluidType = mc_Entity.y;

    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    vec3 playerPosition = (gbufferModelViewInverse * viewPosition).xyz;
    vec3 worldPosition = cameraPosition + playerPosition;

    bool waterId = abs(vBlockId - 119.0) < 0.25
                || abs(vBlockId - 120.0) < 0.25;
    bool lavaId = abs(vBlockId - 199.0) < 0.25
               || abs(vBlockId - 200.0) < 0.25;
    bool fluid = vFluidType > 0.5 || waterId || lavaId;

    // Move only the exposed top of water, leaving vertical sides stable.
    if (fluid && !lavaId && (waterId || vFluidType > 0.5)) {
        float surfaceMask = smoothstep(0.68, 0.84, fract(worldPosition.y));
        float height = aetherWaterHeight(worldPosition.xz, frameTimeCounter);
        vec3 worldDisplacement = vec3(0.0, height * surfaceMask, 0.0);
        viewPosition.xyz += mat3(gl_ModelViewMatrix) * worldDisplacement;
    }

    vViewPos = viewPosition.xyz;
    vPlayerPos = (gbufferModelViewInverse * viewPosition).xyz;
    vPlayerNormal = normalize(mat3(gbufferModelViewInverse)
                        * normalize(gl_NormalMatrix * gl_Normal));

    vec4 displacedPlayerPosition = gbufferModelViewInverse * viewPosition;
    vShadowCoord = shadowProjection * shadowModelView * displacedPlayerPosition;
    gl_Position = gl_ProjectionMatrix * viewPosition;
}
