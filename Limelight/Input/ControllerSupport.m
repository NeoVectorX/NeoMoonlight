//
//  ControllerSupport.m
//  Moonlight
//
//  Created by Cameron Gutman on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "ControllerSupport.h"
#import "Controller.h"
#import "OnScreenControls.h"
#import "DataManager.h"
#import "Moonlight-Swift.h"

#include "Limelight.h"

@import GameController;
@import AudioToolbox;
@import UIKit;

// Constants
static const double MOUSE_SPEED_DIVISOR = 1.25;

// Implementation
@implementation ControllerSupport {
    id _controllerConnectObserver;
    id _controllerDisconnectObserver;
    id _applicationDidBecomeActiveObserver;
    id _applicationWillEnterForegroundObserver;
    GCMouse *_mouseConnectObserver;
    GCMouse *_mouseDisconnectObserver;
    GCKeyboard *_keyboardConnectObserver;
    GCKeyboard *_keyboardDisconnectObserver;

    NSLock *_controllerStreamLock;
    NSMutableDictionary *_controllers;
    id<ControllerSupportDelegate> _delegate;
    
    GCEventInteraction *_gcEventInteraction;

    float accumulatedDeltaX;
    float accumulatedDeltaY;
    float accumulatedScrollX;
    float accumulatedScrollY;

    OnScreenControls *_osc;
    Controller *_oscController;

    #define EMULATING_SELECT 0x1
    #define EMULATING_SPECIAL 0x2

    bool _oscEnabled;
    char _controllerNumbers;
    bool _multiController;
    bool _swapABXYButtons;
    bool _reportControllerAsXbox;
    int _controllerSlotOffset;  // For co-op: offset added to controller index

    dispatch_source_t _inputSyncSource;
    dispatch_source_t _sendSource;
    BOOL _inputSyncEnabled;
    BOOL _coopInputLogged;
    NSTimeInterval _lastGamepadHandlerHealthCheck;
    NSTimeInterval _foregroundRestoreStartTime;
    NSInteger _foregroundRestoreGeneration;
    NSTimeInterval _lastReregisterTime;  // Debounce handler reregister
}

static const double NEO_CONTROLLER_SEND_HZ = 60.0;
/// Re-register GameController handlers periodically (DualSense profile handler can die mid-session).
static const NSTimeInterval NEO_GAMEPAD_HANDLER_HEALTH_INTERVAL = 90.0;
/// Aggressive DualSense prewarm for first N seconds after foreground to unstick frozen D-pad state.
static const NSTimeInterval NEO_DPAD_AGGRESSIVE_PREWARM_DURATION = 3.0;

static dispatch_queue_t neo_controllerInputQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.neomoonlight.controller-input", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static dispatch_queue_t neo_controllerSendQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.neomoonlight.controller-send", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static dispatch_queue_t neo_hapticsQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.neomoonlight.haptics", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static const float NEO_DPAD_AXIS_THRESHOLD = 0.25f;

static BOOL neo_dpadDirectionPressed(GCControllerButtonInput *button) {
    if (button == nil) {
        return NO;
    }
    if (button.pressed) {
        return YES;
    }
    return fabsf((float)button.value) > NEO_DPAD_AXIS_THRESHOLD;
}

static BOOL neo_dpadUpPressed(GCExtendedGamepad *gamepad) {
    if (neo_dpadDirectionPressed(gamepad.dpad.up)) {
        return YES;
    }
    return gamepad.dpad.yAxis.value > NEO_DPAD_AXIS_THRESHOLD;
}

static BOOL neo_dpadDownPressed(GCExtendedGamepad *gamepad) {
    if (neo_dpadDirectionPressed(gamepad.dpad.down)) {
        return YES;
    }
    return gamepad.dpad.yAxis.value < -NEO_DPAD_AXIS_THRESHOLD;
}

static BOOL neo_dpadLeftPressed(GCExtendedGamepad *gamepad) {
    if (neo_dpadDirectionPressed(gamepad.dpad.left)) {
        return YES;
    }
    return gamepad.dpad.xAxis.value < -NEO_DPAD_AXIS_THRESHOLD;
}

static BOOL neo_dpadRightPressed(GCExtendedGamepad *gamepad) {
    if (neo_dpadDirectionPressed(gamepad.dpad.right)) {
        return YES;
    }
    return gamepad.dpad.xAxis.value > NEO_DPAD_AXIS_THRESHOLD;
}

static BOOL neo_dpadUpFromDirectionPad(GCControllerDirectionPad *dpad) {
    if (dpad == nil) {
        return NO;
    }
    if (neo_dpadDirectionPressed(dpad.up)) {
        return YES;
    }
    return dpad.yAxis.value > NEO_DPAD_AXIS_THRESHOLD;
}

static BOOL neo_dpadDownFromDirectionPad(GCControllerDirectionPad *dpad) {
    if (dpad == nil) {
        return NO;
    }
    if (neo_dpadDirectionPressed(dpad.down)) {
        return YES;
    }
    return dpad.yAxis.value < -NEO_DPAD_AXIS_THRESHOLD;
}

static BOOL neo_dpadLeftFromDirectionPad(GCControllerDirectionPad *dpad) {
    if (dpad == nil) {
        return NO;
    }
    if (neo_dpadDirectionPressed(dpad.left)) {
        return YES;
    }
    return dpad.xAxis.value < -NEO_DPAD_AXIS_THRESHOLD;
}

static BOOL neo_dpadRightFromDirectionPad(GCControllerDirectionPad *dpad) {
    if (dpad == nil) {
        return NO;
    }
    if (neo_dpadDirectionPressed(dpad.right)) {
        return YES;
    }
    return dpad.xAxis.value > NEO_DPAD_AXIS_THRESHOLD;
}

static BOOL neo_isTouchpadDpadKey(NSString *key) {
    if (key == nil) {
        return NO;
    }
    if (@available(iOS 14.0, tvOS 14.0, *)) {
        return [key isEqualToString:GCInputDualShockTouchpadOne]
            || [key isEqualToString:GCInputDualShockTouchpadTwo];
    }
    return NO;
}

static BOOL neo_isDirectionPadElement(GCControllerElement *element, GCControllerDirectionPad *dpad) {
    if (element == nil || dpad == nil) {
        return NO;
    }
    return element == dpad
        || element == dpad.up
        || element == dpad.down
        || element == dpad.left
        || element == dpad.right
        || element == dpad.xAxis
        || element == dpad.yAxis;
}

/// Primary menu D-pad on DualSense is often exposed via physicalInputProfile.dpads, not extendedGamepad.dpad.
static GCControllerDirectionPad *neo_primaryDpadFromProfile(GCPhysicalInputProfile *profile) API_AVAILABLE(ios(14.0), tvos(14.0)) {
    if (profile == nil) {
        return nil;
    }
    for (NSString *key in profile.dpads) {
        if (neo_isTouchpadDpadKey(key)) {
            continue;
        }
        GCControllerDirectionPad *pad = profile.dpads[key];
        if (pad != nil) {
            return pad;
        }
    }
    return nil;
}

static GCControllerDirectionPad *neo_primaryDpadFromPhysicalProfile(GCExtendedGamepad *gamepad) API_AVAILABLE(ios(14.0), tvos(14.0)) {
    if (gamepad == nil) {
        return nil;
    }
    return neo_primaryDpadFromProfile(gamepad.controller.physicalInputProfile);
}

/// DualSense often exposes menu D-pad as named profile buttons as well as dpads.
static void neo_orDpadFromProfileButtons(GCPhysicalInputProfile *profile,
                                          BOOL *up, BOOL *down, BOOL *left, BOOL *right) API_AVAILABLE(ios(14.0), tvos(14.0)) {
    if (profile == nil || profile.buttons == nil) {
        return;
    }

    GCControllerButtonInput *btn = profile.buttons[@"Direction Pad Up"];
    if (neo_dpadDirectionPressed(btn)) {
        *up = YES;
    }
    btn = profile.buttons[@"Direction Pad Down"];
    if (neo_dpadDirectionPressed(btn)) {
        *down = YES;
    }
    btn = profile.buttons[@"Direction Pad Left"];
    if (neo_dpadDirectionPressed(btn)) {
        *left = YES;
    }
    btn = profile.buttons[@"Direction Pad Right"];
    if (neo_dpadDirectionPressed(btn)) {
        *right = YES;
    }
}

static GCControllerButtonInput *neo_profileButtonNamed(GCPhysicalInputProfile *profile,
                                                       NSString *gcKey,
                                                       NSString *legacyName) API_AVAILABLE(ios(14.0), tvos(14.0)) {
    if (profile == nil || profile.buttons == nil) {
        return nil;
    }
    GCControllerButtonInput *btn = nil;
    if (gcKey != nil) {
        btn = profile.buttons[gcKey];
    }
    if (btn == nil && legacyName != nil) {
        btn = profile.buttons[legacyName];
    }
    return btn;
}

static BOOL neo_orButtonPressed(GCControllerButtonInput *extendedButton,
                                GCPhysicalInputProfile *liveProfile,
                                GCPhysicalInputProfile *capturedProfile,
                                NSString *gcKey,
                                NSString *legacyName) API_AVAILABLE(ios(14.0), tvos(14.0)) {
    if (extendedButton != nil && extendedButton.pressed) {
        return YES;
    }

    GCControllerButtonInput *profileButton = neo_profileButtonNamed(liveProfile, gcKey, legacyName);
    if (neo_dpadDirectionPressed(profileButton)) {
        return YES;
    }

    profileButton = neo_profileButtonNamed(capturedProfile, gcKey, legacyName);
    return neo_dpadDirectionPressed(profileButton);
}

static void neo_orDpadFromProfile(GCPhysicalInputProfile *profile,
                                BOOL *up, BOOL *down, BOOL *left, BOOL *right) API_AVAILABLE(ios(14.0), tvos(14.0)) {
    if (profile == nil) {
        return;
    }

    GCControllerDirectionPad *pad = neo_primaryDpadFromProfile(profile);
    if (neo_dpadUpFromDirectionPad(pad)) {
        *up = YES;
    }
    if (neo_dpadDownFromDirectionPad(pad)) {
        *down = YES;
    }
    if (neo_dpadLeftFromDirectionPad(pad)) {
        *left = YES;
    }
    if (neo_dpadRightFromDirectionPad(pad)) {
        *right = YES;
    }

    neo_orDpadFromProfileButtons(profile, up, down, left, right);
}

static BOOL neo_isDpadElement(GCControllerElement *element, GCExtendedGamepad *gamepad) {
    if (element == nil || gamepad == nil) {
        return NO;
    }
    if (neo_isDirectionPadElement(element, gamepad.dpad)) {
        return YES;
    }
    if (@available(iOS 14.0, tvOS 14.0, *)) {
        for (NSString *key in gamepad.controller.physicalInputProfile.dpads) {
            if (neo_isTouchpadDpadKey(key)) {
                continue;
            }
            if (neo_isDirectionPadElement(element, gamepad.controller.physicalInputProfile.dpads[key])) {
                return YES;
            }
        }
    }
    return NO;
}

// UPDATE_BUTTON_FLAG(controller, flag, pressed)
#define UPDATE_BUTTON_FLAG(controller, x, y) \
((y) ? [self setButtonFlag:controller flags:x] : [self clearButtonFlag:controller flags:x])

#define MAX_MAGNITUDE(x, y) (abs(x) > abs(y) ? (x) : (y))

// Methods


