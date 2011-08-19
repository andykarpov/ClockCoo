/*
 * ClockCoo v1.1
 *
 * Arduino based LCD clock with temperature sensor and bell / coocoo support.
 * Uses Arduino Nano (Atmega328), DS1307 RTC, Dallas 1 wire temperature sensor, 16x2 LCD and SD card module. 
 *
 * Copyright (C) 2011 Andrey Karpov <andy.karpov@gmail.com>
 */

#include <LiquidCrystal.h>
#include <WProgram.h>
#include <Wire.h>
#include <RealTimeClockDS1307.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <WaveBit.h>
#include <WaveUtil.h>
#include "segments.h"

// init LCD
LiquidCrystal lcd(14, 15, 16, 5, 4, 17, 2); // A0, A1, A2, D5, D4, A3, D2

// init temperature sensor
#define ONE_WIRE_BUS 9
OneWire oneWire(ONE_WIRE_BUS);
DallasTemperature sensors(&oneWire);

// init wave playback from SD card
SdReader card;
FatVolume vol;
FatReader root;
FatReader file;
WaveBit wave;

// wave filenames
char file_kuku[13] = "01KUKU.WAV"; // coocoo sound
char file_chime[13] = "02CHIME.WAV"; // westmine chime sound

// pin definitions
#define SPK_PIN 3 // speaker
#define BTN_HOURS_PIN 7 // settings - hours pin
#define BTN_MINUTES_PIN 8 // settings - minutes pin
#define BTN_MODE_PIN 6 // mode pin 

// variables
int seconds; // current seconds
int minutes; // current minutes
int hours; // current hours
float temperature; // current temperature
int x = 0; // current x cursor position (for big digits)
long curTime = 0; // current time (timestamp)
long lastPush = 0; // last pushed settings button (timestamp)
int lastSec = 0; // last second value
boolean dotsOn = false; // current dots on / off flag
int mode = 0; // 0 - time, 1 - temperature, 2 - text mode
int lastMode = 0; // last mode

/*
 * Setup routine
 * @return void
 */
void setup() {

  // set button pins
  pinMode(BTN_HOURS_PIN, INPUT);
  pinMode(BTN_MINUTES_PIN, INPUT);
  pinMode(BTN_MODE_PIN, INPUT);
  
  // turn on internal pullups
  digitalWrite(BTN_HOURS_PIN, HIGH);
  digitalWrite(BTN_MINUTES_PIN, HIGH);
  digitalWrite(BTN_MODE_PIN, HIGH);
  
  // set speaker pin
  pinMode(SPK_PIN, OUTPUT);
  
  // init LCD's rows and colums
  lcd.begin(16, 2);
 
  // assignes each segment a write number
  lcd.createChar(0,SEGMENT_FULL);
  lcd.createChar(1,SEGMENT_HALF_TOP);
  lcd.createChar(2,SEGMENT_HALF_BOTTOM);
  lcd.createChar(3,SEGMENT_MIDDLE1);
  lcd.createChar(4,SEGMENT_MIDDLE2);
  lcd.createChar(5,SEGMENT_DOT_LEFT);
  lcd.createChar(6,SEGMENT_DOT_RIGHT);
  lcd.createChar(7,SEGMENT_CLEAR);

  // one wire temp sensors start
  sensors.begin();
    
  // free ram
  FreeRam(); 
  
  // trying to init SD card
  if (!card.init()) {
    lcd.print("ERR INIT CARD");
    return;
  }
  // enable optimize read - some cards may timeout. 
  card.partialBlockRead(true);
  
  // Now we will look for a FAT partition!
  uint8_t part;
  // we have up to 5 slots to look in
  for (part = 0; part < 5; part++) {   
    if (vol.init(card, part)) 
      // we found one, lets bail
      break;
  }
  
  if (part == 5) {                     
    // if we ended up not finding one  :(
    // Something went wrong, lets print out why
    lcd.print("ERR NO FAT!");
    return;
  }
  
  // Try to open the root directory
  if (!root.openRoot(vol)) {
    // Something went wrong
    lcd.print("Can't open root dir!");
    return;    
  }
}

/*
 * Loop routine
 * @return void;
 */
