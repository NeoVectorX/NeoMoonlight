//
//  StreamFrameViewController.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/18/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "StreamFrameViewController.h"
#import "MainFrameViewController.h"
#import "VideoDecoderRenderer.h"
#import "StreamManager.h"
#import "ControllerSupport.h"
#import "DataManager.h"
#import "Moonlight-Swift.h"
#import "MetalPresetControllable.h"
#import <TargetConditionals.h>
#import <objc/message.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <Limelight.h>

#if TARGET_OS_TV
#import <AVFoundation/AVDisplayCriteria.h>
#import <AVKit/AVDisplayManager.h>
#import <AVKit/UIWindow.h>
#endif

@interface AVDisplayCriteria()
@property(readonly) int videoDynamicRange;
@property(readonly, nonatomic) float refreshRate;
- (id)initWithRefreshRate:(float)arg1 videoDynamicRange:(int)arg2;
@end

NSString * const StreamDidTeardownNotification = @"StreamDidTeardownNotification";
NSString * const StreamFirstFrameShownNotification = @"StreamFirstFrameShownNotification";
NSString * const StreamControllerDismantledNotification = @"StreamControllerDismantled";

@implementation StreamFrameViewController {
    ControllerSupport *_controllerSupport;
    StreamManager *_streamMan;
    TemporarySettings *_settings;
    NSTimer *_inactivityTimer;
    NSTimer *_statsUpdateTimer;
    UITapGestureRecognizer *_menuTapGestureRecognizer;
    UITapGestureRecognizer *_menuDoubleTapGestureRecognizer;
    UITapGestureRecognizer *_playPauseTapGestureRecognizer;
    UITextView *_overlayView;
    UILabel *_stageLabel;
    UILabel *_tipLabel;
    UIActivityIndicatorView *_spinner;
    StreamView *_streamView;
    UIScrollView *_scrollView;
    BOOL _userIsInteracting;
    CGSize _keyboardSize;
    BOOL _stopStreamCalled;
    BOOL _viewOnlyMode;  // visionOS: view is set up but stream is managed externally
    
    id<AnyVideoDecoderRenderer, MetalPresetControllable> _metalRenderer;
    
#if !TARGET_OS_TV && !TARGET_OS_VISION
    UIScreenEdgePanGestureRecognizer *_exitSwipeRecognizer;
#endif
}

// --- ADD/CHANGE: Strengthen teardown and make it fully idempotent-safe ---
- (void)stopStream {
    if (_stopStreamCalled) {
        Log(LOG_I, @"stopStream() already called; skipping duplicate teardown");
        return;
    }
    _stopStreamCalled = YES;

    Log(LOG_I, @"StreamFrameViewController: stopStream() called from SwiftUI.");

    // Grab a local reference and clear the instance variable
    StreamManager *sm = _streamMan;
    _streamMan = nil;

    // Clean up Metal renderer completely (if active) - with exception handling
    if (_metalRenderer) {
        @try {
            [_metalRenderer shutdown];
        } @catch (NSException *exception) {
            Log(LOG_E, @"Exception during Metal renderer shutdown: %@", exception);
        }
        _metalRenderer = nil;
    }

    // Force static state cleanup from Connection.m
    extern void ResetConnectionStaticState(void);
    ResetConnectionStaticState();

    // Clean up controllers
    if (_controllerSupport) {
        [_controllerSupport cleanup];
        _controllerSupport = nil;
    }

    // Clean up timers
    if (_statsUpdateTimer) {
        [_statsUpdateTimer invalidate];
        _statsUpdateTimer = nil;
    }
    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }

    // Remove observers proactively (in case we're not being deallocated yet)
    [[NSNotificationCenter defaultCenter] removeObserver:self];

#if !TARGET_OS_TV && !TARGET_OS_VISION
    // Remove gestures to avoid callbacks after teardown
    if (_exitSwipeRecognizer) {
        [self.view removeGestureRecognizer:_exitSwipeRecognizer];
        _exitSwipeRecognizer = nil;
    }
#endif

    // Remove overlay if present
    if (_overlayView) {
        [_overlayView removeFromSuperview];
        _overlayView = nil;
    }

    // Remove StreamView and ScrollView (if any) to prevent callbacks/layout on a torn view
    if (_streamView) {
        [_streamView removeFromSuperview];
        _streamView = nil;
    }
    if (_scrollView) {
        [_scrollView removeFromSuperview];
        _scrollView = nil;
    }

    // Allow display to go to sleep
    [UIApplication sharedApplication].idleTimerDisabled = NO;

    // Reset display mode back to default
    [self updatePreferredDisplayMode:NO];

    // Create a block for the final UI feedback and teardown signal
    dispatch_block_t postTeardown = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
