import oscP5.*;
import netP5.*;
import java.util.zip.Inflater;
import java.util.zip.DataFormatException;


OscP5 oscP5;
OscProperties oscProps;

Boolean showBlankLines = true;
Boolean galvoPlotFitToWidth = false;

int selectedPointIndex = -1;

PGraphics projectionCtx;
final Rect projectionCtxRect = new Rect(0, 0, 1024, 1024);
Rect projScreenRect = new Rect(0, 0, 1024, 1024);
Point projScreenCursor = new Point(0,0);

int galvoPlotHeight = 768;
PGraphics galvoPlotCtx;
final Rect galvoPlotCtxRect = new Rect(0, 0, 4096, 512);
Rect galvoPlotScreenRect = new Rect(0, 0, 1024, galvoPlotHeight);

// the mouse cursor, in galvo plot image space
float galvoPlotCursorX = 0.0;

Boolean frameDirty = true;
ArrayList<Point> points;
Point prevFrameFinalPoint;

int plotMargin = 20;
int historyLength = 512;

HistoryPlot fpsHistory;
HistoryPlot pointsHistory;
HistoryPlot ppsHistory;
HistoryPlot pathsHistory;
HistoryPlot distHistory;
HistoryPlot maxdistHistory;
HistoryPlot bcRatioHistory;
HistoryPlot bitrateHistory;
HistoryPlot smoothPoints;
ArrayList<HistoryPlot> plots = new ArrayList();

FrameAnalyzer analyzer;

int padding = 20;

void updateScreenRects() {
  // Projection
  int imagedim = min(width, height-galvoPlotHeight);
  projScreenRect.set(padding, padding, imagedim-2*padding, imagedim-2*padding);

  // Galvo plot
  int widthnew;
  if (galvoPlotFitToWidth) {
    int desiredwidth = (int)(smoothPoints.expMovingAvg/4096.0*width*1);
    //int desiredwidth = (int)(smoothPoints.expMovingAvg/4096.0*galvoPlotScreenRect.w*1);
    widthnew = min(desiredwidth, width);
  }
  else {
    widthnew = width;
  }
  galvoPlotScreenRect.set(0, height-galvoPlotHeight, widthnew, galvoPlotHeight);

}

void setup() {
  size(2220, 2074, P3D);
  surface.setResizable(true);
  surface.setLocation(0, 40);
  textSize(24);
  frameRate(480);
  updateScreenRects();

  projectionCtx = createGraphics(projectionCtxRect.w, projectionCtxRect.h, P2D);
  galvoPlotCtx = createGraphics(galvoPlotCtxRect.w, galvoPlotCtxRect.h, P2D);
  
  oscProps = new OscProperties();
  oscProps.setDatagramSize(65535);
  oscProps.setListeningPort(12000);
  oscP5 = new OscP5(this, oscProps);

  noLoop();

  analyzer = new FrameAnalyzer();

  fpsHistory     = new HistoryPlot("FPS",      historyLength, 0.0, 240.0,  5, "int", "");
  pointsHistory  = new HistoryPlot("Points",   historyLength, 0.0, 4096.0, 1, "int", "");
  ppsHistory     = new HistoryPlot("PPS",      historyLength, 0.0, 360.0,  5, "int", "k");
  pathsHistory   = new HistoryPlot("Paths",    historyLength, 0.0, 100.0,  1, "int", "");
  distHistory    = new HistoryPlot("Dsum",     historyLength, 0.0, 120.0,  5, "float", "k");
  maxdistHistory = new HistoryPlot("Dmax",     historyLength, 0.0, 5800.0, 1, "int", "");
  bcRatioHistory = new HistoryPlot("C/D",      historyLength, 0.0, 1.0,    5, "float", "");
  bitrateHistory = new HistoryPlot("Net",      historyLength, 0.0, 10.0, 5, "float", "Mbps");
  
  plots.add(fpsHistory);
  plots.add(pointsHistory);
  plots.add(ppsHistory);
  plots.add(pathsHistory);
  plots.add(distHistory);
  plots.add(maxdistHistory);
  plots.add(bcRatioHistory);
  plots.add(bitrateHistory);
  
  // For caclulation only, dont add to layout:
  smoothPoints = new HistoryPlot("SmoothPoints", historyLength, 0, 4096, 20, "","");

}