void loop() { 
  
  // start clock if stopped
  if (RTC.isStopped()) {
    RTC.start();
  }
  
  // read clock values into buffers
  RTC.readClock();
  
  // update seconds / minutes / hours variables
  seconds = RTC.getSeconds();
  minutes = RTC.getMinutes();
  hours = RTC.getHours();
    
  // current (internal) timestamp
  curTime = millis();

  // mode button pressed
  if (digitalRead(BTN_MODE_PIN) == LOW) {
     switchMode(mode);
     delay(100);
     tone(SPK_PIN, 2500, 100);
     delay(100);
  }

  // depends on mode - do different operations
  switch(mode) {
    case 0:
      printTime(hours, minutes); // print time
      processDots(); // blink dots
      processTimeAdjustment(); // check if set time buttons pressed and adjust time
    break;
    case 1:
      // read temperature
      sensors.requestTemperatures();
      temperature = sensors.getTempCByIndex(0);
      printTemperature(temperature); // print temparature
    break;
    case 2:
      // read temperature
      sensors.requestTemperatures();
      temperature = sensors.getTempCByIndex(0);
      printTextInfo(); // print both time and temperature in text mode
      //processTimeAdjustment();
    break;
  }

  // check if need to play a sound and play it
  // in any mode
  processSounds();
  
  // just a small delay
  delay(200);
}

/**
 * Switch output mode
 * @param int m
 * return void
 */
void switchMode(int m) {
  if (m < 2) { 
    m++;
  } else {
    m = 0;
  }
  
  mode = m;
  lcd.clear();
  
  switch (m) {
    // time
    case 0:
      lcd.createChar(5,SEGMENT_DOT_LEFT); 
    break;
    // temperature
    case 1:
      lcd.createChar(5,SEGMENT_DEGREE); 
    break;
    // text mode
    case 2:
      lcd.createChar(5,SEGMENT_DEGREE); 
    break;
  }
}

/**
 * Print current time
 * @param int h
 * @param int m
 * @return void
 */
void printTime(int h, int m) {
  x = 0;
  int digits[2];
  int i = 1;

  for (i=0; i<2; i++) {
    digits[i] = 0;
  }
  
  if (h == 0) {
      printDigit(0);
      printDigit(0);
  } else {
      i = 1;
      while (h > 0) {
          int digit = h % 10;
          digits[i] = digit;
          i = i-1;
          h /= 10;
      }
      for (i=0; i<2; i++) {
         printDigit(digits[i]);
      }
  }
  
  x = x+1;
  
  for (i=0; i<2; i++) {
    digits[i] = 0;
  }
  
  if (m == 0) {
      printDigit(0);
      printDigit(0);
  } else {
      i = 1;
      while (m > 0) {
          int digit = m % 10;
          digits[i] = digit;
          i = i-1;
          m /= 10;
      }
      for (i=0; i<2; i++) {
         printDigit(digits[i]);
      }
  }
}

/**
 * Print current temperature
 * @param float t
 * @return void
 */
void printTemperature(float t) {
  // todo
  int tmp = t * 10;
  
    x = 0;
  int digits[3];
  int i;

  for (i=0; i<3; i++) {
    digits[i] = 0;
  }
  
  if (tmp == 0) {
      printDigit(0);
      printDigit(0);
      printDigit(0);
  } else {
      i = 2;
      while (tmp > 0) {
          int digit = tmp % 10;
          digits[i] = digit;
          i = i-1;
          tmp /= 10;
      }
      for (i=0; i<3; i++) {
         printDigit(digits[i]);
      }
  }
  lcd.setCursor(7,1);
  lcd.print(".");
  lcd.setCursor(11,0);
  lcd.write(5);
  lcd.print("C");
}

/**
 * Print big digit on screen, starting from X position
 * @param int digit
 * @return void
 */
