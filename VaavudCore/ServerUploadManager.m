//
//  ServerUploadManager.m
//  Vaavud
//
//  Created by Thomas Stilling Ambus on 19/06/2013.
//  Copyright (c) 2013 Andreas Okholm. All rights reserved.
//

#define consecutiveNetworkErrorBackOffThreshold 3
#define networkErrorBackOff 10
#define graceTimeBetweenDidBecomeActiveTasks 3600.0
#define uploadInterval 10
#define GRACE_TIME_BETWEEN_HISTORY_SYNC 60.0

#import "ServerUploadManager.h"
#import "SharedSingleton.h"
#import "MeasurementSession+Util.h"
#import "VaavudAPIHTTPClient.h"
#import "Property+Util.h"
#import "AFHTTPRequestOperation.h"
#import "AlgorithmConstantsUtil.h"
#import "UUIDUtil.h"
#import "AccountManager.h"
#import "Mixpanel.h"
#import "DictionarySerializationUtil.h"

@interface ServerUploadManager () {
}

@property(nonatomic) NSTimer *syncTimer;
@property(nonatomic) BOOL hasReachability;
@property(nonatomic) NSDate *lastDidBecomeActive;
@property(nonatomic) BOOL justDidBecomeActive;
@property(nonatomic) BOOL hasRegisteredDevice;
@property(nonatomic) int consecutiveNetworkErrors;
@property(nonatomic) int backoffWaitCount;
@property (nonatomic) NSDate *lastHistorySync;
@property(nonatomic) BOOL isHistorySyncInProgress;

@end

@implementation ServerUploadManager

SHARED_INSTANCE

- (id) init {
    self = [super init];
    
    if (self) {
        self.consecutiveNetworkErrors = 0;
        self.backoffWaitCount = 0;
        self.hasReachability = NO;
        self.justDidBecomeActive = YES;
        self.hasRegisteredDevice = NO;

        // initialize HTTP client
        [[VaavudAPIHTTPClient sharedInstance] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status){
            /*
             AFNetworkReachabilityStatusUnknown          = -1,
             AFNetworkReachabilityStatusNotReachable     = 0,
             AFNetworkReachabilityStatusReachableViaWWAN = 1,
             AFNetworkReachabilityStatusReachableViaWiFi = 2,
             */
            NSLog(@"[ServerUploadManager] Reachability status changed to: %d", status);

            if (status == 1 || status == 2) {
                self.hasReachability = YES;
                [self handleDidBecomeActiveTasks];
            }
            else {
                self.hasReachability = NO;
            }
        }];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillTerminate:) name:UIApplicationWillTerminateNotification object:nil];
    }
    
    return self;
}

- (void) start {
    self.syncTimer = [NSTimer scheduledTimerWithTimeInterval:uploadInterval target:self selector:@selector(checkForUnUploadedData) userInfo:nil repeats:YES];
}

// notification from the OS
- (void) appDidBecomeActive:(NSNotification*) notification {
    //NSLog(@"[ServerUploadManager] appDidBecomeActive");
    self.justDidBecomeActive = YES;
    [self handleDidBecomeActiveTasks];
}

// notification from the OS
-(void) appWillTerminate:(NSNotification*) notification {
    NSLog(@"[ServerUploadManager] appWillTerminate");
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillTerminateNotification object:nil];
}

// this is triggered by the OS informing us that the app did become active or AFNetworking telling us that reachability has changed to YES and we haven't yet executed these tasks after becoming active. Thus, if we don't have reachability when becoming active, these tasks are postponed until reachability changes to YES.
- (void) handleDidBecomeActiveTasks {
    
    if (self.lastDidBecomeActive && self.lastDidBecomeActive != nil) {
        NSTimeInterval howRecent = [self.lastDidBecomeActive timeIntervalSinceNow];
        if (abs(howRecent) < graceTimeBetweenDidBecomeActiveTasks) {
            NSLog(@"[ServerUploadManager] ignoring did-become-active due to grace period");

            self.justDidBecomeActive = NO;
        }
    }

    if (self.justDidBecomeActive == NO || self.hasReachability == NO) {
        return;
    }
    
    //NSLog(@"[ServerUploadManager] Handle did-become-active tasks");
    self.justDidBecomeActive = NO;
    self.lastDidBecomeActive = [NSDate date];

    // tasks to do follow here...
    
    // since it's awhile since we last tried to upload, clear network error counts
    self.consecutiveNetworkErrors = 0;
    self.backoffWaitCount = 0;

    // register device
    [self registerDevice];
}

