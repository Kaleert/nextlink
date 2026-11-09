import '../shared/widgets/theme_region.dart';

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme/theme_provider.dart';
import '../core/localization/app_localizations.dart';
import '../core/models/proxies/proxy_config.dart';
import '../core/providers/subscription_provider.dart';
import '../core/providers/chains_provider.dart';
import '../shared/widgets/custom_notification.dart';

class ChainEditorScreen extends ConsumerStatefulWidget {
  final ProxyChain? editingChain;

  const ChainEditorScreen({super.key, this.editingChain});

  @override
  ConsumerState<ChainEditorScreen> createState() => _ChainEditorScreenState();
}

class _ChainEditorScreenState extends ConsumerState<ChainEditorScreen> {
  late TextEditingController _nameController;
  List<ProxyConfig> _nodes = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.editingChain?.name ?? 'Моя цепочка',
    );
    if (widget.editingChain != null) {
      _nodes = List.from(widget.editingChain!.nodes);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _showServerPicker() {
    final loc = AppLocalizations.of(context)!;
    final theme = ref.read(themeProvider).currentTheme;
    final subscriptions = ref.read(subscriptionProvider);

    final allServers = <ProxyConfig>[];
    for (var sub in subscriptions) {
      allServers.addAll(sub.servers);
    }

    if (allServers.isEmpty) {
      CustomNotification.show(
        context,
        AppLocalizations.text(context, "Нет доступных серверов в подписках"),
      );
      return;
    }

    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.12),
      isScrollControlled: true,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
          child: ThemeRegion.auto(
            id: "widget_chain_editor_screen_0",
            label: "Container · chain_editor_screen.dart",
            child: Container(
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: theme.surface.withOpacity(0.24)),
              child: ThemeRegion.auto(
                id: "widget_chain_editor_screen_1",
                label: "Column · chain_editor_screen.dart",
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: ThemeRegion.auto(
                        id: "widget_chain_editor_screen_2",
                        label: "Container · chain_editor_screen.dart",
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ThemeRegion.auto(
                      id: "widget_chain_editor_screen_3",
                      label: "Text · chain_editor_screen.dart",
                      child: Text(
                        loc.translate('add_proxy_to_chain'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    Expanded(
                      child: ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: allServers.length,
                        itemBuilder: (context, index) {
                          final srv = allServers[index];

                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              setState(() => _nodes.add(srv));
                              Navigator.pop(context);
                            },
                            child: ThemeRegion.auto(
                              id: "widget_chain_editor_screen_4",
                              label: "Container · chain_editor_screen.dart",
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: ThemeRegion.auto(
                                  id: "widget_chain_editor_screen_5",
                                  label: "Row · chain_editor_screen.dart",
                                  child: Row(
                                    children: [
                                      ThemeRegion.auto(
                                        id: "widget_chain_editor_screen_6",
                                        label:
                                            "Icon · chain_editor_screen.dart",
                                        child: const Icon(
                                          Icons.dns_rounded,
                                          color: Colors.white70,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: ThemeRegion.auto(
                                          id: "widget_chain_editor_screen_7",
                                          label: "Column · chain_editor_screen.dart",
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              ThemeRegion.auto(
                                                id: "widget_chain_editor_screen_8",
                                                label: "Text · chain_editor_screen.dart",
                                                child: Text(
                                                  srv.name,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                              ThemeRegion.auto(
                                                id: "widget_chain_editor_screen_9",
                                                label: "Text · chain_editor_screen.dart",
                                                child: Text(
                                                  srv.protocol,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: theme.textDim,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      ThemeRegion.auto(
                                        id: "widget_chain_editor_screen_10",
                                        label:
                                            "Icon · chain_editor_screen.dart",
                                        child: Icon(
                                          Icons.add_circle_outline_rounded,
                                          color: theme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _saveChain() {
    final name = _nameController.text.trim().isEmpty
        ? 'Без названия'
        : _nameController.text.trim();
    if (_nodes.isEmpty) {
      CustomNotification.show(
        context,
        AppLocalizations.text(context, "Добавьте хотя бы один узел"),
      );
      return;
    }

    final newChain = ProxyChain(
      id:
          widget.editingChain?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      isActive: widget.editingChain?.isActive ?? false,
      nodes: _nodes,
    );

    if (widget.editingChain != null) {
      ref.read(chainsProvider.notifier).updateChain(newChain);
    } else {
      ref.read(chainsProvider.notifier).addChain(newChain);
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).currentTheme;
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: theme.background,
      body: ThemeRegion(
        id: 'screen_chain_editor',
        child: ThemeRegion.auto(
          id: "widget_chain_editor_screen_11",
          label: "Stack · chain_editor_screen.dart",
          child: Stack(
            children: [
              Positioned(
                top: -50,
                right: 100,
                child: ThemeRegion.auto(
                  id: "widget_chain_editor_screen_12",
                  label: "Container · chain_editor_screen.dart",
                  child: Container(
                    width: 400,
                    height: 400,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.meshIdle1,
                    ),
                  ),
                ),
              ),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: ThemeRegion.auto(
                  id: "widget_chain_editor_screen_13",
                  label: "Container · chain_editor_screen.dart",
                  child: Container(color: Colors.transparent),
                ),
              ),

              SafeArea(
                child: ThemeRegion.auto(
                  id: "widget_chain_editor_screen_14",
                  label: "Column · chain_editor_screen.dart",
                  child: Column(
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20.0,
                          vertical: 16.0,
                        ),
                        child: ThemeRegion.auto(
                          id: "widget_chain_editor_screen_15",
                          label: "Row · chain_editor_screen.dart",
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.pop(context);
                                },
                                child: ThemeRegion.auto(
                                  id: "widget_chain_editor_screen_16",
                                  label: "Container · chain_editor_screen.dart",
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: theme.surface.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: ThemeRegion.auto(
                                      id: "widget_chain_editor_screen_17",
                                      label: "Icon · chain_editor_screen.dart",
                                      child: Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        color: theme.text,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              ThemeRegion.auto(
                                id: "widget_chain_editor_screen_18",
                                label: "Text · chain_editor_screen.dart",
                                child: Text(
                                  loc.translate('chain_editor'),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.mediumImpact();
                                  _saveChain();
                                },
                                child: ThemeRegion.auto(
                                  id: "widget_chain_editor_screen_19",
                                  label: "Container · chain_editor_screen.dart",
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: theme.primary.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: theme.primary.withOpacity(0.5),
                                      ),
                                    ),
                                    child: ThemeRegion.auto(
                                      id: "widget_chain_editor_screen_20",
                                      label: "Icon · chain_editor_screen.dart",
                                      child: Icon(
                                        Icons.check_rounded,
                                        color: theme.primary,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ).animate().fade().slideY(begin: -0.2),

                      Expanded(
                        child: ThemeRegion.auto(
                          id: "widget_chain_editor_screen_21",
                          label: "Column · chain_editor_screen.dart",
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 8,
                                ),
                                child: ThemeRegion.auto(
                                  id: "widget_chain_editor_screen_22",
                                  label: "Container · chain_editor_screen.dart",
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black45,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: ThemeRegion.auto(
                                      id: "widget_chain_editor_screen_23",
                                      label: "TextField · chain_editor_screen.dart",
                                      child: TextField(
                                        controller: _nameController,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                        decoration: InputDecoration(
                                          border: InputBorder.none,
                                          hintText: loc.translate(
                                            'chain_name_hint',
                                          ),
                                          hintStyle: const TextStyle(
                                            color: Colors.white24,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ).animate().fade(delay: 100.ms),

                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 32,
                                  top: 24,
                                  bottom: 8,
                                ),
                                child: ThemeRegion.auto(
                                  id: "widget_chain_editor_screen_24",
                                  label: "Text · chain_editor_screen.dart",
                                  child: Text(
                                    loc.translate('route_top_bottom'),
                                    style: TextStyle(
                                      color: theme.textDim,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                              ).animate().fade(delay: 200.ms),

                              Expanded(
                                child: Theme(
                                  data: Theme.of(
                                    context,
                                  ).copyWith(canvasColor: Colors.transparent),
                                  child: ReorderableListView.builder(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                    ),
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: _nodes.length,
                                    proxyDecorator: (child, index, animation) =>
                                        Material(
                                          color: Colors.transparent,
                                          child: child,
                                        ),
                                    onReorder: (oldIndex, newIndex) {
                                      HapticFeedback.lightImpact();
                                      setState(() {
                                        if (oldIndex < newIndex) newIndex -= 1;
                                        final item = _nodes.removeAt(oldIndex);
                                        _nodes.insert(newIndex, item);
                                      });
                                    },
                                    itemBuilder: (context, index) {
                                      final node = _nodes[index];
                                      return ThemeRegion.auto(
                                        id: "widget_chain_editor_screen_25",
                                        label: "Container · chain_editor_screen.dart",
                                        child: Container(
                                          key: ValueKey(
                                            'node_${index}_${node.uniqueKey}',
                                          ),
                                          margin: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: theme.surface.withOpacity(
                                              0.6,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              24,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withOpacity(
                                                0.05,
                                              ),
                                            ),
                                          ),
                                          child: ThemeRegion.auto(
                                            id: "widget_chain_editor_screen_26",
                                            label: "Row · chain_editor_screen.dart",
                                            child: Row(
                                              children: [
                                                ThemeRegion.auto(
                                                  id: "widget_chain_editor_screen_27",
                                                  label: "Icon · chain_editor_screen.dart",
                                                  child: Icon(
                                                    Icons
                                                        .drag_indicator_rounded,
                                                    color: theme.textDim,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                ThemeRegion.auto(
                                                  id: "widget_chain_editor_screen_28",
                                                  label: "Icon · chain_editor_screen.dart",
                                                  child: const Icon(
                                                    Icons.dns_rounded,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: ThemeRegion.auto(
                                                    id: "widget_chain_editor_screen_29",
                                                    label: "Column · chain_editor_screen.dart",
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        ThemeRegion.auto(
                                                          id: "widget_chain_editor_screen_30",
                                                          label: "Text · chain_editor_screen.dart",
                                                          child: Text(
                                                            node.name,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 16,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                          ),
                                                        ),
                                                        ThemeRegion.auto(
                                                          id: "widget_chain_editor_screen_31",
                                                          label: "Text · chain_editor_screen.dart",
                                                          child: Text(
                                                            node.protocol,
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color:
                                                                  theme.textDim,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                GestureDetector(
                                                  onTap: () {
                                                    HapticFeedback.lightImpact();
                                                    setState(
                                                      () => _nodes.removeAt(
                                                        index,
                                                      ),
                                                    );
                                                  },
                                                  child: ThemeRegion.auto(
                                                    id: "widget_chain_editor_screen_32",
                                                    label: "Container · chain_editor_screen.dart",
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            8,
                                                          ),
                                                      child: ThemeRegion.auto(
                                                        id: "widget_chain_editor_screen_33",
                                                        label: "Icon · chain_editor_screen.dart",
                                                        child: Icon(
                                                          Icons.close_rounded,
                                                          size: 20,
                                                          color: Colors
                                                              .redAccent
                                                              .withOpacity(0.8),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),

                              Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: GestureDetector(
                                  onTap: _showServerPicker,
                                  child: ThemeRegion.auto(
                                    id: "widget_chain_editor_screen_34",
                                    label:
                                        "Container · chain_editor_screen.dart",
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.white10,
                                        ),
                                      ),
                                      child: ThemeRegion.auto(
                                        id: "widget_chain_editor_screen_35",
                                        label: "Row · chain_editor_screen.dart",
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            ThemeRegion.auto(
                                              id: "widget_chain_editor_screen_36",
                                              label: "Icon · chain_editor_screen.dart",
                                              child: const Icon(
                                                Icons.add_rounded,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            ThemeRegion.auto(
                                              id: "widget_chain_editor_screen_37",
                                              label: "Text · chain_editor_screen.dart",
                                              child: Text(
                                                loc.translate('add_proxy'),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ).animate().fade(delay: 300.ms),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
