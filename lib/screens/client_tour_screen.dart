import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/localization/app_localizations.dart';
import '../shared/widgets/tour_anchor.dart';
import 'profiles_screen.dart';
import 'subscriptions_screen.dart';
import 'settings_screen.dart';

const _steps = <({String target, String scene, String title, String body})>[
  (
    target: 'home_map_canvas',
    scene: 'home',
    title: 'Серверы на глобусе',
    body: 'Вращайте глобус и выбирайте серверы на карте.',
  ),
  (
    target: 'widget_globe_controls_22',
    scene: 'home',
    title: 'Цепочки прямо на карте',
    body: 'Создавайте маршруты из нескольких серверов прямо на глобусе.',
  ),
  (
    target: 'widget_globe_controls_21',
    scene: 'home',
    title: 'Сохранённые цепочки',
    body: 'Здесь находятся ваши готовые цепочки серверов.',
  ),
  (
    target: 'widget_globe_controls_20',
    scene: 'home',
    title: 'Автовыбор сервера',
    body: 'Авто из подписок выбирает сервер из доступных конфигураций. Кнопка появляется при наличии подходящих подписок.',
  ),
  (
    target: 'home_ping',
    scene: 'home',
    title: 'Проверка пинга',
    body: 'Нажмите на задержку, чтобы повторно проверить выбранный сервер. Меньше мс — обычно быстрее отклик.',
  ),
  (
    target: 'home_traffic',
    scene: 'home',
    title: 'Просмотр трафика',
    body: 'Нажмите на плашку трафика, чтобы открыть статистику использования VPN.',
  ),
  (
    target: 'home_ip_details',
    scene: 'home',
    title: 'Ваш IP-адрес',
    body: 'Нажмите на IP, чтобы увидеть адрес и сведения о его расположении.',
  ),
  (
    target: 'widget_main_22',
    scene: 'home',
    title: 'Профили и автоматизация',
    body:
        'Эта кнопка открывает профили с условиями автоматического подключения.',
  ),
  (
    target: 'widget_profiles_screen_9',
    scene: 'profiles',
    title: 'Добавить профиль',
    body: 'Вот кнопка «+» для создания профиля. Нажмите её после обучения, задайте условия и включите профиль.',
  ),
  (
    target: 'home_subscriptions_button',
    scene: 'home',
    title: 'Подписки',
    body: 'Здесь находятся серверы из подписок, их обновление и управление.',
  ),
  (
    target: 'widget_subscriptions_screen_49',
    scene: 'subscriptions',
    title: 'Добавить подписку',
    body: 'Нажмите «+», чтобы импортировать ссылку, файл, буфер обмена или QR-код.',
  ),
  (
    target: 'home_rules_button',
    scene: 'home',
    title: 'Правила маршрутизации',
    body: 'Настройте, какие приложения и адреса используют VPN.',
  ),
  (
    target: 'home_apps_button',
    scene: 'home',
    title: 'Приложения',
    body: 'Управляйте настройками VPN для отдельных приложений.',
  ),
  (
    target: 'home_power_button',
    scene: 'home',
    title: 'Первое подключение',
    body: 'Выберите сервер и нажмите эту кнопку для подключения. В обучении VPN не запускается.',
  ),
  (
    target: 'home_settings_button',
    scene: 'home',
    title: 'Свои темы оформления',
    body: 'В настройках откройте «Интерфейс» → «Тема». Там можно выбрать готовую тему, создать свою и отредактировать оформление.',
  ),
  (
    target: 'home_settings_button',
    scene: 'home',
    title: 'Настройте под себя',
    body: 'Темы, диагностика, ядра и другие настройки находятся здесь.',
  ),
];

