import oscP5.*;
import netP5.*;
import java.util.zip.Inflater;
import java.util.zip.DataFormatException;


OscP5 oscP5;
OscProperties oscProps;

Boolean showBlankLines = true;
int pathGraphHeight = 400;

float intensity = 1.0;
PGraphics projCtx;
PGraphics galvoPathCtx;
Boolean frameDirty = true;
ArrayList<Point> points;


float avgBCDistRatio = 0;


void setup() {
  size(1200, 1200, P3D);
  textSize(24);
  frameRate(480);
  projCtx = createGraphics(1200, 1200, P2D);
  galvoPathCtx = createGraphics(width/2, pathGraphHeight/2, P2D);
  oscProps = new OscProperties();
  oscProps.setDatagramSize(65535);
  oscProps.setListeningPort(12000);
  oscP5 = new OscP5(this, oscProps);

  surface.setResizable(true);
  noLoop();
}


void draw() {
  if (points == null || points.size() == 0) {
    return;
  }
  ArrayList<Point> lpoints = new ArrayList(points);

  background(0);
  camera();

  if (frameDirty) {
    renderProjectionImg(lpoints, projCtx);
    renderGalvoPathImg(lpoints, galvoPathCtx);
    frameDirty = false;
  }
  //blendMode(BLEND);
  int imagedim = min(width, height);
  image(projCtx, 0, 0, imagedim, imagedim);

  image(galvoPathCtx, 0, height-pathGraphHeight, width, pathGraphHeight);

  int npoints = lpoints.size();
  float fr = frameRate;
  float kpps = npoints * fr / 1000;

  float[] pathinfo = getPathInfo(lpoints);
  float totalDist = pathinfo[0] + pathinfo[1];
  float dutyCycle = 0.0;
  if (totalDist > 0.0) {
    dutyCycle = pathinfo[1] / totalDist;
  }
  avgBCDistRatio = computeExpMovingAvg(dutyCycle, 50, avgBCDistRatio);

  fill(255);
  text("fps:      " + int(frameRate), 10, 36);
  text("points: " + npoints, 10, 76);
  text("kpps:   " + floor(kpps), 10, 116);
  text("blank:   " + pathinfo[0], 10, 156);
  text("color:   " + pathinfo[1], 10, 196);
  text("duty:   " + avgBCDistRatio, 10, 236);
}


float computeExpMovingAvg(float val, float window, float ema) {
  float smooth = 2.0 / (window + 1); 
  return (val - ema) * smooth + ema;
}


float[] getPathInfo(ArrayList<Point> points) {
    float blankDist = 0.0;
    float colorDist = 0.0;
    float[] dists = new float[2]; 
    int npoints = points.size();
    for (int i=0; i < npoints-1; i++) {
        Point p1 = points.get(i);
        Point p2 = points.get(i+1);
        float dist = p1.dist(p2);
        if (p1.isBlank()) {
            dists[0] += dist;
        }
        else {
            dists[1] += dist;
        }
    }
    return dists;
}


void renderGalvoPathImg(ArrayList ppoints, PGraphics g) {
  int vmargin = 2;
  int npoints = ppoints.size();
  float w = g.width;
  g.beginDraw();
  g.background(0);
  g.blendMode(REPLACE);
  g.stroke(255, 255, 255, 64);
  g.strokeWeight(1);
  g.noFill();
  g.rect(0, 0, g.width-1, g.height-1);
  g.line(0, g.height/2, g.width, g.height/2);
  g.strokeWeight(2);
  
  g.beginShape();
  for (int i = 0; i < w; i++) {
    int pidx = (int)((i / w) * npoints);    
    Point p = (Point)ppoints.get(pidx);
    float xpos = vmargin + 0.5 * (p.x + 1) * (g.height/2 - vmargin*2);
    if (p.isBlank()) {
      g.strokeWeight(1);
      g.stroke(64, 64, 64);
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
    float ypos = g.height/2 + vmargin + 0.5 * (p.y + 1) * (g.height/2 - vmargin*2);
    if (p.isBlank()) {
      g.strokeWeight(1);
      g.stroke(64, 64, 64);
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
  float s = projCtx.width / 2.0;
  g.beginDraw();
  g.background(0);
  g.blendMode(ADD);
  g.noFill();
  g.pushMatrix();
  g.translate(g.width/2, g.height/2); // assume 2D projection
  
  projCtx.stroke(255, 255, 255, 64);
  projCtx.strokeWeight(1);
  projCtx.square(-projCtx.height/2, -projCtx.height/2, projCtx.height-1);
  
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
    if (p1.equal(p2)) {
      g.vertex(p1.x*-s+1.0, p1.y*s+1.0);
      g.vertex(p2.x*-s, p2.y*s);
    }
    else {
      g.vertex(p1.x*-s, p1.y*s);
      g.vertex(p2.x*-s, p2.y*s);
        
    }
  }
  g.endShape();
  g.popMatrix();
  g.endDraw();
}



void oscEvent(OscMessage message) {
  ArrayList<Point> pointList = new ArrayList();
  if (message.checkAddrPattern("/f")) {
    byte[] packedData = message.get(0).bytesValue();

    Inflater decompresser = new Inflater();
    decompresser.setInput(packedData, 0, packedData.length);
    
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

  public Boolean equal(Point p) {
    return (this.x == p.x && this.y == p.y);
  }
}
