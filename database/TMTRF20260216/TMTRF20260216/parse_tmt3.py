import pandas as pd
import re

df = pd.read_excel('TMTRF20260216_SNAPSHOT.xls')

def extract_drug_info(fsn_text):
    if not isinstance(fsn_text, str):
        return None
    
    # 0.0001% DPCP (F 12249) (diphenylcyclopropenone 100 mcg/100 mL) cutaneous solution, 5 mL bottle (TPU)
    # AMOXIL 500 (amoxicillin 500 mg) capsule (TPU)
    # SARA (paracetamol 500 mg) tablet (TPU)
    # GOFEN 400 (ibuprofen 400 mg) clear soft capsule (TPU)

    # pattern to extract Trade Name, Generic Name+Strength, Dosage form
    # Usually: TRADE_NAME (generic_name strength) dosage_form (TPU)
    
    match = re.search(r"^(.*?)\s*\((.*?)\)\s*(.*?)\s*\(TPU\)$", fsn_text)
    if match:
        trade_name = match.group(1).strip()
        generic_strength = match.group(2).strip()
        dosage_form = match.group(3).strip()
        
        # split generic and strength
        parts = generic_strength.rsplit(' ', 2) # usually 'paracetamol', '500', 'mg'
        if len(parts) >= 2 and parts[-1].isalpha() and any(char.isdigit() for char in parts[-2]):
            generic_name = ' '.join(parts[:-2]) if len(parts) > 2 else parts[0]
            strength = f"{parts[-2]} {parts[-1]}"
        else:
            generic_name = generic_strength
            strength = ""

        return {
            'trade_name': trade_name,
            'generic_name': generic_name,
            'dosage_form': dosage_form,
            'strength': strength
        }
    return None

sampled = df.sample(50, random_state=42)
results = []
for index, row in sampled.iterrows():
    info = extract_drug_info(row['FSN'])
    if info:
        info['tmt_code'] = row['TMTID(TPU)']
        info['manufacturer'] = row['MANUFACTURER']
        results.append(info)

print(pd.DataFrame(results).head(20).to_json(orient='records', force_ascii=False, indent=2))
