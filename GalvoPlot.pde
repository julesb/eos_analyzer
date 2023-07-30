
class GalvoPlot {
  PGraphics g;
  int ctxWidth;
  int ctxHeight;
  Boolean ctxResizeLock = false;
  int regionAreaHeight = 80;
  int infoAreaHeight = 20;
  int vpad= 10;
  int selectedPointIndex = 0;
  Boolean fitToWidth = false;
  int scaledPlotWidth = 1;

  public GalvoPlot(int _ctxWidth, int _ctxHeight) {
    ctxWidth = _ctxWidth;
    ctxHeight = _ctxHeight;
    g = createGraphics(ctxWidth, ctxHeight, P2D);
  }


  public void render(ArrayList<Point> points, ArrayList<Region> regions,
                     int selectedPointIndex, float smoothPointCount) {
    if (ctxResizeLock) {
      println("resize lock");
      return;
    }
    int w = g.width-1;
    if (!fitToWidth) {
      w = min(w, (int)(smoothPointCount/4096.0 * w *2));
    }
    scaledPlotWidth = w;

    this.selectedPointIndex = selectedPointIndex;
    g.beginDraw();
    g.background(0);
    drawRegions(0, vpad, scaledPlotWidth, regionAreaHeight, points, regions);
    drawGalvoPlot(0, 0, scaledPlotWidth, g.height, points, regions);
    g.endDraw();
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

    g.stroke(255,255,255,24);
    for (int i=0; i < 5; i++) {
      int yline = (int) (y + pad + i * channelHeight);
      g.line(0, yline, g.width, yline);
    }
    
    for (int ridx=0; ridx < nregions; ridx++) {
      Region region = regions.get(ridx);
      float x1 = (float)region.startIndex / npoints * w;
      float x2 = (float)(1+region.endIndex) / npoints * w;
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
            g.fill(p1.r, p1.g, p1.b, 160);
            g.rect((float)pidx/npoints * w+1, y1, xw/region.pointCount, channelHeight/2);
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

    // Path region highlight
    g.noStroke();
    g.fill(255,255,255,8);
    for (int ridx=0; ridx < nregions; ridx++) {
      Region region = regions.get(ridx);
      if (region.type == Region.PATH || region.type == Region.BLANK) {
        float x1 = x + (float)region.startIndex / npoints * w;
        float x2 = x + (float)(1+region.endIndex) / npoints * w;
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
    // X galvo plot
    g.beginShape();
    for (int i = 0; i < w; i++) {
      int pidx = (int)(((float)i / w) * npoints);
      Point p = points.get(pidx);
      float ypos = xplotCenterY + p.x * plotHeight/2;
      if (p.isBlank()) {
        g.strokeWeight(1);
        g.stroke(84);
      }
      else {
        g.strokeWeight(5);
        g.stroke(p.r, p.g, p.b, 255);
      }
      g.vertex(x+i, ypos);
    }
    g.endShape();
    
    // Y galvo plot
    g.beginShape();
    for (int i = 0; i < w; i++) {
      int pidx = (int)(((float)i / w) * npoints);
      Point p = points.get(pidx);
      float ypos = yplotCenterY + p.y * plotHeight/2;
      if (p.isBlank()) {
        g.strokeWeight(1);
        g.stroke(96);
      }
      else {
        g.strokeWeight(5);
        g.stroke(p.r, p.g, p.b, 255);
      }
      g.vertex(x+i, ypos);
    }
    g.endShape();
   
    drawCursor(x, y, w, h, npoints);

  }



  public void drawCursor(int x, int y, int w, int h, int npoints) {
    if (selectedPointIndex >= 0 && selectedPointIndex < npoints) {
      int cx = x + (int)(((float)selectedPointIndex / npoints) * w);
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
