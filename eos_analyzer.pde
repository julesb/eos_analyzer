import oscP5.*;
import netP5.*;
import java.util.zip.Inflater;
import java.util.zip.DataFormatException;
import org.apache.commons.math4.transform.*;
import java.nio.IntBuffer;

/*
  TODO:

  - Highlight points where the distance to the next point exceeds
    normal "safe" distance eg. 64su. Possibly in the regions view.

  - Draw a little arrow to show travel direction on the frame start
    indicator in projection view.

  - Create a visualization for each point of the direction change angle
    to reach the next point. Map angle (0 - 180deg) => Color intensity.
    
  - Create a basic layout framework for more dynamic and flexible
    layouts.
    Idea: Introduce a concept of "primary view". At any time any of
      the views could be set as primary. The primary view would
          expand to take up as much space as possible, and the other
          non-primary views would resize to accomodate.

  - Allow history plot to collapse on click. Collapsed view just shows 
    the name and current value but not the history plot.

  - RENDERING REWORK:
    
    - Move projection view into its own class.

    - On window resize, we should resize all PGraphics contexts to
      be the actual displayed size so we get pixel perfect renders.
 
    - Rework history plot drawing to use image region copy scrolling
      instead of rendering each point on every frame - at least check
      if that method is more efficient.
    

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

PGraphics projectionCtx;
final Rect projectionCtxRect = new Rect(0, 0, 1024, 1024);
Rect projScreenRect = new Rect(0, 0, 1024, 1024);
Point projScreenCursor = new Point(0,0);
float projBeamIntensity = 1.0;

int galvoPlotHeight = 360;
// int galvoPlotHeight = 768;
GalvoPlot galvoPlot;
Rect galvoPlotCtxRect;
Rect galvoPlotScreenRect = new Rect(0, 0, 1024, galvoPlotHeight);

int statusPanelWidth = 300;
Rect statusPanelScreenRect; 

int spectrumPlotHeight = 200; // will be recalculated
Rect spectrumScreenRect = new Rect(0,0,1024,1024);

int colorPanelHeight = 200;
Rect colorPanelScreenRect;

Boolean frameDirty = true;
ArrayList<Point> points;
Point prevFrameFinalPoint;

int plotMargin = 20;
int historyLength = 512;

HistoryPlot fpsHistory;
HistoryPlot pointsHistory;
HistoryPlot ppsHistory;
// HistoryPlot pathsHistory;
HistoryPlot distHistory;
HistoryPlot maxdistHistory;
HistoryPlot bcRatioHistory;
HistoryPlot bitrateHistory;
HistoryPlot energyxHistory;
HistoryPlot energyyHistory;
HistoryPlot smoothPoints;
ArrayList<HistoryPlot> plots = new ArrayList();

double smoothPowerX = 0.0;
double smoothPowerY = 0.0;

FrameAnalyzer analyzer;
FrequencyAnalyzer freqAnalyzer;
ColorAnalyzer colorAnalyzer;

color meterColor = color(192/2,238/2,1,255);

int oscFrameCount = 0;

int padding = 20;

int buttonWidth = 200;
int buttonHeight = 40;
Button receiveButton    = new Button("Receive",   0, 0, buttonWidth, buttonHeight);
Button oscframesButton  = new Button("000000", 0, 0, buttonWidth, buttonHeight);
Button renderModeButton = new Button("Shape",     0, 0, buttonWidth, buttonHeight);
Button uncapButton      = new Button("Uncap",     0, 0, buttonWidth, buttonHeight);
Button fitwidthButton   = new Button("Fit",       0, 0, buttonWidth, buttonHeight);

int widthPrev, heightPrev;

color borderColor = color(255,255,255,32);

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
  galvoPlotScreenRect.x = 0;
  galvoPlotScreenRect.y = height - galvoPlotHeight;
  galvoPlotScreenRect.w = width;
  galvoPlotScreenRect.h = galvoPlotHeight;

  statusPanelScreenRect.x = projScreenRect.w+padding*2;
  statusPanelScreenRect.y = padding;
  statusPanelScreenRect.w = statusPanelWidth;
  statusPanelScreenRect.h = height - galvoPlotScreenRect.h - 2*padding; // - spectrumPlotHeight;

  spectrumPlotHeight = (height - galvoPlotScreenRect.h) / 4;
  spectrumScreenRect.x = projScreenRect.x
                       + projScreenRect.w
                       + statusPanelScreenRect.w
                       + padding*2;
  spectrumScreenRect.y = height-galvoPlotHeight - padding - spectrumPlotHeight;
  spectrumScreenRect.w = width - 4*padding
                       - projScreenRect.w
                       - statusPanelScreenRect.w;
  spectrumScreenRect.h = spectrumPlotHeight;

}

void setup() {
  size(1920, 1200, P2D);
  // size(2220, 2074, P2D);
  surface.setResizable(true);
  // surface.setLocation(0, 40);
  textSize(24);
  frameRate(480);
  galvoPlotCtxRect = new Rect(0, 0, width, galvoPlotHeight);
  projectionCtx = createGraphics(projectionCtxRect.w, projectionCtxRect.h, P3D);
  galvoPlot = new GalvoPlot(galvoPlotCtxRect.w, galvoPlotCtxRect.h);
  
  statusPanelScreenRect = new Rect(projScreenRect.x,
                                   0,
                                   statusPanelWidth,
                                   height-galvoPlotHeight);

  colorPanelScreenRect = new Rect(width-projScreenRect.x - padding*2,
                            height - galvoPlotScreenRect.h - colorPanelHeight,
                            spectrumScreenRect.h - padding*3,
                            colorPanelHeight);

  oscProps = new OscProperties();
  oscProps.setDatagramSize(65535);
  oscProps.setListeningPort(12000);
  oscP5 = new OscP5(this, oscProps);

  noLoop();

  analyzer = new FrameAnalyzer();
  freqAnalyzer = new FrequencyAnalyzer(4096);
  colorAnalyzer = new ColorAnalyzer();

  fpsHistory     = new HistoryPlot("FPS",    historyLength, 0.0, 240.0,  5, "int", "");
  pointsHistory  = new HistoryPlot("Points", historyLength, 0.0, 4096.0, 1, "int", "");
  ppsHistory     = new HistoryPlot("PPS",    historyLength, 0.0, 360.0,  5, "int", "k");
  // pathsHistory   = new HistoryPlot("Paths",  historyLength, 0.0, 100.0,  1, "int", "");
  distHistory    = new HistoryPlot("Dsum",   historyLength, 0.0, 120.0,  5, "float", "k");
  maxdistHistory = new HistoryPlot("Dmax",   historyLength, 0.0, 5800.0, 1, "int", "");
  bcRatioHistory = new HistoryPlot("C/D",    historyLength, 0.0, 1.0,    5, "float", "");
  bitrateHistory = new HistoryPlot("Net",    historyLength, 0.0, 10.0, 5, "float", "Mb");
  energyxHistory = new HistoryPlot("Ex",     historyLength, 0.0, 4096,   10,  "int", "");
  energyyHistory = new HistoryPlot("Ey",     historyLength, 0.0, 4096,   10,  "int", "");

  plots.add(fpsHistory);
  plots.add(pointsHistory);
  plots.add(ppsHistory);
  // plots.add(pathsHistory);
  plots.add(distHistory);
  plots.add(energyxHistory);
  plots.add(bcRatioHistory);
  plots.add(maxdistHistory);
  plots.add(energyyHistory);
  plots.add(bitrateHistory);

  // For caclulation only, dont add to layout:
  smoothPoints = new HistoryPlot("SmoothPoints", historyLength, 0, 4096, 20, "","");

  updateScreenRects();

  // Configure buttons
  receiveButton.isToggle = true;
  receiveButton.state = !snapshotModeEnabled;
  oscframesButton.state = true;
  renderModeButton.isToggle = true;
  renderModeButton.state = true;
  uncapButton.isToggle = true;
  uncapButton.state = false;
  fitwidthButton.isToggle = true;
  fitwidthButton.state = true;

//   PGL pgl = beginPGL(); // Begin the raw OpenGL context
//   IntBuffer maxUniforms = IntBuffer.allocate(1);
//   pgl.glGetIntegerv(PGL.GL_MAX_FRAGMENT_UNIFORM_VECTORS, maxUniforms);
//   int uniformComponents = maxUniforms.get(0);
//   endPGL(); // End raw OpenGL context
//   println("Max fragment uniform components: " + uniformComponents);
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
  
  ArrayList<Point> lpoints = new ArrayList(points);
  ArrayList<Region> lregions = analyzer.getRegions(lpoints);

  freqAnalyzer.update(lpoints);

  colorAnalyzer.update(lpoints);


  int mx = mouseX, my = mouseY; 
  updateCursors(mx, my, lpoints);
  ArrayList<Region> regionsAtSelection = analyzer.selectAndGetRegionsAtIndex(galvoPlot.selectedPointIndex);

  // Select points in selected region
  for (int ridx = 0; ridx < regionsAtSelection.size(); ridx++) {
    Region r = regionsAtSelection.get(ridx);
    for(int pidx=r.startIndex; pidx <= r.endIndex; pidx++) {
      lpoints.get(pidx).selected = true;
    }
  }

  // Buttons
  if (oscframesButton.clicked()) {
    oscFrameCount = 0;
  }
  oscframesButton.label = String.format("%08d", oscFrameCount);
  if (receiveButton.clicked()) {
    setSnapshotMode(!receiveButton.state);
    oscframesButton.state = receiveButton.state;
  }
  if (renderModeButton.clicked()) {
    galvoPlot.shapeRender = renderModeButton.state;  
  }
  if (uncapButton.clicked()) {
    setSnapshotMode(true);
  }
  if (fitwidthButton.clicked()) {
    galvoPlot.fitToWidth = fitwidthButton.state;
  }

  background(8);
  //camera();


  if (frameDirty || snapshotModeEnabled) {
    renderProjectionImg(lpoints, lregions, projectionCtx);
    galvoPlot.render(lpoints, lregions, smoothPoints.expMovingAvg);
    frameDirty = false;
  }

  // Draw projection image
  image(projectionCtx,
        projScreenRect.x,
        projScreenRect.y,
        projScreenRect.w,
        projScreenRect.h);
  
  // Draw black background for galvo plot area
  // noStroke();
  // fill(0);
  // rect(galvoPlotScreenRect.x,
  //      galvoPlotScreenRect.y,
  //      galvoPlot.scaledPlotWidth,
  //      //width,
  //      galvoPlotScreenRect.h);
    
  // Draw galvo plot image
  galvoPlot.draw(
    galvoPlotScreenRect.x,
    galvoPlotScreenRect.y,
    galvoPlotScreenRect.w,
    galvoPlotScreenRect.h);

  drawStatusPanel(
    statusPanelScreenRect.x,
    statusPanelScreenRect.y,
    statusPanelScreenRect.w,
    statusPanelScreenRect.h,
    lpoints, regionsAtSelection);

  freqAnalyzer.drawFFTShader(
    spectrumScreenRect.x,
    spectrumScreenRect.y,
    spectrumScreenRect.w,
    spectrumScreenRect.h);

  // freqAnalyzer.draw(
  //   spectrumScreenRect.x,
  //   spectrumScreenRect.y,
  //   spectrumScreenRect.w,
  //   spectrumScreenRect.h);

  if (spectrumScreenRect.containsPoint(mouseX, mouseY)) {
    freqAnalyzer.drawCursor(
      spectrumScreenRect.x,
      spectrumScreenRect.y,
      spectrumScreenRect.w,
      spectrumScreenRect.h,
      mouseX - spectrumScreenRect.x);
  }

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

  energyxHistory.addValue((float)freqAnalyzer.energyX);
  energyyHistory.addValue((float)freqAnalyzer.energyY);

  int plotRows, plotCols;
  if (width-projScreenRect.w < width/2) {
    plotRows = plots.size();
    plotCols = 1;
  }
  else {
    // plotRows = 5;
    // plotCols = 2; 
    plotRows = 3;
    plotCols = 3;  
  }
  drawPlotsLayout(projScreenRect.w + statusPanelScreenRect.w+plotMargin*3,
                  1,
                  width-projScreenRect.w - statusPanelScreenRect.w -plotMargin*3,
                  height-galvoPlotHeight-plotMargin*3 - spectrumPlotHeight - colorPanelHeight,
                  plotRows, plotCols);
  // drawPlotsLayout(projScreenRect.w + statusPanelScreenRect.w+plotMargin*3,
  //                 1,
  //                 width-projScreenRect.w - statusPanelScreenRect.w -plotMargin*3,
  //                 height-galvoPlotHeight-plotMargin*3 - spectrumPlotHeight,
  //                 plotRows, plotCols);



  colorAnalyzer.draw(projScreenRect.w + statusPanelScreenRect.w+plotMargin*3,
                  height - galvoPlotScreenRect.h -spectrumPlotHeight - colorPanelHeight - plotMargin,
                  width-projScreenRect.w - statusPanelScreenRect.w -plotMargin*4,
                  colorPanelHeight - plotMargin);

  prevFrameFinalPoint = lpoints.get(npoints-1);
}


float getViewportMin(float cursor, float zoom) {
  return cursor * (1.0f - 1.0f / zoom);
}

float getViewportMax(float cursor, float zoom) {
  return getViewportMin(cursor, zoom) + 1.0f / zoom;
}


void drawStatusPanel(int x, int y, int w, int h,
             ArrayList<Point> points, ArrayList<Region> regionsAtSelection) {
  int pad = 10;
  int infoPanelHeight = 180;
  int bcount = 0;
  int vstep = buttonHeight+pad;
  int vstart = y + h - infoPanelHeight - vstep*7;

  fill(0);
  strokeWeight(1);
  stroke(borderColor);
  rect(x, y, w, h);

  // Draw buttons
  receiveButton.draw   (x+pad*2, vstart+pad*4 + vstep * bcount++);
  uncapButton.draw     (x+pad*2, vstart+pad*5 + vstep * bcount++);
  renderModeButton.draw(x+pad*2, vstart+pad*6 + vstep * bcount++);
  fitwidthButton.draw  (x+pad*2, vstart+pad*7 + vstep * bcount++);
  oscframesButton.draw (x+pad*2, vstart+pad*8 + vstep * bcount++);

  // reset for text
  bcount=1;
  vstep = 20;

  // Draw debug info
  // fill(192);
  // textSize(16);
  // float vpw = 1.0 / galvoPlot.zoom;
  // float vpMin = galvoPlot.cursorNormalized * vpw;
  // float vpMax = galvoPlot.cursorNormalized + vpw / 2.0 / galvoPlot.zoom;
  //
  // String selTxt = (galvoPlot.selectedPointIndex > -1)?
  //                   String.format("sel: %d", galvoPlot.selectedPointIndex)
  //                   : "sel: none";
  // String zoomTxt = String.format("zoom: %.2f", galvoPlot.zoom);
  // String cursorTxt = String.format("cursor: %.2f", galvoPlot.cursorNormalized);
  // String vpwTxt = String.format("VPw: %.2f", 1.0 / galvoPlot.zoom);
  // String vpminTxt = String.format("VPmin: %.2f",
  //                   getViewportMin(galvoPlot.cursorNormalized, galvoPlot.zoom));
  // String vpmaxTxt = String.format("VPmax: %.2f",
  //                    getViewportMax(galvoPlot.cursorNormalized, galvoPlot.zoom));
  // String fpsTxt = String.format("fps: %d", (int)frameRate);
  //
  // text(selTxt,    x+pad*2, y + vstep * bcount++);
  // text(zoomTxt,   x+pad*2, y + vstep * bcount++);
  // text(cursorTxt, x+pad*2, y + vstep * bcount++);
  // text(vpwTxt,    x+pad*2, y + vstep * bcount++);
  // text(vpminTxt,  x+pad*2, y + vstep * bcount++);
  // text(vpmaxTxt,  x+pad*2, y + vstep * bcount++);
  // text(fpsTxt,    x+pad*2, y + vstep * bcount++);

  // Draw selection info panel
  drawSelectionInfoPanel(x+pad, y+h-180-pad, 280, infoPanelHeight,
                         points, regionsAtSelection);

  bcount += 2;

  int metersWidth = 100;
  if (height > 1190) {
    drawdBMeter((float)freqAnalyzer.powerDbX, (float)freqAnalyzer.powerDbY,
                   x+pad*4, y + vstep * (bcount-2), metersWidth, 250);
    
    drawEnergyMeter(energyxHistory.expMovingAvg, energyyHistory.expMovingAvg,
                   x+pad*6+metersWidth, y + vstep * (bcount-2), 100, 250);
  }
} 

void drawEnergyMeter(float dBX, float dBY, int x, int y, int w, int h) {
  float minDB = 0;       // Minimum dB value for the scale
  float maxDB = 4096;         // Maximum dB value for the scale
  int pad = 10;
  // color meterColor = color(192/2,238/2,1,255);

  int meterW = (w-pad*3) / 2;
  int meterH = h - pad*2;
  
  // Map the dB value to the meter's length
  float meterValueX = map(dBX, minDB, maxDB, 0, meterH);
  float meterValueY = map(dBY, minDB, maxDB, 0, meterH);
  meterValueX = min(meterH-1, meterValueX);
  meterValueY = min(meterH-1, meterValueY);


  stroke(255,32);
  fill(0);
  rect(x, y, w, h);

  //stroke(255,64);
  rect(x+pad, y+pad, meterW, meterH);
  rect(x+meterW+pad*2, y+pad, meterW, meterH);
  

  fill(meterColor);
  noStroke();
  rect(x+pad+1, y+h-pad - meterValueX, meterW-1, meterValueX);
  rect(x+meterW+pad*2+1, y+h-pad - meterValueY, meterW-1, meterValueY);
  
  // Draw the scale with reference lines
  stroke(255);
  fill(255);
  for (float refDB = maxDB; refDB >= minDB; refDB -= 512) {
    float refY = map(refDB, minDB, maxDB, y+h-pad, y+pad);
    line(x+2, refY, x+3, refY);
    //text(nf(refDB, 0, 1) + " dB", x, refY);
    //text(nf(refDB, 0, 1) + " dB", refX + 2, y - scaleLength);
  }

  text(String.format("%.2f", dBX), x+pad, y+h+pad*2);

}

void drawdBMeter(float dBX, float dBY, int x, int y, int w, int h) {
  float minDB = -50;       // Minimum dB value for the scale
  float maxDB = 10;         // Maximum dB value for the scale
  int pad = 10;
  // color meterColor = color(192/2,238/2,1,255);
  int meterW = (w-pad*3) / 2;
  int meterH = h - pad*2;
  float meterValueX, meterValueY; 

  if (dBX == Double.NEGATIVE_INFINITY || dBY == Double.NEGATIVE_INFINITY) {
    // meterValueX = 0.0;
    // meterValueY = 0.0;
    smoothPowerX = freqAnalyzer.computeExpMovingAvg(smoothPowerX, minDB, 5.0);
    smoothPowerY = freqAnalyzer.computeExpMovingAvg(smoothPowerY, minDB, 5.0);
  }
  else {
    smoothPowerX = freqAnalyzer.computeExpMovingAvg(smoothPowerX, dBX, 5.0);
    smoothPowerY = freqAnalyzer.computeExpMovingAvg(smoothPowerY, dBY, 5.0);
  }

    // Map the dB value to the meter's length
    meterValueX = map((float)smoothPowerX, minDB, maxDB, 0, meterH);
    meterValueY = map((float)smoothPowerY, minDB, maxDB, 0, meterH);
    meterValueX = max(0, min(meterH-1, meterValueX));
    meterValueY = max(0, min(meterH-1, meterValueY));

  stroke(255,32);
  fill(0);
  rect(x, y, w, h);

  //stroke(255,64);
  rect(x+pad, y+pad, meterW, meterH);
  rect(x+meterW+pad*2, y+pad, meterW, meterH);
  
  fill(meterColor);
  noStroke();
  rect(x+pad+1, y+h-pad - meterValueX, meterW-1, meterValueX);
  rect(x+meterW+pad*2+1, y+h-pad - meterValueY, meterW-1, meterValueY);
  
  // Draw the scale with reference lines
  stroke(255);
  fill(255);


  float refY = map(0.0, minDB, maxDB, y+h-pad, y+pad);
  line(x+2, refY, x+6, refY);
  text("0dB", x-50, refY);

  // for (float refDB = maxDB; refDB >= minDB; refDB -= 10) {
  //   float refY = map(refDB, minDB, maxDB, y+h-pad, y+pad);
  //   line(x+2, refY, x+3, refY);
  //   //text(nf(refDB, 0, 1) + " dB", x, refY);
  //   //text(nf(refDB, 0, 1) + " dB", refX + 2, y - scaleLength);
  // }

  text(String.format("%.2fdB", dBX), x+pad, y+h+pad*2);

}

void drawSelectionInfoPanel(int x, int y, int w, int h, ArrayList<Point> points, ArrayList<Region> regionsAtSelection) {
  int rowHeight = 28;
  int colorw = 100;
  int colorh = 100;
  int margin = 10;
  
  int xpos = x;
  int ypos = y;
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
  stroke(borderColor);
  fill(0,0,0, 240);
  strokeWeight(1);
  rect(xpos, ypos, w, h);

  if (selectedPoint == null || galvoPlot.selectedPointIndex < 0) {
    fill(255,255,255, 32);
    String s = "NO SELECTION";
    text(s, x+w/2-textWidth(s)/2, y+h/2);
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
  if (isBlank) {
    stroke(255,255,255,64);
    rect(xpos+margin, ypos+margin, colorw-2*margin, colorh-2*margin);
    fill(255,255,255,64);
    text ("BLANK", xpos+margin+6, ypos+margin+46);
  }
  else {
    noStroke();
    fill(selectedPoint.col);
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
                                  (int)red(selectedPoint.col),
                                  (int)green(selectedPoint.col),
                                  (int)blue(selectedPoint.col));
  texty = textOriginY + rowCount++ * rowHeight;
  text(colorStr, textx, texty);

  String indexStr = String.format("index: %d", galvoPlot.selectedPointIndex);
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
  
  // DRAW Indicator
  String drawStr;
  if (pathLength > 0 && (isPath || isDwell)) {
    stroke(255,255,255,192);
    noFill();
    rect(xpos+margin*1, ypos+colorh+margin, buttonWidth, buttonHeight);
    fill(255,255,255,240);
    drawStr = String.format("%d", pathLength);
  }
  else {
    stroke(255,255,255,64);
    noFill();
    rect(xpos+margin*1, ypos+colorh+margin, buttonWidth, buttonHeight);
    fill(255,255,255,64);
    drawStr = "";
  }
  textx = xpos+margin*2;
  texty = textOriginY+3;
  text("path", textx, texty);
  texty += rowHeight;
  text(drawStr, textx, texty);

  // BLANK Indicator
  String blankStr;
  if (isBlank) {
    stroke(255,255,255,192);
    noFill();
    rect(xpos+margin*2+buttonWidth, ypos+colorh+margin, buttonWidth, buttonHeight);
    fill(255,255,255,240);
    blankStr = String.format("%d", blankLength);
  }
  else {
    stroke(255,255,255,64);
    noFill();
    rect(xpos+margin*2+buttonWidth, ypos+colorh+margin, buttonWidth, buttonHeight);
    fill(255,255,255,64);
    blankStr = "";
  }
  textx = xpos+margin*3+buttonWidth*1;
  texty = textOriginY+3;
  text("blank", textx, texty);
  texty += rowHeight;
  text(blankStr, textx, texty);
  
  // DWELL Indicator
  String dwellStr;
  if (isDwell) {
    stroke(255,255,255,192);
    noFill();
    rect(xpos+margin*3+buttonWidth*2, ypos+colorh+margin, buttonWidth, buttonHeight);
    fill(255,255,255,240);
    dwellStr = String.format("%d", dwellLength);
  }
  else {
    stroke(255,255,255,64);
    noFill();
    rect(xpos+margin*3+buttonWidth*2, ypos+colorh+margin, buttonWidth, buttonHeight);
    fill(255,255,255,64);
    dwellStr = "";
  }
  textx = xpos+margin*4+buttonWidth*2;
  texty = textOriginY+3; // + rowCount * rowHeight;
  text("dwell", textx, texty);
  texty += rowHeight;
  text(dwellStr, textx, texty);
}


int findClosestPointIndex(Point target, ArrayList<Point> points) {
  int npoints = points.size();
  float minDist = 999999.0;
  int minIndex = -1;

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


void updateCursors(int mx, int my, ArrayList<Point> points) {
  // Update galvo plot cursor
  if (galvoPlotScreenRect.containsPoint(mx, my) || galvoPlot.selectionLatched) {
    galvoPlot.updateCursor(mx, my, galvoPlotScreenRect, points);
    selectedPoint = galvoPlot.selectedPoint; 
  }
   
    // Update projection cursor
  else if(projScreenRect.containsPoint(mx, my)) {
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

    if(closestIndex < 0) {
      galvoPlot.setSelectedIndex(-1, points);
    }
    else {
      if (closestIndex > -1 && cursorPoint.dist(points.get(closestIndex)) < 0.25) {
        galvoPlot.setSelectedIndex(closestIndex, points);
        selectedPoint = points.get(closestIndex);
      }
    }
  }
  else {
    galvoPlot.setSelectedIndex(-1, points);
  }
}


void drawPlotsLayout(int x, int y, int layoutWidth, int layoutHight, int rows, int cols)  {
  int pwidth = (layoutWidth - plotMargin*1*cols) / cols;
  int pheight = (layoutHight - plotMargin*(rows-1)) / rows;

  // println("plot height:", pheight);

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
      p.drawShader(xpos, ypos, pwidth, pheight);
      p.draw(xpos, ypos, pwidth, pheight);
      i++;
    }
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
        if (p1.isBlank) {
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

  // Highlight active view
  // if (galvoPlotScreenRect.containsPoint(mx, my)) {
  //   stroke(0, 255, 0);
  //   strokeWeight(1);
  //   noFill();
  //   rect(galvoPlotScreenRect.x, galvoPlotScreenRect.y,
  //        galvoPlotScreenRect.w, galvoPlotScreenRect.h);
  // }

  // if (projScreenRect.containsPoint(mx, my)) {
  //   stroke(0, 255, 0);
  //   strokeWeight(1);
  //   noFill();
  //   rect(projScreenRect.x, projScreenRect.y,
  //        projScreenRect.w, projScreenRect.h);
  // }
}


void renderProjectionImg(ArrayList<Point> ppoints, ArrayList<Region> regions, PGraphics g) {
  int npoints = ppoints.size();
  int nregions = regions.size();
  float sx = -g.width / 2.0;
  float sy =  g.width / 2.0;

  g.beginDraw();
  g.background(0);
  g.blendMode(ADD);
  g.noFill();
  g.pushMatrix();
  g.translate(g.width/2, g.height/2);

  g.stroke(borderColor);
  g.strokeWeight(1);
  g.square(-g.height/2, -g.height/2, g.height-1);

  if (showBlankLines) {
    g.strokeWeight(1);
    g.stroke(64, 64, 64);
    g.beginShape(LINES);

    for (int i = 0; i < npoints; i++) {
      int pidx1 = i;
      int pidx2 = (i+1) % npoints;
      Point p1 = ppoints.get(pidx1);
      if (!p1.isBlank) {
        continue;
      }
      Point p2 = ppoints.get(pidx2);
      if (p1.posEqual(p2)) {
        continue;
      }

      g.vertex(p1.x*sx, p1.y*sy);
      g.vertex(p2.x*sx, p2.y*sy);
    }
    g.endShape();
  }

  g.strokeWeight(4);
  g.beginShape(LINES);

  for (int i = 0; i < npoints; i++) {
    int pidx1 = i;
    int pidx2 = (i+1) % npoints;
    Point p1 = ppoints.get(pidx1);
    if (p1.isBlank) {
      continue;
    }

    Point p2 = ppoints.get(pidx2);

    if (p1.posEqual(p2)) {
      continue;
    }

    g.stroke(p1.col, 240);
    g.vertex(p1.x*sx, p1.y*sy);
    g.vertex(p2.x*sx, p2.y*sy);
  }
  g.endShape();

  // Draw dwell points
  for (int i=0; i<nregions; i++) {
    Region r = regions.get(i);
    if (r.type != Region.DWELL) {
      continue;
    }
  
    Point p = ppoints.get(r.startIndex);
    g.strokeWeight(6);
    g.stroke(p.col, 255);
    g.point(p.x*sx, p.y*sy);
  }

  // Highlight the selected point
  if (showBlankLines
  // if (snapshotModeEnabled
      && galvoPlot.selectedPointIndex >= 0
      && galvoPlot.selectedPointIndex < npoints-1) {
    Point p1 = (Point)ppoints.get(galvoPlot.selectedPointIndex);
    if (p1.isBlank) {
      g.stroke(255,255,255,240);
      g.fill(0,0,0, 192);
    }
    else {
      g.stroke(255,255,255,240);
      g.fill(p1.col, 192);
    }
    g.strokeWeight(2);
    g.ellipse(p1.x*sx, p1.y*sy, 25, 25);
  }

  // draw cursor
  // g.stroke(255);
  // g.strokeWeight(4);
  // //g.line(p1.x*-s, p1.y*s, p2.x*-s, p2.y*s );
  // g.ellipse(projScreenCursor.x, projScreenCursor.y, 25, 25);
  

  if (showBlankLines) {
    // highlight first point in frame
    Point p1 = (Point)ppoints.get(0);
    g.stroke(255, 255, 255, 128);
    noFill();
    // g.fill(0, 255,0);
    g.ellipse(p1.x*sx, p1.y*sy, 10, 10);
  }
  g.popMatrix();
  g.endDraw();
}


void setSnapshotMode(Boolean enabled) {
  receiveButton.state = !enabled;
  if (enabled) {
    snapshotModeEnabled = true;
    oscEnabled = false;
    if (uncapButton.state) {
      targetFrameRate = 600;
    }
    else {
      targetFrameRate = 60;
    }
    updateFrameRate = true;
    loop();
  }
  else {
    snapshotModeEnabled = false;
    targetFrameRate = 480;
    updateFrameRate = true;
    uncapButton.state = false;
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
    case 'g':
      freqAnalyzer.gamma -= 0.01;
      println("gamma:", freqAnalyzer.gamma);
      break;
    case 'G':
      freqAnalyzer.gamma += 0.01;
      println("gamma:", freqAnalyzer.gamma);
      break;
  }
}

void keyPressed() {
  switch(key) {
    case 'j':
      galvoPlotHeight -= 20;
      updateScreenRects(); 
      //galvoPlot.resizeCtx(galvoPlotScreenRect.w, galvoPlotScreenRect.h);
      break;
    case 'k':
      galvoPlotHeight += 20;
      updateScreenRects(); 
      //galvoPlot.resizeCtx(galvoPlotScreenRect.w, galvoPlotScreenRect.h);
      break;
  }
}

void mouseClicked() {
  if (galvoPlotScreenRect.containsPoint(mouseX, mouseY)
      || projScreenRect.containsPoint(mouseX, mouseY)) {
    galvoPlot.selectionLatched = !galvoPlot.selectionLatched;
  }
  // if (mouseY > height - galvoPlotHeight) {
  //   galvoPlot.fitToWidth = !galvoPlot.fitToWidth;
  //   updateScreenRects();
  //   println("galvoPlot.fitToWidth: ", galvoPlot.fitToWidth);
  // }
}

void mouseWheel(MouseEvent event) {
  float e = event.getCount();
  if (galvoPlotScreenRect.containsPoint(mouseX, mouseY)) {
    galvoPlot.zoomVelocity += -e * galvoPlot.zoom / 200;
  }

  if(spectrumScreenRect.containsPoint(mouseX, mouseY)) {
    freqAnalyzer.zoomVelocity += -e * freqAnalyzer.zoom / 200.0;
  }

}

void mouseDragged() {

}

void mouseReleased() {
  oscframesButton.mouseReleased();
  receiveButton.mouseReleased();
  renderModeButton.mouseReleased();
  uncapButton.mouseReleased();
  fitwidthButton.mouseReleased();
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
    }
    points = pointList;
    frameDirty = true;
    oscFrameCount++;
    redraw();
  }
}

int unpackUInt16(byte[] bytes, int offset) {
  return ((bytes[offset + 1] & 0xFF) << 8) | (bytes[offset] & 0xFF);
}

int unpackUInt8(byte[] bytes, int offset) {
  return bytes[offset] & 0xFF;
}


class Button {
  int x, y, w, h;
  String label = "Button";
  color borderColor = color(255,255,255,16);
  color fillColor   = color(255,255,255,8);
  //color textColor   = color(255,255,255, 192);
  color textColor   = color(255,255,255,160);
  //color onTextcolor = color(128,240,32,255);
  color onTextcolor = color(192,238,1,255);
  //color onTextcolor = color(57,255,20,255); // neon green
  color hoverColor  = color(255,255,255,32);
  color onFillcolor = color(255,255,255,16);
  Boolean isToggle = false;
  Boolean state = false;
  Boolean wasClicked = false;

  public Button() {
    x = 0;
    y = 0;
    w = 150;
    h = 50;
  }

  public Button(String _label, int _x, int _y, int _w, int _h) {
    label = _label;
    x = _x;
    y = _y;
    w = _w;
    h = _h;
  }


  public void draw(int _x, int _y) {
    x=_x;
    y=_y;
    draw();
  }

  public void draw() {
    stroke(borderColor);
    if  ((mouseX<x) || (mouseX>x+w) || (mouseY<y) || (mouseY>y+h)) {
      if (state) {
        fill(onFillcolor);
      }
      else {
        fill(fillColor);
      }
    }
    else {
      fill(hoverColor);
    }
    rect(x, y, w, h, 10);

    if (state) {
      fill(onTextcolor);
    }
    else {
      fill(textColor);
    }
    textSize(30);
    text(label, x + w/2 - textWidth(label)/2, y+h/2+10);

    if (state) {
      fill(onTextcolor, 8);
      rect(x, y, w, h, 10);
    }
  }

  public Boolean clicked() {
    if (mouseX >= x && mouseX <= x + w &&
        mouseY >= y && mouseY <= y + h) {
      if(mousePressed && !wasClicked) {
        wasClicked = true;
        if (isToggle) {
          state = ! state;
        }
        return true;
      }
    }
    return false;

  }

  void mouseReleased() {
    wasClicked = false;
  }
}


class Point {
  public float x, y;
  color col;
  Boolean isBlank;
  public Boolean selected = false;

  Point(float _x, float _y, float r, float g, float b) {
    this.x = _x;
    this.y = _y;
    this.col = color(r, g, b);
    this.isBlank = this.isBlank();
  }
  
  Point(float _x, float _y) {
    this.x = _x;
    this.y = _y;
    this.col = color(0);
    this.isBlank = true;
  }
  Point(float _x, float _y, color _col) {
    this.x = _x;
    this.y = _y;
    this.col = _col;
    this.isBlank = this.isBlank();
  }

  private Boolean isBlank() {
    return (red(col) == 0 && green(col) == 0 && blue(col) == 0);
  }

  public String toString() {
    return String.format("[% .4f, % .4f]\t[%.4f, %.4f, %.4f]", 
      x, y, red(col), green(col), blue(col));
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
    return (this.col == p.col);
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

  public Boolean containsPoint(float px, float py) {
    return !((px<x) || (px>x+w) || (py<y) || (py>y+h));
  }
}


//
// Here lies the graveyard of code
//
// class PointInfo {
//   Boolean frameStart=false;
//   Boolean frameEnd=false;
//   Boolean blankDwell = false;
//   Boolean dwell = false;
//   Boolean pathBegin = false;
//   Boolean pathEnd = false;
//   Boolean travelStart = false;
//   Boolean isBlank = false;
//   public PointInfo() {
//
//   }
//   
//   public String toString() {
//     return String.format("f0: %s, f1: %s, dwb: %s, dwc: %s, p0: %s, p1: %s, trav: %s",
//         frameStart, frameEnd, blankDwell, dwell, pathBegin, pathEnd, travelStart);
//   } 
// }
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
