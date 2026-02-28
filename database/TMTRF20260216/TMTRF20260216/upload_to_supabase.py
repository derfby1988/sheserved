import urllib.request
import json
import os

with open('tmt_massive_seed.sql', 'r') as f:
    sql_query = f.read()

url = "https://psxcgdwcwjdbpaemkozq.supabase.co/rest/v1/sql"
headers = {
    "apikey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzeGNnZHdjd2pkYnBhZW1rb3pxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyNDQzNDQsImV4cCI6MjA4NTgyMDM0NH0.O2OP-tLPW214hQeFUWAFWMTYEn-_RA1MK6TAEJnKGfU",
    "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzeGNnZHdjd2pkYnBhZW1rb3pxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyNDQzNDQsImV4cCI6MjA4NTgyMDM0NH0.O2OP-tLPW214hQeFUWAFWMTYEn-_RA1MK6TAEJnKGfU",
    "Content-Type": "application/json"
}
data = json.dumps({"query": sql_query}).encode("utf-8")

req = urllib.request.Request(url, data=data, headers=headers, method="POST")
try:
    with urllib.request.urlopen(req) as response:
        print("Success:", response.status, response.read().decode())
except urllib.error.HTTPError as e:
    print("Failed:", e.code, e.reason, e.read().decode())