- (void)setupObservers
{
    __weak typeof(self) weakSelf = self;
    _controllerConnectObserver = [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidConnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        Log(LOG_I, @"Controller connected!");

        GCController* controller = note.object;

        if (![ControllerSupport isSupportedGamepad:controller]) {
            // Ignore micro gamepads and motion controllers
            return;
        }

        Controller* limeController = [strongSelf assignController:controller];
        if (limeController) {
            [strongSelf registerControllerCallbacks:controller];
            [strongSelf reportControllerArrival:limeController];
            [strongSelf updateAutoOnScreenControlMode];
            [strongSelf->_delegate gamepadPresenceChanged];
        }
    }];
    _controllerDisconnectObserver = [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidDisconnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        Log(LOG_I, @"Controller disconnected!");

        GCController* controller = note.object;

        if (![ControllerSupport isSupportedGamepad:controller]) {
            // Ignore micro gamepads and motion controllers
            return;
        }

        [strongSelf unregisterControllerCallbacks:controller];
        strongSelf->_controllerNumbers &= ~(1 << controller.playerIndex);
        Log(LOG_I, @"Unassigning controller index: %ld", (long)controller.playerIndex);

        Controller* limeController = [strongSelf->_controllers objectForKey:[NSNumber numberWithInteger:controller.playerIndex]];
        if (limeController) {
            [strongSelf cleanupControllerHaptics:limeController];
            [strongSelf cleanupControllerMotion:limeController];
            [strongSelf cleanupControllerBattery:limeController];

            if (limeController.mergedWithController) {
                assert(limeController.mergedWithController.mergedWithController == limeController);
                limeController.mergedWithController.mergedWithController = nil;
            }

            [strongSelf updateFinished:limeController];
            [strongSelf->_controllers removeObjectForKey:[NSNumber numberWithInteger:controller.playerIndex]];
            [strongSelf updateAutoOnScreenControlMode];
            [strongSelf->_delegate gamepadPresenceChanged];
        }
    }];

    if (@available(iOS 14.0, tvOS 14.0, *)) {
        _mouseConnectObserver = [[NSNotificationCenter defaultCenter] addObserverForName:GCMouseDidConnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            Log(LOG_I, @"Mouse connected!");

            GCMouse* mouse = note.object;

            [strongSelf registerMouseCallbacks:mouse];
            [strongSelf updateAutoOnScreenControlMode];
            [strongSelf->_delegate mousePresenceChanged];
        }];
        _mouseDisconnectObserver = [[NSNotificationCenter defaultCenter] addObserverForName:GCMouseDidDisconnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            Log(LOG_I, @"Mouse disconnected!");

            GCMouse* mouse = note.object;
            [strongSelf unregisterMouseCallbacks:mouse];
            [strongSelf updateAutoOnScreenControlMode];
            [strongSelf->_delegate mousePresenceChanged];
        }];
        _keyboardConnectObserver = [[NSNotificationCenter defaultCenter] addObserverForName:GCKeyboardDidConnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            [weakSelf updateAutoOnScreenControlMode];
        }];
        _keyboardDisconnectObserver = [[NSNotificationCenter defaultCenter] addObserverForName:GCKeyboardDidDisconnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            [weakSelf updateAutoOnScreenControlMode];
        }];
    }
}

// Attach the interaction to the view (idempotent — safe to call repeatedly)
- (void)attachGCEventInteractionToView:(UIView *)view {
    if ([view.interactions containsObject:_gcEventInteraction]) {
        return;
    }
    [view addInteraction:_gcEventInteraction];
    NSLog(@"Attached GCEventInteraction to view!");
}

// Detach the interaction from the view
- (void)detachGCEventInteractionFromView:(UIView *)view {
    [view removeInteraction:_gcEventInteraction];
    NSLog(@"Detached GCEventInteraction from view!");
}


-(void) rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(neo_hapticsQueue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        // FIX: Adjust the controller number by subtracting the offset to find the LOCAL controller index.
        // Host sends command for "Controller 1" (Guest), but locally it is index 0.
        int localIndex = controllerNumber - strongSelf->_controllerSlotOffset;

        Controller* controller = [strongSelf->_controllers objectForKey:[NSNumber numberWithInteger:localIndex]];
        if (controller == nil && localIndex == 0 && strongSelf->_oscEnabled) {
            // TODO: Rumble emulation for OSC
        }
        if (controller == nil) {
            return;
        }

        [controller.lowFreqMotor setMotorAmplitude:lowFreqMotor];
        [controller.highFreqMotor setMotorAmplitude:highFreqMotor];
    });
}

-(void) rumbleTriggers:(uint16_t)controllerNumber leftTrigger:(uint16_t)leftTrigger rightTrigger:(uint16_t)rightTrigger
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(neo_hapticsQueue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        int localIndex = controllerNumber - strongSelf->_controllerSlotOffset;

        Controller* controller = [strongSelf->_controllers objectForKey:[NSNumber numberWithInteger:localIndex]];
        if (controller == nil && localIndex == 0 && strongSelf->_oscEnabled) {
            // TODO: Trigger rumble emulation for OSC
        }
        if (controller == nil) {
            return;
        }

        [controller.leftTriggerMotor setMotorAmplitude:leftTrigger];
        [controller.rightTriggerMotor setMotorAmplitude:rightTrigger];
    });
}

- (void) setMotionEventState:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz
{
    if (@available(iOS 14.0, tvOS 14.0, *)) {
        Controller* controller = [_controllers objectForKey:[NSNumber numberWithInteger:controllerNumber]];
        if (controller == nil) {
            // No connected controller for this player
            return;
        }
        
        if (controller.gamepad.motion == nil) {
            // No motion supported for this controller
            return;
        }
        
        switch (motionType) {
            case LI_MOTION_TYPE_ACCEL:
                [controller.accelTimer invalidate];
                controller.accelTimer = nil;
                                                                
                if (reportRateHz && controller.gamepad.motion.hasGravityAndUserAcceleration) {
                    // Reset the last motion sample
                    GCAcceleration emptyAccelSample = {};
                    controller.lastAccelSample = emptyAccelSample;
                    
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        controller.accelTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / reportRateHz repeats:YES block:^(NSTimer *timer) {
                            // Don't send duplicate samples
                            GCAcceleration lastAccelSample = controller.lastAccelSample;
                            GCAcceleration accelSample = controller.gamepad.motion.acceleration;
                            if (memcmp(&accelSample, &lastAccelSample, sizeof(accelSample)) == 0) {
                                return;
                            }
                            controller.lastAccelSample = accelSample;
                            
                            // Convert g to m/s^2
                            LiSendControllerMotionEvent((uint8_t)controllerNumber,
                                                        LI_MOTION_TYPE_ACCEL,
                                                        accelSample.x * -9.80665f,
                                                        accelSample.y * -9.80665f,
                                                        accelSample.z * -9.80665f);
                        }];
                    });
                }
                break;
                
            case LI_MOTION_TYPE_GYRO:
                [controller.gyroTimer invalidate];
                controller.gyroTimer = nil;
                
                if (reportRateHz && controller.gamepad.motion.hasRotationRate) {
                    // Reset the last motion sample
                    GCRotationRate emptyGyroSample = {};
                    controller.lastGyroSample = emptyGyroSample;
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        controller.gyroTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / reportRateHz repeats:YES block:^(NSTimer *timer) {
                            // Don't send duplicate samples
                            GCRotationRate lastGyroSample = controller.lastGyroSample;
                            GCRotationRate gyroSample = controller.gamepad.motion.rotationRate;
                            if (memcmp(&gyroSample, &lastGyroSample, sizeof(gyroSample)) == 0) {
                                return;
                            }
                            controller.lastGyroSample = gyroSample;
                            
                            // Convert rad/s to deg/s
                            LiSendControllerMotionEvent((uint8_t)controllerNumber,
                                                        LI_MOTION_TYPE_GYRO,
                                                        gyroSample.x * 57.2957795f,
                                                        gyroSample.z * 57.2957795f,
                                                        gyroSample.y * -57.2957795f);
                        }];
                    });
                }
                break;
        }
        
        // Set the motion sensor state if they require manual activation
        if (controller.gamepad.motion.sensorsRequireManualActivation) {
            if (controller.gyroTimer || controller.accelTimer) {
                controller.gamepad.motion.sensorsActive = YES;
            }
            else {
                controller.gamepad.motion.sensorsActive = NO;
            }
        }
    }
}

-(void) setControllerLed:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {
    if (@available(iOS 14.0, tvOS 14.0, *)) {
        Controller* controller = [_controllers objectForKey:[NSNumber numberWithInteger:controllerNumber]];
        if (controller == nil) {
            // No connected controller for this player
            return;
        }
        
        if (controller.gamepad.light == nil) {
            // No LED control supported for this controller
            return;
        }
        
        controller.gamepad.light.color = [[GCColor alloc] initWithRed:(r / 255.0f) green:(g / 255.0f) blue:(b / 255.0f)];
    }
}

-(void) updateLeftStick:(Controller*)controller x:(short)x y:(short)y
{
    @synchronized(controller) {
        controller.lastLeftStickX = x;
        controller.lastLeftStickY = y;
    }
}

-(void) updateRightStick:(Controller*)controller x:(short)x y:(short)y
{
    @synchronized(controller) {
        controller.lastRightStickX = x;
        controller.lastRightStickY = y;
    }
}

-(void) updateLeftTrigger:(Controller*)controller left:(unsigned char)left
{
    @synchronized(controller) {
        controller.lastLeftTrigger = left;
    }
}

-(void) updateRightTrigger:(Controller*)controller right:(unsigned char)right
{
    @synchronized(controller) {
        controller.lastRightTrigger = right;
    }
}

-(void) updateTriggers:(Controller*) controller left:(unsigned char)left right:(unsigned char)right
{
    @synchronized(controller) {
        controller.lastLeftTrigger = left;
        controller.lastRightTrigger = right;
    }
}

-(void) handleSpecialCombosReleased:(Controller*)controller releasedButtons:(int)releasedButtons
{
    if ((controller.emulatingButtonFlags & EMULATING_SELECT) && (releasedButtons & (LB_FLAG | PLAY_FLAG))) {
        controller.lastButtonFlags &= ~BACK_FLAG;
        controller.emulatingButtonFlags &= ~EMULATING_SELECT;
    }
    
    if (controller.emulatingButtonFlags & EMULATING_SPECIAL) {
        // If Select is emulated, we use RB+Start to emulate special, otherwise we use Start+Select
        if (controller.supportedEmulationFlags & EMULATING_SELECT) {
            if (releasedButtons & (RB_FLAG | PLAY_FLAG)) {
                controller.lastButtonFlags &= ~SPECIAL_FLAG;
                controller.emulatingButtonFlags &= ~EMULATING_SPECIAL;
            }
        }
        else {
            if (releasedButtons & (BACK_FLAG | PLAY_FLAG)) {
                controller.lastButtonFlags &= ~SPECIAL_FLAG;
                controller.emulatingButtonFlags &= ~EMULATING_SPECIAL;
            }
        }
    }
}

-(void) handleSpecialCombosPressed:(Controller*)controller pressedButtons:(int)pressedButtons
{
    // Special button combos for select and special
    if (controller.lastButtonFlags & PLAY_FLAG) {
        // If LB and start are down, trigger select
        if (controller.lastButtonFlags & LB_FLAG) {
            if (controller.supportedEmulationFlags & EMULATING_SELECT) {
                controller.lastButtonFlags |= BACK_FLAG;
                controller.lastButtonFlags &= ~(pressedButtons & (PLAY_FLAG | LB_FLAG));
                controller.emulatingButtonFlags |= EMULATING_SELECT;
            }
        }
        else if (controller.supportedEmulationFlags & EMULATING_SPECIAL) {
            // If Select is emulated too, use RB+Start to emulate special
            if (controller.supportedEmulationFlags & EMULATING_SELECT) {
                if (controller.lastButtonFlags & RB_FLAG) {
                    controller.lastButtonFlags |= SPECIAL_FLAG;
                    controller.lastButtonFlags &= ~(pressedButtons & (PLAY_FLAG | RB_FLAG));
                    controller.emulatingButtonFlags |= EMULATING_SPECIAL;
                }
            }
            else {
                // If Select is physical, use Start+Select to emulate special
                if (controller.lastButtonFlags & BACK_FLAG) {
                    controller.lastButtonFlags |= SPECIAL_FLAG;
                    controller.lastButtonFlags &= ~(pressedButtons & (PLAY_FLAG | BACK_FLAG));
                    controller.emulatingButtonFlags |= EMULATING_SPECIAL;
                }
            }
        }
    }
}

