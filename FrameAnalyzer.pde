class FrameAnalyzer {
  ArrayList<Region> regions; 
  public FrameAnalyzer() {
  }

  ArrayList<Region> getRegions(ArrayList<Point> points) {
    ArrayList<Region> newregions = new ArrayList();
    Point pPrev, p, pNext;
    int npoints = points.size();
    int blankStartIndex = -1;
    int blankEndIndex   = -1;
    int pathStartIndex = -1;
    int pathEndIndex   = -1;
    int dwellStartIndex = -1;
    int dwellEndIndex   = -1;

    int i = 0;
    while (i < npoints) {
      pPrev = (i > 0)?         points.get(i-1) : null;
      pNext = (i < npoints-1)? points.get(i+1) : null;
      p = points.get(i);

      if (p.isBlank()) {
        // blank start
        if (i==0 || !pPrev.isBlank()) {
          blankStartIndex = i;
        }
        // blank end
        if (blankStartIndex>=0 && (i >= npoints-1 || !pNext.isBlank())) {
          blankEndIndex = i;
          if (blankStartIndex >= 0) {
            Region r = new Region(Region.BLANK, blankStartIndex, blankEndIndex);
            newregions.add(r);
          }
          else {
            println("geRegions(): ERROR: got BLANK end index without a start index");
          }
          blankStartIndex = -1;
          blankEndIndex = -1;
        }
      }
      else {
        // path start
        if (i==0 || pPrev.isBlank()) { 
          pathStartIndex = i;
        }
        // path end
        if (pathStartIndex>=0 &&  (i >= npoints-1 || pNext.isBlank())) {
          pathEndIndex = i;
          if (pathStartIndex >= 0) {
            Region r = new Region(Region.PATH, pathStartIndex, pathEndIndex);
            newregions.add(r);
          }
          else {
            println("geRegions(): ERROR: got PATH end index without a start index");
          }
          pathStartIndex = -1;
          pathEndIndex = -1;
        }
      }
      
      // dwell start
      if ((dwellStartIndex < 0
          && (i == 0 || !pPrev.identical(p))
          && i < npoints-1 && pNext.identical(p)) ) {
        dwellStartIndex = i;
      }
      // if ((dwellStartIndex < 0
      //      && (i == 0 || pPrev.identical(p))
      //      && i < npoints-1 && pNext.identical(p)) ) {
      //   dwellStartIndex = i;
      // }
      // dwell end
      if (i>0
          && dwellStartIndex>=0
          && pPrev.identical(p)
          && (i >= npoints-1 || !pNext.identical(p))) {
        if (dwellStartIndex >= 0) {
          if (i - dwellStartIndex > 1) {
            dwellEndIndex = i;
          //if ( dwellEndIndex - dwellStartIndex > 1) {
            Region r = new Region(Region.DWELL, dwellStartIndex, dwellEndIndex);
            int[] c = { (int)p.r, (int)p.g, (int)p.b };
            r.col = c;
            newregions.add(r);
            dwellStartIndex = -1;
            dwellEndIndex = -1;
          }
        }
        else {
          println("geRegions(): ERROR: got DWELL end index without a start index");
        }
      }
      i++;
    }
    this.regions = newregions;
    return this.regions;
  }

  ArrayList<Region> getRegionsAtIndex(int index) {
    ArrayList regionsAtIndex = new ArrayList();
    for (int i=0; i< regions.size(); i++) {
      Region r = regions.get(i);
      if (r.containsIndex(i)) {
        regionsAtIndex.add(r);
      }
    }
    return regionsAtIndex;
  }

}

class Region {
  static final int BLANK  = 0x00000001;
  static final int PATH   = 0x00000002;
  static final int DWELL  = 0x00000004;

  int startIndex, endIndex;
  int type;
  int pointCount = 0;
  int[] col = {0,0,0}; // for dwell only

  public Region() {}
  
  public Region(int type, int startIdx, int endIdx) {
    this.type = type;
    this.startIndex = startIdx;
    this.endIndex = endIdx;
    this.pointCount = endIdx - startIdx;
  }

  public Boolean containsIndex(int i) {
    return (i >= startIndex && i <= endIndex);
  }


}
