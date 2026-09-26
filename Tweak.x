#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#pragma mark - Color

static UIColor *ZolaColorFromHex(NSString *hex) {
    if (![hex isKindOfClass:[NSString class]]) {
        return nil;
    }

    NSString *clean = [[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]
                       uppercaseString];

    if (clean.length != 6 && clean.length != 8) {
        return nil;
    }

    unsigned int value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexInt:&value]) {
        return nil;
    }

    CGFloat r, g, b, a = 1.0;

    if (clean.length == 8) {
        r = ((value >> 24) & 0xFF) / 255.0;
        g = ((value >> 16) & 0xFF) / 255.0;
        b = ((value >> 8) & 0xFF) / 255.0;
        a = (value & 0xFF) / 255.0;
    } else {
        r = ((value >> 16) & 0xFF) / 255.0;
        g = ((value >> 8) & 0xFF) / 255.0;
        b = (value & 0xFF) / 255.0;
    }

    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static UIColor *ZolaBubbleColor(void) {
    NSString *hex = [[NSUserDefaults standardUserDefaults]
                      stringForKey:@"ZolaThemeBubbleColorHex"];

    if (hex.length == 0) {
        hex = @"E6F4FF";
    }

    return ZolaColorFromHex(hex) ?: [UIColor colorWithRed:0.90
                                                     green:0.96
                                                      blue:1.0
                                                     alpha:1.0];
}

#pragma mark - Transparent bar cleanup

static void ZolaHideTransparentBarChildren(UIView *container) {
    UIView *containerView = (UIView *)container;

    for (UIView *view in containerView.subviews) {
        NSString *className = NSStringFromClass(view.class);

        if ([className isEqualToString:@"_UIBarBackground"] ||
            [view isKindOfClass:[UIImageView class]]) {
            view.hidden = YES;
            view.alpha = 0.0;
        }
    }
}

#pragma mark - UIImage recoloring

static UIImage *ZolaTintBubbleImage(UIImage *image, UIColor *color) {
    if (!image || !color) {
        return image;
    }

    CGFloat scale = image.scale > 0 ? image.scale : UIScreen.mainScreen.scale;
    CGSize size = image.size;

    UIGraphicsBeginImageContextWithOptions(size, NO, scale);
    CGRect rect = (CGRect){CGPointZero, size};

    [image drawInRect:rect];

    color = [color colorWithAlphaComponent:1.0];
    [color setFill];

    UIRectFillUsingBlendMode(rect, kCGBlendModeSourceIn);

    UIImage *tinted = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return tinted ?: image;
}

static UIImageView *ZolaFindBubbleImageView(UIView *view) {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UIImageView class]]) {
            UIImageView *imageView = (UIImageView *)subview;

            if (imageView.image) {
                NSString *imageClass =
                    NSStringFromClass(imageView.image.class);

                if ([imageClass isEqualToString:@"_UIResizableImage"] ||
                    CGRectEqualToRect(imageView.frame, view.bounds)) {
                    return imageView;
                }
            }
        }

        UIImageView *nested = ZolaFindBubbleImageView(subview);
        if (nested) {
            return nested;
        }
    }

    return nil;
}

static void ZolaStyleBubbleButton(UIView *bubbleButton) {
    UIImageView *imageView = ZolaFindBubbleImageView(bubbleButton);

    if (!imageView || !imageView.image) {
        return;
    }

    UIColor *bubbleColor = ZolaBubbleColor();

    // Keep the V2 bubble styling unchanged.
    imageView.image = ZolaTintBubbleImage(imageView.image, bubbleColor);
    imageView.backgroundColor = UIColor.clearColor;
    imageView.alpha = 1.0;
    imageView.hidden = NO;

    CALayer *layer = imageView.layer;
    layer.cornerRadius = 16.0;
    layer.masksToBounds = NO;

    layer.shadowColor = UIColor.blackColor.CGColor;
    layer.shadowOpacity = 0.14;
    layer.shadowRadius = 5.0;
    layer.shadowOffset = CGSizeMake(0.0, 2.0);
    layer.shadowPath = nil;
}

#pragma mark - Recursive bubble search

static void ZolaStyleBubblesInView(UIView *view) {
    for (UIView *subview in view.subviews) {
        NSString *className = NSStringFromClass(subview.class);

        if ([className isEqualToString:@"SubMenuButton"] ||
            [className isEqualToString:@"MenuButton"]) {
            ZolaStyleBubbleButton(subview);
        }

        ZolaStyleBubblesInView(subview);
    }
}

#pragma mark - Navigation background

%hook _ZDSNavigationBarBackgroundView

- (void)layoutSubviews {
    %orig;

    UIView *backgroundView = (UIView *)self;

    backgroundView.backgroundColor = UIColor.clearColor;
    backgroundView.layer.backgroundColor = UIColor.clearColor.CGColor;
    backgroundView.layer.opaque = NO;

    // Clear Zalo's default pattern image completely.
    backgroundView.layer.contents = nil;

    // Remove any remaining image-backed border / texture views.
    for (UIView *view in backgroundView.subviews) {
        if ([view isKindOfClass:[UIImageView class]]) {
            view.hidden = YES;
            view.alpha = 0.0;
        }
    }
}

%end

#pragma mark - Navigation bar container

%hook UXNavigationBar

- (void)layoutSubviews {
    %orig;

    UIView *barView = (UIView *)self;

    barView.backgroundColor = UIColor.clearColor;
    barView.layer.backgroundColor = UIColor.clearColor.CGColor;
    barView.layer.opaque = NO;
    barView.layer.shadowOpacity = 0.0;
}

%end

#pragma mark - Chat input component

%hook KBChatInputComponentView

- (void)layoutSubviews {
    %orig;

    UIView *inputView = (UIView *)self;

    inputView.backgroundColor = UIColor.clearColor;
    inputView.layer.backgroundColor = UIColor.clearColor.CGColor;
    inputView.layer.opaque = NO;

    ZolaHideTransparentBarChildren(inputView);
}

%end

#pragma mark - Chat input toolbar

%hook KBToolbarView

- (void)layoutSubviews {
    %orig;

    UIView *toolbarView = (UIView *)self;

    toolbarView.backgroundColor = UIColor.clearColor;
    toolbarView.layer.backgroundColor = UIColor.clearColor.CGColor;
    toolbarView.layer.opaque = NO;

    ZolaHideTransparentBarChildren(toolbarView);
}

%end

#pragma mark - Main tab bar

%hook UITabBar

- (void)layoutSubviews {
    %orig;

    UIView *tabBarView = (UIView *)self;

    tabBarView.backgroundColor = UIColor.clearColor;
    tabBarView.layer.backgroundColor = UIColor.clearColor.CGColor;
    tabBarView.layer.opaque = NO;
    tabBarView.layer.shadowOpacity = 0.0;

    ZolaHideTransparentBarChildren(tabBarView);
}

%end

#pragma mark - Text message bubble

%hook ALTextMessageTableItemCell

- (void)layoutSubviews {
    %orig;

    // Preserve the existing V2 bubble styling for MenuButton/SubMenuButton.
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    ZolaStyleBubblesInView(cell.contentView);
}

%end
