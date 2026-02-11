-- Extra Mock Data for Health Articles and Comments

-- Article 2: Health Check at Home
INSERT INTO health_articles (id, title, content, author_id, category, view_count, like_count, image_url)
VALUES (
    'b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e',
    'การตรวจสุขภาพเบื้องต้นที่คุณทำได้เองที่บ้าน',
    'คุณไม่จำเป็นต้องรอให้ถึงวันตรวจสุขภาพประจำปีเพื่อเช็คสภาพร่างกายของคุณ การหมั่นสังเกตสัญญาณเตือนเล็กๆ น้อยๆ จากร่างกายสามารถช่วยให้คุณพบความผิดปกติได้เนิ่นๆ...' || CHR(10) || CHR(10) || '1. ตรวจวัดอัตราการเต้นของหัวใจ' || CHR(10) || '2. สังเกตความเปลี่ยนแปลงของผิวหนัง' || CHR(10) || '3. เช็คค่าดัชนีมวลกาย (BMI)' || CHR(10) || '4. ทดสอบความยืดหยุ่นของร่างกาย',
    '75d96ab0-96d3-430b-8d6f-3855162ef756',
    'สมรรถภาพทางกาย',
    850,
    32,
    'https://images.unsplash.com/photo-1576091160550-217359f4ecf8?q=80&w=1000'
) ON CONFLICT (id) DO NOTHING;

-- Article 3: Heart Healthy Foods
INSERT INTO health_articles (id, title, content, author_id, category, view_count, like_count, image_url)
VALUES (
    'c3d4e5f6-a7b8-9c0d-1e2f-3a4b5c6d7e8f',
    'อาหาร 10 ชนิดที่ช่วยบำรุงหัวใจและลดคอเลสเตอรอล',
    'หัวใจเป็นอวัยวะที่ทำงานหนักที่สุดในร่างกาย การดูแลหัวใจเริ่มต้นที่จานอาหารของคุณ การเลือกทานอาหารที่มีโอเมก้า 3 ใยอาหารสูง และสารต้านอนุมูลอิสระจะช่วยลดความเสี่ยงโรคหัวใจได้อย่างมีนัยสำคัญ...',
    '75d96ab0-96d3-430b-8d6f-3855162ef756',
    'โภชนาการ',
    2100,
    156,
    'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?q=80&w=1000'
) ON CONFLICT (id) DO NOTHING;

-- Comments for Article 2 (12 comments)
INSERT INTO health_article_comments (id, article_id, user_id, content, comment_number, like_count)
VALUES 
(gen_random_uuid(), 'b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e', '176179bd-9663-4559-a8b2-eb8cda1e758b', 'วิธีวัดชีพจรด้วยตัวเองทำยากมั้ยครับ?', 1, 5),
(gen_random_uuid(), 'b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e', 'afe055c3-e614-4024-833c-a650f7793e6a', 'ไม่ยากเลยค่ะ ลองคลำที่ข้อมือดูนะคะ', 2, 12),
(gen_random_uuid(), 'b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e', '91c8d2c6-e054-49af-800d-c5b8ccbc7898', 'ได้ความรู้ใหม่เรื่อง BMI มากเลยครับ', 3, 8),
(gen_random_uuid(), 'b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e', '176179bd-9663-4559-a8b2-eb8cda1e758b', 'ขอบคุณสำหรับบทความดีๆ แบบนี้ครับ', 4, 3),
(gen_random_uuid(), 'b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e', 'afe055c3-e614-4024-833c-a650f7793e6a', 'มีวิธีเช็คสายตาเบื้องต้นมั้ยคะ?', 5, 10),
(gen_random_uuid(), 'b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e', '91c8d2c6-e054-49af-800d-c5b8ccbc7898', 'บทความนี้มีประโยชน์มากในช่วงโควิดเลยครับ', 6, 25),
(gen_random_uuid(), 'b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e', '176179bd-9663-4559-a8b2-eb8cda1e758b', 'ส่งต่อให้ที่บ้านอ่านแล้วครับ', 7, 7),
(gen_random_uuid(), 'b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e', 'afe055c3-e614-4024-833c-a650f7793e6a', 'เช็คแล้วเจอไฝแปลกๆ ควรไปหาหมอเลยมั้ยคะ?', 8, 14),
(gen_random_uuid(), 'b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e', '91c8d2c6-e054-49af-800d-c5b8ccbc7898', 'เครื่องวัดความดันที่บ้านจำเป็นมั้ยครับ?', 9, 2),
(gen_random_uuid(), 'b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e', '176179bd-9663-4559-a8b2-eb8cda1e758b', 'ความยืดหยุ่นผมต่ำมาก ต้องเริ่มโยคะแล้ว', 10, 19),
(gen_random_uuid(), 'b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e', 'afe055c3-e614-4024-833c-a650f7793e6a', 'ชอบแนวทางการเขียนมากค่ะ อ่านเข้าใจง่าย', 11, 23),
(gen_random_uuid(), 'b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e', '91c8d2c6-e054-49af-800d-c5b8ccbc7898', 'ขอบคุณคุณหมอมากครับ', 12, 5)
ON CONFLICT (id) DO NOTHING;

