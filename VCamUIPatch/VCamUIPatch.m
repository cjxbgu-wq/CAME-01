//
//  VCamUIPatch.m — vcam-v3 UI 补丁 (方案J 双体悬浮舱 定稿)
//  -------------------------------------------------------------
//  设计约束 (用户命令):
//   1) 禁止更改现有源码/二进制 — 本补丁为独立 dylib, 运行时注入, 零改动原包
//   2) 不改调用逻辑 — 全部按钮回调仍走原 SEL (switchVideoTapped 等),
//      状态读写(vc.plist/NSUserDefaults/VCamCore)原样
//   3) 仅补丁方式 — 通过 ObjC 运行时方法交换实现, 不依赖 substrate/ellekit
//      符号 (RootHide 环境兼容性最高), 唯一外部框架为 UIKit/CoreGraphics
//
//  方案J 布局 (屏幕占比按 390x844 基准等比缩放):
//    标题胶囊   58-94    宽238    「控制终端UI面板」
//    左主控舱   108-468  宽204    2x2图标键 + 迷你RTMP(开关+输入)
//    右状态舱   108-468  宽150    眼瞳状态徽章 + RTMP迷你开关
//    舱间光柱   216-360  宽6      荧光绿→蓝 呼吸
//    底部双键   486-542  高56     教程 / 关闭
//    主舱区 ≈38.7% 屏占比, 含底部条 ≈44% (不超屏幕一半)
//  悬浮球三态 (按原 label 文本自动切换):
//    OFF/关   -> 摄像机图标 (描边)
//    ON/开    -> 发光圆球 (辉光)
//    视频/图片 -> 狮子头 + 摄像机角标
//  按压反馈: 按下缩放0.9+变亮, 抬起弹性回弹 (全部按键)
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

// ---------------------------------------------------------------
// 标签常量: 全局 UILabel setText: 交换仅对本补丁创建的标签生效
// (以 tag 守卫, 避免影响系统其他 UILabel)
// ---------------------------------------------------------------
static const NSInteger VP_TAG_BALLLABEL = 0x6B61; // 悬浮球原文本标签(隐藏, 仅作状态信号)
static const NSInteger VP_TAG_BADGE     = 0x6B62; // 右舱状态徽章
static const NSInteger VP_TAG_BALLIMG   = 0x6B63; // 悬浮球图标视图
static const NSInteger VP_TAG_BALLRING  = 0x6B64; // 悬浮球呼吸光环

// 主题色 (方案J 撞色)
static UIColor *VPColorGreen(void)  { return [UIColor colorWithRed:0.24 green:1.00 blue:0.62 alpha:1]; }
static UIColor *VPColorBlue(void)   { return [UIColor colorWithRed:0.24 green:0.48 blue:1.00 alpha:1]; }
static UIColor *VPColorPink(void)   { return [UIColor colorWithRed:1.00 green:0.24 blue:0.62 alpha:1]; }
static UIColor *VPColorGold(void)   { return [UIColor colorWithRed:1.00 green:0.77 blue:0.24 alpha:1]; }
static UIColor *VPColorGlass(void)  { return [UIColor colorWithRed:0.063 green:0.102 blue:0.173 alpha:0.5]; }

// ---------------------------------------------------------------
// 说明: 目标类 (VCamSettingsViewController / VCamFloatingBall)
// 全程以 NSClassFromString + @selector + performSelector + 运行时
// ivar 访问 (object_getIvar) 操作, 编译期无需任何头文件/类别声明,
// 与"补丁方式、零源码依赖"约束一致。
// ---------------------------------------------------------------

// ---------------------------------------------------------------
// VPButton: 带按压反馈的图标按钮 (缩放 + 亮度)
// ---------------------------------------------------------------
@interface VPButton : UIButton
@end
@implementation VPButton
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    [UIView animateWithDuration:0.08 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.transform = CGAffineTransformMakeScale(0.9, 0.9);
        self.alpha = 0.85;
    } completion:nil];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    [UIView animateWithDuration:0.16 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0.8
                        options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.transform = CGAffineTransformIdentity;
        self.alpha = 1.0;
    } completion:nil];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    self.transform = CGAffineTransformIdentity;
    self.alpha = 1.0;
}
@end

// ---------------------------------------------------------------
// 图标绘制 (CoreGraphics 程序化, 随包零资源文件)
// 绘制尺寸固定为 3x (retina), 由调用方缩放
// ---------------------------------------------------------------
static UIImage *VPRenderIcon(CGSize size, void (^draw)(CGContextRef ctx)) {
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 3;
    UIGraphicsImageRenderer *ren = [[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt];
    return [ren imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        if (draw) draw(ctx.CGContext);
    }];
}

static UIImage *VPFilmIcon(UIColor *c) {
    return VPRenderIcon(CGSizeMake(48, 48), ^(CGContextRef ctx){
        CGContextSetStrokeColorWithColor(ctx, c.CGColor);
        CGContextSetFillColorWithColor(ctx, c.CGColor);
        CGContextSetLineWidth(ctx, 3);
        CGRect body = CGRectMake(5, 9, 38, 26);
        // 机身 + 中缝(媒体槽)
        CGPathRef p = CGPathCreateWithRoundedRect(body, 4, 4, NULL);
        CGContextAddPath(ctx, p); CGContextStrokePath(ctx);
        CGPathRelease(p);
        CGContextMoveToPoint(ctx, 19, 9); CGContextAddLineToPoint(ctx, 19, 35); CGContextStrokePath(ctx);
        // 左下角"正在播放"三角
        CGContextMoveToPoint(ctx, 28, 17); CGContextAddLineToPoint(ctx, 40, 23); CGContextAddLineToPoint(ctx, 28, 29);
        CGContextClosePath(ctx); CGContextFillPath(ctx);
    });
}