void draw() {
  if (points == null || points.size() == 0) {
    return;
  }
  ArrayList<Point> lpoints = new ArrayList(points);
  int mx = mouseX, my = mouseY; 
  background(8);
  camera();

  updateScreenRects();
  updateCursors(mx, my, lpoints);

  if (frameDirty) {
    renderProjectionImg(lpoints, projectionCtx);
    renderGalvoPathImg(lpoints, galvoPlotCtx);
    frameDirty = false;
  }

  // Draw projection image
  image(projectionCtx,
        projScreenRect.x,
        projScreenRect.y,
        projScreenRect.w,
        projScreenRect.h);
  
  // Draw black background for galvo plot
  noStroke();
  fill(0);
  rect(galvoPlotScreenRect.x,
       galvoPlotScreenRect.y,
       width,
       galvoPlotScreenRect.h);
    
  // Draw galvo plot image
  image(galvoPlotCtx,
        galvoPlotScreenRect.x,
        galvoPlotScreenRect.y,
        galvoPlotScreenRect.w,
        galvoPlotScreenRect.h);

  checkMouse();

  // Update and draw history plots
  float fps = frameRate;
  fpsHistory.addValue(fps);

  int npoints = lpoints.size();
  pointsHistory.addValue(lpoints.size());
  smoothPoints.addValue(lpoints.size());

  float pps = npoints * fps;
  ppsHistory.addValue(pps / 1000);

  float[] pathinfo = getPathStats(lpoints);
  float totalDist = pathinfo[0]*2047 + pathinfo[1]*2047;
  float bcRatio = 0.0;
  if (totalDist > 0.0) {
    bcRatio = pathinfo[1]*2047 / totalDist;
  }
  float maxDist = pathinfo[2] * 2047;
  distHistory.addValue(totalDist/1000);
  maxdistHistory.addValue(maxDist);
  bcRatioHistory.addValue(bcRatio);

  int plotRows, plotCols;
  if (width-projScreenRect.w < width/2) {
    plotRows = plots.size();
    plotCols = 1;
  }
  else {
    plotRows = 4;
    plotCols = 2;  
  }
  drawPlotsLayout(projScreenRect.w+plotMargin*2, 0, //plotMargin/2,
                  width-projScreenRect.w-plotMargin*2, height-galvoPlotHeight-plotMargin*2,
                  plotRows, plotCols);
  
  prevFrameFinalPoint = lpoints.get(npoints-1);
}

int findClosestPointIndex(float px, float py, ArrayList points) {
  int npoints = points.size();
  float minDist = 999999.0;
  int minIndex = -1;
  Point target = new Point(px, py);

  for(int i=0; i< npoints; i++) {
    Point p = (Point)points.get(i);
    float d = target.distSqr(p);
    if (d < minDist) {
      minDist = d;
      minIndex = i;
    }
  }
  return minIndex;
}

void updateCursors(int mx, int my, ArrayList points) {
  // Update galvo plot cursor
  if (galvoPlotScreenRect.containPoint(mx, my)) {
    galvoPlotCursorX = (float)(mx - galvoPlotScreenRect.x)
                       / galvoPlotScreenRect.w
                       * pointsHistory.expMovingAvg;
    
    selectedPointIndex = (int)galvoPlotCursorX-0;
  }
  else {
    selectedPointIndex = -1;
  }
  // Update projection cursor
  if(projScreenRect.containPoint(mx, my)) {
    float projCursorX = (float)(mx - projScreenRect.x)
                        / projScreenRect.w
                        * projectionCtxRect.w
                        - projectionCtxRect.w/2;
    float projCursorY = (float)(my - projScreenRect.y)
                        / projScreenRect.h
                        * projectionCtxRect.h
                        - projectionCtxRect.h/2;

    projScreenCursor.x = projCursorX; 
    projScreenCursor.y = projCursorY; 

    float s = projectionCtxRect.w / 2;
    int closestIndex = findClosestPointIndex(projCursorX / s * -1.0,
                                             projCursorY / s,
                                             points);
    if (closestIndex > -1) {
      selectedPointIndex = closestIndex;
    }

  }
}


