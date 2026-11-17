#version 330 compatibility

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

out vec3 vAetherSkyDirection;

vec3 aetherSkySafeNormalize(vec3 value, vec3 fallbackValue) {
    float magnitudeSquared = dot(value, value);
    if (!(magnitudeSquared > 1e-8) || !(magnitudeSquared < 1e20)) {
        return fallbackValue;
    }
    return value * inversesqrt(magnitudeSquared);
}

void main() {
    // Reconstruct the sky ray from the projected vertex, not its local dome coordinates.
    vec4 clipPosition = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex;
    float inverseClipW = abs(clipPosition.w) > 1e-6
        ? (1.0 / clipPosition.w) : 1.0;
    vec2 ndc = clipPosition.xy * inverseClipW;
    vec4 viewFar = gbufferProjectionInverse * vec4(ndc, 1.0, 1.0);
    float inverseViewW = abs(viewFar.w) > 1e-6
        ? (1.0 / viewFar.w) : 1.0;
    vec3 viewDirection = viewFar.xyz * inverseViewW;
    vAetherSkyDirection = aetherSkySafeNormalize(
        mat3(gbufferModelViewInverse) * viewDirection,
        vec3(0.0, 1.0, 0.0)
    );
    gl_Position = clipPosition;
}