static UIImage *VPEyeIcon(UIColor *c) {
    return VPRenderIcon(CGSizeMake(48, 48), ^(CGContextRef ctx){
        CGContextSetStrokeColorWithColor(ctx, c.CGColor);
        CGContextSetFillColorWithColor(ctx, c.CGColor);
        CGContextSetLineWidth(ctx, 3);
        // 眼睑(贝塞尔杏仁形) + 虹膜 + 瞳孔
        CGMutablePathRef p = CGPathCreateMutable();
        CGPathMoveToPoint(p, NULL, 3, 24);
        CGPathAddCurveToPoint(p, NULL, 8.5, 15, 14, 10.5, 24, 10.5);
        CGPathAddCurveToPoint(p, NULL, 34, 10.5, 39.5, 15, 45, 24);
        CGPathAddCurveToPoint(p, NULL, 39.5, 33, 34, 37.5, 24, 37.5);
        CGPathAddCurveToPoint(p, NULL, 14, 37.5, 8.5, 33, 3, 24);
        CGPathCloseSubpath(p);
        CGContextAddPath(ctx, p); CGContextStrokePath(ctx);
        CGPathRelease(p);
        CGContextFillEllipseInRect(ctx, CGRectMake(17, 17, 14, 14));
    });
}

static UIImage *VPRestoreIcon(UIColor *c) {
    return VPRenderIcon(CGSizeMake(48, 48), ^(CGContextRef ctx){
        CGContextSetStrokeColorWithColor(ctx, c.CGColor);
        CGContextSetLineWidth(ctx, 3);
        CGContextSetLineCap(ctx, kCGLineCapRound);
        CGContextSetLineJoin(ctx, kCGLineJoinRound);
        // 恢复真机: 左向弧 + 箭头
        CGContextAddArc(ctx, 30, 24, 16, 0.35 * M_PI, 1.45 * M_PI, 0);
        CGContextStrokePath(ctx);
        CGContextMoveToPoint(ctx, 14, 8); CGContextAddLineToPoint(ctx, 14, 20); CGContextAddLineToPoint(ctx, 26, 20);
        CGContextStrokePath(ctx);
        CGContextMoveToPoint(ctx, 46, 40); CGContextAddLineToPoint(ctx, 38, 32); CGContextStrokePath(ctx);
    });
}

static UIImage *VPOrbitIcon(UIColor *c) {
    return VPRenderIcon(CGSizeMake(48, 48), ^(CGContextRef ctx){
        CGContextSetStrokeColorWithColor(ctx, c.CGColor);
        CGContextSetFillColorWithColor(ctx, c.CGColor);
        CGContextSetLineWidth(ctx, 3);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(15, 15, 18, 18));
        CGContextFillEllipseInRect(ctx, CGRectMake(21, 21, 6, 6));
        // 四向刻度(悬浮球开关语义)
        CGContextMoveToPoint(ctx, 24, 4);  CGContextAddLineToPoint(ctx, 24, 10);  CGContextStrokePath(ctx);
        CGContextMoveToPoint(ctx, 24, 38); CGContextAddLineToPoint(ctx, 24, 44);  CGContextStrokePath(ctx);
        CGContextMoveToPoint(ctx, 4, 24);  CGContextAddLineToPoint(ctx, 10, 24);  CGContextStrokePath(ctx);
        CGContextMoveToPoint(ctx, 38, 24); CGContextAddLineToPoint(ctx, 44, 24);  CGContextStrokePath(ctx);
    });
}

static UIImage *VPBookIcon(UIColor *c) {
    return VPRenderIcon(CGSizeMake(48, 48), ^(CGContextRef ctx){
        CGContextSetStrokeColorWithColor(ctx, c.CGColor);
        CGContextSetLineWidth(ctx, 3);
        CGContextSetLineJoin(ctx, kCGLineJoinRound);
        // 教程: 翻开的书
        CGPathRef p = CGPathCreateWithRoundedRect(CGRectMake(8, 8, 22, 30), 4, 4, NULL);
        CGContextAddPath(ctx, p); CGContextStrokePath(ctx); CGPathRelease(p);
        CGContextMoveToPoint(ctx, 30, 8); CGContextAddLineToPoint(ctx, 37, 10);
        CGContextAddLineToPoint(ctx, 40, 12); CGContextAddLineToPoint(ctx, 40, 38);
        CGContextAddLineToPoint(ctx, 30, 38); CGContextStrokePath(ctx);
        CGContextMoveToPoint(ctx, 30, 8); CGContextAddLineToPoint(ctx, 30, 38); CGContextStrokePath(ctx);
    });
}

static UIImage *VPXIcon(UIColor *c) {
    return VPRenderIcon(CGSizeMake(48, 48), ^(CGContextRef ctx){
        CGContextSetStrokeColorWithColor(ctx, c.CGColor);
        CGContextSetLineWidth(ctx, 3);
        CGContextSetLineCap(ctx, kCGLineCapRound);
        CGContextMoveToPoint(ctx, 13, 13); CGContextAddLineToPoint(ctx, 35, 35); CGContextStrokePath(ctx);
        CGContextMoveToPoint(ctx, 35, 13); CGContextAddLineToPoint(ctx, 13, 35); CGContextStrokePath(ctx);
    });
}

