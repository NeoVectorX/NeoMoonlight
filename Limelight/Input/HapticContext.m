//
//  HapticContext.m
//  Moonlight
//
//  Created by Cameron Gutman on 9/17/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

#import "HapticContext.h"

@import CoreHaptics;
@import GameController;

@implementation HapticContext {
    GCControllerPlayerIndex _playerIndex;
    CHHapticEngine* _hapticEngine API_AVAILABLE(ios(13.0), tvos(14.0), visionos(1.0));
    id<CHHapticPatternPlayer> _hapticPlayer API_AVAILABLE(ios(13.0), tvos(14.0), visionos(1.0));
    BOOL _playing;
}

-(void)cleanup API_AVAILABLE(ios(14.0), tvos(14.0), visionos(1.0)) {
    // Check _hapticEngine first - if stoppedHandler already fired,
    // both _hapticEngine and _hapticPlayer will be nil
    if (_hapticEngine != nil) {
        if (_hapticPlayer != nil) {
            // Only stop if we were actively playing - avoids exception if engine already stopped
            if (_playing) {
                [_hapticPlayer stopAtTime:0 error:nil];
            }
            _hapticPlayer = nil;
        }
        [_hapticEngine stopWithCompletionHandler:nil];
        _hapticEngine = nil;
    }
    _playing = NO;
}

-(void)setMotorAmplitude:(unsigned short)amplitude API_AVAILABLE(ios(14.0), tvos(14.0), visionos(1.0)) {
    NSError* error;

    // Check if the haptic engine died
    if (_hapticEngine == nil) {
        return;
    }
    
    // Stop the effect entirely if the amplitude is 0
    if (amplitude == 0) {
        if (_playing) {
            [_hapticPlayer stopAtTime:0 error:&error];
            _playing = NO;
        }
        
        return;
    }

    if (_hapticPlayer == nil) {
        // We must initialize the intensity to 1.0f because the dynamic parameters are multiplied by this value before being applied
        CHHapticEventParameter* intensityParameter = [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity value:1.0f];
        CHHapticEvent* hapticEvent = [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous parameters:[NSArray arrayWithObject:intensityParameter] relativeTime:0 duration:GCHapticDurationInfinite];
        CHHapticPattern* hapticPattern = [[CHHapticPattern alloc] initWithEvents:[NSArray arrayWithObject:hapticEvent] parameters:[[NSArray alloc] init] error:&error];
        if (error != nil) {
            Log(LOG_W, @"Controller %d: Haptic pattern creation failed: %@", _playerIndex, error);
            return;
        }
        
        _hapticPlayer = [_hapticEngine createPlayerWithPattern:hapticPattern error:&error];
        if (error != nil) {
            Log(LOG_W, @"Controller %d: Haptic player creation failed: %@", _playerIndex, error);
            return;
        }
    }

    CHHapticDynamicParameter* intensityParameter = [[CHHapticDynamicParameter alloc] initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl value:amplitude / 65535.0f relativeTime:0];
    [_hapticPlayer sendParameters:[NSArray arrayWithObject:intensityParameter] atTime:CHHapticTimeImmediate error:&error];
    if (error != nil) {
        Log(LOG_W, @"Controller %d: Haptic player parameter update failed: %@", _playerIndex, error);
        return;
    }
    
    if (!_playing) {
        [_hapticPlayer startAtTime:0 error:&error];
        if (error != nil) {
            _hapticPlayer = nil;
            Log(LOG_W, @"Controller %d: Haptic playback start failed: %@", _playerIndex, error);
            return;
        }
        
        _playing = YES;
    }
}

