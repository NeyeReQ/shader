#version 330 compatibility

uniform mat4 gbufferModelViewInverse;

out vec3 vAetherSkyDirection;

vec3 aetherSafeNormalize(vec3 value, vec3 fallbackValue) {
    float magnitudeSquared = dot(value, value);
    if (!(magnitudeSquared > 1e-8) || !(magnitudeSquared < 1e20)) {
        return fallbackValue;
    }
    return value * inversesqrt(magnitudeSquared);
}

void main() {
    // Keep translation out of the ray: the sky direction is camera-rotation only.
    vec3 viewDirection = mat3(gl_ModelViewMatrix) * gl_Vertex.xyz;
    vAetherSkyDirection = aetherSafeNormalize(
        mat3(gbufferModelViewInverse) * viewDirection,
        vec3(0.0, 1.0, 0.0)
    );
    gl_Position = ftransform();
}