static UIImage *VPCameraIcon(UIColor *c) {
    return VPRenderIcon(CGSizeMake(48, 48), ^(CGContextRef ctx){
        CGContextSetStrokeColorWithColor(ctx, c.CGColor);
        CGContextSetFillColorWithColor(ctx, c.CGColor);
        CGContextSetLineWidth(ctx, 3);
        // 机身 + 顶部取景凸起 + 镜头
        CGPathRef p = CGPathCreateWithRoundedRect(CGRectMake(4, 13, 30, 21), 4, 4, NULL);
        CGContextAddPath(ctx, p); CGContextStrokePath(ctx); CGPathRelease(p);
        CGContextMoveToPoint(ctx, 14, 13); CGContextAddLineToPoint(ctx, 18, 7);
        CGContextAddLineToPoint(ctx, 28, 7); CGContextAddLineToPoint(ctx, 32, 13); CGContextStrokePath(ctx);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(12.5, 16.5, 13, 13));
        CGContextFillEllipseInRect(ctx, CGRectMake(16, 20, 6, 6));
    });
}

static UIImage *VPOrbIcon(void) {
    return VPRenderIcon(CGSizeMake(48, 48), ^(CGContextRef ctx){
        // 发光圆球: 白->青 径向渐变 + 高光点
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGFloat cols[8] = {1, 1, 1, 1,  0.62, 0.94, 1, 1};
        CGGradientRef g = CGGradientCreateWithColorComponents(cs, cols, NULL, 2);
        CGContextDrawRadialGradient(ctx, g, CGPointMake(20, 18), 2, CGPointMake(24, 24), 17,
                                    kCGGradientDrawsAfterEndLocation);
        CGGradientRelease(g); CGColorSpaceRelease(cs);
    });
}

static UIImage *VPLionIcon(void) {
    return VPRenderIcon(CGSizeMake(64, 64), ^(CGContextRef ctx){
        UIColor *mane = [UIColor colorWithRed:1.0 green:0.71 blue:0.18 alpha:1];
        UIColor *dark = [UIColor colorWithRed:0.13 green:0.08 blue:0.03 alpha:1];
        CGContextSetLineWidth(ctx, 2.2);
        CGContextSetLineCap(ctx, kCGLineCapRound);
        CGContextSetLineJoin(ctx, kCGLineJoinRound);
        // 鬃毛: 头 + 八根放射尖刺 (2 根对角"闪电"更醒目)
        CGContextSetFillColorWithColor(ctx, mane.CGColor);
        CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:1 green:0.82 blue:0.48 alpha:1].CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(15.5, 17.5, 33, 33));
        CGPoint spikes[4][2] = {{ {9, 16}, {5, 4} }, { {22, 9}, {22, 1} }, { {42, 9}, {42, 1} }, { {55, 16}, {59, 4} }};
        for (int i = 0; i < 4; i++) {
            CGContextMoveToPoint(ctx, spikes[i][0].x, spikes[i][0].y);
            CGContextAddLineToPoint(ctx, spikes[i][1].x, spikes[i][1].y);
            CGContextStrokePath(ctx);
        }
        // 面部
        CGContextSetFillColorWithColor(ctx, mane.CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(19, 22, 26, 26));
        // 双眼 + 鼻口
        CGContextSetFillColorWithColor(ctx, dark.CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(23.5, 30.5, 5, 5));
        CGContextFillEllipseInRect(ctx, CGRectMake(35.5, 30.5, 5, 5));
        CGContextSetStrokeColorWithColor(ctx, dark.CGColor);
        CGContextMoveToPoint(ctx, 28.5, 41.5);
        CGContextAddQuadCurveToPoint(ctx, 32, 45.5, 35.5, 41.5);
        CGContextStrokePath(ctx);
    });
}

// ---------------------------------------------------------------
// 运行时方法交换工具 (纯 ObjC, 无 substrate)
// 返回 YES 表示交换成功; 交换后原实现存于 outOrig 供调用
// ---------------------------------------------------------------
static BOOL VPSwizzle(Class cls, SEL sel, IMP newImp, IMP *outOrig) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;
    IMP orig = method_getImplementation(m);
    if (outOrig) *outOrig = orig;
    if (orig == newImp) return YES; // 幂等: 重复安装时跳过
    return class_addMethod(cls, sel, newImp, method_getTypeEncoding(m))
        ? class_replaceMethod(cls, sel, newImp, method_getTypeEncoding(m)) != NULL
        : method_setImplementation(m, newImp) == orig;
}

// 全局安装标志 (幂等)
static BOOL VPInstalled = NO;

// ---------------------------------------------------------------
// 悬浮球三态图标 (按原文本标签内容映射)
// ---------------------------------------------------------------
static UIImage *VPBallImageForText(NSString *text) {
    if (!text) return VPLionIcon();
    if ([text rangeOfString:@"OFF"].location != NSNotFound || [text rangeOfString:@"关"].location != NSNotFound)
        return VPCameraIcon(VPColorGreen());
    if ([text rangeOfString:@"ON"].location != NSNotFound || [text rangeOfString:@"开"].location != NSNotFound)
        return VPOrbIcon();
    return VPLionIcon(); // 视频/图片/初始 "VCam" 均显狮子头
}

