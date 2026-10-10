/// Map Provider Settings section — Phase 1 (map_provider_rollout_plan.md §4)
///
/// Embedded inside PlatformSettingsPage. Owns the full draft→save lifecycle:
/// load config → draft edits → client validation → confirmations → PUT via
/// MapConfigService (server re-validates + optimistic revision lock) →
/// update snapshot + history. Unsaved edits are guarded by PopScope; stale
/// saves surface a conflict banner with reload instead of overwriting.
///
/// No renderer is switched by this widget in Phase 1 — saving only persists
/// the document. Runtime wiring lands in Phase 2+.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../services/map_config_service.dart';
import '../../../../shared/widgets/glass/glass_confirm_dialog.dart';
import '../../models/map_provider_config.dart';

class MapProviderSettingsSection extends StatefulWidget {
  final MapConfigService? service;

  const MapProviderSettingsSection({super.key, this.service});

  @override
  State<MapProviderSettingsSection> createState() =>
      _MapProviderSettingsSectionState();
}

class _MapProviderSettingsSectionState extends State<MapProviderSettingsSection> {
  late final MapConfigService _service =
      widget.service ?? MapConfigService();

  final _reasonCtrl = TextEditingController();

  // §4.4 state model
  MapConfigSnapshot? _snapshot; // last saved state from the server
  MapProviderConfig? _draft; // in-memory edits
  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  List<String> _saveErrors = const [];
  int? _conflictRevision; // newer revision someone else saved
  List<MapConfigRevision>? _history;

