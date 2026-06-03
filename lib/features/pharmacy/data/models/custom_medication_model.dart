import 'package:freezed_annotation/freezed_annotation.dart';

part 'custom_medication_model.freezed.dart';
part 'custom_medication_model.g.dart';

@freezed
class CustomMedicationModel with _$CustomMedicationModel {
  const factory CustomMedicationModel({
    required String id,
    required String professionId,
    required String name,
    String? description,
    String? categoryId,
    double? price,
    @Default(true) bool isCustom,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _CustomMedicationModel;

  factory CustomMedicationModel.fromJson(Map<String, dynamic> json) => _$CustomMedicationModelFromJson(json);
}
