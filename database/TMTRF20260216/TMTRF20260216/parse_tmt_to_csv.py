import pandas as pd
import re
import csv
import json

# โหลดข้อมูล TMT
print("Loading Excel...")
df = pd.read_excel('TMTRF20260216_FULL.xls')
print("Total rows:", len(df))

def extract_drug_info(fsn_text):
    if not isinstance(fsn_text, str):
        return None
    
    match = re.search(r"^(.*?)\s*\((.*?)\)\s*(.*?)\s*\(TPU\)$", fsn_text)
    if match:
        trade_name = match.group(1).strip()
        generic_strength = match.group(2).strip()
        dosage_form = match.group(3).strip()
        
        return {
            'trade_name': trade_name[:250],
            'generic_name': generic_strength[:250],
            'dosage_form': dosage_form[:100],
            'strength': 'See Generic Name'
        }
    return None

records = []
for index, row in df.iterrows():
    info = extract_drug_info(row['FSN'])
    if info:
        manufacturer = str(row['MANUFACTURER'])[:250]
        records.append({
            "source_type": "TMT",
            "reference_code": str(row['TMTID(TPU)']),
            "generic_name": info['generic_name'],
            "trade_name": info['trade_name'],
            "dosage_form": info['dosage_form'],
            "manufacturer": manufacturer,
            "status": "ACTIVE"
        })

print(f"Parsed {len(records)} records. Saving to CSV...")

# save to csv directly
with open('sheserved_tmt_real_dataset.csv', 'w', newline='', encoding='utf-8') as file:
    fieldnames = ['source_type', 'reference_code', 'generic_name', 'trade_name', 'dosage_form', 'manufacturer', 'status']
    writer = csv.DictWriter(file, fieldnames=fieldnames)
    writer.writeheader()
    for row in records:
        writer.writerow(row)

print("Saved to sheserved_tmt_real_dataset.csv successfully.")