#if !TARGET_OS_VISION
            [self->_spinner startAnimating];
            [self->_stageLabel setText:@"Disconnected"];
            [self->_stageLabel sizeToFit];
            self->_stageLabel.hidden = NO;
            self->_tipLabel.hidden = NO;
#endif

            // Notify Swift that teardown is finished so reconnect can proceed safely
            [[NSNotificationCenter defaultCenter] postNotificationName:StreamDidTeardownNotification object:self];
        });
    };

    // Wait for the stream to fully stop before posting the teardown notification
    if (sm) {
        [sm stopStreamWithCompletion:postTeardown];
    } else {
        postTeardown();
    }

#if !TARGET_OS_VISION
    // Ensure config is cleared so a stale config isn't reused accidentally
    // On visionOS, we preserve config for restartStream() to use
    self.streamConfig = nil;
#endif
    
    Log(LOG_I, @"StreamFrameViewController: stopStream() completed");
}

- (void)restartStream {
    Log(LOG_I, @"StreamFrameViewController: restartStream() called");
    
    // If stream is still running, stop it first (but keep config)
    if (_streamMan) {
        [_streamMan stopStreamWithCompletion:nil];
        _streamMan = nil;
    }
    
    // Reset the stop flag so we can stop again later
    _stopStreamCalled = NO;
    
    // Guard: need a valid config to restart
    if (!self.streamConfig) {
        Log(LOG_E, @"restartStream() failed: no streamConfig");
        return;
    }
    
    // Recreate controller support
    if (_controllerSupport) {
        [_controllerSupport cleanup];
    }
    _controllerSupport = [[ControllerSupport alloc] initWithConfig:self.streamConfig delegate:self];
    
    // Recreate the stream manager (same as viewDidLoad)
    _streamMan = [[StreamManager alloc] initWithConfig:self.streamConfig
                                      rendererProvider:^id<AnyVideoDecoderRenderer> __strong {
        return [[VideoDecoderRenderer alloc] initWithView:self->_streamView
                                                callbacks:self
                                        streamAspectRatio:(float)self.streamConfig.width / (float)self.streamConfig.height
                                          useFramePacing:self.streamConfig.useFramePacing];
    }
                                   connectionCallbacks:self];
    
    NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
    [opQueue addOperation:_streamMan];
    
    Log(LOG_I, @"StreamFrameViewController: restartStream() - stream restarted");
}
// --- END CHANGE ---

#pragma mark - visionOS External Stream Control

- (void)setViewOnlyMode:(BOOL)viewOnly {
    _viewOnlyMode = viewOnly;
    Log(LOG_I, @"StreamFrameViewController: viewOnlyMode set to %@", viewOnly ? @"YES" : @"NO");
}

- (BOOL)isStreamActive {
    return _streamMan != nil;
}

- (void)startStreamExternal {
    Log(LOG_I, @"StreamFrameViewController: startStreamExternal() called");
    
    if (_streamMan) {
        Log(LOG_W, @"startStreamExternal: stream already active, ignoring");
        return;
    }
    
    if (!self.streamConfig) {
        Log(LOG_E, @"startStreamExternal: no streamConfig");
        return;
    }
    
    // Reset stop flag
    _stopStreamCalled = NO;
    
    // Ensure controller support exists
    if (!_controllerSupport) {
        _controllerSupport = [[ControllerSupport alloc] initWithConfig:self.streamConfig delegate:self];
    }
    
    // Create and start the stream manager
    _streamMan = [[StreamManager alloc] initWithConfig:self.streamConfig
                                      rendererProvider:^id<AnyVideoDecoderRenderer> __strong {
        return [[VideoDecoderRenderer alloc] initWithView:self->_streamView
                                                callbacks:self
                                        streamAspectRatio:(float)self.streamConfig.width / (float)self.streamConfig.height
                                          useFramePacing:self.streamConfig.useFramePacing];
    }
                                   connectionCallbacks:self];
    
    NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
    [opQueue addOperation:_streamMan];
    
    Log(LOG_I, @"StreamFrameViewController: startStreamExternal() - stream started");
}

- (void)stopStreamExternal {
    Log(LOG_I, @"StreamFrameViewController: stopStreamExternal() called");
    
    if (!_streamMan) {
        Log(LOG_I, @"stopStreamExternal: no stream to stop");
        return;
    }
    
    StreamManager* sm = _streamMan;
    _streamMan = nil;
    
    [sm stopStreamWithCompletion:^{
        Log(LOG_I, @"StreamFrameViewController: stopStreamExternal() — LiStopConnection completed");
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:StreamDidTeardownNotification object:nil];
        });
    }];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
#if !TARGET_OS_TV && !TARGET_OS_VISION
    [[self revealViewController] setPrimaryViewController:self];
#endif
}

