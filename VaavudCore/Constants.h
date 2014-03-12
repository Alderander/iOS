//
//  Constants.h
//  VaavudCore
//
//  Created by Andreas Okholm on 5/8/13.
//  Copyright (c) 2013 Andreas Okholm. All rights reserved.
//

#define APP "Vaavud"

#define preferedSampleFrequency 100 // actual is arround 63 
#define accAndGyroSampleFrequency 5
#define FFTForEvery 3

// Thresholds for isValid
#define accelerationMaxForValid 0.4 // g acc/(9.82 m/s^2)
#define angularVelocityMaxForValid 0.4 // rad/s (maybe deg/s or another unit)
#define orientationDeviationMaxForValid 0.63 // rad  (36) degrees
#define FFTpeakMagnitudeMinForValid 5 // (abs(FFT(maxbin))

// Threshold for valid measurement
#define minimumNumberOfSeconds 30

// Only save every Nth measurement point - set to 1 to save all
#define saveEveryNthPoint 10

#define BUTTON_CORNER_RADIUS 4
#define FORM_CORNER_RADIUS 4

#define SYSTEM_VERSION_EQUAL_TO(v)                  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN(v)              ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedDescending)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v)                 ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)

static int const ALGORITHM_STANDARD = 0;
static int const ALGORITHM_IPHONE4 = 1;

static double const STANDARD_FREQUENCY_START = 0.238;
static double const STANDARD_FREQUENCY_FACTOR = 1.07;

static double const I4_FREQUENCY_START = 0.238;
static double const I4_FREQUENCY_FACTOR = 1.16;

static double const I5_FREQUENCY_START = 0.238;
static double const I5_FREQUENCY_FACTOR = 1.04;

static int const FQ40_FFT_LENGTH = 64;
static int const FQ40_FFT_DATA_LENGTH = 50;

static int const FQ60_FFT_LENGTH = 128;
static int const FQ60_FFT_DATA_LENGTH = 80;

static BOOL const LOGOUT_ENABLED = NO;

static NSString * const GOOGLE_STATIC_MAPS_API_KEY = @"AIzaSyDrrZsMKRBkCw214SbJA6q2lO-cXbu7m0Y";

//static NSString * const vaavudAPIBaseURLString = @"http://192.168.0.105:8080/";
//static NSString * const vaavudAPIBaseURLString = @"http://10.117.1.42:8080/";
static NSString * const vaavudAPIBaseURLString = @"https://mobile-api.vaavud.com/";
