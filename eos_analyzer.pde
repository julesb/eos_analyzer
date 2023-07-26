import oscP5.*;
import netP5.*;
import java.util.zip.Inflater;
import java.util.zip.DataFormatException;

/*
  TODO:

  - Highlight points where the distance to the next point exceeds
    normal "safe" distance eg. 64su. Possibly in the regions view.

  - Draw a little arrow to show travel direction on the frame start
    indicator in projection view.

  - Add a new layout panel to contain point info panel, app FPS,
    frame counter, receive indicator etc.
    - Receiving / Snapshot mode indicator.
    - Frame counter with "click to reset" action.
    - Display app FPS, distinct from network FPS.

  - Create a visualization for each point of the direction change angle
    to reach the next point. Map angle (0 - 180deg) => Color intensity.

  - RENDERING REWORK:
|   - On window resize, we should resize all PGraphics contexts to
|     be the actual displayed size so we get pixel perfect renders.
|
|   - Rework galvo plot non-fit-to-width view, simply rescaling the
|     image is a dirty hack.
|
|   - Galvo plot pan and zoom.


*/

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

GalvoPlot galvoPlot;
final Rect galvoPlotCtxRect = new Rect(0, 0, 3840, 768); // only w and h are used
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


int widthPrev, heightPrev;

void windowResized() {
  println("RESIZE: ", width, height);
  updateScreenRects();
  galvoPlot.resizeCtx(galvoPlotScreenRect.w, galvoPlotScreenRect.h);
}


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
  size(2220, 2074, P2D);
  surface.setResizable(true);
  surface.setLocation(0, 40);
  textSize(24);
  frameRate(480);

  projectionCtx = createGraphics(projectionCtxRect.w, projectionCtxRect.h, P2D);
  galvoPlot = new GalvoPlot(galvoPlotCtxRect.w, galvoPlotCtxRect.h);
  
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
  
  if (!galvoPlotFitToWidth) {
    galvoPlotScreenRect.w = width;
    int desiredwidth = (int)(smoothPoints.expMovingAvg/4096.0*galvoPlotScreenRect.w*2);
    int widthnew = min(desiredwidth, width);
    galvoPlotScreenRect.set(0, height-galvoPlotHeight, widthnew, galvoPlotHeight);
  }
  
  ArrayList<Point> lpoints = new ArrayList(points);
  ArrayList<Region> lregions = analyzer.getRegions(lpoints);
  
  int mx = mouseX, my = mouseY; 
  updateCursors(mx, my, lpoints);
  ArrayList<Region> regionsAtSelection = analyzer.selectAndGetRegionsAtIndex(selectedPointIndex);


  // Select points in selected region
  for (int ridx = 0; ridx < regionsAtSelection.size(); ridx++) {
    Region r = regionsAtSelection.get(ridx);
    for(int pidx=r.startIndex; pidx <= r.endIndex; pidx++) {
      lpoints.get(pidx).selected = true;
    }
  }


  background(8);
  //camera();


  if (frameDirty || snapshotModeEnabled) {
    renderProjectionImg(lpoints, projectionCtx);
    galvoPlot.render(lpoints, lregions, selectedPointIndex);
    frameDirty = false;
  }

  // Draw projection image
  image(projectionCtx,
        projScreenRect.x,
        projScreenRect.y,
        projScreenRect.w,
        projScreenRect.h);
  
  // Draw black background for galvo plot area
  noStroke();
  fill(0);
  rect(galvoPlotScreenRect.x,
       galvoPlotScreenRect.y,
       width,
       galvoPlotScreenRect.h);
    
  // Draw galvo plot image
  galvoPlot.draw(galvoPlotScreenRect.x,
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
  

  if (selectedPoint != null && selectedPointIndex >= 0) {
    int panelx = (int)(projScreenRect.x + projScreenRect.w/2
               + selectedPoint.x*-projScreenRect.w/2);
    int panely = (int)(projScreenRect.y + projScreenRect.w/2
               + selectedPoint.y*projScreenRect.h/2);

    panelx = min(panelx, projScreenRect.x+projScreenRect.w-340);
    panely = max(panely, projScreenRect.y+240);

    //ellipse(selectedPoint.x*-width/2, selectedPoint.y*width/2, 25, 25);
    drawSelectionInfoPanel(panelx, panely, 280, 180, lpoints, regionsAtSelection);
  }
  // String infoText = getSelectionInfoText(regionsAtSelection);
  // fill(255);
  // noStroke();
  // textSize(30);
  // text(infoText, padding*2, padding*2);

  prevFrameFinalPoint = lpoints.get(npoints-1);
}