-(void) updateButtonFlags:(Controller*)controller flags:(int)flags
{
    @synchronized(controller) {
        controller.lastButtonFlags = flags;
        
        // This must be called before handleSpecialCombosPressed
        // because we clear the original button flags there
        int releasedButtons = (controller.lastButtonFlags ^ flags) & ~flags;
        int pressedButtons = (controller.lastButtonFlags ^ flags) & flags;
        
        [self handleSpecialCombosReleased:controller releasedButtons:releasedButtons];
        
        [self handleSpecialCombosPressed:controller pressedButtons:pressedButtons];
    }
}

-(void) setButtonFlag:(Controller*)controller flags:(int)flags
{
    @synchronized(controller) {
        controller.lastButtonFlags |= flags;
        [self handleSpecialCombosPressed:controller pressedButtons:flags];
    }
}

-(void) clearButtonFlag:(Controller*)controller flags:(int)flags
{
    @synchronized(controller) {
        controller.lastButtonFlags &= ~flags;
        [self handleSpecialCombosReleased:controller releasedButtons:flags];
    }
}

-(uint16_t) getActiveGamepadMask
{
    // Base mask: which controllers are present locally
    uint16_t baseMask = (_multiController ? _controllerNumbers : 1) | (_oscEnabled ? 1 : 0);
    
    // FIX: For co-op mode, shift the mask to match the slot offset
    // Host (slot 0): mask stays as 0x1 (bit 0 = controller 0 present)
    // Guest (slot 1): mask becomes 0x2 (bit 1 = controller 1 present)
    if (_controllerSlotOffset > 0) {
        return baseMask << _controllerSlotOffset;
    }
    return baseMask;
}

/// Quit combo and other local side effects after state changes (does not send to host).
-(void) neo_handleControllerStateDidChange:(Controller *)controller
{
    if (controller == nil) {
        return;
    }

    BOOL exitRequested = NO;
    @synchronized(controller) {
        if (controller.lastButtonFlags == (PLAY_FLAG | BACK_FLAG | LB_FLAG | RB_FLAG)) {
            controller.lastButtonFlags = 0;
            exitRequested = YES;
        }
    }

    if (exitRequested) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_delegate streamExitRequested];
        });
    }
}

/// Sends the latest sampled state to the host. Must run on the send queue so LiSend cannot block sampling.
-(void) neo_sendLatestControllerState:(Controller *)controller
{
    if (controller == nil) {
        return;
    }

    [_controllerStreamLock lock];
    @synchronized(controller) {
        if (![self reportControllerArrival:controller]) {
            [_controllerStreamLock unlock];
            return;
        }

        uint32_t buttonFlags = controller.lastButtonFlags;
        uint8_t leftTrigger = controller.lastLeftTrigger;
        uint8_t rightTrigger = controller.lastRightTrigger;
        int16_t leftStickX = controller.lastLeftStickX;
        int16_t leftStickY = controller.lastLeftStickY;
        int16_t rightStickX = controller.lastRightStickX;
        int16_t rightStickY = controller.lastRightStickY;

        if (controller.mergedWithController) {
            buttonFlags |= controller.mergedWithController.lastButtonFlags;
            leftTrigger = MAX(leftTrigger, controller.mergedWithController.lastLeftTrigger);
            rightTrigger = MAX(rightTrigger, controller.mergedWithController.lastRightTrigger);
            leftStickX = MAX_MAGNITUDE(leftStickX, controller.mergedWithController.lastLeftStickX);
            leftStickY = MAX_MAGNITUDE(leftStickY, controller.mergedWithController.lastLeftStickY);
            rightStickX = MAX_MAGNITUDE(rightStickX, controller.mergedWithController.lastRightStickX);
            rightStickY = MAX_MAGNITUDE(rightStickY, controller.mergedWithController.lastRightStickY);
        }

        int controllerNumber = (_multiController ? controller.playerIndex : 0) + _controllerSlotOffset;

        if (_controllerSlotOffset > 0 && !_coopInputLogged) {
            _coopInputLogged = YES;
            Log(LOG_I, @"Co-op input: slotOffset=%d playerIndex=%d controllerNumber=%d mask=0x%x",
                _controllerSlotOffset, controller.playerIndex, controllerNumber, [self getActiveGamepadMask]);
        }

        LiSendMultiControllerEvent(controllerNumber, [self getActiveGamepadMask],
                                   buttonFlags, leftTrigger, rightTrigger,
                                   leftStickX, leftStickY, rightStickX, rightStickY);
    }
    [_controllerStreamLock unlock];
}

/// Transmit current in-memory state on the send queue (does not re-read hardware).
-(void) neo_sendLatestStateForController:(Controller *)controller
{
    if (controller == nil || !_inputSyncEnabled) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(neo_controllerSendQueue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_inputSyncEnabled) {
            return;
        }
        [strongSelf neo_sendLatestControllerState:controller];
    });
}

/// Flush one controller immediately (OSC, release-held). Caller must already have updated in-memory state.
-(void) neo_sendControllerStateNow:(Controller *)controller
{
    [self neo_sendLatestStateForController:controller];
}

-(void) updateFinished:(Controller*)controller
{
    [self neo_handleControllerStateDidChange:controller];
    [self neo_sendControllerStateNow:controller];
}

+(BOOL) hasKeyboardOrMouse {
    if (@available(iOS 14.0, tvOS 14.0, *)) {
        return GCMouse.mice.count > 0 || GCKeyboard.coalescedKeyboard != nil;
    }
    else {
        return NO;
    }
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

-(void) unregisterControllerCallbacks:(GCController*) controller
{
    if (controller != NULL) {
        controller.controllerPausedHandler = NULL;
        
        if (controller.extendedGamepad != NULL) {
            // Re-enable system gestures on the gamepad buttons now
            if (@available(iOS 14.0, tvOS 14.0, *)) {
                for (GCControllerElement* element in controller.physicalInputProfile.allElements) {
                    element.preferredSystemGestureState = GCSystemGestureStateEnabled;
                }
            }
            
            controller.extendedGamepad.valueChangedHandler = NULL;
            controller.physicalInputProfile.valueDidChangeHandler = nil;
        } else if (controller.microGamepad != NULL) {
            // Re-enable system gestures on the gamepad buttons now
            if (@available(iOS 14.0, tvOS 14.0, *)) {
                for (GCControllerElement* element in controller.physicalInputProfile.allElements) {
                    element.preferredSystemGestureState = GCSystemGestureStateEnabled;
                }
            }
            
            controller.microGamepad.valueChangedHandler = NULL;
        }
    }
}

-(void) initializeControllerHaptics:(Controller*) controller
{
    controller.lowFreqMotor = [HapticContext createContextForLowFreqMotor:controller.gamepad];
    controller.highFreqMotor = [HapticContext createContextForHighFreqMotor:controller.gamepad];
    controller.leftTriggerMotor = [HapticContext createContextForLeftTrigger:controller.gamepad];
    controller.rightTriggerMotor = [HapticContext createContextForRightTrigger:controller.gamepad];
}

-(void) initializeControllerHapticsAsync:(Controller*) controller
{
    GCController* gamepad = controller.gamepad;
    if (gamepad == nil) {
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        HapticContext* lowFreq = [HapticContext createContextForLowFreqMotor:gamepad];
        HapticContext* highFreq = [HapticContext createContextForHighFreqMotor:gamepad];
        HapticContext* leftTrigger = [HapticContext createContextForLeftTrigger:gamepad];
        HapticContext* rightTrigger = [HapticContext createContextForRightTrigger:gamepad];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (controller.gamepad == gamepad) {
                controller.lowFreqMotor = lowFreq;
                controller.highFreqMotor = highFreq;
                controller.leftTriggerMotor = leftTrigger;
                controller.rightTriggerMotor = rightTrigger;
                Log(LOG_I, @"[NeoMoonlight] Haptic engines assigned to controller %d", controller.playerIndex);
            } else {
                [lowFreq cleanup];
                [highFreq cleanup];
                [leftTrigger cleanup];
                [rightTrigger cleanup];
            }
        });
    });
}

-(void) cleanupControllerHaptics:(Controller*) controller
{
    if (controller == nil) {
        return;
    }

    dispatch_sync(neo_hapticsQueue(), ^{
        HapticContext* lowFreq = controller.lowFreqMotor;
        HapticContext* highFreq = controller.highFreqMotor;
        HapticContext* leftTrigger = controller.leftTriggerMotor;
        HapticContext* rightTrigger = controller.rightTriggerMotor;
        controller.lowFreqMotor = nil;
        controller.highFreqMotor = nil;
        controller.leftTriggerMotor = nil;
        controller.rightTriggerMotor = nil;

        [lowFreq cleanup];
        [highFreq cleanup];
        [leftTrigger cleanup];
        [rightTrigger cleanup];
    });
}

-(void) cleanupControllerMotion:(Controller*) controller
{
    if (@available(iOS 14.0, tvOS 14.0, *)) {
        // Stop sensor sampling timers
        [controller.gyroTimer invalidate];
        [controller.accelTimer invalidate];
        
        // Disable motion sensors if they require manual activation
        if (controller.gamepad && controller.gamepad.motion && controller.gamepad.motion.sensorsRequireManualActivation) {
            controller.gamepad.motion.sensorsActive = NO;
        }
    }
}

-(void) initializeControllerBattery:(Controller*) controller
{
    if (@available(iOS 14.0, tvOS 14.0, *)) {
        if (controller.gamepad.battery) {
            NSLog(@"[Battery] Initializing battery monitoring for playerIndex=%ld, batteryState=%ld, batteryLevel=%.2f",
                  (long)controller.playerIndex,
                  (long)controller.gamepad.battery.batteryState,
                  controller.gamepad.battery.batteryLevel);
            
            // Send initial battery state unconditionally
            {
                uint8_t batteryState;
                switch (controller.gamepad.battery.batteryState) {
                    case GCDeviceBatteryStateFull:
                        batteryState = LI_BATTERY_STATE_FULL;
                        break;
                    case GCDeviceBatteryStateCharging:
                        batteryState = LI_BATTERY_STATE_CHARGING;
                        break;
                    case GCDeviceBatteryStateDischarging:
                        batteryState = LI_BATTERY_STATE_DISCHARGING;
                        break;
                    case GCDeviceBatteryStateUnknown:
                    default:
                        batteryState = LI_BATTERY_STATE_UNKNOWN;
                        break;
                }
                
                LiSendControllerBatteryEvent(controller.playerIndex, batteryState, (uint8_t)(controller.gamepad.battery.batteryLevel * 100));
                
                controller.lastBatteryState = controller.gamepad.battery.batteryState;
                controller.lastBatteryLevel = controller.gamepad.battery.batteryLevel;
                
                NSLog(@"[Battery] Sending initial battery update to Swift UI: level=%d, state=%u, playerIndex=%ld",
                      (int)(controller.gamepad.battery.batteryLevel * 100), batteryState, (long)controller.playerIndex);
                
                // Update Swift UI for primary controller (playerIndex 0)
                if (controller.playerIndex == 0) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[ControllerBatteryState shared] updateBatteryWithLevel:(int)(controller.gamepad.battery.batteryLevel * 100)
                                                                          state:batteryState
                                                                  hasController:YES];
                    });
                }
            }
            
            // Poll for updated battery status every 5 seconds
            controller.batteryTimer = [NSTimer scheduledTimerWithTimeInterval:5 repeats:YES block:^(NSTimer *timer) {
                if (controller.lastBatteryState != controller.gamepad.battery.batteryState ||
                    controller.lastBatteryLevel != controller.gamepad.battery.batteryLevel) {
                    uint8_t batteryState;
                    
                    switch (controller.gamepad.battery.batteryState) {
                        case GCDeviceBatteryStateFull:
                            batteryState = LI_BATTERY_STATE_FULL;
                            break;
                        case GCDeviceBatteryStateCharging:
                            batteryState = LI_BATTERY_STATE_CHARGING;
                            break;
                        case GCDeviceBatteryStateDischarging:
                            batteryState = LI_BATTERY_STATE_DISCHARGING;
                            break;
                        case GCDeviceBatteryStateUnknown:
                        default:
                            batteryState = LI_BATTERY_STATE_UNKNOWN;
                            break;
                    }
                    
                    LiSendControllerBatteryEvent(controller.playerIndex, batteryState, (uint8_t)(controller.gamepad.battery.batteryLevel * 100));
                    
                    controller.lastBatteryState = controller.gamepad.battery.batteryState;
                    controller.lastBatteryLevel = controller.gamepad.battery.batteryLevel;
                    
                    NSLog(@"[Battery] Battery update: level=%d, state=%u, playerIndex=%ld",
                          (int)(controller.gamepad.battery.batteryLevel * 100), batteryState, (long)controller.playerIndex);
                    
                    // Update Swift UI for primary controller (playerIndex 0)
                    if (controller.playerIndex == 0) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[ControllerBatteryState shared] updateBatteryWithLevel:(int)(controller.gamepad.battery.batteryLevel * 100)
                                                                              state:batteryState
                                                                      hasController:YES];
                        });
                    }
                }
            }];
        } else {
            NSLog(@"[Battery] No battery available for controller playerIndex=%ld", (long)controller.playerIndex);
        }
    }
}

