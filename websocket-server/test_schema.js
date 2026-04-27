const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);

async function check() {
  const { data, error } = await supabase.from('thai_mhung_photos').select('*').limit(1);
  console.log("thai_mhung_photos sample:", data);
}
check();
