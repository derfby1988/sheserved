#version 460 core
#include <flutter/runtime_effect.glsl>

// Glass sheen + rim light for the 3D Court Card chrome.
// uSize  — card size in logical pixels (x, y)
// uLevel — 0..1, how "lit" the score core is (drives the red glow)
uniform vec2 uSize;
uniform float uLevel;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / max(uSize, vec2(1.0));

  // Diagonal sheen band sweeping across the glass.
  float diagonal = uv.x - uv.y * 0.35;
  float band = smoothstep(0.02, 0.42, diagonal) *
               (1.0 - smoothstep(0.48, 0.96, diagonal));

  // Rim light: brightest at the panel edges, calm in the middle.
  float innerX = smoothstep(0.0, 0.07, uv.x) *
                 (1.0 - smoothstep(0.93, 1.0, uv.x));
  float innerY = smoothstep(0.0, 0.07, uv.y) *
                 (1.0 - smoothstep(0.93, 1.0, uv.y));
  float rim = 1.0 - innerX * innerY;

  // Red core glow behind the cube stack.
  float d = distance(uv, vec2(0.78, 0.42));
  float glow = exp(-7.0 * d * d) * (0.30 + 0.70 * clamp(uLevel, 0.0, 1.0));

  vec3 base = vec3(0.95, 0.96, 0.98);
  vec3 warm = vec3(0.93, 0.12, 0.20);
  vec3 color = mix(base, warm, clamp(glow, 0.0, 1.0));
  color += vec3(1.0) * band * 0.22;
  color += vec3(1.0) * rim * 0.28;

  float alpha = 0.26 + 0.30 * band + 0.22 * rim + 0.30 * glow;
  alpha = clamp(alpha, 0.0, 0.92);
  fragColor = vec4(color * alpha, alpha);
}
