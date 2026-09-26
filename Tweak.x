#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static char kZPInstalledKey;

static UIViewController *ZPTopViewController(UIViewController *vc) {
    UIViewController *candidate = vc;

    while (candidate) {
        UIViewController *next = nil;

        if (candidate.presentedViewController &&
            !candidate.presentedViewController.isBeingDismissed) {
            next = candidate.presentedViewController;
        } else if ([candidate isKindOfClass:[UINavigationController class]]) {
            next = [(UINavigationController *)candidate visibleViewController];
        } else if ([candidate isKindOfClass:[UITabBarController class]]) {
            next = [(UITabBarController *)candidate selectedViewController];
        }

        if (!next || next == candidate) {
            break;
        }

        candidate = next;
    }

    return candidate;
}

static void ZPTriggerDump(UIWindow *window) {
    if (!window) {
        return;
    }

    // Resolve private UIKit debugging API dynamically.
    SEL selector = sel_registerName("recursiveDescription");

    if (![window respondsToSelector:selector]) {
        return;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSString *dump = [window performSelector:selector];
#pragma clang diagnostic pop

    if (![dump isKindOfClass:[NSString class]]) {
        dump = @"<recursiveDescription returned non-NSString>";
    }

    NSArray<NSURL *> *documentURLs =
        [[NSFileManager defaultManager]
            URLsForDirectory:NSDocumentDirectory
            inDomains:NSUserDomainMask];

    NSURL *documentsURL = documentURLs.firstObject;

    if (!documentsURL) {
        return;
    }

    NSURL *outputURL =
        [documentsURL URLByAppendingPathComponent:@"Zalo_UI_Dump.txt"];

    NSError *error = nil;

    BOOL success =
        [dump writeToURL:outputURL
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:&error];

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top =
            ZPTopViewController(window.rootViewController);

        if (!top) {
            return;
        }

        NSString *message = success
            ? @"Probe 抓取成功"
            : (error.localizedDescription ?: @"无法写入 Zalo_UI_Dump.txt");

        UIAlertController *alert =
            [UIAlertController
                alertControllerWithTitle:@"Zalo Probe"
                                  message:message
                           preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:
            [UIAlertAction
                actionWithTitle:@"确定"
                          style:UIAlertActionStyleDefault
                        handler:nil]];

        [top presentViewController:alert
                          animated:YES
                        completion:nil];
    });
}

static void ZPInstallGesture(UIWindow *window) {
    if (!window) {
        return;
    }

    if (objc_getAssociatedObject(window, &kZPInstalledKey)) {
        return;
    }

    UILongPressGestureRecognizer *gesture =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:window
                    action:@selector(zp_handleLongPress:)];

    gesture.minimumPressDuration = 2.0;
    gesture.numberOfTouchesRequired = 2;
    gesture.cancelsTouchesInView = NO;

    objc_setAssociatedObject(window,
                             &kZPInstalledKey,
                             gesture,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [window addGestureRecognizer:gesture];
}

%hook UIWindow

- (void)becomeKeyWindow {
    %orig;

    UIWindow *window = self;

    dispatch_async(dispatch_get_main_queue(), ^{
        ZPInstallGesture(window);
    });
}

%new
- (void)zp_handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }

    ZPTriggerDump((UIWindow *)gesture.view);
}

%end

%ctor {
    NSBundle *bundle = [NSBundle mainBundle];

    // Safety guard: this dylib is intended for Zalo only.
    if (![bundle.bundleIdentifier isEqualToString:@"com.vng.zalo"]) {
        return;
    }
}
