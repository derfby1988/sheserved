const { createClient } = require('@supabase/supabase-js');

// we'll fetch credentials from flutter dotenv
const envStr = require('fs').readFileSync('lib/core/constants/app_env.dart', 'utf8');
const urlMatch = envStr.match(/static const String supabaseUrl = '([^']+)'/);
const keyMatch = envStr.match(/static const String supabaseAnonKey = '([^']+)'/);

if (!urlMatch || !keyMatch) {
  console.log('Could not parse app_env.dart');
  process.exit(1);
}

const supabase = createClient(urlMatch[1], keyMatch[1]);
async function run() {
  const { data, error } = await supabase.from('medication_category_mappings').select('*').limit(1);
  if (error) {
    console.error('Error fetching data:', error);
  } else {
    console.log('Success! Connection and table exist. Sample data:', data);
  }
}
run();
