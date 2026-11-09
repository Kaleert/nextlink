import '../shared/widgets/theme_region.dart';

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme/theme_provider.dart';
import '../core/localization/app_localizations.dart';
import '../core/providers/chains_provider.dart';
import 'chain_editor_screen.dart';

class ChainsScreen extends ConsumerWidget {
  const ChainsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).currentTheme;
    final loc = AppLocalizations.of(context)!;
    final chains = ref.watch(chainsProvider);

    return Scaffold(
      backgroundColor: theme.background,
      body: ThemeRegion(
        id: 'screen_chains',
        child: ThemeRegion.auto(
          id: "widget_chains_screen_0",
          label: "Stack · chains_screen.dart",
          child: Stack(
            children: [
              Positioned(
                top: 200,
                left: -100,
                child: ThemeRegion.auto(
                  id: "widget_chains_screen_1",
                  label: "Container · chains_screen.dart",
                  child: Container(
                    width: 300,
                    height: 300,
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
                  id: "widget_chains_screen_2",
                  label: "Container · chains_screen.dart",
                  child: Container(color: Colors.transparent),
                ),
              ),

              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: ThemeRegion.auto(
                      id: "widget_chains_screen_3",
                      label: "Column · chains_screen.dart",
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20.0,
                              vertical: 16.0,
                            ),
                            child: ThemeRegion.auto(
                              id: "widget_chains_screen_4",
                              label: "Row · chains_screen.dart",
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      Navigator.pop(context);
                                    },
                                    child: ThemeRegion.auto(
                                      id: "widget_chains_screen_5",
                                      label: "Container · chains_screen.dart",
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: theme.surface.withOpacity(0.5),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: Colors.white10,
                                          ),
                                        ),
                                        child: ThemeRegion.auto(
                                          id: "widget_chains_screen_6",
                                          label: "Icon · chains_screen.dart",
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
                                    id: "widget_chains_screen_7",
                                    label: "Text · chains_screen.dart",
                                    child: Text(
                                      loc.translate('chains'),
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
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const ChainEditorScreen(),
                                        ),
                                      );
                                    },
                                    child: ThemeRegion.auto(
                                      id: "widget_chains_screen_8",
                                      label: "Container · chains_screen.dart",
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: theme.primary.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: theme.primary.withOpacity(
                                              0.5,
                                            ),
                                          ),
                                        ),
                                        child: ThemeRegion.auto(
                                          id: "widget_chains_screen_9",
                                          label: "Icon · chains_screen.dart",
                                          child: Icon(
                                            Icons.add_rounded,
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
                            child: chains.isEmpty
                                ? Center(
                                    child: ThemeRegion.auto(
                                      id: "widget_chains_screen_10",
                                      label: "Text · chains_screen.dart",
                                      child: Text(
                                        AppLocalizations.text(
                                          context,
                                          "Нет созданных цепочек",
                                        ),
                                        style: TextStyle(
                                          color: theme.textDim,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 10,
                                    ),
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: chains.length,
                                    itemBuilder: (context, index) {
                                      final chain = chains[index];
                                      final isActive = chain.isActive;

                                      return GestureDetector(
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          ref
                                              .read(chainsProvider.notifier)
                                              .setActiveChain(
                                                isActive ? null : chain.id,
                                              );
                                        },
                                        child: ThemeRegion.auto(
                                          id: "widget_chains_screen_11",
                                          label:
                                              "Container · chains_screen.dart",
                                          child: Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 24,
                                            ),
                                            padding: const EdgeInsets.all(24),
                                            decoration: BoxDecoration(
                                              color: isActive
                                                  ? theme.primary.withOpacity(
                                                      0.1,
                                                    )
                                                  : theme.surface.withOpacity(
                                                      0.4,
                                                    ),
                                              borderRadius:
                                                  BorderRadius.circular(32),
                                              border: Border.all(
                                                color: isActive
                                                    ? theme.primary.withOpacity(
                                                        0.5,
                                                      )
                                                    : Colors.white.withOpacity(
                                                        0.08,
                                                      ),
                                                width: isActive ? 1.5 : 1,
                                              ),
                                            ),
                                            child: ThemeRegion.auto(
                                              id: "widget_chains_screen_12",
                                              label:
                                                  "Column · chains_screen.dart",
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  ThemeRegion.auto(
                                                    id: "widget_chains_screen_13",
                                                    label: "Row · chains_screen.dart",
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        ThemeRegion.auto(
                                                          id: "widget_chains_screen_14",
                                                          label: "Text · chains_screen.dart",
                                                          child: Text(
                                                            chain.name,
                                                            style: TextStyle(
                                                              fontSize: 18,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color: isActive
                                                                  ? theme
                                                                        .primary
                                                                  : theme.text,
                                                            ),
                                                          ),
                                                        ),
                                                        ThemeRegion.auto(
                                                          id: "widget_chains_screen_15",
                                                          label: "Row · chains_screen.dart",
                                                          child: Row(
                                                            children: [
                                                              GestureDetector(
                                                                onTap: () {
                                                                  HapticFeedback.lightImpact();
                                                                  Navigator.push(
                                                                    context,
                                                                    MaterialPageRoute(
                                                                      builder: (_) => ChainEditorScreen(
                                                                        editingChain:
                                                                            chain,
                                                                      ),
                                                                    ),
                                                                  );
                                                                },
                                                                child: ThemeRegion.auto(
                                                                  id: "widget_chains_screen_16",
                                                                  label: "Icon · chains_screen.dart",
                                                                  child: Icon(
                                                                    Icons
                                                                        .edit_rounded,
                                                                    size: 20,
                                                                    color: theme
                                                                        .textDim,
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 16,
                                                              ),
                                                              GestureDetector(
                                                                onTap: () {
                                                                  HapticFeedback.mediumImpact();
                                                                  ref
                                                                      .read(
                                                                        chainsProvider
                                                                            .notifier,
                                                                      )
                                                                      .removeChain(
                                                                        chain
                                                                            .id,
                                                                      );
                                                                },
                                                                child: ThemeRegion.auto(
                                                                  id: "widget_chains_screen_17",
                                                                  label: "Icon · chains_screen.dart",
                                                                  child: Icon(
                                                                    Icons
                                                                        .delete_outline_rounded,
                                                                    size: 20,
                                                                    color: theme
                                                                        .textDim,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 24),

                                                  ...chain.nodes.asMap().entries.map((
                                                    nodeEntry,
                                                  ) {
                                                    final isLast =
                                                        nodeEntry.key ==
                                                        chain.nodes.length - 1;
                                                    final srv = nodeEntry.value;
                                                    return ThemeRegion.auto(
                                                      id: "widget_chains_screen_18",
                                                      label: "Column · chains_screen.dart",
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          ThemeRegion.auto(
                                                            id: "widget_chains_screen_19",
                                                            label: "Row · chains_screen.dart",
                                                            child: Row(
                                                              children: [
                                                                ThemeRegion.auto(
                                                                  id: "widget_chains_screen_20",
                                                                  label: "Container · chains_screen.dart",
                                                                  child: Container(
                                                                    padding:
                                                                        const EdgeInsets.all(
                                                                          8,
                                                                        ),
                                                                    decoration: BoxDecoration(
                                                                      color:
                                                                          isLast
                                                                          ? Colors.green.withOpacity(
                                                                              0.2,
                                                                            )
                                                                          : Colors.black38,
                                                                      shape: BoxShape
                                                                          .circle,
                                                                    ),
                                                                    child: ThemeRegion.auto(
                                                                      id: "widget_chains_screen_21",
                                                                      label: "Icon · chains_screen.dart",
                                                                      child: Icon(
                                                                        isLast
                                                                            ? Icons.public_rounded
                                                                            : Icons.dns_rounded,
                                                                        size:
                                                                            16,
                                                                        color:
                                                                            isLast
                                                                            ? Colors.greenAccent
                                                                            : theme.textDim,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                  width: 16,
                                                                ),
                                                                Expanded(
                                                                  child: ThemeRegion.auto(
                                                                    id: "widget_chains_screen_22",
                                                                    label: "Text · chains_screen.dart",
                                                                    child: Text(
                                                                      '${srv.name} (${srv.protocol})',
                                                                      style: const TextStyle(
                                                                        fontSize:
                                                                            15,
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                      ),
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          if (!isLast)
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets.only(
                                                                    left: 15.0,
                                                                    top: 4,
                                                                    bottom: 4,
                                                                  ),
                                                              child: ThemeRegion.auto(
                                                                id: "widget_chains_screen_23",
                                                                label: "Container · chains_screen.dart",
                                                                child: Container(
                                                                  width: 2,
                                                                  height: 20,
                                                                  color: theme
                                                                      .primary
                                                                      .withOpacity(
                                                                        0.3,
                                                                      ),
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    );
                                                  }).toList(),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ).animate().fade(delay: (100 * index).ms).slideY(begin: 0.1),
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
            ],
          ),
        ),
      ),
    );
  }
}
