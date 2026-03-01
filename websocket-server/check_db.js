const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

async function run() {
  const envPath = '../.env';
  if (!fs.existsSync(envPath)) {
    console.log('No .env file found at', envPath);
    return;
  }
  const env = fs.readFileSync(envPath, 'utf8');
  const urlMatch = env.match(/SUPABASE_URL=([^\n]+)/);
  const keyMatch = env.match(/SUPABASE_ANON_KEY=([^\n]+)/);
  
  if (!urlMatch || !keyMatch) {
    console.log('Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env');
    return;
  }

  const supabaseUrl = urlMatch[1].trim();
  const supabaseKey = keyMatch[1].trim();

  const supabase = createClient(supabaseUrl, supabaseKey);
  const result = await supabase.from('medication_category_mappings').select('*').limit(0);
  console.log(JSON.stringify(result, null, 2));
}
run();
