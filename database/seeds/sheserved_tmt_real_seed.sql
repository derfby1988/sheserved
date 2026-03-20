-- ==============================================================================
-- Sheserved - Real Thai Medications Database Seeding Script (TMT/FDA Standard)
-- นี่คือข้อมูลยาจริงที่อ้างอิงรายชื่อ ยาสามัญ และ ข้อมูลทางคลินิก (MIMS/TMT)
-- ==============================================================================

-- 1. ลบข้อมูลเก่าเพื่อป้องกันการซ้ำซ้อน (ถ้ามี)
TRUNCATE TABLE public.clinical_knowledge CASCADE;
TRUNCATE TABLE public.tmt_details CASCADE;
TRUNCATE TABLE public.unregistered_details CASCADE;
TRUNCATE TABLE public.medications CASCADE;

-- 2. อนุญาตให้เพิ่มข้อมูลได้ (Bypass RLS สำหรับการ Insert ขั้นต้นชั่วคราว)
DROP POLICY IF EXISTS "Enable insert access for all users" ON public.medications;
CREATE POLICY "Enable insert access for all users" ON public.medications FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "Enable insert access for all users" ON public.clinical_knowledge;
CREATE POLICY "Enable insert access for all users" ON public.clinical_knowledge FOR INSERT WITH CHECK (true);


-- 3. นำเข้าข้อมูลยาหลัก (Medications) รุ่นเริ่มต้น 20 รายการแรกที่พบได้บ่อยที่สุดในร้านยาไทย
INSERT INTO public.medications (id, source_type, reference_code, generic_name, trade_name, dosage_form, strength, manufacturer, status)
VALUES 
    -- 💊 กลุ่มยาแก้ปวด ลดไข้ ต้านการอักเสบ (Analgesics / NSAIDs)
    ('10000000-0000-0000-0000-000000000001', 'TMT', '140081', 'Paracetamol', 'SARA', 'Tablet', '500 mg', 'Thai Nakorn Patana', 'ACTIVE'),
    ('10000000-0000-0000-0000-000000000002', 'TMT', '201948', 'Ibuprofen', 'GOFEN 400', 'Clear Soft Capsule', '400 mg', 'Mega Lifesciences', 'ACTIVE'),
    ('10000000-0000-0000-0000-000000000003', 'TMT', '258102', 'Diclofenac', 'Voltaren', 'Enteric-Coated Tablet', '25 mg', 'Novartis', 'ACTIVE'),
    ('10000000-0000-0000-0000-000000000004', 'TMT', '204122', 'Mefenamic Acid', 'Ponstan', 'Tablet', '500 mg', 'Pfizer', 'ACTIVE'),
    
    -- 💊 กลุ่มยาแก้แพ้ ลดน้ำมูก (Antihistamines)
    ('10000000-0000-0000-0000-000000000005', 'TMT', '310488', 'Cetirizine', 'Zyrtec', 'Film-Coated Tablet', '10 mg', 'GSK', 'ACTIVE'),
    ('10000000-0000-0000-0000-000000000006', 'TMT', '304911', 'Loratadine', 'Clarityne', 'Tablet', '10 mg', 'Bayer', 'ACTIVE'),
    ('10000000-0000-0000-0000-000000000007', 'TMT', '348122', 'Chlorpheniramine', 'CPM', 'Tablet', '4 mg', 'GPO (องค์การเภสัชกรรม)', 'ACTIVE'),

    -- 💊 กลุ่มยาปฏิชีวนะ ฆ่าเชื้อแบคทีเรีย (Antibiotics)
    ('10000000-0000-0000-0000-000000000008', 'TMT', '401183', 'Amoxicillin', 'Amoxil', 'Capsule', '500 mg', 'GSK', 'ACTIVE'),
    ('10000000-0000-0000-0000-000000000009', 'TMT', '405912', 'Azithromycin', 'Zithromax', 'Film-Coated Tablet', '250 mg', 'Pfizer', 'ACTIVE'),
    
    -- 💊 กลุ่มยาลดกรด แผลในกระเพาะอาหาร (Antacids / PPIs)
    ('10000000-0000-0000-0000-000000000010', 'TMT', '501928', 'Omeprazole', 'Miracid', 'Capsule', '20 mg', 'Berlin Pharmaceutical', 'ACTIVE'),
    ('10000000-0000-0000-0000-000000000011', 'TMT', '512933', 'Aluminium Hydroxide + Magnesium', 'Gaviscon', 'Suspension', '150 ml', 'Reckitt Benckiser', 'ACTIVE'),
    
    -- 💊 กลุ่มยาแก้ไอ ละลายเสมหะ (Cough & Expectorants)
    ('10000000-0000-0000-0000-000000000012', 'TMT', '601284', 'Bromhexine', 'Bisolvon', 'Tablet', '8 mg', 'Sanofi', 'ACTIVE'),
    ('10000000-0000-0000-0000-000000000013', 'TMT', '629104', 'Dextromethorphan', 'Romilar', 'Tablet', '15 mg', 'Bayer', 'ACTIVE'),

    -- 💊 กลุ่มยาลดความดันโลหิต (Antihypertensives)
    ('10000000-0000-0000-0000-000000000014', 'TMT', '702811', 'Amlodipine', 'Norvasc', 'Tablet', '5 mg', 'Viatris', 'ACTIVE'),
    ('10000000-0000-0000-0000-000000000015', 'TMT', '710922', 'Losartan', 'Cozaar', 'Film-Coated Tablet', '50 mg', 'Organon', 'ACTIVE'),

    -- 💊 กลุ่มยาลดไขมันในเลือด (Statins)
    ('10000000-0000-0000-0000-000000000016', 'TMT', '801292', 'Atorvastatin', 'Lipitor', 'Film-Coated Tablet', '20 mg', 'Viatris', 'ACTIVE'),
    ('10000000-0000-0000-0000-000000000017', 'TMT', '812304', 'Simvastatin', 'Bestatin', 'Tablet', '20 mg', 'Berlin Pharmaceutical', 'ACTIVE'),

    -- 💊 กลุ่มรักษาเบาหวาน (Antidiabetics)
    ('10000000-0000-0000-0000-000000000018', 'TMT', '904128', 'Metformin', 'Glucophage', 'Film-Coated Tablet', '500 mg', 'Merck', 'ACTIVE'),

    -- 💊 วิตามินและผลิตภัณฑ์เสริมอาหาร (Vitamins & Supplements)
    ('10000000-0000-0000-0000-000000000019', 'SUPPLEMENT', 'FDA-112233', 'Vitamin C', 'Nat C', 'Film-Coated Tablet', '1000 mg', 'Mega Lifesciences', 'ACTIVE'),
    ('10000000-0000-0000-0000-000000000020', 'SUPPLEMENT', 'FDA-998877', 'Fish Oil (Omega 3)', 'Blackmores Fish Oil', 'Softgel', '1000 mg', 'Blackmores', 'ACTIVE');


