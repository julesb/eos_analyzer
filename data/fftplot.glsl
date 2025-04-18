uniform vec2 resolution;
uniform sampler2D ffttex;

float saturate(float x) { return clamp(x, 0.0, 1.0); }

vec3 inferno_quintic(float x) {
	x = saturate(x);
	vec4 x1 = vec4(1.0, x, x*x, x*x*x); // 1 x x2 x3
	vec4 x2 = x1 * x1.w * x; // x4 x5 x6 x7
	return vec3(
		dot( x1.xyzw, vec4( -0.027780558, +1.228188385, +0.278906882, +3.892783760 ) )
        + dot( x2.xy, vec2( -8.490712758, +4.069046086 ) ),
		dot( x1.xyzw, vec4( +0.014065206, +0.015360518, +1.605395918, -4.821108251 ) )
        + dot( x2.xy, vec2( +8.389314011, -4.193858954 ) ),
		dot( x1.xyzw, vec4( -0.019628385, +3.122510347, -5.893222355, +2.798380308 ) )
        + dot( x2.xy, vec2( -3.608884658, +4.324996022 ) ) );
}


void main(void) {
  vec2 uv = (gl_FragCoord.xy / resolution);
  float texv = uv.y < 0.5? 0.0 : 1.0;
  vec4 encodedValue = texture2D(ffttex, vec2(uv.x, 1.0 - texv));
  float value = encodedValue.a * 255.0 * 16777216.0
              + encodedValue.r * 255.0 * 65536.0
              + encodedValue.g * 255.0 * 256.0
              + encodedValue.b * 255.0;
  float fftvalue = intBitsToFloat(int(value)) * 0.333333;
  vec3 col = vec3(0.0);

  if (uv.y < 0.5) {
    if (uv.y < fftvalue) {
      col += inferno_quintic(fftvalue*3.0);
      //col += vec3(0.1, 1.0, 0.1);
    }
    if (abs(uv.y - fftvalue) < 1.0 / resolution.y) {
      col += vec3(1.0);
    }
  }
  else {
    if (uv.y - 0.5 < fftvalue) {
      col += inferno_quintic(fftvalue*3.0);
      // col += vec3(0.1, 0.1, 1.0);
    }
    if (abs(uv.y-0.5 - fftvalue) < 1.0 / resolution.y) {
      col += vec3(1.0);
    }
  }

  // if (abs(uv.y - fftvalue) < 1.0 / resolution.y
  //  || abs(uv.y+0.5 - fftvalue) < 1.0 / resolution.y) {
  //   col += vec3(1.0);
  // }

  // col = vec3(length(uv));
  gl_FragColor = vec4(col, 1.0);
}


