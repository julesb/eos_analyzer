uniform vec2 resolution;
uniform sampler2D ffttex;
float numbins = 2048;

void main(void) {
  vec2 uv = (gl_FragCoord.xy / resolution);
  float uvy = uv.y < 0.5? 0.0 : 0.5;
  vec4 encodedValue = texture2D(ffttex, vec2(uv.x, uvy));
  float value = encodedValue.a * 255.0 * 16777216.0
              + encodedValue.r * 255.0 * 65536.0
              + encodedValue.g * 255.0 * 256.0
              + encodedValue.b * 255.0;
  float decodedValue = intBitsToFloat(int(value));
  vec3 col = vec3(decodedValue);
  gl_FragColor = vec4(col, 1.0);
}