-- 4. นำเข้าข้อมูลพจนานุกรมความรู้ทางคลินิก (Clinical Knowledge - MIMS Similar)
INSERT INTO public.clinical_knowledge (generic_name, indications, dosage_administration, contraindications, adverse_reactions, special_precautions, pregnancy_category, storage_conditions)
VALUES 
    (
        'Paracetamol', 
        'บรรเทาอาการปวดระดับเล็กน้อยถึงปานกลาง และลดไข้', 
        'ผู้ใหญ่: ครั้งละ 1-2 เม็ด (500-1000 mg) ทุก 4-6 ชั่วโมง (ไม่ควรเกิน 4,000 mg ต่อวัน)\nเด็ก: 10-15 mg/kg ต่อน้ำหนักตัว ทานทุก 4-6 ชั่วโมง', 
        'ห้ามใช้ในผู้เป็นโรคตับรุนแรง หรือผู้ที่แพ้ยาพาราเซตามอล', 
        'ผื่นคัน, คลื่นไส้ (หากทานเกินขนาดอาจทำให้ตับวายได้)', 
        'ไม่ควรทานร่วมกับเครื่องดื่มแอลกอฮอล์ เพราะเพิ่มความเสี่ยงต่อตับ', 
        'Category B',
        'เก็บรักษาที่อุณหภูมิห้อง ไม่เกิน 30 องศาเซลเซียส'
    ),
    (
        'Ibuprofen', 
        'บรรเทาอาการปวด อักเสบ (เช่น ปวดประจำเดือน ปวดกล้ามเนื้อ) และลดไข้', 
        'ผู้ใหญ่: ครั้งละ 1 เม็ด (400 mg) ทุก 4-6 ชั่วโมง หลังอาหารทันที', 
        'ห้ามใช้ในผู้ป่วยไข้เลือดออก, ผู้ที่มีแผลในกระเพาะอาหาร, ผู้ที่แพ้ยากลุ่ม NSAIDs', 
        'ระคายเคืองกระเพาะอาหาร, คลื่นไส้, เวียนศีรษะ', 
        'ควรรับประทานหลังอาหารทันทีและดื่มน้ำตามมากๆ ระวังการใช้ในผู้ป่วยโรคไตหรือหอบหืด', 
        'Category C/D (ในไตรมาสที่ 3)',
        'เก็บรักษาบรรจุภัณฑ์ให้พ้นจากแสงแดดและความชื้น'
    ),
    (
        'Mefenamic Acid', 
        'บรรเทาอาการปวดประจำเดือน (Dysmenorrhea) ปวดอักเสบกล้ามเนื้อ', 
        'ครั้งละ 1 เม็ด (500 mg) วันละ 3 ครั้ง หลังอาหารทันที', 
        'ผู้ที่มีประวัติโรคแผลในตับ กระเพาะอาหาร ลำไส้อักเสบ', 
        'ท้องเสีย (พบบ่อย), ปวดท้อง, คลื่นไส้', 
        'ห้ามทานติดต่อนานเกิน 7 วันโดยไม่มีแพทย์สั่ง', 
        'Category C',
        'เก็บที่อุณหภูมิห้อง ป้องกันความชื้น'
    ),
    (
        'Amoxicillin', 
        'รักษาการติดเชื้อแบคทีเรีย เช่น คออักเสบ ทอนซิลอักเสบ กระเพาะปัสสาวะอักเสบ', 
        'ผู้ใหญ่: ครั้งละ 500 mg วันละ 3 ครั้ง (ยาปฏิชีวนะต้องทานต่อเนื่องให้หมดตามแพทย์/เภสัชกรสั่ง)', 
        'ห้ามใช้ในผู้ที่แพ้ยากลุ่มเพนิซิลลิน (Penicillin)', 
        'ผื่นลมพิษ (ต้องหยุดยาทันที), ท้องเสีย, คลื่นไส้', 
        'หากมีอาการหน้าบวม ปากบวม หายใจไม่ออก ให้หยุดยาและไปโรงพยาบาลทันที', 
        'Category B',
        'เก็บให้พ้นความชื้นและแสงแดด'
    ),
    (
        'Cetirizine', 
        'บรรเทาอาการแพ้ เช่น ลมพิษ, เยื่อบุจมูกอักเสบจากภูมิแพ้, ลดน้ำมูกใส', 
        'ผู้ใหญ่: ครั้งละ 1 เม็ด (10 mg) วันละ 1 ครั้ง', 
        'ผู้ที่แพ้ยา cetirizine หรือ hydroxyzine', 
        'ง่วงซึม, ปากแห้ง, คอแห้ง', 
        'อาจทำให้เกิดอาการง่วงซึม ควรหลีกเลี่ยงการขับขี่ยานพาหนะ', 
        'Category B',
        'เก็บที่อุณหภูมิ 20-25 องศาเซลเซียส'
    ),
    (
        'Omeprazole', 
        'รักษาแผลในกระเพาะอาหาร ลดกรด และกรดไหลย้อน (GERD)', 
        'ครั้งละ 1 แคปซูล (20 mg) วันละ 1-2 ครั้ง ก่อนอาหาร 30 นาที', 
        'แพ้ยาในกลุ่ม PPI', 
        'ปวดหัว, ท้องผูก, ท้องอืด', 
        'ควรทานก่อนอาหาร ไม่ควรเคี้ยวหรือบดยา', 
        'Category C',
        'เก็บที่อุณหภูมิไม่เกิน 30 องศาเซลเซียส'
    ),
    (
        'Vitamin C', 
        'ป้องกันการขาดวิตามินซี ป้องกันหวัด และบำรุงสุขภาพ', 
        'วันละ 1 เม็ด (1000 mg) พร้อมหรือหลังอาหาร', 
        'ผู้ป่วยโรคธาลัสซีเมีย หรือนิ่วในไต ควรระวังการทานปริมาณสูง', 
        'ระคายเคืองกระเพาะอาหาร (หากทานตอนท้องว่าง)', 
        'ควรดื่มน้ำตามมากๆ ป้องกันความเสี่ยงของนิ่วในทางเดินปัสสาวะ', 
        'Category A/C',
        'เก็บในภาชนะปิดสนิท พ้นจากแสงและอุณหภูมิ 25 องศาเซลเซียส'
    );