#if TARGET_OS_TV
- (void)controllerPauseButtonPressed:(id)sender { }
- (void)controllerPauseButtonDoublePressed:(id)sender {
    Log(LOG_I, @"Menu double-pressed -- backing out of stream");
    [self returnToMainFrame];
}
- (void)controllerPlayPauseButtonPressed:(id)sender {
    Log(LOG_I, @"Play/Pause button pressed -- backing out of stream");
    [self returnToMainFrame];
}
#endif


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.navigationController setNavigationBarHidden:YES animated:YES];
    
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    _settings = [[[DataManager alloc] init] getSettings];

#if !TARGET_OS_VISION
    _spinner = [[UIActivityIndicatorView alloc] init];
    [self.view addSubview:_spinner];
    [_spinner setUserInteractionEnabled:NO];
#if TARGET_OS_TV
    [_spinner setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhiteLarge];
#else
    [_spinner setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleMedium];
#endif
    [_spinner sizeToFit];
    [_spinner startAnimating];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [_spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor].active = YES;
    [_spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
    
    _stageLabel = [[UILabel alloc] init];
    [self.view addSubview:_stageLabel];
    [_stageLabel setUserInteractionEnabled:NO];
    [_stageLabel setText:[NSString stringWithFormat:@"Starting %@...", self.streamConfig.appName]];
    [_stageLabel sizeToFit];
    _stageLabel.textAlignment = NSTextAlignmentCenter;
    _stageLabel.textColor = [UIColor whiteColor];
    _stageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_stageLabel.topAnchor constraintEqualToAnchor:_spinner.bottomAnchor constant:20.0].active = YES;
    [_stageLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
#endif

    _controllerSupport = [[ControllerSupport alloc] initWithConfig:self.streamConfig delegate:self];
    _inactivityTimer = nil;
    
    _streamView = [[StreamView alloc] initWithFrame:self.view.frame];
    [_streamView setupStreamView:_controllerSupport interactionDelegate:self config:self.streamConfig];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _streamView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
#if TARGET_OS_TV
    if (!_menuTapGestureRecognizer || !_menuDoubleTapGestureRecognizer || !_playPauseTapGestureRecognizer) {
        _menuTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonPressed:)];
        _menuTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];

        _playPauseTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPlayPauseButtonPressed:)];
        _playPauseTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypePlayPause)];
        
        _menuDoubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonDoublePressed:)];
        _menuDoubleTapGestureRecognizer.numberOfTapsRequired = 2;
        [_menuTapGestureRecognizer requireGestureRecognizerToFail:_menuDoubleTapGestureRecognizer];
        _menuDoubleTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];
    }
    
    [self.view addGestureRecognizer:_menuTapGestureRecognizer];
    [self.view addGestureRecognizer:_menuDoubleTapGestureRecognizer];
    [self.view addGestureRecognizer:_playPauseTapGestureRecognizer];

#elif !TARGET_OS_VISION
    _exitSwipeRecognizer = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(edgeSwiped)];
    _exitSwipeRecognizer.edges = UIRectEdgeLeft;
    _exitSwipeRecognizer.delaysTouchesBegan = NO;
    _exitSwipeRecognizer.delaysTouchesEnded = NO;
    
    [self.view addGestureRecognizer:_exitSwipeRecognizer];
#endif
    
#if !TARGET_OS_VISION
    _tipLabel = [[UILabel alloc] init];
    [self.view addSubview:_tipLabel];
    [_tipLabel setUserInteractionEnabled:NO];
    
#if TARGET_OS_TV
    [_tipLabel setText:@"Tip: Tap the Play/Pause button on the Apple TV Remote to disconnect from your PC"];
#else
    [_tipLabel setText:@"Tip: Swipe from the left edge to disconnect from your PC"];
