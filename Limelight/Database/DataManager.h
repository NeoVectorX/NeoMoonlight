//
//  DataManager.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/28/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "AppDelegate.h"

@class TemporaryApp;
@class TemporaryHost;
@class TemporarySettings;

@interface DataManager : NSObject

- (void) saveSettingsWithBitrate:(NSInteger)bitrate
                       framerate:(NSInteger)framerate
                          height:(NSInteger)height
                           width:(NSInteger)width
                audioConfig:(NSInteger)audioConfig
                onscreenControls:(NSInteger)onscreenControls
                   optimizeGames:(BOOL)optimizeGames
                 multiController:(BOOL)multiController
                 swapABXYButtons:(BOOL)swapABXYButtons
                       audioOnPC:(BOOL)audioOnPC
                  preferredCodec:(uint32_t)preferredCodec
                        renderer:(uint8_t)renderer
                  useFramePacing:(BOOL)useFramePacing
                       enableHdr:(BOOL)enableHdr
                  btMouseSupport:(BOOL)btMouseSupport
               absoluteTouchMode:(BOOL)absoluteTouchMode
                    statsOverlay:(BOOL)statsOverlay
realitykitRendererAnimateOpening:(BOOL)realitykitRendererAnimateOpening
     realitykitRendererCurvature:(NSNumber*)realitykitRendererCurvature
                  dimPassthrough:(BOOL)dimPassthrough
                hideSystemCursor:(BOOL)hideSystemCursor
                  showMicButton:(BOOL)showMicButton
       hideHandsIn360Environment:(BOOL)hideHandsIn360Environment;

- (NSArray<TemporaryHost*>*) getHosts;
- (void) updateHost:(TemporaryHost*)host;
- (void) updateAppsForExistingHost:(TemporaryHost *)host;
- (void) removeHost:(TemporaryHost*)host;
- (void) removeApp:(TemporaryApp*)app;

- (TemporarySettings*) getSettings;

- (void) updateUniqueId:(NSString*)uniqueId;
- (NSString*) getUniqueId;

// Co-op Session Support
- (NSData* _Nullable) exportPairingDataForHost:(TemporaryHost*)host;
- (TemporaryHost* _Nullable) importPairingData:(NSData*)data address:(NSString*)address name:(NSString*)name coopTag:(NSString* _Nullable)coopTag;
- (TemporaryHost* _Nullable) findHostByAddress:(NSString*)address;
- (void) removeCoopHosts;

@end