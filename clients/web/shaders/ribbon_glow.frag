#version 460 core
#include <flutter/runtime_effect.glsl>

// Ribbon Glow — Originkit, adapted from the user-supplied shader for Flutter.
uniform vec2 uRes;
uniform float uTime;
uniform vec2 uMouse;
uniform float uOn;
out vec4 fragColor;

mat2 rot(float a) { return mat2(cos(a), sin(a), -sin(a), cos(a)); }

void main() {
  vec2 frag = FlutterFragCoord().xy;
  frag.y = uRes.y - frag.y;
  vec2 pos = (frag - 0.5 * uRes) / uRes.y;
  vec2 d = pos - uMouse;
  float w = uOn * exp(-dot(d, d) / (0.32 * 0.32));
  pos = uMouse + rot(w * 1.25) * d * (1.0 - 0.3 * w);
  pos = rot(-3.14159265) * pos;
  float t = uTime * 0.49 + 12.0;
  float breath = (-sin(uTime * 0.735) + sin(uTime * 0.49 + 1.0)) * 0.25 + 0.5;
  vec2 u = rot(0.6) * ((pos - vec2(-0.62, 0.24)) * (1.05 - breath * 0.085));
  mat2 fold = mat2(cos(2.13), sin(2.13), -0.963, cos(2.13));
  vec3 col = vec3(0.0);
  for (float i = 1.0; i <= 84.0; i += 1.0) {
    u.x -= sin(u.y * 0.42 + t + i * 0.007) * 0.13;
    u.y -= sin(u.x * 2.4 - t + i * 0.02) * 0.027;
    u = fold * u * 0.953;
    vec2 q = (u - vec2(0.36 + breath * 0.1, 0.0)) * vec2(2.1, 0.17);
    float g = 0.0021 / (dot(q, q) + 0.0019) * (0.25 + breath * 0.4);
    float r = length(u);
    float k = sin(i * 0.16 + t * 1.2 + r * 2.0) * 0.5 + 0.5;
    col += g * mix(vec3(0.10, 0.38, 1.0), vec3(0.18, 0.83, 0.95), k)
        * (0.62 + 0.5 * k) * exp2(-r * 0.37);
  }
  vec3 x = max(col * 0.62, 0.0);
  col = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);
  col = pow(clamp(col, 0.0, 1.0), vec3(0.85, 0.92, 0.98));
  col *= 1.0 - smoothstep(0.5, 1.6, length(pos)) * 0.07;
  vec3 bg = vec3(0.022, 0.055, 0.12);
  fragColor = vec4(bg + col * (1.0 - bg), 1.0);
}
