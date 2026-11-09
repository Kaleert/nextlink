# NextLink NL

Approved black-on-white NL avatar generated with the built-in image generation tool.
Prompt: refine the connected NL monogram into precise bold rounded sans-serif lettering inspired by Nunito ExtraBold, with a shared stem, consistent strokes and a pure white background.

`nextlink-nl.png` is the approved source. Android legacy launcher PNGs are resized from it; adaptive icons use the same art on white. The corresponding white vector silhouette is used by notifications, the Quick Settings tile and Android themed icons. The small notification silhouette is enlarged inside its viewport for readability.

Notifications use only the small `ic_notification_nl` alpha mask. Existing posted notifications are migrated on launch; large avatar overrides are removed to preserve the original layout. Launcher artwork is managed separately.

MIUI compatibility: the collapsed row also receives `miui.appIcon` from the current launcher drawable, rendered as an Icon bitmap. This is separate from `largeIcon` and does not alter notification content or layout. Reference implementation: https://github.com/fankes/MIUINativeNotifyIcon/blob/master/app/src/main/java/com/fankes/miui/notify/utils/tool/IconAdaptationTool.kt .
