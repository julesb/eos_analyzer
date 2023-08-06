import org.apache.commons.math4.transform.*;
import org.apache.commons.numbers.core.*;
import org.apache.commons.numbers.complex.Complex;

class FrequencyAnalyzer {
  int fftSize;
  FastFourierTransform fft;
  
  double[] magnitudeX;
  double[] magnitudeY;

  int sampleRate = 0x10000;
  float[] hamming;

  float zoom = 1.0;
  float zoomVelocity = 0.0;

  public FrequencyAnalyzer(int _fftSize) {
    this.fftSize = _fftSize;
    fft = new FastFourierTransform(FastFourierTransform.Norm.STD);
    magnitudeX = new double[fftSize];
    magnitudeY = new double[fftSize];
    hamming = hammingWindow();
  }

  public FrequencyAnalyzer() {
    this(4096);
  }

  public void update(ArrayList<Point> points) {
    int npoints = points.size();
    double[] xvals = new double[fftSize];
    double[] yvals = new double[fftSize];

    for (int i=0; i < fftSize; i++) {
      Point p = points.get(i % npoints);
      xvals[i] = p.x*hamming[i];
      yvals[i] = p.y*hamming[i];
    }
    
    Complex[] fftResultX = fft.apply(xvals);
    Complex[] fftResultY = fft.apply(yvals);

    // Calculate the magnitudes for both x and y components
    // for (int i = 0; i < fftSize; i++) {
    //   magnitudeX[i] =10 * Math.log10(fftResultX[i].abs());
    //   magnitudeY[i] =10 * Math.log10(fftResultY[i].abs());
    // }

    for (int i = 0; i < fftSize; i++) {
      magnitudeX[i] = fftResultX[i].abs();
      magnitudeY[i] = fftResultY[i].abs();
    }

    zoomVelocity *= 0.8;
    zoom += zoomVelocity;
    zoom = max(1, min(fftSize, zoom));
  }

  public float binIndexToFreq(int binIdx) {
    return (float)binIdx*sampleRate / fftSize;
  }


  public float[] hammingWindow() {
    int size = fftSize;
    float[] window = new float[size];
    for (int n = 0; n < size; n++) {
        window[n] = (float) (0.54 - 0.46 * Math.cos(2 * Math.PI * n / (size - 1)));
    }
    return window;
  }


  public void drawScale(int x, int y, int w, int h) {
    int range = (int)(fftSize/2/zoom);
    int numLabels = 5; 
    int idxStep = range / numLabels; 
    fill(255);
    strokeWeight(1);
    stroke(255,32);
    for (int i=0; i < numLabels; i++) {
      int binIdx = 1 + (int)(i*idxStep / zoom);
      float freq = binIndexToFreq(binIdx);

      int xpos = x + i*w/numLabels;
      int ypos = y+h+20;
      
      String freqstr = (freq < 1000)? String.format("%dHz", (int)freq)
                                    : String.format("%dKhz", (int)freq/1000);
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
    line(x, y + h/2, x+w, y+h/2);
    
    // Number of FFT bins per screen pixel
    float binsPerPixel = (float) fftSize/2/zoom / w;

    for (int i = 0; i < w; i++) {
      // Determine which FFT bin this pixel represents
      int binIndex = round(i * binsPerPixel);

      // Scale magnitude value to fit within our graph
      float scaledMagnitudeX = map((float)magnitudeX[binIndex], 0, 40, 0, h); 
      float scaledMagnitudeY = map((float)magnitudeY[binIndex], 0, 40, 0, h); 

      // Draw x component (bottom half of display)
      //fill(colorX);
      //noStroke();
      stroke(255);
      strokeWeight(4);

      xpos = x + i * barWidth;
      ypos = y + h/2 - scaledMagnitudeX;
      ypos = max(y+2, min(ypos, y+h-1));
      point(xpos, ypos);
      
      //rect(x + i * barWidth, y + h/2, barWidth, -scaledMagnitudeX); 
      // Draw y component (top half of display)
      //fill(colorY);
      //ypos = y + h/2 + scaledMagnitudeY;
      ypos = y+h - scaledMagnitudeY;
      ypos = max(y+h/2, min(ypos, y+h-1));
      point(xpos, ypos);
      //rect(x + i * barWidth, y + h/2, barWidth, scaledMagnitudeY); 
    }
    
    drawScale(x,y,w,h);
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
