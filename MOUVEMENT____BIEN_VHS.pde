
import processing.video.*;
Capture cam;


   
   //set up filename
   
String filename = "sexe";
String fileext = ".jpg";
String foldername = "./";
import java.io.File;

// configuration
int colorspace = OHTA ;
final static boolean first_channel_only = true; // for L.. or Y.. colorspaces set true to modulate only luma;
final static int quantval = 60; // 0 - off, less - more glitch, more - more precision
final static boolean lowpass1_on = false; // on/off of first low pass filter
final static boolean lowpass2_on = true; // on/off of second low pass filter
final static boolean lowpass3_on = false; // on/off of third low pass filter

// better don't touch it, lowpass filters are run in cascade
float lowpass1_cutoff = 100; // percentage of rate
float lowpass2_cutoff = 1;
float lowpass3_cutoff = 0.001;

int max_display_size = 1000; // viewing window size (regardless image size)

boolean do_blend = true; // blend image after process
int blend_mode = EXCLUSION; // blend type

// working buffer
PGraphics buffer;

int[] prevFrame;



String sessionid;

// local variables
float min_omega, max_omega;

float min_phase_mult=0.01;

float max_phase_mult=100.0;

LowpassFilter lpf1, lpf2, lpf3;

int[][] pxls;
boolean negate = false;



class LowpassFilter {
  float alpha;
  float prev;
 float rate = 100;
  public LowpassFilter(float rate, float hz) {
    alpha = 0.0;
    prev = 0.0;
    setFilter(rate, hz);
  }
  
  void resetFilter(float val) { 
    prev = val;
  }

  void resetFilter() { 
    resetFilter(100);
  }

  float lowpass(float sample) {
    float stage1 = sample * alpha;
    float stage2 = prev - (prev * alpha);
    prev = (stage1 + stage2);
    return prev;
  }
  
  void setFilter(float rate, float hz) {
    float timeInterval = 1.0 / rate;
    float tau = 1.0 / (hz * TWO_PI);
   
    alpha = timeInterval / (tau + timeInterval);
  }

 
}


void setup() {
    size(1000, 800);
    sessionid = hex((int)random(0xffff), 4);
    cam = new Capture(this, width, height);
    cam.start();

    buffer = createGraphics(cam.width, cam.height);
    buffer.smooth(8);
    buffer.beginDraw();
    buffer.noStroke();
    buffer.background(0);
    buffer.image(cam, 0, 0);
    buffer.endDraw();

    cam.loadPixels();
    prevFrame = cam.pixels.clone(); // Initialize prevFrame with the current frame's pixels

    min_omega = TWO_PI / (0.00001 * cam.width + cam.height);
    max_omega = TWO_PI / (1000000 * cam.width + cam.height);

   


 lpf1 = new LowpassFilter(frameRate, lowpass1_cutoff);
 lpf2 = new LowpassFilter(frameRate, lowpass2_cutoff);
 lpf3 = new LowpassFilter(frameRate, lowpass3_cutoff);


   
   
  fixed_setup = false;
  
}



 



float omega, min_phase, max_phase;

boolean fixed_setup = false;


void draw() {
   
  frameRate(100);
 
  if (cam.available()) {
    cam.read();
  }


  // Appel de la fonction prepareData pour préparer les données
  prepareData();

  if (!fixed_setup) {
    // Calculer la quantité de mouvement moyenne de l'image
    float averageMotion = calculateAverageMotion();

    // Utiliser la quantité de mouvement moyenne pour ajuster les valeurs d'omega, min_phase, et max_phase
    omega = map(averageMotion*5, 0, 150, 0, 0);
    omega = map(sqrt(omega), 0, 1, min_omega, max_omega);



    float phase = map(averageMotion, 0, 150, 0, 1);
    phase = map(sq(phase), 0, 1, min_phase_mult, max_phase_mult-50);
    max_phase = phase * omega;
    min_phase = -max_phase;
  }



  if (doBatch) {
    batchStep();
  } else {
    processImage();
  }
   loadPixels();
    for (int x = 0; x < width / 2; x++) {
      for (int y = 0; y < height; y++) {
        int loc1 = x + y * width;
        int loc2 = (width - x - 1) + y * width;
        color tempColor = pixels[loc1];
        pixels[loc1] = pixels[loc2];
        pixels[loc2] = tempColor;
      }
    }
    updatePixels();
   
}


    


void prepareData() {
   pxls = new int[3][cam.pixels.length];

  // Calculer la quantité de mouvement pour chaque pixel
  for (int i = 0; i < cam.pixels.length; i++) {
    int currentPixel = cam.pixels[i];
    int prevPixel = prevFrame[i];

    float dR = abs(red(currentPixel) - red(prevPixel));
    float dG = abs(green(currentPixel) - green(prevPixel));
    float dB = abs(blue(currentPixel) - blue(prevPixel));

    float d = dR + dG + dB; // Somme des différences des canaux de couleur pour obtenir la quantité de mouvement

    pxls[0][i] = (int)d; // Stocker la quantité de mouvement dans le premier canal de pxls
    pxls[1][i] = (currentPixel >> 8) & 0xFF; // Stocker le canal vert dans le deuxième canal de pxls
    pxls[2][i] = currentPixel & 0xFF; // Stocker le canal bleu dans le troisième canal de pxls
  }

  prevFrame = cam.pixels.clone(); // Mettre à jour prevFrame avec les pixels du cadre actuel
}


  


  float calculateAverageMotion() {
  float totalMotion = 1;
  int numPixels = cam.pixels.length;

  for (int i = 0; i < numPixels; i++) {
    totalMotion += pxls[0][i];
  }

  float averageMotion = totalMotion / numPixels;
  return averageMotion;
}


