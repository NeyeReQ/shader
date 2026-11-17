#version 330 compatibility

// Sky colour is reconstructed per fragment in gbuffers_skybasic.fsh.
// The vertex stage only preserves the renderer's sky geometry.
void main() {
    gl_Position = ftransform();
}
