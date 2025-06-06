
class HistoryPlot {
  public String name;
  public int historyLength;
  public float rangeMin;
  public float rangeMax;
  float[] values;
  int currentIndex;
  float emaWindowSize;
  float expMovingAvg;
  float bufferAvg;
  String numberFormat = "float";
  String units = "";
  PGraphics g;
  PShader plotShader;
  int indicatorWidth = 50;

  public HistoryPlot(String name, int historyLength, float rangeMin, float rangeMax, float emaWindowSize, String numberFormat, String units) {
    PGraphics g;
    this.name = name;
    this.historyLength = historyLength;
    this.rangeMin = rangeMin;
    this.rangeMax = rangeMax;
    this.values = new float[historyLength];
    this.emaWindowSize = emaWindowSize;
    this.numberFormat = numberFormat;
    this.units = units;
    this.expMovingAvg = 0.0;
    this.bufferAvg = 0.0;
    this.currentIndex = -1;
    initShader();
    println("HistoryPlot: ", this.name, this.historyLength);
  }

  public void initShader() {
    plotShader = loadShader("historyplot.glsl");
  }

  public void addValue(float newValue) {
    expMovingAvg = computeExpMovingAvg(newValue);
    bufferAvg = computeBufferAvg(newValue);
    currentIndex = (currentIndex+1) % historyLength;
    values[currentIndex] = expMovingAvg;
  }


  float computeExpMovingAvg(float val) {
    float smooth = 2.0 / (emaWindowSize + 1);
    return (val - expMovingAvg) * smooth + expMovingAvg;
  }
  float computeBufferAvg(float val) {
    float smooth = 2.0 / (historyLength + 1);
    return (val - bufferAvg) * smooth + bufferAvg;
  }


  
  public void drawShader(int x, int y, int w, int h) {
    int plotw = w - indicatorWidth;
    float ar = (float)plotw/h;
    float[] res = { (float)plotw, (float)h };

    if (this.g == null || g.width != plotw || g.height != h) {
      g = createGraphics(plotw, h, P3D);
    }


    float[] valuesNormalized = new float[historyLength];
    float pix = 1.0 / plotw; 
    for (int i=0;i<historyLength;i++) {
      int vidx = (currentIndex+1+i) % historyLength;
      valuesNormalized[i] = map(values[vidx], rangeMin, rangeMax, 0.0, 1.0);
      valuesNormalized[i] = max(pix*4, min(valuesNormalized[i], (1-pix*4)));
    }

    g.beginDraw();
    plotShader.set("values", valuesNormalized);
    plotShader.set("resolution", res);

    g.shader(plotShader);
    g.beginShape(QUADS);
    g.vertex(0, 0,  0, 0);
    g.vertex( plotw, 0, ar, 0);
    g.vertex( plotw,  h, ar, 1);
    g.vertex(0,  h,  0, 1);
    g.endShape();
    g.endDraw();
    
    fill(255,255,255,255);
    image(g, x, y, plotw, h);

  }

