-- Pagination Test Data for Health Articles (15 Articles)
-- To test pagination of 12 items per page (Page 1: 12 items, Page 2: 3 items)

-- Clean up existing test data if needed (Optional: uncomment if you want to start fresh)
-- DELETE FROM health_article_comments WHERE article_id IN (SELECT id FROM health_articles WHERE title LIKE 'Pagination Test%');
-- DELETE FROM health_articles WHERE title LIKE 'Pagination Test%';

INSERT INTO health_articles (id, title, content, author_id, category, view_count, like_count, image_url, created_at)
VALUES 
-- Page 1 (12 Articles)
(gen_random_uuid(), 'Pagination Test 01: การดูแลสุขภาพเชิงรุกสำหรับผู้หญิง', 'เนื้อหาเกี่ยวกับการดูแลสุขภาพเชิงรุก...', '75d96ab0-96d3-430b-8d6f-3855162ef756', 'สุขภาพผู้หญิง', 100, 10, 'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?q=80&w=800', NOW() - INTERVAL '1 hour'),
(gen_random_uuid(), 'Pagination Test 02: การตรวจสุขภาพเบื้องต้นที่บ้าน', 'เนื้อหาเกี่ยวกับการตรวจสุขภาพเบื้องต้น...', '75d96ab0-96d3-430b-8d6f-3855162ef756', 'สมรรถภาพทางกาย', 120, 15, 'https://images.unsplash.com/photo-1576091160550-217359f4ecf8?q=80&w=800', NOW() - INTERVAL '2 hours'),
(gen_random_uuid(), 'Pagination Test 03: อาหาร 10 ชนิดบำรุงหัวใจ', 'เนื้อหาเกี่ยวกับอาหารบำรุงหัวใจ...', '75d96ab0-96d3-430b-8d6f-3855162ef756', 'โภชนาการ', 150, 20, 'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?q=80&w=800', NOW() - INTERVAL '3 hours'),
(gen_random_uuid(), 'Pagination Test 04: โยคะลดปวดหลังสำหรับการทำงาน', 'เนื้อหาเกี่ยวกับโยคะลดปวดหลัง...', '75d96ab0-96d3-430b-8d6f-3855162ef756', 'สมรรถภาพทางกาย', 80, 5, 'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?q=80&w=800', NOW() - INTERVAL '4 hours'),
(gen_random_uuid(), 'Pagination Test 05: การนอนหลับที่มีคุณภาพสำคัญอย่างไร', 'เนื้อหาเกี่ยวกับการนอนหลับ...', '75d96ab0-96d3-430b-8d6f-3855162ef756', 'สุขภาพจิต', 200, 30, 'https://images.unsplash.com/photo-1541781774459-bb2af2f05b55?q=80&w=800', NOW() - INTERVAL '5 hours'),
(gen_random_uuid(), 'Pagination Test 06: ประโยชน์ของการดื่มน้ำให้เพียงพอ', 'เนื้อหาเกี่ยวกับการดื่มน้ำ...', '75d96ab0-96d3-430b-8d6f-3855162ef756', 'โภชนาการ', 300, 45, 'https://images.unsplash.com/photo-1548919973-5cfe5d4fc474?q=80&w=800', NOW() - INTERVAL '6 hours'),
(gen_random_uuid(), 'Pagination Test 07: การจัดการความเครียดในที่ทำงาน', 'เนื้อหาเกี่ยวกับการจัดการความเครียด...', '75d96ab0-96d3-430b-8d6f-3855162ef756', 'สุขภาพจิต', 110, 12, 'https://images.unsplash.com/photo-1474418397713-7ded03d091aa?q=80&w=800', NOW() - INTERVAL '7 hours'),
(gen_random_uuid(), 'Pagination Test 08: สัญญาณเตือนมะเร็งเต้านมที่ควรรู้', 'เนื้อหาเกี่ยวกับมะเร็งเต้านม...', '75d96ab0-96d3-430b-8d6f-3855162ef756', 'สุขภาพผู้หญิง', 500, 100, 'https://images.unsplash.com/photo-1579154235821-f09696b9f484?q=80&w=800', NOW() - INTERVAL '8 hours'),
(gen_random_uuid(), 'Pagination Test 09: ออกกำลังกายแบบ HIIT เพื่อเผาผลาญไขมัน', 'เนื้อหาเกี่ยวกับการออกกำลังกาย...', '75d96ab0-96d3-430b-8d6f-3855162ef756', 'สมรรถภาพทางกาย', 250, 40, 'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?q=80&w=800', NOW() - INTERVAL '9 hours'),
(gen_random_uuid(), 'Pagination Test 10: อาหารเช้าพลังงานสูงสำหรับคนทำงาน', 'เนื้อหาเกี่ยวกับอาหารเช้า...', '75d96ab0-96d3-430b-8d6f-3855162ef756', 'โภชนาการ', 180, 25, 'https://images.unsplash.com/photo-1494390248081-4e521a5940db?q=80&w=800', NOW() - INTERVAL '10 hours'),
(gen_random_uuid(), 'Pagination Test 11: การดูแลผิวพรรณในช่วงฤดูร้อน', 'เนื้อหาเกี่ยวกับการดูแลผิว...', '75d96ab0-96d3-430b-8d6f-3855162ef756', 'ความงามและผิวพรรณ', 140, 18, 'https://images.unsplash.com/photo-1521335629791-ce4aec67dd15?q=80&w=800', NOW() - INTERVAL '11 hours'),
(gen_random_uuid(), 'Pagination Test 12: วิตามินที่จำเป็นสำหรับผู้หญิงวัยทอง', 'เนื้อหาเกี่ยวกับวิตามินวัยทอง...', '75d96ab0-96d3-430b-8d6f-3855162ef756', 'สุขภาพผู้หญิง', 95, 8, 'https://images.unsplash.com/photo-1584017962801-debd996a7c37?q=80&w=800', NOW() - INTERVAL '12 hours'),

