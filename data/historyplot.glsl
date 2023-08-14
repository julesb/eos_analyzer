uniform vec2 resolution;
uniform float values[512];

void main(void) {
  vec2 ar = vec2(resolution.x / resolution.y, 1.0);
  vec2 uv = (gl_FragCoord.xy / resolution) * ar;
  vec4 col = vec4(0.0, 0.0, 0.0, 1.0);
  
  //float lineThickness = 1.25 / 300.0;
  float lineThickness = 1.5 / resolution.y;

  int idx = int(uv.x / ar.x * 512.0); // % 512;
  int startIdx = max(0, idx - 1);
  int endIdx = min(511, idx + 1);

  for (int i = startIdx; i <= endIdx; i++) {
    float x0 = float(i) / 511.0;
    float x1 = float(i + 1) / 511.0;
    float y0 = values[i];
    float y1 = values[i + 1];
    vec2 p0 = vec2(x0, y0) * ar;
    vec2 p1 = vec2(x1, y1) * ar;
    vec2 p = uv.xy;
    vec2 p0p1 = p1 - p0;
    vec2 p0p = p - p0;
    float t = dot(p0p, p0p1) / dot(p0p1, p0p1);

    if (t < 0.0) t = 0.0;
    if (t > 1.0) t = 1.0;

    vec2 projection = p0 + t * p0p1;
    float d = length(p - projection);

    float alpha = smoothstep(lineThickness, 0., d);
    col += vec4(vec3(0.5, 0.5, 0.5), alpha) * alpha;

    //col += vec3(smoothstep(lineThickness, 0., d)) * vec3(0.2, 0.96, 0.8);
  }

  gl_FragColor = vec4(col.rgb, 0.5);
}