static void VPUpdateBall(UIView *ball) {
    UIImageView *iv = (UIImageView *)[ball viewWithTag:VP_TAG_BALLIMG];
    UILabel *lb = (UILabel *)[ball viewWithTag:VP_TAG_BALLLABEL];
    if (!iv) return;
    iv.image = VPBallImageForText(lb.text);
}

// ---------------------------------------------------------------
// 悬浮球加工 (幂等): 金底+三态图标+呼吸光环+摄像机角标
// 标签尚未创建时返回, 由 setText: 迟到路径补装
// ---------------------------------------------------------------
static void VPBallEnsureStyled(UIView *ball) {
    // 已加工过 (有图标) 则跳过
    if ([ball viewWithTag:VP_TAG_BALLIMG]) return;
    UIView *label = nil;
    for (UIView *v in ball.subviews) {
        if ([v isKindOfClass:[UILabel class]]) { label = v; break; }
    }
    if (!label) return;
    label.tag = VP_TAG_BALLLABEL;
    label.hidden = YES; // 隐藏原文字, 仅保留 setText: 信号

    // 金底 + 辉光
    ball.backgroundColor = [UIColor colorWithRed:1.0 green:0.60 blue:0.18 alpha:1];
    ball.layer.shadowColor = VPColorGold().CGColor;
    ball.layer.shadowOpacity = 0.9f;
    ball.layer.shadowRadius = 10.0f;
    ball.layer.shadowOffset = CGSizeZero;

    // 图标视图
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectInset(ball.bounds, ball.bounds.size.width * 0.14, ball.bounds.size.width * 0.14)];
    iv.tag = VP_TAG_BALLIMG;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.image = VPBallImageForText(((UILabel *)label).text);
    [ball addSubview:iv];

    // 呼吸光环 (绿色, 持续透明度脉冲)
    UIView *ring = [[UIView alloc] initWithFrame:CGRectInset(ball.bounds, -9, -9)];
    ring.tag = VP_TAG_BALLRING;
    ring.layer.cornerRadius = ring.bounds.size.width / 2.0;
    ring.layer.borderWidth = 2.0;
    ring.layer.borderColor = VPColorGreen().CGColor;
    ring.userInteractionEnabled = NO;
    [ball addSubview:ring];
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue = @0.9; pulse.toValue = @0.25;
    pulse.duration = 1.6; pulse.autoreverses = YES; pulse.repeatCount = INFINITY;
    [ring.layer addAnimation:pulse forKey:@"vpPulse"];

    // 摄像机角标 (右下)
    UIImageView *badge = [[UIImageView alloc] initWithFrame:CGRectMake(ball.bounds.size.width - 26, ball.bounds.size.height - 26, 26, 26)];
    badge.image = VPCameraIcon(VPColorGreen());
    badge.backgroundColor = [UIColor colorWithWhite:0.11 alpha:0.9];
    badge.layer.cornerRadius = 13;
    badge.layer.borderWidth = 1.5;
    badge.layer.borderColor = VPColorGreen().CGColor;
    badge.contentMode = UIViewContentModeScaleAspectFit;
    badge.userInteractionEnabled = NO;
    [ball addSubview:badge];
}

// ---------------------------------------------------------------
// 悬浮球: 初始化后重绘 (标签未建时留给 setText: 迟到路径)
// ---------------------------------------------------------------
static void (*origFloatingBallInit)(id, SEL, CGRect) = NULL;
static void VPFloatingBallInit(id self, SEL _cmd, CGRect frame) {
    origFloatingBallInit(self, _cmd, frame);
    VPBallEnsureStyled((UIView *)self);
}

// ---------------------------------------------------------------
// 全局 UILabel setText: 交换
//  1) TG 链接文本 (t.me / taokk3) → 置空并隐藏 (不展示)
//  2) 悬浮球标签 (无论何时创建/赋值) → 标记+隐藏+三态刷新
// ---------------------------------------------------------------
static void (*origLabelSetText)(id, SEL, NSString *) = NULL;
static void VPLabelSetText(id self, SEL _cmd, NSString *text) {
    UIView *v = (UIView *)self;
    // 1) TG 链接过滤
    if (text.length) {
        NSString *low = [text lowercaseString];
        if ([low rangeOfString:@"taokk3"].location != NSNotFound ||
            [low rangeOfString:@"t.me"].location != NSNotFound) {
            origLabelSetText(self, _cmd, @"");
            v.hidden = YES;
            return;
        }
    }
    origLabelSetText(self, _cmd, text);
    // 2) 悬浮球标签: 迟到创建/赋值也能捕获
    UIView *ball = nil;
    if (v.tag == VP_TAG_BALLLABEL) {
        ball = v.superview;
    } else if ([v.superview isKindOfClass:NSClassFromString(@"VCamFloatingBall")]) {
        v.tag = VP_TAG_BALLLABEL;
        v.hidden = YES;
        ball = v.superview;
    }
    if (ball) {
        VPBallEnsureStyled(ball);
        if ([ball viewWithTag:VP_TAG_BALLIMG]) VPUpdateBall(ball);
    }
}

// ---------------------------------------------------------------
// 跳转拦截: TG 链接 (t.me / taokk3) 一律丢弃 — 按钮保留但点击无反应
// ---------------------------------------------------------------
static BOOL (*origOpenURL)(id, SEL, NSURL *, NSDictionary *, id) = NULL;
static BOOL VPOpenURL(id self, SEL _cmd, NSURL *url, NSDictionary *options, id completion) {
    if (url) {
        NSString *u = [[url absoluteString] lowercaseString];
        if ([u rangeOfString:@"taokk3"].location != NSNotFound ||
            [u rangeOfString:@"t.me"].location != NSNotFound) {
            if (completion) ((void (^)(BOOL))completion)(NO);
            return NO;
        }
    }
    return origOpenURL(self, _cmd, url, options, completion);
}