class ClientTour {
  static const steps = _steps;
  static const completedKey = 'client_coach_completed_v4';
  static const progressKey = 'client_coach_step_v4';
  static bool _open = false;
  static Future<void> maybeShow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted ||
        prefs.getBool(completedKey) == true ||
        ModalRoute.of(context)?.isCurrent == false)
      return;
    await show(context, start: prefs.getInt(progressKey) ?? 0);
  }

  static Future<void> show(
    BuildContext context, {
    int start = 0,
    Widget Function(String)? sceneBuilder,
  }) async {
    debugPrint('TOUR show open=$_open mounted=${context.mounted}');
    if (_open || !context.mounted) return;
    _open = true;
    final navigator = Navigator.of(context, rootNavigator: true);
    final overlay = navigator.overlay!;
    navigator.popUntil((r) => r.isFirst);
    final done = Completer<void>();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) {
        debugPrint('TOUR build entry');
        return _CoachOverlay(
          start: start,
          navigator: navigator,
          sceneBuilder: sceneBuilder,
          raise: () {
            // OverlayEntry уже находится поверх маршрутов при первоначальной вставке.
          },
          close: () {
            debugPrint('TOUR close');
            entry.remove();
            entry.dispose();
            if (!done.isCompleted) done.complete();
          },
        );
      },
    );
    overlay.insert(entry);
    debugPrint('TOUR inserted mounted=${entry.mounted}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint(
        'TOUR after frame mounted=${entry.mounted}, navigator=${navigator.mounted}',
      );
    });
    try {
      await done.future;
    } finally {
      _open = false;
    }
  }
}