#endif
    
    [_tipLabel sizeToFit];
    _tipLabel.textColor = [UIColor whiteColor];
    _tipLabel.textAlignment = NSTextAlignmentCenter;
    _tipLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_tipLabel.topAnchor constraintEqualToAnchor:_stageLabel.bottomAnchor constant:20.0].active = YES;
    [_tipLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
#endif

#if TARGET_OS_VISION
    // visionOS: If view-only mode, skip stream creation - Swift will manage it
    if (_viewOnlyMode) {
        Log(LOG_I, @"StreamFrameViewController: view-only mode - skipping stream creation");
        // Still add the stream view to the hierarchy
        [self.view addSubview:_streamView];
        return;
    }
#endif

    _streamMan = [[StreamManager alloc] initWithConfig:self.streamConfig
                                      rendererProvider:^id<AnyVideoDecoderRenderer> __strong {
        // Always use native VideoDecoderRenderer on visionOS for UIKit mode
        // The Metal renderer is kept in the project but disabled for now due to quality issues
        // It can be re-enabled later once the quality is sorted out
        
        /* DISABLED: Metal renderer for UIKit mode
        BOOL useMetal = NO;
#if TARGET_OS_VISION
        useMetal = YES;
#else
        useMetal = (self->_settings.renderer == 1 || self->_settings.uikitPreset != 0);
#endif

        if (useMetal) {
#if defined(TARGET_OS_VISION) && TARGET_OS_VISION
            Class MetalRendererClass = NSClassFromString(@"MetalVideoDecoderRenderer");
            if (MetalRendererClass) {
                SEL initSel = NSSelectorFromString(@"initWithView:callbacks:streamAspectRatio:useFramePacing:enableHDR:");
                id allocated = [MetalRendererClass alloc];
                id instance = nil;
                if ([allocated respondsToSelector:initSel]) {
                    typedef id (*InitFn)(id, SEL, UIView*, id, float, BOOL, BOOL);
                    InitFn fn = (InitFn)objc_msgSend;
                    instance = fn(allocated, initSel,
                                  self->_streamView,
                                  self,
                                  (float)self.streamConfig.width / (float)self.streamConfig.height,
                                  self.streamConfig.useFramePacing,
                                  self->_settings.enableHdr);
                }

                id<AnyVideoDecoderRenderer, MetalPresetControllable> renderer = (id)instance;
                self->_metalRenderer = renderer;

                if (renderer) {
                    [self applyUIKitPreset:self->_settings.uikitPreset];
                }

                if (renderer) {
                    return renderer;
                }
            }
            self->_metalRenderer = nil;
#else
            self->_metalRenderer = nil;
#endif
        }
        */

        // Always use native VideoDecoderRenderer for UIKit mode
        return [[VideoDecoderRenderer alloc] initWithView:self->_streamView
                                                callbacks:self
                                        streamAspectRatio:(float)self.streamConfig.width / (float)self.streamConfig.height
                                          useFramePacing:self.streamConfig.useFramePacing];
    }
                                   connectionCallbacks:self];
    NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
    [opQueue addOperation:_streamMan];
    
    // On visionOS, don't listen to app-wide background/resign notifications,
    // because opening another window can trigger them for this scene and stop the stream.
#if !TARGET_OS_VISION
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidBecomeActive:)
                                                 name: UIApplicationDidBecomeActiveNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidEnterBackground:)
                                                 name: UIApplicationDidEnterBackgroundNotification
                                               object: nil];
#endif

#if 0
    // FIXME: This doesn't work reliably on iPad for some reason. Showing and hiding the keyboard
    // several times in a row will not correctly restore the state of the UIScrollView.
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(keyboardWillShow:)
                                                 name: UIKeyboardWillShowNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(keyboardWillHide:)
                                                 name: UIKeyboardWillHideNotification
                                               object: nil];
#endif
    
    // Only enable scroll and zoom in absolute touch mode
    if (_settings.absoluteTouchMode) {
        _scrollView = [[UIScrollView alloc] initWithFrame:self.view.frame];
#if !TARGET_OS_TV
        [_scrollView.panGestureRecognizer setMinimumNumberOfTouches:2];
#endif
        [_scrollView setShowsHorizontalScrollIndicator:NO];
        [_scrollView setShowsVerticalScrollIndicator:NO];
        [_scrollView setDelegate:self];
        [_scrollView setMaximumZoomScale:10.0f];
        
        // Add StreamView inside a UIScrollView for absolute mode
        [_scrollView addSubview:_streamView];
        [self.view addSubview:_scrollView];
    }
    else {
        // Add StreamView directly in relative mode
        [self.view addSubview:_streamView];
    }
}

- (void)viewDidLayoutSubviews {
    if (_scrollView) {
        _scrollView.frame = self.view.frame;
    }
    _streamView.frame = self.view.frame;

}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return _streamView;
}

