
class GalvoPlot {
  PGraphics g;
  int ctxWidth;
  int ctxHeight;
  Boolean ctxResizeLock = false;
  int regionAreaHeight = 80;
  int infoAreaHeight = 20;
  int vpad= 10;
  
  int selectedPointIndex = 0;
  Point selectedPoint;
  
  Boolean fitToWidth = true;
  int scaledPlotWidth = 1;

  float zoom = 1.0;
  float zoomVelocity = 0.0;
  float cursorNormalized = 0.0;

  Boolean shapeRender = true;

  public GalvoPlot(int _ctxWidth, int _ctxHeight) {
    ctxWidth = _ctxWidth;
    ctxHeight = _ctxHeight;
    g = createGraphics(ctxWidth, ctxHeight, P2D);
  }


  public void render(ArrayList<Point> points, ArrayList<Region> regions,
                     float smoothPointCount) {
    if (ctxResizeLock) {
      println("resize lock");
      return;
    }
    int w = g.width-1;
    if (!fitToWidth) {
      w = min(w, (int)(smoothPointCount/4096.0 * w *2));
    }
    scaledPlotWidth = w;

    zoomVelocity *= 0.8;
    zoom += zoomVelocity;
    zoom = max(1.0, zoom);

    g.beginDraw();
    g.background(0);
    drawZoomIndicator(0, 0, g.width, g.height, points.size());
    drawRegions(0, vpad, scaledPlotWidth, regionAreaHeight, points, regions);
    drawGalvoPlot(0, 0, scaledPlotWidth, g.height, points, regions);
    drawCursor(0, 0, g.width, g.height, points.size());

    g.endDraw();
  }

  void setSelectedIndex(int pointIndex, ArrayList<Point> points) {
    if (pointIndex >= 0 && pointIndex < points.size()) {
      this.selectedPointIndex = pointIndex;
      this.selectedPoint = points.get(pointIndex);
      this.cursorNormalized = (float)pointIndex / points.size();
    }
    else {
      this.selectedPointIndex = -1;
      this.selectedPoint = null;
    }
  }

  void updateCursor(int mx, int my, Rect screenRect, ArrayList<Point> points) {
    float cursortmp = ((float)mx - screenRect.x) / screenRect.w;
    setSelectedIndex((int)(cursortmp * points.size()), points);
  }


  void drawRegions(int x, int y, int w, int h, 
      ArrayList<Point> points, ArrayList<Region> regions) {
    int npoints = points.size();
    int nregions = regions.size();
    int pad = 1;
    float nchannels = 4;
    float channelPad = 1;
    float channelHeight = (h - (channelPad * (1 + nchannels))) / nchannels;

    int npaths = 0; 
    float y1;

    final int channelRankDwellBlank = 3;
    final int channelRankBlank      = 2;
    final int channelRankDwellColor = 0;
    final int channelRankPath       = 1;

    g.blendMode(REPLACE);

    g.strokeWeight(1);
    //g.noStroke();
    //g.fill(255,255,255,8);
    //g.rect(x, y, w-1, h-1);

    g.stroke(255,255,255,8);
    for (int i=0; i < 5; i++) {
      int yline = (int) (y + pad + i * channelHeight);
      //g.line(0, yline, g.width, yline);
      g.line(0, yline, scaledPlotWidth, yline);
    }
    
    for (int ridx=0; ridx < nregions; ridx++) {
      Region region = regions.get(ridx);
      float x1 = x + w * getScreenXForIndex(region.startIndex, cursorNormalized,
                                            zoom, npoints);
      float x2 = x + w * getScreenXForIndex(region.endIndex, cursorNormalized,
                                            zoom, npoints);
      float xw = x2 - x1;
      switch(region.type) {
        case Region.BLANK:
          y1 = y + pad + channelHeight/4 + channelHeight * channelRankBlank;
          g.stroke(255,255,255,96);
          g.fill(0,0,0, 255);
          g.rect((int)x1, (int)y1, (int)xw, (int)channelHeight/2);
          break;
        case Region.PATH:
          npaths++;
          y1 = y + pad + channelHeight/4 + channelHeight * channelRankPath;
          g.noStroke();
          g.fill(255,255,255,32);
          for (int pidx=region.startIndex; pidx <= region.endIndex; pidx++) {
            Point p1 = points.get(pidx);
            float px = x + w * getScreenXForIndex(pidx, cursorNormalized, zoom, npoints);
            g.fill(p1.r, p1.g, p1.b, 160);
            g.rect(px, y1, xw/region.pointCount, channelHeight/2);
          }
          break;
        case Region.DWELL:
          if ((points.get(region.startIndex)).isBlank()) {
            y1 = y + pad + channelHeight * channelRankDwellBlank + 2;
            g.stroke(255,255,255,128);
            g.fill(0,0,0);
            g.rect(x1, y1, xw, channelHeight-6);
          }
          else {
            y1 = y + pad + channelHeight * channelRankDwellColor + 2;
            g.fill(region.col[0],region.col[1],region.col[2],192);
            g.noStroke();
            g.rect(x1, y1, xw, channelHeight - 6);
          }
          break;
      }
    }

    pathsHistory.addValue(npaths);
  }

