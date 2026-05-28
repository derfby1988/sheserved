-- Backfill: อัปเดต consultation_room_experts ที่ provider เข้าร่วมแล้วผ่านระบบเก่า
-- แต่สถานะยังเป็น waiting เนื่องจาก assignProvider() ไม่ได้อัปเดตตารางนี้
-- สาเหตุ: _joinRequest() fallback จาก assignProviderToGroup → assignProvider แล้วไม่ได้ sync
-- ผลกระทบ: ExpertStatusBanner แสดง provider เป็น 🔒 (waiting) แทนที่จะเป็น joined

UPDATE public.consultation_room_experts ce
SET 
  status = 'joined',
  provider_id = COALESCE(ce.provider_id, cr.provider_id),
  joined_at = COALESCE(ce.joined_at, cr.updated_at, now())
FROM public.consultation_requests cr
WHERE 
  ce.consultation_id = cr.id
  AND cr.provider_id IS NOT NULL
  AND ce.status = 'waiting';
