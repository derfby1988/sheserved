-- Mock Data for Health Forum

-- 1. Create a mock article
INSERT INTO health_articles (id, title, content, author_id, category, view_count, like_count)
VALUES (
    'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d',
    'เคล็ดลับการดูแลสุขภาพเชิงรุกสำหรับผู้หญิง: เริ่มต้นวันนี้เพื่ออนาคตที่ยั่งยืน',
    'การดูแลสุขภาพเชิงรุก (Proactive Health) คือหัวใจสำคัญของการมีชีวิตที่ยืนยาวและมีคุณภาพ โดยเฉพาะในผู้หญิงที่มีการเปลี่ยนแปลงของฮอร์โมนและร่างกายแตกต่างกันไปในแต่ละช่วงวัย บทความนี้จะเจาะลึก 5 เคล็ดลับที่จะช่วยให้คุณก้าวทันปัญหาสุขภาพก่อนที่จะสายเกินไป...' || CHR(10) || CHR(10) || '1. ตรวจสุขภาพสม่ำเสมอ' || CHR(10) || '2. อาหารที่สมดุล' || CHR(10) || '3. การออกกำลังกายที่เหมาะสม' || CHR(10) || '4. การจัดการความเครียด' || CHR(10) || '5. การนอนหลับที่มีคุณภาพ',
    '75d96ab0-96d3-430b-8d6f-3855162ef756',
    'Women Health',
    1250,
    45
) ON CONFLICT (id) DO NOTHING;

-- 2. Create mock products
INSERT INTO health_article_products (article_id, name, tag_type, is_approved)
VALUES 
('a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', 'วิตามิน C 1000mg', 'author', true),
('a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', 'อาหารเสริม Zinc', 'sponsor', true),
('a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', 'โปรตีนพืช', 'user', true),
('a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', 'น้ำมันปลา Omega-3', 'author', true);

-- 3. Create mock comments
INSERT INTO health_article_comments (id, article_id, user_id, content, comment_number, like_count)
VALUES 
('c1c1c1c1-1111-1111-1111-111111111111', 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '176179bd-9663-4559-a8b2-eb8cda1e758b', 'ข้อมูลนี้ยอดเยี่ยมมากครับ ผมกำลังมองหาวิธีดูแลตัวเองอยู่พอดี ขอบคุณคุณหมอมากครับที่เอามาแบ่งปัน', 1, 12),
('c2c2c2c2-2222-2222-2222-222222222222', 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', 'afe055c3-e614-4024-833c-a650f7793e6a', 'บทความละเอียดมากค่ะ อยากทราบข้อมูลเรื่องการจัดการความเครียดเพิ่มเติมจังเลยค่ะ', 2, 8);

-- 4. Create mock replies
INSERT INTO health_article_comments (article_id, user_id, parent_id, content, comment_number, like_count)
VALUES 
('a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '75d96ab0-96d3-430b-8d6f-3855162ef756', 'c1c1c1c1-1111-1111-1111-111111111111', 'ยินดีมากครับที่คุณมีประโยชน์จากบทความนี้ ขอให้สุขภาพแข็งแรงนะครับ', 3, 5),
('a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '91c8d2c6-e054-49af-800d-c5b8ccbc7898', 'c1c1c1c1-1111-1111-1111-111111111111', 'เห็นด้วยครับ วิตามิน C ที่หมอแนะนำทานดีมากครับ', 4, 2);
