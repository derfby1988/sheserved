const AUTHOR_ID = '75d96ab0-96d3-430b-8d6f-3855162ef756';
const SUPABASE_URL = 'https://psxcgdwcwjdbpaemkozq.supabase.co';
const ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzeGNnZHdjd2pkYnBhZW1rb3pxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyNDQzNDQsImV4cCI6MjA4NTgyMDM0NH0.O2OP-tLPW214hQeFUWAFWMTYEn-_RA1MK6TAEJnKGfU';

const categories = ['โภชนาการ', 'สมรรถภาพทางกาย', 'สุขภาพจิต', 'สุขภาพผู้หญิง', 'ความงามและผิวพรรณ', 'การแพทย์'];
const titles = [
  'วิตามินที่จำเป็นสำหรับวัยทำงาน',
  'วิธีลดน้ำหนักแบบยั่งยืน',
  'การดูแลหัวใจด้วยการเดิน',
  'สมุนไพรไทยแก้เจ็บคอร้อนใน',
  'เทคนิคการหายใจลดความเครียด',
  'สัญญาณเตือนโรคมะเร็ง',
  'การกินแบบ Intermittent Fasting (IF)',
  'โปรตีนพืช vs โปรตีนสัตว์',
  'การดูแลสายตาจากหน้าจอคอมพิวเตอร์',
  'วิธีเลือกครีมกันแดดให้เหมาะกับผิว',
];

async function run() {
  const mockData = [];
  for (let i = 1; i <= 40; i++) {
    const date = new Date();
    date.setDate(date.getDate() - i);
    const now = date.toISOString();
    
    mockData.push({
      title: `${titles[i % titles.length]} (Vol. ${Math.floor(i / 10) + 1}) #${i}`,
      content: `เนื้อหาจำลองสำหรับบทความเรื่อง ${titles[i % titles.length]} ลำดับที่ ${i}... การดูแลสุขภาพเป็นสิ่งสำคัญที่คุณควรใส่ใจทุกวัน...`,
      author_id: AUTHOR_ID,
      category: categories[i % categories.length],
      view_count: 100 + (i * 20),
      like_count: 10 + (i % 30),
      image_url: `https://picsum.photos/seed/art${i}/800/600`,
      created_at: now,
      updated_at: now,
    });
  }

  console.log('Inserting 40 articles...');

  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/health_articles`, {
      method: 'POST',
      headers: {
        'apikey': ANON_KEY,
        'Authorization': `Bearer ${ANON_KEY}`,
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal'
      },
      body: JSON.stringify(mockData)
    });

    if (res.ok) {
      console.log('Successfully inserted 40 mock articles!');
    } else {
      const text = await res.text();
      console.error('Error:', text);
    }
  } catch (err) {
    console.error('Fetch Error:', err);
  }
}

run();
