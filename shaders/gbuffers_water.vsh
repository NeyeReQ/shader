#version 330 compatibility

uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

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

    // Water classification comes from block.properties. Geometry stays on
    // Minecraft's original fluid mesh; waves are shading normals, not displacement.
    vBlockId = mc_Entity.x;

    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    vViewPos = viewPosition.xyz;
    vPlayerPos = (gbufferModelViewInverse * viewPosition).xyz;
    vPlayerNormal = normalize(mat3(gbufferModelViewInverse)
                       * normalize(gl_NormalMatrix * gl_Normal));

    vec4 playerPosition = gbufferModelViewInverse * viewPosition;
    vShadowCoord = shadowProjection * shadowModelView * playerPosition;
    gl_Position = gl_ProjectionMatrix * viewPosition;
}
