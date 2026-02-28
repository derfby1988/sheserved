import pandas as pd
import re
import csv
import json

# โหลดข้อมูล TTMT
print("Loading TTMT Excel...")
df = pd.read_excel('../MasterTTMT_THIS_20260107.xls')
print("Total TTMT rows:", len(df))

records = []
for index, row in df.iterrows():
    trade_name = str(row.get('TradeName', ''))
    if pd.isna(row['TradeName']):
        trade_name = str(row.get('ActiveIngredient', ''))
        
    records.append({
        "source_type": "TTMT", # Thai Traditional Medicines Terminology
        "reference_code": str(row.get('TTMTCode', '')),
        "generic_name": str(row.get('ActiveIngredient', ''))[:250],
        "trade_name": trade_name[:250],
        "dosage_form": str(row.get('Dosageform', ''))[:100],
        "manufacturer": str(row.get('Manufacturer', ''))[:250],
        "status": "ACTIVE"
    })

print(f"Parsed {len(records)} records. Saving to TTMT CSV...")

with open('sheserved_ttmt_real_dataset.csv', 'w', newline='', encoding='utf-8') as file:
    fieldnames = ['source_type', 'reference_code', 'generic_name', 'trade_name', 'dosage_form', 'manufacturer', 'status']
    writer = csv.DictWriter(file, fieldnames=fieldnames)
    writer.writeheader()
    for row in records:
        writer.writerow(row)

print("Saved to sheserved_ttmt_real_dataset.csv successfully.")