void drawSelectionInfoPanel(int x, int y, int w, int h, ArrayList<Point> points, ArrayList<Region> regionsAtSelection) {
  int rowHeight = 28;
  int cursorOffset = 50;
  int colorw = 100;
  int colorh = 100;
  int margin = 10;
  
  int xpos = x + cursorOffset;
  int ypos = y - h - cursorOffset;
  int textOriginX = xpos + colorw + 6;
  int textOriginY = ypos + margin + 18;
  Boolean isPath = false;
  Boolean isBlank = false;
  Boolean isDwell = false;
  int pathLength = 0;
  int blankLength = 0;
  int dwellLength = 0;

  int textx = textOriginX, texty = textOriginY;

  textSize(24);
  stroke(255,255,255,64);
  fill(0,0,0, 240);
  strokeWeight(1);
  rect(xpos, ypos, w, h);

  if (selectedPoint == null || selectedPointIndex < 0) {
    fill(255,128,128);
    text("NO SELECTION", textOriginX, textOriginY);
    return;
  }
  
  for (int i=0; i<regionsAtSelection.size(); i++) {
    Region r = regionsAtSelection.get(i);
    if (r.type == Region.PATH) {
      isPath = true;
      pathLength = r.pointCount;
    }
    if (r.type == Region.BLANK) {
      isBlank = true;
      blankLength = r.pointCount;
    }
    if (r.type == Region.DWELL){
      isDwell = true;
      dwellLength = r.pointCount;
    }
  }

  // Color patch
  fill(selectedPoint.r, selectedPoint.g, selectedPoint.b);
  if (isBlank) {
    stroke(255,255,255,64);
    rect(xpos+margin, ypos+margin, colorw-2*margin, colorh-2*margin);
    fill(255,255,255,64);
    text ("BLANK", xpos+margin+6, ypos+margin+46);
  }
  else {
    noStroke();
    rect(xpos+margin, ypos+margin, colorw-2*margin, colorh-2*margin);
  }

  int rowCount = 0;
  
  noStroke();
  fill(255,255,255,192);

  String posStr = String.format("pos: %5d, %5d",
    (int)(selectedPoint.x*-2047), (int)(selectedPoint.y*-2047));
  texty = textOriginY + rowCount++ * rowHeight;
  text(posStr, textx, texty);
  
  String colorStr = String.format("color: %02X%02X%02X",
      (int)selectedPoint.r, (int)selectedPoint.g, (int)selectedPoint.b);
  texty = textOriginY + rowCount++ * rowHeight;
  text(colorStr, textx, texty);

  String indexStr = String.format("index: %d", selectedPointIndex);
  texty = textOriginY + rowCount++ * rowHeight;
  text(indexStr, textx, texty);

  // Separator
  stroke(255,255,255,64);
  strokeWeight(1);
  line(xpos, ypos + colorh, xpos+w-1, ypos+colorh);

  textOriginY = ypos + colorh + margin*3;
  rowCount = 0;
  
  int buttonWidth = (w-margin*4) / 3;
  int buttonHeight = 60;
  stroke(255,255,255,64);
  noFill();
  
  if (isPath || isDwell) {
    stroke(255,255,255,192);
    noFill();
    rect(xpos+margin*1, ypos+colorh+margin, buttonWidth, buttonHeight);
    fill(255,255,255,240);
  }
  else {
    stroke(255,255,255,64);
    noFill();
    rect(xpos+margin*1, ypos+colorh+margin, buttonWidth, buttonHeight);
    fill(255,255,255,64);
  }
  textx = xpos+margin*2;
  texty = textOriginY+3; // + rowCount * rowHeight;
  text("draw", textx, texty);
  String drawStr = (isPath || isDwell)? String.format("%d", pathLength) : "";
  texty += rowHeight;
  text(drawStr, textx, texty);

  if (isBlank && !isDwell) {
    stroke(255,255,255,192);
    noFill();
    rect(xpos+margin*2+buttonWidth, ypos+colorh+margin, buttonWidth, buttonHeight);
    fill(255,255,255,240);
  }
  else {
    stroke(255,255,255,64);
    noFill();
    rect(xpos+margin*2+buttonWidth, ypos+colorh+margin, buttonWidth, buttonHeight);
    fill(255,255,255,64);
  }
  textx = xpos+margin*3+buttonWidth*1;
  texty = textOriginY+3; // + rowCount * rowHeight;
  text("blank", textx, texty);
  String blankStr = (isBlank && !isDwell)? String.format("%d", blankLength) : "";
  texty += rowHeight;
  text(blankStr, textx, texty);
  
  if (isDwell) {
    stroke(255,255,255,192);
    noFill();
    rect(xpos+margin*3+buttonWidth*2, ypos+colorh+margin, buttonWidth, buttonHeight);
    fill(255,255,255,240);
  }
  else {
    stroke(255,255,255,64);
    noFill();
    rect(xpos+margin*3+buttonWidth*2, ypos+colorh+margin, buttonWidth, buttonHeight);
    fill(255,255,255,64);
  }
  textx = xpos+margin*4+buttonWidth*2;
  texty = textOriginY+3; // + rowCount * rowHeight;
  text("dwell", textx, texty);
  String dwellStr = (isDwell)? String.format("%d", dwellLength) : "";
  texty += rowHeight;
  text(dwellStr, textx, texty);
}


int findClosestPointIndex(Point target, ArrayList<Point> points) {
  int npoints = points.size();
  float minDist = 999999.0;
  int minIndex = -1;
  //Point target = new Point(px, py);

  for(int i=0; i< npoints; i++) {
    Point p = points.get(i);
    float d = target.distSqr(p);
    if (d < minDist) {
      minDist = d;
      minIndex = i;
    }
  }
  return minIndex;
}


String getSelectionInfoText(ArrayList<Region> regionsAtSelection) {
  if (selectedPoint == null || selectedPointIndex < 0) {
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
                       * points.size();
                       //* pointsHistory.expMovingAvg;

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
    Point cursorPoint = new Point(projCursorX / s * -1.0, projCursorY / s);
    int closestIndex = findClosestPointIndex(cursorPoint, points);
    if (closestIndex > -1 && cursorPoint.dist(points.get(closestIndex)) < 0.25) {
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

    // include the distance from the final point in the previous frame to the
    // first point in the current frame when calculating the max distance 
    // between points in the frame
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
    galvoPlot.fitToWidth = !galvoPlot.fitToWidth;
    updateScreenRects();
  }
  println("galvoPlotFitToWidth: ", galvoPlotFitToWidth);
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
      if (p1.selected) {
        g.strokeWeight(5);
      }
      else {
        g.strokeWeight(3);
      }
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
  public Boolean selected = false;

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



