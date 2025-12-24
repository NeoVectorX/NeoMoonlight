//
//  HDRParsingUtils.h
//  Moonlight
//
//  Created by tht7 on 01/02/2025.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//
//  This is here since this parsing is very difficult in Swift but trivial in ObjC, so why not make them work together

@import AVFoundation;

#import "AnyVideoDecoderRenderer.h"

@interface HDRParsingUtils : NSObject

+ (nullable NSData*)parseHDRDisplayMetadata:(BOOL)enabled;
+ (nullable NSData*)parseHDRLightMetadata:(BOOL)enabled;

@end