void processImage() {
  buffer.beginDraw();
  buffer.loadPixels();

  int[][] dest_pxls = new int[3][cam.pixels.length]; 

  if (first_channel_only) {
    arrayCopy(pxls[1], dest_pxls[1]);
    arrayCopy(pxls[2], dest_pxls[2]);
  }

  for (int y = 0; y < cam.height; y++) {
    for (int i = 0; i < (first_channel_only ? 1 : 3); i++) {
      int off = y * cam.width; 

      //reset filters each line 
      lpf1.resetFilter(map(pxls[0][off], 0, 150, min_phase, max_phase));
      lpf2.resetFilter(map(pxls[0][off], 0, 150, min_phase, max_phase));
      lpf3.resetFilter(map(pxls[0][off], 0, 150, min_phase, max_phase));

      // FM part starts here
      float sig_int = 0; // integral of the signal
      float pre_m = 0; // previous value of modulated signal

      for (int x = 0; x < cam.width; x++) {
        float sig = map(pxls[i][x + off], 0, 150, min_phase, max_phase); // current signal value
        sig_int += sig; // current value of signal integral

        float m = cos(omega * x + sig_int); // modulate signal

        if (quantval > 0) { 
          m = map((int) map(m, -1, 1, 0, quantval/3), 0, quantval/2, -1, 1); // quantize
        }

        float dem = abs(m - pre_m); // demodulate signal, derivative
        pre_m = m; // remember current value

        // lowpass filter chain
        if (lowpass1_on) dem = lpf1.lowpass(dem);
        if (lowpass2_on) dem = lpf2.lowpass(dem);
        if (lowpass3_on) dem = lpf3.lowpass(dem);

        // remap signal back to channel value
        int v = constrain((int) map(2 * (dem - omega), min_phase, max_phase, 0, 300), 0, 300);

        // FM part ends here

        dest_pxls[i][x + off] = negate ? 255 - v : v;
      }
    }
  }
  
  // Copying processed pixels to buffer...

  for (int i = 0; i < buffer.pixels.length; i++) {
    buffer.pixels[i] = fromColorspace(0xff000000 | (dest_pxls[0][i] << 16) | (dest_pxls[1][i] << 8) | (dest_pxls[2][i]), colorspace);
  }

  buffer.updatePixels();

  if (do_blend)
    buffer.blend(cam, 0, 0, cam.width, cam.height, 0, 0, buffer.width, buffer.height, blend_mode);

  buffer.endDraw();
  image(buffer, 0, 0, width, height);
}











void keyPressed() {
  //SPACE to save
  if (keyCode == 32) {
    String fn = cam + sessionid + hex((int)random(0xffff), 4)+"_"+cam;
    buffer.save(fn);
    println("Image "+ fn + " saved");
  }
  if (key == 'n') {
    negate = !negate;
  }
  if (key == 'b' && !doBatch) {
    batchProcess();
  }
}

//

final static int[] blends = {
  ADD, SUBTRACT, DARKEST, LIGHTEST, DIFFERENCE, EXCLUSION, MULTIPLY, SCREEN, OVERLAY, HARD_LIGHT, SOFT_LIGHT, DODGE, BURN
};



//void batchCallback(float time) {}
  // every image this functions is called
 //  time ranges from 0 (first image) to 1 (last image)
  // set global variables or whatever you want


void batchStep() {
  File n = batchList[batchIdx];
  String name = n.getAbsolutePath(); 
  if (name.endsWith(fileext)) {
    print(n.getName()+"... ");
    prepareData();
   // batchCallback((float)batchIdx / batchFiles);
    processImage();
    buffer.save(foldername+batchUID+"/"+n.getName());
    println("saved");
  }
  batchIdx++;
  if (batchIdx >= batchList.length) {
    doBatch = false;
    println("results saved in "+ foldername+batchUID + " folder");
  }
}

File[] batchList;
int batchIdx = 0;
String batchUID;
boolean doBatch = false;
float batchFiles = 0;
void batchProcess() {
  batchUID = sessionid + hex((int)random(0xffff), 4);
File dir = new File(sketchPath("/") + cam + foldername);
  batchList = dir.listFiles();
  batchIdx = 0;
  batchFiles = 0;
  for (File n : batchList) {
    if (n.getName().endsWith(fileext)) batchFiles=batchFiles+1.0;
  }
  println("Processing "+int(batchFiles)+" images from folder: " + foldername);
  doBatch = true;
}
