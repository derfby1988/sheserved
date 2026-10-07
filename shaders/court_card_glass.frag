#version 460 core
#include <flutter/runtime_effect.glsl>

// Glass sheen + soft ambient glow for the 3D Court Card chrome.
// uSize  — art size in logical pixels (x, y)
// uLevel — 0..1, score lit level (drives the red glow)
uniform vec2 uSize;
uniform float uLevel;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / max(uSize, vec2(1.0));

  // Diagonal sheen band sweeping across the surface.
  float diagonal = uv.x - uv.y * 0.35;
  float band = smoothstep(0.08, 0.42, diagonal) *
               (1.0 - smoothstep(0.48, 0.88, diagonal));

  // Soft radiant core glow centered over the cube cluster
  float d = distance(uv, vec2(0.5, 0.52));
  float glow = exp(-4.5 * d * d) * (0.30 + 0.70 * clamp(uLevel, 0.0, 1.0));

  vec3 base = vec3(1.0, 0.28, 0.34);
  vec3 warm = vec3(1.0, 0.10, 0.18);
  vec3 color = mix(base, warm, clamp(glow, 0.0, 1.0));
  color += vec3(1.0) * band * 0.35;

  float alpha = 0.12 * band + 0.28 * glow;
  alpha = clamp(alpha, 0.0, 0.70);
  fragColor = vec4(color * alpha, alpha);
}
