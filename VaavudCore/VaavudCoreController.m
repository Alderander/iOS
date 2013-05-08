//
//  vaavudCoreController.m
//  VaavudCore
//
//  Created by Andreas Okholm on 5/8/13.
//  Copyright (c) 2013 Andreas Okholm. All rights reserved.
//

#import "VaavudCoreController.h"
#import <CoreMotion/CoreMotion.h>

@interface VaavudCoreController ()

@property (nonatomic, strong) NSMutableArray *magneticFieldReadings;
@property (nonatomic) float windSpeed;
@property (nonatomic) float windDirection;
@property (nonatomic) float windSpeedMax;

- (void) startMagneticFieldSensor;

@end

@implementation VaavudCoreController {
    CMMotionManager *motionManager;
    NSOperationQueue *operationQueue;
}

@synthesize magneticFieldReadings;
@synthesize windSpeed;
@synthesize windDirection;
@synthesize windSpeedMax;


// Public methods

- (id) init
{
    self = [super init];
    
    if (self)
    {
        // Do initializing
        
    }
    
    return self;
    
}

- (void) start
{
    [self startMagneticFieldSensor];
}

- (void) stop
{
    [motionManager stopMagnetometerUpdates];
    motionManager = nil;
}


- (void) remove
{
    
}


// Private methods
- (void) startMagneticFieldSensor
{
 
    motionManager = [[CMMotionManager alloc] init];
    
    if (motionManager.magnetometerAvailable) {
        motionManager.magnetometerUpdateInterval = 1.0/preferedSampleFrequency;
        operationQueue = [NSOperationQueue currentQueue];
        [motionManager startMagnetometerUpdatesToQueue:operationQueue withHandler:^(CMMagnetometerData *magnetometerData, NSError *error) {
            CMMagneticField magneticField = magnetometerData.magneticField;
            
//            [self updateDisplay:field];
//            
//            if (isLogging) {
//                double time = CACurrentMediaTime();
//                
//                if (counter == 0)
//                    startTime = time;
//                [self logSet:field andTime:time];
//            }
            
            NSLog( @"magnetic field reading x: %f", magneticField.x);
            
        }];
        
    }  else {
        NSLog(@"No MagnetometerAvailable on device.");
    }

    
}


@end