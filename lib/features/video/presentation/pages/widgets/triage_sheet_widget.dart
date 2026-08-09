import 'package:flutter/material.dart';
import '../../../models/triage_models.dart';
import '../../../data/repositories/victim_repository.dart';
import 'triage_victim_card.dart';
import 'add_victim_dialog.dart';

class TriageSheetWidget extends StatefulWidget {
  final String incidentId;
  final VictimRepository repository;

  const TriageSheetWidget({
    super.key,
    required this.incidentId,
    required this.repository,
  });

  static void show(BuildContext context, String incidentId, VictimRepository repository) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: TriageSheetWidget(
            incidentId: incidentId,
            repository: repository,
          ),
        ),
      ),
    );
  }

  @override
  State<TriageSheetWidget> createState() => _TriageSheetWidgetState();
}

class _TriageSheetWidgetState extends State<TriageSheetWidget> {
  VictimListResponse? _response;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVictims();
  }

  Future<void> _loadVictims() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await widget.repository.getVictims(widget.incidentId);
      if (mounted) {
        setState(() {
          _response = response;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        _buildSummaryBar(),
        Expanded(child: _buildBody()),
        _buildAddButton(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'ระบบคัดแยกผู้ป่วย (Triage)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadVictims,
            tooltip: 'รีเฟรช',
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar() {
    if (_response == null) return const SizedBox.shrink();
    final s = _response!.summary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: [
          if (s.deceased > 0) _buildSummaryChip('⚫', s.deceased, Colors.black),
          if (s.critical > 0) _buildSummaryChip('🔴', s.critical, Colors.red),
          if (s.urgent > 0) _buildSummaryChip('🟡', s.urgent, Colors.amber),
          if (s.nonUrgent > 0) _buildSummaryChip('🟢', s.nonUrgent, Colors.green),
          if (s.white > 0) _buildSummaryChip('⚪', s.white, Colors.grey),
          _buildSummaryChip('รวม', s.total, Colors.blue),
        ],
      ),
    );
  }

  Widget _buildSummaryChip(String emoji, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '$emoji $count',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadVictims, child: const Text('ลองใหม่')),
          ],
        ),
      );
    }
    if (_response == null || _response!.victims.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('ยังไม่มีรายชื่อผู้ป่วย'),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _response!.victims.length,
      itemBuilder: (context, index) {
        final victim = _response!.victims[index];
        return TriageVictimCard(
          victim: victim,
          permissions: _response!.viewerPermissions,
          repository: widget.repository,
          onChanged: _loadVictims,
        );
      },
    );
  }

  Widget _buildAddButton() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () async {
            await AddVictimDialog.show(context, widget.incidentId, widget.repository);
            _loadVictims();
          },
          icon: const Icon(Icons.person_add),
          label: const Text('แจ้งชื่อผู้ป่วย'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}