static BOOL (*origOpenURLLegacy)(id, SEL, NSURL *) = NULL;
static BOOL VPOpenURLLegacy(id self, SEL _cmd, NSURL *url) {
    if (url) {
        NSString *u = [[url absoluteString] lowercaseString];
        if ([u rangeOfString:@"taokk3"].location != NSNotFound ||
            [u rangeOfString:@"t.me"].location != NSNotFound) {
            return NO;
        }
    }
    return origOpenURLLegacy(self, _cmd, url);
}

// ---------------------------------------------------------------
// 状态徽章同步 (右舱眼瞳下方)
// ---------------------------------------------------------------
static void VPSetBadge(UIView *root, NSString *stateText) {
    UILabel *badge = (UILabel *)[root viewWithTag:VP_TAG_BADGE];
    if (!badge) return;
    BOOL on = [stateText rangeOfString:@"ON"].location != NSNotFound;
    badge.text = on ? @"ON" : @"OFF";
    badge.backgroundColor = on ? VPColorGreen() : [UIColor colorWithRed:1 green:0.36 blue:0.36 alpha:1];
}

// ---------------------------------------------------------------
// 面板重建 (方案J 双体悬浮舱)
// ---------------------------------------------------------------
static void VPBuildPanel(UIViewController *vc) {
    UIView *root = vc.view;
    // 幂等: 每次全量重建 (移除原面板与旧重建产物)
    for (UIView *v in [root.subviews copy]) [v removeFromSuperview];

    CGFloat W = root.bounds.size.width;
    CGFloat H = root.bounds.size.height;
    // 屏幕占比等比: 以 390 基准宽缩放 (任意机型均合理占比)
    CGFloat S = W / 390.0;

    // --- 标题胶囊 ---
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake((W - 238 * S) / 2, 58 * S, 238 * S, 36 * S)];
    title.text = @"控制终端UI面板";
    title.font = [UIFont boldSystemFontOfSize:15 * S];
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.layer.cornerRadius = 18 * S;
    title.layer.borderWidth = 1.5;
    title.layer.borderColor = VPColorGreen().CGColor;
    title.backgroundColor = [UIColor colorWithRed:0.24 green:1.0 blue:0.62 alpha:0.15];
    [root addSubview:title];

    // --- 舱间光柱 ---
    UIView *beam = [[UIView alloc] initWithFrame:CGRectMake(220 * S, 216 * S, 6 * S, 144 * S)];
    beam.layer.cornerRadius = 3 * S;
    beam.backgroundColor = VPColorGreen();
    beam.alpha = 0.85;
    [root addSubview:beam];
    CABasicAnimation *bp = [CABasicAnimation animationWithKeyPath:@"opacity"];
    bp.fromValue = @0.85; bp.toValue = @0.3;
    bp.duration = 1.4; bp.autoreverses = YES; bp.repeatCount = INFINITY;
    [beam.layer addAnimation:bp forKey:@"vpBeam"];

    // --- 左主控舱 ---
    UIView *podL = [[UIView alloc] initWithFrame:CGRectMake(14 * S, 108 * S, 204 * S, 360 * S)];
    podL.layer.cornerRadius = 28 * S;
    podL.layer.borderWidth = 1.5;
    podL.layer.borderColor = VPColorGreen().CGColor;
    podL.backgroundColor = VPColorGlass();
    podL.layer.shadowColor = [UIColor blackColor].CGColor;
    podL.layer.shadowOpacity = 0.4f;
    podL.layer.shadowOffset = CGSizeMake(0, 14 * S);
    podL.layer.shadowRadius = 40 * S;
    // 毛玻璃层 (透明要求)
    UIVisualEffectView *blurL = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blurL.frame = podL.bounds;
    blurL.layer.cornerRadius = 28 * S;
    blurL.layer.masksToBounds = YES;
    [podL addSubview:blurL];
    [root addSubview:podL];

    // 舱标题
    UILabel *podTitle = [[UILabel alloc] initWithFrame:CGRectMake(16 * S, 18 * S, 120 * S, 14 * S)];
    podTitle.text = @"主控舱";
    podTitle.font = [UIFont boldSystemFontOfSize:10 * S];
    podTitle.textColor = VPColorGreen();
    [podL addSubview:podTitle];

    // 2x2 图标键 (媒体/状态/恢复相机/悬浮球)
    CGFloat bw = (204 * S - 32 * S - 12 * S) / 2;
    CGFloat bh = 100 * S;
    struct { SEL action; UIColor *color; UIImage *(*icon)(UIColor *); } keys[4] = {
        { @selector(switchVideoTapped),      VPColorGreen(), VPFilmIcon },
        { @selector(toggleReplacementTapped), VPColorBlue(),  VPEyeIcon },
        { @selector(restoreCameraTapped),    VPColorPink(),  VPRestoreIcon },
        { @selector(toggleFloatingBallTapped), VPColorGold(), VPOrbitIcon },
    };
    for (int i = 0; i < 4; i++) {
        int col = i % 2, row = i / 2;
        CGRect f = CGRectMake(16 * S + col * (bw + 12 * S), 44 * S + row * (bh + 12 * S), bw, bh);
        VPButton *b = [VPButton buttonWithType:UIButtonTypeCustom];
        b.frame = f;
        b.layer.cornerRadius = 20 * S;
        b.backgroundColor = keys[i].color;
        b.layer.borderWidth = 1.5;
        b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.4].CGColor;
        [b setImage:keys[i].icon([UIColor whiteColor]) forState:UIControlStateNormal];
        b.imageView.contentMode = UIViewContentModeScaleAspectFit;
        b.imageEdgeInsets = UIEdgeInsetsMake(14 * S, 14 * S, 14 * S, 14 * S);
        // 逻辑不变: 回调仍走原 SEL
        [b addTarget:vc action:keys[i].action forControlEvents:UIControlEventTouchUpInside];
        [podL addSubview:b];
    }

    // 迷你 RTMP: 开关 + 输入 (镜像到原控件后走原方法)
    UISwitch *miniSw = [[UISwitch alloc] initWithFrame:CGRectMake(16 * S, 268 * S, 51 * S, 31 * S)];
    miniSw.onTintColor = VPColorGreen();
    miniSw.transform = CGAffineTransformMakeScale(S, S);
    [miniSw addTarget:vc action:@selector(vpMiniSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [podL addSubview:miniSw];

    UITextField *miniTf = [[UITextField alloc] initWithFrame:CGRectMake(80 * S, 272 * S, 108 * S, 24 * S)];
    miniTf.tag = VP_TAG_BALLLABEL + 10; // 复用信号区无冲突: 独立标签
    miniTf.font = [UIFont systemFontOfSize:9 * S];
    miniTf.textColor = [UIColor colorWithRed:0.81 green:0.88 blue:1 alpha:1];
    miniTf.backgroundColor = [UIColor colorWithRed:0.24 green:0.48 blue:1 alpha:0.15];
    miniTf.layer.cornerRadius = 8 * S;
    miniTf.layer.borderWidth = 1;
    miniTf.layer.borderColor = VPColorBlue().CGColor;
    miniTf.keyboardType = UIKeyboardTypeURL;
    miniTf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    miniTf.returnKeyType = UIReturnKeyDone;
    miniTf.placeholder = @"rtmp://...";
    miniTf.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"rtmp://..." attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.35]}];
    [miniTf addTarget:vc action:@selector(vpMiniTfEnd:) forControlEvents:UIControlEventEditingDidEnd];
    [miniTf addTarget:vc action:@selector(vpMiniTfEnd:) forControlEvents:UIControlEventEditingDidEndOnExit];
    [podL addSubview:miniTf];

    // --- 右状态舱 ---
    UIView *podR = [[UIView alloc] initWithFrame:CGRectMake(W - 14 * S - 150 * S, 108 * S, 150 * S, 360 * S)];
    podR.layer.cornerRadius = 75 * S;
    podR.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    podR.layer.cornerRadius = 26 * S;
    podR.layer.borderWidth = 1.5;
    podR.layer.borderColor = VPColorBlue().CGColor;
    podR.backgroundColor = VPColorGlass();
    podR.layer.shadowColor = [UIColor blackColor].CGColor;
    podR.layer.shadowOpacity = 0.4f;
    podR.layer.shadowOffset = CGSizeMake(0, 14 * S);
    podR.layer.shadowRadius = 40 * S;
    UIVisualEffectView *blurR = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blurR.frame = podR.bounds;
    blurR.layer.cornerRadius = 26 * S;
    blurR.layer.masksToBounds = YES;
    [podR addSubview:blurR];
    [root addSubview:podR];

    UILabel *podTitleR = [[UILabel alloc] initWithFrame:CGRectMake(0, 20 * S, 150 * S, 14 * S)];
    podTitleR.text = @"状态";
    podTitleR.font = [UIFont boldSystemFontOfSize:10 * S];
    podTitleR.textColor = VPColorBlue();
    podTitleR.textAlignment = NSTextAlignmentCenter;
    [podR addSubview:podTitleR];

    // 眼瞳 (状态主视觉)
    UIView *eye = [[UIView alloc] initWithFrame:CGRectMake((150 * S - 84 * S) / 2, 44 * S, 84 * S, 84 * S)];
    eye.layer.cornerRadius = 42 * S;
    eye.backgroundColor = VPColorBlue();
    eye.layer.borderWidth = 2;
    eye.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.7].CGColor;
    eye.layer.shadowColor = VPColorBlue().CGColor;
    eye.layer.shadowOpacity = 0.9f;
    eye.layer.shadowRadius = 20 * S;
    [podR addSubview:eye];
    UIImageView *eyeIv = [[UIImageView alloc] initWithFrame:CGRectInset(eye.bounds, 20 * S, 20 * S)];
    eyeIv.image = VPEyeIcon([UIColor whiteColor]);
    eyeIv.contentMode = UIViewContentModeScaleAspectFit;
    [eye addSubview:eyeIv];

    // 状态徽章
    UILabel *badge = [[UILabel alloc] initWithFrame:CGRectMake((150 * S - 60 * S) / 2, 140 * S, 60 * S, 20 * S)];
    badge.tag = VP_TAG_BADGE;
    badge.font = [UIFont boldSystemFontOfSize:11 * S];
    badge.textColor = [UIColor colorWithWhite:0.06 alpha:1];
    badge.textAlignment = NSTextAlignmentCenter;
    badge.layer.cornerRadius = 10 * S;
    badge.layer.masksToBounds = YES;
    [podR addSubview:badge];

    // RTMP 迷你开关
    UILabel *rtmpLab = [[UILabel alloc] initWithFrame:CGRectMake(0, 176 * S, 150 * S, 12 * S)];
    rtmpLab.text = @"RTMP";
    rtmpLab.font = [UIFont systemFontOfSize:9 * S];
    rtmpLab.textColor = VPColorGreen();
    rtmpLab.textAlignment = NSTextAlignmentCenter;
    [podR addSubview:rtmpLab];
    UISwitch *rtmpSw = [[UISwitch alloc] initWithFrame:CGRectMake((150 * S - 51 * S) / 2, 194 * S, 51 * S, 31 * S)];
    rtmpSw.onTintColor = VPColorBlue();
    rtmpSw.transform = CGAffineTransformMakeScale(S, S);
    [rtmpSw addTarget:vc action:@selector(vpRtmpSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [podR addSubview:rtmpSw];

    // --- 底部双键: 教程 / 关闭 ---
    CGFloat footY = 486 * S;
    CGFloat footH = 56 * S;
    CGFloat footW = (W - 28 * S - 14 * S) / 2;
    VPButton *tut = [VPButton buttonWithType:UIButtonTypeCustom];
    tut.frame = CGRectMake(14 * S, footY, footW, footH);
    tut.layer.cornerRadius = 20 * S;
    tut.backgroundColor = VPColorBlue();
    tut.layer.borderWidth = 1.5;
    tut.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.4].CGColor;
    [tut setImage:VPBookIcon([UIColor whiteColor]) forState:UIControlStateNormal];
    tut.imageEdgeInsets = UIEdgeInsetsMake(14 * S, 14 * S, 14 * S, 14 * S);
    [tut addTarget:vc action:@selector(openTutorial) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:tut];

    VPButton *close = [VPButton buttonWithType:UIButtonTypeCustom];
    close.frame = CGRectMake(14 * S + footW + 14 * S, footY, footW, footH);
    close.layer.cornerRadius = 20 * S;
    close.backgroundColor = VPColorPink();
    close.layer.borderWidth = 1.5;
    close.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.4].CGColor;
    [close setImage:VPXIcon([UIColor whiteColor]) forState:UIControlStateNormal];
    close.imageEdgeInsets = UIEdgeInsetsMake(14 * S, 14 * S, 14 * S, 14 * S);
    [close addTarget:vc action:@selector(dismissPanel) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:close];

    // 初始徽章同步
    VPSetBadge(root, @"OFF");
    [vc performSelector:@selector(updateStatusLabel) withObject:nil afterDelay:0.1];
}