- (void)willMoveToParentViewController:(UIViewController *)parent {
    // Only cleanup when we're being destroyed
    if (parent == nil) {
        [_controllerSupport cleanup];
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        [_streamMan stopStream];
        if (_inactivityTimer != nil) {
            [_inactivityTimer invalidate];
            _inactivityTimer = nil;
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
}

#if 0
- (void)keyboardWillShow:(NSNotification *)notification {
    _keyboardSize = [[[notification userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;

    [UIView animateWithDuration:0.3 animations:^{
        CGRect frame = self->_scrollView.frame;
        frame.size.height -= self->_keyboardSize.height;
        self->_scrollView.frame = frame;
    }];
}

-(void)keyboardWillHide:(NSNotification *)notification {
    // NOTE: UIKeyboardFrameEndUserInfoKey returns a different keyboard size
    // than UIKeyboardFrameBeginUserInfoKey, so it's unsuitable for use here
    // to undo the changes made by keyboardWillShow.
    
    [UIView animateWithDuration:0.3 animations:^{
        CGRect frame = self->_scrollView.frame;
        frame.size.height += self->_keyboardSize.height;
        self->_scrollView.frame = frame;
    }];
}
#endif

- (void)updateStatsOverlay {
    NSString* overlayText = [self->_streamMan getStatsOverlayText];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateOverlayText:overlayText];
    });
}

- (NSString*)getStatsOverlayText {
    return [_streamMan getStatsOverlayText];
}

- (BOOL)toggleKeyboard {
    if (_streamView) {
        return [_streamView toggleKeyboard];
    }
    return NO;
}

- (void)updateOverlayText:(NSString*)text {
    if (_overlayView == nil) {
        _overlayView = [[UITextView alloc] init];
#if !TARGET_OS_TV
        [_overlayView setEditable:NO];
#endif
        [_overlayView setUserInteractionEnabled:NO];
        [_overlayView setSelectable:NO];
        [_overlayView setScrollEnabled:NO];
        
        // HACK: If not using stats overlay, center the text
        if (_statsUpdateTimer == nil) {
            [_overlayView setTextAlignment:NSTextAlignmentCenter];
        }
        
        [_overlayView setTextColor:[UIColor lightGrayColor]];
        [_overlayView setBackgroundColor:[UIColor blackColor]];
#if TARGET_OS_TV
        [_overlayView setFont:[UIFont systemFontOfSize:24]];
#else
        [_overlayView setFont:[UIFont systemFontOfSize:12]];
#endif
        [_overlayView setAlpha:0.5];
        [self.view addSubview:_overlayView];
    }
    
    if (text != nil) {
        // We set our bounds to the maximum width in order to work around a bug where
        // sizeToFit interacts badly with the UITextView's line breaks, causing the
        // width to get smaller and smaller each time as more line breaks are inserted.
        [_overlayView setBounds:CGRectMake(self.view.frame.origin.x,
                                           _overlayView.frame.origin.y,
                                           self.view.frame.size.width,
                                           _overlayView.frame.size.height)];
        [_overlayView setText:text];
        [_overlayView sizeToFit];
        [_overlayView setCenter:CGPointMake(self.view.frame.size.width / 2, _overlayView.frame.size.height / 2)];
        [_overlayView setHidden:NO];
    }
    else {
        [_overlayView setHidden:YES];
    }
}

- (void) returnToMainFrame {
    // Reset display mode back to default
    [self updatePreferredDisplayMode:NO];
    
    [_statsUpdateTimer invalidate];
    _statsUpdateTimer = nil;
    
    // Ensure full teardown before leaving
    if (_streamMan) {
        [_streamMan stopStream];
        _streamMan = nil;
    }
    if (_metalRenderer) {
        [_metalRenderer shutdown];
        _metalRenderer = nil;
    }
    
    [self.navigationController popToRootViewControllerAnimated:YES];
}

// This will fire if the user opens control center or gets a low battery message
- (void)applicationWillResignActive:(NSNotification *)notification {
#if TARGET_OS_VISION
    // On visionOS, opening another window (the Main menu) may trigger this for the stream scene.
    // Ignore so the stream stays live.
    Log(LOG_I, @"[visionOS] Ignoring applicationWillResignActive to keep stream running.");
    return;
#endif

    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
    }
    
#if !TARGET_OS_TV
    Log(LOG_I, @"Starting inactivity termination timer");
    _inactivityTimer = [NSTimer scheduledTimerWithTimeInterval:60
                                                      target:self
                                                    selector:@selector(inactiveTimerExpired:)
                                                    userInfo:nil
                                                     repeats:NO];
#endif
}

- (void)inactiveTimerExpired:(NSTimer*)timer {
    Log(LOG_I, @"Terminating stream after inactivity");

    [self returnToMainFrame];
    
    _inactivityTimer = nil;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    // Stop the background timer, since we're foregrounded again
    if (_inactivityTimer != nil) {
        Log(LOG_I, @"Stopping inactivity timer after becoming active again");
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
}

// This fires when the home button is pressed
- (void)applicationDidEnterBackground:(UIApplication *)application {
#if TARGET_OS_VISION
    Log(LOG_I, @"[visionOS] Ignoring applicationDidEnterBackground to keep stream running.");
    return;
#endif

    Log(LOG_I, @"Terminating stream immediately for backgrounding");

    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
    
    // Ensure full teardown
    if (_streamMan) {
        [_streamMan stopStream];
        _streamMan = nil;
    }
    if (_metalRenderer) {
        [_metalRenderer shutdown];
        _metalRenderer = nil;
    }
    
    [self returnToMainFrame];
}

- (void)edgeSwiped {
    Log(LOG_I, @"User swiped to end stream");
    
    [self returnToMainFrame];
}

- (void) connectionStarted {
    Log(LOG_I, @"Connection started");
    dispatch_async(dispatch_get_main_queue(), ^{
#if !TARGET_OS_VISION
        // Leave the spinner spinning until it's obscured by
        // the first frame of video.
        self->_stageLabel.hidden = YES;
        self->_tipLabel.hidden = YES;
#endif
        
        [self->_streamView showOnScreenControls];
        
        [self->_controllerSupport connectionEstablished];
        
#if !TARGET_OS_VISION
        if (self->_settings.statsOverlay) {
            self->_statsUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f
                                                                       target:self
                                                                     selector:@selector(updateStatsOverlay)
                                                                     userInfo:nil
                                                                      repeats:YES];
        }
#endif
        
        if (self->_connectedCallback) {
            self->_connectedCallback();
        }
    });
}

- (void)connectionTerminated:(int)errorCode {
    Log(LOG_I, @"Connection terminated: %d", errorCode);
    
    unsigned int portFlags = LiGetPortFlagsFromTerminationErrorCode(errorCode);
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portFlags);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;

#if TARGET_OS_VISION
        // On visionOS: Avoid presenting alerts which conflict with SwiftUI window dismissal.
        // Just drive the flow back to main and inform Swift.
        if (self->_disconnectedCallback) {
            self->_disconnectedCallback();
        }
        [self returnToMainFrame];
#else
        NSString* title;
        NSString* message;
        
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            title = @"Connection Error";
            message = @"Your device's network connection is blocking Moonlight. Streaming may not work while connected to this network.";
        }
        else {
            switch (errorCode) {
                case ML_ERROR_GRACEFUL_TERMINATION:
                    [self returnToMainFrame];
                    return;
                    
                case ML_ERROR_NO_VIDEO_TRAFFIC:
                    title = @"Connection Error";
                    message = @"No video received from host.";
                    if (portFlags != 0) {
                        char failingPorts[256];
                        LiStringifyPortFlags(portFlags, "\n", failingPorts, sizeof(failingPorts));
                        message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\nCheck your firewall and port forwarding rules for port(s):\n%s", failingPorts]];
                    }
                    break;
                    
                case ML_ERROR_NO_VIDEO_FRAME:
                    title = @"Connection Error";
                    message = @"Your network connection isn't performing well. Reduce your video bitrate setting or try a faster connection.";
                    break;
                    
                case ML_ERROR_UNEXPECTED_EARLY_TERMINATION:
                case ML_ERROR_PROTECTED_CONTENT:
                    title = @"Connection Error";
                    message = @"Something went wrong on your host PC when starting the stream.\n\nMake sure you don't have any DRM-protected content open on your host PC. You can also try restarting your host PC.\n\nIf the issue persists, try reinstalling your GPU drivers and GeForce Experience.";
                    break;
                    
                case ML_ERROR_FRAME_CONVERSION:
                    title = @"Connection Error";
                    message = @"The host PC reported a fatal video encoding error.\n\nTry disabling HDR mode, changing the streaming resolution, or changing your host PC's display resolution.";
                    break;
                    
                default:
                {
                    NSString* errorString;
                    if (abs(errorCode) > 1000) {
                        // We'll assume large errors are hex values
                        errorString = [NSString stringWithFormat:@"%08X", (uint32_t)errorCode];
                    }
                    else {
                        // Smaller values will just be printed as decimal (probably errno.h values)
                        errorString = [NSString stringWithFormat:@"%d", errorCode];
                    }
                    
                    title = @"Connection Terminated";
                    message = [NSString stringWithFormat: @"The connection was terminated\n\nError code: %@", errorString];
                    break;
                }
            }
        }
        
        UIAlertController* conTermAlert = [UIAlertController alertControllerWithTitle:title
                                                                              message:message
                                                                       preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:conTermAlert];
        [conTermAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:conTermAlert animated:YES completion:nil];
        
        if (self->_disconnectedCallback) {
            self->_disconnectedCallback();
        }
