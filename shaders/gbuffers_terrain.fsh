#version 330 compatibility

#include "/lib/lighting.glsl"

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform vec3 shadowLightPosition;
uniform float wetness;
uniform float rainStrength;
uniform float alphaTestRef;

in vec2 vTexCoord;
in vec2 vLightCoord;
in vec4 vColor;
in vec3 vViewPos;
in vec3 vViewNormal;
in vec4 vShadowCoord;

void main() {
    /* RENDERTARGETS: 0 */
    vec4 albedo = texture2D(gtexture, vTexCoord) * vColor;
    if (albedo.a < alphaTestRef) discard;

    vec3 normal = normalize(vViewNormal);
    vec3 lightDirection = normalize(shadowLightPosition);
    vec3 viewDirection = normalize(-vViewPos);

    float skyLight = clamp(vLightCoord.y, 0.0, 1.0);
    float blockLight = clamp(vLightCoord.x, 0.0, 1.0);
    float shadow = aetherShadowPCF(vShadowCoord, normal, lightDirection);

    // Cool skylight, warm emissive block light and a warm direct key light.
    vec3 skyAmbient = vec3(0.105, 0.135, 0.190)
                    + vec3(0.39, 0.47, 0.61) * pow(skyLight, 1.10);
    vec3 blockAmbient = vec3(1.00, 0.54, 0.27) * pow(blockLight, 1.25) * 0.78;

    float diffuse = max(dot(normal, lightDirection), 0.0);
    vec3 directLight = vec3(1.00, 0.87, 0.72)
                     * diffuse * pow(skyLight, 1.12) * shadow * 1.10;

    // Rain subtly increases the sheen on exposed surfaces.
    float wetSpecular = pow(max(dot(reflect(-lightDirection, normal), viewDirection), 0.0), 42.0);
    vec3 specular = vec3(1.00, 0.88, 0.73) * wetSpecular * wetness * 0.16 * shadow;

    vec3 lighting = skyAmbient + blockAmbient + directLight;
    vec3 finalColor = albedo.rgb * lighting + specular;
    finalColor = max(finalColor, vec3(0.0));

    gl_FragData[0] = vec4(finalColor, albedo.a);
}