- (void) triggerUpload {
    //NSLog(@"[ServerUploadManager] Trigger upload");
    [self checkForUnUploadedData];
}

- (void) checkForUnUploadedData {
    
    //NSLog(@"[ServerUploadManager, %@] checkForUnUploadedData", [NSThread currentThread]);
    
    if (!self.hasReachability) {
        return;
    }
    
    if (self.consecutiveNetworkErrors >= consecutiveNetworkErrorBackOffThreshold) {
        self.backoffWaitCount++;
        if (self.backoffWaitCount % networkErrorBackOff != 0) {
            //NSLog(@"[ServerUploadManager] Backing off due to %d consecutive network errors, wait count is %d", self.consecutiveNetworkErrors, self.backoffWaitCount);
            return;
        }
    }

    // if we didn't successfully call register device yet, do this instead of uploading
    if (self.hasRegisteredDevice == NO) {
        [self registerDevice];
        return;
    }
    
    NSArray *unuploadedMeasurementSessions = [MeasurementSession MR_findByAttribute:@"uploaded" withValue:[NSNumber numberWithBool:NO]];

    if (unuploadedMeasurementSessions && [unuploadedMeasurementSessions count] > 0) {
        
        //NSLog(@"[ServerUploadManager] Found %d un-uploaded MeasurementSessions", [unuploadedMeasurementSessions count]);
        
        for (MeasurementSession *measurementSession in unuploadedMeasurementSessions) {

            NSNumber *pointCount = [NSNumber numberWithUnsignedInteger:[measurementSession.points count]];

            //NSLog(@"[ServerUploadManager] Found non-uploaded MeasurementSession with uuid=%@, startTime=%@, startIndex=%@, endIndex=%@, pointCount=%@", measurementSession.uuid, measurementSession.startTime, measurementSession.startIndex, measurementSession.endIndex, pointCount);

            if ([measurementSession.measuring boolValue] == YES) {
                
                // if an unuploaded 
                NSTimeInterval howRecent = [measurementSession.endTime timeIntervalSinceNow];
                if (abs(howRecent) > 60.0 * 10.0) {
                    //NSLog(@"[ServerUploadManager] Found old MeasurementSession (%@) that is still measuring - setting it to not measuring", measurementSession.uuid);
                    // TODO: we ought to force the controller to stop if it is still in started mode. Or should we remove this altogether?
                    measurementSession.measuring = [NSNumber numberWithBool:NO];
                    [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreWithCompletion:nil];
                }
            }
            
            if ([measurementSession.startIndex intValue] == [pointCount intValue] && ([pointCount intValue] > 0 || [measurementSession.measuring boolValue] == NO)) {

                if ([measurementSession.measuring boolValue] == NO) {
                    //NSLog(@"[ServerUploadManager] Found MeasurementSession (%@) that is not measuring and has no new points, so setting it as uploaded", measurementSession.uuid);
                    measurementSession.uploaded = [NSNumber numberWithBool:YES];
                    [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreWithCompletion:nil];
                }
                else {
                    //NSLog(@"[ServerUploadManager] Found MeasurementSession that is not uploaded, is still measuring, but has no new points, so skipping");
                }
            }
            else {
                
                //NSLog(@"[ServerUploadManager] Uploading MeasurementSession (%@)", measurementSession.uuid);
                
                NSNumber *newEndIndex = pointCount;
                NSString *uuid = measurementSession.uuid;
                measurementSession.endIndex = newEndIndex;

                NSDictionary *parameters = [measurementSession toDictionary];
                
                [[VaavudAPIHTTPClient sharedInstance] postPath:@"/api/measure" parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
                    
                    NSLog(@"[ServerUploadManager] Got successful response uploading");
                    
                    // clear consecutive errors since we got a successful reponse
                    self.consecutiveNetworkErrors = 0;
                    self.backoffWaitCount = 0;
                    
                    // lookup MeasurementSession again since it might have changed while uploading
                    MeasurementSession *msession = [MeasurementSession MR_findFirstByAttribute:@"uuid" withValue:uuid];
                    msession.startIndex = newEndIndex;
                    [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreWithCompletion:nil];
                    
                } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                    long statusCode = (long)operation.response.statusCode;
                    NSLog(@"[ServerUploadManager] Got error status code %ld uploading: %@", statusCode, error);
                    
                    self.consecutiveNetworkErrors++;

                    // check for unauthorized
                    if (statusCode == 401) {
                        // try to re-register
                        self.hasRegisteredDevice = NO;
                    }
                }];
                
                // stop iterating since we did process a measurement session to ensure that we don't spam the server in case the user has a lot of unuploaded measurement sessions
                break;
            }
        }
    }
    else {
        //NSLog(@"[ServerUploadManager] Found no uploading MeasurementSession");
    }
}

