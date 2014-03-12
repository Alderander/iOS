//
//  AccountManager.h
//  Vaavud
//
//  Created by Thomas Stilling Ambus on 19/02/2014.
//  Copyright (c) 2014 Andreas Okholm. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <FacebookSDK/FacebookSDK.h>

enum AuthenticationActionType : NSUInteger {
    AuthenticationActionLogin = 1,
    AuthenticationActionSignup = 2,
    AuthenticationActionRefresh = 3
};

enum AuthenticationStateType : NSUInteger {
    AuthenticationStateNeverLoggedIn = 1,
    AuthenticationStateLoggedIn = 2,
    AuthenticationStateWasLoggedIn = 3
};

enum AuthenticationResponseType : NSUInteger {
    AuthenticationResponseCreated = 1,
    AuthenticationResponsePaired = 2,
    AuthenticationResponseGenericError = 3,
    AuthenticationResponseMalformedEmail = 4,
    AuthenticationResponseInvalidCredentials = 5,
    AuthenticationResponseEmailUsedProvidePassword = 6,
    AuthenticationResponseLoginWithFacebook = 7,
    AuthenticationResponseFacebookInvalidAccessToken = 8,
    AuthenticationResponseFacebookUserMessage = 9,
    AuthenticationResponseFacebookUserCancelled = 10,
    AuthenticationResponseFacebookReopenSession = 11,
    AuthenticationResponseNoReachability = 12
};

// note: the reason we use a delegate and not a closure is that the Facebook SDK keeps a
// reference to the completion handler provided in openActiveSessionXXX and to make sure
// that we don't end up calling a deallocated closure we use a delegate as indirection

@protocol AuthenticationDelegate <NSObject>
- (void) facebookAuthenticationSuccess:(enum AuthenticationResponseType)response;
- (void) facebookAuthenticationFailure:(enum AuthenticationResponseType)response message:(NSString*)message displayFeedback:(BOOL)displayFeedback;
@end

@interface AccountManager : NSObject

@property (nonatomic, weak) id<AuthenticationDelegate> delegate;

+ (AccountManager*) sharedInstance;

-(void) registerWithPassword:(NSString*)password email:(NSString*)email firstName:(NSString*)firstName lastName:(NSString*)lastName action:(enum AuthenticationActionType)action success:(void(^)(enum AuthenticationResponseType response))success failure:(void(^)(enum AuthenticationResponseType response))failure;

-(void) registerWithFacebook:(NSString*)password action:(enum AuthenticationActionType)action;

-(void) logout;

-(BOOL) isLoggedIn;

@end