void drawPlotsLayout(int x, int y, int layoutWidth, int layoutHight, int rows, int cols)  {
  int pwidth = (layoutWidth - plotMargin*1*cols) / cols;
  int pheight = (layoutHight - plotMargin*(rows-1)) / rows;
  int nplots = plots.size();
  int i = 0;
  for (int yi = 0; yi < rows; yi++) {
    for (int xi = 0; xi < cols; xi++) {
      int xpos = x + xi * (pwidth + plotMargin);
      int ypos = y+plotMargin + yi * (pheight + plotMargin);
      if (i >= nplots) {
        break;
      }
      HistoryPlot p = plots.get(i);
      p.draw(xpos, ypos, pwidth, pheight);
      i++;
    }
  }
}

void drawPlots(int x, int y, int plotWidth, int plotHeight, int plotMargin) {
  int nplots = plots.size();
  for (int i=0; i < nplots; i++) {
    int xpos = x;
    int ypos = y + plotMargin + i*plotHeight + i*plotMargin;
    HistoryPlot p = plots.get(i);
    p.draw(xpos, ypos, plotWidth, plotHeight);
  }
}


float[] getPathStats(ArrayList<Point> points) {
    float blankDist = 0.0;
    float colorDist = 0.0;
    float maxDist = 0.0;
    float[] dists = new float[3]; 
    int npoints = points.size();

    if (prevFrameFinalPoint != null && npoints > 0) {
      float d = prevFrameFinalPoint.dist(points.get(0));
      if (d > maxDist) {
        maxDist = d;
      }
    }

    for (int i=0; i < npoints-1; i++) {
        Point p1 = points.get(i);
        Point p2 = points.get(i+1);
        float dist = p1.dist(p2);
        if (dist > maxDist) {
          maxDist = dist;
        }
        if (p1.isBlank()) {
            dists[0] += dist;
        }
        else {
          if (dist == 0.0) {
            dists[1] += 1.0/2047.0;
          }
          else {
            dists[1] += dist;
          }
        }
    }
    dists[2] = maxDist;
    return dists;
}

void checkMouse() {
  int mx = mouseX, my = mouseY;

  // if (galvoPlotScreenRect.containPoint(mx, my)) {
  //   stroke(0, 255, 0);
  //   strokeWeight(1);
  //   noFill();
  //   rect(galvoPlotScreenRect.x, galvoPlotScreenRect.y,
  //        galvoPlotScreenRect.w, galvoPlotScreenRect.h);
  // }


  if (selectedPointIndex >= 0) {
    fill(255);
    textSize(24);
    // int cx = (int)(((float)selectedPointIndex / pointsHistory.expMovingAvg)
    int cx = (int)(((float)selectedPointIndex / smoothPoints.expMovingAvg)
             * galvoPlotScreenRect.w);
    text(selectedPointIndex, cx, galvoPlotScreenRect.y+galvoPlotScreenRect.h-8);
  }


  // if (projScreenRect.containPoint(mx, my)) {
  //   stroke(0, 255, 0);
  //   strokeWeight(1);
  //   noFill();
  //   rect(projScreenRect.x, projScreenRect.y,
  //        projScreenRect.w, projScreenRect.h);
  // }
}


void mouseClicked() {
  if (mouseY > height - galvoPlotHeight) {
    galvoPlotFitToWidth = !galvoPlotFitToWidth;
  }
}

