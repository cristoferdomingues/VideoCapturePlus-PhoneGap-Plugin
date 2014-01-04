/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "CDVCapture.h"
#import <UIKit/UIDevice.h>

// see https://github.com/ednasgoldfishuk/cordova-plugin-media-capture/blob/master/src/ios/CDVCapture.h for full custom overlay

@implementation CDVImagePicker

@synthesize callbackId;

- (uint64_t)accessibilityTraits
{
    NSString* systemVersion = [[UIDevice currentDevice] systemVersion];
    
    if (([systemVersion compare:@"4.0" options:NSNumericSearch] != NSOrderedAscending)) { // this means system version is not less than 4.0
        return UIAccessibilityTraitStartsMediaSession;
    }
    
    return UIAccessibilityTraitNone;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (UIViewController*)childViewControllerForStatusBarHidden {
    return nil;
}

- (void)viewWillAppear:(BOOL)animated {
    SEL sel = NSSelectorFromString(@"setNeedsStatusBarAppearanceUpdate");
    if ([self respondsToSelector:sel]) {
        [self performSelector:sel withObject:nil afterDelay:0];
    }
    
    [super viewWillAppear:animated];
}

@end

@implementation CDVCapture
@synthesize inUse, timer;

- (id)initWithWebView:(UIWebView*)theWebView
{
    self = (CDVCapture*)[super initWithWebView:theWebView];
    if (self) {
        self.inUse = NO;
    }
    return self;
}

-(void)rotateOverlayIfNeeded:(UIView*) overlayView {
    UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
    
    float rotation = 0;
    if (deviceOrientation == UIDeviceOrientationPortraitUpsideDown) {
        rotation = M_PI;
    } else if (deviceOrientation == UIDeviceOrientationLandscapeLeft) {
        rotation = M_PI_2;
    } else if (deviceOrientation == UIDeviceOrientationLandscapeRight) {
        rotation = -M_PI_2;
    }

    if (rotation != 0) {
      CGAffineTransform transform = overlayView.transform;
      transform = CGAffineTransformRotate(transform, rotation);
      overlayView.transform = transform;
    }
}

-(void)alignOverlayDimensionsWithOrientation {
    if (portraitOverlay == nil && landscapeOverlay == nil) {
        return;
    }

    UIView* overlayView = [[UIView alloc] initWithFrame:pickerController.view.frame];

    // png transparency
    [overlayView.layer setOpaque:NO];
    overlayView.opaque = NO;

    UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;

    UIImage* overlayImage;
    if (UIDeviceOrientationIsLandscape(deviceOrientation)) {
        overlayImage = landscapeOverlay;
    } else {
        overlayImage = portraitOverlay;
    }
    // may be null if no image was passed for this orientation
    if (overlayImage != nil) {
        overlayView.backgroundColor = [UIColor colorWithPatternImage:overlayImage];
        [overlayView setFrame:CGRectMake(0, 0, overlayImage.size.width, overlayImage.size.height)]; // x, y, width, height

        // regardless the orientation, these are the width and height in portrait mode
        float width = CGRectGetWidth(pickerController.view.frame);
        float height = CGRectGetHeight(pickerController.view.frame);

        if (CDV_IsIPad()) {
            if (UIDeviceOrientationIsLandscape(deviceOrientation)) {
                [overlayView setCenter:CGPointMake(height/2,width/2)];
            } else {
                [overlayView setCenter:CGPointMake(width/2,height/2)];
            }
        } else {
            // on iPad, the image rotates with the orientation, but on iPhone it doesn't - so we have to manually rotate the overlay on iPhone
            [self rotateOverlayIfNeeded:overlayView];
            [overlayView setCenter:CGPointMake(width/2,height/2)];
        }
        pickerController.cameraOverlayView = overlayView;
    }
}

- (void) orientationChanged:(NSNotification *)notification {
    [self alignOverlayDimensionsWithOrientation];
}

- (void)captureVideo:(CDVInvokedUrlCommand*)command {
    
    NSString* callbackId = command.callbackId;
    NSDictionary* options = [command.arguments objectAtIndex:0];
    
    // emit and capture changes to the deviceOrientation
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationChanged:) name:@"UIDeviceOrientationDidChangeNotification" object:nil];

    // enable this line of code if you want to do stuff when the capture session is started
    // [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didStartRunning:) name:AVCaptureSessionDidStartRunningNotification object:nil];
    
    // TODO try this: self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5f target:self selector:@selector(updateStopwatchLabel) userInfo:nil repeats:YES];
    //    timer en session.running property gebruiken?
    
    if ([options isKindOfClass:[NSNull class]]) {
        options = [NSDictionary dictionary];
    }
    
    // options could contain limit, duration, highquality, frontcamera and mode
    // taking more than one video (limit) is only supported if provide own controls via cameraOverlayView property
    NSNumber* duration  = [options objectForKey:@"duration"];
    BOOL highquality    = [[options objectForKey:@"highquality"] boolValue];
    BOOL frontcamera    = [[options objectForKey:@"frontcamera"] boolValue];
    portraitOverlay = [self getImage:[options objectForKey:@"portraitOverlay"]];
    landscapeOverlay = [self getImage:[options objectForKey:@"landscapeOverlay"]];
    NSString* mediaType = nil;

    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        // there is a camera, it is available, make sure it can do movies
        pickerController = [[CDVImagePicker alloc] init];
        
        NSArray* types = nil;
        if ([UIImagePickerController respondsToSelector:@selector(availableMediaTypesForSourceType:)]) {
            types = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeCamera];
            // NSLog(@"MediaTypes: %@", [types description]);
            
            if ([types containsObject:(NSString*)kUTTypeMovie]) {
                mediaType = (NSString*)kUTTypeMovie;
            } else if ([types containsObject:(NSString*)kUTTypeVideo]) {
                mediaType = (NSString*)kUTTypeVideo;
            }
        }
    }
    if (!mediaType) {
        // don't have video camera return error
        NSLog(@"Capture.captureVideo: video mode not available.");
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageToErrorObject:CAPTURE_NOT_SUPPORTED];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        pickerController = nil;
    } else {
        pickerController.delegate = self;
        
        pickerController.sourceType = UIImagePickerControllerSourceTypeCamera;
        pickerController.allowsEditing = NO;
        // iOS 3.0
        pickerController.mediaTypes = [NSArray arrayWithObjects:mediaType, nil];
        
        if ([mediaType isEqualToString:(NSString*)kUTTypeMovie]){
            if (duration) {
                pickerController.videoMaximumDuration = [duration doubleValue];
            }
        }
        
        // iOS 4.0
        if ([pickerController respondsToSelector:@selector(cameraCaptureMode)]) {
            pickerController.cameraCaptureMode = UIImagePickerControllerCameraCaptureModeVideo;
            if (highquality) {
                pickerController.videoQuality = UIImagePickerControllerQualityTypeHigh;
            }
            if (frontcamera) {
                pickerController.cameraDevice = UIImagePickerControllerCameraDeviceFront;
            }
            
            pickerController.delegate = self;
            [self alignOverlayDimensionsWithOrientation];

            /*
             // this works btw, for adding a custom label
             CGRect labelFrame = CGRectMake(pickerController.cameraOverlayView.frame.origin.x + pickerController.cameraOverlayView.frame.size.width/2, pickerController.cameraOverlayView.frame.origin.y+10, 75, 42);
             self.stopwatchLabel = [[UILabel alloc] initWithFrame:labelFrame];
             self.stopwatchLabel.textColor = [UIColor whiteColor];
             self.stopwatchLabel.backgroundColor = [UIColor clearColor];
             self.stopwatchLabel.text = @"00:00";
             //               self.pauseRecord = YES;         //assign video recording to paused
             //             self.pauseRecordTime = [NSNumber numberWithInteger:0];       //assign current timer value to 0
             [pickerController.cameraOverlayView addSubview:self.stopwatchLabel];
             */
            
            // trying to add a progressbar to the bottom
            /*
             CGRect progressbarLabelFrame = CGRectMake(0, 0, pickerController.cameraOverlayView.frame.size.width/2, 4);
             self.progressbarLabel = [[UILabel alloc] initWithFrame:progressbarLabelFrame];
             self.progressbarLabel.backgroundColor = [UIColor redColor];
             [pickerController.cameraOverlayView addSubview:self.progressbarLabel];
             
             self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5f target:self selector:@selector(updateStopwatchLabel) userInfo:nil repeats:YES];
             */

            // TODO make this configurable via the API (but only if Android supports it)
            // pickerController.cameraFlashMode = UIImagePickerControllerCameraFlashModeAuto;
        }
        
        // CDVImagePicker specific property
        pickerController.callbackId = callbackId;
        
        SEL selector = NSSelectorFromString(@"presentViewController:animated:completion:");
        if ([self.viewController respondsToSelector:selector]) {
            [self.viewController presentViewController:pickerController animated:YES completion:nil];
        } else {
            // deprecated as of iOS >= 6.0
            [self.viewController presentModalViewController:pickerController animated:YES];
        }
    }
}

