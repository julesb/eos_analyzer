
class HistoryPlot {
  public String name;
  public int historyLength;
  public float rangeMin;
  public float rangeMax;
  float[] values;
  int currentIndex;
  float emaWindowSize;
  float expMovingAvg;
  String numberFormat = "float";
  String units = "";

  public HistoryPlot(String name, int historyLength, float rangeMin, float rangeMax, float emaWindowSize, String numberFormat, String units) {
    this.name = name;
    this.historyLength = historyLength;
    this.rangeMin = rangeMin;
    this.rangeMax = rangeMax;
    this.values = new float[historyLength];
    this.emaWindowSize = emaWindowSize;
    this.numberFormat = numberFormat;
    this.units = units;
    this.expMovingAvg = 0.0;
    this.currentIndex = -1;


    println("HistoryPlot: ", this.name, this.historyLength);
  }

  public void addValue(float newValue) {
    expMovingAvg = computeExpMovingAvg(newValue);
    currentIndex = (currentIndex+1) % historyLength;
    values[currentIndex] = expMovingAvg;
  }


  float computeExpMovingAvg(float val) {
    float smooth = 2.0 / (emaWindowSize + 1);
    return (val - expMovingAvg) * smooth + expMovingAvg;
  }


  public void draw(int x, int y, int w, int h) {
    boolean clipped;
    float xpos=0, ypos=0, ylen=0;
    int indicatorWidth = 50;
    int w2 = w - indicatorWidth;
    stroke(255,255,255,64);
    strokeWeight(1);
    fill(0, 0, 0, 192);
    rect(x,y,w,h);
    fill(255,255,255);
    textSize(36);

    if (this.numberFormat == "float") {
      text(String.format("%s: %.2f%s", name, expMovingAvg, units), x+5, y+30);
    }
    else {
      text(String.format("%s: %d%s", name, (int)expMovingAvg, units), x+5, y+30);
    }

      noFill();
    //stroke(255,255,255,240);
    float range = this.rangeMax - this.rangeMin;

    // int numlines = 100;
    // for (int i = 0; i < numlines; i++) {
    //   int hidx = (int)(currentIndex + (float)i / numlines * historyLength) % historyLength;
    //   int hidx2 = (int)(currentIndex + (float)(i+1) / numlines * historyLength) % historyLength;
    //   xpos = x + i* (1.0/numlines)*w2;
    //   float xpos2 = x + (i+1) * (1.0/numlines)*w2;
    //   float val = values[hidx];
    //   float val2 = values[hidx2];
    //
    //   clipped = (val < rangeMin || val > rangeMax); 
    //   float clippedVal = min(max(rangeMin, val), rangeMax);
    //   ylen = clippedVal / range * (h -2);
    //   
    //   float clippedVal2 = min(max(rangeMin, val2), rangeMax);
    //   float ylen2 = clippedVal2 / range * (h -2);
    //   
    //   ypos = y + h - ylen - 1;
    //   float ypos2 = y + h - ylen2 - 1;
    //
    //   if (clipped) {
    //     stroke(255,0,0);
    //   }
    //   else {
    //     stroke(255,255,255);
    //   }
    //   line(xpos, ypos, xpos2, ypos2); 
    //   point(xpos, ypos);
    // }

    strokeWeight(1.5);
    for (int i = 0; i < w2; i++) {
      int hidx = (int)(currentIndex + (float)i / w2 * historyLength) % historyLength;
      xpos = x + i;
      float val = values[hidx];
      clipped = (val < rangeMin || val > rangeMax); 
      float clippedVal = min(max(rangeMin, val), rangeMax);
      ylen = clippedVal / range * (h -2);
      
      ypos = y + h - ylen - 1;

      if (clipped) {
        stroke(255,0,0);
      }
      else {
        stroke(255,255,255,192);
      }
      point(xpos, ypos);
    }

    // center line
    stroke(255,255,255,48);
    strokeWeight(1);
    line(x, y+h/2, x+w-indicatorWidth, y+h/2);

    // bar graph
    // noStroke();
    // fill(255,255,255,128);
    // rect(xpos-10, ypos, 10, ylen);
    
    // needle
    strokeWeight(1);
    stroke(255,255,255,192);
    line(x+w - indicatorWidth*3/4, ypos, x+w, ypos);

    // needlepoint
    strokeWeight(2);
    stroke(255,255,255,220);
    point(x+w - indicatorWidth*3/4, ypos);

    // indicator separator
    strokeWeight(1);
    stroke(255,255,255,192);
    line(x+w - indicatorWidth, y, x+w - indicatorWidth, y+h);

    // indicator 
    strokeWeight(4);
    stroke(255,255,255);
    line(x+w-indicatorWidth/6, ypos, x+w, ypos);
    //line(xpos-10, ypos, xpos, ypos);
    
  // graduations
    strokeWeight(1);
    stroke(255,255,255,160);
    int numGrads = 4;
    int gradLen = 16;
    int step = h / (numGrads);
    for (int gy=0; gy<=numGrads; gy++) {
      line(x+w - indicatorWidth, y + gy*step,
           x+w - indicatorWidth + gradLen, y + gy*step);
    }
    numGrads = 8;
    gradLen = 6;
    step = h / (numGrads);
    for (int gy=0; gy<=numGrads; gy++) {
      line(x+w - indicatorWidth, y + gy*step,
           x+w - indicatorWidth + gradLen, y + gy*step);
    }

    drawScale(x,y,w,h);
  }

  void drawScale(int x, int y, int w, int h) {
    int textsize = 20;
    int xpos = x + w - 50;
    int yMinPos = y + h - textsize/2;
    int yMaxPos = y + textsize;
    int yCenterPos = y + h/2;

    fill(255, 255, 255, 128);
    textSize(textsize);
    text(String.format("% 4.0f%s", rangeMin, units), xpos, yMinPos);
    text(String.format("% 4.0f%s", rangeMax, units), xpos, yMaxPos);
    if (this.numberFormat == "float") {
      text(String.format("% 4.1f%s", (rangeMax-rangeMin)/2, units), xpos, yCenterPos);
    }
    else {
      text(String.format("% 4.0f%s", (rangeMax-rangeMin)/2, units), xpos, yCenterPos);
    }
  }

  public void draw1(int x, int y, int w, int h) {
    stroke(255,255,255,64);
    strokeWeight(1);
    fill(0, 0, 0, 192);
    rect(x,y,w,h);
    fill(255,255,255);
    textSize(16);
    text(name, x+5, y+21);
    noFill();
    stroke(255,255,255,240);
    for (int i = 0; i < w; i++) {
      int hidx = (currentIndex + i) % historyLength;
      float xpos = x + i;
      float ypos = y + 1 + (1 - values[hidx]) * (h-2);
      point(xpos, ypos);
    }
  }
}