-(void) cleanupControllerBattery:(Controller*) controller
{
    if (@available(iOS 14.0, tvOS 14.0, *)) {
        [controller.batteryTimer invalidate];
        
        // Update Swift UI when primary controller disconnects
        if (controller.playerIndex == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[ControllerBatteryState shared] updateBatteryWithLevel:0
                                                                  state:LI_BATTERY_STATE_UNKNOWN
                                                          hasController:NO];
            });
        }
    }
}

-(BOOL) reportControllerArrival:(Controller*) limeController
{
    // Only report arrival once
    if (limeController.reportedArrival) {
        return YES;
    }
    
    uint8_t type = LI_CTYPE_UNKNOWN;
    uint16_t capabilities = 0;
    uint32_t supportedButtonFlags = 0;
    
    GCController *controller = limeController.gamepad;
    if (controller) {
        // This is a physical controller with a corresponding GCController object
        
        // Start is always present
        supportedButtonFlags |= PLAY_FLAG;
        
        // Detect buttons present in the GCExtendedGamepad profile
        if (controller.gamepad.dpad || controller.microGamepad.dpad) {
            supportedButtonFlags |= UP_FLAG | DOWN_FLAG | LEFT_FLAG | RIGHT_FLAG;
        }
        if (controller.gamepad.leftShoulder || controller.gamepad.leftShoulder) {
            supportedButtonFlags |= LB_FLAG;
        }
        if (controller.gamepad.rightShoulder) {
            supportedButtonFlags |= RB_FLAG;
        }
        if (@available(iOS 13.0, tvOS 13.0, *)) {
            if (controller.extendedGamepad.buttonOptions) {
                supportedButtonFlags |= BACK_FLAG;
            }
        }
        if (@available(iOS 14.0, tvOS 14.0, *)) {
            if (controller.extendedGamepad.buttonHome) {
                supportedButtonFlags |= SPECIAL_FLAG;
            }
        }
        if (controller.gamepad.buttonA) {
            supportedButtonFlags |= A_FLAG;
        }
        if (controller.gamepad.buttonB) {
            supportedButtonFlags |= B_FLAG;
        }
        if (controller.gamepad.buttonX) {
            supportedButtonFlags |= X_FLAG;
        }
        if (controller.gamepad.buttonY) {
            supportedButtonFlags |= Y_FLAG;
        }
        if (@available(iOS 12.1, tvOS 12.1, *)) {
            if (controller.extendedGamepad.leftThumbstickButton) {
                supportedButtonFlags |= LS_CLK_FLAG;
            }
            if (controller.extendedGamepad.rightThumbstickButton) {
                supportedButtonFlags |= RS_CLK_FLAG;
            }
        }
        
        if (@available(iOS 14.0, tvOS 14.0, *)) {
            // Xbox One/Series controller
            if (controller.physicalInputProfile.buttons[GCInputXboxPaddleOne]) {
                supportedButtonFlags |= PADDLE1_FLAG;
            }
            if (controller.physicalInputProfile.buttons[GCInputXboxPaddleTwo]) {
                supportedButtonFlags |= PADDLE2_FLAG;
            }
            if (controller.physicalInputProfile.buttons[GCInputXboxPaddleThree]) {
                supportedButtonFlags |= PADDLE3_FLAG;
            }
            if (controller.physicalInputProfile.buttons[GCInputXboxPaddleFour]) {
                supportedButtonFlags |= PADDLE4_FLAG;
            }
            if (@available(iOS 15.0, tvOS 15.0, *)) {
                if (controller.physicalInputProfile.buttons[GCInputButtonShare]) {
                    supportedButtonFlags |= MISC_FLAG;
                }
            }
            
            // DualShock/DualSense controller
            if (controller.physicalInputProfile.buttons[GCInputDualShockTouchpadButton]) {
                supportedButtonFlags |= TOUCHPAD_FLAG;
            }
            if (controller.physicalInputProfile.dpads[GCInputDualShockTouchpadOne]) {
                capabilities |= LI_CCAP_TOUCHPAD;
            }
            
            if ([controller.extendedGamepad isKindOfClass:[GCXboxGamepad class]] || [controller.gamepad isKindOfClass:[GCXboxGamepad class]]) {
                type = LI_CTYPE_XBOX;
            }
            else if ([controller.extendedGamepad isKindOfClass:[GCDualShockGamepad class]] || [controller.gamepad isKindOfClass:[GCDualShockGamepad class]]) {
                type = LI_CTYPE_PS;
            }
            
            if (@available(iOS 14.5, tvOS 14.5, *)) {
                if ([controller.extendedGamepad isKindOfClass:[GCDualSenseGamepad class]] || [controller.gamepad isKindOfClass:[GCDualSenseGamepad class]]) {
                    type = LI_CTYPE_PS;
                }
            }
            
            // Detect supported haptics localities
            if (controller.haptics) {
                if ([controller.haptics.supportedLocalities containsObject:GCHapticsLocalityHandles]) {
                    capabilities |= LI_CCAP_RUMBLE;
                }
                if ([controller.haptics.supportedLocalities containsObject:GCHapticsLocalityTriggers]) {
                    capabilities |= LI_CCAP_TRIGGER_RUMBLE;
                }
            }
            
            // Detect supported motion sensors
            if (controller.motion) {
                if (controller.motion.hasGravityAndUserAcceleration) {
                    capabilities |= LI_CCAP_ACCEL;
                }
                if (controller.motion.hasRotationRate) {
                    capabilities |= LI_CCAP_GYRO;
                }
            }
            
            // Detect RGB LED support
            if (controller.light) {
                capabilities |= LI_CCAP_RGB_LED;
            }
            
            // Detect battery support
            if (controller.battery) {
                capabilities |= LI_CCAP_BATTERY_STATE;
            }
        }
        else {
            // This is a virtual controller corresponding to our OSC

            // TODO: Support various layouts and button labels on the OSC
            type = LI_CTYPE_XBOX;
            capabilities = 0;
            supportedButtonFlags =
                PLAY_FLAG | BACK_FLAG | UP_FLAG | DOWN_FLAG | LEFT_FLAG | RIGHT_FLAG |
                LB_FLAG | RB_FLAG | LS_CLK_FLAG | RS_CLK_FLAG | A_FLAG | B_FLAG | X_FLAG | Y_FLAG;
        }

        if (_reportControllerAsXbox && type == LI_CTYPE_PS) {
            type = LI_CTYPE_XBOX;
            supportedButtonFlags &= ~TOUCHPAD_FLAG;
            capabilities &= ~(LI_CCAP_TOUCHPAD | LI_CCAP_TRIGGER_RUMBLE | LI_CCAP_ACCEL | LI_CCAP_GYRO | LI_CCAP_RGB_LED);
            Log(LOG_I, @"Reporting PlayStation controller as Xbox to host (XInput compatibility mode)");
        }
    }

    // Report the new controller to the host
    // NB: This will fail if the connection hasn't been fully established yet
    // and we will try again later.
    // FIX: Apply co-op slot offset to controller number (must match LiSendMultiControllerEvent)
    int controllerNumber = controller.playerIndex + _controllerSlotOffset;
    Log(LOG_I, @"Reporting controller arrival: playerIndex=%d, slotOffset=%d, controllerNumber=%d",
        controller.playerIndex, _controllerSlotOffset, controllerNumber);
    if (LiSendControllerArrivalEvent(controllerNumber,
                                     [self getActiveGamepadMask],
                                     type,
                                     supportedButtonFlags,
                                     capabilities) != 0) {
        return NO;
    }
    
    // Begin polling for battery status
    [self initializeControllerBattery:limeController];
    
    // Remember that we've reported arrival already
    limeController.reportedArrival = YES;
    return YES;
}

-(void) handleControllerTouchpad:(Controller*)controller touch:(GCControllerDirectionPad*)touch index:(int)index
{
    controller_touch_context_t context = index == 0 ? controller.primaryTouch : controller.secondaryTouch;
    
    // This magic is courtesy of SDL
    float normalizedX = (1.0f + touch.xAxis.value) * 0.5f;
    float normalizedY = 1.0f - (1.0f + touch.yAxis.value) * 0.5f;
    
    // If we went from a touch to no touch, generate a touch up event
    if ((context.lastX || context.lastY) && (!touch.xAxis.value && !touch.yAxis.value)) {
        LiSendControllerTouchEvent(controller.playerIndex, LI_TOUCH_EVENT_UP, index, normalizedX, normalizedY, 1.0f);
    }
    else if (touch.xAxis.value || touch.yAxis.value) {
        // If we went from no touch to a touch, generate a touch down event
        if (!context.lastX && !context.lastY) {
            LiSendControllerTouchEvent(controller.playerIndex, LI_TOUCH_EVENT_DOWN, index, normalizedX, normalizedY, 1.0f);
        }
        else if (context.lastX != touch.xAxis.value || context.lastY != touch.yAxis.value) {
            // Otherwise it's just a move
            LiSendControllerTouchEvent(controller.playerIndex, LI_TOUCH_EVENT_MOVE, index, normalizedX, normalizedY, 1.0f);
        }
    }
    
    // We have to assign the whole struct because this is a property rather than a standard
    // field that we could modify through a pointer.
    if (index == 0) {
        controller.primaryTouch = (controller_touch_context_t) {
            touch.xAxis.value,
            touch.yAxis.value
        };
    }
    else {
        controller.secondaryTouch = (controller_touch_context_t) {
            touch.xAxis.value,
            touch.yAxis.value
        };
    }
}

