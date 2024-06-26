//
//  ControlsViewController.m
//  CustomControls
//
//  Copyright © 2024 Brightcove, Inc. All rights reserved.
//

#import "ClosedCaptionMenuController.h"

#import "ControlsViewController.h"


// ** Customize these values **
static NSTimeInterval const kVisibleDuration = 5.0;
static NSTimeInterval const kAnimateInDuration = 0.1;
static NSTimeInterval const kAnimateOutDuration = 0.2;


@interface ControlsViewController () <UIGestureRecognizerDelegate>

@property (nonatomic, weak) IBOutlet UIView *controlsContainer;
@property (nonatomic, weak) IBOutlet UIButton *playPauseButton;
@property (nonatomic, weak) IBOutlet UILabel *playheadLabel;
@property (nonatomic, weak) IBOutlet UISlider *playheadSlider;
@property (nonatomic, weak) IBOutlet UILabel *durationLabel;
@property (nonatomic, weak) IBOutlet UIButton *fullscreenButton;
@property (nonatomic, weak) IBOutlet MPVolumeView *externalScreenButton;
@property (nonatomic, weak) IBOutlet UIButton *closedCaptionButton;

@property (nonatomic, weak) AVPlayer *currentPlayer;
@property (nonatomic, strong) NSTimer *controlTimer;
@property (nonatomic, assign, getter=wasPlayingOnSeek) BOOL playingOnSeek;
@property (nonatomic, strong) ClosedCaptionMenuController *ccMenuController;

@end


@implementation ControlsViewController


-(void)viewDidLoad
{
    [super viewDidLoad];

    // Used for hiding and showing the controls.
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self 
                                                                                    action:@selector(tapDetected:)];
    tapRecognizer.numberOfTapsRequired = 1;
    tapRecognizer.numberOfTouchesRequired = 1;
    tapRecognizer.delegate = self;
    [self.view addGestureRecognizer:tapRecognizer];

    self.externalScreenButton.showsRouteButton = YES;
    self.externalScreenButton.showsVolumeSlider = NO;
    
    self.closedCaptionButton.enabled = NO;

    self.ccMenuController = [[ClosedCaptionMenuController alloc] initWithStyle:UITableViewStyleGrouped];
    self.ccMenuController.controlsView = self;
}

- (void)setClosedCaptionEnabled:(BOOL)closedCaptionEnabled
{
    _closedCaptionEnabled = closedCaptionEnabled;
    self.closedCaptionButton.enabled = closedCaptionEnabled;
}

- (void)tapDetected:(UIGestureRecognizer *)gestureRecognizer
{
    if (self.playPauseButton.isSelected)
    {
        if (self.controlsContainer.alpha == 0.f)
        {
            [self fadeControlsIn];
        }
        else if (self.controlsContainer.alpha == 1.f)
        {
            [self fadeControlsOut];
        }
    }
}

- (void)fadeControlsIn
{
    [UIView animateWithDuration:kAnimateInDuration animations:^{
        [self showControls];
    } completion:^(BOOL finished) {
        if(finished)
        {
            [self reestablishTimer];
        }
    }];
}

- (void)fadeControlsOut
{
    [UIView animateWithDuration:kAnimateOutDuration animations:^{
        [self hideControls];
    }];
}

- (void)reestablishTimer
{
    [self.controlTimer invalidate];
    self.controlTimer = [NSTimer scheduledTimerWithTimeInterval:kVisibleDuration
                                                         target:self
                                                       selector:@selector(fadeControlsOut)
                                                       userInfo:nil
                                                        repeats:NO];
}

- (void)hideControls
{
    self.controlsContainer.alpha = 0.f;
}

- (void)showControls
{
    self.controlsContainer.alpha = 1.f;
}

- (void)invalidateTimerAndShowControls
{
    [self.controlTimer invalidate];
    [self showControls];
}

+ (NSString *)formatTime:(NSTimeInterval)timeInterval
{
    static NSNumberFormatter *numberFormatter;
    static dispatch_once_t once;

    dispatch_once(&once, ^{

        numberFormatter = [[NSNumberFormatter alloc] init];
        numberFormatter.paddingCharacter = @"0";
        numberFormatter.minimumIntegerDigits = 2;

    });

    if (isnan(timeInterval) || !isfinite(timeInterval) || timeInterval == 0)
    {
        return @"00:00";
    }

    NSUInteger hours = floor(timeInterval / 60.0f / 60.0f);
    NSUInteger minutes = (NSUInteger)(timeInterval / 60.0f) % 60;
    NSUInteger seconds = (NSUInteger)timeInterval % 60;

    NSString *formattedMinutes = [numberFormatter stringFromNumber:@(minutes)];
    NSString *formattedSeconds = [numberFormatter stringFromNumber:@(seconds)];

    NSString *ret = nil;
    if (hours > 0)
    {
        ret = [NSString stringWithFormat:@"%@:%@:%@", @(hours), formattedMinutes, formattedSeconds];
    }
    else
    {
        ret = [NSString stringWithFormat:@"%@:%@", formattedMinutes, formattedSeconds];
    }

    return ret;
}