-- Comments for Article 3 (12 comments)
INSERT INTO health_article_comments (id, article_id, user_id, content, comment_number, like_count)
VALUES 
(gen_random_uuid(), 'c3d4e5f6-a7b8-9c0d-1e2f-3a4b5c6d7e8f', '176179bd-9663-4559-a8b2-eb8cda1e758b', 'อะโวคาโดทานวันละเท่าไหร่ดีครับ?', 1, 15),
(gen_random_uuid(), 'c3d4e5f6-a7b8-9c0d-1e2f-3a4b5c6d7e8f', 'afe055c3-e614-4024-833c-a650f7793e6a', 'ครึ่งลูกกำลังดีค่ะ อย่าทานเยอะเกินไปนะคะ', 2, 28),
(gen_random_uuid(), 'c3d4e5f6-a7b8-9c0d-1e2f-3a4b5c6d7e8f', '91c8d2c6-e054-49af-800d-c5b8ccbc7898', 'ปลาแซลมอนหาทานยากจัง มีปลาไทยแทนมั้ยครับ?', 3, 11),
(gen_random_uuid(), 'c3d4e5f6-a7b8-9c0d-1e2f-3a4b5c6d7e8f', '176179bd-9663-4559-a8b2-eb8cda1e758b', 'ปลาทูหรือปลาสวายก็มีโอเมก้า 3 เยอะครับ', 4, 34),
(gen_random_uuid(), 'c3d4e5f6-a7b8-9c0d-1e2f-3a4b5c6d7e8f', 'afe055c3-e614-4024-833c-a650f7793e6a', 'พวกรำข้าวช่วยได้จริงมั้ยคะ?', 5, 2),
(gen_random_uuid(), 'c3d4e5f6-a7b8-9c0d-1e2f-3a4b5c6d7e8f', '91c8d2c6-e054-49af-800d-c5b8ccbc7898', 'บทความคุณหมอพรีเมียมจริงๆ ครับ', 6, 45),
(gen_random_uuid(), 'c3d4e5f6-a7b8-9c0d-1e2f-3a4b5c6d7e8f', '176179bd-9663-4559-a8b2-eb8cda1e758b', 'ผมเปลี่ยนมาทานข้าวกล้องตามคำแนะนำแล้วครับ', 7, 9),
(gen_random_uuid(), 'c3d4e5f6-a7b8-9c0d-1e2f-3a4b5c6d7e8f', 'afe055c3-e614-4024-833c-a650f7793e6a', 'คอเลสเตอรอลลดลงจริงๆ ค่ะ ตรวจเลือดล่าสุดดีขึ้นมาก', 8, 112),
(gen_random_uuid(), 'c3d4e5f6-a7b8-9c0d-1e2f-3a4b5c6d7e8f', '91c8d2c6-e054-49af-800d-c5b8ccbc7898', 'นัทหรือถั่วเปลือกแข็งควรทานแบบอบหรือดิบครับ?', 9, 4),
(gen_random_uuid(), 'c3d4e5f6-a7b8-9c0d-1e2f-3a4b5c6d7e8f', '176179bd-9663-4559-a8b2-eb8cda1e758b', 'แบบอบไม่ใส่เกลือดีที่สุดครับ', 10, 21),
(gen_random_uuid(), 'c3d4e5f6-a7b8-9c0d-1e2f-3a4b5c6d7e8f', 'afe055c3-e614-4024-833c-a650f7793e6a', 'ชอบแอปนี้ตรงที่มีความรู้สาระแน่นแบบนี้นี่แหละ', 11, 67),
(gen_random_uuid(), 'c3d4e5f6-a7b8-9c0d-1e2f-3a4b5c6d7e8f', '91c8d2c6-e054-49af-800d-c5b8ccbc7898', 'ขอบคุณครับ จะแชร์ต่อให้กลุ่มเพื่อนที่ทำงานด้วย', 12, 13)
ON CONFLICT (id) DO NOTHING;