- (void) registerDevice {

    NSLog(@"[ServerUploadManager] Register device");
    self.hasRegisteredDevice = NO;

    NSDictionary *parameters = [Property getDeviceDictionary];
    
    [[VaavudAPIHTTPClient sharedInstance] postPath:@"/api/device/register" parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        //NSLog(@"[ServerUploadManager] Got successful response registering device");
        self.hasRegisteredDevice = YES;
        
        // clear consecutive errors since we got a successful reponse
        self.consecutiveNetworkErrors = 0;
        self.backoffWaitCount = 0;

        // remember the authToken we got from the server as response
        NSString *authToken = [responseObject objectForKey:@"authToken"];
        if (authToken && authToken != nil && authToken != (id)[NSNull null] && ([authToken length] > 0)) {
            //NSLog(@"[ServerUploadManager] Got authToken");
            [Property setAsString:authToken forKey:KEY_AUTH_TOKEN];
            [[VaavudAPIHTTPClient sharedInstance] setAuthToken:authToken];
        }
        else {
            NSLog(@"[ServerUploadManager] Got no authToken");
        }
        
        // set algorithm parameters
        
        NSString *algorithm = [responseObject objectForKey:@"algorithm"];
        if (algorithm && algorithm != nil && algorithm != (id)[NSNull null] && ([algorithm length] > 0)) {
            [Property setAsInteger:[AlgorithmConstantsUtil getAlgorithmFromString:algorithm] forKey:KEY_ALGORITHM];
        }
        
        NSNumber *frequencyStart = [self doubleValue:responseObject forKey:@"frequencyStart"];
        if (frequencyStart != nil) {
            [Property setAsDouble:frequencyStart forKey:KEY_FREQUENCY_START];
        }

        NSNumber *frequencyFactor = [self doubleValue:responseObject forKey:@"frequencyFactor"];
        if (frequencyFactor != nil) {
            [Property setAsDouble:frequencyFactor forKey:KEY_FREQUENCY_FACTOR];
        }

        NSNumber *fftLength = [self integerValue:responseObject forKey:@"fftLength"];
        if (fftLength != nil) {
            [Property setAsInteger:fftLength forKey:KEY_FFT_LENGTH];
        }

        NSNumber *fftDataLength = [self integerValue:responseObject forKey:@"fftDataLength"];
        if (fftDataLength != nil) {
            [Property setAsInteger:fftDataLength forKey:KEY_FFT_DATA_LENGTH];
        }

        NSNumber *analyticsGridDegree = [self doubleValue:responseObject forKey:@"analyticsGridDegree"];
        if (analyticsGridDegree != nil) {
            [Property setAsDouble:analyticsGridDegree forKey:KEY_ANALYTICS_GRID_DEGREE];
        }
        
        NSArray *hourOptions = [responseObject objectForKey:@"hourOptions"];
        if (hourOptions != nil && hourOptions.count > 0) {
            [Property setAsFloatArray:hourOptions forKey:KEY_HOUR_OPTIONS];
        }
        
        NSString *enableMixpanel = [responseObject objectForKey:@"enableMixpanel"];
        if (enableMixpanel && enableMixpanel != nil && enableMixpanel != (id)[NSNull null] && ([enableMixpanel length] > 0)) {
            [Property setAsBoolean:[@"true" isEqualToString:enableMixpanel] forKey:KEY_ENABLE_MIXPANEL];
        }

        NSString *enableFacebookDisclaimer = [responseObject objectForKey:@"enableFacebookDisclaimer"];
        if (enableFacebookDisclaimer && enableFacebookDisclaimer != nil && enableFacebookDisclaimer != (id)[NSNull null] && ([enableFacebookDisclaimer length] > 0)) {
            [Property setAsBoolean:[@"true" isEqualToString:enableFacebookDisclaimer] forKey:KEY_ENABLE_FACEBOOK_DISCLAIMER];
        }

        NSNumber *creationTimeMillis = [responseObject objectForKey:@"creationTime"];
        if (creationTimeMillis && [Property getAsDate:KEY_CREATION_TIME] == nil) {
            NSDate *creationTime = [NSDate dateWithTimeIntervalSince1970:([creationTimeMillis doubleValue] / 1000.0)];
            [Property setAsDate:creationTime forKey:KEY_CREATION_TIME];
            if ([Property isMixpanelEnabled]) {
                [[Mixpanel sharedInstance] registerSuperPropertiesOnce:@{@"Creation Time": creationTime}];
            }
        }
        
        // only trigger upload once we get OK from server for registering device, otherwise the device could be unregistered when uploading
        [self triggerUpload];
        
        [self syncHistory:1 ignoreGracePeriod:YES success:nil failure:nil];

    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        long statusCode = (long)operation.response.statusCode;
        NSLog(@"[ServerUploadManager] Got error status code %ld registering device: %@", statusCode, error);
        self.hasRegisteredDevice = NO;
        self.consecutiveNetworkErrors++;
        
        // check for unauthorized
        if (statusCode == 401) {
            // Unauthorized most likely means that a user is associated with this device and the authToken has been changed or invalidated
            // server-side.
            [[AccountManager sharedInstance] logout];
        }
    }];
}

