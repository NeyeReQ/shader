#version 330 compatibility

uniform sampler2D texture;
uniform float alphaTestRef;

in vec2 vTexCoord;
in vec4 vColor;

void main() {
    vec4 texel = texture2D(texture, vTexCoord) * vColor;
    if (texel.a < alphaTestRef) discard;
}
