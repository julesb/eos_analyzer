import oscP5.*;
import netP5.*;
import java.util.zip.Inflater;
import java.util.zip.DataFormatException;


OscP5 oscP5;
OscProperties oscProps;
Boolean oscEnabled = true;

int targetFrameRate = 480;
Boolean updateFrameRate = false;

// dont modify this directly, use setSnapshotMode()
Boolean snapshotModeEnabled = false;

Boolean showBlankLines = true;

Point selectedPoint;
int selectedPointIndex = -1;

PGraphics projectionCtx;
final Rect projectionCtxRect = new Rect(0, 0, 1024, 1024);
Rect projScreenRect = new Rect(0, 0, 1024, 1024);
Point projScreenCursor = new Point(0,0);

int galvoPlotHeight = 768;

PGraphics galvoPlotCtx;
final Rect galvoPlotCtxRect = new Rect(0, 0, 4096, 512);
Rect galvoPlotScreenRect = new Rect(0, 0, 1024, galvoPlotHeight);
Boolean galvoPlotFitToWidth = true;

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
    widthnew = width;
  }
  else {
    galvoPlotScreenRect.w = width;
    int desiredwidth = (int)(smoothPoints.expMovingAvg/4096.0*galvoPlotScreenRect.w*2);
    widthnew = min(desiredwidth, width);
  }
  galvoPlotScreenRect.set(0, height-galvoPlotHeight, widthnew, galvoPlotHeight);
}

void setup() {
  size(2220, 2074, P3D);
  surface.setResizable(true);
  surface.setLocation(0, 40);
  textSize(24);
  frameRate(480);

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

  updateScreenRects();
}