-(void) registerUser:(NSString*)action email:(NSString*)email passwordHash:(NSString*)passwordHash facebookId:(NSString*)facebookId facebookAccessToken:(NSString*)facebookAccessToken firstName:(NSString*)firstName lastName:(NSString*)lastName gender:(NSNumber*)gender verified:(NSNumber*)verified retry:(int)retryCount success:(void (^)(NSString *status, id responseObject))success failure:(void (^)(NSError *error))failure {
    
    if (!self.hasReachability) {
        failure(nil);
        return;
    }
    
    if (retryCount <= 0) {
        failure(nil);
        return;
    }
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithCapacity:10];
    if (action) {
        [parameters setObject:action forKey:@"action"];
    }
    if (email) {
        [parameters setObject:email forKey:@"email"];
    }
    if (passwordHash) {
        [parameters setObject:passwordHash forKey:@"clientPasswordHash"];
    }
    if (facebookId) {
        [parameters setObject:facebookId forKey:@"facebookId"];
    }
    if (facebookAccessToken) {
        [parameters setObject:facebookAccessToken forKey:@"facebookAccessToken"];
    }
    if (firstName) {
        [parameters setObject:firstName forKey:@"firstName"];
    }
    if (lastName) {
        [parameters setObject:lastName forKey:@"lastName"];
    }
    if (gender) {
        [parameters setObject:gender forKey:@"gender"];
    }
    if (verified) {
        [parameters setObject:verified forKey:@"verified"];
    }

    [[VaavudAPIHTTPClient sharedInstance] postPath:@"/api/user/register" parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        // clear consecutive errors since we got a successful reponse
        self.consecutiveNetworkErrors = 0;
        self.backoffWaitCount = 0;
        
        NSString *status = [responseObject objectForKey:@"status"];
        if (status && status != nil && status != (id)[NSNull null] && ([status length] > 0)) {
            
            // remember the authToken we got from the server as response
            NSString *authToken = [responseObject objectForKey:@"authToken"];
            if (authToken && authToken != nil && authToken != (id)[NSNull null] && ([authToken length] > 0)) {
                [Property setAsString:authToken forKey:KEY_AUTH_TOKEN];
                [[VaavudAPIHTTPClient sharedInstance] setAuthToken:authToken];
            }
            
            NSLog(@"[ServerUploadManager] Got status %@ registering user", status);

            success(status, responseObject);
        }
        else {
            NSLog(@"[ServerUploadManager] Didn't get any status from server");
            failure(nil);
        }

    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        long statusCode = (long)operation.response.statusCode;
        NSLog(@"[ServerUploadManager] Got error status code %ld registering user: %@", statusCode, error);
        
        self.consecutiveNetworkErrors++;
        
        // check for unauthorized
        if (statusCode == 401) {
            // Unauthorized most likely means that a user is associated with this device and the authToken has been changed or invalidated
            // server-side. Thus, we need to remove the local authToken, create a new deviceUuid, and re-register the user
            [[AccountManager sharedInstance] logout];
            failure(error);
        }
        else if (statusCode == 404) {
            failure(error);
        }
        else {
            [self registerUser:action
                         email:email
                  passwordHash:passwordHash
                    facebookId:facebookId
           facebookAccessToken:facebookAccessToken
                     firstName:firstName
                      lastName:lastName
                        gender:gender
                      verified:verified
                         retry:retryCount-1
                       success:success
                       failure:failure];
        }
    }];
}