  // normalized cursor, zoom => normalized viewport min x
  float getViewportMinX(float cursor, float zoom) {
    return cursor * (1.0f - 1.0f / zoom);
  }

  float getViewportMaxX(float cursor, float zoom) {
    return getViewportMin(cursor, zoom) + 1.0f / zoom;
  }

  float getScreenXForIndex(int sampleIndex, float cursor, float zoom, int waveBufferLen) {
      // Convert sample index to a normalized position.
      float normalizedSampleIndex = (float)sampleIndex / waveBufferLen;

      // Calculate the normalized position of this sample within the viewport.
      float viewportMin = getViewportMin(cursor, zoom);
      float viewportMax = getViewportMax(cursor, zoom);
      float screenX = (normalizedSampleIndex - viewportMin) / (viewportMax - viewportMin);

      return screenX;
  }


  void drawGalvoPlot(int x, int y, int w, int h,
                     ArrayList<Point> points, ArrayList<Region> regions) {
    int plotAreaMinY = y + regionAreaHeight + infoAreaHeight + 1;
    int plotAreaMaxY = y + h - infoAreaHeight -1;
    int plotAreaCenterY = (plotAreaMinY+plotAreaMaxY)/2;
    int plotAreaHeight = plotAreaMaxY - plotAreaMinY;
    int plotHeight = plotAreaHeight/2 - vpad*2; // height of a single plot

    int xplotCenterY = plotAreaMinY + vpad + plotHeight/2;
    int yplotCenterY = plotAreaMaxY - vpad - plotHeight/2;

    int npoints = points.size();
    int nregions = regions.size();

    //drawRegions(0,4, (int)w-1, regionAreaHeight, points, regions);

    g.blendMode(ADD);

    //g.rect(0, vpad, g.width-1, g.height/2 - vpad);
    //g.rect(0, g.height/2+vpad, g.width-1, g.height/2 - vpad*2);
    //g.line(0, g.height/2, g.width, g.height/2);

    g.noFill();

    g.strokeWeight(1);

    // Image border
    // g.stroke(0, 255,0);
    // g.rect(0, 0, g.width-1, g.height-1);

    // Regions area lower border
    // g.stroke(255, 255, 255, 32);
    // g.line(0, regionAreaHeight-0, g.width-1, regionAreaHeight-0);

    // Plot area vertical center
    g.stroke(255, 255, 255, 32);
    // g.line(0, plotAreaCenterY, g.width-1, plotAreaCenterY);

    // Top border
    g.line(x, y, g.width-1, y);

    // Plot area min max
    g.line(x, plotAreaMinY, w-1, plotAreaMinY);
    g.line(x, plotAreaMaxY, w-1, plotAreaMaxY);

    // Plot min max
    g.stroke(255, 255, 255, 16);
    g.line(x, plotAreaMinY + vpad, w, plotAreaMinY+vpad);
    g.line(x, plotAreaCenterY - vpad, w, plotAreaCenterY - vpad);
    g.line(x, plotAreaMaxY - vpad, w, plotAreaMaxY-vpad);
    g.line(x, plotAreaCenterY + vpad, w, plotAreaCenterY + vpad);

    // Plot center lines
    // g.stroke(255, 255, 0);
    // g.line(0, xplotCenterY, g.width-1, xplotCenterY);
    // g.line(0, yplotCenterY, g.width-1, yplotCenterY);
    
    //g.strokeWeight(1);
    //g.stroke(255,255,255,32);

    float viewOffset = (float)selectedPointIndex / points.size() * w;

    // Path region background highlight
    g.noStroke();
    g.fill(255,255,255,8);
    for (int ridx=0; ridx < nregions; ridx++) {
      Region region = regions.get(ridx);
      if (region.type == Region.PATH || region.type == Region.BLANK) {
        float x1 = x + w * getScreenXForIndex(region.startIndex, cursorNormalized,
                                              zoom, npoints);
        float x2 = x + w * getScreenXForIndex(region.endIndex, cursorNormalized,
                                              zoom, npoints);
        float xw = x2 - x1;
        if (region.selected) {
          if (region.type == Region.PATH) {
            g.fill(128, 128, 255, 32);
          }
          else {
            g.fill(128, 128, 255, 24);
          }
        }
        else {
          g.fill(255,255,255,8);
        }
        if (region.type == Region.PATH || region.selected) {
          g.rect(x1, plotAreaMinY+vpad, xw, plotHeight);
          g.rect(x1, plotAreaMinY+plotHeight+vpad*3, xw, plotHeight);
        }
      }
    }
    g.noFill();
    
    g.blendMode(REPLACE);

    float minxn = getViewportMinX(cursorNormalized, zoom);
    float maxxn = getViewportMaxX(cursorNormalized, zoom);
    int minIdx = (int)(minxn * (points.size()-0.0));
    int maxIdx = (int)(maxxn * (points.size()-0.0));
    int npointsInView = 1 + maxIdx - minIdx;

    if (shapeRender) {
      // X galvo plot (shape)
      g.beginShape(POINTS);
      g.strokeWeight(1+zoom/4);
      g.stroke(160);
      for (int i = 0; i < npointsInView; i++) {
        int pidx = min(npoints-1, minIdx + i);
        Point p = points.get(pidx);
        if (p.isBlank()) {
          float xpos = x + w * getScreenXForIndex(pidx, cursorNormalized, zoom, npoints);
          float ypos = xplotCenterY + p.x * plotHeight/2;
          g.vertex(xpos, ypos);
        }
      }
      g.endShape();
      g.beginShape(POINTS);
      g.strokeWeight(5+zoom/4);
      for (int i = 0; i < npointsInView; i++) {
        int pidx = min(npoints-1, minIdx + i);
        Point p = points.get(pidx);
        if (!p.isBlank()) {
          float xpos = x + w * getScreenXForIndex(pidx, cursorNormalized, zoom, npoints);
          float ypos = xplotCenterY + p.x * plotHeight/2;
          g.stroke(p.r, p.g, p.b, 255);
          g.vertex(xpos, ypos);
        }
      }
      g.endShape();

      // Y galvo plot (shape)
      g.beginShape(POINTS);
      g.strokeWeight(1+zoom/4);
      g.stroke(160);
      for (int i = 0; i < npointsInView; i++) {
        int pidx = min(npoints-1, minIdx + i);
        Point p = points.get(pidx);
        if (p.isBlank()) {
          float xpos = x + w * getScreenXForIndex(pidx, cursorNormalized, zoom, npoints);
          float ypos = yplotCenterY + p.y * plotHeight/2;
          g.vertex(xpos, ypos);
        }
      }
      g.endShape();
      g.beginShape(POINTS);
      g.strokeWeight(5+zoom/4);
      for (int i = 0; i < npointsInView; i++) {
        int pidx = min(npoints-1, minIdx + i);
        Point p = points.get(pidx);
        if (!p.isBlank()) {
          float xpos = x + w * getScreenXForIndex(pidx, cursorNormalized, zoom, npoints);
          float ypos = yplotCenterY + p.y * plotHeight/2;
          g.stroke(p.r, p.g, p.b, 255);
          g.vertex(xpos, ypos);
        }
      }
      g.endShape();
    }
    else {
      // X galvo plot (points)
      for (int i = 0; i < npointsInView; i++) {
        int pidx = min(npoints-1, minIdx + i);
        Point p = points.get(pidx);
        float xpos = x + i * w / npointsInView;
        float ypos = xplotCenterY + p.x * plotHeight/2;
        if (p.isBlank()) {
          g.strokeWeight(1+zoom/4);
          g.stroke(160);
        }
        else {
          g.strokeWeight(5+zoom/4);
          g.stroke(p.r, p.g, p.b, 255);
        }
        g.point(xpos, ypos);
      }
      
      // Y galvo plot (points)
      for (int i = 0; i < npointsInView; i++) {
        int pidx = min(npoints-1, minIdx + i);
        Point p = points.get(pidx);
        float xpos = x + i * w / npointsInView;
        float ypos = yplotCenterY + p.y * plotHeight/2;
        if (p.isBlank()) {
          g.strokeWeight(1+zoom/4);
          g.stroke(160);
        }
        else {
          g.strokeWeight(5+zoom/4);
          g.stroke(p.r, p.g, p.b, 255);
        }
        g.point(xpos, ypos);
      }
  
    }
  }