#endif
    });

    [_streamMan stopStream];
}

- (void) stageStarting:(const char*)stageName {
    Log(LOG_I, @"Starting %s", stageName);
#if !TARGET_OS_VISION
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString* lowerCase = [NSString stringWithFormat:@"%s in progress...", stageName];
        NSString* titleCase = [[[lowerCase substringToIndex:1] uppercaseString] stringByAppendingString:[lowerCase substringFromIndex:1]];
        [self->_stageLabel setText:titleCase];
        [self->_stageLabel sizeToFit];
        self->_stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self->_stageLabel.center.y);
    });
#endif
}

- (void) stageComplete:(const char*)stageName {
}

- (void) stageFailed:(const char*)stageName withError:(int)errorCode portTestFlags:(int)portTestFlags {
    Log(LOG_I, @"Stage %s failed: %d", stageName, errorCode);
    
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portTestFlags);

    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].idleTimerDisabled = NO;

#if TARGET_OS_VISION
        // Avoid alert presentation on visionOS; return to main and notify Swift
        if (self->_disconnectedCallback) {
            self->_disconnectedCallback();
        }
        [self returnToMainFrame];
#else
        NSString* message = [NSString stringWithFormat:@"%s failed with error %d", stageName, errorCode];
        if (portTestFlags != 0) {
            char failingPorts[256];
            LiStringifyPortFlags(portTestFlags, "\n", failingPorts, sizeof(failingPorts));
            message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\nCheck your firewall and port forwarding rules for port(s):\n%s", failingPorts]];
        }
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            message = [message stringByAppendingString:@"\n\nYour device's network connection is blocking Moonlight. Streaming may not work while connected to this network."];
        }
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Connection Failed"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:alert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
#endif
    });
    
    [_streamMan stopStream];
}

