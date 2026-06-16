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
    BOOL _engineReady;
    BOOL _invalidated;
    dispatch_queue_t _lifecycleQueue;
}

@synthesize isReady = _engineReady;

- (void)neo_cleanupOnLifecycleQueue API_AVAILABLE(ios(14.0), tvos(14.0), visionos(1.0)) {
    if (_invalidated) {
        return;
    }
    _invalidated = YES;
    _engineReady = NO;

    CHHapticEngine *engine = _hapticEngine;
    id<CHHapticPatternPlayer> player = _hapticPlayer;
    BOOL wasPlaying = _playing;

    _hapticEngine = nil;
    _hapticPlayer = nil;
    _playing = NO;

    if (engine != nil) {
        engine.stoppedHandler = nil;
        engine.resetHandler = nil;
    }

    if (player != nil && wasPlaying) {
        [player stopAtTime:0 error:nil];
    }

    if (engine != nil) {
        @try {
            [engine stopWithCompletionHandler:nil];
        }
        @catch (NSException *exception) {
            Log(LOG_W, @"Controller %d: Haptic engine stop failed during cleanup: %@", _playerIndex, exception);
        }
    }
}

-(void)cleanup API_AVAILABLE(ios(14.0), tvos(14.0), visionos(1.0)) {
    if (_lifecycleQueue == nil) {
        return;
    }
    dispatch_sync(_lifecycleQueue, ^{
        [self neo_cleanupOnLifecycleQueue];
    });
}

- (void)neo_setMotorAmplitudeOnLifecycleQueue:(unsigned short)amplitude API_AVAILABLE(ios(14.0), tvos(14.0), visionos(1.0)) {
    NSError* error;

    if (_invalidated || _hapticEngine == nil || !_engineReady) {
        return;
    }

    if (amplitude == 0) {
        if (_playing) {
            [_hapticPlayer stopAtTime:0 error:&error];
            _playing = NO;
        }

        return;
    }

    if (_hapticPlayer == nil) {
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

-(void)setMotorAmplitude:(unsigned short)amplitude API_AVAILABLE(ios(14.0), tvos(14.0), visionos(1.0)) {
    if (_lifecycleQueue == nil) {
        return;
    }
    dispatch_sync(_lifecycleQueue, ^{
        [self neo_setMotorAmplitudeOnLifecycleQueue:amplitude];
    });
}

-(id) initWithGamepad:(GCController*)gamepad locality:(GCHapticsLocality)locality API_AVAILABLE(ios(14.0), tvos(14.0), visionos(1.0)) {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _lifecycleQueue = dispatch_queue_create("com.neomoonlight.haptics.context", DISPATCH_QUEUE_SERIAL);

    Log(LOG_I, @"[NeoMoonlight] Initializing Haptics for Player %ld (async)...", (long)gamepad.playerIndex);

    if (gamepad.haptics == nil) {
        Log(LOG_W, @"[NeoMoonlight] FAILURE: Controller %ld haptics is NIL.", (long)gamepad.playerIndex);
        return nil;
    }

    Log(LOG_I, @"[NeoMoonlight] Supported Localities: %@", [gamepad.haptics supportedLocalities]);

    _playerIndex = gamepad.playerIndex;
    _engineReady = NO;
    _invalidated = NO;
    GCHapticsLocality targetLocality = locality;

    if (![[gamepad.haptics supportedLocalities] containsObject:locality]) {
        Log(LOG_W, @"[NeoMoonlight] Requested locality %@ missing. Attempting fallback to 'All'...", locality);
        targetLocality = GCHapticsLocalityAll;

        if (![[gamepad.haptics supportedLocalities] containsObject:GCHapticsLocalityAll]) {
             Log(LOG_W, @"[NeoMoonlight] Even 'All' is not listed. Forcing engine creation anyway as 'Default'...");
             targetLocality = GCHapticsLocalityDefault;
        }
    }

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

    __weak typeof(self) weakSelf = self;
    _hapticEngine.stoppedHandler = ^(CHHapticEngineStoppedReason stoppedReason) {
        HapticContext* me = weakSelf;
        if (me == nil || me->_lifecycleQueue == nil) {
            return;
        }

        dispatch_async(me->_lifecycleQueue, ^{
            if (me->_invalidated) {
                return;
            }

            Log(LOG_W, @"Controller %ld: Haptic engine stopped: %ld", (long)me->_playerIndex, (long)stoppedReason);
            me->_hapticPlayer = nil;
            me->_hapticEngine = nil;
            me->_engineReady = NO;
            me->_playing = NO;
        });
    };
    _hapticEngine.resetHandler = ^{
        HapticContext* me = weakSelf;
        if (me == nil || me->_lifecycleQueue == nil) {
            return;
        }

        dispatch_async(me->_lifecycleQueue, ^{
            if (me->_invalidated) {
                return;
            }

            Log(LOG_W, @"Controller %ld: Haptic engine reset", (long)me->_playerIndex);
            me->_hapticPlayer = nil;
            me->_engineReady = NO;
            me->_playing = NO;

            CHHapticEngine *engine = me->_hapticEngine;
            if (engine == nil) {
                return;
            }

            [engine startWithCompletionHandler:^(NSError* restartError) {
                dispatch_async(me->_lifecycleQueue, ^{
                    if (me->_invalidated || me->_hapticEngine != engine) {
                        return;
                    }
                    if (restartError == nil) {
                        me->_engineReady = YES;
                    }
                });
            }];
        });
    };

    [_hapticEngine startWithCompletionHandler:^(NSError* startError) {
        HapticContext* me = weakSelf;
        if (me == nil || me->_lifecycleQueue == nil) {
            return;
        }

        dispatch_async(me->_lifecycleQueue, ^{
            if (me->_invalidated) {
                return;
            }

            if (startError != nil) {
                Log(LOG_W, @"[NeoMoonlight] Haptic engine async start failed: %@", startError);
                me->_hapticEngine = nil;
                return;
            }

            Log(LOG_I, @"[NeoMoonlight] SUCCESS: Haptic Engine Ready for Player %ld", (long)me->_playerIndex);
            me->_engineReady = YES;
        });
    }];

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
