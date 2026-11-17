#version 330 compatibility

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float viewWidth;
uniform float viewHeight;

#include "/lib/sky.glsl"

void main() {
    /* RENDERTARGETS: 0 */
    // A per-pixel ray avoids polygon-shaped cloud distortion from interpolating
    // a direction across the engine's low-resolution sky dome.
    vec2 uv = gl_FragCoord.xy / max(vec2(viewWidth, viewHeight), vec2(1.0));
    vec2 ndc = uv * 2.0 - 1.0;
    vec4 farPoint = gbufferProjectionInverse * vec4(ndc, 1.0, 1.0);
    float inverseW = abs(farPoint.w) > 0.00001 ? (1.0 / farPoint.w) : 1.0;
    vec3 viewRay = aetherSafeNormalize(
        farPoint.xyz * inverseW, vec3(0.0, 1.0, 0.0)
    );
    vec3 playerRay = aetherSafeNormalize(
        mat3(gbufferModelViewInverse) * viewRay, vec3(0.0, 1.0, 0.0)
    );
    gl_FragData[0] = vec4(aetherRenderSky(playerRay, cameraPosition), 1.0);
}
