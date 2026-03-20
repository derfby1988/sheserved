INSERT INTO public.medications (source_type, reference_code, generic_name, trade_name, dosage_form, strength, manufacturer, status)
VALUES 
  ('TMT', '101010101010101010101010', 'Paracetamol', 'Sara', 'Tablet', '500 mg', 'Thai Nakorn Patana', 'ACTIVE'),
  ('TMT', '202020202020202020202020', 'Ibuprofen', 'Nurofen', 'Film-coated tablet', '400 mg', 'Reckitt Benckiser', 'ACTIVE'),
  ('TMT', '303030303030303030303030', 'Amoxicillin', 'Amoxil', 'Capsule', '500 mg', 'GSK', 'ACTIVE'),
  ('SUPPLEMENT', 'FDA-12345678', 'Vitamin C', 'Nat C', 'Tablet', '1000 mg', 'Mega We Care', 'ACTIVE'),
  ('UNREG', NULL, 'Melatonin', 'Natrol Melatonin', 'Gummy', '5 mg', 'Natrol', 'ACTIVE');