/// Sync DualSense extended profile from physical hardware (unsticks stale extendedGamepad.dpad after app switch).
-(void) neo_prewarmDualSenseGamepadIfNeeded:(GCExtendedGamepad *)gamepad API_AVAILABLE(ios(14.5), tvos(14.5)) {
    if (gamepad == nil || ![gamepad isKindOfClass:[GCDualSenseGamepad class]]) {
        return;
    }

    GCDualSenseGamepad *dualSense = (GCDualSenseGamepad *)gamepad;
    GCPhysicalInputProfile *profile = gamepad.controller.physicalInputProfile;
    if (profile == nil) {
        return;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    if ([dualSense respondsToSelector:@selector(setStateFromPhysicalInput:)]) {
        [dualSense setStateFromPhysicalInput:profile];
    }
#pragma clang diagnostic pop
}

/// DualSense D-pad: OR extended, live profile, profile buttons, and capture snapshot.
-(void) neo_applyDpadToController:(GCExtendedGamepad *)gamepad limeController:(Controller *)limeController
{
    BOOL up = neo_dpadUpPressed(gamepad);
    BOOL down = neo_dpadDownPressed(gamepad);
    BOOL left = neo_dpadLeftPressed(gamepad);
    BOOL right = neo_dpadRightPressed(gamepad);

    if (@available(iOS 14.0, tvOS 14.0, *)) {
        neo_orDpadFromProfile(gamepad.controller.physicalInputProfile, &up, &down, &left, &right);

        GCPhysicalInputProfile *captured = [gamepad.controller.physicalInputProfile capture];
        neo_orDpadFromProfile(captured, &up, &down, &left, &right);
    }

    UPDATE_BUTTON_FLAG(limeController, UP_FLAG, up);
    UPDATE_BUTTON_FLAG(limeController, DOWN_FLAG, down);
    UPDATE_BUTTON_FLAG(limeController, LEFT_FLAG, left);
    UPDATE_BUTTON_FLAG(limeController, RIGHT_FLAG, right);
}

/// Sticks and triggers only — no physicalInputProfile capture (safe at 60 Hz on send queue).
-(void) neo_applyAnalogAxesFromGamepad:(GCExtendedGamepad *)gamepad toController:(Controller *)limeController
{
    short leftStickX = gamepad.leftThumbstick.xAxis.value * 0x7FFE;
    short leftStickY = gamepad.leftThumbstick.yAxis.value * 0x7FFE;
    short rightStickX = gamepad.rightThumbstick.xAxis.value * 0x7FFE;
    short rightStickY = gamepad.rightThumbstick.yAxis.value * 0x7FFE;
    unsigned char leftTrigger = gamepad.leftTrigger.value * 0xFF;
    unsigned char rightTrigger = gamepad.rightTrigger.value * 0xFF;

    [self updateLeftStick:limeController x:leftStickX y:leftStickY];
    [self updateRightStick:limeController x:rightStickX y:rightStickY];
    [self updateTriggers:limeController left:leftTrigger right:rightTrigger];
}

/// Buttons, D-pad, and touchpad — uses physicalInputProfile OR path for DualSense D-pad.
-(void) neo_applyDigitalInputFromGamepad:(GCExtendedGamepad *)gamepad toController:(Controller *)limeController
{
    GCPhysicalInputProfile *liveProfile = nil;
    GCPhysicalInputProfile *capturedProfile = nil;
    if (@available(iOS 14.0, tvOS 14.0, *)) {
        liveProfile = gamepad.controller.physicalInputProfile;
        capturedProfile = [liveProfile capture];
    }

    if (self->_swapABXYButtons) {
        BOOL b = neo_orButtonPressed(gamepad.buttonA, liveProfile, capturedProfile, GCInputButtonA, @"Button A");
        BOOL a = neo_orButtonPressed(gamepad.buttonB, liveProfile, capturedProfile, GCInputButtonB, @"Button B");
        BOOL y = neo_orButtonPressed(gamepad.buttonX, liveProfile, capturedProfile, GCInputButtonX, @"Button X");
        BOOL x = neo_orButtonPressed(gamepad.buttonY, liveProfile, capturedProfile, GCInputButtonY, @"Button Y");
        UPDATE_BUTTON_FLAG(limeController, B_FLAG, b);
        UPDATE_BUTTON_FLAG(limeController, A_FLAG, a);
        UPDATE_BUTTON_FLAG(limeController, Y_FLAG, y);
        UPDATE_BUTTON_FLAG(limeController, X_FLAG, x);
    }
    else {
        BOOL a = neo_orButtonPressed(gamepad.buttonA, liveProfile, capturedProfile, GCInputButtonA, @"Button A");
        BOOL b = neo_orButtonPressed(gamepad.buttonB, liveProfile, capturedProfile, GCInputButtonB, @"Button B");
        BOOL x = neo_orButtonPressed(gamepad.buttonX, liveProfile, capturedProfile, GCInputButtonX, @"Button X");
        BOOL y = neo_orButtonPressed(gamepad.buttonY, liveProfile, capturedProfile, GCInputButtonY, @"Button Y");
        UPDATE_BUTTON_FLAG(limeController, A_FLAG, a);
        UPDATE_BUTTON_FLAG(limeController, B_FLAG, b);
        UPDATE_BUTTON_FLAG(limeController, X_FLAG, x);
        UPDATE_BUTTON_FLAG(limeController, Y_FLAG, y);
    }

    [self neo_applyDpadToController:gamepad limeController:limeController];

    BOOL lb = neo_orButtonPressed(gamepad.leftShoulder, liveProfile, capturedProfile, GCInputLeftShoulder, @"Left Shoulder");
    BOOL rb = neo_orButtonPressed(gamepad.rightShoulder, liveProfile, capturedProfile, GCInputRightShoulder, @"Right Shoulder");
    UPDATE_BUTTON_FLAG(limeController, LB_FLAG, lb);
    UPDATE_BUTTON_FLAG(limeController, RB_FLAG, rb);

    if (@available(iOS 12.1, tvOS 12.1, *)) {
        if (gamepad.leftThumbstickButton != nil) {
            BOOL ls = neo_orButtonPressed(gamepad.leftThumbstickButton, liveProfile, capturedProfile, GCInputLeftThumbstickButton, nil);
            UPDATE_BUTTON_FLAG(limeController, LS_CLK_FLAG, ls);
        }
        if (gamepad.rightThumbstickButton != nil) {
            BOOL rs = neo_orButtonPressed(gamepad.rightThumbstickButton, liveProfile, capturedProfile, GCInputRightThumbstickButton, nil);
            UPDATE_BUTTON_FLAG(limeController, RS_CLK_FLAG, rs);
        }
    }

    if (@available(iOS 13.0, tvOS 13.0, *)) {
        BOOL back = neo_orButtonPressed(gamepad.buttonOptions, liveProfile, capturedProfile, GCInputButtonOptions, @"Button Options");
        BOOL play = neo_orButtonPressed(gamepad.buttonMenu, liveProfile, capturedProfile, GCInputButtonMenu, @"Button Menu");
        UPDATE_BUTTON_FLAG(limeController, BACK_FLAG, back);
        UPDATE_BUTTON_FLAG(limeController, PLAY_FLAG, play);
    }

    if (@available(iOS 14.0, tvOS 14.0, *)) {
        BOOL special = neo_orButtonPressed(gamepad.buttonHome, liveProfile, capturedProfile, GCInputButtonHome, @"Button Home");
        UPDATE_BUTTON_FLAG(limeController, SPECIAL_FLAG, special);

        if (gamepad.controller.physicalInputProfile.buttons[GCInputXboxPaddleOne]) {
            UPDATE_BUTTON_FLAG(limeController, PADDLE1_FLAG, gamepad.controller.physicalInputProfile.buttons[GCInputXboxPaddleOne].pressed);
        }
        if (gamepad.controller.physicalInputProfile.buttons[GCInputXboxPaddleTwo]) {
            UPDATE_BUTTON_FLAG(limeController, PADDLE2_FLAG, gamepad.controller.physicalInputProfile.buttons[GCInputXboxPaddleTwo].pressed);
        }
        if (gamepad.controller.physicalInputProfile.buttons[GCInputXboxPaddleThree]) {
            UPDATE_BUTTON_FLAG(limeController, PADDLE3_FLAG, gamepad.controller.physicalInputProfile.buttons[GCInputXboxPaddleThree].pressed);
        }
        if (gamepad.controller.physicalInputProfile.buttons[GCInputXboxPaddleFour]) {
            UPDATE_BUTTON_FLAG(limeController, PADDLE4_FLAG, gamepad.controller.physicalInputProfile.buttons[GCInputXboxPaddleFour].pressed);
        }
        if (@available(iOS 15.0, tvOS 15.0, *)) {
            if (gamepad.controller.physicalInputProfile.buttons[GCInputButtonShare]) {
                UPDATE_BUTTON_FLAG(limeController, MISC_FLAG, gamepad.controller.physicalInputProfile.buttons[GCInputButtonShare].pressed);
            }
        }

        if (gamepad.controller.physicalInputProfile.buttons[GCInputDualShockTouchpadButton]) {
            UPDATE_BUTTON_FLAG(limeController, TOUCHPAD_FLAG, gamepad.controller.physicalInputProfile.buttons[GCInputDualShockTouchpadButton].pressed);
        }
        if (gamepad.controller.physicalInputProfile.dpads[GCInputDualShockTouchpadOne]) {
            [self handleControllerTouchpad:limeController
                                     touch:gamepad.controller.physicalInputProfile.dpads[GCInputDualShockTouchpadOne]
                                     index:0];
        }
        if (gamepad.controller.physicalInputProfile.dpads[GCInputDualShockTouchpadTwo]) {
            [self handleControllerTouchpad:limeController
                                     touch:gamepad.controller.physicalInputProfile.dpads[GCInputDualShockTouchpadTwo]
                                     index:1];
        }
    }
}

/// Applies extended gamepad element state to a Moonlight controller (no network send).
-(void) neo_applyExtendedGamepad:(GCExtendedGamepad *)gamepad toController:(Controller *)limeController
{
    [self neo_applyDigitalInputFromGamepad:gamepad toController:limeController];
    [self neo_applyAnalogAxesFromGamepad:gamepad toController:limeController];
}

-(BOOL) neo_syncDigitalFromGamepad:(Controller *)limeController gamepad:(GCExtendedGamepad *)gamepad
{
    int priorFlags;
    @synchronized(limeController) {
        priorFlags = limeController.lastButtonFlags;
    }

    [self neo_applyDigitalInputFromGamepad:gamepad toController:limeController];

    @synchronized(limeController) {
        return limeController.lastButtonFlags != priorFlags;
    }
}

-(BOOL) neo_isInDualSensePrewarmWindow
{
    if (_foregroundRestoreStartTime <= 0) {
        return NO;
    }
    NSTimeInterval elapsed = CFAbsoluteTimeGetCurrent() - _foregroundRestoreStartTime;
    return elapsed < NEO_DPAD_AGGRESSIVE_PREWARM_DURATION;
}

-(void) neo_maybeRefreshGamepadHandlersForHealth
{
    // Disabled during steady streaming — foreground restore handles handler recovery.
    (void)NEO_GAMEPAD_HANDLER_HEALTH_INTERVAL;
}

/// Single digital sample path (buttons/D-pad) on the input queue.
-(BOOL) neo_sampleDigitalFromHardware:(Controller *)limeController gamepad:(GCExtendedGamepad *)gamepad
{
    if (limeController == nil || gamepad == nil || !_inputSyncEnabled) {
        return NO;
    }

    if ([self neo_isInDualSensePrewarmWindow]) {
        if (@available(iOS 14.5, tvOS 14.5, *)) {
            [self neo_prewarmDualSenseGamepadIfNeeded:gamepad];
        }
    }

    if ([self neo_syncDigitalFromGamepad:limeController gamepad:gamepad]) {
        [self neo_handleControllerStateDidChange:limeController];
        return YES;
    }
    return NO;
}

-(void) neo_flushLatestStateForAllControllers
{
    if (!_inputSyncEnabled) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(neo_controllerSendQueue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_inputSyncEnabled) {
            return;
        }
        for (Controller *limeController in [strongSelf->_controllers allValues]) {
            [strongSelf neo_sendLatestControllerState:limeController];
        }
    });
}

-(void) inputSyncTick
{
    if (!_inputSyncEnabled) {
        return;
    }

    [self neo_maybeRefreshGamepadHandlersForHealth];

    for (Controller *limeController in [_controllers allValues]) {
        GCExtendedGamepad *gamepad = limeController.gamepad.extendedGamepad;
        if (gamepad == nil) {
            continue;
        }
        [self neo_sampleDigitalFromHardware:limeController gamepad:gamepad];
    }
}

-(void) controllerSendTick
{
    if (!_inputSyncEnabled) {
        return;
    }

    for (Controller *limeController in [_controllers allValues]) {
        GCExtendedGamepad *gamepad = limeController.gamepad.extendedGamepad;
        if (gamepad != nil) {
            [self neo_applyAnalogAxesFromGamepad:gamepad toController:limeController];
        }
        [self neo_sendLatestControllerState:limeController];
    }
}

-(void) neo_refreshControllerStateFromHardware:(Controller *)limeController
{
    GCExtendedGamepad *gamepad = limeController.gamepad.extendedGamepad;
    if (gamepad == nil) {
        return;
    }
    (void)[self neo_sampleDigitalFromHardware:limeController gamepad:gamepad];
}

