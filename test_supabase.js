const { createClient } = require('@supabase/supabase-js');
const supabaseUrl = 'https://psxcgdwcwjdbpaemkozq.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzeGNnZHdjd2pkYnBhZW1rb3pxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyNDQzNDQsImV4cCI6MjA4NTgyMDM0NH0.O2OP-tLPW214hQeFUWAFWMTYEn-_RA1MK6TAEJnKGfU';
const supabase = createClient(supabaseUrl, supabaseKey);

async function check() {
  console.log('Checking Supabase connection...');
  const { data, error } = await supabase.from('donation_categories').select('*').limit(1);
  if (error) {
    console.error('Error:', error);
  } else {
    console.log('Success, data length:', data.length);
  }
}
check();
