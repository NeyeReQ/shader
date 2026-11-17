#version 330 compatibility

uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
in vec4 at_tangent;

out vec2 vTexCoord;
out vec2 vLightCoord;
out vec4 vColor;
out vec3 vViewPos;
out vec3 vViewNormal;
out vec3 vViewTangent;
out float vHandedness;
out vec4 vShadowCoord;

void main() {
    gl_Position = ftransform();
    vTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLightCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor = gl_Color;

    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    vViewPos = viewPosition.xyz;
    vViewNormal = normalize(gl_NormalMatrix * gl_Normal);
    vViewTangent = normalize(gl_NormalMatrix * at_tangent.xyz);
    vHandedness = at_tangent.w < 0.0 ? -1.0 : 1.0;

    vec4 playerPosition = gbufferModelViewInverse * viewPosition;
    vShadowCoord = shadowProjection * shadowModelView * playerPosition;
}