-(void) readMeasurements:(int)hours retry:(int)retryCount success:(void (^)(NSArray *measurements))success failure:(void (^)(NSError *error))failure {
    if (!self.hasReachability) {
        if (failure) {
            failure(nil);
        }
        return;
    }
    
    if (retryCount <= 0) {
        if (failure) {
            failure(nil);
        }
        return;
    }
    
    NSDate *startTime = [NSDate dateWithTimeIntervalSinceNow:-hours * 3600];
    NSNumber *startTimeMillis = [NSNumber numberWithLongLong:[startTime timeIntervalSince1970] * 1000.0];
    NSDictionary *parameters = [NSDictionary dictionaryWithObjectsAndKeys:[startTimeMillis stringValue], @"startTime", nil];
    
    [[VaavudAPIHTTPClient sharedInstance] postPath:@"/api/measurements" parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        //NSLog(@"[ServerUploadManager] Got successful response reading measurements");
        
        // clear consecutive errors since we got a successful reponse
        self.consecutiveNetworkErrors = 0;
        self.backoffWaitCount = 0;
        
        if (success) {
            success(responseObject);
        }
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        long statusCode = (long)operation.response.statusCode;
        NSLog(@"[ServerUploadManager] Got error status code %ld reading measurements: %@", statusCode, error);
        
        self.consecutiveNetworkErrors++;
        
        // check for unauthorized
        if (statusCode == 401) {
            // try to re-register
            self.hasRegisteredDevice = NO;
            if (failure) {
                failure(error);
            }
        }
        else {
            [self readMeasurements:hours retry:retryCount-1 success:success failure:failure];
        }
    }];
}

