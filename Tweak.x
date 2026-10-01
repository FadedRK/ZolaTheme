#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

#pragma mark - Keys / Tags

static NSString * const ZolaBubblePathKey = @"ZolaThemeBubblePath";
static NSString * const ZolaGlobalBackgroundPathKey = @"ZolaThemeGlobalBackgroundPath";
static NSString * const ZolaPerChatBackgroundMapKey = @"ZolaThemePerChatBackgroundMap";
static NSString * const ZolaGlobalBackgroundEnabledKey = @"ZolaThemeGlobalBackgroundEnabled";


static char kZolaCustomBackgroundViewKey;
static char kZolaAppliedBubblePathKey;
static char kZolaAppliedBubbleImageKey;

#pragma mark - Defaults

static NSUserDefaults *ZolaDefaults(void) {
    return [NSUserDefaults standardUserDefaults];
}

static BOOL ZolaGlobalBackgroundEnabled(void) {
    return [ZolaDefaults() boolForKey:ZolaGlobalBackgroundEnabledKey];
}

static void ZolaSetGlobalBackgroundEnabled(BOOL enabled) {
    [ZolaDefaults() setBool:enabled forKey:ZolaGlobalBackgroundEnabledKey];
    [ZolaDefaults() synchronize];
}

#pragma mark - Stable chat key

static NSString *ZolaStableHash(NSString *string) {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    const unsigned char *bytes = data.bytes;
    NSUInteger length = data.length;

    uint64_t hash = 1469598103934665603ULL;
    for (NSUInteger i = 0; i < length; i++) {
        hash ^= bytes[i];
        hash *= 1099511628211ULL;
    }

    return [NSString stringWithFormat:@"%016llx", hash];
}

static NSString *ZolaCurrentChatKey(void);

#pragma mark - Colors

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
    NSString *hex = [ZolaDefaults() stringForKey:@"ZolaThemeBubbleColorHex"];

    if (hex.length == 0) {
        hex = @"E6F4FF";
    }

    return ZolaColorFromHex(hex) ?: [UIColor colorWithRed:0.90
                                                     green:0.96
                                                      blue:1.0
                                                     alpha:1.0];
}

#pragma mark - Window / controller helpers

static NSArray<UIWindow *> *ZolaAllWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateUnattached) {
                continue;
            }

            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }

            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (!window.hidden &&
                    window.alpha > 0.01 &&
                    window.bounds.size.width > 0) {
                    [windows addObject:window];
                }
            }
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            if (!window.hidden &&
                window.alpha > 0.01 &&
                window.bounds.size.width > 0) {
                [windows addObject:window];
            }
        }
#pragma clang diagnostic pop
    }

    return windows;
}

static UIViewController *ZolaTopViewController(void) {
    UIWindow *window = nil;

    for (UIWindow *candidate in ZolaAllWindows()) {
        if (candidate.isKeyWindow) {
            window = candidate;
            break;
        }

        if (!window) {
            window = candidate;
        }
    }

    if (!window) {
        return nil;
    }

    UIViewController *vc = window.rootViewController;

    while (vc) {
        UIViewController *next = nil;

        if (vc.presentedViewController &&
            !vc.presentedViewController.isBeingDismissed) {
            next = vc.presentedViewController;
        } else if ([vc isKindOfClass:[UINavigationController class]]) {
            next = [(UINavigationController *)vc visibleViewController];
        } else if ([vc isKindOfClass:[UITabBarController class]]) {
            next = [(UITabBarController *)vc selectedViewController];
        }

        if (!next || next == vc) {
            break;
        }

        vc = next;
    }

    return vc;
}

static UIView *ZolaFindViewWithClassName(UIView *root, NSString *className) {
    if (!root || className.length == 0) {
        return nil;
    }

    for (UIView *subview in root.subviews) {
        if ([NSStringFromClass(subview.class) isEqualToString:className]) {
            return subview;
        }

        UIView *found = ZolaFindViewWithClassName(subview, className);

        if (found) {
            return found;
        }
    }

    return nil;
}

static UINavigationBar *ZolaFindUXNavigationBar(void) {
    for (UIWindow *window in ZolaAllWindows()) {
        UIView *view =
            ZolaFindViewWithClassName(window, @"UXNavigationBar");

        if (view) {
            return (UINavigationBar *)view;
        }
    }

    return nil;
}

static NSString *ZolaCurrentChatKey(void) {
    UINavigationBar *bar = ZolaFindUXNavigationBar();

    NSString *title = nil;

    if (bar.topItem.title.length > 0) {
        title = bar.topItem.title;
    } else if (bar.items.lastObject.title.length > 0) {
        title = bar.items.lastObject.title;
    }

    if (title.length == 0) {
        UIViewController *top = ZolaTopViewController();
        title = top.navigationItem.title;
    }

    if (title.length == 0) {
        return nil;
    }

    return title;
}

#pragma mark - Stored files

static NSURL *ZolaThemeDirectoryURL(void) {
    NSURL *documents =
        [[NSFileManager defaultManager]
            URLsForDirectory:NSDocumentDirectory
                   inDomains:NSUserDomainMask].firstObject;

    if (!documents) {
        return nil;
    }

    NSURL *directory =
        [documents URLByAppendingPathComponent:@"ZolaTheme" isDirectory:YES];

    [[NSFileManager defaultManager]
        createDirectoryAtURL:directory
   withIntermediateDirectories:YES
                    attributes:nil
                         error:nil];

    return directory;
}

