const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);

async function check() {
  try {
    const { data, error } = await supabase.from('thai_mhung_photos').select('*').limit(2);
    if (error) {
      console.log("Error querying thai_mhung_photos:", error.message);
    } else {
      console.log("Success! Data:", data);
    }
  } catch (err) {
    console.log("Exception:", err);
  }
}
check();