void renderGalvoPathImg(ArrayList ppoints, PGraphics g) {
  int vmargin = 20;
  int infoHeight = 50;
  int plotHeight = g.height - infoHeight;
  int npoints = ppoints.size();
  float w = g.width;
  g.beginDraw();
  g.background(0);
  g.blendMode(ADD);
  g.stroke(255, 255, 255, 32);
  g.strokeWeight(1);
  g.noFill();
  g.rect(0, vmargin, g.width-1, g.height/2 - vmargin);
  g.rect(0, g.height/2+vmargin, g.width-1, g.height/2 - vmargin*2);
  //g.line(0, g.height/2, g.width, g.height/2);

  // Regions
  ArrayList<Region> regions = analyzer.getRegions(ppoints);
  int nregions = regions.size();
  int npaths = 0;
  for (int ridx=0; ridx < nregions; ridx++) {
    Region region = regions.get(ridx);
    float x1 = (float)region.startIndex / npoints * w;
    float x2 = (float)region.endIndex / npoints * w;
    float xw = x2 - x1;
    switch(region.type) {
      case Region.BLANK:
        //g.noStroke();
        g.strokeWeight(1);
        g.stroke(255,255,255,128);
        g.fill(0);
        //g.fill(255,0,0,192);
        g.rect(x1, g.height-vmargin/2-4, xw, vmargin/2-2);
        break;
      case Region.PATH:
        npaths++;
        g.strokeWeight(1);
        g.stroke(255,255,255,32);
        g.fill(255,255,255,8);
        g.rect(x1, vmargin+2, xw, g.height/2-vmargin-4);
        g.rect(x1, g.height/2+vmargin+2, xw, g.height/2-vmargin-4);

        g.stroke(0, 0, 0);
        for (int pidx=region.startIndex; pidx <= region.endIndex; pidx++) {
          Point p1 = (Point)ppoints.get(pidx);
          g.fill(p1.r, p1.g, p1.b, 96);
          g.rect((float)pidx/npoints * w+1, vmargin/2+4, xw/region.pointCount, vmargin/2-6);
        }
        break;
      case Region.DWELL:
        int dheight;
        if (((Point)ppoints.get(region.startIndex)).isBlank()) {
          g.stroke(255,255,255,96);
          g.strokeWeight(1);
          dheight = vmargin/2-3;
        }
        else {
          g.noStroke();
          dheight = vmargin/2-2;
        }
        g.fill(region.col[0],region.col[1],region.col[2],192);
        g.rect(x1+1, 2, xw-1, dheight);
        break;
    }
  }
  pathsHistory.addValue(npaths);
  g.noFill();

  // X galvo plot
  g.beginShape();
  for (int i = 0; i < w; i++) {
    int pidx = (int)((i / w) * npoints);    
    Point p = (Point)ppoints.get(pidx);
    float xpos = vmargin + 1 + 0.5 * (p.x + 1) * (g.height/2 - vmargin*2);
    //float xpos = vmargin + 0.5 * (p.x + 1) * (g.height/2 - vmargin*2);
    if (p.isBlank()) {
      g.strokeWeight(1);
      //g.stroke(255, 192, 192, 64);
      g.stroke(255, 255, 255, 96);
      //g.stroke(64, 64, 64);
    }
    else {
      g.strokeWeight(2);
      g.stroke(p.r, p.g, p.b);
    }
    g.vertex(i, xpos);
  }
  g.endShape();
  
  // Y galvo plot
  g.beginShape();
  for (int i = 0; i < w; i++) {
    int pidx = (int)((i / w) * npoints);    
    Point p = (Point)ppoints.get(pidx);
    float ypos = g.height/2 + vmargin + 1 + 0.5 * (p.y + 1) * (g.height/2 - vmargin*2);
    if (p.isBlank()) {
      g.strokeWeight(1);
      //g.stroke(255, 192, 192, 64);
      g.stroke(255, 255, 255, 96);
      //g.stroke(64, 64, 64);
    }
    else {
      g.strokeWeight(2);
      g.stroke(p.r, p.g, p.b);
    }
    g.vertex(i, ypos);
  }
  g.endShape();
  
  // Highlight the selected point
  if (selectedPointIndex >= 0 && selectedPointIndex < npoints-1) {
    int cx = (int)(((float)selectedPointIndex / npoints) * w);
    Point p1 = (Point)ppoints.get(selectedPointIndex);
    g.stroke(192);
    g.strokeWeight(2);
    g.line(cx, vmargin+2, cx, galvoPlotCtxRect.h-vmargin-2);
    //g.line(p1.x*-s, p1.y*s, p2.x*-s, p2.y*s );
    //g.ellipse(p1.x*-s, p1.y*s, 25, 25);

    // g.fill(255);
    // g.textSize(36);
    // g.text(selectedPointIndex, cx, g.height-vmargin+2);
  }
  g.endDraw();
}


