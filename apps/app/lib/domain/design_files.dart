/// What a board on the design canvas can be besides a page.
library;

/// The 3D models the canvas shows with Helmy's own viewer (glTF, binary or
/// not, STL and OBJ): drawn, played and saved, never read as a page.
bool isModelFile(String file) =>
    RegExp(r'\.(glb|gltf|stl|obj)$', caseSensitive: false).hasMatch(file);