// ---------------------------------------------------------------
// 交换实现
// ---------------------------------------------------------------
static void (*origViewDidLoad)(id, SEL) = NULL;
static void VPViewDidLoad(id self, SEL _cmd) {
    origViewDidLoad(self, _cmd);
    VPBuildPanel(self); // 原逻辑先执行(状态文件/开关初始化), 再整面重建
}

static void (*origUpdateStatusLabel)(id, SEL) = NULL;
static void VPUpdateStatusLabel(id self, SEL _cmd) {
    origUpdateStatusLabel(self, _cmd);
    // 从原 _statusLabel.text 读取状态 (原逻辑的单一事实来源), 仅同步显示
    Ivar iv = class_getInstanceVariable(object_getClass(self), "_statusLabel");
    UILabel *sl = iv ? object_getIvar(self, iv) : nil;
    if (sl && sl.text) VPSetBadge(((UIViewController *)self).view, sl.text);
    // 同步悬浮球 (替换状态文本含 ON/OFF)
    UIView *ball = [[UIApplication sharedApplication].windows.firstObject viewWithTag:VP_TAG_BALLIMG];
    if (ball) VPUpdateBall(ball.superview);
}

// ---------------------------------------------------------------
// 呈现宿主修复: 面板 VC 挂载于自定义悬浮窗 (非窗口控制器层级),
// iOS 16+ 从其 self 上 present 会被系统丢弃 (view is not in the
// window hierarchy) → 选择器/弹窗改为从最高层可见窗口的顶层 VC
// 呈现; 委托/回调仍由面板 VC 处理, 内容与原件完全一致。
// ---------------------------------------------------------------
static UIViewController *VPTopmostPresentingVC(void) {
    NSArray *wins = [[UIApplication sharedApplication] windows];
    NSArray *sorted = [wins sortedArrayUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        return a.windowLevel > b.windowLevel ? NSOrderedAscending : NSOrderedDescending;
    }];
    for (UIWindow *w in sorted) {
        if (w.hidden || !w.rootViewController) continue;
        UIViewController *top = w.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        return top;
    }
    return nil;
}

