import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../data/book_court_models.dart';
import '../../domain/venue_setup_progress.dart';

/// Setup-progress checklist card for the per-venue manage page.
///
/// Pure presentation: rows are tappable only when the step is actionable or
/// re-editable — read-only steps (owner application, venue creation, admin
/// review) never show a tap affordance without a handler behind it.
class VenueSetupChecklistCard extends StatelessWidget {
  final List<VenueSetupStep> steps;
  final VenueStatus? venueStatus;
  final bool saving;

  /// Called when the owner taps an actionable/re-editable step row.
  final void Function(VenueSetupStepId step) onRun;

  /// Steps the owner may reopen to adjust existing values.
  final bool editableSteps;

  const VenueSetupChecklistCard({
    super.key,
    required this.steps,
    required this.venueStatus,
    required this.onRun,
    this.saving = false,
    this.editableSteps = true,
  });

  static bool _editable(VenueSetupStepId id) => switch (id) {
    VenueSetupStepId.sports ||
    VenueSetupStepId.hours ||
    VenueSetupStepId.amenities ||
    VenueSetupStepId.terms ||
    VenueSetupStepId.courts => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final doneCount = steps.where((s) => s.done).length;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'ขั้นตอนการเปิดสนาม',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '$doneCount/${steps.length}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: doneCount / steps.length,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < steps.length; i++)
              _StepRow(
                step: steps[i],
                order: i + 1,
                venueStatus: steps[i].id == VenueSetupStepId.venueApproved
                    ? venueStatus
                    : null,
                enabled:
                    editableSteps &&
                    _editable(steps[i].id) &&
                    (steps[i].actionable || steps[i].done),
                onTap: saving ? null : () => onRun(steps[i].id),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final VenueSetupStep step;
  final int order;
  final VenueStatus? venueStatus;
  final bool enabled;
  final VoidCallback? onTap;

  const _StepRow({
    required this.step,
    required this.order,
    required this.venueStatus,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tappable = enabled && (step.actionable || step.done);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: tappable ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _stepIcon(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: step.done ? FontWeight.w500 : FontWeight.w600,
                      color: step.done || step.actionable
                          ? Colors.black87
                          : Colors.grey.shade500,
                    ),
                  ),
                  if (step.note != null)
                    Text(
                      step.note!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ),
            _trailing(),
          ],
        ),
      ),
    );
  }

  Widget _stepIcon() {
    if (step.done) {
      return const Icon(
        Icons.check_circle_rounded,
        size: 20,
        color: Colors.green,
      );
    }
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: step.actionable ? AppColors.primaryDark : Colors.grey.shade300,
      ),
      child: Text(
        '$order',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: step.actionable ? Colors.white : Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _trailing() {
    if (step.id == VenueSetupStepId.venueApproved) {
      if (venueStatus == VenueStatus.approved) {
        return const SizedBox.shrink();
      }
      final (icon, color) = switch (venueStatus) {
        VenueStatus.pending => (
          Icons.hourglass_top_rounded,
          Colors.orange.shade700,
        ),
        VenueStatus.rejected => (Icons.error_rounded, Colors.red.shade700),
        VenueStatus.suspended => (Icons.block_rounded, Colors.red.shade700),
        _ => (Icons.send_rounded, Colors.grey.shade500),
      };
      return Icon(icon, size: 18, color: color);
    }
    if (!(enabled && (step.actionable || step.done))) {
      return const SizedBox.shrink();
    }
    return Icon(
      step.done ? Icons.edit_outlined : Icons.chevron_right_rounded,
      size: 18,
      color: step.done ? Colors.grey.shade500 : AppColors.primaryDark,
    );
  }
}