  public void drawZoomIndicator(int x, int y, int w, int h, int npoints) {
    float c = 1.0 - 2.0 * ((float)selectedPointIndex / npoints);

    float lineStartX = x + w/2 - w/2/zoom;
    float lineEndX   = x + w/2 + w/2/zoom;
    float len = lineEndX - lineStartX;
    float offs = (w - len)/2 *c;
    lineStartX -= offs;
    lineEndX -= offs;
    float lineY = y + h - infoAreaHeight / 2;
    
    g.stroke(32,32,255);
    g.strokeWeight(5);
    g.line(lineStartX, lineY, lineEndX, lineY);
  }


  public void drawCursor(int x, int y, int w, int h, int npoints) {
    if (selectedPointIndex >= 0 && selectedPointIndex < npoints) {
      float cursorScaled = (float)cursorNormalized * ((float)scaledPlotWidth/w);
      int cx = fitToWidth? (int)(x+w*cursorNormalized): (int)(x+w*cursorScaled);
      g.stroke(192);
      g.strokeWeight(1);
      g.line(cx, y+vpad+2, cx, h - vpad*2-2);

      g.fill(255);
      g.textSize(22);
      g.text(selectedPointIndex, cx, g.height - vpad+7);
    }
  }


  public void draw(int x, int y, int w, int h) {
    image(g, x, y, w, h);
  }


  public void resizeCtx(int w, int h) {
    ctxWidth = w;
    ctxHeight = h;
    ctxResizeLock = true;
    g = createGraphics(w, h, P2D);
    ctxResizeLock = false;
  }
}
