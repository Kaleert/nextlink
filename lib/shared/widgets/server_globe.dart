import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/models/proxies/proxy_config.dart';
import '../../core/models/proxies/proxy_parser.dart';
import '../../core/providers/map_selection_provider.dart';
import '../../core/providers/server_locations_provider.dart';
import '../../core/providers/chains_provider.dart';
import 'glass_alert_dialog.dart';
import '../../core/utils/ip_location.dart';
import '../../core/utils/server_location.dart';
import 'country_flag.dart';
import 'theme_region.dart';
import '../../core/theme/theme_provider.dart';
import 'custom_notification.dart';

class GlobeProjection {
  final double longitude, latitude;
  const GlobeProjection(this.longitude, this.latitude);

  /// Orthographic projection. The third coordinate is visibility/depth.
  (Offset, double) project(double lat, double lon, Size size) {
    final phi = lat * math.pi / 180, lambda = lon * math.pi / 180 - longitude;
    final c = math.cos(phi), s = math.sin(phi);
    final z =
        c * math.cos(lambda) * math.cos(latitude) + s * math.sin(latitude);
    final r = math.min(size.width, size.height) * .44;
    return (
      Offset(
        size.width / 2 + r * c * math.sin(lambda),
        size.height / 2 -
            r *
                (s * math.cos(latitude) -
                    c * math.cos(lambda) * math.sin(latitude)),
      ),
      z,
    );
  }
}

class _Marker {
  final ServerEndpoint endpoint;
  IpLocation location;
  final ProxyConfig config;
  final ProxyConfig? savedNode;
  _Marker(this.endpoint, this.location, this.config, {this.savedNode});
}

class _LandVertex {
  final double x, y, z;
  int frame = -1;
  (Offset, double)? projected;
  _LandVertex(Offset p)
    : x = math.cos(p.dy * math.pi / 180) * math.sin(p.dx * math.pi / 180),
      y = math.sin(p.dy * math.pi / 180),
      z = math.cos(p.dy * math.pi / 180) * math.cos(p.dx * math.pi / 180);
}

class _Geometry {
  final List<List<Offset>> land, borders;
  final List<List<_LandVertex>> mesh;
  const _Geometry(this.land, this.borders, this.mesh);
}

Future<_Geometry>? _geometry;
Future<_Geometry> _loadGeometry() => _geometry ??= Future.wait([
  rootBundle.loadString('assets/map/land.json'),
  rootBundle.loadString('assets/map/borders.json'),
  rootBundle.loadString('assets/map/land_mesh.json'),
]).then((data) => compute(_parseGeometry, data));

_Geometry _parseGeometry(List<String> data) {
  List<List<Offset>> read(String text) => [
    for (final ring in jsonDecode(text) as List)
      [
        for (final p in ring)
          Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
      ],
  ];
  final vertices = <Offset, _LandVertex>{};
  return _Geometry(read(data[0]), read(data[1]), [
    for (final triangle in read(data[2]))
      [for (final p in triangle) vertices.putIfAbsent(p, () => _LandVertex(p))],
  ]);
}

class _GlobePaintCache {
  Object? key;
  Picture? picture;
  void dispose() {
    picture?.dispose();
    picture = null;
    key = null;
  }
}

/// Clusters use screen distance, so zooming separates nearby cities naturally.
List<List<int>> clusterGlobePoints(List<Offset> points, {double radius = 40}) {
  final clusters = <List<int>>[];
  for (var i = 0; i < points.length; i++) {
    final group = clusters
        .where((c) => (points[c.first] - points[i]).distance <= radius)
        .firstOrNull;
    if (group == null)
      clusters.add([i]);
    else
      group.add(i);
  }
  return clusters;
}

class _Cluster {
  final Offset point;
  final List<_Marker> markers;
  const _Cluster(this.point, this.markers);
}

List<_Cluster> _clusters(
  List<_Marker> markers,
  GlobeProjection projection,
  Size size,
) {
  final visible = <_Marker>[], points = <Offset>[];
  for (final marker in markers) {
    final (p, z) = projection.project(
      marker.location.latitude!,
      marker.location.longitude!,
      size,
    );
    if (z <= 0) continue;
    visible.add(marker);
    points.add(p);
  }
  return [
    for (final group in clusterGlobePoints(points))
      _Cluster(points[group.first], [for (final i in group) visible[i]]),
  ];
}

List<IpLocation> chainMapLocations(
  ProxyChain chain,
  Map<String, IpLocation> locations, {
  IpLocation? exit,
}) => [
  for (var i = 0; i < chain.nodes.length; i++)
    if (i == chain.nodes.length - 1 && exit?.hasCoordinates == true)
      exit!
    else
      locations[concreteServerEndpoint(chain.nodes[i])?.host] ??
          const IpLocation(),
];

class ServerGlobe extends ConsumerStatefulWidget {
  final bool fullScreen;
  final bool connected;
  final String? connectedServerKey;
  final Future<void> Function()? onDisconnect;
  final IpLocation? currentLocation;
  final Future<void> Function(ProxyConfig, String?)? onConnect;
  final Future<void> Function(ProxyChain)? onConnectChain;
  final ValueChanged<bool>? onEditingChanged;
  const ServerGlobe({
    super.key,
    this.fullScreen = false,
    this.connected = false,
    this.connectedServerKey,
    this.onDisconnect,
    this.currentLocation,
    this.onConnect,
    this.onConnectChain,
    this.onEditingChanged,
  });
  @override
  ConsumerState<ServerGlobe> createState() => _ServerGlobeState();
}

