#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static char kZolaNavBlurKey;
static char kZolaTabBlurKey;
static char kZolaToolbarBlurKey;

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

#pragma mark - Blur

static UIVisualEffectView *ZolaEnsureBlur(UIView *container, char *key) {
    UIVisualEffectView *blur =
        objc_getAssociatedObject(container, key);

    if (!blur) {
        UIBlurEffect *effect =
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];

        blur = [[UIVisualEffectView alloc] initWithEffect:effect];
        blur.userInteractionEnabled = NO;
        blur.autoresizingMask =
            UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleHeight;

        objc_setAssociatedObject(container,
                                 key,
                                 blur,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        [container insertSubview:blur atIndex:0];
    }

    blur.frame = container.bounds;
    [container sendSubviewToBack:blur];

    return blur;
}

#pragma mark - Background cleanup

static BOOL ZolaLooksLikeSystemBackgroundImageView(UIView *view, UIView *parent) {
    if (![view isKindOfClass:[UIImageView class]]) {
        return NO;
    }

    if (view.frame.size.width < parent.bounds.size.width * 0.85) {
        return NO;
    }

    if (view.frame.size.height < parent.bounds.size.height * 0.60) {
        return NO;
    }

    NSString *colorDescription = view.backgroundColor.description ?: @"";
    return [colorDescription localizedCaseInsensitiveContainsString:@"systemBackgroundColor"];
}

static void ZolaHideBackgroundSubviews(UIView *container) {
    for (UIView *view in container.subviews) {
        NSString *className = NSStringFromClass(view.class);

        if ([className isEqualToString:@"_ZDSNavigationBarBackgroundView"] ||
            [className isEqualToString:@"_UIBarBackground"]) {
            view.hidden = YES;
            view.alpha = 0.0;
            continue;
        }

        if (ZolaLooksLikeSystemBackgroundImageView(view, container)) {
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

    // Preserve Zalo's original resizable bubble silhouette/tail,
    // while recoloring the image instead of replacing its geometry.
    imageView.image = ZolaTintBubbleImage(imageView.image, bubbleColor);
    imageView.backgroundColor = UIColor.clearColor;
    imageView.alpha = 1.0;
    imageView.hidden = NO;

    CALayer *layer = imageView.layer;

    // Keep the original bubble bounds but add a soft drop shadow.
    layer.cornerRadius = 16.0;
    layer.masksToBounds = NO;

    layer.shadowColor = UIColor.blackColor.CGColor;
    layer.shadowOpacity = 0.14;
    layer.shadowRadius = 5.0;
    layer.shadowOffset = CGSizeMake(0.0, 2.0);

    // No explicit rectangle path: Core Animation can derive the shadow
    // from the image-backed layer's visible content.
    layer.shadowPath = nil;
}

#pragma mark - Recursive bubble search

static void ZolaStyleBubblesInView(UIView *view) {
    for (UIView *subview in view.subviews) {
        NSString *className = NSStringFromClass(subview.class);

        if ([className isEqualToString:@"SubMenuButton"]) {
            ZolaStyleBubbleButton(subview);
        }

        ZolaStyleBubblesInView(subview);
    }
}

#pragma mark - Navigation Bar

%hook UXNavigationBar

- (void)layoutSubviews {
    %orig;

    self.backgroundColor = UIColor.clearColor;
    self.layer.backgroundColor = UIColor.clearColor.CGColor;
    self.layer.opaque = NO;
    self.layer.shadowOpacity = 0.0;

    // The dump shows Zalo's real navigation background class.
    for (UIView *view in self.subviews) {
        if ([NSStringFromClass(view.class)
             isEqualToString:@"_ZDSNavigationBarBackgroundView"]) {
            view.hidden = YES;
            view.alpha = 0.0;
        }
    }

    // Associated object prevents duplicate blur views.
    ZolaEnsureBlur(self, &kZolaNavBlurKey);
}

%end

#pragma mark - Chat input toolbar

%hook KBToolbarView

- (void)layoutSubviews {
    %orig;

    self.backgroundColor = UIColor.clearColor;
    self.layer.backgroundColor = UIColor.clearColor.CGColor;
    self.layer.opaque = NO;

    ZolaHideBackgroundSubviews(self);
    ZolaEnsureBlur(self, &kZolaToolbarBlurKey);
}

%end

#pragma mark - Main Tab Bar

%hook UITabBar

- (void)layoutSubviews {
    %orig;

    self.backgroundColor = UIColor.clearColor;
    self.layer.backgroundColor = UIColor.clearColor.CGColor;
    self.layer.opaque = NO;
    self.layer.shadowOpacity = 0.0;

    // Dump shows UITabBar -> _UIBarBackground -> UIImageView(systemBackgroundColor).
    ZolaHideBackgroundSubviews(self);
    ZolaEnsureBlur(self, &kZolaTabBlurKey);
}

%end

#pragma mark - Text message bubble

%hook ALTextMessageTableItemCell

- (void)layoutSubviews {
    %orig;

    // The dump shows:
    // ALTextMessageTableItemCell
    //   -> MenuButton
    //      -> SubMenuButton
    //         -> UIImageView(image = _UIResizableImage)
    //
    // We keep that original image geometry and only recolor/style it.
    ZolaStyleBubblesInView(self.contentView);
}

%end