void renderGalvoPathCombinedImg(ArrayList ppoints, PGraphics g) {
  int npoints = ppoints.size();
  float w = g.width;
  g.beginDraw();
  g.background(0);
  g.blendMode(ADD);
  g.noFill();
  g.stroke(255, 255, 255, 64);
  g.strokeWeight(1);
  
  g.rect(0, 0, g.width-1, g.height-1);
  g.strokeWeight(2);
  
  g.beginShape(POINTS);
  for (int i = 0; i < w; i++) {
    int pidx = (int)((i / w) * npoints);    
    Point p = (Point)ppoints.get(pidx);
    float xpos = 0.5 * (p.x + 1) * g.height;
    float ypos = 0.5 * (p.y + 1) * g.height;
    
    g.stroke(10, 255, 10);
    g.vertex(i, xpos);
    g.stroke(255, 255, 10);
    g.vertex(i, ypos);
  }
  g.endShape();
  g.endDraw();
}


void renderProjectionImg(ArrayList ppoints, PGraphics g) {
  int npoints = ppoints.size();
  float s = g.width / 2.0;
  g.beginDraw();
  g.background(0);
  g.blendMode(ADD);
  g.noFill();
  g.pushMatrix();
  g.translate(g.width/2, g.height/2); // assume 2D projection
  
  g.stroke(255, 255, 255, 32);
  g.strokeWeight(1);
  g.square(-g.height/2, -g.height/2, g.height-1);
  
  g.beginShape(LINES);
  for (int i = 0; i < npoints; i++) {
    int pidx1 = i;
    int pidx2 = (i+1) % npoints;
    Point p1 = (Point)ppoints.get(pidx1);
    Point p2 = (Point)ppoints.get(pidx2);
    //p1.x *= -1;
    //p2.x *= -1;

    if (p1.isBlank()) {
      if (showBlankLines) {
        g.strokeWeight(1);
        g.stroke(64, 64, 64);
      } else {
        continue;
      }
    } else {
      g.strokeWeight(4);
      g.stroke(p1.r, p1.g, p1.b, 160);
    }
    if (p1.posEqual(p2)) {
      g.vertex(p1.x*-s+1.0, p1.y*s+1.0);
      g.vertex(p2.x*-s, p2.y*s);
    }
    else {
      g.vertex(p1.x*-s, p1.y*s);
      g.vertex(p2.x*-s, p2.y*s);
        
    }
  }
  g.endShape();

  // Highlight the selected point
  if (selectedPointIndex >= 0 && selectedPointIndex < npoints-1) {
    Point p1 = (Point)ppoints.get(selectedPointIndex);
    //Point p2 = (Point)ppoints.get(selectedPointIndex+1);
    if (p1.isBlank()) {
      g.stroke(255,255,255,240);
      g.fill(0,0,0, 192);
    }
    else {
      g.stroke(255,255,255,240);
      g.fill(p1.r, p1.b, p1.b, 192);
    }
    g.strokeWeight(2);
    //g.line(p1.x*-s, p1.y*s, p2.x*-s, p2.y*s );
    g.ellipse(p1.x*-s, p1.y*s, 25, 25);
  }

  // draw cursor
  // g.stroke(255);
  // g.strokeWeight(4);
  // //g.line(p1.x*-s, p1.y*s, p2.x*-s, p2.y*s );
  // g.ellipse(projScreenCursor.x, projScreenCursor.y, 25, 25);
  

  // highlight first point in frame
  Point p1 = (Point)ppoints.get(0);
  g.stroke(0, 255, 0);
  g.fill(0, 255,0);
  g.ellipse(p1.x*-s, p1.y*s, 10, 10);

  g.popMatrix();
  g.endDraw();
}