class _ServerGlobeState extends ConsumerState<ServerGlobe> {
  final _paintCache = _GlobePaintCache();
  int _gesturePointers = 0;
  bool buildingChain = false;
  bool _focusPending = false;
  bool _draftFocusPending = false;
  String? editingChainId, editingChainName;
  final List<_Marker> draft = [];
  double longitude = .35, latitude = .55, zoom = 1, startZoom = 1;
  late final Future<_Geometry> geometry = _loadGeometry();
  @override
  void initState() {
    super.initState();
    zoom = widget.fullScreen ? 1.65 : 1;
    _focusPending = widget.connected;
  }

  @override
  void dispose() {
    _paintCache.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ServerGlobe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected &&
        (!oldWidget.connected ||
            oldWidget.connectedServerKey != widget.connectedServerKey))
      _focusPending = true;
  }

  void _focusRoute(List<IpLocation> route, IpLocation? exit) {
    final points = route.where((p) => p.hasCoordinates).toList();
    if (points.isEmpty && exit?.hasCoordinates == true) points.add(exit!);
    if (points.isEmpty) return;
    longitude = math.atan2(
      points.fold<double>(
        0,
        (sum, p) => sum + math.sin(p.longitude! * math.pi / 180),
      ),
      points.fold<double>(
        0,
        (sum, p) => sum + math.cos(p.longitude! * math.pi / 180),
      ),
    );
    latitude =
        points.fold<double>(0, (sum, p) => sum + p.latitude!) /
        points.length *
        math.pi /
        180;
    zoom = points.length > 1 ? .95 : 1.65;
    _focusPending = false;
  }

  String t(String text) => AppLocalizations.text(context, text);

  Future<void> _choose(_Marker marker) async {
    try {
      if (buildingChain) {
        chainNodeForEndpoint(
          marker.config,
          marker.endpoint,
        ); // Validate before adding.
        if (draft.isNotEmpty &&
            draft.last.config.uniqueKey == marker.config.uniqueKey &&
            draft.last.endpoint.label == marker.endpoint.label)
          return;
        setState(() => draft.add(marker));
        return;
      }
      final selected = connectionForEndpoint(marker.config, marker.endpoint);
      await widget.onConnect?.call(selected, marker.config.uniqueKey);
    } catch (error) {
      if (mounted) CustomNotification.show(context, '$error', isError: true);
    }
  }

  void _setBuilding(bool value) {
    setState(() {
      buildingChain = value;
      if (!value) {
        draft.clear();
        editingChainId = null;
        editingChainName = null;
      }
    });
    widget.onEditingChanged?.call(value);
  }

  int get _minimumNodes => editingChainId == null ? 2 : 1;
  Future<void> _finishChain(bool connect) async {
    if (draft.length < _minimumNodes) return;
    final controller = TextEditingController(
      text:
          editingChainName ??
          draft
              .map(
                (m) => m.location.city.isNotEmpty
                    ? m.location.city
                    : m.endpoint.label,
              )
              .join(' → '),
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => GlassAlertDialog(
        surfaceColor: Theme.of(context).colorScheme.surface,
        title: Text(t('Название цепочки')),
        content: ThemeRegion.auto(
          id: "widget_globe_controls_0",
          label: "TextField · server_globe.dart",
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 80,
            onSubmitted: (value) {
              if (value.trim().isNotEmpty)
                Navigator.pop(dialogContext, value.trim());
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('Отмена')),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty)
                Navigator.pop(dialogContext, controller.text.trim());
            },
            child: Text(t('Сохранить')),
          ),
        ],
      ),
    );
    // The route transition may still use the controller until its reverse ends.
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (name == null || !mounted) return;
    try {
      final chain = ProxyChain(
        id: editingChainId ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        isActive:
            ref
                .read(chainsProvider)
                .where((c) => c.id == editingChainId)
                .firstOrNull
                ?.isActive ??
            false,
        nodes: [
          for (var i = 0; i < draft.length; i++)
            if (draft[i].savedNode != null)
              ProxyParser.fromMap(draft[i].savedNode!.toMap())
            else if (i == draft.length - 1)
              ..._terminalDraftNode(draft[i])
            else
              chainNodeForEndpoint(draft[i].config, draft[i].endpoint),
        ],
      );
      await ref.read(chainsProvider.notifier).ready;
      if (!mounted) return;
      final wasEditing = editingChainId != null;
      if (wasEditing)
        ref.read(chainsProvider.notifier).updateChain(chain);
      else
        ref.read(chainsProvider.notifier).addChain(chain);
      _setBuilding(false);
      CustomNotification.show(context, t('Цепочка сохранена'));
      if (connect && !(chain.isActive && widget.connected))
        await widget.onConnectChain?.call(chain);
    } catch (error) {
      if (mounted) CustomNotification.show(context, '$error', isError: true);
    }
  }

  List<ProxyConfig> _terminalDraftNode(_Marker marker) {
    final node = chainNodeForEndpoint(marker.config, marker.endpoint);
    final full = connectionForEndpoint(marker.config, marker.endpoint);
    if (full.finalJson.containsKey('outbounds') ||
        full.finalJson.containsKey('endpoints'))
      node.rawJsonOverride = jsonEncode(full.finalJson);
    node.fp = marker.config.fp;
    return [node];
  }

  void _editChain(ProxyChain chain) {
    final locations =
        ref.read(serverLocationsProvider).asData?.value ??
        const <String, IpLocation>{};
    setState(() {
      editingChainId = chain.id;
      editingChainName = chain.name;
      draft.clear();
      for (final node in chain.nodes) {
        final endpoint =
            concreteServerEndpoint(node) ??
            ServerEndpoint('', node.name, node.uniqueKey, node.name, false);
        draft.add(
          _Marker(
            endpoint,
            locations[endpoint.host] ?? const IpLocation(),
            node,
            savedNode: node,
          ),
        );
      }
      buildingChain = true;
      _draftFocusPending = true;
    });
    widget.onEditingChanged?.call(true);
  }

  bool _isConnectedChain(ProxyChain chain) =>
      widget.connected &&
      (widget.connectedServerKey == 'chain:${chain.id}' ||
          widget.connectedServerKey == null && chain.isActive);
  Future<void> _deleteChain(ProxyChain chain) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassAlertDialog(
        surfaceColor: Theme.of(context).colorScheme.surface,
        title: Text(t('Удалить цепочку?')),
        content: FlagText(original: Text(chain.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('Отмена')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t('Удалить')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      if (_isConnectedChain(chain)) {
        if (widget.onDisconnect == null)
          throw const FormatException('Сначала отключите VPN');
        await widget.onDisconnect!();
      }
      if (!mounted) return;
      ref.read(chainsProvider.notifier).removeChain(chain.id);
      if (editingChainId == chain.id) _setBuilding(false);
      CustomNotification.show(context, t('Цепочка удалена'));
    } catch (error) {
      if (mounted) CustomNotification.show(context, '$error', isError: true);
    }
  }

  void _showSavedChains() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => LocationSheetSurface(
        child: Consumer(
          builder: (context, ref, _) {
            final chains = ref.watch(chainsProvider);
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .7,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t('Мои цепочки'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      ThemeRegion.auto(
                        id: "widget_globe_controls_1",
                        label: "IconButton · server_globe.dart",
                        child: IconButton(
                          tooltip: t('Новая цепочка'),
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _setBuilding(false);
                            _setBuilding(true);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (chains.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(t('Сохранённых цепочек пока нет')),
                    ),
                  for (final chain in chains)
                    ThemeRegion.auto(
                      id: "widget_globe_controls_2",
                      label: "ListTile · server_globe.dart",
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: FlagText(
                          original: Text(
                            chain.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        subtitle: FlagText(
                          original: Text(
                            chain.nodes.map((n) => n.name).join(' → '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _editChain(chain);
                        },
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ThemeRegion.auto(
                              id: "widget_globe_controls_3",
                              label: "IconButton · server_globe.dart",
                              child: IconButton(
                                tooltip: t('Редактировать'),
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () {
                                  Navigator.pop(sheetContext);
                                  _editChain(chain);
                                },
                              ),
                            ),
                            ThemeRegion.auto(
                              id: "widget_globe_controls_4",
                              label: "IconButton · server_globe.dart",
                              child: IconButton(
                                tooltip: t(
                                  _isConnectedChain(chain)
                                      ? 'Отключить'
                                      : 'Подключить',
                                ),
                                icon: Icon(
                                  _isConnectedChain(chain)
                                      ? Icons.stop_circle_outlined
                                      : Icons.play_arrow,
                                  size: 22,
                                ),
                                onPressed: widget.onConnectChain == null
                                    ? null
                                    : () async {
                                        Navigator.pop(sheetContext);
                                        try {
                                          if (_isConnectedChain(chain))
                                            await widget.onDisconnect?.call();
                                          else
                                            await widget.onConnectChain?.call(
                                              chain,
                                            );
                                        } catch (error) {
                                          if (mounted)
                                            CustomNotification.show(
                                              this.context,
                                              '$error',
                                              isError: true,
                                            );
                                        }
                                      },
                              ),
                            ),
                            ThemeRegion.auto(
                              id: "widget_globe_controls_5",
                              label: "IconButton · server_globe.dart",
                              child: IconButton(
                                tooltip: t('Удалить цепочку'),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                ),
                                onPressed: () async {
                                  Navigator.pop(sheetContext);
                                  await _deleteChain(chain);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showAuto(List<ProxyConfig> configs) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => LocationSheetSurface(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .65,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                t('Авто из подписок'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              for (final config in configs)
                ThemeRegion.auto(
                  id: "widget_globe_controls_6",
                  label: "ListTile · server_globe.dart",
                  child: ListTile(
                    leading: const Icon(Icons.auto_awesome),
                    title: FlagText(original: Text(config.name)),
                    subtitle: Text(
                      t('Исходный конфиг с автовыбором и правилами подписки'),
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      try {
                        await widget.onConnect?.call(config, config.uniqueKey);
                      } catch (error) {
                        if (mounted)
                          CustomNotification.show(
                            context,
                            '$error',
                            isError: true,
                          );
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _draftPanel() => LocationSheetSurface(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  editingChainName ?? t('Маршрут цепочки'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (draft.any((m) => m.location.hasCoordinates))
                ThemeRegion.auto(
                  id: "widget_globe_controls_7",
                  label: "IconButton · server_globe.dart",
                  child: IconButton(
                    tooltip: t('Показать маршрут'),
                    icon: const Icon(Icons.center_focus_strong),
                    onPressed: () => setState(
                      () => _focusRoute(
                        draft.map((m) => m.location).toList(),
                        null,
                      ),
                    ),
                  ),
                ),
              ThemeRegion.auto(
                id: "widget_globe_controls_8",
                label: "IconButton · server_globe.dart",
                child: IconButton(
                  tooltip: t('Мои цепочки'),
                  onPressed: _showSavedChains,
                  icon: const Icon(Icons.folder_outlined),
                ),
              ),
              ThemeRegion.auto(
                id: "widget_globe_controls_9",
                label: "IconButton · server_globe.dart",
                child: IconButton(
                  tooltip: t('Отмена'),
                  onPressed: () => _setBuilding(false),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
          if (draft.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(t('Нажимайте на точки: сначала вход, затем выход')),
            ),
          if (draft.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .22,
              ),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: draft.length,
                onReorder: (oldIndex, newIndex) => setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  draft.insert(newIndex, draft.removeAt(oldIndex));
                }),
                itemBuilder: (context, index) {
                  final marker = draft[index];
                  return ThemeRegion.auto(
                    key: ObjectKey(marker),
                    id: "widget_globe_controls_10",
                    label: "ListTile · server_globe.dart",
                    child: ListTile(
                      key: ObjectKey(marker),
                      dense: true,
                      leading: Text(
                        '${index + 1}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      title: FlagText(
                        original: Text(
                          marker.endpoint.grouped
                              ? marker.endpoint.label
                              : marker.endpoint.serverName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      subtitle: Text(
                        '${index == 0
                            ? t('Вход')
                            : index == draft.length - 1
                            ? t('Выход')
                            : t('Промежуточный узел')} · ${marker.location.city.isNotEmpty ? marker.location.city : t('Локация пока неизвестна')}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ThemeRegion.auto(
                            id: "widget_globe_controls_11",
                            label: "IconButton · server_globe.dart",
                            child: IconButton(
                              tooltip: t('Удалить узел'),
                              onPressed: () =>
                                  setState(() => draft.removeAt(index)),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ),
                          ReorderableDragStartListener(
                            index: index,
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(Icons.drag_handle),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          Row(
            children: [
              Expanded(
                child: ThemeRegion.auto(
                  id: "widget_globe_controls_12",
                  label: "OutlinedButton · server_globe.dart",
                  child: OutlinedButton(
                    onPressed: draft.length < _minimumNodes
                        ? null
                        : () => _finishChain(false),
                    child: Text(t('Сохранить')),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ThemeRegion.auto(
                  id: "widget_globe_controls_13",
                  label: "FilledButton · server_globe.dart",
                  child: FilledButton(
                    onPressed:
                        draft.length < _minimumNodes ||
                            widget.onConnectChain == null
                        ? null
                        : () => _finishChain(true),
                    child: Text(t('Подключить')),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  void _showServers(List<_Marker> markers) {
    // Only compact choices here. Technical information opens one location at a time.
    final autoKeys = ref
        .read(automaticSubscriptionConfigsProvider)
        .map((c) => c.uniqueKey)
        .toSet();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => LocationSheetSurface(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .64,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                t(markers.length > 1 ? 'Серверы рядом' : 'Локация'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (!buildingChain)
                for (final config in {
                  for (final m in markers)
                    if (autoKeys.contains(m.config.uniqueKey))
                      m.config.uniqueKey: m.config,
                }.values)
                  ThemeRegion.auto(
                    id: "widget_globe_controls_14",
                    label: "ListTile · server_globe.dart",
                    child: ListTile(
                      leading: const Icon(Icons.auto_awesome),
                      title: FlagText(
                        original: Text('${t('Авто')} · ${config.name}'),
                      ),
                      subtitle: Text(
                        t('Исходный конфиг с автовыбором и правилами подписки'),
                      ),
                      onTap: widget.onConnect == null
                          ? null
                          : () async {
                              Navigator.pop(sheetContext);
                              try {
                                await widget.onConnect?.call(
                                  config,
                                  config.uniqueKey,
                                );
                              } catch (error) {
                                if (mounted)
                                  CustomNotification.show(
                                    context,
                                    '$error',
                                    isError: true,
                                  );
                              }
                            },
                    ),
                  ),
              for (final marker in markers)
                ThemeRegion.auto(
                  id: "widget_globe_controls_15",
                  label: "ListTile · server_globe.dart",
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CountryFlagImage(
                      countryCode: marker.location.countryCode,
                      height: 24,
                    ),
                    title: FlagText(
                      original: Text(
                        marker.endpoint.grouped
                            ? marker.endpoint.label
                            : marker.endpoint.serverName,
                      ),
                    ),
                    subtitle: FlagText(
                      original: Text(
                        [
                          [
                            marker.location.country,
                            marker.location.city,
                          ].where((s) => s.isNotEmpty).join(' · '),
                          if (marker.endpoint.grouped)
                            '${t('Группа серверов')}: ${marker.endpoint.serverName}',
                          if (marker.config.ping >= 0)
                            '${marker.endpoint.grouped ? '${t('Пинг группы')}: ' : ''}${marker.config.ping} ms',
                        ].join('\n'),
                      ),
                    ),
                    onTap: widget.onConnect == null
                        ? null
                        : () {
                            Navigator.pop(sheetContext);
                            _choose(marker);
                          },
                    trailing: ThemeRegion.auto(
                      id: "widget_globe_controls_16",
                      label: "IconButton · server_globe.dart",
                      child: IconButton(
                        tooltip: t('Инфа по локации ^^'),
                        icon: const Icon(Icons.info_outline),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          showIpLocationDetails(context, marker.location);
                        },
                      ),
                    ),
                  ),
                ),
              if (widget.onConnect != null)
                Text(
                  t(
                    buildingChain
                        ? 'Нажмите на сервер, чтобы добавить узел'
                        : 'Нажмите на сервер, чтобы подключиться',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(globeServersProvider);
    final automatic = ref.watch(automaticSubscriptionConfigsProvider);
    final locations =
        ref.watch(serverLocationsProvider).asData?.value ??
        const <String, IpLocation>{};
    final markers = <_Marker>[];
    for (final server in servers) {
      for (final endpoint in serverEndpoints(server)) {
        final location = locations[endpoint.host];
        if (location?.hasCoordinates == true)
          markers.add(_Marker(endpoint, location!, server));
      }
    }
    final savedChains = ref.watch(chainsProvider);
    final runtime = ref.watch(mapSelectionProvider);
    final activeChain = widget.connected
        ? savedChains
              .where(
                (c) => widget.connectedServerKey != null
                    ? widget.connectedServerKey == 'chain:${c.id}'
                    : c.isActive,
              )
              .firstOrNull
        : null;
    ProxyConfig? connectedServer;
    if (widget.connected && activeChain == null) {
      if (runtime != null &&
          (widget.connectedServerKey == runtime.server.uniqueKey ||
              widget.connectedServerKey == null &&
                  runtime.appliesTo(
                    servers.where((s) => s.isActive).firstOrNull?.uniqueKey,
                  )))
        connectedServer = runtime.server;
      connectedServer ??= servers
          .where(
            (s) => widget.connectedServerKey != null
                ? s.uniqueKey == widget.connectedServerKey
                : s.isActive,
          )
          .firstOrNull;
    }
    final connectedLocation = widget.connected
        ? (widget.currentLocation?.hasCoordinates == true
              ? widget.currentLocation
              : locations[connectedServer == null
                    ? null
                    : concreteServerEndpoint(connectedServer)?.host])
        : null;
    final activeRoute = activeChain == null
        ? <IpLocation>[]
        : chainMapLocations(activeChain, locations, exit: connectedLocation);
    for (final hop in draft) {
      final updated = locations[hop.endpoint.host];
      if (updated?.hasCoordinates == true) hop.location = updated!;
    }
    if (buildingChain &&
        _draftFocusPending &&
        draft.any((m) => m.location.hasCoordinates)) {
      _focusRoute(draft.map((m) => m.location).toList(), null);
      _draftFocusPending = false;
    }
    final connectedPoint =
        connectedLocation ??
        (activeRoute.lastOrNull?.hasCoordinates == true
            ? activeRoute.last
            : null);
    if (_focusPending &&
        !buildingChain &&
        (connectedLocation?.hasCoordinates == true ||
            activeRoute.any((p) => p.hasCoordinates)))
      _focusRoute(activeRoute, connectedLocation);
    final projection = GlobeProjection(longitude, latitude);
    final accent = Theme.of(context).colorScheme.primary;
    final theme = ref.watch(themeProvider).currentTheme;
    final water = theme.componentColors['home_map_canvas'] == null
        ? const Color(0xff09283b)
        : Color(theme.componentColors['home_map_canvas']!);
    final land = Color.lerp(theme.surface, theme.primary, .08)!;
    final active = markers
        .where((m) => m.config.isActive && !m.endpoint.grouped)
        .firstOrNull;
    final current =
        widget.currentLocation ?? (widget.fullScreen ? null : active?.location);
    Widget canvas() => LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        final projectedSize = Size(size.width * zoom, size.height * zoom);
        final shift = Offset(
          (size.width - projectedSize.width) / 2,
          (size.height - projectedSize.height) / 2,
        );
        final clusters = _clusters(markers, projection, projectedSize);
        return ThemeRegion(
          id: 'home_map_canvas',
          label: t('Фон глобуса — вода'),
          canvas: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (d) {
              startZoom = zoom;
              _gesturePointers = d.pointerCount;
            },
            onScaleUpdate: (d) => setState(() {
              if (_gesturePointers != d.pointerCount) {
                _gesturePointers = d.pointerCount;
                startZoom = zoom / d.scale;
                return;
              }
              longitude -= d.focalPointDelta.dx / 130 / zoom;
              latitude = (latitude + d.focalPointDelta.dy / 130 / zoom).clamp(
                -1.5,
                1.5,
              );
              zoom = (startZoom * d.scale).clamp(.65, 12.0);
            }),
            onDoubleTap: () =>
                setState(() => zoom = (zoom * 1.7).clamp(.65, 12.0)),
            onTapUp: (d) {
              _Cluster? closest;
              var distance = 34.0;
              for (final c in clusters) {
                final delta = (c.point + shift - d.localPosition).distance;
                if (delta < distance) {
                  closest = c;
                  distance = delta;
                }
              }
              if (closest != null)
                _showServers(closest.markers);
              else if (connectedPoint?.hasCoordinates == true) {
                final (point, depth) = projection.project(
                  connectedPoint!.latitude!,
                  connectedPoint.longitude!,
                  projectedSize,
                );
                if (depth > 0 &&
                    (point + shift - d.localPosition).distance < 22)
                  showIpLocationDetails(context, connectedPoint);
              }
            },
            child: ClipRect(
              child: FutureBuilder<_Geometry>(
                future: geometry,
                builder: (context, snapshot) => RepaintBoundary(
                  child: CustomPaint(
                    painter: _GlobePainter(
                      projection,
                      markers,
                      snapshot.data?.land ?? [],
                      snapshot.data?.borders ?? [],
                      accent,
                      zoom,
                      draft.map((m) => m.location).toList(),
                      activeRoute,
                      connectedPoint,
                      water,
                      land,
                      snapshot.data?.mesh ?? [],
                      _paintCache,
                    ),
                    child: Semantics(
                      label: activeChain != null
                          ? AppLocalizations.text(
                              context,
                              'Глобус серверов. Подключенная цепочка: {0}',
                              args: [activeChain.name],
                            )
                          : connectedPoint != null
                          ? t('Глобус серверов. Подключенная локация')
                          : t('Глобус серверов'),
                      hint: t('Вращайте глобус и нажимайте на локации'),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    final controls = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ThemeRegion.auto(
          id: "widget_globe_controls_17",
          label: "IconButton · server_globe.dart",
          child: IconButton(
            tooltip: t('Приблизить'),
            icon: const Icon(Icons.add),
            onPressed: () =>
                setState(() => zoom = (zoom * 1.5).clamp(.65, 12.0)),
          ),
        ),
        ThemeRegion.auto(
          id: "widget_globe_controls_18",
          label: "IconButton · server_globe.dart",
          child: IconButton(
            tooltip: t('Отдалить'),
            icon: const Icon(Icons.remove),
            onPressed: () =>
                setState(() => zoom = (zoom / 1.5).clamp(.65, 12.0)),
          ),
        ),
        if (widget.connected &&
            (connectedLocation?.hasCoordinates == true ||
                activeRoute.any((p) => p.hasCoordinates)))
          ThemeRegion.auto(
            id: "widget_globe_controls_19",
            label: "IconButton · server_globe.dart",
            child: IconButton(
              tooltip: t('Показать подключение'),
              icon: const Icon(Icons.my_location),
              onPressed: () =>
                  setState(() => _focusRoute(activeRoute, connectedLocation)),
            ),
          ),
        if (!buildingChain && widget.onConnect != null && automatic.isNotEmpty)
          ThemeRegion.auto(
            id: "widget_globe_controls_20",
            label: "IconButton · server_globe.dart",
            child: IconButton(
              tooltip: t('Авто из подписок'),
              icon: const Icon(Icons.auto_awesome),
              onPressed: () => _showAuto(automatic),
            ),
          ),
        if (!buildingChain)
          ThemeRegion.auto(
            id: "widget_globe_controls_21",
            label: "IconButton · server_globe.dart",
            child: IconButton(
              tooltip: t('Мои цепочки'),
              onPressed: _showSavedChains,
              icon: const Icon(Icons.folder_copy_outlined),
            ),
          ),
        ThemeRegion.auto(
          id: "widget_globe_controls_22",
          label: "IconButton · server_globe.dart",
          child: IconButton(
            tooltip: t(
              buildingChain ? 'Завершить построение' : 'Строить цепочку',
            ),
            icon: Icon(buildingChain ? Icons.close : Icons.add_road),
            onPressed: () => _setBuilding(!buildingChain),
          ),
        ),
      ],
    );
    final info = current == null
        ? null
        : TextButton.icon(
            onPressed: () => showIpLocationDetails(context, current),
            icon: CountryFlagImage(countryCode: current.countryCode),
            label: Text(
              [
                current.city,
                current.country,
              ].where((s) => s.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              backgroundColor: Theme.of(context).colorScheme.surface
                  .withValues(alpha: .15),
            ),
          );
    return RepaintBoundary(
      child: widget.fullScreen
          ? Stack(
              fit: StackFit.expand,
              children: [
                canvas(),
                if (buildingChain)
                  Positioned(
                    bottom: MediaQuery.paddingOf(context).bottom + 12,
                    left: 12,
                    right: 12,
                    child: _draftPanel(),
                  ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 90,
                  left: 20,
                  right: 75,
                  child: Align(alignment: Alignment.centerLeft, child: info),
                ),
                Positioned(
                  top: MediaQuery.sizeOf(context).height * .3,
                  right: 12,
                  child: controls,
                ),
              ],
            )
          : SizedBox(
              height: 220,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  canvas(),
                  Positioned(top: 0, right: 0, child: controls),
                  if (info != null)
                    Positioned(bottom: 0, left: 12, right: 52, child: info),
                ],
              ),
            ),
    );
  }
}

class LocationDetails extends StatelessWidget {
  final IpLocation location;
  final String host;
  const LocationDetails({super.key, required this.location, this.host = ''});
  @override
  Widget build(BuildContext context) {
    final l = location;
    final rows = <String, String>{
      if (host.isNotEmpty) 'Сервер': host,
      'IP': l.ip,
      'Страна': l.country,
      'Город': l.city,
      'Регион': l.region,
      if (l.latitude != null) 'Широта': '${l.latitude}',
      if (l.longitude != null) 'Долгота': '${l.longitude}',
      'Часовой пояс': l.timezone,
      'UTC': l.utc,
      'Телефонный код': l.callingCode.isEmpty
          ? ''
          : '+${l.callingCode.replaceFirst('+', '')}',
      'Индекс': l.postal,
      'Провайдер': l.isp,
    };
    return Column(
      children: [
        for (final row in rows.entries.where((e) => e.value.isNotEmpty))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    AppLocalizations.text(context, row.key),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: SelectableText(row.value)),
              ],
            ),
          ),
      ],
    );
  }
}

int _globeProjectionFrame = 0;

class _GlobePainter extends CustomPainter {
  final GlobeProjection projection;
  final List<_Marker> markers;
  final List<List<Offset>> land, borders;
  final Color accent;
  final double zoom;
  final List<IpLocation> route, activeRoute;
  final IpLocation? connectedLocation;
  final Color water, landColor;
  final List<List<_LandVertex>> mesh;
  final _GlobePaintCache cache;
  _GlobePainter(
    this.projection,
    this.markers,
    this.land,
    this.borders,
    this.accent,
    this.zoom,
    this.route,
    this.activeRoute,
    this.connectedLocation,
    this.water,
    this.landColor,
    this.mesh,
    this.cache,
  );
  @override
  void paint(Canvas output, Size size) {
    String point(IpLocation p) => '${p.latitude},${p.longitude}';
    final key = (
      size,
      projection.longitude,
      projection.latitude,
      zoom,
      accent,
      water,
      landColor,
      identityHashCode(mesh),
      markers
          .map(
            (m) =>
                '${m.config.uniqueKey}:${m.config.isActive}:${point(m.location)}',
          )
          .join('|'),
      route.map(point).join('|'),
      activeRoute.map(point).join('|'),
      connectedLocation == null ? '' : point(connectedLocation!),
    );
    if (cache.key == key && cache.picture != null) {
      output.drawPicture(cache.picture!);
      return;
    }
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final full = Size(size.width * zoom, size.height * zoom);
    canvas.save();
    canvas.translate(
      (size.width - full.width) / 2,
      (size.height - full.height) / 2,
    );
    final center = Offset(full.width / 2, full.height / 2),
        r = math.min(full.width, full.height) * .44;
    final bounds = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r + 4,
      Paint()
        ..shader = RadialGradient(
          colors: [accent.withValues(alpha: .16), Colors.transparent],
        ).createShader(Rect.fromCircle(center: center, radius: r + 4)),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.4, -.4),
          colors: [
            Color.lerp(water, Colors.white, .08)!,
            Color.lerp(water, Colors.black, .35)!,
          ],
        ).createShader(bounds),
    );
    final grid = Paint()
      ..color = accent.withValues(alpha: .16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .5;
    void line(List<Offset> coordinates, Paint paint) {
      final path = Path();
      var started = false;
      for (final pair in coordinates) {
        final (p, z) = projection.project(pair.dy, pair.dx, full);
        if (z < 0) {
          started = false;
          continue;
        }
        if (started)
          path.lineTo(p.dx, p.dy);
        else {
          path.moveTo(p.dx, p.dy);
          started = true;
        }
      }
      canvas.drawPath(path, paint);
    }

    for (var lat = -60; lat <= 60; lat += 30) {
      line([
        for (var lon = -180; lon <= 180; lon += 3)
          Offset(lon.toDouble(), lat.toDouble()),
      ], grid);
    }
    for (var lon = -180; lon < 180; lon += 30) {
      line([
        for (var lat = -90; lat <= 90; lat += 3)
          Offset(lon.toDouble(), lat.toDouble()),
      ], grid);
    }
    final vertices = <Offset>[];
    final sinLon = math.sin(projection.longitude),
        cosLon = math.cos(projection.longitude);
    final sinLat = math.sin(projection.latitude),
        cosLat = math.cos(projection.latitude);
    final frame = ++_globeProjectionFrame;
    (Offset, double) projectVertex(_LandVertex v) {
      if (v.frame == frame) return v.projected!;
      v.frame = frame;
      final forward = v.x * sinLon + v.z * cosLon;
      return v.projected = (
        center +
            Offset(
              (v.x * cosLon - v.z * sinLon) * r,
              -(v.y * cosLat - forward * sinLat) * r,
            ),
        forward * cosLat + v.y * sinLat,
      );
    }

    for (final triangle in mesh) {
      final projected = triangle.map(projectVertex).toList();
      final polygon = <Offset>[];
      for (var i = 0; i < 3; i++) {
        final a = projected[(i + 2) % 3], b = projected[i];
        if ((a.$2 >= 0) != (b.$2 >= 0)) {
          final point = Offset.lerp(a.$1, b.$1, a.$2 / (a.$2 - b.$2))!;
          polygon.add(point);
        }
        if (b.$2 >= 0) polygon.add(b.$1);
      }
      for (var i = 1; i + 1 < polygon.length; i++)
        vertices.addAll([polygon.first, polygon[i], polygon[i + 1]]);
    }
    if (vertices.isNotEmpty)
      canvas.drawVertices(
        Vertices(VertexMode.triangles, vertices),
        BlendMode.srcOver,
        Paint()..color = landColor,
      );
    final coast = Paint()
      ..color = Colors.white.withValues(alpha: .5)
      ..strokeWidth = .85
      ..style = PaintingStyle.stroke;
    for (final ring in land) line(ring, coast);
    final border = Paint()
      ..color = Colors.white.withValues(alpha: .28)
      ..strokeWidth = .6
      ..style = PaintingStyle.stroke;
    for (final boundary in borders) line(boundary, border);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = accent.withValues(alpha: .4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    void drawRoute(List<IpLocation> hops, Color color, double width) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = width
        ..style = PaintingStyle.stroke;
      for (var i = 1; i < hops.length; i++) {
        final a = hops[i - 1], b = hops[i];
        if (!a.hasCoordinates || !b.hasCoordinates) continue;
        var delta = b.longitude! - a.longitude!;
        if (delta > 180) delta -= 360;
        if (delta < -180) delta += 360;
        line([
          for (var step = 0; step <= 40; step++)
            Offset(
              a.longitude! + delta * step / 40,
              a.latitude! + (b.latitude! - a.latitude!) * step / 40,
            ),
        ], paint);
      }
    }

    drawRoute(activeRoute, const Color(0xff65e6a3), 3);
    drawRoute(route, const Color(0xffffbf69), 2);
    for (final cluster in _clusters(markers, projection, full)) {
      final p = cluster.point;
      final color = accent;
      final count = cluster.markers.length;
      final radius = count > 1 ? 11.0 : 4.5;
      canvas.drawCircle(
        p,
        radius + 4,
        Paint()..color = color.withValues(alpha: .2),
      );
      canvas.drawCircle(p, radius, Paint()..color = color);
      canvas.drawCircle(
        p,
        radius,
        Paint()
          ..color = Colors.white.withValues(alpha: .75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8,
      );
      if (count > 1) {
        final text = TextPainter(
          text: TextSpan(
            text: '$count',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, p - Offset(text.width / 2, text.height / 2));
      }
    }
    for (var i = 0; i < route.length; i++) {
      if (!route[i].hasCoordinates) continue;
      final (p, z) = projection.project(
        route[i].latitude!,
        route[i].longitude!,
        full,
      );
      if (z > 0) {
        canvas.drawCircle(p, 14, Paint()..color = const Color(0xff176444));
        final text = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, p - Offset(text.width / 2, text.height / 2));
      }
    }

    for (var i = 0; i < activeRoute.length; i++) {
      if (!activeRoute[i].hasCoordinates) continue;
      final (p, z) = projection.project(
        activeRoute[i].latitude!,
        activeRoute[i].longitude!,
        full,
      );
      if (z <= 0) continue;
      canvas.drawCircle(p, 8, Paint()..color = const Color(0xff65e6a3));
      final label = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, p - Offset(label.width / 2, label.height / 2));
    }
    if (connectedLocation?.hasCoordinates == true) {
      final location = connectedLocation!;
      final (p, z) = projection.project(
        location.latitude!,
        location.longitude!,
        full,
      );
      if (z > 0) {
        canvas.drawCircle(
          p,
          21,
          Paint()..color = const Color(0xff65e6a3).withValues(alpha: .2),
        );
        canvas.drawCircle(
          p,
          13,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        canvas.drawCircle(p, 8, Paint()..color = const Color(0xff65e6a3));
        canvas.drawLine(
          p + const Offset(-3, 0),
          p + const Offset(-.5, 3),
          Paint()
            ..color = Colors.black
            ..strokeWidth = 2,
        );
        canvas.drawLine(
          p + const Offset(-.5, 3),
          p + const Offset(4, -3),
          Paint()
            ..color = Colors.black
            ..strokeWidth = 2,
        );
      }
    }
    canvas.restore();
    cache.picture?.dispose();
    cache.picture = recorder.endRecording();
    cache.key = key;
    output.drawPicture(cache.picture!);
  }

  @override
  bool shouldRepaint(covariant _GlobePainter old) => true;
}

class LocationSheetSurface extends StatelessWidget {
  final Widget child;
  const LocationSheetSurface({super.key, required this.child});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .28),
        child: child,
      ),
    ),
  );
}

void showIpLocationDetails(BuildContext context, IpLocation location) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: LocationSheetSurface(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .75,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CountryFlagImage(countryCode: location.countryCode),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppLocalizations.text(context, 'Инфа по локации ^^'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LocationDetails(location: location),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