-(UIImage*)getImage: (NSString *)imageName {
    UIImage *image = nil;
    if (imageName != (id)[NSNull null]) {
        if ([imageName rangeOfString:@"http"].location == 0) { // from the internet?
            image = [UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:imageName]]];
        } else if ([imageName rangeOfString:@"www/"].location == 0) { // www folder?
            image = [UIImage imageNamed:imageName];
        } else if ([imageName rangeOfString:@"file://"].location == 0) {
            // using file: protocol? then strip the file:// part
            image = [UIImage imageWithData:[NSData dataWithContentsOfFile:[[NSURL URLWithString:imageName] path]]];
        } else {
            // assume anywhere else, on the local filesystem
            image = [UIImage imageWithData:[NSData dataWithContentsOfFile:imageName]];
        }
    }
    return image;
}

//- (void)updateStopwatchLabel {
    // update the label with the elapsed time
    //  [self.stopwatchLabel setText:[self.timer.timeInterval]];
    //   [self.timerLabel setText:[self formatTime:self.avRecorder.currentTime]];
//}

- (CDVPluginResult*)processVideo:(NSString*)moviePath forCallbackId:(NSString*)callbackId {
    // save the movie to photo album (only avail as of iOS 3.1)
    NSDictionary* fileDict = [self getMediaDictionaryFromPath:moviePath ofType:nil];
    NSArray* fileArray = [NSArray arrayWithObject:fileDict];
    return [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:fileArray];
}