- (void) launchFailed:(NSString*)message {
    Log(LOG_I, @"Launch failed: %@", message);

    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].idleTimerDisabled = NO;

#if TARGET_OS_VISION
        // Avoid alert presentation on visionOS; return to main and notify Swift
        if (self->_disconnectedCallback) {
            self->_disconnectedCallback();
        }
        [self returnToMainFrame];
#else
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Connection Error"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:alert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
#endif
    });
}

- (void)rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor {
    Log(LOG_I, @"Rumble on gamepad %d: %04x %04x", controllerNumber, lowFreqMotor, highFreqMotor);
    
    [_controllerSupport rumble:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
}

- (void) rumbleTriggers:(uint16_t)controllerNumber leftTrigger:(uint16_t)leftTrigger rightTrigger:(uint16_t)rightTrigger {
    Log(LOG_I, @"Trigger rumble on gamepad %d: %04x %04x", controllerNumber, leftTrigger, rightTrigger);
    
    [_controllerSupport rumbleTriggers:controllerNumber leftTrigger:leftTrigger rightTrigger:rightTrigger];
}

- (void) setMotionEventState:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz {
    Log(LOG_I, @"Set motion state on gamepad %d: %02x %u Hz", controllerNumber, motionType, reportRateHz);
    
    [_controllerSupport setMotionEventState:controllerNumber motionType:motionType reportRateHz:reportRateHz];
}

- (void) setControllerLed:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {
    Log(LOG_I, @"Set controller LED on gamepad %d: l%02x%02x%02x", controllerNumber, r, g, b);
    
    [_controllerSupport setControllerLed:controllerNumber r:r g:g b:b];
}

- (void)connectionStatusUpdate:(int)status {
    Log(LOG_W, @"Connection status update: %d", status);

    // The stats overlay takes precedence over these warnings
    if (_statsUpdateTimer != nil) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (status) {
            case CONN_STATUS_OKAY:
                [self updateOverlayText:nil];
                break;
                
            case CONN_STATUS_POOR:
                if (self->_streamConfig.bitRate > 5000) {
                    [self updateOverlayText:@"Slow connection to PC\nReduce your bitrate"];
                }
                else {
                    [self updateOverlayText:@"Poor connection to PC"];
                }
                break;
        }
    });
}

- (void) updatePreferredDisplayMode:(BOOL)streamActive {
#if TARGET_OS_TV
    if (@available(tvOS 11.2, *)) {
        UIWindow* window = [[[UIApplication sharedApplication] delegate] window];
        AVDisplayManager* displayManager = [window avDisplayManager];
        
        // This logic comes from Kodi and MrMC
        if (streamActive) {
            int dynamicRange;
            
            if (LiGetCurrentHostDisplayHdrMode()) {
                dynamicRange = 2; // HDR10
            }
            else {
                dynamicRange = 0; // SDR
            }
            
            AVDisplayCriteria* displayCriteria = [[AVDisplayCriteria alloc] initWithRefreshRate:[_settings.framerate floatValue]
                                                                              videoDynamicRange:dynamicRange];
            displayManager.preferredDisplayCriteria = displayCriteria;
        }
        else {
            // Switch back to the default display mode
            displayManager.preferredDisplayCriteria = nil;
        }
    }
#endif
}

- (void) setHdrMode:(bool)enabled {
    Log(LOG_I, @"HDR is now: %s", enabled ? "active" : "inactive");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updatePreferredDisplayMode:YES];
    });
}

- (void) videoContentShown {
#if !TARGET_OS_VISION
    [_spinner stopAnimating];
#endif
    [self.view setBackgroundColor:[UIColor blackColor]];

    // Notify Swift the first frame has been shown so window management can proceed safely
    [[NSNotificationCenter defaultCenter] postNotificationName:StreamFirstFrameShownNotification object:self];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)gamepadPresenceChanged {
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)mousePresenceChanged {
#if !TARGET_OS_TV
    if (@available(iOS 14.0, *)) {
        [self setNeedsUpdateOfPrefersPointerLocked];
    }
#endif
}

