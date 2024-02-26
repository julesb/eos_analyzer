
class ColorAnalyzer {
  static final int NUM_HUE_BINS = 256;
  public float[] huePowerBins = new float[NUM_HUE_BINS];
  public float[] huePowerBinsSmooth = new float[NUM_HUE_BINS];
  public float[] rgbPower = new float[3];
  color[] barColors = new color[3];
  int rgbPanelWidth = 100;

  public ColorAnalyzer() {
    barColors[0] = color(255,0,0, 192);
    barColors[1] = color(0,255,0, 192);
    barColors[2] = color(0,0,255, 192);
  }

  void draw(int x, int y, int w, int h) {
    stroke(borderColor);

    noFill();
    rect(x, y, w, h);

    // RGB Bars
    int pad = 10;
    int barWidth = rgbPanelWidth / 3 - pad;
    int barHeight = h - pad*2;

    for (int i=0; i < rgbPower.length; i++) {
      int bx = x + pad + i * (barWidth + pad);
      int by = y + pad;
      noFill();
      rect(bx, by, barWidth, h - pad*2);
      
      fill(barColors[i]);
      rect(bx, by + barHeight - rgbPower[i]* barHeight, barWidth, rgbPower[i]*barHeight);
    }

    drawHuePower(x+rgbPanelWidth+pad*1, y+pad, w-rgbPanelWidth - 2*pad, h-2*pad);
  }

  void drawHuePower(int x, int y, int w, int h) {
    float binW = (float)w / NUM_HUE_BINS;
    float vx, vy;
    noStroke();
    fill(4);
    rect(x, y, w, h);
    strokeWeight(1);
    noFill();

    beginShape();
    for (int i=0; i < NUM_HUE_BINS; i++) {
      color c = hsvToRgb((float)i / NUM_HUE_BINS, 1.0, 1.0);
      stroke(c,255);
      vx = x + i*binW;
      if (i > 0 && i < NUM_HUE_BINS-1) {
        vy = y+h - (h * (huePowerBinsSmooth[i-1]
                      + huePowerBinsSmooth[i]
                      + huePowerBinsSmooth[i+1]) / 3.0);
      }
      else {
        vy = y + h - huePowerBinsSmooth[i]*h;
      }
      vertex(vx, vy);
      // vertex(x + i*binW, max(y, y+h - huePowerBins[i]*h));
    }

    endShape();

  }
  
  void updateExpMovingAvg(float val, int idx) {
    float window = 10.0;
    float smooth = 2.0 / (window + 1);
    huePowerBinsSmooth[idx] = (val - huePowerBinsSmooth[idx]) * smooth + huePowerBinsSmooth[idx];
  }

  public void update(ArrayList<Point> points) {
    int npoints = points.size();
    float sumR = 0;
    float sumG = 0;
    float sumB = 0;

    int colPointCount = 0;
    huePowerBins = new float[NUM_HUE_BINS];
    // colorMode(HSB, ) 
    for (int i=0; i < npoints; i++) {
      Point p = points.get(i);
      if (p.isBlank()) {
        continue;
      }
      colPointCount++;
      color col = p.col;
      sumR += red(col);
      sumG += green(col);
      sumB += blue(col);

      float h = hue(col) / 255.0;
      float v = brightness(col) / 255.0;
      // println(v);
      int binIdx = (int) min(h * NUM_HUE_BINS, NUM_HUE_BINS-1);
      huePowerBins[binIdx] += v*v;
    }

    rgbPower[0] = (sumR / colPointCount) / 255.0;
    rgbPower[1] = (sumG / colPointCount) / 255.0;
    rgbPower[2] = (sumB / colPointCount) / 255.0;
  
    float maxPower = 0;
    for (int i=0; i < NUM_HUE_BINS; i++) {
      if (huePowerBins[i] > maxPower) {
        maxPower = huePowerBins[i];
      }
    }
  
    for (int i=0; i < NUM_HUE_BINS; i++) {
      // huePowerBins[i] /= colPointCount;
      huePowerBins[i] /= maxPower; // colPointCount;
      // huePowerBins[i] *= huePowerBins[i];
      updateExpMovingAvg(huePowerBins[i], i);
    }

  }

  float[] rgbToHsv(color rgb) {
    float h = hue(rgb);
    float s = saturation(rgb);
    float v = brightness(rgb);
    return new float[] {h, s, v};
  }

  color hsvToRgb(float h, float s, float v) {
    float r, g, b;

    int i = (int) Math.floor(h * 6);
    float f = h * 6 - i;
    float p = v * (1 - s);
    float q = v * (1 - f * s);
    float t = v * (1 - (1 - f) * s);

    switch (i % 6) {
        case 0: r = v; g = t; b = p; break;
        case 1: r = q; g = v; b = p; break;
        case 2: r = p; g = v; b = t; break;
        case 3: r = p; g = q; b = v; break;
        case 4: r = t; g = p; b = v; break;
        case 5: r = v; g = p; b = q; break;
        default: throw new IllegalArgumentException("Something went wrong in the HSV to RGB conversion.");
    }
    return color(r * 255, g * 255, b * 255);
  }

} 
