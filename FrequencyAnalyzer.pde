import org.apache.commons.math4.transform.*;
import org.apache.commons.numbers.core.*;
import org.apache.commons.numbers.complex.Complex;

class FrequencyAnalyzer {
  int fftSize;
  FastFourierTransform fft;
  
  double[] magnitudeX;
  double[] magnitudeY;
  double[] logMagnitudeX;
  double[] logMagnitudeY;
  double[] smoothMagnitudeX;
  double[] smoothMagnitudeY;
  double[] zeroMeanX;
  double[] zeroMeanY;

  double energyX, energyY, energyRef;
  double powerDbX, powerDbY;
  double dcOffsetX, dcOffsetY;

  double gamma = 0.57;

  int sampleRate = 0x10000;
  //float[] hamming;

  float zoom = 1.0;
  float zoomVelocity = 0.0;

  public FrequencyAnalyzer(int _fftSize) {
    this.fftSize = _fftSize;
    fft = new FastFourierTransform(FastFourierTransform.Norm.STD);
    magnitudeX = new double[fftSize];
    magnitudeY = new double[fftSize];
    logMagnitudeX = new double[fftSize/2];
    logMagnitudeY = new double[fftSize/2];
    smoothMagnitudeX = new double[fftSize/2];
    smoothMagnitudeY = new double[fftSize/2];
    zeroMeanX = new double[fftSize];
    zeroMeanY = new double[fftSize];

    energyRef = fftSize;
    dcOffsetX = 0;
    dcOffsetY = 0;
  }

  public FrequencyAnalyzer() {
    this(4096);
  }

