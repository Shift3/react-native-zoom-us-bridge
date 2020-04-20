#import "RNZoomUsBridge.h"
#import "RNZoomUSBridgeEventEmitter.h"

#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>

typedef enum {
  MobileRTCSampleTokenType_Token,
  MobileRTCSampleTokenType_ZAK,
} MobileRTCSampleTokenType;

NSString *const kSDKDomain = @"zoom.us";

@implementation RNZoomUsBridge
{
  BOOL isInitialized;
  RCTPromiseResolveBlock initializePromiseResolve;
  RCTPromiseRejectBlock initializePromiseReject;
  RCTPromiseResolveBlock meetingPromiseResolve;
  RCTPromiseRejectBlock meetingPromiseReject;
}

static RNZoomUsBridgeEventEmitter *internalEmitter = nil;

- (instancetype)init {
  if (self = [super init]) {
    isInitialized = NO;
    initializePromiseResolve = nil;
    initializePromiseReject = nil;
    meetingPromiseResolve = nil;
    meetingPromiseReject = nil;
  }
  return self;
}

+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

- (dispatch_queue_t)methodQueue
{
  return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(
  initialize: (NSString *)appKey
  withAppSecret: (NSString *)appSecret
  withResolve: (RCTPromiseResolveBlock)resolve
  withReject: (RCTPromiseRejectBlock)reject
)
{
  if (isInitialized) {
    resolve(@"Already initialize Zoom SDK successfully.");
    return;
  }

  isInitialized = true;

  @try {
    initializePromiseResolve = resolve;
    initializePromiseReject = reject;

    MobileRTCSDKInitContext *context = [MobileRTCSDKInitContext new];
    [context setDomain:kSDKDomain];
    [context setEnableLog:NO];
    [[MobileRTC sharedRTC] initialize:context];

    MobileRTCAuthService *authService = [[MobileRTC sharedRTC] getAuthService];
    if (authService)
    {
      authService.delegate = self;
      authService.clientKey = appKey;
      authService.clientSecret = appSecret;
      [authService sdkAuth];
    } else {
      NSLog(@"onZoomSDKInitializeResult, no authService");
    }
  } @catch (NSError *ex) {
      reject(@"ERR_UNEXPECTED_EXCEPTION", @"Executing initialize", ex);
  }
}

RCT_EXPORT_METHOD(
                  startMeeting:(NSString *)meetingNumber
                  userName:(NSString *)userName
                  userId:(NSString *)userId
                  userZak:(NSString *)userZak
                  withResolve: (RCTPromiseResolveBlock)resolve
                  withReject: (RCTPromiseRejectBlock)reject
)
{
  @try {
    meetingPromiseResolve = resolve;
    meetingPromiseReject = reject;

    MobileRTCMeetingService *ms = [[MobileRTC sharedRTC] getMeetingService];
    if (ms) {
      ms.delegate = self;

      MobileRTCMeetingStartParam4WithoutLoginUser * params = [[MobileRTCMeetingStartParam4WithoutLoginUser alloc]init];
      params.userName = userName;
      params.meetingNumber = meetingNumber;
      params.userID = userId;
      params.userType = MobileRTCUserType_APIUser;
      params.zak = userZak;
        params.userToken = @"null";

      MobileRTCMeetError startMeetingResult = [ms startMeetingWithStartParam:params];
      NSLog(@"startMeeting, startMeetingResult=%d", startMeetingResult);
    }
  } @catch (NSError *ex) {
      reject(@"ERR_UNEXPECTED_EXCEPTION", @"Executing startMeeting", ex);
  }
}

RCT_EXPORT_METHOD(
  joinMeeting: (NSString *)displayName
  withMeetingNo: (NSString *)meetingNo
  withPassword:(NSString *)password
  withResolve: (RCTPromiseResolveBlock)resolve
  withReject: (RCTPromiseRejectBlock)reject
)
{
  @try {
    meetingPromiseResolve = resolve;
    meetingPromiseReject = reject;

    MobileRTCMeetingService *ms = [[MobileRTC sharedRTC] getMeetingService];
    if (ms) {
      ms.delegate = self;

      NSDictionary *paramDict = @{
        kMeetingParam_Username: displayName,
        kMeetingParam_MeetingNumber: meetingNo,
        kMeetingParam_MeetingPassword: password ? password : @""
      };

      MobileRTCMeetError joinMeetingResult = [ms joinMeetingWithDictionary:paramDict];
      NSLog(@"joinMeeting, joinMeetingResult=%d", joinMeetingResult);
    }
  } @catch (NSError *ex) {
      reject(@"ERR_UNEXPECTED_EXCEPTION", @"Executing joinMeeting", ex);
  }
}

- (void)onMobileRTCAuthReturn:(MobileRTCAuthError)returnValue {
  NSLog(@"SDK LOG - Auth Returned %d", returnValue);
  RNZoomUsBridgeEventEmitter *emitter = [RNZoomUsBridgeEventEmitter allocWithZone: nil];

  NSDictionary *resultDict = returnValue == MobileRTCMeetError_Success ? @{} : @{@"error": @"start_error"};
  [emitter userSDKInitilized:resultDict];

  [[[MobileRTC sharedRTC] getAuthService] setDelegate:self];
  if (returnValue != MobileRTCAuthError_Success)
  {
    NSLog(@"SDK LOG - Auth Error'd %d", returnValue);
  }
}

- (void)onMeetingReturn:(MobileRTCMeetError)errorCode internalError:(NSInteger)internalErrorCode {
  NSLog(@"onMeetingReturn, error=%d, internalErrorCode=%zd", errorCode, internalErrorCode);

  if (!meetingPromiseResolve) {
    return;
  }

  if (errorCode != MobileRTCMeetError_Success) {
    meetingPromiseReject(
      @"ERR_ZOOM_MEETING",
      [NSString stringWithFormat:@"Error: %d, internalErrorCode=%zd", errorCode, internalErrorCode],
      [NSError errorWithDomain:@"us.zoom.sdk" code:errorCode userInfo:nil]
    );
  } else {
    meetingPromiseResolve(@"Connected to zoom meeting");
  }

  meetingPromiseResolve = nil;
  meetingPromiseReject = nil;
}

- (void)onMeetingStateChange:(MobileRTCMeetingState)state {
  NSLog(@"onMeetingStatusChanged, meetingState=%d", state);

  if (state == MobileRTCMeetingState_InMeeting || state == MobileRTCMeetingState_Idle) {
    if (!meetingPromiseResolve) {
      return;
    }

    meetingPromiseResolve(@"Connected to zoom meeting");

    meetingPromiseResolve = nil;
    meetingPromiseReject = nil;
  }
}

- (void)onMeetingError:(MobileRTCMeetError)errorCode message:(NSString *)message {
  NSLog(@"onMeetingError, errorCode=%d, message=%@", errorCode, message);

  if (!meetingPromiseResolve) {
    return;
  }

  meetingPromiseReject(
    @"ERR_ZOOM_MEETING",
    [NSString stringWithFormat:@"Error: %d, internalErrorCode=%@", errorCode, message],
    [NSError errorWithDomain:@"us.zoom.sdk" code:errorCode userInfo:nil]
  );

  meetingPromiseResolve = nil;
  meetingPromiseReject = nil;
}

@end
