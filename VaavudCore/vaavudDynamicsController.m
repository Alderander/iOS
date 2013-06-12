//
//  vaavudDynamicsController.m
//  VaavudCore
//
//  Created by Andreas Okholm on 5/19/13.
//  Copyright (c) 2013 Andreas Okholm. All rights reserved.
//
//  Check if abs(acceleration) & device orientation & gyroscope is below theshold values
//

#import "vaavudDynamicsController.h"
#import <CoreMotion/CoreMotion.h>



@interface vaavudDynamicsController ()

    @property (nonatomic, strong) CMMotionManager *motionManager;
    @property (nonatomic, strong) NSOperationQueue *operationQueue;
    @property (nonatomic) BOOL accelerationIsValid;
    @property (nonatomic) BOOL orientationIsValid;
    @property (nonatomic) BOOL angularVeclocityIsValid;

    @property (nonatomic, strong) CLLocationManager *locationManager;

    - (void) updateValidity;

@end

@implementation vaavudDynamicsController

- (id) init
{
    self = [super init];
    
    if (self)
    {
        // Do initializing
        
        self.accelerationIsValid = YES;
        self.angularVeclocityIsValid = YES;
        self.orientationIsValid = YES;
        
    }
    
    return self;
    
}


- (void) updateValidity
{
    if (self.accelerationIsValid && self.orientationIsValid && self.angularVeclocityIsValid)
        self.isValid = YES;
    else
        self.isValid = NO;
    
    [self.vaavudCoreController DynamicsIsValid:self.isValid];
}



- (void) start
{
    self.motionManager = [[CMMotionManager alloc] init];
    
    if (self.motionManager.deviceMotionAvailable) {
        self.motionManager.deviceMotionUpdateInterval = 1.0/accAndGyroSampleFrequency;
        
        if(!self.operationQueue)
            self.operationQueue = [NSOperationQueue currentQueue];
        
        [self.motionManager startDeviceMotionUpdatesToQueue:self.operationQueue withHandler:^(CMDeviceMotion *motion, NSError *error) {
            
            
            // Orientation
            double deviceDeviationFromVertical =  M_PI/2 - fabs(motion.attitude.pitch);
            
            if ( deviceDeviationFromVertical > orientationDeviationMaxForValid ) {
                self.orientationIsValid = NO;
                NSLog(@"Orientation deviation from vertical is too big with value %f", deviceDeviationFromVertical);
            } else {
                self.orientationIsValid = YES;
            }
            
            // angular velocity
            double angularVelocity = fabs( sqrt( pow(motion.rotationRate.x, 2) + pow(motion.rotationRate.x, 2) + pow(motion.rotationRate.x, 2)));
            
            if (angularVelocity > angularVelocityMaxForValid) {
                self.angularVeclocityIsValid = NO;
                NSLog(@"Angular velocity is too big with value %f ", angularVelocity);
            } else
                self.angularVeclocityIsValid = YES;

            
            // acceleration
            
            double acceleration = fabs( sqrt( pow(motion.userAcceleration.x, 2) + pow(motion.userAcceleration.y,2) + pow(motion.userAcceleration.z,2) ) );
            
            if (acceleration > accelerationMaxForValid ) {
                self.accelerationIsValid = NO;
                NSLog(@"Acceleration is too big with value %f", acceleration);
            }
            else {
                self.accelerationIsValid = YES;
            }
            
            
            [self updateValidity];

            
        }];
        
    }
    
    if ([CLLocationManager headingAvailable])
    {
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.delegate = self;
        self.locationManager.headingFilter = 1;
        [self.locationManager startUpdatingHeading];
    } else
    {
        NSLog(@"No heading avaliable!!!");
    }
    
}

- (void) stop
{
    [self.motionManager stopDeviceMotionUpdates];
    self.motionManager = nil;
    self.operationQueue = nil;
    [self.locationManager stopUpdatingHeading];
}


// Heading

- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading
{
    [self.vaavudCoreController newHeading: [NSNumber numberWithDouble: newHeading.trueHeading]];
    
//    NSLog(@"heading accuracy: %f", newHeading.headingAccuracy);
}

@end