-(void) startInputSync
{
    [self stopInputSync];
    if (!_inputSyncEnabled) {
        return;
    }

    dispatch_queue_t queue = neo_controllerInputQueue();
    _inputSyncSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    uint64_t interval = (uint64_t)(NSEC_PER_SEC / 30.0);
    dispatch_source_set_timer(_inputSyncSource,
                              dispatch_time(DISPATCH_TIME_NOW, interval),
                              interval,
                              (uint64_t)(NSEC_PER_SEC / 300.0));
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_inputSyncSource, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf inputSyncTick];
    });
    dispatch_resume(_inputSyncSource);
}

-(void) startSendLoop
{
    [self stopSendLoop];
    if (!_inputSyncEnabled) {
        return;
    }

    dispatch_queue_t queue = neo_controllerSendQueue();
    _sendSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    uint64_t interval = (uint64_t)(NSEC_PER_SEC / NEO_CONTROLLER_SEND_HZ);
    dispatch_source_set_timer(_sendSource,
                              dispatch_time(DISPATCH_TIME_NOW, interval),
                              interval,
                              (uint64_t)(NSEC_PER_SEC / (NEO_CONTROLLER_SEND_HZ * 10.0)));
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_sendSource, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf controllerSendTick];
    });
    dispatch_resume(_sendSource);
}

-(void) stopSendLoop
{
    if (_sendSource) {
        dispatch_source_cancel(_sendSource);
        _sendSource = nil;
    }
}

-(void) stopInputSync
{
    if (_inputSyncSource) {
        dispatch_source_cancel(_inputSyncSource);
        _inputSyncSource = nil;
    }
    [self stopSendLoop];
}

-(void) setInputSyncEnabled:(BOOL)enabled
{
    if (enabled) {
        if (_inputSyncEnabled) {
            return;  // Already enabled — avoid redundant handler tear-down
        }
        _inputSyncEnabled = YES;
        _lastGamepadHandlerHealthCheck = 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reregisterConnectedGamepadCallbacksIfNeeded];
        });
        [self refreshControllerStates];
        [self startInputSync];
        [self startSendLoop];
        return;
    }
    if (!_inputSyncEnabled) {
        return;
    }
    _inputSyncEnabled = NO;
    [self stopInputSync];
    [self releaseHeldInputsToHost];
}

-(Controller *)neo_limeControllerForGamepad:(GCController *)gamepad
{
    if (gamepad == nil) {
        return nil;
    }

    for (Controller *limeController in [_controllers allValues]) {
        if (limeController.gamepad == gamepad) {
            return limeController;
        }
    }

    return [_controllers objectForKey:[NSNumber numberWithInteger:gamepad.playerIndex]];
}

/// Rebinds Moonlight controllers to current GCController instances (playerIndex / object can shift after app switch).
-(void) resyncConnectedGamepadReferences
{
    for (GCController *gamepad in [GCController controllers]) {
        if (![ControllerSupport isSupportedGamepad:gamepad] || gamepad.extendedGamepad == nil) {
            continue;
        }

        Controller *limeController = [self neo_limeControllerForGamepad:gamepad];
        if (limeController == nil) {
            limeController = [self assignController:gamepad];
            if (limeController != nil) {
                [self reportControllerArrival:limeController];
            }
            continue;
        }

        limeController.gamepad = gamepad;
    }
}

/// Sample from hardware when handlers may be stale (post-foreground / profile backup path).
-(void) neo_pollControllerFromHardware:(Controller *)limeController
{
    GCExtendedGamepad *gamepad = limeController.gamepad.extendedGamepad;
    if (gamepad == nil) {
        return;
    }
    [self neo_sampleDigitalFromHardware:limeController gamepad:gamepad];
}

/// Must run on the main thread — clears then re-installs handlers iOS may clear when leaving the stream.
-(void) reregisterConnectedGamepadCallbacks
{
    for (GCController *controller in [GCController controllers]) {
        if ([ControllerSupport isSupportedGamepad:controller] && controller.extendedGamepad != nil) {
            [self unregisterControllerCallbacks:controller];
            if (@available(iOS 14.5, tvOS 14.5, *)) {
                if ([self neo_isInDualSensePrewarmWindow]) {
                    [self neo_prewarmDualSenseGamepadIfNeeded:controller.extendedGamepad];
                }
            }
            [self registerControllerCallbacks:controller];
        }
    }
}

static const NSTimeInterval NEO_REREGISTER_DEBOUNCE_INTERVAL = 0.25;

-(void) reregisterConnectedGamepadCallbacksIfNeeded
{
    NSTimeInterval now = CACurrentMediaTime();
    if (_lastReregisterTime > 0 && (now - _lastReregisterTime) < NEO_REREGISTER_DEBOUNCE_INTERVAL) {
        return;
    }
    _lastReregisterTime = now;
    [self reregisterConnectedGamepadCallbacks];
}

/// After app switch, iOS often clears physicalInputProfile handlers after didBecomeActive returns.
-(void) restoreGamepadHandlersAfterForeground
{
    _foregroundRestoreStartTime = CFAbsoluteTimeGetCurrent();

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf resyncConnectedGamepadReferences];
        [strongSelf reregisterConnectedGamepadCallbacksIfNeeded];
    });
    [self refreshControllerStates];
}

-(void) handleApplicationDidBecomeActive
{
    [self restoreGamepadHandlersAfterForeground];
}

-(void) releaseHeldInputsToHost
{
    for (Controller *limeController in [_controllers allValues]) {
        @synchronized(limeController) {
            limeController.lastButtonFlags = 0;
            limeController.lastLeftTrigger = 0;
            limeController.lastRightTrigger = 0;
            limeController.lastLeftStickX = 0;
            limeController.lastLeftStickY = 0;
            limeController.lastRightStickX = 0;
            limeController.lastRightStickY = 0;
        }
        [self neo_handleControllerStateDidChange:limeController];
    }
    [self neo_flushLatestStateForAllControllers];
}

-(void) flushNeutralState
{
    for (Controller *limeController in [_controllers allValues]) {
        @synchronized(limeController) {
            limeController.lastLeftStickX = 0;
            limeController.lastLeftStickY = 0;
            limeController.lastRightStickX = 0;
            limeController.lastRightStickY = 0;
        }
        [self neo_handleControllerStateDidChange:limeController];
    }
    [self neo_flushLatestStateForAllControllers];
}

-(void) refreshControllerStates
{
    if (!_inputSyncEnabled) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(neo_controllerInputQueue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_inputSyncEnabled) {
            return;
        }
        for (Controller *limeController in [strongSelf->_controllers allValues]) {
            GCExtendedGamepad *gamepad = limeController.gamepad.extendedGamepad;
            if (gamepad == nil) {
                continue;
            }
            [strongSelf neo_sampleDigitalFromHardware:limeController gamepad:gamepad];
        }
        [strongSelf neo_flushLatestStateForAllControllers];
    });
}

static BOOL neo_isStickOrTriggerElement(GCControllerElement *element, GCExtendedGamepad *gamepad) {
    if (element == nil || gamepad == nil) {
        return NO;
    }
    if (element == gamepad.leftThumbstick || element == gamepad.rightThumbstick) {
        return YES;
    }
    if (element == gamepad.leftThumbstick.xAxis || element == gamepad.leftThumbstick.yAxis) {
        return YES;
    }
    if (element == gamepad.rightThumbstick.xAxis || element == gamepad.rightThumbstick.yAxis) {
        return YES;
    }
    if (element == gamepad.leftTrigger || element == gamepad.rightTrigger) {
        return YES;
    }
    return NO;
}

/// Backup handler: physicalInputProfile fires for buttons and D-pad (not sticks/triggers).
/// This catches button/D-pad input when extendedGamepad.valueChangedHandler is broken after app switch.
-(void) neo_registerProfileHandlerForController:(GCController *)controller
{
    GCExtendedGamepad *gamepad = controller.extendedGamepad;
    if (gamepad == nil) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    __weak GCController *weakGamepad = controller;

    controller.physicalInputProfile.valueDidChangeHandler = ^(GCPhysicalInputProfile *profile, GCControllerElement *element) {
        __strong GCController *gcController = weakGamepad;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (gcController == nil || strongSelf == nil || !strongSelf->_inputSyncEnabled) {
            return;
        }

        GCExtendedGamepad *liveGamepad = gcController.extendedGamepad;
        if (liveGamepad == nil) {
            return;
        }

        if (neo_isStickOrTriggerElement(element, liveGamepad)) {
            return;
        }

        Controller *limeController = [strongSelf neo_limeControllerForGamepad:gcController];
        if (limeController == nil) {
            return;
        }

        dispatch_async(neo_controllerInputQueue(), ^{
            __strong typeof(weakSelf) strongSelf2 = weakSelf;
            if (!strongSelf2 || !strongSelf2->_inputSyncEnabled) {
                return;
            }
            [strongSelf2 neo_pollControllerFromHardware:limeController];
        });
    };
}

