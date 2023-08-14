uniform vec2 resolution;
uniform float time;
uniform float zoom;
uniform float values[512];
uniform float valuesindex; // start index

float exp_glow(vec2 uv, float e) {
    return e / length(uv);
}


void main(void) {
    vec2 ar = vec2(resolution.x/resolution.y, 1.0);
    vec2 uv = (gl_FragCoord.xy / resolution) * ar;

    vec3 col = vec3(0.0, 0.0, 0.0);
    
    int idx = int(uv.x/ar.x*512.0) % int(512);
    float value = values[idx];
    
    float currentValue = values[511];

    // fill area under curve
    // if (uv.y < value) {
    //   col.g = 0.5;
    // }
    
    vec2 vpos = vec2(uv.x,  value);
    
    // the point
    //col = vec3(exp_glow(uv - vpos, 0.001));
    col = vec3(smoothstep(1.0/resolution.y, 0., length(uv - vpos))) * vec3(0.2, 0.96, 0.8);

    // red dot at center - placeholder out-of-range indicator
    if (currentValue > 1.0 - (2.0 / resolution.y)) {
      col.r += exp_glow(uv - vec2(0.5, 0.5)*ar, 0.02);
    }

    gl_FragColor = vec4(col, 0.5);
}