  public void update(ArrayList<Point> points) {
    int npoints = points.size();
    // if (npoints < 1) {
    //   return;
    // }
    double[] xvals = new double[fftSize];
    double[] yvals = new double[fftSize];

    double offset = 1e-6; // Small positive constant to avoid log of a small number
    double minLogMagnitudeX = Double.POSITIVE_INFINITY;
    double maxLogMagnitudeX = Double.NEGATIVE_INFINITY;
    double minLogMagnitudeY = Double.POSITIVE_INFINITY;
    double maxLogMagnitudeY = Double.NEGATIVE_INFINITY;
    
    //fft = new FastFourierTransform(FastFourierTransform.Norm.STD);

    //float[] window = hanningWindow(npoints);
    
    // sine wave test to check freq scale calcs
    // double f = 1024.0001;
    // double astep = 2.0 * Math.PI * f / sampleRate;
    // for (int i=0; i < fftSize; i++) {
    //   xvals[i] = Math.sin(i*astep);
    //   yvals[i] = Math.cos(i*astep);
    //   //xvals[i] = p.x*window[i];
    //   //yvals[i] = p.y*window[i];
    // }

    //repeat waveform to fill buffer 
    if (npoints > 0) {
      for (int i=0; i < fftSize; i++) {
        Point p = points.get(i % npoints);
        xvals[i] = p.x;
        yvals[i] = p.y;
      }
    }
    // zero pad waveform 
    // for (int i=0; i < min(npoints, fftSize); i++) {
    //   Point p = points.get(i);
    //   xvals[i] = p.x;
    //   yvals[i] = p.y;
    // }

    energyX = 0.0;
    energyY = 0.0;
    dcOffsetX = getDCOffset(xvals, fftSize);
    dcOffsetY = getDCOffset(yvals, fftSize);
    // dcOffsetX = getDCOffset(xvals, npoints);
    // dcOffsetY = getDCOffset(yvals, npoints);
    for (int i = 0; i < fftSize; i++) {
    //for (int i = 0; i < min(npoints, fftSize); i++) {
      zeroMeanX[i] = xvals[i] - dcOffsetX;
      zeroMeanY[i] = yvals[i] - dcOffsetY;

      energyX += zeroMeanX[i]*zeroMeanX[i];
      energyY += zeroMeanY[i]*zeroMeanY[i];
      // energyX += Math.pow(magnitudeX[i], 2);
      // energyY += Math.pow(magnitudeY[i], 2);
    }
    energyRef = (double)fftSize;
    //energyRef = (double)npoints;
    if (npoints > 0) {
      powerDbX = 10 * Math.log10(energyX / energyRef);
      powerDbY = 10 * Math.log10(energyY / energyRef);
    }
    //println("dB: ", powerDbX, powerDbY);
    
    //println("energy:", energyX, energyY);

    int n = min(fftSize, npoints);
    float[] window = hammingWindow(n);
    for (int i = 0; i < n; i++) {
      zeroMeanX[i] *= window[i];
      zeroMeanY[i] *= window[i];
    }

    Complex[] fftResultX = fft.apply(zeroMeanX);
    Complex[] fftResultY = fft.apply(zeroMeanY);
    // Complex[] fftResultX = fft.apply(xvals);
    // Complex[] fftResultY = fft.apply(yvals);

    for (int i = 0; i < fftSize/2; i++) {
      // "gamma" corrected mag scale
      magnitudeX[i] = Math.pow(fftResultX[i].abs(), gamma) * 0.05;
      magnitudeY[i] = Math.pow(fftResultY[i].abs(), gamma) * 0.05;
      
      // linear mag scale
      // magnitudeX[i] = fftResultX[i].abs();
      // magnitudeY[i] = fftResultY[i].abs();
      
      smoothMagnitudeX[i] = computeExpMovingAvg(smoothMagnitudeX[i], magnitudeX[i], 5.0);
      smoothMagnitudeY[i] = computeExpMovingAvg(smoothMagnitudeY[i], magnitudeY[i], 5.0);
    }


  //   // Apply log scale
    // for (int i = 0; i < fftSize/2; i++) {
    //   logMagnitudeX[i] = 0 + 10 * Math.log10(magnitudeX[i] + offset);
    //   logMagnitudeY[i] = 0 + 10 * Math.log10(magnitudeY[i] + offset);
    // }
    //
    // for (int i = 0; i < fftSize/2; i++) {
    //   // logMagnitudeX[i] = (logMagnitudeX[i] - minLogMagnitudeX) / xrange;
    //   // logMagnitudeY[i] = (logMagnitudeY[i] - minLogMagnitudeY) / yrange;
    //   logMagnitudeX[i] = 0.1 + logMagnitudeX[i]* 0.03;
    //   logMagnitudeY[i] = 0.1 + logMagnitudeY[i]* 0.03;
    //
    //   smoothMagnitudeX[i] = computeExpMovingAvg(smoothMagnitudeX[i], logMagnitudeX[i], 3.0);
    //   smoothMagnitudeY[i] = computeExpMovingAvg(smoothMagnitudeY[i], logMagnitudeY[i], 3.0);
    // }

  }

  double getDCOffset(double[] buf, int numvals) {
    double offset = 0.0;
    numvals = (numvals <= buf.length)? numvals : buf.length;
    for (int i = 0; i < numvals; i++) {
      offset += buf[i];
    }
    return offset /= numvals;
  }
  
  double computeExpMovingAvg(double currentval, double newVal, double windowSize) {
    double smooth = 2.0 / (windowSize + 1);
    return (newVal - currentval) * smooth + currentval;
  }

  public float binIndexToFreq(int binIdx) {
    return (float)binIdx*sampleRate / fftSize;
  }


  public float[] hammingWindow(int size) {
    float[] window = new float[size];
    for (int n = 0; n < size; n++) {
        window[n] = (float) (0.54 - 0.46 * Math.cos(2 * Math.PI * n / (size - 1)));
    }
    return window;
  }

  public float[] hanningWindow(int size) {
    float[] window = new float[size];
    for (int n = 0; n < size; n++) {
      window[n] = (float) (0.5 - 0.5 * Math.cos(2 * Math.PI * n / (size - 1)));
    }
    return window;
  }