-(void) registerControllerCallbacks:(GCController*) controller
{
    if (controller != NULL) {
        // iOS 13 allows the Start button to behave like a normal button, however
        // older MFi controllers can send an instant down+up event for the start button
        // which means the button will not be down long enough to register on the PC.
        // To work around this issue, use the old controllerPausedHandler if the controller
        // doesn't have a Select button (which indicates it probably doesn't have a proper
        // Start button either).
        BOOL useLegacyPausedHandler = YES;
        if (@available(iOS 13.0, tvOS 13.0, *)) {
            if (controller.extendedGamepad != nil &&
                controller.extendedGamepad.buttonOptions != nil) {
                useLegacyPausedHandler = NO;
            }
        }
        
        if (useLegacyPausedHandler) {
            controller.controllerPausedHandler = ^(GCController *controller) {
                Controller* limeController = [self->_controllers objectForKey:[NSNumber numberWithInteger:controller.playerIndex]];
                
                // Get off the main thread
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                    [self setButtonFlag:limeController flags:PLAY_FLAG];
                    [self updateFinished:limeController];
                    
                    // Pause for 100 ms
                    usleep(100 * 1000);
                    
                    [self clearButtonFlag:limeController flags:PLAY_FLAG];
                    [self updateFinished:limeController];
                });
            };
        }
        
        if (controller.extendedGamepad != NULL || controller.microGamepad != NULL) {
            // Disable system gestures on the gamepad to avoid interfering
            // with in-game controller actions
            if (@available(iOS 14.0, tvOS 14.0, *)) {
                for (GCControllerElement* element in controller.physicalInputProfile.allElements) {
                    element.preferredSystemGestureState = GCSystemGestureStateDisabled;
                }
            }
            if (controller.extendedGamepad != NULL) {
                __weak typeof(self) weakSelf = self;
                __weak GCController *weakGamepad = controller;
                controller.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *gamepad, GCControllerElement *element) {
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    __strong GCController *gcController = weakGamepad;
                    if (!strongSelf || !strongSelf->_inputSyncEnabled || gcController == nil) {
                        return;
                    }

                    dispatch_async(neo_controllerInputQueue(), ^{
                        Controller *limeController = [strongSelf neo_limeControllerForGamepad:gcController];
                        GCExtendedGamepad *liveGamepad = gcController.extendedGamepad;
                        if (limeController == nil || liveGamepad == nil) {
                            return;
                        }
                        if (neo_isStickOrTriggerElement(element, liveGamepad)) {
                            [strongSelf neo_applyAnalogAxesFromGamepad:liveGamepad toController:limeController];
                        } else {
                            [strongSelf neo_sampleDigitalFromHardware:limeController gamepad:liveGamepad];
                        }
                    });
                };
                [self neo_registerProfileHandlerForController:controller];
            } else {
                Log(LOG_W, @"Found Micro pad with following elements: ", controller.physicalInputProfile.elements.allKeys);
                controller.microGamepad.valueChangedHandler = ^(GCMicroGamepad *gamepad, GCControllerElement *element) {
                    Log(LOG_I, @"INPUT DETECTED BY MICRO PAD");
                    gamepad.controller.physicalInputProfile.valueDidChangeHandler(gamepad.controller.physicalInputProfile, element);
                };
                controller.physicalInputProfile.valueDidChangeHandler = ^(GCPhysicalInputProfile *gamepad, GCControllerElement *element) {
                    Controller* limeController = [self->_controllers objectForKey:[NSNumber numberWithInteger:0]];
                    short leftStickX, leftStickY;
                    short rightStickX, rightStickY;
                    unsigned char leftTrigger, rightTrigger;
                    
                    if (self->_swapABXYButtons) {
                        UPDATE_BUTTON_FLAG(limeController, B_FLAG, gamepad.buttons[@"Button A"].pressed);
                        UPDATE_BUTTON_FLAG(limeController, A_FLAG, gamepad.buttons[@"Button B"].pressed);
                        UPDATE_BUTTON_FLAG(limeController, Y_FLAG, gamepad.buttons[@"Button X"].pressed);
                        UPDATE_BUTTON_FLAG(limeController, X_FLAG, gamepad.buttons[@"Button Y"].pressed);
                    }
                    else {
                        UPDATE_BUTTON_FLAG(limeController, A_FLAG, gamepad.buttons[@"Button A"].pressed);
                        UPDATE_BUTTON_FLAG(limeController, B_FLAG, gamepad.buttons[@"Button B"].pressed);
                        UPDATE_BUTTON_FLAG(limeController, X_FLAG, gamepad.buttons[@"Button X"].pressed);
                        UPDATE_BUTTON_FLAG(limeController, Y_FLAG, gamepad.buttons[@"Button Y"].pressed);
                    }
                    
                    UPDATE_BUTTON_FLAG(limeController, UP_FLAG, neo_dpadDirectionPressed(gamepad.buttons[@"Direction Pad Up"]));
                    UPDATE_BUTTON_FLAG(limeController, DOWN_FLAG, neo_dpadDirectionPressed(gamepad.buttons[@"Direction Pad Down"]));
                    UPDATE_BUTTON_FLAG(limeController, LEFT_FLAG, neo_dpadDirectionPressed(gamepad.buttons[@"Direction Pad Left"]));
                    UPDATE_BUTTON_FLAG(limeController, RIGHT_FLAG, neo_dpadDirectionPressed(gamepad.buttons[@"Direction Pad Right"]));
                    
                    UPDATE_BUTTON_FLAG(limeController, LB_FLAG, gamepad.buttons[@"Left Shoulder"].pressed);
                    UPDATE_BUTTON_FLAG(limeController, RB_FLAG, gamepad.buttons[@"Right Shoulder"].pressed);
                    
//                    // Yay, iOS 12.1 now supports analog stick buttons
//                    if (@available(iOS 12.1, tvOS 12.1, *)) {
//                        if (gamepad.leftThumbstickButton != nil) {
//                            UPDATE_BUTTON_FLAG(limeController, LS_CLK_FLAG, gamepad.leftThumbstickButton.pressed);
//                        }
//                        if (gamepad.rightThumbstickButton != nil) {
//                            UPDATE_BUTTON_FLAG(limeController, RS_CLK_FLAG, gamepad.rightThumbstickButton.pressed);
//                        }
//                    }
                    
                    if (@available(iOS 13.0, tvOS 13.0, *)) {
                        // Options button is optional (only present on Xbox One S and PS4 gamepads)
                        if (gamepad.buttons[@"Button Options"] != nil) {
                            UPDATE_BUTTON_FLAG(limeController, BACK_FLAG, gamepad.buttons[@"Button Options"].pressed);//gamepad.buttonOptions.pressed);
                            
                            // For older MFi gamepads, the menu button will already be handled by
                            // the controllerPausedHandler.
                            UPDATE_BUTTON_FLAG(limeController, PLAY_FLAG, gamepad.buttons[@"Button Menu"].pressed); //gamepad.buttonMenu.pressed);
                        }
                    }
                    
                    if (@available(iOS 14.0, tvOS 14.0, *)) {
                        // Home/Guide button is optional (only present on Xbox One S and PS4 gamepads)
                        if (gamepad.buttons[@"Button Home"] != nil) {
                            UPDATE_BUTTON_FLAG(limeController, SPECIAL_FLAG, gamepad.buttons[@"Button Home"].pressed);
                        }
                        
                        if (@available(iOS 15.0, tvOS 15.0, *)) {
                            if (gamepad.buttons[GCInputButtonShare]) {
                                UPDATE_BUTTON_FLAG(limeController, MISC_FLAG, gamepad.buttons[GCInputButtonShare].pressed);
                            }
                        }
                        
                        // DualShock/DualSense controllers
                        if (gamepad.buttons[GCInputDualShockTouchpadButton]) {
                            UPDATE_BUTTON_FLAG(limeController, TOUCHPAD_FLAG, gamepad.buttons[GCInputDualShockTouchpadButton].pressed);
                        }
                        if (gamepad.dpads[GCInputDualShockTouchpadOne]) {
                            [self handleControllerTouchpad:limeController
                                                     touch:gamepad.dpads[GCInputDualShockTouchpadOne]
                                                     index:0];
                        }
                        if (gamepad.dpads[GCInputDualShockTouchpadTwo]) {
                            [self handleControllerTouchpad:limeController
                                                     touch:gamepad.dpads[GCInputDualShockTouchpadTwo]
                                                     index:1];
                        }
                    }
                    
//                    leftStickX = gamepad.leftThumbstick.xAxis.value * 0x7FFE;
//                    leftStickY = gamepad.leftThumbstick.yAxis.value * 0x7FFE;
//                    
//                    rightStickX = gamepad.rightThumbstick.xAxis.value * 0x7FFE;
//                    rightStickY = gamepad.rightThumbstick.yAxis.value * 0x7FFE;
//                    
//                    leftTrigger = gamepad.leftTrigger.value * 0xFF;
//                    rightTrigger = gamepad.rightTrigger.value * 0xFF;
                    
                    [self updateLeftStick:limeController x:0 y:0];
                    [self updateRightStick:limeController x:0 y:0];
                    [self updateTriggers:limeController left:0 right:0];
                    [self updateFinished:limeController];
                };
            }
        }
    } else {
        Log(LOG_W, @"Tried to register controller callbacks on NULL controller");
    }
}

-(void) unregisterMouseCallbacks:(GCMouse*)mouse API_AVAILABLE(ios(14.0)) {
    mouse.mouseInput.mouseMovedHandler = nil;
    
    mouse.mouseInput.leftButton.pressedChangedHandler = nil;
    mouse.mouseInput.middleButton.pressedChangedHandler = nil;
    mouse.mouseInput.rightButton.pressedChangedHandler = nil;
    
    for (GCControllerButtonInput* auxButton in mouse.mouseInput.auxiliaryButtons) {
        auxButton.pressedChangedHandler = nil;
    }
    
#if TARGET_OS_TV
    mouse.mouseInput.scroll.xAxis.valueChangedHandler = nil;
    mouse.mouseInput.scroll.yAxis.valueChangedHandler = nil;
#endif
}

-(void) registerMouseCallbacks:(GCMouse*) mouse API_AVAILABLE(ios(14.0)) {
    __weak typeof(self) weakSelf = self;

    mouse.mouseInput.mouseMovedHandler = ^(GCMouseInput * _Nonnull mouse, float deltaX, float deltaY) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (fabs(deltaX) < 0.0001f && fabs(deltaY) < 0.0001f) {
            return;
        }

        strongSelf->accumulatedDeltaX += deltaX / MOUSE_SPEED_DIVISOR;
        strongSelf->accumulatedDeltaY += -deltaY / MOUSE_SPEED_DIVISOR;

        short truncatedDeltaX = (short)strongSelf->accumulatedDeltaX;
        short truncatedDeltaY = (short)strongSelf->accumulatedDeltaY;

        if (truncatedDeltaX != 0 || truncatedDeltaY != 0) {
            LiSendMouseMoveEvent(truncatedDeltaX, truncatedDeltaY);
            strongSelf->accumulatedDeltaX -= truncatedDeltaX;
            strongSelf->accumulatedDeltaY -= truncatedDeltaY;
        }
    };
    
    mouse.mouseInput.leftButton.pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
        LiSendMouseButtonEvent(pressed ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE, BUTTON_LEFT);
    };
    mouse.mouseInput.middleButton.pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
        LiSendMouseButtonEvent(pressed ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE, BUTTON_MIDDLE);
    };
    mouse.mouseInput.rightButton.pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
        LiSendMouseButtonEvent(pressed ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
    };
    
    if (mouse.mouseInput.auxiliaryButtons != nil) {
        if (mouse.mouseInput.auxiliaryButtons.count >= 1) {
            mouse.mouseInput.auxiliaryButtons[0].pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
                LiSendMouseButtonEvent(pressed ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE, BUTTON_X1);
            };
        }
        if (mouse.mouseInput.auxiliaryButtons.count >= 2) {
            mouse.mouseInput.auxiliaryButtons[1].pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
                LiSendMouseButtonEvent(pressed ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE, BUTTON_X2);
            };
        }
    }
    
    // We use UIPanGestureRecognizer on iPadOS because it allows us to distinguish
    // between discrete and continuous scroll events and also works around a bug
    // in iPadOS 15 where discrete scroll events are dropped. tvOS only supports
    // GCMouse for mice, so we will have to just use it and hope for the best.
#if TARGET_OS_TV
    mouse.mouseInput.scroll.xAxis.valueChangedHandler = ^(GCControllerAxisInput * _Nonnull axis, float value) {
        self->accumulatedScrollX += value;
        
        short truncatedScrollX = (short)self->accumulatedScrollX;
        
        if (truncatedScrollX != 0) {
            // Direction is reversed from vertical scrolling
            LiSendHighResHScrollEvent(-truncatedScrollX * 20);
            
            self->accumulatedScrollX -= truncatedScrollX;
        }
    };
    mouse.mouseInput.scroll.yAxis.valueChangedHandler = ^(GCControllerAxisInput * _Nonnull axis, float value) {
        self->accumulatedScrollY += value;
        
        short truncatedScrollY = (short)self->accumulatedScrollY;
        
        if (truncatedScrollY != 0) {
            LiSendHighResScrollEvent(truncatedScrollY * 20);
            
            self->accumulatedScrollY -= truncatedScrollY;
        }
    };
#endif
}

-(void) updateAutoOnScreenControlMode
{
    // Auto on-screen control support may not be enabled
    if (_osc == NULL) {
        return;
    }
    
    OnScreenControlsLevel level = OnScreenControlsLevelFull;
    
    // We currently stop after the first controller we find.
    // Maybe we'll want to change that logic later.
    for (int i = 0; i < [[GCController controllers] count]; i++) {
        GCController *controller = [GCController controllers][i];
        
        if (controller != NULL) {
            if (controller.extendedGamepad != NULL) {
                level = OnScreenControlsLevelAutoGCExtendedGamepad;
                if (@available(iOS 12.1, tvOS 12.1, *)) {
                    if (controller.extendedGamepad.leftThumbstickButton != nil &&
                        controller.extendedGamepad.rightThumbstickButton != nil) {
                        level = OnScreenControlsLevelAutoGCExtendedGamepadWithStickButtons;
                        if (@available(iOS 13.0, tvOS 13.0, *)) {
                            if (controller.extendedGamepad.buttonOptions != nil) {
                                // Has L3/R3 and Select, so we can show nothing :)
                                level = OnScreenControlsLevelOff;
                            }
                        }
                    }
                }
                break;
            }
        }
    }
    
    // If we didn't find a gamepad present and we have a keyboard or mouse, turn
    // the on-screen controls off to get the overlays out of the way.
    if (level == OnScreenControlsLevelFull && [ControllerSupport hasKeyboardOrMouse]) {
        level = OnScreenControlsLevelOff;
        
        // Ensure the virtual gamepad disappears to avoid confusing some games.
        // If the mouse and keyboard disconnect later, it will reappear when the
        // first OSC input is received.
        LiSendMultiControllerEvent(0, 0, 0, 0, 0, 0, 0, 0, 0);
    }
    
    [_osc setLevel:level];
}

-(void) initAutoOnScreenControlMode:(OnScreenControls*)osc
{
    _osc = osc;
    
    [self updateAutoOnScreenControlMode];
}