  MapProviderConfig? get _saved => _snapshot?.config;
  TileSourceRegistry get _registry =>
      _snapshot?.registry ?? TileSourceRegistry.defaults();
  MapLayerRegistry get _layerRegistry =>
      _snapshot?.mapLayers ?? MapLayerRegistry.defaults();
  bool get _dirty =>
      _draft != null && _saved != null && !_draft!.isSameConfig(_saved!);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _loadError = null;
      _conflictRevision = null;
    });
    try {
      final snap = await _service.load(admin: true, forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _draft = snap.config;
        _loading = false;
        _saveErrors = const [];
      });
      unawaited(_loadHistory());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _loadHistory() async {
    final items = await _service.history();
    if (!mounted) return;
    setState(() => _history = items);
  }

  void _edit(MapProviderConfig next) => setState(() {
        _draft = next;
        _saveErrors = const [];
      });

  // ── Save flow ─────────────────────────────────────────────────────────

  Future<void> _onSave() async {
    final draft = _draft;
    final saved = _saved;
    if (draft == null || saved == null || _saving) return;
    if (_snapshot?.isAppDefault == true) return;

    final validation = draft.validate(_registry);
    if (!validation.isValid) {
      setState(() => _saveErrors = validation.errors);
      return;
    }

    // §4.5 confirmations — collect acknowledgements the server requires.
    final needGoogleWeb = draft.platformDefaults[MapPlatform.web]?.enabled ==
            true &&
        draft.platformDefaults[MapPlatform.web]?.renderer == MapRendererKind.google;
    final needOsmTraffic = validation.usesOsm;
    if (needGoogleWeb || needOsmTraffic) {
      final confirmed = await _confirmSaveDialog(
        needGoogleWeb: needGoogleWeb,
        needOsmTraffic: needOsmTraffic,
      );
      if (confirmed != true || !mounted) return;
    }

    if (draft.environment == 'prod' && _reasonCtrl.text.trim().isEmpty) {
      setState(() => _saveErrors = const ['กรุณาระบุเหตุผลของการเปลี่ยนแปลง']);
      return;
    }

    setState(() {
      _saving = true;
      _saveErrors = const [];
    });
    final result = await _service.save(
      draft,
      expectedRevision: saved.revision,
      reason: _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      confirmations: {
        if (needGoogleWeb) 'googleWebBudget': true,
        if (needOsmTraffic) 'osmNoTraffic': true,
      },
    );
    if (!mounted) return;

    switch (result) {
      case MapConfigSaved():
        setState(() {
          _saving = false;
          _snapshot = MapConfigSnapshot(
            config: result.config,
            registry: _snapshot!.registry,
            mapLayers: _snapshot!.mapLayers,
          );
          _draft = result.config;
          _reasonCtrl.clear();
        });
        unawaited(_loadHistory());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกการตั้งค่าแล้ว')),
        );
      case MapConfigConflict():
        setState(() {
          _saving = false;
          _conflictRevision = result.currentRevision;
        });
      case MapConfigValidationFailed():
        setState(() {
          _saving = false;
          _saveErrors = result.errors;
        });
      case MapConfigUnauthorized():
        setState(() {
          _saving = false;
          _saveErrors = [result.message];
        });
      case MapConfigSaveError():
        setState(() {
          _saving = false;
          _saveErrors = [result.message];
        });
    }
  }

  Future<bool?> _confirmSaveDialog({
    required bool needGoogleWeb,
    required bool needOsmTraffic,
  }) {
    var googleWebOk = !needGoogleWeb;
    var osmTrafficOk = !needOsmTraffic;
    return GlassConfirmDialog.show(
      context,
      title: 'ยืนยันการบันทึก',
      content: StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (needGoogleWeb)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'ยืนยันว่ามี Google key และงบที่อนุมัติสำหรับ Web',
                  style: TextStyle(fontSize: 13),
                ),
                value: googleWebOk,
                onChanged: (v) => setDialogState(() => googleWebOk = v ?? false),
              ),
            if (needOsmTraffic)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'ยืนยันว่าเข้าใจ: แผนที่ OSM ไม่มีข้อมูลจราจรแบบเรียลไทม์',
                  style: TextStyle(fontSize: 13),
                ),
                value: osmTrafficOk,
                onChanged: (v) => setDialogState(() => osmTrafficOk = v ?? false),
              ),
          ],
        ),
      ),
      accentColor: AppColors.primary,
      cancelLabel: 'ยกเลิก',
      confirmLabel: 'บันทึก',
    ).then((v) => v == true && googleWebOk && osmTrafficOk);
  }

  Future<void> _onRollback(MapConfigRevision rev) async {
    final ok = await GlassConfirmDialog.show(
      context,
      title: 'ย้อนกลับไป revision ${rev.revision}?',
      content: Text(
        'การตั้งค่าจะถูกแทนด้วยค่าจากประวัติ\nเหตุผลเดิม: ${rev.reason ?? '—'}',
        style: const TextStyle(fontSize: 13),
      ),
      accentColor: Colors.orange,
      cancelLabel: 'ยกเลิก',
      confirmLabel: 'ย้อนกลับ',
    );
    if (ok != true || !mounted || _saved == null) return;
    final result = await _service.rollback(
      rev.id,
      expectedRevision: _saved!.revision,
      reason: 'Rollback ไป revision ${rev.revision}',
    );
    if (!mounted) return;
    switch (result) {
      case MapConfigSaved():
        setState(() {
          _snapshot = MapConfigSnapshot(
            config: result.config,
            registry: _snapshot!.registry,
            mapLayers: _snapshot!.mapLayers,
          );
          _draft = result.config;
        });
        unawaited(_loadHistory());
      case MapConfigConflict():
        setState(() => _conflictRevision = result.currentRevision);
      default:
        setState(() => _saveErrors = const ['ย้อนกลับไม่สำเร็จ — ลองใหม่อีกครั้ง']);
    }
  }

  Future<void> _showTestMap(MapTarget target) async {
    final src = _registry[target.tileSourceId];
    if (target.renderer == MapRendererKind.google || src == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 560,
          height: 420,
          child: Column(
            children: [
              Expanded(
                child: FlutterMap(
                  options: const MapOptions(
                    initialCenter: LatLng(13.7563, 100.5018),
                    initialZoom: 12,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: src.urlTemplate,
                      userAgentPackageName: 'com.sheserved.mapsmoke',
                      maxNativeZoom: src.maxNativeZoom,
                    ),
                    RichAttributionWidget(
                      attributions: [TextSourceAttribution(src.attribution)],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'ตัวอย่าง: ${src.label} — ตรวจ CORS/attribution ก่อนบันทึก',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !_dirty) return;
        final discard = await GlassConfirmDialog.show(
          context,
          title: 'มีการแก้ไขที่ยังไม่ได้บันทึก',
          content: const Text('ออกจากหน้านี้จะทำให้การแก้ไขหายไป'),
          accentColor: Colors.redAccent,
          cancelLabel: 'อยู่ต่อ',
          confirmLabel: 'ทิ้งการแก้ไข',
        );
        if (discard == true && mounted) {
          setState(() => _draft = _saved);
          if (mounted) Navigator.of(this.context).maybePop();
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          if (_loading) _buildSkeleton(),
          if (!_loading && _loadError != null) _buildLoadError(),
          if (!_loading && _loadError == null && _draft != null) ..._buildBody(),
        ],
      ),
    );
  }

  List<Widget> _buildBody() => [
        if (_snapshot?.isAppDefault == true) _defaultBanner(),
        if (_conflictRevision != null) _conflictBanner(),
        _statusBanner(),
        const SizedBox(height: 20),
        _sectionTitle('ค่าเริ่มต้นตามแพลตฟอร์ม', Icons.devices),
        const SizedBox(height: 8),
        for (final p in MapPlatform.values) _platformCard(p),
        const SizedBox(height: 20),
        _sectionTitle('การตั้งค่าเฉพาะระบบ', Icons.tune),
        const SizedBox(height: 8),
        for (final f in MapFeature.values) _featureCard(f),
        _yieldWayLockedRow(),
        const SizedBox(height: 20),
        _sectionTitle('ฟีเจอร์แผนที่ (Feature Gates)', Icons.extension),
        const SizedBox(height: 8),
        _incidentMapGateCard(),
        _mapLayersCard(),
        const SizedBox(height: 20),
        _sectionTitle('บริการประกอบ (เส้นทาง / ค้นหา / จราจร)', Icons.alt_route),
        const SizedBox(height: 8),
        _servicesCard(),
        const SizedBox(height: 20),
        _sectionTitle('นโยบายเมื่อโหลดไม่สำเร็จ', Icons.report_gmailerrorred),
        const SizedBox(height: 8),
        _fallbackCard(),
        const SizedBox(height: 20),
        _sectionTitle('ค่าที่จะใช้จริง (Preview)', Icons.preview),
        const SizedBox(height: 8),
        _effectiveTable(),
        const SizedBox(height: 20),
        _sectionTitle('ประวัติการตั้งค่า', Icons.history),
        const SizedBox(height: 8),
        _historyList(),
        if (_dirty) ...[
          const SizedBox(height: 20),
          _saveBar(),
        ],
      ];

  Widget _buildHeader() => const Row(
        children: [
          Icon(Icons.map, color: AppColors.primary, size: 22),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'ผู้ให้บริการแผนที่ (Map Provider)',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );

  Widget _sectionTitle(String text, IconData icon) => Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ),
        ],
      );

  Widget _buildSkeleton() => Column(
        children: List.generate(
          3,
          (i) => Container(
            height: 88,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      );

  Widget _buildLoadError() => _card(
        Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(width: 12),
            const Expanded(child: Text('โหลดการตั้งค่าไม่ได้ — ใช้ค่า default')),
            TextButton(onPressed: () => _load(forceRefresh: true), child: const Text('ลองใหม่')),
          ],
        ),
      );

  Widget _defaultBanner() => _banner(
        color: Colors.orange,
        icon: Icons.cloud_off,
        text:
            'เชื่อมต่อ server ไม่ได้ — แสดงค่า default ที่ฝังในแอป การแก้ไขจะยังไม่ถูกบันทึก',
      );

  Widget _conflictBanner() => _banner(
        color: Colors.redAccent,
        icon: Icons.sync_problem,
        text:
            'มีการบันทึกจากผู้ใช้อื่นหลังจากคุณเริ่มแก้ไข (revision $_conflictRevision)',
        trailing: TextButton(
          onPressed: () => _load(forceRefresh: true),
          child: const Text('โหลดใหม่', style: TextStyle(color: Colors.redAccent)),
        ),
      );

  Widget _statusBanner() => _card(
        Row(
          children: [
            _chip(_saved?.environment.toUpperCase() ?? 'DEV', Colors.blueGrey),
            const SizedBox(width: 8),
            _chip('rev ${_saved?.revision ?? '-'}', AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'iOS/Android: ${_rendererLabel(MapPlatform.ios)} · Web: ${_rendererLabel(MapPlatform.web)}',
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'โหลดการตั้งค่าใหม่',
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: _saving ? null : () => _load(forceRefresh: true),
            ),
          ],
        ),
      );

  String _rendererLabel(MapPlatform p) {
    final t = _draft?.platformDefaults[p];
    if (t == null || !t.enabled) return 'ปิด';
    if (t.renderer == MapRendererKind.google) return 'Google';
    return 'OSM · ${_registry[t.tileSourceId]?.label ?? t.tileSourceId}';
  }

  // ── Platform defaults ────────────────────────────────────────────────

  Widget _platformCard(MapPlatform platform) {
    final t = _draft!.platformDefaults[platform] ??
        const MapTarget(enabled: false, renderer: MapRendererKind.google);
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: 'เปิดแผนที่บน ${platform.labelTh}',
                  child: Text(
                    platform.labelTh,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
              Switch.adaptive(
                value: t.enabled,
                onChanged: _saving
                    ? null
                    : (v) => _edit(_draft!.copyWith(platformDefaults: {
                            ..._draft!.platformDefaults,
                            platform: t.copyWith(enabled: v),
                          })),
                activeThumbColor: AppColors.success,
              ),
            ],
          ),
          if (t.enabled) ...[
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SegmentedButton<MapRendererKind>(
                segments: const [
                  ButtonSegment(
                      value: MapRendererKind.google,
                      label: Text('Google'),
                      icon: Icon(Icons.map_outlined, size: 16)),
                  ButtonSegment(
                      value: MapRendererKind.osm,
                      label: Text('OSM'),
                      icon: Icon(Icons.public, size: 16)),
                ],
                selected: {t.renderer},
                onSelectionChanged: _saving
                    ? null
                    : (sel) => _edit(_draft!.copyWith(platformDefaults: {
                          ..._draft!.platformDefaults,
                          platform: t.copyWith(
                            renderer: sel.first,
                            tileSourceId: () => sel.first == MapRendererKind.osm
                                ? (t.tileSourceId ?? 'osm_standard')
                                : t.tileSourceId,
                          ),
                        })),
              ),
            ),
            if (t.renderer == MapRendererKind.osm) ...[
              const SizedBox(height: 12),
              _tileSourcePicker(
                selected: t.tileSourceId,
                onChanged: (id) => _edit(_draft!.copyWith(platformDefaults: {
                      ..._draft!.platformDefaults,
                      platform: t.copyWith(tileSourceId: () => id),
                    })),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: const Text('ทดสอบแผนที่'),
                  onPressed: () => _showTestMap(t),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _tileSourcePicker({
    required String? selected,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownMenu<String>(
      initialSelection: selected,
      expandedInsets: EdgeInsets.zero,
      label: const Text('Tile source'),
      onSelected: _saving
          ? null
          : (id) {
              if (id != null) onChanged(id);
            },
      dropdownMenuEntries: [
        for (final s in _registry.sources.values)
          DropdownMenuEntry(
            value: s.id,
            label: s.readiness == TileSourceReadiness.needsKey
                ? '${s.label} (ต้องมี API key)'
                : s.label,
            enabled: s.selectable,
          ),
      ],
    );
  }

  // ── Feature overrides ────────────────────────────────────────────────

  Widget _featureCard(MapFeature feature) {
    final o = _draft!.featureOverrides[feature] ?? const FeatureOverride.inherit();
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(feature.labelTh,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('ใช้ค่าของแพลตฟอร์ม'),
                selected: !o.isOverride,
                onSelected: _saving
                    ? null
                    : (_) => _edit(_draft!.copyWith(featureOverrides: {
                          ..._draft!.featureOverrides,
                          feature: const FeatureOverride.inherit(),
                        })),
              ),
              ChoiceChip(
                label: const Text('กำหนดเอง'),
                selected: o.isOverride,
                onSelected: _saving
                    ? null
                    : (_) => _edit(_draft!.copyWith(featureOverrides: {
                          ..._draft!.featureOverrides,
                          feature: const FeatureOverride.override(
                            renderer: MapRendererKind.google,
                          ),
                        })),
              ),
            ],
          ),
          if (o.isOverride) ...[
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SegmentedButton<MapRendererKind>(
                segments: const [
                  ButtonSegment(value: MapRendererKind.google, label: Text('Google')),
                  ButtonSegment(value: MapRendererKind.osm, label: Text('OSM')),
                ],
                selected: {o.renderer},
                onSelectionChanged: _saving
                    ? null
                    : (sel) => _edit(_draft!.copyWith(featureOverrides: {
                          ..._draft!.featureOverrides,
                          feature: FeatureOverride.override(
                            renderer: sel.first,
                            tileSourceId: sel.first == MapRendererKind.osm
                                ? (o.tileSourceId ?? 'osm_standard')
                                : o.tileSourceId,
                          ),
                        })),
              ),
            ),
            if (o.renderer == MapRendererKind.osm) ...[
              const SizedBox(height: 10),
              _tileSourcePicker(
                selected: o.tileSourceId,
                onChanged: (id) => _edit(_draft!.copyWith(featureOverrides: {
                      ..._draft!.featureOverrides,
                      feature: FeatureOverride.override(
                        renderer: MapRendererKind.osm,
                        tileSourceId: id,
                      ),
                    })),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _yieldWayLockedRow() => _card(
        Row(
          children: [
            const Icon(Icons.lock_outline, size: 16, color: Colors.grey),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Yield Way — สืบทอดจาก Emergency เสมอ (ล็อกไม่ให้แก้แยก)',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ),
          ],
        ),
      );

  /// §22.6 — server-driven feature gate for the per-category
  /// "แผนที่เกิดเหตุ" entry (VIDEO_SYSTEM_PLAN.md §22.9: must be
  /// switchable off without redeploying).
  Widget _incidentMapGateCard() {
    final enabled = _draft!.incidentOverviewMapEnabled;
    return _card(
      Row(
        children: [
          const Icon(Icons.map_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'แผนที่เกิดเหตุ (Incident Overview Map)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'แสดงปุ่ม "แผนที่เกิดเหตุ" ใต้แต่ละประเภทเหตุในหน้าเหตุฉุกเฉิน',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: enabled,
            onChanged: (v) =>
                _edit(_draft!.copyWith(incidentOverviewMapEnabled: v)),
          ),
        ],
      ),
    );
  }

  /// §24.A — global switches for the optional incident-map data layers.
  /// The server registry (`snapshot.mapLayers`) decides which layers exist
  /// and where they may be enabled; saving still goes through the normal
  /// config PUT so revision lock + audit apply. Layers the registry marks
  /// needs_key stay disabled until the server deploys the missing asset.
  Widget _mapLayersCard() {
    final locked = _saving || _snapshot?.isAppDefault == true;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.layers_outlined, size: 18, color: AppColors.primary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ชั้นข้อมูลบนแผนที่ (Map Data Layers)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'ชั้นข้อมูลเสริมบนแผนที่เกิดเหตุ — เมื่อเปิด ผู้ใช้เลือกแสดงเองเป็นราย session',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 6),
          for (final layer in _layerRegistry.layers.values)
            _layerRow(layer, locked: locked),
        ],
      ),
    );
  }

  Widget _layerRow(MapLayer layer, {required bool locked}) {
    final enabled = _draft!.featureGateEnabled(layer.id);
    final String? blockedNote;
    if (layer.readiness == TileSourceReadiness.needsKey) {
      blockedNote = 'ต้องมี credential/license จากผู้ให้ข้อมูล — server ยังไม่พร้อม';
    } else if (layer.prodBlocked(_draft!.environment)) {
      blockedNote = 'ใช้ได้เฉพาะ dev/staging';
    } else {
      blockedNote = null;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  layer.label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                Text(
                  blockedNote ??
                      '${layer.source} · ${layer.type}${layer.minZoom > 0 ? ' · zoom ${layer.minZoom}+' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: blockedNote != null
                        ? Colors.orange.shade800
                        : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            key: Key('map-layer-switch-${layer.id}'),
            value: enabled,
            onChanged: locked || blockedNote != null
                ? null
                : (v) => _edit(_draft!.withFeatureGate(layer.id, v)),
          ),
        ],
      ),
    );
  }

  // ── Services / fallback ──────────────────────────────────────────────

  Widget _servicesCard() {
    final s = _draft!.services;
    return _card(
      Column(
        children: [
          _serviceRow(
            'เส้นทาง (Routing)',
            s.routingProvider,
            const {
              'google_directions': 'Google Directions',
              'osrm': 'OSRM',
              'off': 'ปิดใช้งาน',
            },
            (v) => _edit(_draft!.copyWith(services: s.copyWith(routingProvider: v))),
          ),
          _serviceRow(
            'ค้นหาสถานที่ (Search)',
            s.searchPrimary,
            const {
              'nominatim': 'Nominatim (OSM)',
              'google_places': 'Google Places',
            },
            (v) => _edit(_draft!.copyWith(services: s.copyWith(searchPrimary: v))),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Flexible(
                  child: Text('Places fallback', style: TextStyle(fontSize: 12)),
                ),
                Switch.adaptive(
                  value: s.searchFallbackEnabled,
                  onChanged: _saving
                      ? null
                      : (v) => _edit(
                          _draft!.copyWith(services: s.copyWith(searchFallbackEnabled: v))),
                  activeThumbColor: AppColors.success,
                ),
              ],
            ),
          ),
          _serviceRow(
            'ข้อมูลจราจร (Traffic)',
            s.trafficProvider,
            const {'google': 'Google', 'none': 'ไม่มี'},
            (v) => _edit(_draft!.copyWith(services: s.copyWith(trafficProvider: v))),
          ),
          if (_draft!.validate(_registry).usesOsm)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'แผนที่ OSM ไม่มีข้อมูลจราจรแบบเรียลไทม์',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _serviceRow(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> onChanged, {
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(flex: 2, child: Text(label, style: const TextStyle(fontSize: 13))),
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  initialValue: options.containsKey(value) ? value : options.keys.first,
                  isDense: true,
                  isExpanded: true,
                  items: [
                    for (final e in options.entries)
                      DropdownMenuItem(
                          value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13))),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) {
                          if (v != null) onChanged(v);
                        },
                ),
              ),
            ],
          ),
          if (trailing != null) Align(alignment: Alignment.centerRight, child: trailing),
        ],
      ),
    );
  }

  Widget _fallbackCard() {
    final fb = _draft!.fallback;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Fallback provider',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              Switch.adaptive(
                value: fb.enabled,
                onChanged: _saving
                    ? null
                    : (v) => _edit(_draft!.copyWith(
                        fallback: fb.copyWith(
                          enabled: v,
                          providerId: () => v ? (fb.providerId ?? 'google') : fb.providerId,
                        ))),
                activeThumbColor: AppColors.success,
              ),
            ],
          ),
          if (fb.enabled)
            DropdownButtonFormField<String>(
              initialValue: fb.providerId ?? 'google',
              isDense: true,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'google', child: Text('Google')),
                DropdownMenuItem(value: 'osm', child: Text('OSM')),
              ],
              onChanged: _saving
                  ? null
                  : (v) => _edit(_draft!.copyWith(fallback: fb.copyWith(providerId: () => v))),
            )
          else
            Text(
              'ไม่สลับผู้ให้บริการอัตโนมัติ — tile โหลดไม่ได้จะแสดงสถานะผิดพลาด',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }

  // ── Effective preview ────────────────────────────────────────────────

  Widget _effectiveTable() {
    return _card(
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 32,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 44,
          columns: const [
            DataColumn(label: Text('ระบบ')),
            DataColumn(label: Text('Web')),
            DataColumn(label: Text('iOS')),
            DataColumn(label: Text('Android')),
          ],
          rows: [
            for (final f in MapFeature.values)
              DataRow(cells: [
                DataCell(Text(f.labelTh, style: const TextStyle(fontSize: 12))),
                for (final p in MapPlatform.values) _effectiveCell(f, p),
              ]),
            DataRow(cells: [
              const DataCell(Text('Yield Way', style: TextStyle(fontSize: 12))),
              for (final p in MapPlatform.values) _effectiveCell(MapFeature.emergency, p, inheritedNote: 'ตาม Emergency'),
            ]),
          ],
        ),
      ),
    );
  }

  DataCell _effectiveCell(MapFeature f, MapPlatform p, {String? inheritedNote}) {
    final t = _draft!.resolveTarget(f, p);
    final overridden = _draft!.featureOverrides[f]?.isOverride == true;
    final label = !t.enabled
        ? 'ปิด'
        : t.renderer == MapRendererKind.google
            ? 'Google'
            : 'OSM · ${_registry[t.tileSourceId]?.label ?? t.tileSourceId}';
    return DataCell(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        if (overridden)
          const Text('override', style: TextStyle(fontSize: 10, color: Colors.orange))
        else if (inheritedNote != null)
          Text(inheritedNote, style: const TextStyle(fontSize: 10, color: Colors.grey))
        else
          const Text('platform', style: TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    ));
  }

  // ── History ──────────────────────────────────────────────────────────

  Widget _historyList() {
    final items = _history;
    if (items == null) {
      return _card(const Center(child: Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      )));
    }
    if (items.isEmpty) {
      return _card(Text('ยังไม่มีประวัติการเปลี่ยนแปลง',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)));
    }
    return _card(
      Column(
        children: [
          for (final rev in items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: Colors.blueGrey.shade50,
                child: Text('${rev.revision}', style: const TextStyle(fontSize: 11)),
              ),
              title: Text(rev.reason ?? '—',
                  style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${rev.actor ?? '?'} · ${rev.createdAt.toLocal()}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: TextButton(
                onPressed: _saving ? null : () => _onRollback(rev),
                child: const Text('ย้อนกลับ', style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }

  // ── Save bar ─────────────────────────────────────────────────────────

  Widget _saveBar() {
    final validation = _draft!.validate(_registry);
    final errors = {..._saveErrors, ...validation.errors}.toList();
    // §24.A — never allow a save while showing the embedded app default:
    // writing it would fabricate a revision the server never produced.
    final canSave = validation.isValid &&
        !_saving &&
        _snapshot?.isAppDefault != true;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (errors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in errors)
                    Row(children: [
                      const Icon(Icons.error_outline, size: 14, color: Colors.redAccent),
                      const SizedBox(width: 6),
                      Expanded(child: Text(e, style: const TextStyle(fontSize: 12, color: Colors.redAccent))),
                    ]),
                ],
              ),
            ),
          if (validation.warnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final w in validation.warnings)
                    Row(children: [
                      const Icon(Icons.warning_amber, size: 14, color: Colors.orange),
                      const SizedBox(width: 6),
                      Expanded(child: Text(w, style: TextStyle(fontSize: 12, color: Colors.orange.shade800))),
                    ]),
                ],
              ),
            ),
          TextField(
            controller: _reasonCtrl,
            decoration: InputDecoration(
              labelText: 'เหตุผลของการเปลี่ยนแปลง${_draft!.environment == 'prod' ? ' (บังคับ)' : ''}',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            maxLines: 2,
            enabled: !_saving,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => setState(() => _draft = _saved),
                  child: const Text('ยกเลิก'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: canSave ? _onSave : null,
                  icon: _saving
                      ? const SizedBox(
                          height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save, size: 18),
                  label: Text(_saving ? 'กำลังบันทึก…' : 'บันทึกการตั้งค่า'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Shared bits ──────────────────────────────────────────────────────

  Widget _card(Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );

  Widget _banner({required Color color, required IconData icon, required String text, Widget? trailing}) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color))),
            ?trailing,
          ],
        ),
      );

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
      );

  void unawaited(Future<void> f) {}
}