void oscEvent(OscMessage message) {
  ArrayList<Point> pointList = new ArrayList();
  if (message.checkAddrPattern("/f")) {
    byte[] packedData = message.get(0).bytesValue();

    Inflater decompresser = new Inflater();
    decompresser.setInput(packedData, 0, packedData.length);
    
    float bitrate = (packedData.length * 8 * fpsHistory.expMovingAvg) / (1024*1024);  
    bitrateHistory.addValue(bitrate);

    byte[] result = new byte[packedData.length*7];
    int resultLength = 0;
    try {
      resultLength = decompresser.inflate(result);
    } catch (DataFormatException e) {
      e.printStackTrace();
    }
    decompresser.end();
    
    // [uint16 uint16 uint8 uint8 uint8] = 7 bytes
    int numPoints = resultLength / 7; 
    pointList.clear();

    for (int i = 0; i < numPoints; i++) {
      int offset = i * 7;
      int x = unpackUInt16(result, offset);
      int y = unpackUInt16(result, offset + 2);
      int r = unpackUInt8(result, offset + 4);
      int g = unpackUInt8(result, offset + 5);
      int b = unpackUInt8(result, offset + 6);

      Point point = new Point(x / 32767.5 - 1, y / 32767.5 - 1, r, g, b);
      pointList.add(point);
      //println("["+(i+1)+"/"+numPoints+"]\t"+ point.toString());
    }
    points = pointList;
    frameDirty = true;
    redraw();
  }
}


//void oscEventUncompressed(OscMessage message) {
//  ArrayList<Point> pointList = new ArrayList();
//  if (message.checkAddrPattern("/f")) {
//    byte[] packedData = message.get(0).bytesValue();

//    // [uint16 uint16 uint8 uint8 uint8 ]  = 7 bytes
//    int numPoints = packedData.length / 7; 
//    pointList.clear();

//    for (int i = 0; i < numPoints; i++) {
//      int offset = i * 7;
//      int x = unpackUInt16(packedData, offset);
//      int y = unpackUInt16(packedData, offset + 2);
//      int r = unpackUInt8(packedData, offset + 4);
//      int g = unpackUInt8(packedData, offset + 5);
//      int b = unpackUInt8(packedData, offset + 6);

//      Point point = new Point(x / 32767.5 - 1, y / 32767.5 - 1, r, g, b);
//      pointList.add(point);
//      //println("["+(i+1)+"/"+numPoints+"]\t"+ point.toString());
//    }
//    points = pointList;
//    frameDirty = true;
//    redraw();
//  }
//}


int unpackUInt16(byte[] bytes, int offset) {
  return ((bytes[offset + 1] & 0xFF) << 8) | (bytes[offset] & 0xFF);
}

int unpackUInt8(byte[] bytes, int offset) {
  return bytes[offset] & 0xFF;
}



class Point {
  public float x, y, r, g, b;
  public PointInfo info;

  Point(float _x, float _y, float _r, float _g, float _b) {
    this.x = _x;
    this.y = _y;
    this.r = _r;
    this.g = _g;
    this.b = _b;
  }
  