-(Controller*) assignController:(GCController*)controller {
    for (int i = 0; i < 4; i++) {
        if (!(_controllerNumbers & (1 << i))) {
            _controllerNumbers |= (1 << i);
            controller.playerIndex = i;
            
            Controller* limeController = [[Controller alloc] init];
            limeController.playerIndex = i;
            limeController.supportedEmulationFlags = EMULATING_SPECIAL | EMULATING_SELECT;
            limeController.gamepad = controller;

            // If this is player 0, it shares state with the OSC
            limeController.mergedWithController = _oscController;
            _oscController.mergedWithController = limeController;
            if (@available(iOS 13.0, tvOS 13.0, *)) {
                if (controller.extendedGamepad != nil &&
                    controller.extendedGamepad.buttonOptions != nil) {
                    // Disable select button emulation since we have a physical select button
                    limeController.supportedEmulationFlags &= ~EMULATING_SELECT;
                }
            }
            
            if (@available(iOS 14.0, tvOS 14.0, *)) {
                if (controller.extendedGamepad != nil &&
                    controller.extendedGamepad.buttonHome != nil) {
                    // Disable special button emulation since we have a physical special button
                    limeController.supportedEmulationFlags &= ~EMULATING_SPECIAL;
                }
            }
            
            // Proactively initialize haptics on background thread at connect time
            [self initializeControllerHapticsAsync:limeController];

            [_controllers setObject:limeController forKey:[NSNumber numberWithInteger:controller.playerIndex]];
            
            
            Log(LOG_I, @"Assigning controller index: %d", i);
            return limeController;
        }
    }
    
    return nil;
}

-(Controller*) getOscController {
    return _oscController;
}

+(bool) isSupportedGamepad:(GCController*) controller {
    return controller.extendedGamepad != nil || controller.microGamepad != nil || controller.gamepad != nil;
}

#pragma clang diagnostic pop

+(int) getGamepadCount {
    int count = 0;
    
    for (GCController* controller in [GCController controllers]) {
        if ([ControllerSupport isSupportedGamepad:controller]) {
            count++;
        }
    }
    
    return count;
}

+(int) getConnectedGamepadMask:(StreamConfiguration*)streamConfig settings:(TemporarySettings* _Nullable) settings {
    int mask = 0;
    
    if (streamConfig.multiController) {
        int i = 0;
        for (GCController* controller in [GCController controllers]) {
            if ([ControllerSupport isSupportedGamepad:controller]) {
                mask |= 1 << i++;
            }
        }
    }
    else {
        // Some games don't deal with having controller reconnected
        // properly so always report controller 1 if not in MC mode
        mask = 0x1;
    }
    if (settings == NULL) {
        DataManager* dataMan = [[DataManager alloc] init];
        settings = [dataMan getSettings];
    }
    OnScreenControlsLevel level = (OnScreenControlsLevel)settings.onscreenControls;
    
    // Even if no gamepads are present, we will always count one if OSC is enabled,
    // or it's set to auto and no keyboard or mouse is present. Absolute touch mode
    // disables the OSC.
    if (level != OnScreenControlsLevelOff && (![ControllerSupport hasKeyboardOrMouse] || level != OnScreenControlsLevelAuto) && !settings.absoluteTouchMode) {
        mask |= 0x1;
    }
    return mask;
}

+(int) getGamepadMaskForSlot:(int)slot
{
    // Return a bitmask for a specific controller slot
    // Used for co-op sessions to assign specific slots to players
    return 1 << slot;
}

-(NSUInteger) getConnectedGamepadCount
{
    return _controllers.count;
}

-(void) setSwapABXYButtons:(BOOL)swap
{
    _swapABXYButtons = swap;
    Log(LOG_I, @"Swap A/B X/Y buttons updated to: %d", swap);
}

-(void) setReportControllerAsXbox:(BOOL)reportAsXbox
{
    if (_reportControllerAsXbox == reportAsXbox) {
        return;
    }
    _reportControllerAsXbox = reportAsXbox;
    Log(LOG_I, @"Report controller as Xbox updated to: %d", reportAsXbox);

    for (Controller* limeController in [_controllers allValues]) {
        if (!limeController.gamepad) {
            continue;
        }
        limeController.reportedArrival = NO;
        [self reportControllerArrival:limeController];
    }
}

-(id) initWithConfig:(StreamConfiguration*)streamConfig delegate:(id<ControllerSupportDelegate>)delegate
{
    self = [super init];
    
    _controllerStreamLock = [[NSLock alloc] init];
    _controllers = [[NSMutableDictionary alloc] init];
    _controllerNumbers = 0;
    _multiController = streamConfig.multiController;
    _swapABXYButtons = streamConfig.swapABXYButtons;
    _reportControllerAsXbox = streamConfig.reportControllerAsXbox;
    _controllerSlotOffset = streamConfig.controllerSlotOffset;
    _delegate = delegate;
    Log(LOG_I, @"ControllerSupport initialized with slotOffset: %d, multiController: %d", _controllerSlotOffset, _multiController);

    _oscController = [[Controller alloc] init];
    _oscController.playerIndex = 0;

    DataManager* dataMan = [[DataManager alloc] init];
    _oscEnabled = (OnScreenControlsLevel)[dataMan getSettings].onscreenControls != OnScreenControlsLevelOff;
    
    _gcEventInteraction = [[GCEventInteraction alloc] init];
    _gcEventInteraction.handledEventTypes = GCUIEventTypeGamepad;
    
    Log(LOG_I, @"Number of supported controllers connected: %d", [ControllerSupport getGamepadCount]);
    Log(LOG_I, @"Multi-controller: %d", _multiController);
    
    _gcEventInteraction = [[GCEventInteraction alloc] init];
    _gcEventInteraction.handledEventTypes = GCUIEventTypeGamepad;
    
    for (GCController* controller in [GCController controllers]) {
        if ([ControllerSupport isSupportedGamepad:controller]) {
            [self assignController:controller];
            [self registerControllerCallbacks:controller];
            
            // Note: We cannot report controller arrival to the host here,
            // because the connection has not been established yet.
        }
    }
    
    if (@available(iOS 14.0, tvOS 14.0, *)) {
        for (GCMouse* mouse in [GCMouse mice]) {
            [self registerMouseCallbacks:mouse];
        }
    }
    
    _controllerConnectObserver = [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidConnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        Log(LOG_I, @"Controller connected!");
        
        GCController* controller = note.object;
        
        if (![ControllerSupport isSupportedGamepad:controller]) {
            // Ignore micro gamepads and motion controllers
            return;
        }
        
        Controller* limeController = [self assignController:controller];
        if (limeController) {
            // Register callbacks on the new controller
            [self registerControllerCallbacks:controller];
            
            // Report the controller arrival to the host if we're connected
            [self reportControllerArrival:limeController];
            
            // Re-evaluate the on-screen control mode
            [self updateAutoOnScreenControlMode];
            
            // Notify the delegate
            [self->_delegate gamepadPresenceChanged];
        }
    }];
    _controllerDisconnectObserver = [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidDisconnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        Log(LOG_I, @"Controller disconnected!");
        
        GCController* controller = note.object;
        
        if (![ControllerSupport isSupportedGamepad:controller]) {
            // Ignore micro gamepads and motion controllers
            return;
        }
        
        [self unregisterControllerCallbacks:controller];
        self->_controllerNumbers &= ~(1 << controller.playerIndex);
        Log(LOG_I, @"Unassigning controller index: %ld", (long)controller.playerIndex);
        
        Controller* limeController = [self->_controllers objectForKey:[NSNumber numberWithInteger:controller.playerIndex]];
        if (limeController) {
            // Stop haptics on this controller
            [self cleanupControllerHaptics:limeController];
            
            // Stop motion reports on this controller
            [self cleanupControllerMotion:limeController];
            
            // Stop battery reports on this controller
            [self cleanupControllerBattery:limeController];
            
            // Disassociate this controller from any controllers merged with it
            if (limeController.mergedWithController) {
                assert(limeController.mergedWithController.mergedWithController == limeController);
                limeController.mergedWithController.mergedWithController = nil;
            }
            
            // Inform the server of the updated active gamepads before removing this controller
            [self updateFinished:limeController];
            [self->_controllers removeObjectForKey:[NSNumber numberWithInteger:controller.playerIndex]];
            
            // Re-evaluate the on-screen control mode
            [self updateAutoOnScreenControlMode];
            
            // Notify the delegate
            [self->_delegate gamepadPresenceChanged];
        }
    }];
    
    if (@available(iOS 14.0, tvOS 14.0, *)) {
        _mouseConnectObserver = [[NSNotificationCenter defaultCenter] addObserverForName:GCMouseDidConnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            Log(LOG_I, @"Mouse connected!");
            
            GCMouse* mouse = note.object;
            
            // Register for mouse events
            [self registerMouseCallbacks: mouse];

            // Re-evaluate the on-screen control mode
            [self updateAutoOnScreenControlMode];
            
            // Notify the delegate
            [self->_delegate mousePresenceChanged];
        }];
        _mouseDisconnectObserver = [[NSNotificationCenter defaultCenter] addObserverForName:GCMouseDidDisconnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            Log(LOG_I, @"Mouse disconnected!");
            
            GCMouse* mouse = note.object;
            
            // Unregister for mouse events
            [self unregisterMouseCallbacks: mouse];

            // Re-evaluate the on-screen control mode
            [self updateAutoOnScreenControlMode];
            
            // Notify the delegate
            [self->_delegate mousePresenceChanged];
        }];
        _keyboardConnectObserver = [[NSNotificationCenter defaultCenter] addObserverForName:GCKeyboardDidConnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            Log(LOG_I, @"Keyboard connected!");
            
            // Re-evaluate the on-screen control mode
            [self updateAutoOnScreenControlMode];
        }];
        _keyboardDisconnectObserver = [[NSNotificationCenter defaultCenter] addObserverForName:GCKeyboardDidDisconnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            Log(LOG_I, @"Keyboard disconnected!");

            // Re-evaluate the on-screen control mode
            [self updateAutoOnScreenControlMode];
        }];
    }

    __weak typeof(self) weakSelf = self;
    _applicationDidBecomeActiveObserver = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf handleApplicationDidBecomeActive];
    }];
    _applicationWillEnterForegroundObserver = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf restoreGamepadHandlersAfterForeground];
    }];

    return self;
}

-(void) connectionEstablished
{
    for (Controller* controller in [_controllers allValues]) {
        // Report the controller arrival to the host if we haven't done so yet
        [self reportControllerArrival:controller];
    }
}

- (void)cleanup
{
    [self setInputSyncEnabled:NO];

    [[NSNotificationCenter defaultCenter] removeObserver:_controllerConnectObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:_controllerDisconnectObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:_mouseConnectObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:_mouseDisconnectObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:_keyboardConnectObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:_keyboardDisconnectObserver];
    if (_applicationDidBecomeActiveObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:_applicationDidBecomeActiveObserver];
        _applicationDidBecomeActiveObserver = nil;
    }
    if (_applicationWillEnterForegroundObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:_applicationWillEnterForegroundObserver];
        _applicationWillEnterForegroundObserver = nil;
    }

    _controllerConnectObserver = nil;
    _controllerDisconnectObserver = nil;
    _mouseConnectObserver = nil;
    _mouseDisconnectObserver = nil;
    _keyboardConnectObserver = nil;
    _keyboardDisconnectObserver = nil;

    _controllerNumbers = 0;

    for (Controller* controller in [_controllers allValues]) {
        [self cleanupControllerHaptics:controller];
        [self cleanupControllerMotion:controller];
        [self cleanupControllerBattery:controller];
    }
    [_controllers removeAllObjects];

    for (GCController* controller in [GCController controllers]) {
        if ([ControllerSupport isSupportedGamepad:controller]) {
            [self unregisterControllerCallbacks:controller];
        }
    }

    if (@available(iOS 14.0, tvOS 14.0, *)) {
        for (GCMouse* mouse in [GCMouse mice]) {
            [self unregisterMouseCallbacks:mouse];
        }
    }
}

@end