-(void) syncHistory:(int)retryCount ignoreGracePeriod:(BOOL)ignoreGracePeriod success:(void (^)())success failure:(void (^)(NSError *error))failure {
    if (!self.hasReachability) {
        if (failure) {
            failure(nil);
        }
        return;
    }
    
    if (![[AccountManager sharedInstance] isLoggedIn]) {
        if (failure) {
            failure(nil);
        }
        return;
    }
    
    if (retryCount <= 0) {
        if (failure) {
            failure(nil);
        }
        return;
    }

    if (!ignoreGracePeriod && self.lastHistorySync && self.lastHistorySync != nil) {
        NSTimeInterval howRecent = [self.lastHistorySync timeIntervalSinceNow];
        if (abs(howRecent) < GRACE_TIME_BETWEEN_HISTORY_SYNC) {
            return;
        }
    }
    
    NSDate *beginSyncDate = [NSDate date];
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    NSString *formatString = @"yyyy-MM-dd HH:mm:ss.SSS Z";
    [formatter setDateFormat:formatString];
    
    NSDate *latestEndTime = nil;
    NSArray *measurementSessions = [MeasurementSession MR_findAllSortedBy:@"endTime" ascending:TRUE];
    NSMutableString *concatenatedUUIDs = [NSMutableString stringWithCapacity:measurementSessions.count * (36 + 10)];
    for (int i = 0; i < measurementSessions.count; i++) {
        MeasurementSession *measurementSession = measurementSessions[i];
        if (measurementSession.endTime && measurementSession.uuid && measurementSession.uuid.length > 0 && [measurementSession.measuring boolValue] == NO) {
            NSString *endTimeSecondsString = [[NSNumber numberWithLongLong:(long) ceil([measurementSession.endTime timeIntervalSince1970])] stringValue];
            //NSLog(@"uuid=%@, time=%@", measurementSession.uuid, endTimeSecondsString);
            [concatenatedUUIDs appendString:measurementSession.uuid];
            [concatenatedUUIDs appendString:endTimeSecondsString];
            latestEndTime = measurementSession.endTime;
        }
    }
    
    NSDictionary *parameters = [NSDictionary new];
    if (latestEndTime && concatenatedUUIDs.length > 0) {
        
        // round up to nearest whole second to avoid precision issues
        latestEndTime = [NSDate dateWithTimeIntervalSince1970:ceil([latestEndTime timeIntervalSince1970])];
        
        NSString *hashedUUIDs = [UUIDUtil md5Hash:[concatenatedUUIDs uppercaseString]];
        NSLog(@"[ServerUploadManager] Sync history with hash:%@, time:%@", hashedUUIDs, [formatter stringFromDate:latestEndTime]);
        parameters = [NSDictionary dictionaryWithObjectsAndKeys:hashedUUIDs, @"hash", latestEndTime, @"latestEndTime", nil];
        parameters = [DictionarySerializationUtil convertValuesToBasicTypes:parameters];
    }

    NSLog(@"[ServerUploadManager] History sync (took %f s to compute hash)", -[beginSyncDate timeIntervalSinceNow]);
    
    // only let it look like history sync is in progress if it was forced
    self.isHistorySyncInProgress = ignoreGracePeriod;
    
    [[VaavudAPIHTTPClient sharedInstance] postPath:@"/api/history" parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        // clear consecutive errors since we got a successful reponse
        self.consecutiveNetworkErrors = 0;
        self.backoffWaitCount = 0;
        self.lastHistorySync = [NSDate date];
        self.isHistorySyncInProgress = NO;

        //NSLog(@"[ServerUploadManager] Response: %@", responseObject);

        NSDictionary *responseDictionary = (NSDictionary*) responseObject;

        NSDate *fromEndTime = [NSDate dateWithTimeIntervalSince1970:([((NSString*)[responseDictionary objectForKey:@"fromEndTime"]) doubleValue] / 1000.0)];
        NSLog(@"[ServerUploadManager] Got successful history sync with fromEndTime: %@ (%@)", [formatter stringFromDate:fromEndTime], (NSString*)[responseDictionary objectForKey:@"fromEndTime"]);

        // make response array of measurements into a dictionary with measurement uuid as key
        
        NSArray *measurementArray = (NSArray*) [responseDictionary objectForKey:@"measurements"];
        NSMutableDictionary *uuidToDictionary = [NSMutableDictionary dictionaryWithCapacity:measurementArray.count];
        for (int i = 0; i < measurementArray.count; i++) {
            NSDictionary *measurementDictionary = measurementArray[i];
            NSString *uuid = [measurementDictionary objectForKey:@"uuid"];
            if (uuid) {
                [uuidToDictionary setObject:measurementDictionary forKey:uuid];
            }
        }
        
        // go through all existing measurements in our local database and
        // (1) update any measurement that has been modified - i.e. its endTime has changed
        // (2) delete any measurement that wasn't in the response from the server
        // (3) remove the response measurement from the uuid->measurement map so that eventually
        //     that map will only contain new measurements
        
        NSArray *measurementSessions = [MeasurementSession MR_findAllSortedBy:@"endTime" ascending:YES withPredicate:[NSPredicate predicateWithFormat:@"endTime >= %@", fromEndTime]];
        NSLog(@"[ServerUploadManager] Existing sessions after endTime: %u", (int)measurementSessions.count);
        for (int i = 0; i < measurementSessions.count; i++) {
            MeasurementSession *measurementSession = measurementSessions[i];
            if (measurementSession.uuid && measurementSession.uuid.length > 0) {
                NSDictionary *measurementDictionary = (NSDictionary*) [uuidToDictionary objectForKey:measurementSession.uuid];
                if (measurementDictionary) {
                    NSDate *endTime = [NSDate dateWithTimeIntervalSince1970:([((NSString*)[measurementDictionary objectForKey:@"endTime"]) doubleValue] / 1000.0)];
                    if ([measurementSession.endTime isEqualToDate:endTime]) {
                        NSLog(@"[ServerUploadManager] Measurement known: %@, endTime: %@", measurementSession.uuid, [formatter stringFromDate:measurementSession.endTime]);
                    }
                    else {
                        NSDate *startTime = [NSDate dateWithTimeIntervalSince1970:([((NSString*)[measurementDictionary objectForKey:@"startTime"]) doubleValue] / 1000.0)];
                        NSDate *endTime = [NSDate dateWithTimeIntervalSince1970:([((NSString*)[measurementDictionary objectForKey:@"endTime"]) doubleValue] / 1000.0)];
                        NSNumber *latitude = [self numberValueFrom:measurementDictionary forKey:@"latitude"];
                        NSNumber *longitude = [self numberValueFrom:measurementDictionary forKey:@"longitude"];
                        NSNumber *windSpeedAvg = [self numberValueFrom:measurementDictionary forKey:@"windSpeedAvg"];
                        NSNumber *windSpeedMax = [self numberValueFrom:measurementDictionary forKey:@"windSpeedMax"];
                        NSArray *points = [measurementDictionary objectForKey:@"points"];

                        if ([measurementSession.measuring boolValue] == NO && [measurementSession.uploaded boolValue] == YES) {

                            NSLog(@"[ServerUploadManager] Measurement modified: %@, endTime=%@", measurementSession.uuid, endTime);
                            
                            measurementSession.startTime = startTime;
                            measurementSession.endTime = endTime;
                            measurementSession.latitude = latitude;
                            measurementSession.longitude = longitude;
                            measurementSession.windSpeedAvg = windSpeedAvg;
                            measurementSession.windSpeedMax = windSpeedMax;
                        
                            if (points.count > measurementSession.points.count) {

                                NSLog(@"[ServerUploadManager] Measurement points added, old size=%lu, new size=%lu", (unsigned long)measurementSession.points.count, (unsigned long)points.count);

                                NSOrderedSet *measurementPoints = [self createMeasurementPoints:points withSession:measurementSession];
                                [measurementSession setPoints:measurementPoints];
                            }
                        }
                    }
                    [uuidToDictionary removeObjectForKey:measurementSession.uuid];
                }
                else {
                    NSLog(@"[ServerUploadManager] Measurement deleted: %@, endTime: %@", measurementSession.uuid, [formatter stringFromDate:measurementSession.endTime]);
                    [measurementSession MR_deleteEntity];
                }
            }
        }
        
        // create new measurement sessions that did not already exist in the local database
        
        NSArray *newMeasurementSessions = [uuidToDictionary allValues];
        for (int i = 0; i < newMeasurementSessions.count; i++) {
            NSDictionary *measurementDictionary = (NSDictionary*) newMeasurementSessions[i];
            
            NSString *uuid = [self stringValueFrom:measurementDictionary forKey:@"uuid"];
            NSString *deviceUuid = [self stringValueFrom:measurementDictionary forKey:@"deviceUuid"];
            NSDate *startTime = [NSDate dateWithTimeIntervalSince1970:([((NSString*)[measurementDictionary objectForKey:@"startTime"]) doubleValue] / 1000.0)];
            NSDate *endTime = [NSDate dateWithTimeIntervalSince1970:([((NSString*)[measurementDictionary objectForKey:@"endTime"]) doubleValue] / 1000.0)];
            NSNumber *latitude = [self numberValueFrom:measurementDictionary forKey:@"latitude"];
            NSNumber *longitude = [self numberValueFrom:measurementDictionary forKey:@"longitude"];
            NSNumber *windSpeedAvg = [self numberValueFrom:measurementDictionary forKey:@"windSpeedAvg"];
            NSNumber *windSpeedMax = [self numberValueFrom:measurementDictionary forKey:@"windSpeedMax"];
            NSArray *points = [measurementDictionary objectForKey:@"points"];

            MeasurementSession *measurementSession = [MeasurementSession MR_findFirstByAttribute:@"uuid" withValue:uuid];
            if (measurementSession && measurementSession != nil && measurementSession != (id)[NSNull null]) {

                if ([measurementSession.measuring boolValue] == NO && [measurementSession.uploaded boolValue] == YES) {

                    NSLog(@"[ServerUploadManager] Measurement before fromEndTime modified: %@, endTime=%@", measurementSession.uuid, endTime);
                    
                    measurementSession.startTime = startTime;
                    measurementSession.endTime = endTime;
                    measurementSession.latitude = latitude;
                    measurementSession.longitude = longitude;
                    measurementSession.windSpeedAvg = windSpeedAvg;
                    measurementSession.windSpeedMax = windSpeedMax;
                
                    if (points.count > measurementSession.points.count) {
                        
                        NSLog(@"[ServerUploadManager] Measurement points added, old size=%lu, new size=%lu", (unsigned long)measurementSession.points.count, (unsigned long)points.count);
                        
                        NSOrderedSet *measurementPoints = [self createMeasurementPoints:points withSession:measurementSession];
                        [measurementSession setPoints:measurementPoints];
                    }
                }
            }
            else {
            
                NSLog(@"[ServerUploadManager] Measurement created: %@, endTime=%@ (%@)", uuid, endTime, (NSString*)[measurementDictionary objectForKey:@"endTime"]);
                
                MeasurementSession *measurementSession = [MeasurementSession MR_createEntity];
                measurementSession.uuid = uuid;
                measurementSession.device = deviceUuid;
                measurementSession.startTime = startTime;
                measurementSession.timezoneOffset = [NSNumber numberWithInt:[[NSTimeZone localTimeZone] secondsFromGMTForDate:measurementSession.startTime]];
                measurementSession.endTime = endTime;
                measurementSession.measuring = [NSNumber numberWithBool:NO];
                measurementSession.uploaded = [NSNumber numberWithBool:YES];
                measurementSession.startIndex = [NSNumber numberWithInt:0];
                measurementSession.source = @"server";
                measurementSession.latitude = latitude;
                measurementSession.longitude = longitude;
                measurementSession.windSpeedAvg = windSpeedAvg;
                measurementSession.windSpeedMax = windSpeedMax;
                
                NSOrderedSet *measurementPoints = [self createMeasurementPoints:points withSession:measurementSession];
                [measurementSession setPoints:measurementPoints];
            }
            
            [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreWithCompletion:nil];
        }
        
        if (success) {
            success();
        }
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        long statusCode = (long)operation.response.statusCode;
        NSLog(@"[ServerUploadManager] Got error status code %ld syncing history: %@", statusCode, error);
        
        self.consecutiveNetworkErrors++;
        self.isHistorySyncInProgress = NO;
        
        // check for unauthorized
        if (statusCode == 401) {
            // 401 is most likely due to the user not being logged in, so don't try to re-register the device as it could cause endless
            // calls of "register" and "history" (since register will call sync history afterwards)
            // try to re-register
            if (failure) {
                failure(error);
            }
        }
        else {
            [self syncHistory:retryCount-1 ignoreGracePeriod:ignoreGracePeriod success:success failure:failure];
        }
    }];
}