  Point(float _x, float _y) {
    this.x = _x;
    this.y = _y;
    this.r = 0;
    this.g = 0;
    this.b = 0;
  }
  public Boolean isBlank() {
    float eps = 0.0001;
    //return (this.r < eps && this.g < eps && this.b < eps);
    return (this.r < 1 && this.g < 1 && this.b < 1);
  }

  public String toString() {
    return String.format("[% .4f, % .4f]\t[%.4f, %.4f, %.4f]", 
      x, y, r, g, b);
  }
  public float dist(Point other) {
      Point d = this.sub(other);
      return (float)Math.sqrt(d.x*d.x + d.y*d.y);
  }
  public float distSqr(Point other) {
      Point d = this.sub(other);
      return (float)d.x*d.x + d.y*d.y;
  }
  public Point sub(Point other) {
      return new Point(this.x-other.x, this.y-other.y);
  }  

  public Boolean posEqual(Point p) {
    return (this.x == p.x && this.y == p.y);
  }
  public Boolean colorEqual(Point p) {
    return (this.r == p.r && this.g == p.g && this.b == p.b);
  }
  public Boolean identical(Point p) {
    return this.posEqual(p) && this.colorEqual(p);
  }

}

class Rect {
  int x=0, y=0, w=0, h=0;

  public Rect() {}

  public Rect(int _x, int _y, int _w, int _h) {
    this.x = _x;
    this.y = _y;
    this.w = _w;
    this.h = _h;
  }
  
  public void set(int _x, int _y, int _w, int _h) {
    this.x = _x;
    this.y = _y;
    this.w = _w;
    this.h = _h;
  }

  public Boolean containPoint(float px, float py) {
    return !((px<x) || (px>x+w) || (py<y) || (py>y+h));
  }
}

class PointInfo {
  Boolean frameStart=false;
  Boolean frameEnd=false;
  Boolean blankDwell = false;
  Boolean dwell = false;
  Boolean pathBegin = false;
  Boolean pathEnd = false;
  Boolean travelStart = false;
  Boolean isBlank = false;
  public PointInfo() {

  }
  
  public String toString() {
    return String.format("f0: %s, f1: %s, dwb: %s, dwc: %s, p0: %s, p1: %s, trav: %s",
        frameStart, frameEnd, blankDwell, dwell, pathBegin, pathEnd, travelStart);
  } 
}


// void addPathInfo(ArrayList<Point> lpoints) {
//   int npoints = lpoints.size();
//   int npaths = 0;
//   Point pPrev, p, pNext;
//   for(int i=0; i < npoints; i++) {
//     PointInfo info = new PointInfo();
//     pPrev = (i > 0)?         lpoints.get(i-1) : null;
//     pNext = (i < npoints-1)? lpoints.get(i+1) : null;
//     p = lpoints.get(i);
//
//     info.isBlank = p.isBlank();
//
//     // frameStart
//     if (i == 0) {
//       info.frameStart = true;
//     }
//     if (p.isBlank()) {
//       // blank dwell
//       if (pPrev != null && !p.identical(pPrev)
//           && pNext != null && p.identical(pNext)) {
//         info.blankDwell = true;
//       }
//
//       // travel
//       if (pPrev != null && !p.posEqual(pPrev)) {
//         info.travelStart = true;
//       }
//     }
//     else {
//       // dwell start
//       if (pPrev != null && p.identical(pPrev)
//        && pNext != null && pNext.identical(p)) {
//         info.dwell = true;
//       }
//       // path begin
//       if (pPrev != null && pPrev.isBlank()) {
//         info.pathBegin = true;
//         npaths++;
//       }
//       // path end
//       if (pNext != null && pNext.isBlank()) {
//         info.pathEnd = true;
//       }
//
//     }
//     // frame end
//     if (i == npoints-1) {
//       info.frameEnd = true;
//     }
//     p.info = info;
//     //println(info.toString());
//   }
//   pathsHistory.addValue(npaths);
// }

