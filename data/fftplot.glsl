uniform vec2 resolution;
uniform sampler2D ffttex;

void main(void) {
  vec2 uv = (gl_FragCoord.xy / resolution);
  float texv = uv.y < 0.5? 0.0 : 1.0;
  vec4 encodedValue = texture2D(ffttex, vec2(uv.x, 1.0 - texv));
  float value = encodedValue.a * 255.0 * 16777216.0
              + encodedValue.r * 255.0 * 65536.0
              + encodedValue.g * 255.0 * 256.0
              + encodedValue.b * 255.0;
  float fftvalue = intBitsToFloat(int(value)) * 0.5;
  vec3 col = vec3(0.0);

  if (uv.y < 0.5) {
    if (uv.y < fftvalue) {
      col += vec3(0.1, 1.0, 0.1);
    }
  }
  else {
    if (uv.y - 0.5 < fftvalue) {
      col += vec3(0.1, 0.1, 1.0);
    }
  }

  gl_FragColor = vec4(col, 1.0);
}