static NSString *ZolaCopySelectedImage(NSURL *sourceURL,
                                       NSString *baseName,
                                       NSString *suffix) {
    if (!sourceURL) {
        return nil;
    }

    BOOL securityScoped = NO;

    if ([sourceURL respondsToSelector:@selector(startAccessingSecurityScopedResource)]) {
        securityScoped = [sourceURL startAccessingSecurityScopedResource];
    }

    NSData *data = [NSData dataWithContentsOfURL:sourceURL];

    if (securityScoped) {
        [sourceURL stopAccessingSecurityScopedResource];
    }

    if (!data) {
        return nil;
    }

    NSURL *directory = ZolaThemeDirectoryURL();

    if (!directory) {
        return nil;
    }

    NSString *extension = sourceURL.pathExtension.lowercaseString;

    if (extension.length == 0) {
        extension = @"png";
    }

    NSString *fileName =
        [NSString stringWithFormat:@"%@_%@.%@",
         baseName,
         suffix ?: @"image",
         extension];

    NSURL *destination = [directory URLByAppendingPathComponent:fileName];

    if (![data writeToURL:destination options:NSDataWritingAtomic error:nil]) {
        return nil;
    }

    return destination.path;
}

#pragma mark - Document picker

typedef NS_ENUM(NSInteger, ZolaThemePickerMode) {
    ZolaThemePickerModeBubble = 0,
    ZolaThemePickerModeBackground = 1
};

@interface ZolaThemeDocumentPickerDelegate : NSObject <UIDocumentPickerDelegate>
+ (instancetype)shared;
- (void)presentPickerFrom:(UIViewController *)viewController
                     mode:(ZolaThemePickerMode)mode;
@end

@implementation ZolaThemeDocumentPickerDelegate {
    ZolaThemePickerMode _mode;
}

+ (instancetype)shared {
    static ZolaThemeDocumentPickerDelegate *shared;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        shared = [self new];
    });

    return shared;
}

- (void)presentPickerFrom:(UIViewController *)viewController
                     mode:(ZolaThemePickerMode)mode {
    if (!viewController) {
        return;
    }

    _mode = mode;

    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc]
            initForOpeningContentTypes:@[[UTType typeWithIdentifier:@"public.image"]]];

    picker.allowsMultipleSelection = NO;
    picker.delegate = self;
    [viewController presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *sourceURL = urls.firstObject;

    if (!sourceURL) {
        return;
    }

    if (_mode == ZolaThemePickerModeBubble) {
        NSString *path =
            ZolaCopySelectedImage(sourceURL, @"bubble", @"custom");

        if (path.length > 0) {
            [ZolaDefaults() setObject:path forKey:ZolaBubblePathKey];
            [ZolaDefaults() synchronize];

            dispatch_async(dispatch_get_main_queue(), ^{
                UIViewController *top = ZolaTopViewController();

                if (top.presentedViewController == controller) {
                    [top dismissViewControllerAnimated:YES completion:^{
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[NSNotificationCenter defaultCenter]
                                postNotificationName:@"ZolaThemeBubbleChanged"
                                              object:nil];
                        });
                    }];
                } else {
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:@"ZolaThemeBubbleChanged"
                                      object:nil];
                }
            });

            return;
        }
    }

    NSString *chatKey = ZolaCurrentChatKey();
    NSString *stableKey = chatKey.length > 0 ? ZolaStableHash(chatKey) : @"default";

    NSString *path =
        ZolaCopySelectedImage(sourceURL, @"background", stableKey);

    if (path.length == 0) {
        return;
    }

    if (ZolaGlobalBackgroundEnabled()) {
        [ZolaDefaults() setObject:path forKey:ZolaGlobalBackgroundPathKey];
    } else if (chatKey.length > 0) {
        NSMutableDictionary *map =
            [[ZolaDefaults() dictionaryForKey:ZolaPerChatBackgroundMapKey]
                mutableCopy];

        if (!map) {
            map = [NSMutableDictionary dictionary];
        }

        map[chatKey] = path;
        [ZolaDefaults() setObject:map forKey:ZolaPerChatBackgroundMapKey];
    } else {
        [ZolaDefaults() setObject:path forKey:ZolaGlobalBackgroundPathKey];
    }

    [ZolaDefaults() synchronize];

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = ZolaTopViewController();

        if (top.presentedViewController == controller) {
            [top dismissViewControllerAnimated:YES completion:^{
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:@"ZolaThemeBackgroundChanged"
                                  object:nil];
            }];
        } else {
            [[NSNotificationCenter defaultCenter]
                postNotificationName:@"ZolaThemeBackgroundChanged"
                              object:nil];
        }
    });
}

@end

#pragma mark - Bubble image

static UIImage *ZolaLoadBubbleImage(void) {
    NSString *path = [ZolaDefaults() stringForKey:ZolaBubblePathKey];

    if (path.length == 0) {
        return nil;
    }

    NSData *data = [NSData dataWithContentsOfFile:path];

    if (!data) {
        return nil;
    }

    return [UIImage imageWithData:data scale:UIScreen.mainScreen.scale];
}

