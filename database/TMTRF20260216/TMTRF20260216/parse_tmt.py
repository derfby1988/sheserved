import pandas as pd
import json

df = pd.read_excel('TMTRF20260216_SNAPSHOT.xls')
print("Columns:", df.columns.tolist())
print(df.head(2).to_json(orient='records', force_ascii=False))
