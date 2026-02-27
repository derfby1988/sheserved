-- =====================================================
-- อัปเดต local_gov_type จากข้อมูลจริง DLA Open Data (CSV)
-- แหล่งข้อมูล: กรมส่งเสริมการปกครองท้องถิ่น (opendata.dla.go.th)
-- จำนวน: 7256 ตำบลทั่วประเทศ
-- Generated: 2026-02-27T16:18:19.915Z
-- =====================================================

-- Step 1: Reset ทั้งหมดเป็น อบต. (default)
UPDATE public.thai_addresses SET local_gov_type = 'sao';

-- Step 2: กรุงเทพมหานคร → bma
UPDATE public.thai_addresses SET local_gov_type = 'bma'
  WHERE province = 'กรุงเทพมหานคร';

-- Step 3: เมืองพัทยา → pattaya
UPDATE public.thai_addresses SET local_gov_type = 'pattaya'
  WHERE province = 'ชลบุรี' AND district = 'บางละมุง'
  AND sub_district IN ('นาเกลือ', 'หนองปรือ', 'หนองปลาไหล', 'โป่ง');

-- Step 4: เทศบาลนคร (86 ตำบล)
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'ขอนแก่น' AND district = 'เมืองขอนแก่น' AND sub_district IN ('ในเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'ชลบุรี' AND district = 'ศรีราชา' AND sub_district IN ('สุรศักดิ์', 'บึง', 'ทุ่งสุขลา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'ตรัง' AND district = 'เมืองตรัง' AND sub_district IN ('ทับเที่ยง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'ตาก' AND district = 'แม่สอด' AND sub_district IN ('แม่สอด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'นครปฐม' AND district = 'เมืองนครปฐม' AND sub_district IN ('พระปฐมเจดีย์', 'นครปฐม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'นครราชสีมา' AND district = 'เมืองนครราชสีมา' AND sub_district IN ('ในเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'นครศรีธรรมราช' AND district = 'เมืองนครศรีธรรมราช' AND sub_district IN ('ท่าวัง', 'คลัง', 'ในเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'นครสวรรค์' AND district = 'เมืองนครสวรรค์' AND sub_district IN ('ปากน้ำโพ', 'วัดไทร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'นนทบุรี' AND district = 'ปากเกร็ด' AND sub_district IN ('ปากเกร็ด', 'บ้านใหม่', 'บางพูด', 'บางตลาด', 'คลองเกลือ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'นนทบุรี' AND district = 'เมืองนนทบุรี' AND sub_district IN ('ท่าทราย', 'ตลาดขวัญ', 'บางกระสอ', 'บางเขน', 'สวนใหญ่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'ปทุมธานี' AND district = 'ธัญบุรี' AND sub_district IN ('บึงสนั่น', 'ประชาธิปัตย์', 'รังสิต', 'ลำผักกูด', 'บึงน้ำรักษ์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'พระนครศรีอยุธยา' AND district = 'พระนครศรีอยุธยา' AND sub_district IN ('ไผ่ลิง', 'กะมัง', 'หัวรอ', 'หอรัตนไชย', 'ประตูชัย', 'บ้านรุน', 'ท่าวาสุกรี', 'คลองสวนพลู');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'พิษณุโลก' AND district = 'เมืองพิษณุโลก' AND sub_district IN ('ในเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'ภูเก็ต' AND district = 'เมืองภูเก็ต' AND sub_district IN ('ตลาดใหญ่', 'ตลาดเหนือ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'ยะลา' AND district = 'เมืองยะลา' AND sub_district IN ('สะเตง', 'ยะลา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'ระยอง' AND district = 'เมืองระยอง' AND sub_district IN ('ห้วยโป่ง', 'ปากน้ำ', 'ท่าประดู่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'ลำปาง' AND district = 'เมืองลำปาง' AND sub_district IN ('ปงแสนทอง', 'พระบาท', 'สบตุ๋ย', 'สวนดอก', 'หัวเวียง', 'เวียงเหนือ', 'กล้วยแพะ', 'ชมพู');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'สกลนคร' AND district = 'เมืองสกลนคร' AND sub_district IN ('ธาตุเชิงชุม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'สงขลา' AND district = 'หาดใหญ่' AND sub_district IN ('หาดใหญ่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'สงขลา' AND district = 'เมืองสงขลา' AND sub_district IN ('บ่อยาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'สมุทรปราการ' AND district = 'เมืองสมุทรปราการ' AND sub_district IN ('ท้ายบ้าน', 'ท้ายบ้านใหม่', 'บางปูใหม่', 'บางเมืองใหม่', 'ปากน้ำ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'สมุทรสาคร' AND district = 'กระทุ่มแบน' AND sub_district IN ('ตลาดกระทุ่มแบน', 'อ้อมน้อย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'สมุทรสาคร' AND district = 'เมืองสมุทรสาคร' AND sub_district IN ('มหาชัย', 'ท่าฉลอม', 'โกรกกราก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'เกาะสมุย' AND sub_district IN ('อ่างทอง', 'หน้าเมือง', 'บ่อผุด', 'มะเร็ต', 'ลิปะน้อย', 'ตลิ่งงาม', 'แม่น้ำ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'เมืองสุราษฎร์ธานี' AND sub_district IN ('ตลาด', 'บางกุ้ง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'อุดรธานี' AND district = 'เมืองอุดรธานี' AND sub_district IN ('บ้านเลื่อม', 'หมากแข้ง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'อุบลราชธานี' AND district = 'เมืองอุบลราชธานี' AND sub_district IN ('ในเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'เชียงราย' AND district = 'เมืองเชียงราย' AND sub_district IN ('เวียง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'
  WHERE province = 'เชียงใหม่' AND district = 'เมืองเชียงใหม่' AND sub_district IN ('ช้างคลาน', 'ศรีภูมิ', 'วัดเกต', 'พระสิงห์', 'ป่าตัน', 'ช้างม่อย', 'หายยา');

-- Step 5: เทศบาลเมือง (279 ตำบล)
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'กระบี่' AND district = 'เมืองกระบี่' AND sub_district IN ('กระบี่ใหญ่', 'ปากน้ำ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'กาญจนบุรี' AND district = 'ท่ามะกา' AND sub_district IN ('ท่าเรือ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'กาญจนบุรี' AND district = 'เมืองกาญจนบุรี' AND sub_district IN ('บ้านเหนือ', 'บ้านใต้', 'ปากแพรก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'กาฬสินธุ์' AND district = 'เมืองกาฬสินธุ์' AND sub_district IN ('กาฬสินธุ์', 'ลำปาว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'กำแพงเพชร' AND district = 'ขาณุวรลักษบุรี' AND sub_district IN ('ปางมะค่า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'กำแพงเพชร' AND district = 'เมืองกำแพงเพชร' AND sub_district IN ('หนองปลิง', 'ในเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ขอนแก่น' AND district = 'ชุมแพ' AND sub_district IN ('ชุมแพ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ขอนแก่น' AND district = 'บ้านไผ่' AND sub_district IN ('บ้านไผ่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ขอนแก่น' AND district = 'พล' AND sub_district IN ('เมืองพล');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ขอนแก่น' AND district = 'เมืองขอนแก่น' AND sub_district IN ('ศิลา', 'บ้านทุ่ม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'จันทบุรี' AND district = 'ขลุง' AND sub_district IN ('ขลุง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'จันทบุรี' AND district = 'ท่าใหม่' AND sub_district IN ('เขาวัว', 'สีพยา', 'ยายร้า', 'พลอยแหวน', 'บ่อพุ', 'ท่าใหม่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'จันทบุรี' AND district = 'เมืองจันทบุรี' AND sub_district IN ('จันทนิมิต', 'ตลาด', 'ท่าช้าง', 'วัดใหม่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ฉะเชิงเทรา' AND district = 'เมืองฉะเชิงเทรา' AND sub_district IN ('หน้าเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ชลบุรี' AND district = 'บางละมุง' AND sub_district IN ('นาเกลือ', 'หนองปรือ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ชลบุรี' AND district = 'บ้านบึง' AND sub_district IN ('บ้านบึง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ชลบุรี' AND district = 'พนัสนิคม' AND sub_district IN ('พนัสนิคม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ชลบุรี' AND district = 'ศรีราชา' AND sub_district IN ('ศรีราชา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ชลบุรี' AND district = 'สัตหีบ' AND sub_district IN ('สัตหีบ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ชลบุรี' AND district = 'เมืองชลบุรี' AND sub_district IN ('บางปลาสร้อย', 'บ้านปึก', 'บ้านสวน', 'บ้านโขด', 'มะขามหย่ง', 'อ่างศิลา', 'แสนสุข');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ชัยนาท' AND district = 'เมืองชัยนาท' AND sub_district IN ('ในเมือง', 'ชัยนาท');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ชัยภูมิ' AND district = 'เมืองชัยภูมิ' AND sub_district IN ('ในเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ชุมพร' AND district = 'หลังสวน' AND sub_district IN ('หลังสวน', 'ปากน้ำ', 'ขันเงิน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ชุมพร' AND district = 'เมืองชุมพร' AND sub_district IN ('ท่าตะเภา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ตรัง' AND district = 'กันตัง' AND sub_district IN ('กันตัง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ตราด' AND district = 'เมืองตราด' AND sub_district IN ('บางพระ', 'ท่าพริก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ตาก' AND district = 'เมืองตาก' AND sub_district IN ('เชียงเงิน', 'หัวเดียด', 'ระแหง', 'หนองหลวง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นครนายก' AND district = 'เมืองนครนายก' AND sub_district IN ('นครนายก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นครปฐม' AND district = 'สามพราน' AND sub_district IN ('ไร่ขิง', 'สามพราน', 'กระทุ่มล้ม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นครปฐม' AND district = 'เมืองนครปฐม' AND sub_district IN ('สามควายเผือก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นครพนม' AND district = 'เมืองนครพนม' AND sub_district IN ('หนองแสง', 'ในเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นครราชสีมา' AND district = 'บัวใหญ่' AND sub_district IN ('บัวใหญ่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นครราชสีมา' AND district = 'ปักธงชัย' AND sub_district IN ('เมืองปัก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นครราชสีมา' AND district = 'ปากช่อง' AND sub_district IN ('ปากช่อง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นครราชสีมา' AND district = 'สีคิ้ว' AND sub_district IN ('สีคิ้ว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นครศรีธรรมราช' AND district = 'ทุ่งสง' AND sub_district IN ('ปากแพรก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นครศรีธรรมราช' AND district = 'ปากพนัง' AND sub_district IN ('ท่าพยา', 'บางตะพง', 'ปากพนัง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นครศรีธรรมราช' AND district = 'เมืองนครศรีธรรมราช' AND sub_district IN ('ปากพูน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นครสวรรค์' AND district = 'ชุมแสง' AND sub_district IN ('ชุมแสง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นครสวรรค์' AND district = 'ตาคลี' AND sub_district IN ('ตาคลี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นนทบุรี' AND district = 'บางกรวย' AND sub_district IN ('วัดชลอ', 'บางกรวย', 'บางคูเวียง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นนทบุรี' AND district = 'บางบัวทอง' AND sub_district IN ('พิมลราช', 'โสนลอย', 'บางบัวทอง', 'บางคูรัด', 'บางรักพัฒนา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นนทบุรี' AND district = 'บางใหญ่' AND sub_district IN ('บางแม่นาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นนทบุรี' AND district = 'เมืองนนทบุรี' AND sub_district IN ('บางกร่าง', 'บางศรีเมือง', 'ไทรม้า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นราธิวาส' AND district = 'ตากใบ' AND sub_district IN ('เจ๊ะเห');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นราธิวาส' AND district = 'สุไหงโก-ลก' AND sub_district IN ('สุไหงโก-ลก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'นราธิวาส' AND district = 'เมืองนราธิวาส' AND sub_district IN ('บางนาค');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'น่าน' AND district = 'เมืองน่าน' AND sub_district IN ('ในเวียง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'บึงกาฬ' AND district = 'เมืองบึงกาฬ' AND sub_district IN ('วิศิษฐ์', 'บึงกาฬ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'บุรีรัมย์' AND district = 'นางรอง' AND sub_district IN ('นางรอง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'บุรีรัมย์' AND district = 'เมืองบุรีรัมย์' AND sub_district IN ('ในเมือง', 'ชุมเห็ด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ปทุมธานี' AND district = 'คลองหลวง' AND sub_district IN ('คลองหนึ่ง', 'คลองสอง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ปทุมธานี' AND district = 'ธัญบุรี' AND sub_district IN ('บึงยี่โถ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ปทุมธานี' AND district = 'ลำลูกกา' AND sub_district IN ('คูคต', 'ลาดสวาย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ปทุมธานี' AND district = 'เมืองปทุมธานี' AND sub_district IN ('บางกะดี', 'บางปรอก', 'บางคูวัด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ประจวบคีรีขันธ์' AND district = 'หัวหิน' AND sub_district IN ('หัวหิน', 'หนองแก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ประจวบคีรีขันธ์' AND district = 'เมืองประจวบคีรีขันธ์' AND sub_district IN ('ประจวบคีรีขันธ์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ปราจีนบุรี' AND district = 'กบินทร์บุรี' AND sub_district IN ('หนองกี่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ปราจีนบุรี' AND district = 'เมืองปราจีนบุรี' AND sub_district IN ('หน้าเมือง', 'บางบริบูรณ์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ปัตตานี' AND district = 'สายบุรี' AND sub_district IN ('ทุ่งคล้า', 'ตะลุบัน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ปัตตานี' AND district = 'เมืองปัตตานี' AND sub_district IN ('อาเนาะรู', 'สะบารัง', 'ปุยุด', 'จะบังติกอ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'พระนครศรีอยุธยา' AND district = 'บางปะอิน' AND sub_district IN ('บ้านเลน', 'คุ้งลาน', 'ตลิ่งชัน', 'ขนอนหลวง', 'บ้านกรด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'พระนครศรีอยุธยา' AND district = 'ผักไห่' AND sub_district IN ('บ้านใหญ่', 'ผักไห่', 'ลำตะเคียน', 'หนองน้ำใหญ่', 'อมฤต', 'โคกช้าง', 'จักราช', 'ตาลาน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'พระนครศรีอยุธยา' AND district = 'วังน้อย' AND sub_district IN ('ลำตาเสา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'พระนครศรีอยุธยา' AND district = 'เสนา' AND sub_district IN ('เสนา', 'บ้านแถว', 'บ้านกระทุ่ม', 'เจ้าเสด็จ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'พะเยา' AND district = 'ดอกคำใต้' AND sub_district IN ('ดอกคำใต้', 'บุญเกิด', 'สว่างอารมณ์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'พะเยา' AND district = 'เมืองพะเยา' AND sub_district IN ('เวียง', 'แม่ต๋ำ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'พังงา' AND district = 'ตะกั่วป่า' AND sub_district IN ('ตะกั่วป่า', 'ตำตัว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'พังงา' AND district = 'เมืองพังงา' AND sub_district IN ('สองแพรก', 'ท้ายช้าง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'พัทลุง' AND district = 'เมืองพัทลุง' AND sub_district IN ('คูหาสวรรค์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'พิจิตร' AND district = 'ตะพานหิน' AND sub_district IN ('ไทรโรงโขน', 'ตะพานหิน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'พิจิตร' AND district = 'บางมูลนาก' AND sub_district IN ('บางมูลนาก', 'ห้วยเขน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'พิจิตร' AND district = 'เมืองพิจิตร' AND sub_district IN ('ในเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'พิษณุโลก' AND district = 'เมืองพิษณุโลก' AND sub_district IN ('อรัญญิก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ภูเก็ต' AND district = 'กะทู้' AND sub_district IN ('ป่าตอง', 'กะทู้');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'มหาสารคาม' AND district = 'เมืองมหาสารคาม' AND sub_district IN ('ตลาด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'มุกดาหาร' AND district = 'เมืองมุกดาหาร' AND sub_district IN ('ศรีบุญเรือง', 'มุกดาหาร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ยะลา' AND district = 'เบตง' AND sub_district IN ('เบตง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ยะลา' AND district = 'เมืองยะลา' AND sub_district IN ('สะเตงนอก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ยโสธร' AND district = 'เมืองยโสธร' AND sub_district IN ('ในเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ระนอง' AND district = 'เมืองระนอง' AND sub_district IN ('เขานิเวศน์', 'บางริ้น');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ระยอง' AND district = 'บ้านฉาง' AND sub_district IN ('บ้านฉาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ระยอง' AND district = 'เมืองระยอง' AND sub_district IN ('มาบตาพุด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ราชบุรี' AND district = 'บ้านโป่ง' AND sub_district IN ('บ้านโป่ง', 'ท่าผา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ราชบุรี' AND district = 'เมืองราชบุรี' AND sub_district IN ('โคกหม้อ', 'อ่างทอง', 'หน้าเมือง', 'พงสวาย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ราชบุรี' AND district = 'โพธาราม' AND sub_district IN ('โพธาราม', 'นางแก้ว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ร้อยเอ็ด' AND district = 'เมืองร้อยเอ็ด' AND sub_district IN ('ปอภาร  (ปอพาน)', 'ในเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ลพบุรี' AND district = 'บ้านหมี่' AND sub_district IN ('บ้านหมี่', 'บางกะพี้', 'ดงพลับ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ลพบุรี' AND district = 'เมืองลพบุรี' AND sub_district IN ('ท่าหิน', 'นิคมสร้างตนเอง', 'สี่คลอง', 'เขาสามยอด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ลำปาง' AND district = 'เถิน' AND sub_district IN ('ล้อมแรด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ลำปาง' AND district = 'เมืองลำปาง' AND sub_district IN ('พิชัย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ลำพูน' AND district = 'เมืองลำพูน' AND sub_district IN ('ในเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'ศรีสะเกษ' AND district = 'เมืองศรีสะเกษ' AND sub_district IN ('เมืองเหนือ', 'เมืองใต้');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สงขลา' AND district = 'รัตภูมิ' AND sub_district IN ('กำแพงเพชร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สงขลา' AND district = 'สะเดา' AND sub_district IN ('สะเดา', 'ปาดังเบซาร์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สงขลา' AND district = 'สิงหนคร' AND sub_district IN ('หัวเขา', 'สทิงหม้อ', 'ม่วงงาม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สงขลา' AND district = 'หาดใหญ่' AND sub_district IN ('คลองแห', 'บ้านพรุ', 'ควนลัง', 'ทุ่งตำเสา', 'คอหงส์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สงขลา' AND district = 'เมืองสงขลา' AND sub_district IN ('เขารูปช้าง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สตูล' AND district = 'เมืองสตูล' AND sub_district IN ('พิมาน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สมุทรปราการ' AND district = 'บางพลี' AND sub_district IN ('บางแก้ว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สมุทรปราการ' AND district = 'พระประแดง' AND sub_district IN ('บางหัวเสือ', 'สำโรงกลาง', 'สำโรงใต้', 'ตลาด', 'บางครุ', 'บางจาก', 'บางพึ่ง', 'บางหญ้าแพรก', 'สำโรง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สมุทรปราการ' AND district = 'เมืองสมุทรปราการ' AND sub_district IN ('แพรกษา', 'แพรกษาใหม่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สมุทรสงคราม' AND district = 'เมืองสมุทรสงคราม' AND sub_district IN ('แม่กลอง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สมุทรสาคร' AND district = 'กระทุ่มแบน' AND sub_district IN ('คลองมะเดื่อ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สระบุรี' AND district = 'พระพุทธบาท' AND sub_district IN ('พระพุทธบาท', 'ขุนโขลน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สระบุรี' AND district = 'เมืองสระบุรี' AND sub_district IN ('ปากเพรียว', 'นาโฉง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สระบุรี' AND district = 'แก่งคอย' AND sub_district IN ('ทับกวาง', 'แก่งคอย', 'บ้านธาตุ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สระแก้ว' AND district = 'วังน้ำเย็น' AND sub_district IN ('วังน้ำเย็น');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สระแก้ว' AND district = 'อรัญประเทศ' AND sub_district IN ('อรัญประเทศ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สระแก้ว' AND district = 'เมืองสระแก้ว' AND sub_district IN ('สระแก้ว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สิงห์บุรี' AND district = 'บางระจัน' AND sub_district IN ('โพชนไก่', 'เชิงกลัด', 'สิงห์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สิงห์บุรี' AND district = 'เมืองสิงห์บุรี' AND sub_district IN ('บางพุทรา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สุพรรณบุรี' AND district = 'สองพี่น้อง' AND sub_district IN ('สองพี่น้อง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สุพรรณบุรี' AND district = 'เมืองสุพรรณบุรี' AND sub_district IN ('สระแก้ว', 'ท่าพี่เลี้ยง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'ดอนสัก' AND sub_district IN ('ดอนสัก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'บ้านนาสาร' AND sub_district IN ('นาสาร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'พุนพิน' AND sub_district IN ('ท่าข้าม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สุรินทร์' AND district = 'เมืองสุรินทร์' AND sub_district IN ('ในเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สุโขทัย' AND district = 'ศรีสัชนาลัย' AND sub_district IN ('ท่าชัย', 'ศรีสัชนาลัย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สุโขทัย' AND district = 'สวรรคโลก' AND sub_district IN ('วังพิณพาทย์', 'เมืองสวรรคโลก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'สุโขทัย' AND district = 'เมืองสุโขทัย' AND sub_district IN ('ธานี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'หนองคาย' AND district = 'ท่าบ่อ' AND sub_district IN ('ท่าบ่อ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'หนองคาย' AND district = 'เมืองหนองคาย' AND sub_district IN ('ในเมือง', 'มีชัย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'หนองบัวลำภู' AND district = 'เมืองหนองบัวลำภู' AND sub_district IN ('โพธิ์ชัย', 'ลำภู');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'อุดรธานี' AND district = 'บ้านดุง' AND sub_district IN ('ศรีสุทโธ', 'บ้านดุง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'อุตรดิตถ์' AND district = 'เมืองอุตรดิตถ์' AND sub_district IN ('ท่าอิฐ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'อุทัยธานี' AND district = 'เมืองอุทัยธานี' AND sub_district IN ('โนนเหล็ก', 'อุทัยใหม่', 'หนองพังค่า', 'ทุ่งใหญ่', 'หนองเต่า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'อุบลราชธานี' AND district = 'พิบูลมังสาหาร' AND sub_district IN ('พิบูล');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'อุบลราชธานี' AND district = 'วารินชำราบ' AND sub_district IN ('วารินชำราบ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'อุบลราชธานี' AND district = 'เมืองอุบลราชธานี' AND sub_district IN ('แจระแม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'อ่างทอง' AND district = 'เมืองอ่างทอง' AND sub_district IN ('มหาดไทย', 'บ้านรี', 'บางแก้ว', 'ตลาดหลวง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'เชียงใหม่' AND district = 'สันกำแพง' AND sub_district IN ('ทรายมูล', 'ต้นเปา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'เชียงใหม่' AND district = 'สันทราย' AND sub_district IN ('แม่แฝกใหม่', 'สันทรายน้อย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'เชียงใหม่' AND district = 'เมืองเชียงใหม่' AND sub_district IN ('แม่เหียะ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'เชียงใหม่' AND district = 'แม่แตง' AND sub_district IN ('ขี้เหล็ก', 'ช่อแล', 'กื้ดช้าง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'เพชรบุรี' AND district = 'ชะอำ' AND sub_district IN ('เขาใหญ่', 'ดอนขุนห้วย', 'ชะอำ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'เพชรบุรี' AND district = 'เมืองเพชรบุรี' AND sub_district IN ('วังตะโก', 'ท่าราบ', 'คลองกระแชง', 'เวียงคอย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'เพชรบูรณ์' AND district = 'หล่มสัก' AND sub_district IN ('หล่มสัก', 'หนองสว่าง', 'น้ำเฮี้ย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'เพชรบูรณ์' AND district = 'เมืองเพชรบูรณ์' AND sub_district IN ('ในเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'เลย' AND district = 'วังสะพุง' AND sub_district IN ('วังสะพุง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'เลย' AND district = 'เมืองเลย' AND sub_district IN ('กุดป่อง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'แพร่' AND district = 'เมืองแพร่' AND sub_district IN ('น้ำชำ', 'ในเวียง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'
  WHERE province = 'แม่ฮ่องสอน' AND district = 'เมืองแม่ฮ่องสอน' AND sub_district IN ('จองคำ');

-- Step 6: เทศบาลตำบล (2104 ตำบล)
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กระบี่' AND district = 'คลองท่อม' AND sub_district IN ('คลองท่อมใต้', 'ห้วยน้ำขาว', 'ทรายขาว', 'คลองพน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กระบี่' AND district = 'ปลายพระยา' AND sub_district IN ('ปลายพระยา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กระบี่' AND district = 'ลำทับ' AND sub_district IN ('ลำทับ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กระบี่' AND district = 'อ่าวลึก' AND sub_district IN ('แหลมสัก', 'อ่าวลึกใต้');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กระบี่' AND district = 'เกาะลันตา' AND sub_district IN ('ศาลาด่าน', 'เกาะลันตาใหญ่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กระบี่' AND district = 'เขาพนม' AND sub_district IN ('เขาพนม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กระบี่' AND district = 'เมืองกระบี่' AND sub_district IN ('กระบี่น้อย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กระบี่' AND district = 'เหนือคลอง' AND sub_district IN ('เหนือคลอง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาญจนบุรี' AND district = 'ด่านมะขามเตี้ย' AND sub_district IN ('ด่านมะขามเตี้ย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาญจนบุรี' AND district = 'ทองผาภูมิ' AND sub_district IN ('สหกรณ์นิคม', 'ลิ่นถิ่น', 'ท่าขนุน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาญจนบุรี' AND district = 'ท่ามะกา' AND sub_district IN ('ดอนขมิ้น', 'หวายเหนียว', 'หนองลาน', 'พระแท่น', 'ท่าไม้', 'ท่ามะกา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาญจนบุรี' AND district = 'ท่าม่วง' AND sub_district IN ('ท่าม่วง', 'ท่าล้อ', 'ม่วงชุม', 'วังขนาย', 'วังศาลา', 'หนองขาว', 'หนองตากยา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาญจนบุรี' AND district = 'บ่อพลอย' AND sub_district IN ('หนองรี', 'บ่อพลอย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาญจนบุรี' AND district = 'พนมทวน' AND sub_district IN ('หนองสาหร่าย', 'รางหวาย', 'พนมทวน', 'ดอนเจดีย์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาญจนบุรี' AND district = 'ศรีสวัสดิ์' AND sub_district IN ('เขาโจด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาญจนบุรี' AND district = 'หนองปรือ' AND sub_district IN ('สมเด็จเจริญ', 'หนองปลาไหล', 'หนองปรือ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาญจนบุรี' AND district = 'ห้วยกระเจา' AND sub_district IN ('สระลงเรือ', 'ห้วยกระเจา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาญจนบุรี' AND district = 'เมืองกาญจนบุรี' AND sub_district IN ('แก่งเสี้ยน', 'ท่ามะขาม', 'ลาดหญ้า', 'หนองบัว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาญจนบุรี' AND district = 'เลาขวัญ' AND sub_district IN ('เลาขวัญ', 'หนองฝ้าย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาญจนบุรี' AND district = 'ไทรโยค' AND sub_district IN ('ไทรโยค');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาฬสินธุ์' AND district = 'กมลาไสย' AND sub_district IN ('กมลาไสย', 'หลักเมือง', 'หนองแปน', 'ธัญญา', 'ดงลิง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาฬสินธุ์' AND district = 'กุฉินารายณ์' AND sub_district IN ('กุดหว้า', 'จุมจัง', 'นาขาม', 'เหล่าใหญ่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาฬสินธุ์' AND district = 'คำม่วง' AND sub_district IN ('โพน', 'นาทัน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาฬสินธุ์' AND district = 'ฆ้องชัย' AND sub_district IN ('ฆ้องชัยพัฒนา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาฬสินธุ์' AND district = 'ดอนจาน' AND sub_district IN ('ม่วงนา', 'ดอนจาน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาฬสินธุ์' AND district = 'ท่าคันโท' AND sub_district IN ('กุดจิก', 'ดงสมบูรณ์', 'ท่าคันโท', 'นาตาล', 'กุงเก่า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาฬสินธุ์' AND district = 'นาคู' AND sub_district IN ('นาคู', 'ภูแล่นช้าง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาฬสินธุ์' AND district = 'นามน' AND sub_district IN ('นามน', 'สงเปลือย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาฬสินธุ์' AND district = 'ยางตลาด' AND sub_district IN ('บัวบาน', 'ยางตลาด', 'หัวนาคำ', 'อิตื้อ', 'อุ่มเม่า', 'เขาพระนอน', 'โนนสูง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาฬสินธุ์' AND district = 'ร่องคำ' AND sub_district IN ('ร่องคำ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาฬสินธุ์' AND district = 'สมเด็จ' AND sub_district IN ('มหาไชย', 'ลำห้วยหลัว', 'สมเด็จ', 'แซงบาดาล', 'ผาเสวย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาฬสินธุ์' AND district = 'สหัสขันธ์' AND sub_district IN ('ภูสิงห์', 'โนนน้ำเกลี้ยง', 'โนนบุรี', 'โนนศิลา', 'นามะเขือ', 'นิคม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาฬสินธุ์' AND district = 'หนองกุงศรี' AND sub_district IN ('ดงมูล', 'ลำหนองแสน', 'หนองกุงศรี', 'หนองบัว', 'หนองสรวง', 'หนองหิน', 'หนองใหญ่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาฬสินธุ์' AND district = 'ห้วยผึ้ง' AND sub_district IN ('คำบง', 'หนองอีบุตร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาฬสินธุ์' AND district = 'ห้วยเม็ก' AND sub_district IN ('คำเหมือดแก้ว', 'คำใหญ่', 'ห้วยเม็ก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาฬสินธุ์' AND district = 'เขาวง' AND sub_district IN ('กุดปลาค้าว', 'สระพังทอง', 'สงเปลือย', 'กุดสิมคุ้มใหม่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กาฬสินธุ์' AND district = 'เมืองกาฬสินธุ์' AND sub_district IN ('ลำคลอง', 'ภูปอ', 'ภูดิน', 'บึงวิชัย', 'นาจารย์', 'ขมิ้น', 'กลางหมื่น', 'ไผ่', 'โพนทอง', 'เหนือ', 'เชียงเครือ', 'ห้วยโพธิ์', 'หลุบ', 'ลำพาน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กำแพงเพชร' AND district = 'ขาณุวรลักษบุรี' AND sub_district IN ('สลกบาตร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กำแพงเพชร' AND district = 'คลองขลุง' AND sub_district IN ('คลองขลุง', 'วังยาง', 'ท่ามะเขือ', 'ท่าพุทรา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กำแพงเพชร' AND district = 'คลองลาน' AND sub_district IN ('คลองลานพัฒนา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กำแพงเพชร' AND district = 'ทรายทองวัฒนา' AND sub_district IN ('ทุ่งทราย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กำแพงเพชร' AND district = 'บึงสามัคคี' AND sub_district IN ('ระหาน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กำแพงเพชร' AND district = 'พรานกระต่าย' AND sub_district IN ('เขาคีริส', 'คลองพิไกร', 'พรานกระต่าย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กำแพงเพชร' AND district = 'ลานกระบือ' AND sub_district IN ('ลานกระบือ', 'ประชาสุขสันต์', 'ช่องลม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กำแพงเพชร' AND district = 'เมืองกำแพงเพชร' AND sub_district IN ('คลองแม่ลาย', 'นครชุม', 'นิคมทุ่งโพธิ์ทะเล', 'เทพนคร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'กำแพงเพชร' AND district = 'ไทรงาม' AND sub_district IN ('ไทรงาม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'กระนวน' AND sub_district IN ('น้ำอ้อม', 'หนองโน', 'ห้วยยาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'ชนบท' AND sub_district IN ('ชนบท');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'ชุมแพ' AND sub_district IN ('หนองไผ่', 'หนองเสาเล้า', 'นาเพียง', 'โนนสะอาด', 'โนนหัน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'ซำสูง' AND sub_district IN ('กระนวน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'น้ำพอง' AND sub_district IN ('ม่วงหวาน', 'วังชัย', 'กุดน้ำใส', 'สะอาด', 'น้ำพอง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'บ้านฝาง' AND sub_district IN ('โนนฆ้อง', 'ป่ามะนาว', 'หนองบัว', 'โคกงาม', 'บ้านฝาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'บ้านแฮด' AND sub_district IN ('โคกสำราญ', 'บ้านแฮด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'บ้านไผ่' AND sub_district IN ('ในเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'พระยืน' AND sub_district IN ('พระยืน', 'พระบุ', 'บ้านโต้น');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'ภูผาม่าน' AND sub_district IN ('โนนคอม', 'ภูผาม่าน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'ภูเวียง' AND sub_district IN ('ภูเวียง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'มัญจาคีรี' AND sub_district IN ('นาข่า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'สีชมพู' AND sub_district IN ('นาจาน', 'วังเพิ่ม', 'สีชมพู');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'หนองนาคำ' AND sub_district IN ('ขนวน', 'บ้านโคก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'หนองสองห้อง' AND sub_district IN ('หนองสองห้อง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'หนองเรือ' AND sub_district IN ('โนนสะอาด', 'โนนทอง', 'หนองเรือ', 'กุดกว้าง', 'บ้านผือ', 'ยางคำ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'อุบลรัตน์' AND sub_district IN ('โคกสูง', 'เขื่อนอุบลรัตน์', 'นาคำ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'เขาสวนกวาง' AND sub_district IN ('เขาสวนกวาง', 'โนนสมบูรณ์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'เปือยน้อย' AND sub_district IN ('เปือยน้อย', 'สระแก้ว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'เมืองขอนแก่น' AND sub_district IN ('สาวะถี', 'บ้านเป็ด', 'บ้านค้อ', 'บึงเนียม', 'ท่าพระ', 'โนนท่อน', 'เมืองเก่า', 'หนองตูม', 'สำราญ', 'พระลับ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'เวียงเก่า' AND sub_district IN ('ในเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'แวงน้อย' AND sub_district IN ('แวงน้อย', 'ก้านเหลือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'แวงใหญ่' AND sub_district IN ('แวงใหญ่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'โคกโพธิ์ไชย' AND sub_district IN ('บ้านโคก', 'โพธิ์ไชย', 'นาแพง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ขอนแก่น' AND district = 'โนนศิลา' AND sub_district IN ('โนนศิลา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'จันทบุรี' AND district = 'ขลุง' AND sub_district IN ('เกวียนหัก', 'วันยาว', 'ซึ้ง', 'บ่อ', 'ตกพรม', 'บ่อเวฬุ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'จันทบุรี' AND district = 'ท่าใหม่' AND sub_district IN ('เขาบายศรี', 'สองพี่น้อง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'จันทบุรี' AND district = 'นายายอาม' AND sub_district IN ('สนามไชย', 'นายายอาม', 'ช้างข้าม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'จันทบุรี' AND district = 'มะขาม' AND sub_district IN ('ฉมัน', 'วังแซ้ม', 'ปัถวี', 'มะขาม', 'ท่าหลวง', 'อ่างคีรี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'จันทบุรี' AND district = 'สอยดาว' AND sub_district IN ('ทับช้าง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'จันทบุรี' AND district = 'เขาคิชฌกูฏ' AND sub_district IN ('จันทเขลม', 'ชากไทย', 'ตะเคียนทอง', 'พลวง', 'คลองพลู');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'จันทบุรี' AND district = 'เมืองจันทบุรี' AND sub_district IN ('บางกะจะ', 'พลับพลา', 'หนองบัว', 'แสลง', 'เกาะขวาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'จันทบุรี' AND district = 'แก่งหางแมว' AND sub_district IN ('พวา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'จันทบุรี' AND district = 'แหลมสิงห์' AND sub_district IN ('ปากน้ำแหลมสิงห์', 'พลิ้ว', 'คลองน้ำเค็ม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'จันทบุรี' AND district = 'โป่งน้ำร้อน' AND sub_district IN ('โป่งน้ำร้อน', 'หนองตาคง', 'ทับไทร', 'คลองใหญ่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ฉะเชิงเทรา' AND district = 'บางคล้า' AND sub_district IN ('บางคล้า', 'ปากน้ำ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ฉะเชิงเทรา' AND district = 'บางน้ำเปรี้ยว' AND sub_district IN ('ดอนฉิมพลี', 'ดอนเกาะกา', 'บางขนาก', 'บางน้ำเปรี้ยว', 'ศาลาแดง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ฉะเชิงเทรา' AND district = 'บางปะกง' AND sub_district IN ('พิมพา', 'บางสมัคร', 'บางวัว', 'บางผึ้ง', 'บางปะกง', 'ท่าสะอ้าน', 'ท่าข้าม', 'หอมศีล');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ฉะเชิงเทรา' AND district = 'บ้านโพธิ์' AND sub_district IN ('เทพราช', 'ลาดขวาง', 'บ้านโพธิ์', 'บางซ่อน', 'ท่าพลับ', 'แสนภูดาษ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ฉะเชิงเทรา' AND district = 'พนมสารคาม' AND sub_district IN ('เขาหินซ้อน', 'ท่าถ่าน', 'บ้านซ่อง', 'พนมสารคาม', 'เกาะขนุน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ฉะเชิงเทรา' AND district = 'แปลงยาว' AND sub_district IN ('หัวสำโรง', 'แปลงยาว', 'วังเย็น');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชลบุรี' AND district = 'บางละมุง' AND sub_district IN ('บางละมุง', 'ตะเคียนเตี้ย', 'หนองปลาไหล', 'ห้วยใหญ่', 'โป่ง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชลบุรี' AND district = 'บ่อทอง' AND sub_district IN ('ธาตุทอง', 'บ่อทอง', 'บ่อกวางทอง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชลบุรี' AND district = 'บ้านบึง' AND sub_district IN ('หนองไผ่แก้ว', 'หนองชาก', 'หนองซ้ำซาก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชลบุรี' AND district = 'พนัสนิคม' AND sub_district IN ('กุฎโง้ง', 'หัวถนน', 'หมอนนาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชลบุรี' AND district = 'พานทอง' AND sub_district IN ('เกาะลอย', 'หนองตำลึง', 'พานทอง', 'บางหัก', 'หนองกะขะ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชลบุรี' AND district = 'ศรีราชา' AND sub_district IN ('บางพระ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชลบุรี' AND district = 'สัตหีบ' AND sub_district IN ('นาจอมเทียน', 'บางเสร่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชลบุรี' AND district = 'หนองใหญ่' AND sub_district IN ('หนองใหญ่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชลบุรี' AND district = 'เกาะจันทร์' AND sub_district IN ('ท่าบุญมี', 'เกาะจันทร์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชลบุรี' AND district = 'เกาะสีชัง' AND sub_district IN ('ท่าเทววงษ์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชลบุรี' AND district = 'เมืองชลบุรี' AND sub_district IN ('ดอนหัวฬ่อ', 'คลองตำหรุ', 'บางทราย', 'หนองไม้แดง', 'ห้วยกะปิ', 'เสม็ด', 'เหมือง', 'นาป่า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยนาท' AND district = 'มโนรมย์' AND sub_district IN ('หางน้ำสาคร', 'ศิลาดาน', 'คุ้งสำเภา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยนาท' AND district = 'วัดสิงห์' AND sub_district IN ('หนองน้อย', 'วัดสิงห์', 'หนองขุ่น');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยนาท' AND district = 'สรรคบุรี' AND sub_district IN ('ห้วยกรดพัฒนา', 'บางขุด', 'ดอนกำ', 'ดงคอน', 'ห้วยกรด', 'แพรกศรีราชา', 'โพงาม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยนาท' AND district = 'สรรพยา' AND sub_district IN ('โพนางดำตก', 'โพนางดำออก', 'หาดอาษา', 'สรรพยา', 'บางหลวง', 'ตลุก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยนาท' AND district = 'หนองมะโมง' AND sub_district IN ('หนองมะโมง', 'วังตะเคียน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยนาท' AND district = 'หันคา' AND sub_district IN ('หนองแซง', 'หันคา', 'ห้วยงู', 'สามง่ามท่าโบสถ์', 'บ้านเชี่ยน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยนาท' AND district = 'เนินขาม' AND sub_district IN ('เนินขาม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยนาท' AND district = 'เมืองชัยนาท' AND sub_district IN ('หาดท่าเสา', 'บ้านกล้วย', 'เสือโฮก', 'ธรรมามูล', 'นางลือ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยภูมิ' AND district = 'คอนสวรรค์' AND sub_district IN ('คอนสวรรค์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยภูมิ' AND district = 'คอนสาร' AND sub_district IN ('ทุ่งลุยลาย', 'ห้วยยาง', 'คอนสาร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยภูมิ' AND district = 'จัตุรัส' AND sub_district IN ('หนองบัวใหญ่', 'หนองบัวโคก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยภูมิ' AND district = 'บำเหน็จณรงค์' AND sub_district IN ('บ้านเพชร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยภูมิ' AND district = 'บ้านเขว้า' AND sub_district IN ('ตลาดแร้ง', 'บ้านเขว้า', 'ลุ่มลำชี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยภูมิ' AND district = 'บ้านแท่น' AND sub_district IN ('บ้านเต่า', 'บ้านแท่น');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยภูมิ' AND district = 'ภูเขียว' AND sub_district IN ('บ้านแก้ง', 'ธาตุทอง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยภูมิ' AND district = 'หนองบัวระเหว' AND sub_district IN ('โคกสะอาด', 'ห้วยแย้', 'หนองบัวระเหว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยภูมิ' AND district = 'หนองบัวแดง' AND sub_district IN ('หนองบัวแดง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยภูมิ' AND district = 'เกษตรสมบูรณ์' AND sub_district IN ('บ้านเดื่อ', 'บ้านเป้า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยภูมิ' AND district = 'เมืองชัยภูมิ' AND sub_district IN ('ลาดใหญ่', 'โคกสูง', 'ชีลอง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชัยภูมิ' AND district = 'แก้งคร้อ' AND sub_district IN ('หนองสังข์', 'นาหนองทุ่ม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชุมพร' AND district = 'ทุ่งตะโก' AND sub_district IN ('ปากตะโก', 'ทุ่งตะไคร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชุมพร' AND district = 'ท่าแซะ' AND sub_district IN ('ท่าแซะ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชุมพร' AND district = 'ปะทิว' AND sub_district IN ('ทะเลทรัพย์', 'บางสน', 'สะพลี', 'ชุมโค');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชุมพร' AND district = 'พะโต๊ะ' AND sub_district IN ('พะโต๊ะ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชุมพร' AND district = 'ละแม' AND sub_district IN ('ละแม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชุมพร' AND district = 'สวี' AND sub_district IN ('ปากแพรก', 'นาโพธิ์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชุมพร' AND district = 'หลังสวน' AND sub_district IN ('วังตะกอ', 'ท่ามะพลา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ชุมพร' AND district = 'เมืองชุมพร' AND sub_district IN ('ขุนกระทิง', 'วังไผ่', 'วังใหม่', 'บางหมาก', 'บางลึก', 'นาชะอัง', 'ท่ายาง', 'หาดทรายรี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตรัง' AND district = 'กันตัง' AND sub_district IN ('บางเป้า', 'ควนธานี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตรัง' AND district = 'นาโยง' AND sub_district IN ('นาโยงเหนือ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตรัง' AND district = 'ปะเหลียน' AND sub_district IN ('ท่าพญา', 'ท่าข้าม', 'ทุ่งยาว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตรัง' AND district = 'ย่านตาขาว' AND sub_district IN ('ทุ่งกระบือ', 'ย่านตาขาว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตรัง' AND district = 'รัษฎา' AND sub_district IN ('คลองปาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตรัง' AND district = 'สิเกา' AND sub_district IN ('นาเมืองเพชร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตรัง' AND district = 'ห้วยยอด' AND sub_district IN ('นาวง', 'ท่างิ้ว', 'ลำภูรา', 'ห้วยนาง', 'ห้วยยอด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตรัง' AND district = 'เมืองตรัง' AND sub_district IN ('โคกหล่อ', 'นาตาล่วง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตราด' AND district = 'คลองใหญ่' AND sub_district IN ('คลองใหญ่', 'หาดเล็ก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตราด' AND district = 'บ่อไร่' AND sub_district IN ('บ่อพลอย', 'หนองบอน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตราด' AND district = 'เกาะช้าง' AND sub_district IN ('เกาะช้าง', 'เกาะช้างใต้');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตราด' AND district = 'เขาสมิง' AND sub_district IN ('เขาสมิง', 'แสนตุ้ง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตราด' AND district = 'เมืองตราด' AND sub_district IN ('ตะกาง', 'ชำราก', 'หนองเสม็ด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตราด' AND district = 'แหลมงอบ' AND sub_district IN ('น้ำเชี่ยว', 'แหลมงอบ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตาก' AND district = 'ท่าสองยาง' AND sub_district IN ('แม่ต้าน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตาก' AND district = 'บ้านตาก' AND sub_district IN ('ทุ่งกระเชาะ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตาก' AND district = 'พบพระ' AND sub_district IN ('พบพระ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตาก' AND district = 'สามเงา' AND sub_district IN ('สามเงา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตาก' AND district = 'อุ้มผาง' AND sub_district IN ('แม่ละมุ้ง', 'แม่จัน', 'แม่กลอง', 'อุ้มผาง', 'หนองหลวง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตาก' AND district = 'เมืองตาก' AND sub_district IN ('ไม้งาม', 'หนองบัวใต้');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตาก' AND district = 'แม่ระมาด' AND sub_district IN ('แม่จะเรา', 'แม่ระมาด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ตาก' AND district = 'แม่สอด' AND sub_district IN ('แม่ตาว', 'แม่กุ', 'ท่าสายลวด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครนายก' AND district = 'บ้านนา' AND sub_district IN ('บ้านนา', 'พิกุลออก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครนายก' AND district = 'ปากพลี' AND sub_district IN ('เกาะหวาย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครนายก' AND district = 'องครักษ์' AND sub_district IN ('องครักษ์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครนายก' AND district = 'เมืองนครนายก' AND sub_district IN ('ท่าช้าง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครปฐม' AND district = 'กำแพงแสน' AND sub_district IN ('กำแพงแสน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครปฐม' AND district = 'ดอนตูม' AND sub_district IN ('สามง่าม', 'ลำลูกบัว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครปฐม' AND district = 'นครชัยศรี' AND sub_district IN ('บางกระเบา', 'นครชัยศรี', 'ขุนแก้ว', 'ห้วยพลู', 'ศรีษะทอง', 'ศรีมหาโพธิ์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครปฐม' AND district = 'บางเลน' AND sub_district IN ('บางเลน', 'บางหลวง', 'ลำพญา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครปฐม' AND district = 'พุทธมณฑล' AND sub_district IN ('คลองโยง', 'ศาลายา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครปฐม' AND district = 'สามพราน' AND sub_district IN ('อ้อมใหญ่', 'บางกระทึก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครปฐม' AND district = 'เมืองนครปฐม' AND sub_district IN ('บ่อพลับ', 'ดอนยายหอม', 'โพรงมะเดื่อ', 'มาบแค', 'ธรรมศาลา', 'ตาก้อง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครพนม' AND district = 'ท่าอุเทน' AND sub_district IN ('ท่าอุเทน', 'เวินพระบาท');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครพนม' AND district = 'ธาตุพนม' AND sub_district IN ('ธาตุพนม', 'ธาตุพนมเหนือ', 'นาหนาด', 'น้ำก่ำ', 'ฝั่งแดง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครพนม' AND district = 'นาหว้า' AND sub_district IN ('ท่าเรือ', 'นาหว้า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครพนม' AND district = 'นาแก' AND sub_district IN ('พระซอง', 'นาแก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครพนม' AND district = 'บ้านแพง' AND sub_district IN ('บ้านแพง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครพนม' AND district = 'ปลาปาก' AND sub_district IN ('ปลาปาก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครพนม' AND district = 'ศรีสงคราม' AND sub_district IN ('หาดแพง', 'สามผง', 'ศรีสงคราม', 'บ้านข่า', 'นาคำ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครพนม' AND district = 'เมืองนครพนม' AND sub_district IN ('หนองญาติ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครพนม' AND district = 'โพนสวรรค์' AND sub_district IN ('โพนสวรรค์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'ขามทะเลสอ' AND sub_district IN ('พันดุง', 'ขามทะเลสอ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'ขามสะแกแสง' AND sub_district IN ('โนนเมือง', 'หนองหัวฟาน', 'ขามสะแกแสง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'คง' AND sub_district IN ('เมืองคง', 'เทพาลัย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'ครบุรี' AND sub_district IN ('แชะ', 'อรพิมพ์', 'จระเข้หิน', 'ครบุรีใต้');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'จักราช' AND sub_district IN ('จักราช');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'ชุมพวง' AND sub_district IN ('ชุมพวง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'ด่านขุนทด' AND sub_district IN ('ด่านขุนทด', 'หนองบัวตะเกียด', 'หนองกราด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'บัวใหญ่' AND sub_district IN ('หนองบัวสะอาด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'บ้านเหลื่อม' AND sub_district IN ('บ้านเหลื่อม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'ประทาย' AND sub_district IN ('ประทาย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'ปักธงชัย' AND sub_district IN ('นกออก', 'บ่อปลาทอง', 'ลำนางแก้ว', 'ตะขบ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'ปากช่อง' AND sub_district IN ('หมูสี', 'วังไทร', 'กลางดง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'พระทองคำ' AND sub_district IN ('สระพระ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'พิมาย' AND sub_district IN ('รังกาใหญ่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'ลำทะเมนชัย' AND sub_district IN ('ไพล', 'บ้านยาง', 'ช่องแมว', 'ขุย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'สีคิ้ว' AND sub_district IN ('หนองน้ำใส', 'คลองไผ่', 'ลาดบัวขาว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'สีดา' AND sub_district IN ('สีดา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'สูงเนิน' AND sub_district IN ('กุดจิก', 'สูงเนิน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'หนองบุญมาก' AND sub_district IN ('แหลมทอง', 'หนองหัวแรต');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'ห้วยแถลง' AND sub_district IN ('หินดาด', 'ห้วยแถลง', 'กงรถ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'เฉลิมพระเกียรติ' AND sub_district IN ('ท่าช้าง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'เมืองนครราชสีมา' AND sub_district IN ('พุดซา', 'ปรุใหญ่', 'บ้านใหม่', 'บ้านโพธิ์', 'ตลาด', 'จอหอ', 'ไชยมงคล', 'โพธิ์กลาง', 'โคกสูง', 'โคกกรวด', 'หัวทะเล', 'หนองไผ่ล้อม', 'หนองไข่น้ำ', 'สุรนารี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'เมืองยาง' AND sub_district IN ('เมืองยาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'เสิงสาง' AND sub_district IN ('เสิงสาง', 'โนนสมบูรณ์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'แก้งสนามนาง' AND sub_district IN ('บึงสำโรง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'โชคชัย' AND sub_district IN ('ด่านเกวียน', 'ท่าเยี่ยม', 'โชคชัย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'โนนสูง' AND sub_district IN ('ใหม่', 'โนนสูง', 'มะค่า', 'ด่านคล้า', 'ดอนหวาย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'โนนแดง' AND sub_district IN ('โนนแดง', 'วังหิน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครราชสีมา' AND district = 'โนนไทย' AND sub_district IN ('โนนไทย', 'บัลลังก์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'ขนอม' AND sub_district IN ('ขนอม', 'ท้องเนียน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'ฉวาง' AND sub_district IN ('ฉวาง', 'จันดี', 'ไม้เรียง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'ชะอวด' AND sub_district IN ('ชะอวด', 'ท่าประจะ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'ช้างกลาง' AND sub_district IN ('สวนขัน', 'หลักช้าง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'ทุ่งสง' AND sub_district IN ('กะปาง', 'ที่วัง', 'ถ้ำใหญ่', 'ชะมาย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'ทุ่งใหญ่' AND sub_district IN ('ท่ายาง', 'ทุ่งสัง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'ท่าศาลา' AND sub_district IN ('ท่าศาลา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'นบพิตำ' AND sub_district IN ('นาเหรง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'นาบอน' AND sub_district IN ('นาบอน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'ปากพนัง' AND sub_district IN ('เกาะทวด', 'บางพระ', 'ชะเมา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'พรหมคีรี' AND sub_district IN ('ทอนหงส์', 'พรหมโลก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'พระพรหม' AND sub_district IN ('นาสาร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'พิปูน' AND sub_district IN ('เขาพระ', 'พิปูน', 'ควนกลาง', 'กะทูน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'ร่อนพิบูลย์' AND sub_district IN ('หินตก', 'ร่อนพิบูลย์', 'ควนเกย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'ลานสกา' AND sub_district IN ('ลานสกา', 'ขุนทะเล');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'สิชล' AND sub_district IN ('สิชล', 'ทุ่งใส');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'หัวไทร' AND sub_district IN ('หัวไทร', 'เกาะเพชร', 'หน้าสตน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'เฉลิมพระเกียรติ' AND sub_district IN ('ดอนตรอ', 'ทางพูน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'เชียรใหญ่' AND sub_district IN ('เชียรใหญ่', 'การะเกด', 'บ้านกลาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครศรีธรรมราช' AND district = 'เมืองนครศรีธรรมราช' AND sub_district IN ('บางจาก', 'ท่างิ้ว', 'โพธิ์เสด็จ', 'ปากนคร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครสวรรค์' AND district = 'ชุมแสง' AND sub_district IN ('ทับกฤช');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครสวรรค์' AND district = 'ตากฟ้า' AND sub_district IN ('ตากฟ้า', 'อุดมธัญญา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครสวรรค์' AND district = 'ตาคลี' AND sub_district IN ('ช่องแค');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครสวรรค์' AND district = 'ท่าตะโก' AND sub_district IN ('ท่าตะโก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครสวรรค์' AND district = 'บรรพตพิสัย' AND sub_district IN ('บ้านแดน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครสวรรค์' AND district = 'พยุหะคีรี' AND sub_district IN ('ม่วงหัก', 'พยุหะ', 'ท่าน้ำอ้อย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครสวรรค์' AND district = 'ลาดยาว' AND sub_district IN ('ลาดยาว', 'ศาลเจ้าไก่ต่อ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครสวรรค์' AND district = 'หนองบัว' AND sub_district IN ('หนองบัว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครสวรรค์' AND district = 'เก้าเลี้ยว' AND sub_district IN ('เก้าเลี้ยว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครสวรรค์' AND district = 'โกรกพระ' AND sub_district IN ('บางมะฝ่อ', 'บางประมุง', 'โกรกพระ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นครสวรรค์' AND district = 'ไพศาลี' AND sub_district IN ('ไพศาลี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นนทบุรี' AND district = 'บางกรวย' AND sub_district IN ('ปลายบาง', 'ศาลากลาง', 'บางสีทอง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นนทบุรี' AND district = 'บางใหญ่' AND sub_district IN ('เสาธงหิน', 'บางใหญ่', 'บางเลน', 'บางม่วง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นนทบุรี' AND district = 'ปากเกร็ด' AND sub_district IN ('บางพลับ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นนทบุรี' AND district = 'ไทรน้อย' AND sub_district IN ('ไทรน้อย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นราธิวาส' AND district = 'บาเจาะ' AND sub_district IN ('บาเจาะ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นราธิวาส' AND district = 'ยี่งอ' AND sub_district IN ('ยี่งอ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นราธิวาส' AND district = 'ระแงะ' AND sub_district IN ('ตันหยงมัส', 'มะรือโบตก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นราธิวาส' AND district = 'รือเสาะ' AND sub_district IN ('รือเสาะ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นราธิวาส' AND district = 'ศรีสาคร' AND sub_district IN ('ศรีสาคร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นราธิวาส' AND district = 'สุคิริน' AND sub_district IN ('สุคิริน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นราธิวาส' AND district = 'สุไหงปาดี' AND sub_district IN ('ปะลุรู');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นราธิวาส' AND district = 'สุไหงโก-ลก' AND sub_district IN ('ปาเสมัส');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นราธิวาส' AND district = 'เมืองนราธิวาส' AND sub_district IN ('กะลุวอเหนือ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'นราธิวาส' AND district = 'แว้ง' AND sub_district IN ('แว้ง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'น่าน' AND district = 'ทุ่งช้าง' AND sub_district IN ('งอบ', 'ทุ่งช้าง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'น่าน' AND district = 'ท่าวังผา' AND sub_district IN ('ท่าวังผา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'น่าน' AND district = 'นาน้อย' AND sub_district IN ('นาน้อย', 'ศรีษะเกษ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'น่าน' AND district = 'นาหมื่น' AND sub_district IN ('บ่อแก้ว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'น่าน' AND district = 'บ่อเกลือ' AND sub_district IN ('บ่อเกลือใต้');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'น่าน' AND district = 'ปัว' AND sub_district IN ('ปัว', 'ศิลาแลง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'น่าน' AND district = 'สองแคว' AND sub_district IN ('ยอด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'น่าน' AND district = 'เชียงกลาง' AND sub_district IN ('พญาแก้ว', 'พระพุทธบาท', 'เชียงกลาง', 'เชียงคาน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'น่าน' AND district = 'เมืองน่าน' AND sub_district IN ('ดู่ใต้', 'กองควาย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'น่าน' AND district = 'เวียงสา' AND sub_district IN ('กลางเวียง', 'ขึ่ง', 'ปงสนุก', 'ส้านนาหนองใหม่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'น่าน' AND district = 'แม่จริม' AND sub_district IN ('หนองแดง', 'น้ำปาย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บึงกาฬ' AND district = 'บึงโขงหลง' AND sub_district IN ('บึงโขงหลง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บึงกาฬ' AND district = 'ปากคาด' AND sub_district IN ('ปากคาด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บึงกาฬ' AND district = 'พรเจริญ' AND sub_district IN ('ดอนหญ้านาง', 'พรเจริญ', 'ศรีสำราญ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บึงกาฬ' AND district = 'ศรีวิไล' AND sub_district IN ('ศรีวิไล');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บึงกาฬ' AND district = 'เซกา' AND sub_district IN ('ป่งไฮ', 'ซาง', 'ท่าสะอาด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บึงกาฬ' AND district = 'เมืองบึงกาฬ' AND sub_district IN ('หนองเลิง', 'โคกก่อง', 'หอคำ', 'โนนสว่าง', 'ไคสี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'กระสัง' AND sub_district IN ('กระสัง', 'สองชั้น', 'หนองเต็ง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'คูเมือง' AND sub_district IN ('หินเหล็กไฟ', 'คูเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'ชำนิ' AND sub_district IN ('หนองปล่อง', 'ชำนิ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'นางรอง' AND sub_district IN ('ทุ่งแสงทอง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'นาโพธิ์' AND sub_district IN ('นาโพธิ์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'บ้านกรวด' AND sub_district IN ('โนนเจริญ', 'หนองไม้งาม', 'จันทบเพชร', 'ปราสาท', 'บ้านกรวด', 'บึงเจริญ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'บ้านด่าน' AND sub_district IN ('ปราสาท', 'บ้านด่าน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'ประโคนชัย' AND sub_district IN ('โคกม้า', 'ประโคนชัย', 'เขาคอก', 'แสลงโทน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'ปะคำ' AND sub_district IN ('ปะคำ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'พลับพลาชัย' AND sub_district IN ('จันดุม', 'โคกขมิ้น');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'พุทไธสง' AND sub_district IN ('พุทไธสง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'ละหานทราย' AND sub_district IN ('หนองแวง', 'หนองตะครอง', 'สำโรงใหม่', 'ละหานทราย', 'ตาจง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'ลำปลายมาศ' AND sub_district IN ('ลำปลายมาศ', 'ทะเมนชัย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'สตึก' AND sub_district IN ('สตึก', 'ดอนมนต์', 'สะแก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'หนองกี่' AND sub_district IN ('หนองกี่', 'ดอนอะราง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'หนองหงส์' AND sub_district IN ('ห้วยหิน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'ห้วยราช' AND sub_district IN ('โคกเหล็ก', 'ห้วยราชา', 'ห้วยราช', 'สามแวง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'เฉลิมพระเกียรติ' AND sub_district IN ('ยายแย้มวัฒนา', 'ถาวร', 'ตาเป๊ก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'เมืองบุรีรัมย์' AND sub_district IN ('หนองตาด', 'หลักเขต', 'อิสาณ', 'บ้านบัว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'แคนดง' AND sub_district IN ('แคนดง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'โนนดินแดง' AND sub_district IN ('โนนดินแดง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'บุรีรัมย์' AND district = 'โนนสุวรรณ' AND sub_district IN ('โกรกแก้ว', 'โนนสุวรรณ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปทุมธานี' AND district = 'ลาดหลุมแก้ว' AND sub_district IN ('คลองพระอุดม', 'คูขวาง', 'ระแหง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปทุมธานี' AND district = 'ลำลูกกา' AND sub_district IN ('ลำลูกกา', 'ลำไทร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปทุมธานี' AND district = 'สามโคก' AND sub_district IN ('สามโคก', 'เชียงรากใหญ่', 'บางเตย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปทุมธานี' AND district = 'หนองเสือ' AND sub_district IN ('หนองสามวัง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปทุมธานี' AND district = 'เมืองปทุมธานี' AND sub_district IN ('บ้านกลาง', 'บ้านใหม่', 'หลักหก', 'บางหลวง', 'บางพูน', 'บางขะแยง', 'บางเดื่อ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ประจวบคีรีขันธ์' AND district = 'กุยบุรี' AND sub_district IN ('กุยบุรี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ประจวบคีรีขันธ์' AND district = 'ทับสะแก' AND sub_district IN ('ทับสะแก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ประจวบคีรีขันธ์' AND district = 'บางสะพาน' AND sub_district IN ('ร่อนทอง', 'กำเนิดนพคุณ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ประจวบคีรีขันธ์' AND district = 'ปราณบุรี' AND sub_district IN ('ปากน้ำปราณ', 'เขาน้อย', 'ปราณบุรี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ประจวบคีรีขันธ์' AND district = 'สามร้อยยอด' AND sub_district IN ('ไร่ใหม่', 'ไร่เก่า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ประจวบคีรีขันธ์' AND district = 'หัวหิน' AND sub_district IN ('หนองพลับ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ประจวบคีรีขันธ์' AND district = 'เมืองประจวบคีรีขันธ์' AND sub_district IN ('คลองวาฬ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปราจีนบุรี' AND district = 'กบินทร์บุรี' AND sub_district IN ('กบินทร์', 'เมืองเก่า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปราจีนบุรี' AND district = 'นาดี' AND sub_district IN ('นาดี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปราจีนบุรี' AND district = 'บ้านสร้าง' AND sub_district IN ('บ้านสร้าง', 'กระทุ่มแพ้ว', 'บางขาม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปราจีนบุรี' AND district = 'ประจันตคาม' AND sub_district IN ('ประจันตคาม', 'โพธิ์งาม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปราจีนบุรี' AND district = 'ศรีมหาโพธิ' AND sub_district IN ('หาดยาง', 'สัมพันธ์', 'กรอกสมบูรณ์', 'บางกุ้ง', 'ศรีมหาโพธิ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปราจีนบุรี' AND district = 'ศรีมโหสถ' AND sub_district IN ('โคกปีบ', 'คู้ลำพัน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปัตตานี' AND district = 'ปะนาเระ' AND sub_district IN ('พ่อมิ่ง', 'ปะนาเระ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปัตตานี' AND district = 'มายอ' AND sub_district IN ('มายอ', 'ปานัน', 'สาคอใต้');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปัตตานี' AND district = 'ยะรัง' AND sub_district IN ('ยะรัง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปัตตานี' AND district = 'ยะหริ่ง' AND sub_district IN ('ตอหลัง', 'ตันหยงจึงงา', 'บางปู', 'ปุลากง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปัตตานี' AND district = 'สายบุรี' AND sub_district IN ('เตราะบอน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปัตตานี' AND district = 'หนองจิก' AND sub_district IN ('บ่อทอง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปัตตานี' AND district = 'เมืองปัตตานี' AND sub_district IN ('รูสะมิแล');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ปัตตานี' AND district = 'โคกโพธิ์' AND sub_district IN ('โคกโพธิ์', 'มะกรูด', 'นาประดู่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พระนครศรีอยุธยา' AND district = 'ท่าเรือ' AND sub_district IN ('ท่าหลวง', 'ท่าเรือ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พระนครศรีอยุธยา' AND district = 'นครหลวง' AND sub_district IN ('ท่าช้าง', 'นครหลวง', 'บางพระครู', 'บางระกำ', 'พระนอน', 'สามไถ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พระนครศรีอยุธยา' AND district = 'บางซ้าย' AND sub_district IN ('แก้วฟ้า', 'เต่าเล่า', 'บางซ้าย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พระนครศรีอยุธยา' AND district = 'บางบาล' AND sub_district IN ('บ้านกุ่ม', 'ทางช้าง', 'บางชะนี', 'บางบาล', 'บางหลวง', 'มหาพราหมณ์', 'วัดตะกู', 'วัดยม', 'สะพานไทย', 'ไทรน้อย', 'บางหลวงโดด', 'บางหัก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พระนครศรีอยุธยา' AND district = 'บางปะหัน' AND sub_district IN ('ขยาย', 'บ้านม้า', 'บางเพลิง', 'บางปะหัน', 'บางนางร้า', 'ทางกลาง', 'ตาลเอน', 'ขวัญเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พระนครศรีอยุธยา' AND district = 'บางปะอิน' AND sub_district IN ('ตลาดเกรียบ', 'บางกระสั้น', 'เชียงรากน้อย', 'คลองจิก', 'บ้านสร้าง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พระนครศรีอยุธยา' AND district = 'บางไทร' AND sub_district IN ('กกแก้วบูรพา', 'แคตก', 'เชียงรากน้อย', 'ห่อหมก', 'หน้าไม้', 'ราชคราม', 'บ้านแป้ง', 'บ้านเกาะ', 'บางไทร', 'บางพลี', 'ช้างใหญ่', 'ช้างน้อย', 'ช่างเหล็ก', 'แคออก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พระนครศรีอยุธยา' AND district = 'บ้านแพรก' AND sub_district IN ('บ้านแพรก', 'สองห้อง', 'บ้านใหม่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พระนครศรีอยุธยา' AND district = 'ภาชี' AND sub_district IN ('ภาชี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พระนครศรีอยุธยา' AND district = 'มหาราช' AND sub_district IN ('บ้านใหม่', 'พิตเพียน', 'มหาราช', 'หัวไผ่', 'โรงช้าง', 'กะทุ่ม', 'น้ำเต้า', 'เจ้าปลุก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พระนครศรีอยุธยา' AND district = 'ลาดบัวหลวง' AND sub_district IN ('สามเมือง', 'ลาดบัวหลวง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พระนครศรีอยุธยา' AND district = 'อุทัย' AND sub_district IN ('อุทัย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พระนครศรีอยุธยา' AND district = 'เสนา' AND sub_district IN ('เจ้าเจ็ด', 'หัวเวียง', 'สามกอ', 'บางนมโค');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พะเยา' AND district = 'จุน' AND sub_district IN ('ทุ่งรวงทอง', 'จุน', 'ลอ', 'หงส์หิน', 'ห้วยข้าวก่ำ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พะเยา' AND district = 'ดอกคำใต้' AND sub_district IN ('ห้วยลาน', 'บ้านถ้ำ', 'หนองหล่ม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พะเยา' AND district = 'ปง' AND sub_district IN ('ปง', 'งิม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พะเยา' AND district = 'ภูกามยาว' AND sub_district IN ('ดงเจน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พะเยา' AND district = 'ภูซาง' AND sub_district IN ('สบบง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พะเยา' AND district = 'เชียงคำ' AND sub_district IN ('ฝายกวาง', 'หย่วน', 'เวียง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พะเยา' AND district = 'เชียงม่วน' AND sub_district IN ('เชียงม่วน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พะเยา' AND district = 'เมืองพะเยา' AND sub_district IN ('ท่าจำปี', 'ท่าวังทอง', 'บ้านต๊ำ', 'บ้านต๋อม', 'บ้านสาง', 'บ้านใหม่', 'สันป่าม่วง', 'แม่กา', 'แม่ปืม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พะเยา' AND district = 'แม่ใจ' AND sub_district IN ('ป่าแฝก', 'ศรีถ้อย', 'เจริญราษฎร์', 'แม่ใจ', 'บ้านเหล่า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พังงา' AND district = 'กะปง' AND sub_district IN ('ท่านา', 'กะปง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พังงา' AND district = 'ตะกั่วทุ่ง' AND sub_district IN ('โคกกลอย', 'กระโสม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พังงา' AND district = 'ตะกั่วป่า' AND sub_district IN ('บางนายสี', 'คึกคัก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พังงา' AND district = 'ทับปุด' AND sub_district IN ('ทับปุด', 'ถ้ำทองหลาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พังงา' AND district = 'ท้ายเหมือง' AND sub_district IN ('ลำแก่น', 'ท้ายเหมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พังงา' AND district = 'เกาะยาว' AND sub_district IN ('พรุใน', 'เกาะยาวใหญ่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พังงา' AND district = 'เมืองพังงา' AND sub_district IN ('บางเตย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พัทลุง' AND district = 'กงหรา' AND sub_district IN ('สมหวัง', 'ชะรัด', 'คลองทรายขาว', 'กงหรา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พัทลุง' AND district = 'ควนขนุน' AND sub_district IN ('โตนดด้วน', 'แหลมโตนด', 'แพรกหา', 'มะกอกเหนือ', 'พนางตุง', 'ควนขนุน', 'นาขยาด', 'ทะเลน้อย', 'ดอนทราย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พัทลุง' AND district = 'ตะโหมด' AND sub_district IN ('คลองใหญ่', 'ตะโหมด', 'แม่ขรี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พัทลุง' AND district = 'บางแก้ว' AND sub_district IN ('ท่ามะเดื่อ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พัทลุง' AND district = 'ปากพะยูน' AND sub_district IN ('เกาะนางคำ', 'ดอนทราย', 'ดอนประดู่', 'ปากพะยูน', 'หารเทา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พัทลุง' AND district = 'ป่าบอน' AND sub_district IN ('ป่าบอน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พัทลุง' AND district = 'ป่าพะยอม' AND sub_district IN ('ลานข่อย', 'บ้านพร้าว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พัทลุง' AND district = 'ศรีนครินทร์' AND sub_district IN ('อ่างทอง', 'ลำสินธุ์', 'บ้านนา', 'ชุมพล');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พัทลุง' AND district = 'เขาชัยสน' AND sub_district IN ('โคกม่วง', 'จองถนน', 'เขาชัยสน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พัทลุง' AND district = 'เมืองพัทลุง' AND sub_district IN ('ตำนาน', 'ท่ามิหรำ', 'ท่าแค', 'นาท่อม', 'นาโหนด', 'ปรางหมู่', 'พญาขัน', 'ร่มเมือง', 'เขาเจียก', 'โคกชะงาย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิจิตร' AND district = 'ดงเจริญ' AND sub_district IN ('สำนักขุนเณร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิจิตร' AND district = 'ตะพานหิน' AND sub_district IN ('หนองพยอม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิจิตร' AND district = 'ทับคล้อ' AND sub_district IN ('เขาทราย', 'ทับคล้อ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิจิตร' AND district = 'บางมูลนาก' AND sub_district IN ('หอไกร', 'บางไผ่', 'วังตะกู', 'เนินมะกอก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิจิตร' AND district = 'วังทรายพูน' AND sub_district IN ('หนองปล้อง', 'วังทรายพูน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิจิตร' AND district = 'สากเหล็ก' AND sub_district IN ('สากเหล็ก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิจิตร' AND district = 'สามง่าม' AND sub_district IN ('เนินปอ', 'กำแพงดิน', 'สามง่าม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิจิตร' AND district = 'เมืองพิจิตร' AND sub_district IN ('ดงป่าคำ', 'ท่าฬ่อ', 'หัวดง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิจิตร' AND district = 'โพทะเล' AND sub_district IN ('โพทะเล', 'ท่าเสา', 'ทุ่งน้อย', 'บางคลาน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิจิตร' AND district = 'โพธิ์ประทับช้าง' AND sub_district IN ('วังจิก', 'โพธิ์ประทับช้าง', 'ไผ่รอบ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิษณุโลก' AND district = 'ชาติตระการ' AND sub_district IN ('ป่าแดง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิษณุโลก' AND district = 'นครไทย' AND sub_district IN ('นครไทย', 'บ้านแยง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิษณุโลก' AND district = 'บางกระทุ่ม' AND sub_district IN ('บางกระทุ่ม', 'เนินกุ่ม', 'สนามคลี', 'วัดตายม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิษณุโลก' AND district = 'บางระกำ' AND sub_district IN ('พันเสา', 'ปลักแรด', 'บางระกำ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิษณุโลก' AND district = 'พรหมพิราม' AND sub_district IN ('พรหมพิราม', 'วงฆ้อง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิษณุโลก' AND district = 'วังทอง' AND sub_district IN ('วังทอง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิษณุโลก' AND district = 'วัดโบสถ์' AND sub_district IN ('วัดโบสถ์', 'ท้อแท้');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิษณุโลก' AND district = 'เนินมะปราง' AND sub_district IN ('ไทรย้อย', 'เนินมะปราง', 'บ้านมุง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'พิษณุโลก' AND district = 'เมืองพิษณุโลก' AND sub_district IN ('หัวรอ', 'พลายชุมพล', 'บ้านคลอง', 'ท่าทอง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ภูเก็ต' AND district = 'ถลาง' AND sub_district IN ('ป่าคลอก', 'ศรีสุนทร', 'เทพกระษัตรี', 'เชิงทะเล');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ภูเก็ต' AND district = 'เมืองภูเก็ต' AND sub_district IN ('วิชิต', 'ราไวย์', 'รัษฎา', 'ฉลอง', 'กะรน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'มหาสารคาม' AND district = 'กันทรวิชัย' AND sub_district IN ('ท่าขอนยาง', 'ขามเรียง', 'โคกพระ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'มหาสารคาม' AND district = 'ชื่นชม' AND sub_district IN ('หนองกุง', 'กุดปลาดุก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'มหาสารคาม' AND district = 'นาดูน' AND sub_district IN ('หนองไผ่', 'หัวดง', 'นาดูน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'มหาสารคาม' AND district = 'นาเชือก' AND sub_district IN ('นาเชือก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'มหาสารคาม' AND district = 'บรบือ' AND sub_district IN ('บรบือ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'มหาสารคาม' AND district = 'เชียงยืน' AND sub_district IN ('โพนทอง', 'เชียงยืน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'มหาสารคาม' AND district = 'เมืองมหาสารคาม' AND sub_district IN ('แวงน่าง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'มหาสารคาม' AND district = 'แกดำ' AND sub_district IN ('แกดำ', 'มิตรภาพ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'มุกดาหาร' AND district = 'คำชะอี' AND sub_district IN ('คำชะอี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'มุกดาหาร' AND district = 'ดงหลวง' AND sub_district IN ('หนองแคน', 'กกตูม', 'ดงหลวง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'มุกดาหาร' AND district = 'ดอนตาล' AND sub_district IN ('บ้านแก้ง', 'ดอนตาล');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'มุกดาหาร' AND district = 'นิคมคำสร้อย' AND sub_district IN ('ร่มเกล้า', 'นิคมคำสร้อย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'มุกดาหาร' AND district = 'หนองสูง' AND sub_district IN ('บ้านเป้า', 'หนองสูงเหนือ', 'หนองสูง', 'ภูวง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'มุกดาหาร' AND district = 'หว้านใหญ่' AND sub_district IN ('ชะโนด', 'ดงหมู', 'หว้านใหญ่', 'ป่งขาม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'มุกดาหาร' AND district = 'เมืองมุกดาหาร' AND sub_district IN ('โพนทราย', 'ผึ่งแดด', 'บางทรายใหญ่', 'นาสีนวน', 'ดงเย็น', 'ดงมอน', 'คำอาฮวน', 'คำป่าหลาย', 'นาโสก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ยะลา' AND district = 'บันนังสตา' AND sub_district IN ('บันนังสตา', 'เขื่อนบางลาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ยะลา' AND district = 'ยะหา' AND sub_district IN ('ปะแต', 'ยะหา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ยะลา' AND district = 'รามัน' AND sub_district IN ('โกตาบารู', 'ตะโล๊ะหะลอ', 'บาลอ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ยะลา' AND district = 'เบตง' AND sub_district IN ('ธารน้ำทิพย์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ยะลา' AND district = 'เมืองยะลา' AND sub_district IN ('ลำใหม่', 'ยุโป', 'บุดี', 'ท่าสาป');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ยโสธร' AND district = 'คำเขื่อนแก้ว' AND sub_district IN ('ดงแคนใหญ่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ยโสธร' AND district = 'ค้อวัง' AND sub_district IN ('ค้อวัง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ยโสธร' AND district = 'ทรายมูล' AND sub_district IN ('ทรายมูล', 'นาเวียง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ยโสธร' AND district = 'มหาชนะชัย' AND sub_district IN ('ฟ้าหยาด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ยโสธร' AND district = 'เมืองยโสธร' AND sub_district IN ('สำราญ', 'น้ำคำใหญ่', 'ทุ่งแต้', 'ตาดทอง', 'เดิด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ยโสธร' AND district = 'เลิงนกทา' AND sub_district IN ('ห้องแซง', 'กุดเชียงหมี', 'กุดแห่', 'บุ่งค้า', 'ศรีแก้ว', 'สวาท', 'สามัคคี', 'สามแยก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ยโสธร' AND district = 'ไทยเจริญ' AND sub_district IN ('คำเตย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ระนอง' AND district = 'กระบุรี' AND sub_district IN ('น้ำจืด', 'จ.ป.ร.');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ระนอง' AND district = 'กะเปอร์' AND sub_district IN ('กะเปอร์', 'เชี่ยวเหลียง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ระนอง' AND district = 'ละอุ่น' AND sub_district IN ('ในวงใต้', 'บางพระใต้', 'ละอุ่นใต้', 'ในวงเหนือ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ระนอง' AND district = 'สุขสำราญ' AND sub_district IN ('กำพวน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ระนอง' AND district = 'เมืองระนอง' AND sub_district IN ('หงาว', 'ปากน้ำ', 'บางนอน', 'ราชกรูด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ระยอง' AND district = 'นิคมพัฒนา' AND sub_district IN ('มาบข่า', 'มะขามคู่', 'นิคมพัฒนา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ระยอง' AND district = 'บ้านค่าย' AND sub_district IN ('บ้านค่าย', 'ชากบก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ระยอง' AND district = 'บ้านฉาง' AND sub_district IN ('สำนักท้อน', 'พลา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ระยอง' AND district = 'วังจันทร์' AND sub_district IN ('ชุมแสง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ระยอง' AND district = 'เขาชะเมา' AND sub_district IN ('ห้วยทับมอญ', 'ชำฆ้อ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ระยอง' AND district = 'เมืองระยอง' AND sub_district IN ('เนินพระ', 'เชิงเนิน', 'น้ำคอก', 'ทับมา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ระยอง' AND district = 'แกลง' AND sub_district IN ('เนินฆ้อ', 'สองสลึง', 'ปากน้ำกระแส', 'บ้านนา', 'ทุ่งควายกิน', 'ชากพง', 'กองดิน', 'กร่ำ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ราชบุรี' AND district = 'จอมบึง' AND sub_district IN ('จอมบึง', 'ด่านทับตะโก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ราชบุรี' AND district = 'ดำเนินสะดวก' AND sub_district IN ('ดำเนินสะดวก', 'ศรีสุราษฎร์', 'ประสาทสิทธิ์', 'บ้านไร่', 'บัวงาม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ราชบุรี' AND district = 'บางแพ' AND sub_district IN ('โพหัก', 'วังเย็น', 'บางแพ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ราชบุรี' AND district = 'บ้านโป่ง' AND sub_district IN ('กรับใหญ่', 'เบิกไพร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ราชบุรี' AND district = 'ปากท่อ' AND sub_district IN ('ทุ่งหลวง', 'ปากท่อ', 'วันดาว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ราชบุรี' AND district = 'วัดเพลง' AND sub_district IN ('วัดเพลง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ราชบุรี' AND district = 'สวนผึ้ง' AND sub_district IN ('สวนผึ้ง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ราชบุรี' AND district = 'เมืองราชบุรี' AND sub_district IN ('หินกอง', 'หลุมดิน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ราชบุรี' AND district = 'โพธาราม' AND sub_district IN ('เจ็ดเสมียน', 'หนองโพ', 'บ้านเลือก', 'บ้านสิงห์', 'บ้านฆ้อง', 'ดอนทราย', 'คลองตาคต');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'จตุรพักตรพิมาน' AND sub_district IN ('ดงแดง', 'ลิ้นฟ้า', 'หนองผือ', 'หัวช้าง', 'เมืองหงส์', 'โคกล่าม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'จังหาร' AND sub_district IN ('ดงสิงห์', 'ดินดำ', 'จังหาร', 'ผักแว่น');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'ธวัชบุรี' AND sub_district IN ('มะอึ', 'อุ่มเม้า', 'นิเวศน์', 'ธงธานี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'ปทุมรัตต์' AND sub_district IN ('โพนสูง', 'โนนสวรรค์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'พนมไพร' AND sub_district IN ('โพธิ์ชัย', 'พนมไพร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'ศรีสมเด็จ' AND sub_district IN ('โพธิ์ทอง', 'บ้านบาก', 'ศรีสมเด็จ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'สุวรรณภูมิ' AND sub_district IN ('จำปาขัน', 'หินกอง', 'ทุ่งหลวง', 'ทุ่งกุลา', 'ดอกไม้');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'หนองพอก' AND sub_district IN ('หนองพอก', 'ท่าสีดา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'หนองฮี' AND sub_district IN ('หนองฮี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'อาจสามารถ' AND sub_district IN ('โพนเมือง', 'อาจสามารถ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'เกษตรวิสัย' AND sub_district IN ('กู่กาสิงห์', 'เมืองบัว', 'เกษตรวิสัย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'เชียงขวัญ' AND sub_district IN ('เชียงขวัญ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'เมยวดี' AND sub_district IN ('เมยวดี', 'บุ่งเลิศ', 'ชุมพร', 'ชมสะอาด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'เมืองร้อยเอ็ด' AND sub_district IN ('สีแก้ว', 'โนนตาล');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'เมืองสรวง' AND sub_district IN ('หนองหิน', 'เมืองสรวง', 'คูเมือง', 'กกกุง', 'หนองผือ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'เสลภูมิ' AND sub_district IN ('พรสวรรค์', 'นาเมือง', 'ท่าม่วง', 'ขวาว', 'ขวัญเมือง', 'กลาง', 'เมืองไพร', 'เกาะแก้ว', 'หนองหลวง', 'วังหลวง', 'นาแซง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'โพธิ์ชัย' AND sub_district IN ('เชียงใหม่', 'อัคคะคำ', 'คำพอุง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'โพนทราย' AND sub_district IN ('โพนทราย', 'สามขา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ร้อยเอ็ด' AND district = 'โพนทอง' AND sub_district IN ('แวง', 'โคกกกม่วง', 'โคกสูง', 'โนนชัยศรี', 'โพธิ์ทอง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลพบุรี' AND district = 'ชัยบาดาล' AND sub_district IN ('ลำนารายณ์', 'มะกอกหวาน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลพบุรี' AND district = 'ท่าวุ้ง' AND sub_district IN ('ท่าวุ้ง', 'โพตลาดแก้ว', 'โคกสลุด', 'ลาดสาลี่', 'บางงา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลพบุรี' AND district = 'ท่าหลวง' AND sub_district IN ('ทะเลวังวัด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลพบุรี' AND district = 'พัฒนานิคม' AND sub_district IN ('ดีลัง', 'พัฒนานิคม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลพบุรี' AND district = 'สระโบสถ์' AND sub_district IN ('ห้วยใหญ่', 'สระโบสถ์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลพบุรี' AND district = 'หนองม่วง' AND sub_district IN ('หนองม่วง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลพบุรี' AND district = 'เมืองลพบุรี' AND sub_district IN ('กกโก', 'ถนนใหญ่', 'ท่าศาลา', 'ป่าตาล', 'เขาพระงาม', 'โคกตูม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลพบุรี' AND district = 'โคกสำโรง' AND sub_district IN ('โคกสำโรง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำปาง' AND district = 'งาว' AND sub_district IN ('หลวงใต้', 'หลวงเหนือ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำปาง' AND district = 'วังเหนือ' AND sub_district IN ('วังเหนือ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำปาง' AND district = 'สบปราบ' AND sub_district IN ('สบปราบ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำปาง' AND district = 'ห้างฉัตร' AND sub_district IN ('เวียงตาล', 'เมืองยาว', 'ปงยางคก', 'ห้างฉัตร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำปาง' AND district = 'เกาะคา' AND sub_district IN ('นาแก้ว', 'ท่าผา', 'ไหล่หิน', 'เกาะคา', 'ศาลา', 'วังพร้าว', 'ลำปางหลวง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำปาง' AND district = 'เถิน' AND sub_district IN ('แม่มอก', 'เวียงมอก', 'เถินบุรี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำปาง' AND district = 'เมืองปาน' AND sub_district IN ('เมืองปาน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำปาง' AND district = 'เมืองลำปาง' AND sub_district IN ('บ่อแฮ้ว', 'ต้นธงชัย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำปาง' AND district = 'เสริมงาม' AND sub_district IN ('ทุ่งงาม', 'เสริมซ้าย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำปาง' AND district = 'แจ้ห่ม' AND sub_district IN ('แจ้ห่ม', 'ทุ่งผึ้ง', 'บ้านสา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำปาง' AND district = 'แม่ทะ' AND sub_district IN ('แม่ทะ', 'นาครัว', 'น้ำโจ้', 'ป่าตัน', 'สันดอนแก้ว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำปาง' AND district = 'แม่พริก' AND sub_district IN ('แม่พริก', 'แม่ปุ', 'พระบาทวังตวง', 'ผาปัง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำปาง' AND district = 'แม่เมาะ' AND sub_district IN ('แม่เมาะ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำพูน' AND district = 'ทุ่งหัวช้าง' AND sub_district IN ('ทุ่งหัวช้าง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำพูน' AND district = 'บ้านธิ' AND sub_district IN ('บ้านธิ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำพูน' AND district = 'บ้านโฮ่ง' AND sub_district IN ('บ้านโฮ่ง', 'ศรีเตี้ย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำพูน' AND district = 'ป่าซาง' AND sub_district IN ('แม่แรง', 'ม่วงน้อย', 'มะกอก', 'ป่าซาง', 'ปากบ่อง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำพูน' AND district = 'ลี้' AND sub_district IN ('ศรีวิชัย', 'ลี้', 'ป่าไผ่', 'ดงดำ', 'ก้อ', 'แม่ตืน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำพูน' AND district = 'เมืองลำพูน' AND sub_district IN ('ต้นธง', 'เหมืองง่า', 'เวียงยอง', 'อุโมงค์', 'หนองช้างคืน', 'ศรีบัวบาน', 'ริมปิง', 'มะเขือแจ้', 'ป่าสัก', 'ประตูป่า', 'บ้านแป้น', 'บ้านกลาง', 'เหมืองจี้');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำพูน' AND district = 'เวียงหนองล่อง' AND sub_district IN ('หนองยวง', 'หนองล่อง', 'วังผาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ลำพูน' AND district = 'แม่ทา' AND sub_district IN ('ทาปลาดุก', 'ทาสบเส้า', 'ทาทุ่งหลวง', 'ทากาศ', 'ทาขุมเงิน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ศรีสะเกษ' AND district = 'กันทรลักษ์' AND sub_district IN ('หนองหญ้าลาด', 'สวนกล้วย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ศรีสะเกษ' AND district = 'ขุขันธ์' AND sub_district IN ('ศรีสะอาด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ศรีสะเกษ' AND district = 'ขุนหาญ' AND sub_district IN ('กันทรอม', 'กระหวัน', 'โพธิ์กระสังข์', 'โนนสูง', 'สิ', 'ขุนหาญ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ศรีสะเกษ' AND district = 'บึงบูรพ์' AND sub_district IN ('บึงบูรพ์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ศรีสะเกษ' AND district = 'พยุห์' AND sub_district IN ('พยุห์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ศรีสะเกษ' AND district = 'ยางชุมน้อย' AND sub_district IN ('ยางชุมน้อย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ศรีสะเกษ' AND district = 'ราษีไศล' AND sub_district IN ('บัวหุ่ง', 'ส้มป่อย', 'เมืองคง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ศรีสะเกษ' AND district = 'วังหิน' AND sub_district IN ('บุสูง', 'วังหิน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ศรีสะเกษ' AND district = 'ห้วยทับทัน' AND sub_district IN ('จานแสนไชย', 'ห้วยทับทัน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ศรีสะเกษ' AND district = 'อุทุมพรพิสัย' AND sub_district IN ('กำแพง', 'โคกจาน', 'แต้', 'สระกำแพงใหญ่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ศรีสะเกษ' AND district = 'เมืองจันทร์' AND sub_district IN ('หนองใหญ่', 'เมืองจันทร์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ศรีสะเกษ' AND district = 'เมืองศรีสะเกษ' AND sub_district IN ('น้ำคำ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ศรีสะเกษ' AND district = 'โพธิ์ศรีสุวรรณ' AND sub_district IN ('ผือใหญ่', 'โดด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'ศรีสะเกษ' AND district = 'ไพรบึง' AND sub_district IN ('สำโรงพลัน', 'ไพรบึง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สกลนคร' AND district = 'กุดบาก' AND sub_district IN ('กุดไห', 'กุดบาก', 'นาม่อง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สกลนคร' AND district = 'กุสุมาลย์' AND sub_district IN ('กุสุมาลย์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สกลนคร' AND district = 'คำตากล้า' AND sub_district IN ('คำตากล้า', 'แพด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สกลนคร' AND district = 'บ้านม่วง' AND sub_district IN ('ห้วยหลัว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สกลนคร' AND district = 'พรรณานิคม' AND sub_district IN ('นาหัวบ่อ', 'นาใน', 'พรรณา', 'วังยาง', 'สว่าง', 'ไร่', 'พอกน้อย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สกลนคร' AND district = 'พังโคน' AND sub_district IN ('แร่', 'พังโคน', 'ไฮหย่อง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สกลนคร' AND district = 'ภูพาน' AND sub_district IN ('สร้างค้อ', 'โคกภู');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สกลนคร' AND district = 'วานรนิวาส' AND sub_district IN ('หนองแวง', 'หนองสนม', 'กุดเรือคำ', 'นาซอ', 'คูสะคาม', 'วานรนิวาส');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สกลนคร' AND district = 'วาริชภูมิ' AND sub_district IN ('วาริชภูมิ', 'คำบ่อ', 'หนองลาด', 'ปลาโหล');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สกลนคร' AND district = 'สว่างแดนดิน' AND sub_district IN ('หนองหลวง', 'สว่างแดนดิน', 'พันนา', 'บ้านต้าย', 'บงใต้', 'โคกสี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สกลนคร' AND district = 'ส่องดาว' AND sub_district IN ('ท่าศิลา', 'ปทุมวาปี', 'วัฒนา', 'ส่องดาว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สกลนคร' AND district = 'อากาศอำนวย' AND sub_district IN ('โพนแพง', 'ท่าก้อน', 'บะหว้า', 'วาใหญ่', 'สามัคคีพัฒนา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สกลนคร' AND district = 'เจริญศิลป์' AND sub_district IN ('เจริญศิลป์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สกลนคร' AND district = 'เมืองสกลนคร' AND sub_district IN ('ธาตุนาเวง', 'ท่าแร่', 'ดงมะไฟ', 'งิ้วด่อน', 'หนองลาด', 'ฮางโฮง', 'เชียงเครือ', 'เหล่าปอแดง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สกลนคร' AND district = 'โคกศรีสุพรรณ' AND sub_district IN ('ตองโขบ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สกลนคร' AND district = 'โพนนาแก้ว' AND sub_district IN ('บ้านโพน', 'นาแก้ว', 'เชียงสือ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สงขลา' AND district = 'กระแสสินธุ์' AND sub_district IN ('กระแสสินธุ์', 'เชิงแส');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สงขลา' AND district = 'คลองหอยโข่ง' AND sub_district IN ('โคกม่วง', 'ทุ่งลาน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สงขลา' AND district = 'ควนเนียง' AND sub_district IN ('บางเหรียง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สงขลา' AND district = 'จะนะ' AND sub_district IN ('บ้านนา', 'นาทับ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สงขลา' AND district = 'นาทวี' AND sub_district IN ('นาทวี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สงขลา' AND district = 'บางกล่ำ' AND sub_district IN ('ท่าช้าง', 'บ้านหาร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สงขลา' AND district = 'ระโนด' AND sub_district IN ('ปากแตระ', 'ระโนด', 'บ่อตรุ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สงขลา' AND district = 'รัตภูมิ' AND sub_district IN ('คูหาใต้');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สงขลา' AND district = 'สะบ้าย้อย' AND sub_district IN ('สะบ้าย้อย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สงขลา' AND district = 'สะเดา' AND sub_district IN ('สำนักขาม', 'ปริก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สงขลา' AND district = 'สิงหนคร' AND sub_district IN ('ชะแล้');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สงขลา' AND district = 'หาดใหญ่' AND sub_district IN ('พะตง', 'น้ำน้อย', 'คูเต่า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สงขลา' AND district = 'เทพา' AND sub_district IN ('เทพา', 'ลำไพล');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สงขลา' AND district = 'เมืองสงขลา' AND sub_district IN ('พะวง', 'เกาะแต้ว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สตูล' AND district = 'ควนโดน' AND sub_district IN ('ควนโดน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สตูล' AND district = 'ทุ่งหว้า' AND sub_district IN ('ทุ่งหว้า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สตูล' AND district = 'ละงู' AND sub_district IN ('กำแพง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สตูล' AND district = 'เมืองสตูล' AND sub_district IN ('ฉลุง', 'คลองขุด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สมุทรปราการ' AND district = 'บางบ่อ' AND sub_district IN ('บางบ่อ', 'คลองสวน', 'บางพลีน้อย', 'คลองด่าน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สมุทรปราการ' AND district = 'บางเสาธง' AND sub_district IN ('บางเสาธง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สมุทรปราการ' AND district = 'พระสมุทรเจดีย์' AND sub_district IN ('แหลมฟ้าผ่า', 'ปากคลองบางปลากด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สมุทรปราการ' AND district = 'เมืองสมุทรปราการ' AND sub_district IN ('บางปู', 'บางเมือง', 'สำโรงเหนือ', 'เทพารักษ์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สมุทรสงคราม' AND district = 'บางคนที' AND sub_district IN ('ยายแพง', 'บ้านปราโมทย์', 'บางยี่รงค์', 'บางนกแขวก', 'บางกุ้ง', 'บางกระบือ', 'กระดังงา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สมุทรสงคราม' AND district = 'อัมพวา' AND sub_district IN ('เหมืองใหม่', 'อัมพวา', 'สวนหลวง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สมุทรสงคราม' AND district = 'เมืองสมุทรสงคราม' AND sub_district IN ('บางจะเกร็ง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สมุทรสาคร' AND district = 'กระทุ่มแบน' AND sub_district IN ('สวนหลวง', 'แคราย', 'ดอนไก่ดี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สมุทรสาคร' AND district = 'บ้านแพ้ว' AND sub_district IN ('โรงเข้', 'เกษตรพัฒนา', 'หนองสองห้อง', 'หนองบัว', 'ยกกระบัตร', 'บ้านแพ้ว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สมุทรสาคร' AND district = 'เมืองสมุทรสาคร' AND sub_district IN ('คอกกระบือ', 'ท่าจีน', 'นาดี', 'บางหญ้าแพรก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระบุรี' AND district = 'ดอนพุด' AND sub_district IN ('ไผ่หลิ่ว', 'บ้านหลวง', 'ดอนพุด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระบุรี' AND district = 'บ้านหมอ' AND sub_district IN ('โคกใหญ่', 'หรเทพ', 'หนองบัว', 'ตลาดน้อย', 'บ้านหมอ', 'บ้านครัว', 'บางโขมด', 'สร่างโศก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระบุรี' AND district = 'พระพุทธบาท' AND sub_district IN ('ธารเกษม', 'นายาว', 'พุกร่าง', 'หนองแก', 'ห้วยป่าหวาย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระบุรี' AND district = 'มวกเหล็ก' AND sub_district IN ('มวกเหล็ก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระบุรี' AND district = 'วังม่วง' AND sub_district IN ('แสลงพัน', 'วังม่วง', 'คำพราน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระบุรี' AND district = 'วิหารแดง' AND sub_district IN ('วิหารแดง', 'หนองหมู');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระบุรี' AND district = 'หนองแค' AND sub_district IN ('คชสิทธิ์', 'ไผ่ต่ำ', 'โพนทอง', 'โคกตูม', 'หนองแค');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระบุรี' AND district = 'หนองแซง' AND sub_district IN ('เขาดิน', 'หนองแซง', 'หนองสีดา', 'หนองควายโซ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระบุรี' AND district = 'หนองโดน' AND sub_district IN ('หนองโดน', 'บ้านโปร่ง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระบุรี' AND district = 'เฉลิมพระเกียรติ' AND sub_district IN ('หน้าพระลาน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระบุรี' AND district = 'เมืองสระบุรี' AND sub_district IN ('กุดนกเปล้า', 'ตะกุด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระบุรี' AND district = 'เสาไห้' AND sub_district IN ('เสาไห้', 'เมืองเก่า', 'หัวปลวก', 'สวนดอกไม้', 'งิ้วงาม', 'พระยาทด', 'บ้านยาง', 'ท่าช้าง', 'ต้นตาล', 'ศาลารีไทย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระแก้ว' AND district = 'คลองหาด' AND sub_district IN ('คลองหาด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระแก้ว' AND district = 'ตาพระยา' AND sub_district IN ('ตาพระยา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระแก้ว' AND district = 'วังสมบูรณ์' AND sub_district IN ('วังสมบูรณ์', 'วังทอง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระแก้ว' AND district = 'วัฒนานคร' AND sub_district IN ('วัฒนานคร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระแก้ว' AND district = 'อรัญประเทศ' AND sub_district IN ('ป่าไร่', 'บ้านใหม่หนองไทร', 'บ้านด่าน', 'ฟากห้วย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระแก้ว' AND district = 'เขาฉกรรจ์' AND sub_district IN ('เขาฉกรรจ์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระแก้ว' AND district = 'เมืองสระแก้ว' AND sub_district IN ('ท่าเกษม', 'ศาลาลำดวน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สระแก้ว' AND district = 'โคกสูง' AND sub_district IN ('โคกสูง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สิงห์บุรี' AND district = 'ค่ายบางระจัน' AND sub_district IN ('โพสังโฆ', 'บางระจัน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สิงห์บุรี' AND district = 'ท่าช้าง' AND sub_district IN ('ถอนสมอ', 'พิกุลทอง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สิงห์บุรี' AND district = 'พรหมบุรี' AND sub_district IN ('บางน้ำเชี่ยว', 'พรหมบุรี', 'หัวป่า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สิงห์บุรี' AND district = 'อินทร์บุรี' AND sub_district IN ('อินทร์บุรี', 'ทับยา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุพรรณบุรี' AND district = 'ดอนเจดีย์' AND sub_district IN ('ดอนเจดีย์', 'สระกระโจม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุพรรณบุรี' AND district = 'ด่านช้าง' AND sub_district IN ('ด่านช้าง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุพรรณบุรี' AND district = 'บางปลาม้า' AND sub_district IN ('โคกคราม', 'ไผ่กองดิน', 'ตะค่า', 'บ้านแหลม', 'บางปลาม้า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุพรรณบุรี' AND district = 'ศรีประจันต์' AND sub_district IN ('บ้านกร่าง', 'ปลายนา', 'ศรีประจันต์', 'วังน้ำซับ', 'วังยาง', 'วังหว้า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุพรรณบุรี' AND district = 'สองพี่น้อง' AND sub_district IN ('ทุ่งคอก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุพรรณบุรี' AND district = 'สามชุก' AND sub_district IN ('สามชุก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุพรรณบุรี' AND district = 'หนองหญ้าไซ' AND sub_district IN ('หนองหญ้าไซ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุพรรณบุรี' AND district = 'อู่ทอง' AND sub_district IN ('เจดีย์', 'อู่ทอง', 'สระยายโสม', 'กระจัน', 'บ้านโข้ง', 'บ้านดอน', 'จรเข้สามพัน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุพรรณบุรี' AND district = 'เดิมบางนางบวช' AND sub_district IN ('เดิมบาง', 'เขาพระ', 'เขาดิน', 'ทุ่งคลี', 'วังศรีราช', 'ปากน้ำ', 'บ่อกรุ', 'นางบวช', 'หนองกระทุ่ม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุพรรณบุรี' AND district = 'เมืองสุพรรณบุรี' AND sub_district IN ('สวนแตง', 'รั้วใหญ่', 'บ้านโพธิ์', 'บางกุ้ง', 'ท่าระหัด', 'โพธิ์พระยา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'กาญจนดิษฐ์' AND sub_district IN ('กะแดะ', 'ช้างขวา', 'ช้างซ้าย', 'กรูด', 'ท่าทองใหม่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'คีรีรัฐนิคม' AND sub_district IN ('ท่าขนอน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'ท่าฉาง' AND sub_district IN ('ท่าฉาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'ท่าชนะ' AND sub_district IN ('ท่าชนะ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'บ้านตาขุน' AND sub_district IN ('เขาพัง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'บ้านนาสาร' AND sub_district IN ('ท่าชี', 'คลองปราบ', 'ควนศรี', 'พรุพี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'บ้านนาเดิม' AND sub_district IN ('บ้านนา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'พนม' AND sub_district IN ('พังกาญจน์', 'คลองชะอุ่น', 'พนม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'พระแสง' AND sub_district IN ('บางสวรรค์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'เกาะพะงัน' AND sub_district IN ('เกาะเต่า', 'เกาะพะงัน', 'บ้านใต้');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'เคียนซา' AND sub_district IN ('เคียนซา', 'บ้านเสด็จ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'เมืองสุราษฎร์ธานี' AND sub_district IN ('ขุนทะเล', 'วัดประดู่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'เวียงสระ' AND sub_district IN ('ทุ่งหลวง', 'เวียงสระ', 'เขานิพันธ์', 'บ้านส้อง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุราษฎร์ธานี' AND district = 'ไชยา' AND sub_district IN ('ตลาดไชยา', 'เวียง', 'พุมเรียง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุรินทร์' AND district = 'กาบเชิง' AND sub_district IN ('โคกตะเคียน', 'กาบเชิง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุรินทร์' AND district = 'จอมพระ' AND sub_district IN ('บุแกรง', 'จอมพระ', 'กระหาด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุรินทร์' AND district = 'ชุมพลบุรี' AND sub_district IN ('สระขุด', 'ยะวึก', 'นาหนองไผ่', 'ชุมพลบุรี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุรินทร์' AND district = 'ท่าตูม' AND sub_district IN ('เมืองแก', 'ท่าตูม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุรินทร์' AND district = 'บัวเชด' AND sub_district IN ('บัวเชด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุรินทร์' AND district = 'ปราสาท' AND sub_district IN ('กันตวจระมวล', 'กังแอน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุรินทร์' AND district = 'รัตนบุรี' AND sub_district IN ('รัตนบุรี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุรินทร์' AND district = 'ลำดวน' AND sub_district IN ('โชคเหนือ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุรินทร์' AND district = 'ศีขรภูมิ' AND sub_district IN ('ผักไหม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุรินทร์' AND district = 'สนม' AND sub_district IN ('แคน', 'สนม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุรินทร์' AND district = 'สังขะ' AND sub_district IN ('สังขะ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุรินทร์' AND district = 'สำโรงทาบ' AND sub_district IN ('สำโรงทาบ', 'หมื่นศรี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุรินทร์' AND district = 'เขวาสินรินทร์' AND sub_district IN ('เขวาสินรินทร์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุรินทร์' AND district = 'เมืองสุรินทร์' AND sub_district IN ('เมืองที');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุโขทัย' AND district = 'กงไกรลาศ' AND sub_district IN ('บ้านกร่าง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุโขทัย' AND district = 'คีรีมาศ' AND sub_district IN ('ทุ่งหลวง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุโขทัย' AND district = 'ทุ่งเสลี่ยม' AND sub_district IN ('กลางดง', 'ทุ่งเสลี่ยม', 'เขาแก้วศรีสมบูรณ์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุโขทัย' AND district = 'บ้านด่านลานหอย' AND sub_district IN ('ตลิ่งชัน', 'ลานหอย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุโขทัย' AND district = 'ศรีนคร' AND sub_district IN ('ศรีนคร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุโขทัย' AND district = 'ศรีสัชนาลัย' AND sub_district IN ('หาดเสี้ยว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุโขทัย' AND district = 'ศรีสำโรง' AND sub_district IN ('คลองตาล');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุโขทัย' AND district = 'สวรรคโลก' AND sub_district IN ('เมืองบางขลัง', 'คลองยาง', 'ป่ากุมเกาะ', 'ในเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'สุโขทัย' AND district = 'เมืองสุโขทัย' AND sub_district IN ('เมืองเก่า', 'บ้านกล้วย', 'บ้านสวน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'หนองคาย' AND district = 'ท่าบ่อ' AND sub_district IN ('โพนสา', 'กองนาง', 'บ้านถ่อน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'หนองคาย' AND district = 'ศรีเชียงใหม่' AND sub_district IN ('หนองปลาปาก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'หนองคาย' AND district = 'สังคม' AND sub_district IN ('สังคม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'หนองคาย' AND district = 'เฝ้าไร่' AND sub_district IN ('เฝ้าไร่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'หนองคาย' AND district = 'เมืองหนองคาย' AND sub_district IN ('กวนวัน', 'บ้านเดื่อ', 'โพธิ์ชัย', 'เวียงคุก', 'หาดคำ', 'วัดธาตุ', 'ปะโค');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'หนองคาย' AND district = 'โพนพิสัย' AND sub_district IN ('สร้างนางขาว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'หนองบัวลำภู' AND district = 'นากลาง' AND sub_district IN ('เก่ากลอย', 'ฝั่งแดง', 'กุดดินจี่', 'นากลาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'หนองบัวลำภู' AND district = 'นาวัง' AND sub_district IN ('นาเหล่า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'หนองบัวลำภู' AND district = 'ศรีบุญเรือง' AND sub_district IN ('ยางหล่อ', 'หนองแก', 'โนนสะอาด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'หนองบัวลำภู' AND district = 'สุวรรณคูหา' AND sub_district IN ('สุวรรณคูหา', 'บ้านโคก', 'บุญทัน', 'นาด่าน', 'นาดี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'หนองบัวลำภู' AND district = 'เมืองหนองบัวลำภู' AND sub_district IN ('หัวนา', 'นามะเฟือง', 'นาคำไฮ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'หนองบัวลำภู' AND district = 'โนนสัง' AND sub_district IN ('บ้านค้อ', 'กุดดู่', 'โนนสัง', 'หนองเรือ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อำนาจเจริญ' AND district = 'ชานุมาน' AND sub_district IN ('โคกก่ง', 'ชานุมาน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อำนาจเจริญ' AND district = 'ปทุมราชวงศา' AND sub_district IN ('ห้วย', 'หนองข่า', 'นาป่าแซง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อำนาจเจริญ' AND district = 'พนา' AND sub_district IN ('พนา', 'พระเหลา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อำนาจเจริญ' AND district = 'ลืออำนาจ' AND sub_district IN ('เปือย', 'โคกกลาง', 'อำนาจ', 'ดงมะยาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อำนาจเจริญ' AND district = 'หัวตะพาน' AND sub_district IN ('เค็งใหญ่', 'หัวตะพาน', 'รัตนวารี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อำนาจเจริญ' AND district = 'เมืองอำนาจเจริญ' AND sub_district IN ('ไก่คำ', 'น้ำปลีก', 'นาหมอม้า', 'นาวัง', 'นายม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อำนาจเจริญ' AND district = 'เสนางคนิคม' AND sub_district IN ('เสนางคนิคม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุดรธานี' AND district = 'กุดจับ' AND sub_district IN ('เมืองเพีย', 'เชียงเพ็ง', 'สร้างก่อ', 'กุดจับ', 'ตาลเลียน', 'ปะโค');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุดรธานี' AND district = 'กุมภวาปี' AND sub_district IN ('เวียงคำ', 'หนองหว้า', 'ห้วยเกิ้ง', 'ปะโค', 'พันดอน', 'เชียงแหว', 'กุมภวาปี', 'แชแล');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุดรธานี' AND district = 'กู่แก้ว' AND sub_district IN ('บ้านจีต', 'คอนสาย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุดรธานี' AND district = 'ทุ่งฝน' AND sub_district IN ('ทุ่งใหญ่', 'ทุ่งฝน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุดรธานี' AND district = 'นายูง' AND sub_district IN ('โนนทอง', 'นายูง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุดรธานี' AND district = 'น้ำโสม' AND sub_district IN ('นางัว', 'น้ำโสม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุดรธานี' AND district = 'บ้านผือ' AND sub_district IN ('บ้านผือ', 'คำบง', 'กลางใหญ่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุดรธานี' AND district = 'วังสามหมอ' AND sub_district IN ('หนองหญ้าไซ', 'วังสามหมอ', 'ผาสุก', 'บะยาว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุดรธานี' AND district = 'ศรีธาตุ' AND sub_district IN ('หัวนาคำ', 'ศรีธาตุ', 'บ้านโปร่ง', 'จำปี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุดรธานี' AND district = 'สร้างคอม' AND sub_district IN ('สร้างคอม', 'บ้านโคก', 'บ้านยวด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุดรธานี' AND district = 'หนองวัวซอ' AND sub_district IN ('โนนหวาย', 'อูบมุง', 'หนองวัวซอ', 'หนองบัวบาน', 'กุดหมากไฟ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุดรธานี' AND district = 'หนองหาน' AND sub_district IN ('หนองไผ่', 'หนองเม็ก', 'บ้านเชียง', 'ผักตบ', 'หนองหาน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุดรธานี' AND district = 'หนองแสง' AND sub_district IN ('แสงสว่าง', 'นาดี');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุดรธานี' AND district = 'เพ็ญ' AND sub_district IN ('บ้านธาตุ', 'เพ็ญ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุดรธานี' AND district = 'เมืองอุดรธานี' AND sub_district IN ('นาข่า', 'นิคมสงเคราะห์', 'บ้านจั่น', 'บ้านตาด', 'หนองขอนกว้าง', 'หนองบัว', 'หนองไผ่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุดรธานี' AND district = 'โนนสะอาด' AND sub_district IN ('โนนสะอาด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุดรธานี' AND district = 'ไชยวาน' AND sub_district IN ('โพนสูง', 'ไชยวาน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุตรดิตถ์' AND district = 'ตรอน' AND sub_district IN ('บ้านแก่ง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุตรดิตถ์' AND district = 'ท่าปลา' AND sub_district IN ('ร่วมจิต', 'ท่าปลา', 'จริม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุตรดิตถ์' AND district = 'บ้านโคก' AND sub_district IN ('บ้านโคก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุตรดิตถ์' AND district = 'พิชัย' AND sub_district IN ('ท่าสัก', 'ในเมือง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุตรดิตถ์' AND district = 'ฟากท่า' AND sub_district IN ('ฟากท่า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุตรดิตถ์' AND district = 'ลับแล' AND sub_district IN ('ทุ่งยั้ง', 'ศรีพนมมาศ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุตรดิตถ์' AND district = 'เมืองอุตรดิตถ์' AND sub_district IN ('งิ้วงาม', 'ท่าเสา', 'น้ำริด', 'บ้านด่านนาขาม', 'บ้านเกาะ', 'ป่าเซ่า', 'ผาจุก', 'วังกะพี้', 'หาดกรวด', 'คุ้งตะเภา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุทัยธานี' AND district = 'ทัพทัน' AND sub_district IN ('เขาขี้ฝอย', 'หนองหญ้าปล้อง', 'หนองสระ', 'ตลุกดู่', 'ทุ่งนาไทย', 'ทัพทัน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุทัยธานี' AND district = 'บ้านไร่' AND sub_district IN ('บ้านไร่', 'เมืองการุ้ง', 'แก่นมะกรูด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุทัยธานี' AND district = 'ลานสัก' AND sub_district IN ('ลานสัก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุทัยธานี' AND district = 'สว่างอารมณ์' AND sub_district IN ('พลวงสองนาง', 'สว่างอารมณ์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุทัยธานี' AND district = 'หนองขาหย่าง' AND sub_district IN ('หนองขาหย่าง', 'ทุ่งพึ่ง', 'ดอนกลอย', 'ห้วยรอบ', 'หมกแถว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุทัยธานี' AND district = 'หนองฉาง' AND sub_district IN ('บ้านเก่า', 'เขาบางแกรก', 'หนองฉาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุทัยธานี' AND district = 'เมืองอุทัยธานี' AND sub_district IN ('หาดทนง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'ตระการพืชผล' AND sub_district IN ('ขุหลุ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'ตาลสุม' AND sub_district IN ('ตาลสุม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'นาจะหลวย' AND sub_district IN ('นาจะหลวย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'นาเยีย' AND sub_district IN ('นาเรือง', 'นาเยีย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'น้ำขุ่น' AND sub_district IN ('ขี้เหล็ก', 'ตาเกา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'น้ำยืน' AND sub_district IN ('สีวิเชียร', 'โซง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'บุณฑริก' AND sub_district IN ('คอแลน', 'นาโพธิ์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'พิบูลมังสาหาร' AND sub_district IN ('โพธิ์ไทร', 'โพธิ์ศรี', 'อ่างศิลา', 'กุดชมภู');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'ม่วงสามสิบ' AND sub_district IN ('ม่วงสามสิบ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'วารินชำราบ' AND sub_district IN ('ธาตุ', 'คำน้ำแซบ', 'คำขวาง', 'แสนสุข', 'เมืองศรีไค', 'ห้วยขะยุง', 'บุ่งไหม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'สว่างวีระวงศ์' AND sub_district IN ('สว่าง', 'บุ่งมะแลง', 'ท่าช้าง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'สำโรง' AND sub_district IN ('สำโรง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'สิรินธร' AND sub_district IN ('ช่องเม็ก', 'นิคมสร้างตนเองลำโดมน้อย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'เขมราฐ' AND sub_district IN ('ขามป้อม', 'เขมราฐ', 'หัวนา', 'หนองผือ', 'หนองนกทา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'เขื่องใน' AND sub_district IN ('บ้านกอก', 'เขื่องใน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'เดชอุดม' AND sub_district IN ('โพนงาม', 'บัวงาม', 'นาส่วง', 'กุดประทาย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'เมืองอุบลราชธานี' AND sub_district IN ('ปทุม', 'ขามใหญ่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'เหล่าเสือโก้ก' AND sub_district IN ('เหล่าเสือโก้ก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อุบลราชธานี' AND district = 'โพธิ์ไทร' AND sub_district IN ('โพธิ์ไทร');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อ่างทอง' AND district = 'ป่าโมก' AND sub_district IN ('บางปลากด', 'ป่าโมก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อ่างทอง' AND district = 'วิเศษชัยชาญ' AND sub_district IN ('ไผ่จำศิล', 'ห้วยคันแหลน', 'สี่ร้อย', 'สาวร้องไห้', 'ม่วงเตี้ย', 'บางจัก', 'ท่าช้าง', 'ไผ่ดำพัฒนา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อ่างทอง' AND district = 'สามโก้' AND sub_district IN ('สามโก้', 'ราษฎรพัฒนา', 'มงคลธรรมนิมิต');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อ่างทอง' AND district = 'เมืองอ่างทอง' AND sub_district IN ('โพสะ', 'ศาลาแดง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อ่างทอง' AND district = 'แสวงหา' AND sub_district IN ('แสวงหา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อ่างทอง' AND district = 'โพธิ์ทอง' AND sub_district IN ('โคกพุทรา', 'ทางพระ', 'สามง่าม', 'รำมะสัก', 'บ่อแร่', 'โพธิ์รังนก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'อ่างทอง' AND district = 'ไชโย' AND sub_district IN ('ไชโย', 'ไชยภูมิ', 'จรเข้ร้อง', 'ชะไว', 'ตรีณรงค์', 'หลักฟ้า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงราย' AND district = 'ขุนตาล' AND sub_district IN ('ป่าตาล', 'ยางฮอม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงราย' AND district = 'ป่าแดด' AND sub_district IN ('ป่าแดด', 'ศรีโพธิ์เงิน', 'สันมะค่า', 'โรงช้าง', 'ป่าแงะ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงราย' AND district = 'พญาเม็งราย' AND sub_district IN ('เม็งราย', 'ไม้ยา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงราย' AND district = 'พาน' AND sub_district IN ('เมืองพาน', 'สันมะเค็ด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงราย' AND district = 'เชียงของ' AND sub_district IN ('บุญเรือง', 'ครึ่ง', 'สถาน', 'ห้วยซ้อ', 'เวียง', 'ศรีดอนชัย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงราย' AND district = 'เชียงแสน' AND sub_district IN ('เวียง', 'แม่เงิน', 'โยนก', 'บ้านแซว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงราย' AND district = 'เทิง' AND sub_district IN ('หงาว', 'สันทรายงาม', 'งิ้ว', 'เชียงเคี่ยน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงราย' AND district = 'เมืองเชียงราย' AND sub_district IN ('แม่ยาว', 'ดอยลาน', 'ห้วยสัก', 'สันทราย', 'ป่าอ้อดอนชัย', 'บ้านดู่', 'นางแล', 'ท่าสุด', 'ท่าสาย', 'ดอยฮาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงราย' AND district = 'เวียงชัย' AND sub_district IN ('เวียงชัย', 'เวียงเหนือ', 'ดอนศิลา', 'เมืองชุม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงราย' AND district = 'เวียงป่าเป้า' AND sub_district IN ('เวียงกาหลง', 'ป่างิ้ว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงราย' AND district = 'เวียงแก่น' AND sub_district IN ('ท่าข้าม', 'หล่ายงาว', 'ม่วงยาย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงราย' AND district = 'แม่จัน' AND sub_district IN ('แม่ไร่', 'แม่จัน', 'แม่คำ', 'สันทราย', 'ป่าซาง', 'ท่าข้าวเปลือก', 'จันจว้าใต้', 'จันจว้า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงราย' AND district = 'แม่ลาว' AND sub_district IN ('ป่าก่อดำ', 'ดงมะดะ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงราย' AND district = 'แม่สรวย' AND sub_district IN ('แม่สรวย', 'เจดีย์หลวง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงราย' AND district = 'แม่สาย' AND sub_district IN ('แม่สาย', 'เวียงพางคำ', 'ห้วยไคร้');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'จอมทอง' AND sub_district IN ('แม่สอย', 'สบเตี๊ยะ', 'บ้านแปะ', 'บ้านหลวง', 'ดอยแก้ว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'ดอยสะเก็ด' AND sub_district IN ('ตลาดใหญ่', 'ป่าป้อง', 'ตลาดขวัญ', 'ป่าลาน', 'ป่าเมี่ยง', 'ลวงเหนือ', 'สง่าบ้าน', 'สันปูเลย', 'สำราญราษฎร์', 'เชิงดอย', 'แม่คือ', 'แม่ฮ้อยเงิน', 'แม่โป่ง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'ดอยหล่อ' AND sub_district IN ('ยางคราม', 'สองแคว', 'สันติสุข');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'ดอยเต่า' AND sub_district IN ('มืดกา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'ฝาง' AND sub_district IN ('แม่ข่า', 'สันทราย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'พร้าว' AND sub_district IN ('แม่ปั๋ง', 'เวียง', 'ทุ่งหลวง', 'ป่าไหน่', 'ป่าตุ้ม', 'บ้านโป่ง', 'น้ำแพร่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'สะเมิง' AND sub_district IN ('สะเมิงใต้');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'สันกำแพง' AND sub_district IN ('ออนใต้', 'สันกลาง', 'บวกค้าง', 'ห้วยทราย', 'สันกำแพง', 'แม่ปูคา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'สันทราย' AND sub_district IN ('แม่แฝก', 'เมืองเล็น', 'หนองแหย่ง', 'หนองหาร', 'ป่าไผ่', 'สันพระเนตร', 'สันป่าเปา', 'สันนาเม็ง', 'สันทรายหลวง', 'หนองจ๊อม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'สันป่าตอง' AND sub_district IN ('บ้านกลาง', 'บ้านแม', 'ทุ่งสะโตก', 'ทุ่งต้อม', 'ยุหว่า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'สารภี' AND sub_district IN ('ขัวมุง', 'ไชยสถาน', 'ยางเนิ้ง', 'ป่าบง', 'ท่าวังตาล', 'หนองแฝก', 'ดอนแก้ว', 'ชมภู', 'สันทราย', 'สารภี', 'หนองผึ้ง', 'ท่ากว้าง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'หางดง' AND sub_district IN ('บ้านแหวน', 'บ้านปง', 'น้ำแพร่', 'หารแก้ว', 'หนองควาย', 'หนองตอง', 'หนองแก๋ว', 'หางดง', 'สันผักหวาน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'อมก๋อย' AND sub_district IN ('สบโขง', 'อมก๋อย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'ฮอด' AND sub_district IN ('บ้านตาล', 'บ่อหลวง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'เชียงดาว' AND sub_district IN ('เมืองนะ', 'เมืองงาย', 'เชียงดาว', 'ปิงโค้ง', 'ทุ่งข้าวพวง', 'แม่นะ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'เมืองเชียงใหม่' AND sub_district IN ('หนองหอย', 'หนองป่าครั่ง', 'สุเทพ', 'สันผีเสื้อ', 'ฟ้าฮ่าม', 'ป่าแดด', 'ท่าศาลา', 'ช้างเผือก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'เวียงแหง' AND sub_district IN ('แสนไห');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'แม่ริม' AND sub_district IN ('ขี้เหล็ก', 'ริมเหนือ', 'ริมใต้', 'แม่แรม', 'เหมืองแก้ว', 'สันโป่ง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'แม่อาย' AND sub_district IN ('มะลิกา', 'แม่อาย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'แม่แจ่ม' AND sub_district IN ('ท่าผา');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'แม่แตง' AND sub_district IN ('แม่แตง', 'แม่หอพระ', 'อินทขิล', 'สันมหาพน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เชียงใหม่' AND district = 'ไชยปราการ' AND sub_district IN ('ปงตำ', 'หนองบัว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เพชรบุรี' AND district = 'ชะอำ' AND sub_district IN ('บางเก่า', 'นายาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เพชรบุรี' AND district = 'ท่ายาง' AND sub_district IN ('หนองจอก', 'ท่าไม้รวก', 'ท่าแลง', 'ท่ายาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เพชรบุรี' AND district = 'บ้านลาด' AND sub_district IN ('ห้วยข้อง', 'สะพานไกร', 'ลาดโพธิ์', 'บ้านลาด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เพชรบุรี' AND district = 'บ้านแหลม' AND sub_district IN ('บ้านแหลม', 'บางตะบูนออก', 'บางตะบูน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เพชรบุรี' AND district = 'เขาย้อย' AND sub_district IN ('เขาย้อย', 'ทับคาง', 'สระพัง', 'บางเค็ม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เพชรบุรี' AND district = 'เมืองเพชรบุรี' AND sub_district IN ('หัวสะพาน', 'หาดเจ้าสำราญ', 'หนองขนาน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เพชรบูรณ์' AND district = 'ชนแดน' AND sub_district IN ('ท่าข้าม', 'ดงขุย', 'ชนแดน', 'ศาลาลาย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เพชรบูรณ์' AND district = 'บึงสามพัน' AND sub_district IN ('ซับสมอทอด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เพชรบูรณ์' AND district = 'วังโป่ง' AND sub_district IN ('วังโป่ง', 'ท้ายดง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เพชรบูรณ์' AND district = 'วิเชียรบุรี' AND sub_district IN ('พุเตย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เพชรบูรณ์' AND district = 'ศรีเทพ' AND sub_district IN ('โคกสะอาด');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เพชรบูรณ์' AND district = 'หนองไผ่' AND sub_district IN ('หนองไผ่', 'บ่อไทย', 'บัววัฒนา', 'นาเฉลียง', 'บ้านโภชน์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เพชรบูรณ์' AND district = 'หล่มสัก' AND sub_district IN ('ตาลเดี่ยว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เพชรบูรณ์' AND district = 'หล่มเก่า' AND sub_district IN ('หล่มเก่า');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เพชรบูรณ์' AND district = 'เขาค้อ' AND sub_district IN ('แคมป์สน', 'สะเดาะพง', 'ริมสีม่วง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เพชรบูรณ์' AND district = 'เมืองเพชรบูรณ์' AND sub_district IN ('วังชมภู', 'นางั่ว', 'ท่าพล');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เลย' AND district = 'ด่านซ้าย' AND sub_district IN ('ด่านซ้าย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เลย' AND district = 'ท่าลี่' AND sub_district IN ('น้ำทูน', 'ท่าลี่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เลย' AND district = 'นาด้วง' AND sub_district IN ('นาด้วง', 'นาดอกคำ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เลย' AND district = 'นาแห้ว' AND sub_district IN ('นาแห้ว');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เลย' AND district = 'ปากชม' AND sub_district IN ('ปากชม', 'เชียงกลม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เลย' AND district = 'ผาขาว' AND sub_district IN ('โนนปอแดง', 'ท่าช้างคล้อง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เลย' AND district = 'ภูกระดึง' AND sub_district IN ('ภูกระดึง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เลย' AND district = 'ภูเรือ' AND sub_district IN ('ร่องจิก');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เลย' AND district = 'วังสะพุง' AND sub_district IN ('ปากปวน', 'ศรีสงคราม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เลย' AND district = 'หนองหิน' AND sub_district IN ('หนองหิน');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เลย' AND district = 'เชียงคาน' AND sub_district IN ('เชียงคาน', 'เขาแก้ว', 'ธาตุ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เลย' AND district = 'เมืองเลย' AND sub_district IN ('น้ำสวย', 'นาโป่ง', 'นาอ้อ', 'นาอาน', 'นาดินดำ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'เลย' AND district = 'เอราวัณ' AND sub_district IN ('ผาอินทร์แปลง', 'เอราวัณ');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'แพร่' AND district = 'ร้องกวาง' AND sub_district IN ('ทุ่งศรี', 'บ้านเวียง', 'ร้องกวาง', 'ร้องเข็ม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'แพร่' AND district = 'ลอง' AND sub_district IN ('บ้านปิน', 'แม่ปาน', 'ห้วยอ้อ', 'เวียงต้า', 'ปากกาง');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'แพร่' AND district = 'วังชิ้น' AND sub_district IN ('วังชิ้น');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'แพร่' AND district = 'สอง' AND sub_district IN ('ห้วยหม้าย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'แพร่' AND district = 'สูงเม่น' AND sub_district IN ('สูงเม่น');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'แพร่' AND district = 'หนองม่วงไข่' AND sub_district IN ('หนองม่วงไข่');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'แพร่' AND district = 'เด่นชัย' AND sub_district IN ('แม่จั๊วะ', 'ปงป่าหวาย', 'เด่นชัย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'แพร่' AND district = 'เมืองแพร่' AND sub_district IN ('ป่าแมต', 'บ้านถิ่น', 'ทุ่งโฮ้ง', 'ทุ่งกวาว', 'ช่อแฮ', 'แม่หล่าย', 'แม่คำมี', 'สวนเขื่อน', 'วังหงส์');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'แม่ฮ่องสอน' AND district = 'ขุนยวม' AND sub_district IN ('ขุนยวม');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'แม่ฮ่องสอน' AND district = 'แม่ลาน้อย' AND sub_district IN ('แม่ลาน้อย');
UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'
  WHERE province = 'แม่ฮ่องสอน' AND district = 'แม่สะเรียง' AND sub_district IN ('แม่สะเรียง', 'แม่ยวม');

-- =====================================================
-- สรุปสถิติ (ตรวจสอบหลังรัน)
-- SELECT local_gov_type, COUNT(*) FROM thai_addresses GROUP BY local_gov_type ORDER BY 2 DESC;
-- =====================================================