- (NSDictionary*)getMediaDictionaryFromPath:(NSString*)fullPath ofType:(NSString*)type {
    NSFileManager* fileMgr = [[NSFileManager alloc] init];
    NSMutableDictionary* fileDict = [NSMutableDictionary dictionaryWithCapacity:5];
    
    [fileDict setObject:[fullPath lastPathComponent] forKey:@"name"];
    [fileDict setObject:fullPath forKey:@"fullPath"];
    // determine type
    if (!type) {
        id command = [self.commandDelegate getCommandInstance:@"File"];
        if ([command isKindOfClass:[CDVFile class]]) {
            CDVFile* cdvFile = (CDVFile*)command;
            NSString* mimeType = [cdvFile getMimeTypeFromPath:fullPath];
            [fileDict setObject:(mimeType != nil ? (NSObject*)mimeType : [NSNull null]) forKey:@"type"];
        }
    }
    NSDictionary* fileAttrs = [fileMgr attributesOfItemAtPath:fullPath error:nil];
    [fileDict setObject:[NSNumber numberWithUnsignedLongLong:[fileAttrs fileSize]] forKey:@"size"];
    NSDate* modDate = [fileAttrs fileModificationDate];
    NSNumber* msDate = [NSNumber numberWithDouble:[modDate timeIntervalSince1970] * 1000];
    [fileDict setObject:msDate forKey:@"lastModifiedDate"];
    
    return fileDict;
}

- (void)imagePickerController:(UIImagePickerController*)picker didFinishPickingImage:(UIImage*)image editingInfo:(NSDictionary*)editingInfo {
    // older api calls new one
    [self imagePickerController:picker didFinishPickingMediaWithInfo:editingInfo];
}

/* Called when movie is finished recording.
 * Calls success or error code as appropriate
 * if successful, result  contains an array (with just one entry since can only get one image unless build own camera UI) of MediaFile object representing the image
 *      name
 *      fullPath
 *      type
 *      lastModifiedDate
 *      size
 */
- (void)imagePickerController:(UIImagePickerController*)picker didFinishPickingMediaWithInfo:(NSDictionary*)info {
    CDVImagePicker* cameraPicker = (CDVImagePicker*)picker;
    NSString* callbackId = cameraPicker.callbackId;
    
    if ([picker respondsToSelector:@selector(presentingViewController)]) {
        [[picker presentingViewController] dismissModalViewControllerAnimated:YES];
    } else {
        [[picker parentViewController] dismissModalViewControllerAnimated:YES];
    }
    
    CDVPluginResult* result = nil;
    NSString* moviePath = [[info objectForKey:UIImagePickerControllerMediaURL] path];
    if (moviePath) {
        result = [self processVideo:moviePath forCallbackId:callbackId];
    }
    if (!result) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageToErrorObject:CAPTURE_INTERNAL_ERR];
    }
    [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    pickerController = nil;
}

@end