// 切换视频: 与原件同构 (同款选择器/类型/委托), 仅呈现宿主改为顶层 VC
static void (*origSwitchVideo)(id, SEL) = NULL;
static void VPSwitchVideo(id self, SEL _cmd) {
    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[@"public.image", @"public.movie"];
    picker.delegate = self; // 选片回调仍走面板 VC 的原方法
    UIViewController *host = VPTopmostPresentingVC();
    if (host) [host presentViewController:picker animated:YES completion:nil];
}

// 关闭: 面板 VC 处于正规 presented 层级 → 原样 dismiss; 否则直接摘除视图
static void (*origDismissPanel)(id, SEL) = NULL;
static void VPDismissPanel(id self, SEL _cmd) {
    UIViewController *vc = (UIViewController *)self;
    if (!vc.presentingViewController && vc.view.superview) {
        [vc.view removeFromSuperview];
        return;
    }
    if (origDismissPanel) origDismissPanel(self, _cmd);
}

// 弹窗 (教程/提示): 同因修复 — 从顶层 VC 呈现, 标题统一品牌
static void (*origShowAlert)(id, SEL, NSString *) = NULL;
static void VPShowAlert(id self, SEL _cmd, NSString *msg) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"控制终端UI面板"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *host = VPTopmostPresentingVC();
    if (host) {
        [host presentViewController:alert animated:YES completion:nil];
    } else if (origShowAlert) {
        origShowAlert(self, _cmd, msg);
    }
}