static UIImage *ZolaMakeResizableBubbleImage(UIImage *image) {
    if (!image) {
        return nil;
    }

    CGFloat width = image.size.width;
    CGFloat height = image.size.height;

    CGFloat horizontalInset = MIN(MAX(width * 0.25, 8.0), 32.0);
    CGFloat verticalInset = MIN(MAX(height * 0.25, 8.0), 32.0);

    UIEdgeInsets insets =
        UIEdgeInsetsMake(verticalInset,
                         horizontalInset,
                         verticalInset,
                         horizontalInset);

    return [image resizableImageWithCapInsets:insets
                                  resizingMode:UIImageResizingModeStretch];
}

#pragma mark - Background image

static NSString *ZolaBackgroundPathForCurrentChat(void) {
    NSUserDefaults *defaults = ZolaDefaults();

    if (ZolaGlobalBackgroundEnabled()) {
        return [defaults stringForKey:ZolaGlobalBackgroundPathKey];
    }

    NSString *chatKey = ZolaCurrentChatKey();

    if (chatKey.length == 0) {
        return nil;
    }

    NSDictionary *map =
        [defaults dictionaryForKey:ZolaPerChatBackgroundMapKey];

    return map[chatKey];
}

static UIImageView *ZolaFindOriginalChatBackgroundImageView(UIView *host) {
    CGFloat hostWidth = CGRectGetWidth(host.bounds);
    CGFloat hostHeight = CGRectGetHeight(host.bounds);

    for (UIView *subview in host.subviews) {
        if (![subview isKindOfClass:[UIImageView class]]) {
            continue;
        }

        CGRect frame = subview.frame;

        BOOL wideEnough = CGRectGetWidth(frame) >= hostWidth * 0.85;
        BOOL tallEnough = CGRectGetHeight(frame) >= hostHeight * 1.05;
        BOOL extendsAboveHost = CGRectGetMinY(frame) <= 0.0;

        if (wideEnough && tallEnough && extendsAboveHost) {
            return (UIImageView *)subview;
        }
    }

    return nil;
}

static UIView *ZolaFindChatBackgroundHostFromCollectionView(UIView *collectionView) {
    UIView *host = collectionView.superview;

    for (NSInteger depth = 0; depth < 6 && host; depth++) {
        UIImageView *background =
            ZolaFindOriginalChatBackgroundImageView(host);

        BOOL hasCollection =
            [host.subviews containsObject:collectionView];

        if (background && hasCollection) {
            return host;
        }

        host = host.superview;
    }

    return nil;
}

