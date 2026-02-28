import pandas as pd
import re

# โหลดข้อมูล TMT
print("Loading Excel...")
df = pd.read_excel('TMTRF20260216_FULL.xls')
print("Total rows:", len(df))

# สุ่มข้อมูลหรือเอาข้อมูลที่ไม่ซ้ำมา 500 รายการ เพื่อไม่ให้ไฟล์หนักเกิน
sampled = df.sample(500, random_state=123)

def extract_drug_info(fsn_text):
    if not isinstance(fsn_text, str):
        return None
    
    # 0.0001% DPCP (F 12249) (diphenylcyclopropenone 100 mcg/100 mL) cutaneous solution, 5 mL bottle (TPU)
    # AMOXIL 500 (amoxicillin 500 mg) capsule (TPU)
    match = re.search(r"^(.*?)\s*\((.*?)\)\s*(.*?)\s*\(TPU\)$", fsn_text)
    if match:
        trade_name = match.group(1).strip().replace("'", "''")
        generic_strength = match.group(2).strip().replace("'", "''")
        dosage_form = match.group(3).strip().replace("'", "''")
        
        # สมมติง่ายๆ ให้ Generic ประกอบด้วยตัวยา และ Strength ดึงมาจาก Dosage form หรือแยกแบบง่ายๆ
        # เนื่องจาก TMT ชื่อซับซ้อนมาก ในโปรดักขั่นจริงต้องอิงจาก VTM/GPU 
        return {
            'trade_name': trade_name[:250],
            'generic_name': generic_strength[:250],
            'dosage_form': dosage_form[:100],
            'strength': 'See Generic Name'
        }
    return None

sql_statements = []
sql_statements.append("TRITRUNCATE TABLE public.medications CASCADE;\n")
sql_statements.append("DROP POLICY IF EXISTS \"Enable insert access for all users\" ON public.medications;")
sql_statements.append("CREATE POLICY \"Enable insert access for all users\" ON public.medications FOR INSERT WITH CHECK (true);\n")

sql_statements.append("INSERT INTO public.medications (source_type, reference_code, generic_name, trade_name, dosage_form, manufacturer, status) VALUES")

values = []
for index, row in sampled.iterrows():
    info = extract_drug_info(row['FSN'])
    if info:
        tmt_code = str(row['TMTID(TPU)'])
        manufacturer = str(row['MANUFACTURER']).replace("'", "''")[:250]
        val = f"('TMT', '{tmt_code}', '{info['generic_name']}', '{info['trade_name']}', '{info['dosage_form']}', '{manufacturer}', 'ACTIVE')"
        values.append(val)

if values:
    sql_statements.append(",\n".join(values) + ";")
    
    with open('tmt_massive_seed.sql', 'w') as f:
        f.write("\n".join(sql_statements))
    print(f"Generated SQL with {len(values)} records in tmt_massive_seed.sql")
else:
    print("Failed to parse any rows")
