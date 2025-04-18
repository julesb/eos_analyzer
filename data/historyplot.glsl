uniform vec2 resolution;
uniform float values[512];

void main(void) {
  vec2 ar = vec2(resolution.x / resolution.y, 1.0);
  vec2 uv = (gl_FragCoord.xy / resolution) * ar;
  vec3 col = vec3(0.0, 0.0, 0.0);
  
  float lineThickness = 1.1 / resolution.y;
  //vec3 lineColor = vec3(0.3, 0.4, 0.6);
  vec3 lineColor = vec3(192./255., 248./255., 1./255.) * 0.66;
  // vec3 lineColor = vec3(192./255., 238./255., 1./255.) * 0.5;

  int idx = int(uv.x / ar.x * 512.0);
  int startIdx = max(0, idx - 10);
  int endIdx = min(511, idx + 10);

  float minDist = 1000;

  for (int i = startIdx; i < endIdx; i++) {
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
    t = max(0.0, min(1.0, t));
    vec2 projection = p0 + t * p0p1;
    float d = length(p - projection);
    minDist = min(minDist, d);
  }

  float alpha = smoothstep(lineThickness, 0., minDist);
  col.rgb += lineColor * alpha;
 

  gl_FragColor = vec4(col.rgb, 1.0);
}