  public void draw(int x, int y, int w, int h) {
    boolean clipped;
    float xpos=0, ypos=0, ylen=0;
    int w2 = w - indicatorWidth;

    float dynamicTextSize = map(h, 50, 200, 24, 32);
    textSize(dynamicTextSize);
    float labelWidth = textWidth("XXXXXX");
    float valueOffset = labelWidth*1.1;
    float textYOffset = y+dynamicTextSize * 0.9;

    color plotColor = color(255,255,255,128); // neon green
    color needleColor = color(192,238,1,255);
    strokeWeight(1);
    stroke(borderColor);
    noFill();
    rect(x,y,w,h);

    fill(255,255,255,32);
    rect(x+2,y+2, labelWidth, dynamicTextSize*1.1);

    fill(255,255,255);
    text(name, x+8, textYOffset);

    fill(255,255,255, 240);
    if (this.numberFormat == "float") {
      text(String.format("%.2f %s", expMovingAvg, units), x+valueOffset, textYOffset);
    }
    else {
      text(String.format("%d %s", (int)expMovingAvg, units), x+valueOffset, textYOffset);
    }

    noFill();
    //stroke(255,255,255,240);
    float range = this.rangeMax - this.rangeMin;
    float clippedVal = min(max(rangeMin, values[currentIndex]), rangeMax);
    ylen = clippedVal / range * (h -2);
    ypos = y + h - ylen - 1;

    // strokeWeight(1.5);
    // for (int i = 0; i < w2; i++) {
    //   int hidx = (int)(currentIndex+1 + (float)i / w2 * historyLength) % historyLength;
    //   if (hidx < 0) continue;
    //   xpos = x + i;
    //   float val = values[hidx];
    //   clipped = (val < rangeMin || val > rangeMax); 
    //   float clippedVal = min(max(rangeMin, val), rangeMax);
    //   ylen = clippedVal / range * (h -2);
    //   ypos = y + h - ylen - 1;
    //   if (clipped) {
    //     stroke(255,0,0);
    //   }
    //   else {
    //     stroke(plotColor);
    //   }
    //   point(xpos, ypos);
    // }


    // center line
    stroke(255,255,255,16);
    strokeWeight(1);
    line(x, y+h/2, x+w-indicatorWidth, y+h/2);

    // bar graph
    // noStroke();
    // fill(255,255,255,128);
    // rect(xpos-10, ypos, 10, ylen);
    
    // buffer average
    int bavgy  = (int)(y+h - bufferAvg/range*h);

    // buffer avg to current avg delta
    if (ypos < bavgy) {
      stroke(255,0,0,255);
    }
    else {
      stroke(64,128,255,255);
    }
    strokeWeight(6);
    line(x+w-indicatorWidth+6, ypos, x+w-indicatorWidth+6, bavgy);
    //line(x+w-2, ypos, x+w-2, bavgy);
    
    strokeWeight(4);
    stroke(255,255,255,255);
    line(x+w - indicatorWidth+3, bavgy, x+w-indicatorWidth+12, bavgy);

    // needle
    stroke(needleColor);
    strokeWeight(1);
    line(x+w - indicatorWidth*3/4, ypos, x+w-2, ypos);
    
    strokeWeight(3);
    line(x+w - indicatorWidth/2, ypos, x+w-2, ypos);
    
    strokeWeight(5);
    line(x+w-indicatorWidth/4, ypos, x+w-2, ypos);
    //line(xpos-10, ypos, xpos, ypos);

    // // needlepoint
    // strokeWeight(1);
    // stroke(255,255,255,240);
    // point(x+w - indicatorWidth*3/4, ypos);

    // indicator separator
    strokeWeight(1);
    stroke(255,255,255,64);
    line(x+w - indicatorWidth, y, x+w - indicatorWidth, y+h);

  // graduations
    strokeWeight(1);
    stroke(255,255,255,160);
    int numGrads = 4;
    int gradLen = 16;
    int step = h / (numGrads);
    for (int gy=0; gy<=numGrads; gy++) {
      line(x+w - indicatorWidth+1, y + gy*step,
           x+w - indicatorWidth + gradLen, y + gy*step);
    }
    numGrads = 8;
    gradLen = 6;
    step = h / (numGrads);
    for (int gy=0; gy<=numGrads; gy++) {
      line(x+w - indicatorWidth+1, y + gy*step,
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
    text(String.format("% 4.0f%s", rangeMin, ""), xpos, yMinPos);
    text(String.format("% 4.0f%s", rangeMax, ""), xpos, yMaxPos);
    if (h > 100) {
      if (this.numberFormat == "float") {
        text(String.format("% 4.1f%s", (rangeMax-rangeMin)/2, ""), xpos, yCenterPos);
      }
      else {
        text(String.format("% 4.0f%s", (rangeMax-rangeMin)/2, ""), xpos, yCenterPos);
      }
    }
  }
}
