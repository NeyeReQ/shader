#version 330 compatibility

// Vitrail supplies Minecraft's generated cloud vertices through gl_Vertex.
// The pack draws its own volumetric atmosphere in composite.fsh, so this
// compatibility program only keeps the cloud format available to the engine.
void main() {
    gl_Position = ftransform();
}