static void ZolaApplyChatBackground(UIView *collectionView) {
    UIView *host =
        ZolaFindChatBackgroundHostFromCollectionView(collectionView);

    if (!host) {
        return;
    }

    UIImageView *original =
        ZolaFindOriginalChatBackgroundImageView(host);

    NSString *path = ZolaBackgroundPathForCurrentChat();

    UIImageView *custom =
        objc_getAssociatedObject(host, &kZolaCustomBackgroundViewKey);

    if (path.length == 0) {
        if (custom) {
            custom.hidden = YES;
        }

        original.hidden = NO;
        return;
    }

    UIImage *image =
        [UIImage imageWithContentsOfFile:path];

    if (!image) {
        if (custom) {
            custom.hidden = YES;
        }

        original.hidden = NO;
        return;
    }

    if (!custom) {
        custom = [[UIImageView alloc] initWithImage:image];
        custom.userInteractionEnabled = NO;
        custom.clipsToBounds = YES;
        custom.contentMode = UIViewContentModeScaleAspectFill;
        custom.autoresizingMask =
            UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleHeight;

        objc_setAssociatedObject(host,
                                 &kZolaCustomBackgroundViewKey,
                                 custom,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (original) {
        custom.frame = original.frame;
        custom.autoresizingMask = original.autoresizingMask;
        [host insertSubview:custom atIndex:0];
        original.hidden = YES;
    } else {
        custom.frame = host.bounds;
        [host insertSubview:custom atIndex:0];
    }

    custom.image = image;
    custom.hidden = NO;

    // Keep the chat list and controls above the custom background.
    [host sendSubviewToBack:custom];
}

#pragma mark - Existing V2 bubble styling

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

static BOOL ZolaBubbleIsOutgoing(UIView *bubbleButton, UIView *cell) {
    CGRect rect =
        [bubbleButton.superview convertRect:bubbleButton.frame
                                     toView:cell];

    return CGRectGetMidX(rect) > CGRectGetWidth(cell.bounds) * 0.5;
}

static void ZolaStyleBubbleButton(UIView *bubbleButton, UIView *cell) {
    UIImageView *imageView = ZolaFindBubbleImageView(bubbleButton);

    if (!imageView || !imageView.image) {
        return;
    }

    NSString *customPath =
        [ZolaDefaults() stringForKey:ZolaBubblePathKey];

    if (customPath.length > 0 && ZolaBubbleIsOutgoing(bubbleButton, cell)) {
        UIImage *customImage = ZolaLoadBubbleImage();

        if (customImage) {
            UIImage *resizable =
                ZolaMakeResizableBubbleImage(customImage);

            NSString *appliedPath =
                objc_getAssociatedObject(imageView, &kZolaAppliedBubblePathKey);

            if (![appliedPath isEqualToString:customPath]) {
                imageView.image = resizable ?: customImage;

                objc_setAssociatedObject(imageView,
                                         &kZolaAppliedBubblePathKey,
                                         customPath,
                                         OBJC_ASSOCIATION_COPY_NONATOMIC);

                objc_setAssociatedObject(imageView,
                                         &kZolaAppliedBubbleImageKey,
                                         customImage,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    } else if (customPath.length == 0) {
        // Preserve the existing V2/V4 default coloring when no custom
        // bubble image is configured.
        imageView.image =
            ZolaTintBubbleImage(imageView.image, ZolaBubbleColor());

        objc_setAssociatedObject(imageView,
                                 &kZolaAppliedBubblePathKey,
                                 nil,
                                 OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(imageView,
                                 &kZolaAppliedBubbleImageKey,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

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

static void ZolaStyleBubblesInView(UIView *view, UIView *cell) {
    for (UIView *subview in view.subviews) {
        NSString *className = NSStringFromClass(subview.class);

        if ([className isEqualToString:@"SubMenuButton"] ||
            [className isEqualToString:@"MenuButton"]) {
            ZolaStyleBubbleButton(subview, cell);
        }

        ZolaStyleBubblesInView(subview, cell);
    }
}

#pragma mark - Settings screen

@interface ZolaThemeSettingsViewController : UIViewController
@end

@implementation ZolaThemeSettingsViewController {
    UISwitch *_globalSwitch;
    UILabel *_chatLabel;
    UILabel *_bubbleLabel;
    UILabel *_backgroundLabel;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.navigationItem.title = @"ZolaTheme";
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                  target:self
                                  action:@selector(close)];

    UILabel *title =
        [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"气泡与聊天背景";
    title.font = [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    _chatLabel =
        [[UILabel alloc] initWithFrame:CGRectZero];
    _chatLabel.text =
        [NSString stringWithFormat:@"当前聊天：%@",
         ZolaCurrentChatKey() ?: @"未识别"];
    _chatLabel.font = [UIFont systemFontOfSize:13];
    _chatLabel.textColor = UIColor.secondaryLabelColor;
    _chatLabel.numberOfLines = 2;
    _chatLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_chatLabel];

    UIButton *bubbleButton =
        [UIButton buttonWithType:UIButtonTypeSystem];
    [bubbleButton setTitle:@"上传自定义聊天气泡"
                  forState:UIControlStateNormal];
    bubbleButton.titleLabel.font =
        [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    bubbleButton.contentHorizontalAlignment =
        UIControlContentHorizontalAlignmentLeft;
    bubbleButton.translatesAutoresizingMaskIntoConstraints = NO;
    [bubbleButton addTarget:self
                     action:@selector(selectBubble)
           forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:bubbleButton];

    _bubbleLabel =
        [[UILabel alloc] initWithFrame:CGRectZero];
    _bubbleLabel.text =
        [ZolaDefaults() stringForKey:ZolaBubblePathKey].length > 0
            ? @"已设置自定义气泡"
            : @"使用 Zalo 默认气泡";
    _bubbleLabel.font = [UIFont systemFontOfSize:12];
    _bubbleLabel.textColor = UIColor.secondaryLabelColor;
    _bubbleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_bubbleLabel];

    UIButton *backgroundButton =
        [UIButton buttonWithType:UIButtonTypeSystem];
    [backgroundButton setTitle:@"上传聊天背景"
                       forState:UIControlStateNormal];
    backgroundButton.titleLabel.font =
        [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    backgroundButton.contentHorizontalAlignment =
        UIControlContentHorizontalAlignmentLeft;
    backgroundButton.translatesAutoresizingMaskIntoConstraints = NO;
    [backgroundButton addTarget:self
                         action:@selector(selectBackground)
               forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:backgroundButton];

    _backgroundLabel =
        [[UILabel alloc] initWithFrame:CGRectZero];
    _backgroundLabel.text =
        ZolaGlobalBackgroundEnabled()
            ? @"当前模式：所有聊天共用全局背景"
            : @"当前模式：按聊天分别设置背景";
    _backgroundLabel.font = [UIFont systemFontOfSize:12];
    _backgroundLabel.textColor = UIColor.secondaryLabelColor;
    _backgroundLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_backgroundLabel];

    UILabel *globalTitle =
        [[UILabel alloc] initWithFrame:CGRectZero];
    globalTitle.text = @"全局应用聊天背景";
    globalTitle.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    globalTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:globalTitle];

    UILabel *globalSub =
        [[UILabel alloc] initWithFrame:CGRectZero];
    globalSub.text = @"开启：上传的背景对所有聊天生效；关闭：仅当前聊天生效";
    globalSub.font = [UIFont systemFontOfSize:12];
    globalSub.textColor = UIColor.secondaryLabelColor;
    globalSub.numberOfLines = 2;
    globalSub.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:globalSub];

    _globalSwitch =
        [[UISwitch alloc] initWithFrame:CGRectZero];
    _globalSwitch.on = ZolaGlobalBackgroundEnabled();
    _globalSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [_globalSwitch addTarget:self
                      action:@selector(globalSwitchChanged:)
            forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_globalSwitch];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
        [title.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [title.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [_chatLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [_chatLabel.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [_chatLabel.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],

        [bubbleButton.topAnchor constraintEqualToAnchor:_chatLabel.bottomAnchor constant:28],
        [bubbleButton.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [bubbleButton.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [bubbleButton.heightAnchor constraintEqualToConstant:34],

        [_bubbleLabel.topAnchor constraintEqualToAnchor:bubbleButton.bottomAnchor constant:1],
        [_bubbleLabel.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [_bubbleLabel.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],

        [backgroundButton.topAnchor constraintEqualToAnchor:_bubbleLabel.bottomAnchor constant:24],
        [backgroundButton.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [backgroundButton.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [backgroundButton.heightAnchor constraintEqualToConstant:34],

        [_backgroundLabel.topAnchor constraintEqualToAnchor:backgroundButton.bottomAnchor constant:1],
        [_backgroundLabel.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [_backgroundLabel.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],

        [globalTitle.topAnchor constraintEqualToAnchor:_backgroundLabel.bottomAnchor constant:24],
        [globalTitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [globalTitle.trailingAnchor constraintLessThanOrEqualToAnchor:_globalSwitch.leadingAnchor constant:-12],

        [globalSub.topAnchor constraintEqualToAnchor:globalTitle.bottomAnchor constant:2],
        [globalSub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [globalSub.trailingAnchor constraintLessThanOrEqualToAnchor:_globalSwitch.leadingAnchor constant:-12],

        [_globalSwitch.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [_globalSwitch.centerYAnchor constraintEqualToAnchor:globalTitle.centerYAnchor],

        [globalSub.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20]
    ]];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)selectBubble {
    [[ZolaThemeDocumentPickerDelegate shared]
        presentPickerFrom:self
                     mode:ZolaThemePickerModeBubble];
}

- (void)selectBackground {
    [[ZolaThemeDocumentPickerDelegate shared]
        presentPickerFrom:self
                     mode:ZolaThemePickerModeBackground];
}

- (void)globalSwitchChanged:(UISwitch *)sender {
    ZolaSetGlobalBackgroundEnabled(sender.isOn);

    _backgroundLabel.text =
        sender.isOn
            ? @"当前模式：所有聊天共用全局背景"
            : @"当前模式：按聊天分别设置背景";

    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"ZolaThemeBackgroundChanged"
                      object:nil];
}

@end

static void ZolaPresentSettings(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = ZolaTopViewController();

        if (!top) {
            return;
        }

        UINavigationController *nav =
            [[UINavigationController alloc]
                initWithRootViewController:[ZolaThemeSettingsViewController new]];

        nav.modalPresentationStyle = UIModalPresentationPageSheet;

        [top presentViewController:nav animated:YES completion:nil];
    });
}

#pragma mark - Native Zalo / ZolaCN Settings entry

static NSInteger const ZolaThemeSettingsEntryTag = 0x5A5449;
static NSInteger const ZolaCNThemeRowTag = 0x5A5452;

@interface ZolaThemeSettingsEntryTarget : NSObject
+ (instancetype)shared;
- (void)openSettings:(UIBarButtonItem *)sender;
@end

static BOOL ZolaStringLooksLikeSettings(NSString *value) {
    if (value.length == 0) {
        return NO;
    }

    NSString *title = value.lowercaseString;

    return [title containsString:@"setting"] ||
           [title isEqualToString:@"设置"] ||
           [title isEqualToString:@"cài đặt"] ||
           [title isEqualToString:@"cài đặt chung"];
}

static BOOL ZolaLooksLikeSettingsViewController(UIViewController *vc) {
    if (!vc) {
        return NO;
    }

    NSString *className =
        NSStringFromClass(vc.class).lowercaseString;

    NSString *title =
        (vc.navigationItem.title ?: vc.title);

    if ([className containsString:@"setting"] ||
        ZolaStringLooksLikeSettings(title)) {
        return YES;
    }

    UINavigationController *navigationController =
        vc.navigationController;

    UINavigationBar *bar = navigationController.navigationBar;

    if (ZolaStringLooksLikeSettings(bar.topItem.title)) {
        return YES;
    }

    return NO;
}

@implementation ZolaThemeSettingsEntryTarget

+ (instancetype)shared {
    static ZolaThemeSettingsEntryTarget *shared;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        shared = [self new];
    });

    return shared;
}

- (void)openSettings:(__unused UIBarButtonItem *)sender {
    ZolaPresentSettings();
}

@end

static void ZolaInstallNativeSettingsEntry(UIViewController *vc) {
    if (!ZolaLooksLikeSettingsViewController(vc)) {
        return;
    }

    NSMutableArray<UIBarButtonItem *> *items =
        [(vc.navigationItem.rightBarButtonItems ?: @[]) mutableCopy];

    for (UIBarButtonItem *item in items) {
        if (item.tag == ZolaThemeSettingsEntryTag) {
            return;
        }
    }

    UIBarButtonItem *item =
        [[UIBarButtonItem alloc]
            initWithTitle:@"ZolaTheme"
                  style:UIBarButtonItemStylePlain
                 target:[ZolaThemeSettingsEntryTarget shared]
                 action:@selector(openSettings:)];

    item.tag = ZolaThemeSettingsEntryTag;
    [items addObject:item];

    vc.navigationItem.rightBarButtonItems = items;
}

#pragma mark - ZolaCN compatibility

typedef NSInteger (*ZolaCNNumberOfRowsIMP)(id, SEL, UITableView *);
typedef UITableViewCell *(*ZolaCNCellForRowIMP)(id, SEL, UITableView *, NSIndexPath *);
typedef void (*ZolaCNDidSelectIMP)(id, SEL, UITableView *, NSIndexPath *);

static ZolaCNNumberOfRowsIMP ZolaCNOriginalNumberOfRows = NULL;
static ZolaCNCellForRowIMP ZolaCNOriginalCellForRow = NULL;
static ZolaCNDidSelectIMP ZolaCNOriginalDidSelect = NULL;

static NSInteger ZolaCNThemeNumberOfRows(id self,
                                         SEL _cmd,
                                         UITableView *tableView) {
    if (!ZolaCNOriginalNumberOfRows) {
        return 0;
    }

    NSInteger count =
        ZolaCNOriginalNumberOfRows(self, _cmd, tableView);

    return count + 1;
}

static UITableViewCell *ZolaCNThemeCellForRow(id self,
                                              SEL _cmd,
                                              UITableView *tableView,
                                              NSIndexPath *indexPath) {
    NSInteger originalCount =
        ZolaCNOriginalNumberOfRows
            ? ZolaCNOriginalNumberOfRows(
                  self,
                  @selector(numberOfRowsInSection:),
                  tableView)
            : 0;

    if (indexPath.section == 0 &&
        indexPath.row == originalCount) {

        static NSString *reuseIdentifier = @"ZolaCNThemeCompatCell";

        UITableViewCell *cell =
            [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];

        if (!cell) {
            cell =
                [[UITableViewCell alloc]
                    initWithStyle:UITableViewCellStyleValue1
                 reuseIdentifier:reuseIdentifier];
        }

        cell.tag = ZolaCNThemeRowTag;
        cell.accessoryView = nil;
        cell.accessoryType =
            UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.text = @"主题美化";
        cell.detailTextLabel.text = nil;

        return cell;
    }

    if (!ZolaCNOriginalCellForRow) {
        return nil;
    }

    return ZolaCNOriginalCellForRow(self, _cmd, tableView, indexPath);
}

static void ZolaCNThemeDidSelect(id self,
                                 SEL _cmd,
                                 UITableView *tableView,
                                 NSIndexPath *indexPath) {
    NSInteger originalCount =
        ZolaCNOriginalNumberOfRows
            ? ZolaCNOriginalNumberOfRows(
                  self,
                  @selector(numberOfRowsInSection:),
                  tableView)
            : 0;

    if (indexPath.section == 0 &&
        indexPath.row == originalCount) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        ZolaPresentSettings();
        return;
    }

    if (ZolaCNOriginalDidSelect) {
        ZolaCNOriginalDidSelect(self, _cmd, tableView, indexPath);
    }
}

static void ZolaInstallZolaCNSettingsEntry(void) {
    static BOOL installed = NO;

    if (installed) {
        return;
    }

    Class cls = objc_getClass("ZARSettingsViewController");

    if (!cls) {
        return;
    }

    Method rowsMethod =
        class_getInstanceMethod(cls,
                                @selector(numberOfRowsInSection:));

    Method cellMethod =
        class_getInstanceMethod(cls,
                                @selector(tableView:cellForRowAtIndexPath:));

    Method selectMethod =
        class_getInstanceMethod(cls,
                                @selector(tableView:didSelectRowAtIndexPath:));

    if (!rowsMethod || !cellMethod || !selectMethod) {
        return;
    }


    ZolaCNOriginalNumberOfRows =
        (ZolaCNNumberOfRowsIMP)method_getImplementation(rowsMethod);

    ZolaCNOriginalCellForRow =
        (ZolaCNCellForRowIMP)method_getImplementation(cellMethod);

    ZolaCNOriginalDidSelect =
        (ZolaCNDidSelectIMP)method_getImplementation(selectMethod);

    // The existing-cell check needs a live table. The first settings screen
    // will call this installer again through the retry loop; at that point
    // the original implementations are captured below. We still install our
    // compatibility row for the three-row ZolaCN version shown in use.

    installed = YES;

    method_setImplementation(rowsMethod,
                             (IMP)ZolaCNThemeNumberOfRows);

    method_setImplementation(cellMethod,
                             (IMP)ZolaCNThemeCellForRow);

    method_setImplementation(selectMethod,
                             (IMP)ZolaCNThemeDidSelect);

    NSLog(@"[ZolaTheme] ZARSettingsViewController entry installed");
}

static void ZolaRetryZolaCNSettingsEntry(void) {
    if (objc_getClass("ZARSettingsViewController")) {
        ZolaInstallZolaCNSettingsEntry();
    }
}

static void ZolaThemeViewDidAppear(UIViewController *self,
                                   SEL _cmd,
                                   BOOL animated) {
    SEL alias =
        sel_registerName("zolaTheme_original_viewDidAppear:");

    void (*orig)(id, SEL, BOOL) =
        (void (*)(id, SEL, BOOL))
        [self methodForSelector:alias];

    if (orig) {
        orig(self, alias, animated);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        ZolaRetryZolaCNSettingsEntry();
        ZolaInstallNativeSettingsEntry(self);
    });
}

static void ZolaThemeInstallSettingsHook(void) {
    Class cls = UIViewController.class;
    SEL selector = @selector(viewDidAppear:);
    SEL alias =
        sel_registerName("zolaTheme_original_viewDidAppear:");

    Method method =
        class_getInstanceMethod(cls, selector);

    if (!method ||
        class_getInstanceMethod(cls, alias)) {
        return;
    }

    class_addMethod(cls,
                    alias,
                    method_getImplementation(method),
                    method_getTypeEncoding(method));

    method_setImplementation(method,
                             (IMP)ZolaThemeViewDidAppear);
}

#pragma mark - View hierarchy dump

static NSString *ZolaViewDumpPath(void) {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [documents stringByAppendingPathComponent:@"ZolaThemeViewDump.txt"];
}

static NSString *ZolaColorDescription(UIColor *color) {
    if (!color) return @"(nil)";
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) {
        return [NSString stringWithFormat:@"rgba(%.3f, %.3f, %.3f, %.3f)", r, g, b, a];
    }
    CGFloat white = 0;
    if ([color getWhite:&white alpha:&a]) {
        return [NSString stringWithFormat:@"white(%.3f, %.3f)", white, a];
    }
    return [color description] ?: @"(unknown)";
}

static void ZolaAppendViewDump(NSMutableString *output, UIView *view, NSUInteger depth) {
    if (!view) return;

    NSMutableString *indent = [NSMutableString string];
    for (NSUInteger i = 0; i < depth; i++) [indent appendString:@"  "];

    NSString *className = NSStringFromClass(view.class);
    NSString *bg = ZolaColorDescription(view.backgroundColor);
    NSString *layerBG = view.layer.backgroundColor ? [CIColor colorWithCGColor:view.layer.backgroundColor].description : @"(nil)";

    [output appendFormat:@"%@Class: %@\n", indent, className];
    [output appendFormat:@"%@Frame: %@\n", indent, NSStringFromCGRect(view.frame)];
    [output appendFormat:@"%@Bounds: %@\n", indent, NSStringFromCGRect(view.bounds)];
    [output appendFormat:@"%@Hidden: %@  Alpha: %.3f  FirstResponder: %@\n", indent, view.hidden ? @"YES" : @"NO", view.alpha, [view isFirstResponder] ? @"YES" : @"NO"];
    [output appendFormat:@"%@Background: %@\n", indent, bg];
    [output appendFormat:@"%@Layer background: %@  Opaque: %@\n", indent, layerBG, view.layer.opaque ? @"YES" : @"NO"];

    if ([view isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)view;
        [output appendFormat:@"%@>>> UITextView textLength=%lu editable=%@\n", indent, (unsigned long)tv.text.length, tv.editable ? @"YES" : @"NO"];
    }
    if ([view isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)view;
        [output appendFormat:@"%@>>> UITextField textLength=%lu enabled=%@\n", indent, (unsigned long)tf.text.length, tf.enabled ? @"YES" : @"NO"];
    }

    for (UIView *subview in view.subviews) {
        ZolaAppendViewDump(output, subview, depth + 1);
    }
}

static void ZolaDumpKBChatInputView(UIView *inputView) {
    NSMutableString *output = [NSMutableString string];
    [output appendString:@"ZolaTheme View Dump\n"];
    [output appendFormat:@"Date: %@\n\n", [NSDate date]];
    [output appendString:@"===== KBChatInputComponentView =====\n"];
    ZolaAppendViewDump(output, inputView, 0);

    NSString *path = ZolaViewDumpPath();
    NSError *error = nil;
    if (![output writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        NSLog(@"[ZolaTheme] View dump failed: %@", error);
    } else {
        NSLog(@"[ZolaTheme] View dump saved: %@", path);
    }
}

@interface ZolaDumpGestureTarget : NSObject
+ (void)handleDump:(UITapGestureRecognizer *)gesture;
@end

@implementation ZolaDumpGestureTarget
+ (void)handleDump:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;

    ZolaDumpKBChatInputView(gesture.view);

    UIViewController *vc = gesture.view.window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ZolaTheme"
                                                                   message:@"View dump 已保存到 Documents/ZolaThemeViewDump.txt"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}
@end

static void ZolaInstallDumpGesture(UIView *view) {
    if (!view) return;

    for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
        if ([gesture.name isEqualToString:@"ZolaThemeViewDump"]) return;
    }

    UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:[ZolaDumpGestureTarget class]
                                                                               action:@selector(handleDump:)];
    gesture.numberOfTapsRequired = 7;
    gesture.numberOfTouchesRequired = 1;
    gesture.cancelsTouchesInView = NO;
    gesture.name = @"ZolaThemeViewDump";
    [view addGestureRecognizer:gesture];
}

#pragma mark - Full transparency

%hook _ZDSNavigationBarBackgroundView

- (void)layoutSubviews {
    %orig;
    UIView *view = (UIView *)self;
    view.backgroundColor = UIColor.clearColor;
    view.layer.backgroundColor = UIColor.clearColor.CGColor;
    view.layer.opaque = NO;
}

%end

%hook UXNavigationBar

- (void)layoutSubviews {
    %orig;
    UIView *view = (UIView *)self;
    view.backgroundColor = UIColor.clearColor;
    view.layer.backgroundColor = UIColor.clearColor.CGColor;
    view.layer.opaque = NO;

    for (UIView *subview in view.subviews) {
        NSString *className = NSStringFromClass(subview.class).lowercaseString;
        if ([className isEqualToString:@"_uibarbbackground"] ||
            [className containsString:@"blur"]) {
            subview.hidden = YES;
            subview.alpha = 0.0;
        }
    }
}

%end

%hook KBChatInputComponentView

- (void)layoutSubviews {
    %orig;

    UIView *view = (UIView *)self;

    // Make only the outer chat-input container transparent.
    // Do NOT modify its child controls: Zalo's native composer lives
    // inside KBToolbarView as HPGrowingTextView.
    view.backgroundColor = UIColor.clearColor;
    view.layer.backgroundColor = UIColor.clearColor.CGColor;
    view.layer.opaque = NO;

    for (UIView *subview in view.subviews) {
        NSString *className = NSStringFromClass(subview.class).lowercaseString;

        if ([className isEqualToString:@"_uibarbbackground"] ||
            [className containsString:@"blur"]) {
            subview.hidden = YES;
            subview.alpha = 0.0;
        }
    }
}

%end

%hook KBToolbarView

- (void)layoutSubviews {
    %orig;

    UIView *toolbarView = (UIView *)self;

    // The real native input box is:
    // HPGrowingTextView -> MyTextView -> HPTextViewInternal.
    // Leave that hierarchy completely untouched.
    toolbarView.backgroundColor = UIColor.clearColor;
    toolbarView.layer.backgroundColor = UIColor.clearColor.CGColor;
    toolbarView.layer.opaque = NO;

    for (UIView *subview in toolbarView.subviews) {
        NSString *className = NSStringFromClass(subview.class).lowercaseString;

        if ([className isEqualToString:@"hpgrowingtextview"] ||
            [className isEqualToString:@"mytextview"] ||
            [className isEqualToString:@"hptextviewinternal"]) {
            continue;
        }

        // Hide only toolbar chrome / separator lines.
        if ([className isEqualToString:@"_uibarbbackground"] ||
            [className containsString:@"blur"]) {
            subview.hidden = YES;
            subview.alpha = 0.0;
            continue;
        }

        // The dump shows two 0.5pt gray separator UIViews at the top
        // and bottom of KBToolbarView. Hide those without touching
        // the native HPGrowingTextView.
        if ([subview isKindOfClass:[UIView class]] &&
            subview.frame.size.height <= 1.0) {
            subview.hidden = YES;
            subview.alpha = 0.0;
        }
    }
}

%end

%hook UITabBar

- (void)layoutSubviews {
    %orig;

    UITabBar *bar = (UITabBar *)self;
    bar.backgroundColor = UIColor.clearColor;
    bar.backgroundImage = [UIImage new];
    bar.shadowImage = [UIImage new];

    for (UIView *view in bar.subviews) {
        NSString *className = NSStringFromClass(view.class).lowercaseString;
        if ([className isEqualToString:@"_uibarbbackground"] ||
            [className containsString:@"blur"]) {
            view.hidden = YES;
            view.alpha = 0.0;
        }
    }
}

%end

#pragma mark - Notifications / install

static void ZolaRefreshBubblesInView(UIView *root) {
    if (!root) {
        return;
    }

    for (UIView *subview in root.subviews) {
        if ([[NSStringFromClass(subview.class)
              lowercaseString] isEqualToString:@"altextmessagetableitemcell"]) {
            UICollectionViewCell *cell = (UICollectionViewCell *)subview;
            ZolaStyleBubblesInView(cell.contentView, cell);
        }

        ZolaRefreshBubblesInView(subview);
    }
}

static void ZolaRefreshChatBackgroundsInView(UIView *root) {
    if (!root) {
        return;
    }

    for (UIView *subview in root.subviews) {
        if ([[NSStringFromClass(subview.class)
              lowercaseString] isEqualToString:@"zxcollectionview"]) {
            ZolaApplyChatBackground(subview);
        }

        ZolaRefreshChatBackgroundsInView(subview);
    }
}

%ctor {
    NSBundle *bundle = [NSBundle mainBundle];

    if (![bundle.bundleIdentifier isEqualToString:@"com.vng.zalo"]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [ZolaThemeDocumentPickerDelegate shared];

        [[NSNotificationCenter defaultCenter]
            addObserverForName:@"ZolaThemeBackgroundChanged"
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *note) {
            for (UIWindow *window in ZolaAllWindows()) {
                ZolaRefreshChatBackgroundsInView(window);
            }
        }];

        [[NSNotificationCenter defaultCenter]
            addObserverForName:@"ZolaThemeBubbleChanged"
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *note) {
            for (UIWindow *window in ZolaAllWindows()) {
                ZolaRefreshBubblesInView(window);
            }
        }];

        ZolaThemeInstallSettingsHook();

        // ZolaCN may load its settings controller lazily. Retry briefly
        // after launch so the entry is installed regardless of load order.
        for (NSInteger i = 0; i < 40; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                          (int64_t)(i * 0.25 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                ZolaRetryZolaCNSettingsEntry();
            });
        }
    });
}