- (void) deleteMeasurementSession:(NSString*)measurementSessionUuid retry:(int)retryCount success:(void(^)())success failure:(void(^)(NSError *error))failure {

    if (!measurementSessionUuid || measurementSessionUuid.length == 0) {
        NSLog(@"[ServerUploadManager] ERROR: No measurement session uuid calling delete measurement session");
        return;
    }
    
    if (!self.hasReachability) {
        if (failure) {
            failure(nil);
        }
        return;
    }
    
    if (retryCount <= 0) {
        if (failure) {
            failure(nil);
        }
        return;
    }
    
    NSDictionary *parameters = [NSDictionary dictionaryWithObjectsAndKeys:measurementSessionUuid, @"uuid", nil];
    
    [[VaavudAPIHTTPClient sharedInstance] postPath:@"/api/measurement/delete" parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        NSLog(@"[ServerUploadManager] Got successful response deleting measurement");
        
        // clear consecutive errors since we got a successful reponse
        self.consecutiveNetworkErrors = 0;
        self.backoffWaitCount = 0;
        
        if (success) {
            success();
        }
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        long statusCode = (long)operation.response.statusCode;
        NSLog(@"[ServerUploadManager] Got error status code %ld deleting measurement: %@", statusCode, error);
        
        self.consecutiveNetworkErrors++;
        
        // check for unauthorized
        if (statusCode == 401) {
            // try to re-register
            self.hasRegisteredDevice = NO;
            if (failure) {
                failure(error);
            }
        }
        else {
            [self deleteMeasurementSession:measurementSessionUuid retry:retryCount-1 success:success failure:failure];
        }
    }];
}