// ---------------------------------------------------------------
// RTMP 镜像处理: 写回原控件后调用原方法 (逻辑零改动)
// ---------------------------------------------------------------
static Ivar VPIvar(Class cls, const char *name) {
    return class_getInstanceVariable(cls, name);
}
static void VPMirrorRtmpState(UIViewController *vc, BOOL on, NSString *url) {
    Class cls = object_getClass(vc);
    Ivar swIv = VPIvar(cls, "_rtmpSwitch");
    Ivar tfIv = VPIvar(cls, "_rtmpTextField");
    if (swIv) {
        UISwitch *origSw = object_getIvar(vc, swIv);
        if (origSw) {
            origSw.on = on;
            [vc performSelector:@selector(rtmpSwitchChanged:) withObject:origSw];
        }
    }
    if (tfIv && url) {
        UITextField *origTf = object_getIvar(vc, tfIv);
        if (origTf) {
            origTf.text = url;
            [vc performSelector:@selector(saveRtmpUrl)];
        }
    }
}

// 仅镜像文本(编辑结束): 不动开关状态, 避免编辑地址把拉流开关误关
static void VPMirrorRtmpText(UIViewController *vc, NSString *url) {
    Class cls = object_getClass(vc);
    Ivar tfIv = VPIvar(cls, "_rtmpTextField");
    if (!tfIv || !url) return;
    UITextField *origTf = object_getIvar(vc, tfIv);
    if (origTf) {
        origTf.text = url;
        [vc performSelector:@selector(saveRtmpUrl)];
    }
}

// ---------------------------------------------------------------
// 补丁附加动作 (运行时注册到 VCamSettingsViewController, 无源码改动)
// ---------------------------------------------------------------
static void vpMiniSwitchChanged(id self, SEL _cmd, id sender) {
    UISwitch *sw = sender;
    VPMirrorRtmpState((UIViewController *)self, sw.isOn, nil);
}
static void vpMiniTfEnd(id self, SEL _cmd, id sender) {
    UITextField *tf = sender;
    VPMirrorRtmpText((UIViewController *)self, tf.text);
}
static void vpRtmpSwitchChanged(id self, SEL _cmd, id sender) {
    UISwitch *sw = sender;
    VPMirrorRtmpState((UIViewController *)self, sw.isOn, nil);
}

// ---------------------------------------------------------------
// 安装 (幂等 + 延迟重试: 目标类可能晚于本 dylib 加载)
// ---------------------------------------------------------------
static void VPInstallSwizzles(void) {
    if (VPInstalled) return;

    Class settings = NSClassFromString(@"VCamSettingsViewController");
    Class ball = NSClassFromString(@"VCamFloatingBall");
    if (!settings || !ball) return; // 类未加载, 由重试调度补装

    VPSwizzle(settings, @selector(viewDidLoad), (IMP)VPViewDidLoad, (IMP *)&origViewDidLoad);
    VPSwizzle(settings, @selector(updateStatusLabel), (IMP)VPUpdateStatusLabel, (IMP *)&origUpdateStatusLabel);
    VPSwizzle(settings, @selector(showAlertWithMessage:), (IMP)VPShowAlert, (IMP *)&origShowAlert);
    VPSwizzle(settings, @selector(switchVideoTapped), (IMP)VPSwitchVideo, (IMP *)&origSwitchVideo);
    VPSwizzle(settings, @selector(dismissPanel), (IMP)VPDismissPanel, (IMP *)&origDismissPanel);
    VPSwizzle(ball, @selector(initWithFrame:), (IMP)VPFloatingBallInit, (IMP *)&origFloatingBallInit);
    VPSwizzle([UILabel class], @selector(setText:), (IMP)VPLabelSetText, (IMP *)&origLabelSetText);
    // TG 跳转拦截: 按钮保留, 点击无反应
    VPSwizzle([UIApplication class], @selector(openURL:options:completionHandler:), (IMP)VPOpenURL, (IMP *)&origOpenURL);
    VPSwizzle([UIApplication class], @selector(openURL:), (IMP)VPOpenURLLegacy, (IMP *)&origOpenURLLegacy);

    // 附加 RTMP 镜像动作 (仅本补丁的开关/输入框使用)
    class_addMethod(settings, @selector(vpMiniSwitchChanged:), (IMP)vpMiniSwitchChanged, "v@:@");
    class_addMethod(settings, @selector(vpMiniTfEnd:), (IMP)vpMiniTfEnd, "v@:@");
    class_addMethod(settings, @selector(vpRtmpSwitchChanged:), (IMP)vpRtmpSwitchChanged, "v@:@");

    VPInstalled = YES;
}

// dylib 构造: 立即尝试 + 0.5/2/5s 重试 (覆盖类加载顺序差异)
__attribute__((constructor))
static void VPPatchInit(void) {
    VPInstallSwizzles();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        VPInstallSwizzles();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            VPInstallSwizzles();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                VPInstallSwizzles();
            });
        });
    });
}