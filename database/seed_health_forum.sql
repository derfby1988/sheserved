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
('c2c2c2c2-2222-2222-2222-222222222222', 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', 'afe055c3-e614-4024-833c-a650f7793e6a', 'บทความละเอียดมากค่ะ อยากทราบข้อมูลเรื่องการจัดการความเครียดเพิ่มเติมจังเลยค่ะ', 2, 8),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '176179bd-9663-4559-a8b2-eb8cda1e758b', 'ขอบคุณสำหรับความรู้ดีๆ ครับ', 5, 3),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', 'afe055c3-e614-4024-833c-a650f7793e6a', 'น่าสนใจมากเลยค่ะ จะลองเอาไปปรับใช้ดูนะคะ', 6, 15),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '91c8d2c6-e054-49af-800d-c5b8ccbc7898', 'วิตามินซีช่วงนี้สำคัญจริงๆ ครับ', 7, 20),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '176179bd-9663-4559-a8b2-eb8cda1e758b', 'ติดตามผลงานคุณหมอมานานแล้วครับ เขียนดีทุกเรื่องเลย', 8, 45),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', 'afe055c3-e614-4024-833c-a650f7793e6a', 'มีแนะนำยี่ห้อวิตามินซีมั้ยคะ?', 9, 2),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '91c8d2c6-e054-49af-800d-c5b8ccbc7898', 'ผมทานตัวที่ติดอยู่ในบทความอยู่ครับ ดีมาก', 10, 5),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '176179bd-9663-4559-a8b2-eb8cda1e758b', 'รบกวนถามเรื่องการนอนหลับหน่อยครับ ควรนอนกี่โมงดีที่สุด?', 11, 10),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', 'afe055c3-e614-4024-833c-a650f7793e6a', 'แชร์ให้เพื่อนๆ แล้วนะคะ บทความมีประโยชน์มาก', 12, 33),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '91c8d2c6-e054-49af-800d-c5b8ccbc7898', 'Zinc ช่วยเรื่องผมร่วงได้จริงมั้ยครับคุณหมอ?', 13, 7),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '176179bd-9663-4559-a8b2-eb8cda1e758b', 'บรรยากาศในกลุ่มดีมากครับ มีแต่คนแบ่งปันความรู้', 14, 18),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', 'afe055c3-e614-4024-833c-a650f7793e6a', 'อยากให้มีภาคต่อเรื่องอาหารคลีนจังเลยค่ะ', 15, 25),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '91c8d2c6-e054-49af-800d-c5b8ccbc7898', 'อ่านแล้วมีกำลังใจออกกำลังกายเลยครับ', 16, 11),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '176179bd-9663-4559-a8b2-eb8cda1e758b', 'ถ้าเครียดมากๆ ควรปรึกษาหมอด้านไหนครับ?', 17, 4),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', 'afe055c3-e614-4024-833c-a650f7793e6a', 'ลองทำตามข้อ 5 แล้ว หลับลึกขึ้นจริงๆ ค่ะ', 18, 50),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '91c8d2c6-e054-49af-800d-c5b8ccbc7898', 'ขอเทคนิคการกินโปรตีนพืชให้ครบหน่อยครับ', 19, 9),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '176179bd-9663-4559-a8b2-eb8cda1e758b', 'หน้ากากอนามัยยังจำเป็นอยู่มั้ยครับช่วงนี้?', 20, 1),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', 'afe055c3-e614-4024-833c-a650f7793e6a', 'ขอบคุณสำหรับสิ่งดีๆ ที่มอบให้กันนะคะ', 21, 14),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '91c8d2c6-e054-49af-800d-c5b8ccbc7898', 'เป็นบทความที่อ่านง่ายและเข้าใจได้ทันทีเลยครับ', 22, 22),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '176179bd-9663-4559-a8b2-eb8cda1e758b', 'อยากทราบผลข้างเคียงของ Zinc ครับ มีมั้ย?', 23, 3),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', 'afe055c3-e614-4024-833c-a650f7793e6a', 'ส่งต่อให้คุณแม่กะคุณน้าอ่านแล้วค่ะ ท่านชอบมาก', 24, 38),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '91c8d2c6-e054-49af-800d-c5b8ccbc7898', 'ราคาโปรตีนพืชตัวนี้ประมาณเท่าไหร่ครับ?', 25, 6),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '176179bd-9663-4559-a8b2-eb8cda1e758b', 'เนื้อหาพรีเมียมมากครับ ไม่เสียแรงที่ติดตาม', 26, 12),
(gen_random_uuid(), 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', 'afe055c3-e614-4024-833c-a650f7793e6a', 'รักแอปนี้จังเลยค่ะ ข้อมูลแน่นมาก', 27, 29)
ON CONFLICT (id) DO NOTHING;

-- 4. Create mock replies
INSERT INTO health_article_comments (article_id, user_id, parent_id, content, comment_number, like_count)
VALUES 
('a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '75d96ab0-96d3-430b-8d6f-3855162ef756', 'c1c1c1c1-1111-1111-1111-111111111111', 'ยินดีมากครับที่คุณมีประโยชน์จากบทความนี้ ขอให้สุขภาพแข็งแรงนะครับ', 3, 5),
('a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d', '91c8d2c6-e054-49af-800d-c5b8ccbc7898', 'c1c1c1c1-1111-1111-1111-111111111111', 'เห็นด้วยครับ วิตามิน C ที่หมอแนะนำทานดีมากครับ', 4, 2)
ON CONFLICT DO NOTHING;