-- Page 2 (3 Articles)
(gen_random_uuid(), 'Pagination Test 13: ความสำคัญของการตรวจคัดกรองมะเร็งปากมดลูก', 'เนื้อหาเกี่ยวกับมะเร็งปากมดลูก...', '75d96ab0-96d3-430b-8d6f-3855162ef756', 'สุขภาพผู้หญิง', 420, 85, 'https://images.unsplash.com/photo-1581594693702-fbdc51b2ad49?q=80&w=800', NOW() - INTERVAL '13 hours'),
(gen_random_uuid(), 'Pagination Test 14: นวัตกรรมการใหม่ๆ ในการรักษาโรคเบาหวาน', 'เนื้อหาเกี่ยวกับการรักษาเบาหวาน...', '75d96ab0-96d3-430b-8d6f-3855162ef756', 'การแพทย์', 310, 55, 'https://images.unsplash.com/photo-1579154341098-e4e158cc7f55?q=80&w=800', NOW() - INTERVAL '14 hours'),
(gen_random_uuid(), 'Pagination Test 15: พลังของความคิดบวกต่อสุขภาพกาย', 'เนื้อหาเกี่ยวกับพลังความคิดบวก...', '75d96ab0-96d3-430b-8d6f-3855162ef756', 'สุขภาพจิต', 190, 35, 'https://images.unsplash.com/photo-1499209974431-9dac3adaf471?q=80&w=800', NOW() - INTERVAL '15 hours');

-- Add Comments for the first article to test comment listing/pagination
WITH first_article AS (
    SELECT id FROM health_articles WHERE title = 'Pagination Test 01: การดูแลสุขภาพเชิงรุกสำหรับผู้หญิง' LIMIT 1
)
INSERT INTO health_article_comments (id, article_id, user_id, content, comment_number, like_count)
SELECT 
    gen_random_uuid(), 
    (SELECT id FROM first_article), 
    CASE WHEN n % 3 = 0 THEN '176179bd-9663-4559-a8b2-eb8cda1e758b' 
         WHEN n % 3 = 1 THEN 'afe055c3-e614-4024-833c-a650f7793e6a' 
         ELSE '91c8d2c6-e054-49af-800d-c5b8ccbc7898' END,
    'ความเห็นจำลองที่ ' || n || ' สำหรับบทความนี้ครับ มีประโยชน์มาก!',
    n,
    floor(random() * 50)::int
FROM generate_series(1, 15) n;
