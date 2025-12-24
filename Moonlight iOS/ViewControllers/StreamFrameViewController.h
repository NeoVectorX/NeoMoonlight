//
//  StreamFrameViewController.h
//  Moonlight
//
//  Created by Diego Waxemberg on 1/18/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "Connection.h"
#import "StreamView.h"

#import <UIKit/UIKit.h>

// Forward declare the Swift class for visionOS
#if TARGET_OS_VISION
@class MetalVideoDecoderRenderer;
#endif

FOUNDATION_EXPORT NSString * const StreamDidTeardownNotification;
FOUNDATION_EXPORT NSString * const StreamFirstFrameShownNotification;
FOUNDATION_EXPORT NSString * const StreamControllerDismantledNotification;

#if TARGET_OS_TV
@import GameController;

@interface StreamFrameViewController : GCEventViewController <ConnectionCallbacks, ControllerSupportDelegate, UserInteractionDelegate, UIScrollViewDelegate>
#else
@interface StreamFrameViewController : UIViewController <ConnectionCallbacks, ControllerSupportDelegate, UserInteractionDelegate, UIScrollViewDelegate>
#endif
@property (nonatomic, strong) StreamConfiguration* streamConfig;

typedef void (^noargCallbackType)(void);
@property (nonatomic, strong) noargCallbackType connectedCallback;
@property (nonatomic, strong) noargCallbackType disconnectedCallback;

-(void)updatePreferredDisplayMode:(BOOL)streamActive;
- (void)stopStream;
- (void)applyUIKitPreset:(int32_t)preset;

// Method to update HDR parameters
- (void)updateRendererHDRParams:(float)brightness saturation:(float)saturation contrast:(float)contrast luminosity:(float)luminosity gamma:(float)gamma;

@end