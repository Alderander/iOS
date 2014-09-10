//
//  vaavudCoreController.h
//  VaavudCore
//
//  Created by Andreas Okholm on 5/8/13.
//  Copyright (c) 2013 Andreas Okholm. All rights reserved.
//

@protocol MjolnirMeasurementControllerDelegate <NSObject>

- (void) addSpeedMeasurement:(NSNumber*)currentSpeed avgSpeed:(NSNumber*)avgSpeed maxSpeed:(NSNumber*)maxSpeed;
- (void) measuringStoppedByModel;
- (void) temperatureUpdated:(float)temperature;

@optional
- (void) changedValidity:(BOOL)isValid dynamicsIsValid:(BOOL)dynamicsIsValid;

@end

#import <Foundation/Foundation.h>
#import "VaavudMagneticFieldDataManager.h"
#import "vaavudDynamicsController.h"

@interface MjolnirMeasurementController : NSObject <VaavudMagneticFieldDataManagerDelegate, vaavudDynamicsControllerDelegate>

- (id) init;
- (void) start;
- (NSTimeInterval) stop;
- (void) remove;
- (NSNumber *) getAverage;
- (NSNumber *) getMax;
- (NSNumber *) getProgress;

@property (nonatomic) BOOL lookupTemperature;

@property (readonly, nonatomic, strong) NSNumber *setWindDirection;
@property (readonly, nonatomic, strong) NSMutableArray *windSpeed;
@property (readonly, nonatomic, strong) NSMutableArray *isValid;
@property (readonly, nonatomic, strong) NSMutableArray *windSpeedTime;
@property (readonly, nonatomic, strong) NSMutableArray *windDirection;
@property (readonly, nonatomic, strong) NSDate *startTime;
@property (nonatomic) BOOL upsideDown;
@property (readonly, nonatomic) int fftLength;
@property (readonly, nonatomic) int fftDataLength;

@property (nonatomic) BOOL dynamicsIsValid;
@property (nonatomic) BOOL windDirectionIsConfirmed;
@property (nonatomic) BOOL FFTisValid;
@property (nonatomic) BOOL isValidCurrentStatus;

@property (nonatomic, strong) NSNumber *currentLatitude;
@property (nonatomic, strong) NSNumber *currentLongitude;

@property (nonatomic, weak) id <MjolnirMeasurementControllerDelegate> delegate;

@end