class _CoachOverlay extends StatefulWidget {
  final int start;
  final NavigatorState navigator;
  final Widget Function(String)? sceneBuilder;
  final VoidCallback raise, close;
  const _CoachOverlay({
    required this.start,
    required this.navigator,
    required this.raise,
    required this.close,
    this.sceneBuilder,
  });
  @override
  State<_CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<_CoachOverlay>
    with SingleTickerProviderStateMixin {
  late int step;
  String scene = 'home';
  bool busy = false;
  Rect? target;
  late final AnimationController pulse;
  Timer? geometryTimer;
  @override
  void initState() {
    super.initState();
    step = widget.start.clamp(0, _steps.length - 1);
    pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) go(step);
    });
    geometryTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => measure(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      pulse.stop();
      pulse.value = .5;
    } else if (!pulse.isAnimating)
      pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    geometryTimer?.cancel();
    pulse.dispose();
    super.dispose();
  }

  void measure() {
    if (!mounted) return;
    var rect = TourAnchor.rect(_steps[step].target);
    final size = MediaQuery.sizeOf(context);
    if (rect != null && _steps[step].target == 'home_map_canvas') {
      rect = Rect.fromCenter(
        center: Offset(rect.center.dx, rect.top + rect.height * .35),
        width: size.width * .62,
        height: size.height * .25,
      );
    }
    rect = rect?.inflate(8).intersect(Offset.zero & size);
    if (rect?.isEmpty == true) rect = null;
    if (rect != target) setState(() => target = rect);
  }

  Future<void> go(int index) async {
    if (busy || !mounted) return;
    setState(() {
      busy = true;
      target = null;
    });
    if (index >= _steps.length) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(ClientTour.completedKey, true);
        await prefs.remove(ClientTour.progressKey);
      } catch (_) {
        debugPrint('Could not save client tour progress');
      }
      if (!mounted) return;
      widget.navigator.popUntil((r) => r.isFirst);
      widget.close();
      return;
    }
    final nextScene = _steps[index].scene;
    if (nextScene != scene) {
      widget.navigator.popUntil((r) => r.isFirst);
      scene = nextScene;
      if (scene != 'home') {
        final page =
            widget.sceneBuilder?.call(scene) ??
            (scene == 'profiles'
                ? const ProfilesScreen()
                : const SubscriptionsScreen());
        unawaited(
          widget.navigator.push(MaterialPageRoute<void>(builder: (_) => page)),
        );
      }
    }
    try {
      await (await SharedPreferences.getInstance()).setInt(
        ClientTour.progressKey,
        index,
      );
    } catch (_) {
      debugPrint('Could not save client tour progress');
    }
    if (!mounted) return;
    setState(() {
      step = index;
      busy = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.raise();
        measure();
      }
    });
  }

  void advance() {
    if (busy) return;
    if (step == _steps.length - 1) {
      final navigator = widget.navigator;
      go(_steps.length).then((_) {
        if (navigator.mounted)
          navigator.push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          );
      });
    } else {
      go(step + 1);
    }
  }

  String t(String text) => AppLocalizations.text(context, text);
  @override
  Widget build(BuildContext context) {
    debugPrint('TOUR overlay build step=$step');
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final media = MediaQuery.of(context);
    final item = _steps[step];
    final size = media.size;
    final rect = target;
    // Keep the card in the larger free area so it never covers the control it
    // is describing.
    final topInset = media.padding.top + 12;
    final bottomInset = media.padding.bottom + 12;
    final topSpace = rect == null ? size.height * .55 : rect.top - topInset;
    final bottomSpace = rect == null
        ? size.height * .55
        : size.height - rect.bottom - bottomInset;
    final placeAbove = topSpace >= bottomSpace;
    final cardHeight = (placeAbove ? topSpace : bottomSpace).clamp(
      120.0,
      size.height * .62,
    );
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Only the globe hole passes real gestures through. Other highlighted
          // controls advance the guided flow, never enabling VPN or changing data.
          Positioned.fill(
            child: _HoleBarrier(hole: step == 0 && !busy ? target : null),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _Spotlight(target, accent, pulse)),
            ),
          ),
          if (target != null && step != 0)
            Positioned.fromRect(
              rect: target!,
              child: GestureDetector(
                key: ValueKey('coach-target-${item.target}'),
                behavior: HitTestBehavior.opaque,
                onTap: advance,
              ),
            ),
          Align(
            alignment: placeAbove
                ? Alignment.topCenter
                : Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                placeAbove ? topInset : media.padding.top + 12,
                16,
                placeAbove ? media.padding.bottom + 12 : bottomInset,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 460,
                  maxHeight: cardHeight,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      key: const ValueKey('tour-card'),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(alpha: .88),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: accent.withValues(alpha: .4)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Flexible(
                            fit: FlexFit.loose,
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: (step + 1) / _steps.length,
                                      minHeight: 4,
                                      backgroundColor: accent.withValues(
                                        alpha: .18,
                                      ),
                                      valueColor: AlwaysStoppedAnimation(
                                        accent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Text(
                                        '${step + 1} / ${_steps.length}',
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(color: accent),
                                      ),
                                      const Spacer(),
                                      Flexible(
                                        child: TextButton(
                                          key: const ValueKey('tour-skip-all'),
                                          onPressed: busy
                                              ? null
                                              : () => go(_steps.length),
                                          child: Text(t('Пропустить обучение')),
                                        ),
                                      ),
                                    ],
                                  ),
                                  AnimatedSwitcher(
                                    duration:
                                        MediaQuery.disableAnimationsOf(context)
                                        ? Duration.zero
                                        : const Duration(milliseconds: 180),
                                    child: Align(
                                      key: ValueKey(step),
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        t(item.title),
                                        key: const ValueKey('tour-title'),
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    t(item.body),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      height: 1.4,
                                    ),
                                  ),
                                  if (target == null && !busy)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        t(
                                          'Этот элемент скрыт темой или недоступен. Можно пропустить шаг.',
                                        ),
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              IconButton(
                                key: const ValueKey('tour-back'),
                                tooltip: t('Назад'),
                                onPressed: step > 0 && !busy
                                    ? () => go(step - 1)
                                    : null,
                                icon: const Icon(Icons.arrow_back_rounded),
                              ),
                              TextButton(
                                key: const ValueKey('tour-skip-step'),
                                onPressed: busy ? null : () => go(step + 1),
                                child: Text(t('Пропустить шаг')),
                              ),
                              FilledButton(
                                key: const ValueKey('tour-next'),
                                onPressed: busy ? null : () => go(step + 1),
                                child: Text(
                                  t(
                                    step == _steps.length - 1
                                        ? 'Начать'
                                        : 'Далее',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Spotlight extends CustomPainter {
  final Rect? target;
  final Color color;
  final Animation<double> pulse;
  _Spotlight(this.target, this.color, this.pulse) : super(repaint: pulse);
  @override
  void paint(Canvas canvas, Size size) {
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    final hole = target == null
        ? null
        : RRect.fromRectAndRadius(target!, const Radius.circular(18));
    if (hole != null) mask.addRRect(hole);
    canvas.drawPath(mask, Paint()..color = Colors.black.withValues(alpha: .7));
    if (hole != null) {
      canvas.drawRRect(
        hole.inflate(3 + pulse.value * 2),
        Paint()
          ..color = color.withValues(alpha: .15 + pulse.value * .15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7,
      );
      canvas.drawRRect(
        hole,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Spotlight old) =>
      old.target != target || old.color != color;
}

class _HoleBarrier extends SingleChildRenderObjectWidget {
  final Rect? hole;
  const _HoleBarrier({this.hole});
  @override
  _RenderHoleBarrier createRenderObject(BuildContext context) =>
      _RenderHoleBarrier(hole);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHoleBarrier renderObject,
  ) => renderObject.hole = hole;
}

class _RenderHoleBarrier extends RenderBox {
  Rect? hole;
  _RenderHoleBarrier(this.hole);
  @override
  void performLayout() {
    size = constraints.biggest;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (hole?.contains(position) == true) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}