- (IBAction)handlePlayPauseButtonPressed:(UIButton *)sender
{
    if (sender.selected)
    {
        [self.playbackController pause];
    }
    else
    {
        [self.playbackController play];
    }
}

- (IBAction)handlePlayheadSliderValueChanged:(UISlider *)sender
{
    NSTimeInterval newCurrentTime = sender.value * CMTimeGetSeconds(self.currentPlayer.currentItem.duration);
    self.playheadLabel.text = [ControlsViewController formatTime:newCurrentTime];
}

- (IBAction)handlePlayheadSliderTouchBegin:(UISlider *)sender
{
    self.playingOnSeek = self.playPauseButton.selected;
    [self.playbackController pause];
}

- (IBAction)handlePlayheadSliderTouchEnd:(UISlider *)sender
{
    NSTimeInterval newCurrentTime = sender.value * CMTimeGetSeconds(self.currentPlayer.currentItem.duration);
    CMTime seekToTime = CMTimeMakeWithSeconds(newCurrentTime, 600);

    typeof(self) __weak weakSelf = self;

    [self.playbackController seekToTime:seekToTime completionHandler:^(BOOL finished) {
        typeof(self) strongSelf = weakSelf;
        if (finished && strongSelf.wasPlayingOnSeek)
        {
            strongSelf.playingOnSeek = NO;
            [strongSelf.playbackController play];
        }
    }];
}

- (IBAction)handleFullScreenButtonPressed:(UIButton *)sender
{
    if (sender.isSelected)
    {
        sender.selected = NO;
        [self.delegate handleExitFullScreenButtonPressed];
    }
    else
    {
        sender.selected = YES;
        [self.delegate handleEnterFullScreenButtonPressed];
    }
}

- (IBAction)handleClosedCaptionButtonPressed:(UIButton *)sender
{
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:self.ccMenuController];
    [self presentViewController:navController animated:YES completion:nil];
}


#pragma mark - BCOVPlaybackSessionConsumer

- (void)didAdvanceToPlaybackSession:(id<BCOVPlaybackSession>)session
{
    self.currentPlayer = session.player;

    // Reset State
    self.playingOnSeek = NO;
    self.playheadLabel.text = [ControlsViewController formatTime:0];
    self.playheadSlider.value = 0.f;

    [self invalidateTimerAndShowControls];
}

- (void)playbackSession:(id<BCOVPlaybackSession>)session 
      didChangeDuration:(NSTimeInterval)duration
{
    self.durationLabel.text = [ControlsViewController formatTime:duration];
}

- (void)playbackSession:(id<BCOVPlaybackSession>)session 
          didProgressTo:(NSTimeInterval)progress
{
    self.playheadLabel.text = [ControlsViewController formatTime:progress];

    NSTimeInterval duration = CMTimeGetSeconds(session.player.currentItem.duration);
    float percent = progress / duration;
    self.playheadSlider.value = isnan(percent) ? 0.0f : percent;
}

- (void)playbackSession:(id<BCOVPlaybackSession>)session 
didReceiveLifecycleEvent:(BCOVPlaybackSessionLifecycleEvent *)lifecycleEvent
{
    if ([kBCOVPlaybackSessionLifecycleEventPlay isEqualToString:lifecycleEvent.eventType])
    {
        self.playPauseButton.selected = YES;
        [self reestablishTimer];
    }
    else if([kBCOVPlaybackSessionLifecycleEventPause isEqualToString:lifecycleEvent.eventType])
    {
        self.playPauseButton.selected = NO;
        [self invalidateTimerAndShowControls];
    } 
    else if ([kBCOVPlaybackSessionLifecycleEventReady isEqualToString:lifecycleEvent.eventType])
    {
        self.ccMenuController.currentSession = session;
    }
}


#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
      shouldReceiveTouch:(UITouch *)touch
{
    // This makes sure that we don't try and hide the controls if someone is pressing any of the buttons
    // or slider.
    if([touch.view isKindOfClass:[UIButton class]] || [touch.view isKindOfClass:[UISlider class]])
    {
        return NO;
    }

    return YES;
}

@end
