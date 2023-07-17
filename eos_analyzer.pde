import oscP5.*;
import netP5.*;
import java.util.zip.Inflater;
import java.util.zip.DataFormatException;


OscP5 oscP5;
OscProperties oscProps;

Boolean showBlankLines = true;
int pathGraphHeight = 512;
Boolean galvoPlotFitToWidth = false;

float intensity = 1.0;
PGraphics projCtx;
PGraphics galvoPathCtx;
Boolean frameDirty = true;
ArrayList<Point> points;
Point prevFrameFinalPoint;

//int plotWidth = 512;
//int plotHeight = 216;
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

void setup() {
  size(2220, 2074, P3D);
  surface.setResizable(true);
  surface.setLocation(0, 40);
  textSize(24);
  frameRate(480);
  projCtx = createGraphics(1024, 1024, P2D);
  galvoPathCtx = createGraphics(width/2, pathGraphHeight, P2D);
  //galvoPathCtx = createGraphics(width/2, pathGraphHeight/2, P2D);
  oscProps = new OscProperties();
  oscProps.setDatagramSize(65535);
  oscProps.setListeningPort(12000);
  oscP5 = new OscP5(this, oscProps);

  noLoop();

  fpsHistory     = new HistoryPlot("FPS",      historyLength, 0.0, 240.0,  5, "int", "");
  pointsHistory  = new HistoryPlot("Points",   historyLength, 0.0, 4096.0, 1, "int", "");
  ppsHistory     = new HistoryPlot("PPS",      historyLength, 0.0, 360.0,  5, "int", "k");
  pathsHistory   = new HistoryPlot("Paths",    historyLength, 0.0, 50.0,  1, "int", "");
  distHistory    = new HistoryPlot("Dist",     historyLength, 0.0, 120.0,  5, "float", "k");
  maxdistHistory = new HistoryPlot("Dmax",     historyLength, 0.0, 5800.0, 1, "int", "");
  bcRatioHistory = new HistoryPlot("C/D",      historyLength, 0.0, 1.0,    5, "float", "");
  bitrateHistory = new HistoryPlot("Net",      historyLength, 0.0, 10.0, 5, "float", "Mbps");
  
  // For caclulation only, dont add to layout:
  smoothPoints = new HistoryPlot("SmoothPoints", historyLength, 0, 4096, 20, "","");

  plots.add(fpsHistory);
  plots.add(pointsHistory);
  plots.add(ppsHistory);
  plots.add(pathsHistory);
  plots.add(distHistory);
  plots.add(maxdistHistory);
  plots.add(bcRatioHistory);
  plots.add(bitrateHistory);
}