-(id) initWithGamepad:(GCController*)gamepad locality:(GCHapticsLocality)locality API_AVAILABLE(ios(14.0), tvos(14.0), visionos(1.0)) {
    // 1. DIAGNOSTIC LOGGING
    Log(LOG_I, @"[NeoMoonlight] Initializing Haptics for Player %ld...", (long)gamepad.playerIndex);
    
    if (gamepad.haptics == nil) {
        Log(LOG_W, @"[NeoMoonlight] FAILURE: Controller %ld haptics is NIL.", (long)gamepad.playerIndex);
        return nil;
    }
    
    // Log what the OS actually thinks this controller can do
    Log(LOG_I, @"[NeoMoonlight] Supported Localities: %@", [gamepad.haptics supportedLocalities]);

    _playerIndex = gamepad.playerIndex;
    GCHapticsLocality targetLocality = locality;

    // 2. THE BYPASS LOGIC
    // If the requested locality (e.g., LeftHandle) is NOT supported, try 'All' instead of quitting.
    if (![[gamepad.haptics supportedLocalities] containsObject:locality]) {
        Log(LOG_W, @"[NeoMoonlight] Requested locality %@ missing. Attempting fallback to 'All'...", locality);
        targetLocality = GCHapticsLocalityAll;
        
        // Double check if 'All' is supported, or just force it blindly (Apple sometimes hides capabilities)
        if (![[gamepad.haptics supportedLocalities] containsObject:GCHapticsLocalityAll]) {
             Log(LOG_W, @"[NeoMoonlight] Even 'All' is not listed. Forcing engine creation anyway as 'Default'...");
             targetLocality = GCHapticsLocalityDefault;
        }
    }

    // 3. CREATE ENGINE
    // We use the determined targetLocality (Original -> All -> Default)
    @try {
        _hapticEngine = [gamepad.haptics createEngineWithLocality:targetLocality];
    }
    @catch (NSException *exception) {
        Log(LOG_E, @"[NeoMoonlight] CRASH creating engine: %@", exception);
        return nil;
    }

    if (_hapticEngine == nil) {
         Log(LOG_W, @"[NeoMoonlight] createEngineWithLocality returned nil.");
         return nil;
    }

    NSError* error;
    [_hapticEngine startAndReturnError:&error];
    if (error != nil) {
        Log(LOG_W, @"[NeoMoonlight] Haptic engine failed to start: %@", error);
        return nil;
    }
    
    Log(LOG_I, @"[NeoMoonlight] SUCCESS: Haptic Engine Started for Player %ld", (long)_playerIndex);
    
    __weak typeof(self) weakSelf = self;
    _hapticEngine.stoppedHandler = ^(CHHapticEngineStoppedReason stoppedReason) {
        HapticContext* me = weakSelf;
        if (me == nil) {
            return;
        }
        
        Log(LOG_W, @"Controller %ld: Haptic engine stopped: %ld", (long)me->_playerIndex, (long)stoppedReason);
        me->_hapticPlayer = nil;
        me->_hapticEngine = nil;
        me->_playing = NO;
    };
    _hapticEngine.resetHandler = ^{
        HapticContext* me = weakSelf;
        if (me == nil) {
            return;
        }
        
        Log(LOG_W, @"Controller %ld: Haptic engine reset", (long)me->_playerIndex);
        me->_hapticPlayer = nil;
        me->_playing = NO;
        [me->_hapticEngine startAndReturnError:nil];
    };
    
    return self;
}

+(HapticContext*) createContextForHighFreqMotor:(GCController*)gamepad {
    if (@available(iOS 14.0, tvOS 14.0, visionOS 1.0, *)) {
        return [[HapticContext alloc] initWithGamepad:gamepad locality:GCHapticsLocalityRightHandle];
    }
    else {
        return nil;
    }
}

+(HapticContext*) createContextForLowFreqMotor:(GCController*)gamepad {
    if (@available(iOS 14.0, tvOS 14.0, visionOS 1.0, *)) {
        return [[HapticContext alloc] initWithGamepad:gamepad locality:GCHapticsLocalityLeftHandle];
    }
    else {
        return nil;
    }
}

+(HapticContext*) createContextForLeftTrigger:(GCController*)gamepad {
    if (@available(iOS 14.0, tvOS 14.0, visionOS 1.0, *)) {
        return [[HapticContext alloc] initWithGamepad:gamepad locality:GCHapticsLocalityLeftTrigger];
    }
    else {
        return nil;
    }
}

+(HapticContext*) createContextForRightTrigger:(GCController*)gamepad {
    if (@available(iOS 14.0, tvOS 14.0, visionOS 1.0, *)) {
        return [[HapticContext alloc] initWithGamepad:gamepad locality:GCHapticsLocalityRightTrigger];
    }
    else {
        return nil;
    }
}

@end