void draw() {
  if (points == null || points.size() == 0) {
    return;
  }

  // we have to mess with frame rates because we want uncapped
  // when receiving but not in snapshot mode
  if (updateFrameRate) {
    frameRate(targetFrameRate);
    updateFrameRate = false;
  }
  
  // TODO: only do this on resize
  updateScreenRects();

  ArrayList<Point> lpoints = new ArrayList(points);
  ArrayList<Region> lregions = analyzer.getRegions(lpoints);
  
  int mx = mouseX, my = mouseY; 
  updateCursors(mx, my, lpoints);
  ArrayList<Region> regionsAtSelection = analyzer.getRegionsAtIndex(selectedPointIndex);
  background(8);
  //camera();


  if (frameDirty || snapshotModeEnabled) {
    renderProjectionImg(lpoints, projectionCtx);
    renderGalvoPathImg(lpoints, lregions, galvoPlotCtx);
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

  if (snapshotModeEnabled) {
    bitrateHistory.addValue(0);
  }

  int plotRows, plotCols;
  if (width-projScreenRect.w < width/2) {
    plotRows = plots.size();
    plotCols = 1;
  }
  else {
    plotRows = 4;
    plotCols = 2;  
  }
  drawPlotsLayout(projScreenRect.w+plotMargin*2, 1, //plotMargin/2,
                  width-projScreenRect.w-plotMargin*2, height-galvoPlotHeight-plotMargin*2+1,
                  plotRows, plotCols);
  
  String infoText = getSelectionInfoText(regionsAtSelection);
  fill(255);
  noStroke();
  textSize(30);
  text(infoText, padding*2, padding*2);

  prevFrameFinalPoint = lpoints.get(npoints-1);
}


// void drawSelectionInfoPanel(int x, int y, ) {
//   // TODO
// }

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


String getSelectionInfoText(ArrayList<Region> regionsAtSelection) {
  if (selectedPoint == null | selectedPointIndex < 0) {
    return "NO SELECTION";
  }

  String info = String.format("[i: %d] [pos: %d, %d]",
    selectedPointIndex, (int)(selectedPoint.x*2047), (int)(selectedPoint.y*2047));
  for (int i=0; i<regionsAtSelection.size(); i++) {
    Region r = regionsAtSelection.get(i);
    info += String.format("[%s]", r.toString());
  }
  return info;
}


void updateCursors(int mx, int my, ArrayList<Point> points) {
  // Update galvo plot cursor
  if (galvoPlotScreenRect.containPoint(mx, my)) {
    galvoPlotCursorX = (float)(mx - galvoPlotScreenRect.x)
                       / galvoPlotScreenRect.w
                       * pointsHistory.expMovingAvg;

    selectedPointIndex = (int)galvoPlotCursorX;
    if (selectedPointIndex < points.size()) {
      selectedPoint = points.get(selectedPointIndex); 
    }
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
      selectedPoint = points.get(selectedPointIndex);
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
    int cx = (int)(((float)selectedPointIndex / pointsHistory.expMovingAvg)
    //int cx = (int)(((float)selectedPointIndex / smoothPoints.expMovingAvg)
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
  println("galvoPlotFitToWidth: ", galvoPlotFitToWidth);
}


void drawRegions(int x, int y, int w, int h, 
    ArrayList<Point> ppoints, ArrayList<Region> regions, PGraphics g) {
  int npoints = ppoints.size();
  int nregions = regions.size();
  int pad = 1;
  float nchannels = 4;
  float channelPad = 1;
  float channelHeight = (h - (channelPad * (0 + nchannels))) / nchannels;

  int vpad = 10;
  int npaths = 0; 
  float y1;

  final int channelRankDwellBlank = 0;
  final int channelRankDwellColor = 1;
  final int channelRankBlank      = 2;
  final int channelRankPath       = 3;


  g.blendMode(REPLACE);

  g.strokeWeight(1);
  g.noStroke();
  //g.fill(255,255,255,8);
  //g.rect(x, y, w-1, h-1);

  for (int ridx=0; ridx < nregions; ridx++) {
    Region region = regions.get(ridx);
    float x1 = (float)region.startIndex / npoints * w;
    float x2 = (float)region.endIndex / npoints * w;
    float xw = x2 - x1;
    switch(region.type) {
      case Region.BLANK:
        g.stroke(255,255,255,96);
        g.fill(0,0,0, 255);
        y1 = y + pad + channelHeight * channelRankBlank;
        g.rect((int)x1, (int)y1+channelHeight/4, (int)xw, (int)channelHeight/2);
        break;
      case Region.PATH:
        npaths++;
        g.noStroke();
        g.fill(255,255,255,32);
        y1 = y + pad + channelHeight * channelRankPath;
        //g.rect(x1, y1, xw, channelHeight/2);
        for (int pidx=region.startIndex; pidx <= region.endIndex; pidx++) {
          Point p1 = ppoints.get(pidx);
          g.fill(p1.r, p1.g, p1.b, 128);
          g.rect((float)pidx/npoints * w+1, y1, xw/region.pointCount, channelHeight/2);
        }
        break;
      case Region.DWELL:
        if ((ppoints.get(region.startIndex)).isBlank()) {
          g.stroke(255,255,255,128);
          g.fill(0,0,0);
          y1 = y + pad + channelHeight * channelRankDwellBlank + 2;
          g.rect(x1, y1+1, xw, channelHeight-3);
        }
        else {
          g.fill(region.col[0],region.col[1],region.col[2],192);
          g.noStroke();
          y1 = y + pad + channelHeight * channelRankDwellColor + 3;
          g.rect(x1, y1, xw, channelHeight - 3);
        }
        break;
    }
  }

  pathsHistory.addValue(npaths);
}

void renderGalvoPathImg(ArrayList<Point> ppoints, ArrayList<Region> regions, PGraphics g) {
  int vpad = 10;
  int infoAreaHeight = 20;
  int regionAreaHeight = 50;
  int plotAreaMinY = regionAreaHeight+1;
  int plotAreaMaxY = g.height - infoAreaHeight -1;
  int plotAreaCenterY = (plotAreaMinY+plotAreaMaxY)/2;
  int plotAreaHeight = plotAreaMaxY - plotAreaMinY;
  int plotHeight = plotAreaHeight/2 - vpad*2; // height of a single plot

  int xplotCenterY = plotAreaMinY + vpad + plotHeight/2;
  int yplotCenterY = plotAreaMaxY - vpad - plotHeight/2;

  int npoints = ppoints.size();
  int nregions = regions.size();
  float w = g.width;
  int h = g.height;
  g.beginDraw();
  g.background(0);

  drawRegions(0,4, (int)w-1, regionAreaHeight, ppoints, regions, g);

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
  // g.stroke(0, 0, 255);
  // g.line(0, regionAreaHeight-1, g.width-1, regionAreaHeight-1);

  // Plot area vertical center
  g.stroke(255, 255, 255, 32);
  // g.line(0, plotAreaCenterY, g.width-1, plotAreaCenterY);

  // Top border
  g.line(0, 0,g.width-1, 0);

  // Plot area min max
  g.line(0, plotAreaMinY, g.width-1, plotAreaMinY);
  g.line(0, plotAreaMaxY, g.width-1, plotAreaMaxY);

  // Plot min max
  g.line(0, plotAreaMinY + vpad, g.width-1, plotAreaMinY+vpad);
  g.line(0, plotAreaCenterY - vpad, g.width-1, plotAreaCenterY - vpad);
  
  g.line(0, plotAreaMaxY - vpad, g.width-1, plotAreaMaxY-vpad);
  g.line(0, plotAreaCenterY + vpad, g.width-1, plotAreaCenterY + vpad);

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
    if (region.type == Region.PATH) {
      float x1 = (float)region.startIndex / npoints * w;
      float x2 = (float)region.endIndex / npoints * w;
      float xw = x2 - x1;
      g.rect(x1, plotAreaMinY+vpad, xw, plotHeight);
      g.rect(x1, plotAreaMinY+plotHeight+vpad*3, xw, plotHeight);
    }
  }
  g.noFill();

  // X galvo plot
  g.beginShape();
  for (int i = 0; i < w; i++) {
    int pidx = (int)((i / w) * npoints);    
    Point p = ppoints.get(pidx);
    float ypos = xplotCenterY + p.x * plotHeight/2;
    if (p.isBlank()) {
      g.strokeWeight(1);
      g.stroke(255, 255, 255, 96);
    }
    else {
      g.strokeWeight(2);
      g.stroke(p.r, p.g, p.b);
    }
    g.vertex(i, ypos);
  }
  g.endShape();
  
  // Y galvo plot
  g.beginShape();
  for (int i = 0; i < w; i++) {
    int pidx = (int)((i / w) * npoints);    
    Point p = ppoints.get(pidx);
    float ypos = yplotCenterY + p.y * plotHeight/2;
    if (p.isBlank()) {
      g.strokeWeight(1);
      g.stroke(255, 255, 255, 96);
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
    Point p1 = ppoints.get(selectedPointIndex);
    g.stroke(192);
    g.strokeWeight(2);
    g.line(cx, vpad+2, cx, galvoPlotCtxRect.h-vpad-2);
    //g.line(p1.x*-s, p1.y*s, p2.x*-s, p2.y*s );
    //g.ellipse(p1.x*-s, p1.y*s, 25, 25);

    // g.fill(255);
    // g.textSize(36);
    // g.text(selectedPointIndex, cx, g.height-vpad+2);
  }
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
      }
      else {
        continue;
      }
    }
    else {
      g.strokeWeight(4);
      g.stroke(p1.r, p1.g, p1.b, 128);
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

void setSnapshotMode(Boolean enabled) {
  if (enabled) {
    snapshotModeEnabled = true;
    oscEnabled = false;
    targetFrameRate = 60;
    updateFrameRate = true;
    loop();
  }
  else {
    snapshotModeEnabled = false;
    targetFrameRate = 480;
    updateFrameRate = true;
    noLoop();
    oscEnabled = true;
  }
}

void keyTyped() {
  println("KEY:", key);
  switch(key) {
    case ' ':
      setSnapshotMode(!snapshotModeEnabled);
      break;
    case 'b':
      showBlankLines = !showBlankLines;
      break;
  }
}

void keyPressed() {
  switch(key) {
    case 'j':
      galvoPlotHeight -= 20;
      break;
    case 'k':
      galvoPlotHeight += 20;
        break;
  }

}

void oscEvent(OscMessage message) {
  if (!oscEnabled) {
    return;
  }
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

//
// Here lies the graveyard of code
//
// void renderGalvoPathCombinedImg(ArrayList ppoints, PGraphics g) {
//   int npoints = ppoints.size();
//   float w = g.width;
//   g.beginDraw();
//   g.background(0);
//   g.blendMode(ADD);
//   g.noFill();
//   g.stroke(255, 255, 255, 64);
//   g.strokeWeight(1);
//   
//   g.rect(0, 0, g.width-1, g.height-1);
//   g.strokeWeight(2);
//   
//   g.beginShape(POINTS);
//   for (int i = 0; i < w; i++) {
//     int pidx = (int)((i / w) * npoints);    
//     Point p = (Point)ppoints.get(pidx);
//     float xpos = 0.5 * (p.x + 1) * g.height;
//     float ypos = 0.5 * (p.y + 1) * g.height;
//     
//     g.stroke(10, 255, 10);
//     g.vertex(i, xpos);
//     g.stroke(255, 255, 10);
//     g.vertex(i, ypos);
//   }
//   g.endShape();
//   g.endDraw();
// }



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



