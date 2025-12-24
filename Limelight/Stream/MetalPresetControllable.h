//
//  MetalPresetControllable.h
//  Moonlight
//
//  Declares the properties/methods used from the Swift Metal renderer so Obj-C can compile
//

#import <Foundation/Foundation.h>

@protocol MetalPresetControllable <NSObject>
@property(nonatomic) float hdrBrightness;
@property(nonatomic) float hdrSaturation;
@property(nonatomic) float hdrContrast;
@property(nonatomic) float hdrLuminosity;
@property(nonatomic) float hdrGamma;
@property(nonatomic) BOOL presetActive;

- (void)setPresetMode:(int32_t)mode;
- (void)shutdown;
@end