  public void drawScale(int x, int y, int w, int h) {
    int range = (int)(fftSize/2/zoom);
    int numDivisions = 6; 
    int idxStep = range / numDivisions; 
    fill(255,192);
    strokeWeight(1);
    stroke(255,32);
    for (int i=0; i < numDivisions; i++) {
      int binIdx = 1 + (int)(i*idxStep); // / zoom);
      float freq = binIndexToFreq(binIdx);
      String freqstr = (freq < 1000)? String.format("%dHz", (int)freq)
                                    : String.format("%.1fKhz", freq/1000);
      int xpos = (int)min(x + i*w/numDivisions, x+w-textWidth(freqstr));
      int ypos = y+h+20;
      
      text(freqstr, xpos, ypos);
      line(xpos, y, xpos, y+h);
     }
  }


  public void draw(int x, int y, int w, int h) {
    // Width of each bar
    float barWidth = 1;  // One pixel wide
    float xpos, ypos;

    strokeWeight(1);
    stroke(255,255,255,32);
    fill(0, 0, 0, 192);
    rect(x,y,w,h);
    
    zoomVelocity *= 0.8;
    zoom += zoomVelocity;
    zoom = max(1, min(fftSize, zoom));
    
    // Number of FFT bins per screen pixel
    float binsPerPixel = (float) fftSize/2/zoom / w;

    for (int i = 0; i < w; i++) {
      // Determine which FFT bin this pixel represents
      int binIndex = round(i * binsPerPixel);

      // Scale magnitude value to fit within our graph

      float scaledMagnitudeX = (float) smoothMagnitudeX[binIndex]*h/2;
      float scaledMagnitudeY = (float) smoothMagnitudeY[binIndex]*h/2;
                              //
      // float scaledMagnitudeX; // = map((float)smoothMagnitudeX[binIndex], 0, 50, 0, h); 
      // float scaledMagnitudeY; // = map((float)smoothMagnitudeY[binIndex], 0, 50, 0, h); 
      // if (!Double.isNaN(smoothMagnitudeX[binIndex])) {
      //   scaledMagnitudeX = map((float)smoothMagnitudeX[binIndex], 0, 60, 0, h);
      // }
      // else {
      //   scaledMagnitudeX = 0.0;
      // }
      // if (!Double.isNaN(smoothMagnitudeY[binIndex])) {
      //   scaledMagnitudeY = map((float)smoothMagnitudeY[binIndex], 0, 60, 0, h);
      // }
      // else {
      //   scaledMagnitudeY = 0.0;
      // }

      strokeWeight(1);

      xpos = x + i * barWidth;
      ypos = y + h/2 - scaledMagnitudeX;
      ypos = max(y+4, min(ypos, y+h/2));
      stroke(16);
      line (xpos, ypos, xpos, y+h/2); 
      if (ypos > y+4) {
        stroke(255);
        point(xpos, ypos);
      }
      
      ypos = y+h - scaledMagnitudeY;
      ypos = max(y+h/2+4, min(ypos, y+h-1));
      stroke(16);
      line (xpos, ypos, xpos, y+h-1); 
      if (ypos > y+h/2+4) {
        stroke(255);
        point(xpos, ypos);
      }
    }
    
    stroke(255,255,255,32);
    line(x, y + h/2, x+w, y+h/2);
    drawScale(x,y,w,h);
  }


  public void drawCursor(int x, int y, int w, int h, int cursorPos) {
    strokeWeight(1);
    stroke(255,255,255,128);
    line(x+cursorPos, y, x+cursorPos, y+h);
    float freq = binIndexToFreq((int)((float)cursorPos / w / zoom * fftSize/2));
    String s = freq < 1000 ? String.format("%dHz", (int)freq)
                           : String.format("%.1fKhz", freq/1000);
    text(s, min(x+w-textWidth(s), x+cursorPos), y+30);
  }

}




//   // linear interpolated resample
//   double[] resample(double[] originalData, int targetSize) {
//     double[] resampledData = new double[targetSize];
//     double ratio = (double) originalData.length / targetSize;
//
//     for (int i = 0; i < targetSize; i++) {
//       double originalIndex = i * ratio;
//       int index1 = (int) originalIndex;
//       int index2 = Math.min(index1 + 1, originalData.length - 1);
//       double fraction = originalIndex - index1;
//       resampledData[i] = originalData[index1] * (1 - fraction) + originalData[index2] * fraction;
//     }
//
//     return resampledData;
// }  