-(NSNumber*) doubleValue:(id) responseObject forKey:(NSString*) key {
    NSString *value = [responseObject objectForKey:key];
    if (value && value != nil && value != (id)[NSNull null] && ([value length] > 0)) {
        return [NSNumber numberWithDouble:[value doubleValue]];
    }
    return nil;
}

-(NSNumber*) integerValue:(id) responseObject forKey:(NSString*) key {
    NSString *value = [responseObject objectForKey:key];
    if (value && value != nil && value != (id)[NSNull null] && ([value length] > 0)) {
        return [NSNumber numberWithInt:[value doubleValue]];
    }
    return nil;
}

-(NSString*) stringValueFrom:(NSDictionary*)dictionary forKey:(NSString*)key {
    NSString *value = (NSString*) [dictionary objectForKey:key];
    if (value && value != nil && ![value isEqual:[NSNull null]] && ![@"<null>" isEqualToString:value] && [value length] > 0) {
        return (NSString*) value;
    }
    return nil;
}

-(NSNumber*) numberValueFrom:(NSDictionary*)dictionary forKey:(NSString*)key {
    NSObject *v = [dictionary objectForKey:key];
    if ([v isKindOfClass:[NSNumber class]]) {
        return (NSNumber*) v;
    }
    return nil;
}

- (NSOrderedSet*) createMeasurementPoints:(NSArray*)array withSession:(MeasurementSession*)session {
    
    NSMutableOrderedSet *set = [NSMutableOrderedSet new];
    
    for (int i = 0; i < array.count; i++) {
        NSDictionary *dictionary = array[i];
        
        NSDate *time = [NSDate dateWithTimeIntervalSince1970:([((NSString*)[dictionary objectForKey:@"time"]) doubleValue] / 1000.0)];
        NSNumber *speed = [self numberValueFrom:dictionary forKey:@"speed"];
    
        MeasurementPoint *measurementPoint = [MeasurementPoint MR_createEntity];
        measurementPoint.session = session;
        measurementPoint.time = time;
        measurementPoint.windSpeed = speed;
        
        [set addObject:measurementPoint];
    }
    return set;
}

@end