void draw() {
  if (points == null || points.size() == 0) {
    return;
  }
  ArrayList<Point> lpoints = new ArrayList(points);

  background(8);
  camera();

  if (frameDirty) {
    renderProjectionImg(lpoints, projCtx);
    renderGalvoPathImg(lpoints, galvoPathCtx);
    frameDirty = false;
  }

  int imagedim = min(width, height-pathGraphHeight);
  image(projCtx, 20, 20, imagedim-40, imagedim-40);
  
  noStroke();
  fill(0);
  int galvoPlotWidth = width; //width-plotWidth-plotMargin*2;
  rect(0, height - pathGraphHeight, galvoPlotWidth, pathGraphHeight);
  if (galvoPlotFitToWidth) {
    image(galvoPathCtx, 0, height-pathGraphHeight, width, pathGraphHeight);
  }
  else {
    image(galvoPathCtx, 0, height-pathGraphHeight,
        min((int)((float)smoothPoints.expMovingAvg/4096.0*galvoPlotWidth*2), galvoPlotWidth),
        pathGraphHeight);
  }
  float fps = frameRate;
  fpsHistory.addValue(fps);

  int npoints = lpoints.size();
  pointsHistory.addValue(lpoints.size());
  smoothPoints.addValue(lpoints.size());

  float pps = npoints * fps;
  //float kpps = npoints * fps / 1000;
  ppsHistory.addValue(pps / 1000);

  float[] pathinfo = getPathStats(lpoints);
  float totalDist = pathinfo[0]*2047 + pathinfo[1]*2047;
  float bcRatio = 0.0;
  if (totalDist > 0.0) {
    bcRatio = pathinfo[1]*2047 / totalDist;
  }
  float maxDist = pathinfo[2] * 2047;
  //println(maxDist);
  distHistory.addValue(totalDist/1000);
  maxdistHistory.addValue(maxDist);
  bcRatioHistory.addValue(bcRatio);
  
  // float bitrate = pps * (7 * 8) / (1024*1024);  
  // bitrateHistory.addValue(bitrate);
  //plotHeight = (height - pathGraphHeight) / (1+plots.size()); // - plotMargin*7;
  //drawPlots(width-plotWidth-plotMargin, 0, plotWidth, plotHeight, plotMargin);

  int plotRows, plotCols;
  if (width-imagedim < width/2) {
    plotRows = plots.size();
    plotCols = 1;
  }
  else {
    plotRows = 4;
    plotCols = 2;  
  }
  drawPlotsLayout(imagedim, 0, //plotMargin/2,
                  width-imagedim, height-pathGraphHeight-plotMargin*2,
                  plotRows, plotCols);
  
  prevFrameFinalPoint = lpoints.get(npoints-1);
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

void addPathInfo(ArrayList<Point> lpoints) {
  int npoints = lpoints.size();
  int npaths = 0;
  Point pPrev, p, pNext;
  for(int i=0; i < npoints; i++) {
    PointInfo info = new PointInfo();
    pPrev = (i > 0)?         lpoints.get(i-1) : null;
    pNext = (i < npoints-1)? lpoints.get(i+1) : null;
    p = lpoints.get(i);

    info.isBlank = p.isBlank();

    // frameStart
    if (i == 0) {
      info.frameStart = true;
    }
    if (p.isBlank()) {
      // blank dwell
      if (pPrev != null && !p.identical(pPrev)
          && pNext != null && p.identical(pNext)) {
        info.blankDwell = true;
      }

      // travel
      if (pPrev != null && !p.posEqual(pPrev)) {
        info.travelStart = true;
      }
    }
    else {
      // dwell start
      if (pPrev != null && p.identical(pPrev)
       && pNext != null && pNext.identical(p)) {
        info.dwell = true;
      }
      // path begin
      if (pPrev != null && pPrev.isBlank()) {
        info.pathBegin = true;
        npaths++;
      }
      // path end
      if (pNext != null && pNext.isBlank()) {
        info.pathEnd = true;
      }

    }
    // frame end
    if (i == npoints-1) {
      info.frameEnd = true;
    }
    p.info = info;
    //println(info.toString());
  }
  pathsHistory.addValue(npaths);
}

void mouseClicked() {
  if (mouseY > height - pathGraphHeight) {
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
  //g.rect(0, 0, g.width-1, g.height-1);
  g.rect(0, vmargin, g.width-1, g.height/2 - vmargin);
  g.rect(0, g.height/2+vmargin, g.width-1, g.height/2 - vmargin*2);

  g.line(0, g.height/2, g.width, g.height/2);

  // Info markers
  addPathInfo(ppoints);
  g.beginShape(LINES);
  g.strokeWeight(1);
  for (int i = 0; i < npoints; i++) {
    // int pidx = (int)((i / w) * npoints);    
    Point p = (Point)ppoints.get(i);
    float x = (float)i / npoints * w;
    float x2 = (float)(i+1) / npoints * w;
    if(p.info != null) {  
      if (!p.info.isBlank) {
        g.stroke(255, 255, 255, 32);
        g.vertex(x, g.height-vmargin+3);
        g.vertex(x, g.height-2);
      }
     
      if (p.info.dwell) {
        g.stroke(p.r, p.g, p.b, 160);
        g.vertex(x, 2);
        g.vertex(x, vmargin/2-1);
        // g.vertex(x, vmargin/2+1);
        // g.vertex(x, vmargin-2);
        continue;
      }
      if (p.info.pathBegin) {
        //g.stroke(255, 16, 16, 96);
        //g.stroke(255, 162, 162, 64);
        g.stroke(255, 255, 255, 32);
        //g.stroke(64, 64, 255, 128);
        g.vertex(x, vmargin+1);
        g.vertex(x, g.height);
        continue;
      }
      if (p.info.pathEnd) {
        //g.stroke(255, 16, 16, 96);
        //g.stroke(255, 162, 162, 64);
        g.stroke(255, 255, 255, 32);
        //g.stroke(64, 64, 255, 128);
        g.vertex(x, vmargin+1);
        g.vertex(x, g.height);
        continue;
      }
      if (!p.info.dwell && !p.info.isBlank) {
        g.stroke(p.r, p.g, p.b, 64);
        //g.vertex(x, 0);
        //g.vertex(x, vmargin-1);
        g.vertex(x, vmargin/2+4);
        g.vertex(x, vmargin/2+5);
        // g.vertex(x, vmargin/2+1);
        // g.vertex(x, vmargin-3);
        continue;
      }
      // if (p.info.travelStart) {
      //   g.stroke(255, 64, 64, 64);
      //   g.vertex(x, 0);
      //   g.vertex(x, vmargin-1);
      // }
      if (p.info.isBlank) {
        // g.stroke(255, 255, 255, 16);
        // //g.stroke(255, 16, 16, 240);
        // g.vertex(x, g.height-vmargin+3);
        // g.vertex(x, g.height-2);
        
        g.stroke(255, 255, 255, 64);
        g.vertex(x, vmargin/2+4);
        g.vertex(x, vmargin/2+5);
        continue;
      }

    }
  }
  g.endShape();


  g.beginShape();
  for (int i = 0; i < w; i++) {
    int pidx = (int)((i / w) * npoints);    
    Point p = (Point)ppoints.get(pidx);
    float xpos = vmargin + 1 + 0.5 * (p.x + 1) * (g.height/2 - vmargin*2);
    //float xpos = vmargin + 0.5 * (p.x + 1) * (g.height/2 - vmargin*2);
    if (p.isBlank()) {
      g.strokeWeight(1);
      //g.stroke(255, 192, 192, 64);
      g.stroke(255, 255, 255, 64);
      //g.stroke(64, 64, 64);
    }
    else {
      g.strokeWeight(2);
      g.stroke(p.r, p.g, p.b);
    }
    g.vertex(i, xpos);
  }
  g.endShape();
  
  g.beginShape();
  for (int i = 0; i < w; i++) {
    int pidx = (int)((i / w) * npoints);    
    Point p = (Point)ppoints.get(pidx);
    float ypos = g.height/2 + vmargin + 1 + 0.5 * (p.y + 1) * (g.height/2 - vmargin*2);
    if (p.isBlank()) {
      g.strokeWeight(1);
      //g.stroke(255, 192, 192, 64);
      g.stroke(255, 255, 255, 64);
      //g.stroke(64, 64, 64);
    }
    else {
      g.strokeWeight(2);
      g.stroke(p.r, p.g, p.b);
    }
    g.vertex(i, ypos);
  }
  g.endShape();
  
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
      //println("color", p1.r, p1.g, p1.b);
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

  // highlight first point in frame
  Point p1 = (Point)ppoints.get(0);
  g.stroke(0, 255, 0);
  g.ellipse(p1.x*-s, p1.y*s, 25, 25);

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
