#version 330 compatibility

uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform int moonPhase;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float cloudHeight;

in vec3 vAetherSkyDirection;

#include "/lib/sky.glsl"

void main() {
    /* RENDERTARGETS: 0 */
    vec3 ray = aetherSafeNormalize(vAetherSkyDirection, vec3(0.0, 1.0, 0.0));
    gl_FragData[0] = vec4(aetherRenderSky(ray, cameraPosition), 1.0);
}