- (void) streamExitRequested {
    Log(LOG_I, @"Gamepad combo requested stream exit");
    
    [self returnToMainFrame];
}

- (void)userInteractionBegan {
    // Disable hiding home bar when user is interacting.
    // iOS will force it to be shown anyway, but it will
    // also discard our edges deferring system gestures unless
    // we willingly give up home bar hiding preference.
    _userIsInteracting = YES;
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)userInteractionEnded {
    // Enable home bar hiding again if conditions allow
    _userIsInteracting = NO;
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

#if !TARGET_OS_TV
// Require a confirmation when streaming to activate a system gesture
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {
    return UIRectEdgeAll;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    if ([_controllerSupport getConnectedGamepadCount] > 0 &&
        [_streamView getCurrentOscState] == OnScreenControlsLevelOff &&
        _userIsInteracting == NO) {
        // Autohide the home bar when a gamepad is connected
        // and the on-screen controls are disabled. We can't
        // do this all the time because any touch on the display
        // will cause the home indicator to reappear, and our
        // preferredScreenEdgesDeferringSystemGestures will also
        // be suppressed (leading to possible errant exits of the
        // stream).
        return YES;
    }
    
    return NO;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (BOOL)prefersPointerLocked {
    // Pointer lock breaks the UIKit mouse APIs, which is a problem because
    // GCMouse is horribly broken on iOS 14.0 for certain mice. Only lock
    // the cursor if there is a GCMouse present.
    return [GCMouse mice].count > 0;
}
#endif

- (void)updateRendererHDRParams:(float)brightness saturation:(float)saturation contrast:(float)contrast luminosity:(float)luminosity gamma:(float)gamma {
    if (_metalRenderer != nil) {
        _metalRenderer.hdrBrightness = brightness;
        _metalRenderer.hdrSaturation = saturation;
        _metalRenderer.hdrContrast = contrast;
        _metalRenderer.hdrLuminosity = luminosity;
        _metalRenderer.hdrGamma = gamma;
        Log(LOG_I, @"Updated HDR params: brightness=%.2f, saturation=%.2f, contrast=%.2f, luminosity=%.2f, gamma=%.2f", brightness, saturation, contrast, luminosity, gamma);
    }
}

- (NSString *)_friendlyNameForPreset:(int32_t)preset {
    // 4-profile mapping for uniform names across all renderers
    switch (preset) {
        case 0: return @"Default";
        case 1: return @"Cinematic";
        case 2: return @"Vivid";
        case 3: return @"Realistic";
        default: return @"Default";
    }
}

- (void)applyUIKitPreset:(int32_t)preset {
    self->_settings.uikitPreset = preset;

    if (_metalRenderer != nil) {
        if (preset == 0) {
            _metalRenderer.presetActive = NO;
            [_metalRenderer setPresetMode:0];
            [self updateRendererHDRParams:0.00f saturation:1.00f contrast:1.00f luminosity:1.00f gamma:1.0f];
        } else {
            _metalRenderer.presetActive = YES;
            switch (preset) {
                case 1: { // Cinematic - Warm, slightly desaturated, higher contrast
                    [_metalRenderer setPresetMode:1];
                    [self updateRendererHDRParams:0.00f saturation:0.85f contrast:1.03f luminosity:1.00f gamma:1.0f];
                    break;
                }
                case 2: { // Vivid - High saturation and contrast for punch
                    [_metalRenderer setPresetMode:2];
                    [self updateRendererHDRParams:0.00f saturation:1.15f contrast:1.04f luminosity:1.00f gamma:1.0f];
                    break;
                }
                case 3: { // Realistic - Balanced, natural look with slight boost
                    [_metalRenderer setPresetMode:0];
                    [self updateRendererHDRParams:0.00f saturation:0.95f contrast:1.04f luminosity:1.00f gamma:1.0f];
                    break;
                }
                default: {
                    _metalRenderer.presetActive = NO;
                    [_metalRenderer setPresetMode:0];
                    [self updateRendererHDRParams:0.00f saturation:1.00f contrast:1.00f luminosity:1.00f gamma:1.0f];
                    break;
                }
            }
        }
        // Show brief toast with new unified names
        NSString *msg = [NSString stringWithFormat:@"Preset: %@", [self _friendlyNameForPreset:preset]];
        [self updateOverlayText:msg];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self updateOverlayText:nil];
        });
    } else {
        NSString *msg = (preset == 0) ? @"Preset: Default" : @"Reconnect to enable presets";
        [self updateOverlayText:msg];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self updateOverlayText:nil];
        });
    }
}

@end