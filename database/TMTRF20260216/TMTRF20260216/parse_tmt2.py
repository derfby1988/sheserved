import pandas as pd
df = pd.read_excel('TMTRF20260216_FULL.xls')
print("Columns:", df.columns.tolist())
print(df.head(2).to_json(orient='records', force_ascii=False))