void printDigit(int digit) {
   switch (digit) {
       case 9:
          lcd.setCursor(x,0);
          lcd.write(0);
          lcd.write(3);
          lcd.write(0);
          lcd.setCursor(x, 1);
          lcd.write(4);
          lcd.write(4);
          lcd.write(0);
       break;
       case 8:
          lcd.setCursor(x,0);
          lcd.write(0);
          lcd.write(3);
          lcd.write(0);
          lcd.setCursor(x, 1);
          lcd.write(0);
          lcd.write(4);
          lcd.write(0);
       break;
       case 7:
          lcd.setCursor(x,0);
          lcd.write(1);
          lcd.write(1);
          lcd.write(0);
          lcd.setCursor(x, 1);
          lcd.write(7);
          lcd.write(0);
          lcd.write(7);
       break;
       case 6:
          lcd.setCursor(x,0);
          lcd.write(0);
          lcd.write(3);
          lcd.write(3);
          lcd.setCursor(x, 1);
          lcd.write(0);
          lcd.write(4);
          lcd.write(0);
       break;
       case 5:
          lcd.setCursor(x,0);
          lcd.write(0);
          lcd.write(3);
          lcd.write(3);
          lcd.setCursor(x, 1);
          lcd.write(4);
          lcd.write(4);
          lcd.write(0);
       break;
       case 4:
          lcd.setCursor(x,0);
          lcd.write(0);
          lcd.write(2);
          lcd.write(0);
          lcd.setCursor(x, 1);
          lcd.write(7);
          lcd.write(7);
          lcd.write(0);
       break;
       case 3:
          lcd.setCursor(x,0);
          lcd.write(3);
          lcd.write(3);
          lcd.write(0);
          lcd.setCursor(x, 1);
          lcd.write(4);
          lcd.write(4);
          lcd.write(0);
       break;
       case 2:
          lcd.setCursor(x,0);
          lcd.write(3);
          lcd.write(3);
          lcd.write(0);
          lcd.setCursor(x, 1);
          lcd.write(0);
          lcd.write(4);
          lcd.write(4);
       break;
       case 1:
          lcd.setCursor(x,0);
          lcd.write(1);
          lcd.write(0);
          lcd.write(7);
          lcd.setCursor(x, 1);
          lcd.write(2);
          lcd.write(0);
          lcd.write(2);
       break;
       case 0:
          lcd.setCursor(x, 0); 
          lcd.write(0);  
          lcd.write(1);  
          lcd.write(0);
          lcd.setCursor(x, 1); 
          lcd.write(0);  
          lcd.write(2);  
          lcd.write(0);
       break;
    }
    x = x+4;
}

/**
 * Print or clear time dots
 * @param boolean on
 * @return void
 */
void printDots(boolean on) 
{
  lcd.setCursor(7,0);
  lcd.write((on) ? 5 : 7);
  lcd.write((on) ? 6 : 7);
  lcd.setCursor(7,1);
  lcd.write((on) ? 5 : 7);
  lcd.write((on) ? 6 : 7);
}

/**
 * Play wave file 
 *
 * @param char *name
 * @return void
 */
void playfile(char *name) {
   if (!file.open(root, name)) {
      lcd.clear();
      lcd.setCursor(0,0);
      lcd.print("ERR OPEN FILE");
      return;
   }
   if (!wave.create(file)) {
      lcd.clear();
      lcd.setCursor(0,0);
      lcd.print("ERR OPEN WAV");
      return;
   }
   wave.play();
   while(wave.isplaying) {
      delay(100);
   }
   digitalWrite(SPK_PIN, LOW);
}

/**
 * Check if need to play a sounds (every 15 minutes) and play them
 * @return void
 */
void processSounds() {
    if ((hours >= 8 && hours <= 21) && (minutes % 15 == 0) && (seconds == 0) && (curTime-lastPush > 5000)) {

      // every hour play N times coo-cooo
      // and say time after that
      if (minutes == 0) {
        int times = hours;
        if(times > 12) {
          times = times - 12;
        }
        while (times > 0) {
           playfile(file_kuku);
           times--;
        }
        char filename[12];
        sprintf(filename, "%d.WAV", hours);
        playfile(filename);
     
     } 
     // every 15 minutes play chime
     else if (hours < 21) {
       playfile(file_chime);
     }

  }
}

/**
 * Check if need to show or hide time dots (every second)
 * @return void
 */
void processDots() {
    if (lastSec != seconds) {
      dotsOn = !dotsOn; 
      if (mode == 0) {
        printDots(dotsOn);
      }
        lastSec = seconds;
    }
}

/**
 * Check if time adjustment buttons pressed and adjust time
 * @return void
 */
void processTimeAdjustment() {
  // hours buttons pressed
  if (digitalRead(BTN_HOURS_PIN) == LOW) {
    hours++;
    if (hours > 23) hours = 0;
    RTC.setHours(hours);
    RTC.setClock();
    lastPush = curTime;
  }
  // minutes button pressed
  if (digitalRead(BTN_MINUTES_PIN) == LOW) {
    minutes++;
    if (minutes > 59) minutes = 0;
    RTC.setMinutes(minutes);
    RTC.setClock();
    lastPush = curTime;
  }
}

/**
 * Print temperature and time in text format
 *
 * @return void
 */
void printTextInfo() {
  lcd.setCursor(0,0);
  lcd.print("Time: ");
  if (hours < 10) lcd.print("0");
  lcd.print(hours);
  lcd.print(":");
  if (minutes < 10) lcd.print("0");
  lcd.print(minutes);
  lcd.print(":");
  if (seconds < 10) lcd.print("0");
  lcd.print(seconds);
  
  lcd.setCursor(0,1);
  lcd.print("Temp: ");
  lcd.print(temperature);
  lcd.print(" ");
  lcd.write(5);
  lcd.print("C");
}
