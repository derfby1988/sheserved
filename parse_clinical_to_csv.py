import pandas as pd
import csv
import re

# Since there is no actual full clinical dataset at hand, we will mock some generic names 
# that exist in the real TMT data, assigning some basic clinical info so MedicationDetailPage looks complete.
# E.g. paracetamol, amoxicillin, ibuprofen etc.

clinical_data = [
    {
        "generic_name": "paracetamol",
        "indications": "ใช้บรรเทาอาการปวดเล็กน้อยถึงปานกลาง และลดไข้",
        "dosage_administration": "ผู้ใหญ่: รับประทานครั้งละ 1-2 เม็ด ทุก 4-6 ชั่วโมง (ไม่เกิน 8 เม็ด/วัน)",
        "contraindications": "ผู้ป่วยโรคตับรุนแรง, แพ้ยาพาราเซตามอล",
        "adverse_reactions": "หากใช้เกินขนาดอาจเกิดพิษต่อตับ เกิดผื่นแพ้",
        "special_precautions": "ไม่ควรใช้ติดต่อกันนานเกิน 5 วันโดยไม่ปรึกษาแพทย์",
    },
    {
        "generic_name": "amoxicillin",
        "indications": "ใช้รักษาโรคติดเชื้อแบคทีเรีย เช่น ติดเชื้อในทางเดินหายใจ หูอักเสบ",
        "dosage_administration": "ผู้ใหญ่: รับประทาน 250-500 มิลลิกรัม วันละ 3 ครั้ง",
        "contraindications": "ผู้ป่วยที่แพ้ยากลุ่มเพนิซิลลิน (Penicillins)",
        "adverse_reactions": "คลื่นไส้ อาเจียน ท้องเสีย มีผื่นคัน",
        "special_precautions": "ควรรับประทานยาให้ครบตามที่แพทย์สั่งอย่างเคร่งครัด",
    },
    {
        "generic_name": "ibuprofen",
        "indications": "ใช้ลดไข้ และบรรเทาอาการปวดอักเสบต่างๆ เช่น ปวดประจำเดือน ปวดข้อ",
        "dosage_administration": "ผู้ใหญ่: รับประทานครั้งละ 400 มิลลิกรัม ทุก 4-6 ชั่วโมง หลังอาหารทันที",
        "contraindications": "ผู้ป่วยไข้เลือดออก, โรคแผลในกระเพาะอาหาร, หญิงตั้งครรภ์ไตรมาสสุดท้าย",
        "adverse_reactions": "ระคายเคืองกระเพาะอาหาร, คลื่นไส้, เลือดออกในทางเดินอาหาร",
        "special_precautions": "ห้ามใช้ในผู้ป่วยสงสัยไข้เลือดออก และระวังมิตรกระเพาะอาหารควรทานหลังอาหารทันที",
    },
    {
        "generic_name": "salbutamol",
        "indications": "บรรเทาอาการหลอดลมตีบในผู้ป่วยโรคหอบหืด (Asthma)",
        "dosage_administration": "ชนิดพ่น: พ่น 1-2 ครั้ง เมื่อมีอาการ (หรือตามแพทย์สั่ง)",
        "contraindications": "ระมัดระวังในผู้ป่วยโรคหัวใจเต้นผิดจังหวะ, ไทรอยด์เป็นพิษ",
        "adverse_reactions": "ใจสั่น, มือสั่น, ปวดศีรษะ",
        "special_precautions": "หากพ่นยาแล้วอาการไม่ดีขึ้น ให้รีบไปพบแพทย์",
    },
    {
        "generic_name": "chlorpheniramine",
        "indications": "บรรเทาอาการแพ้ เช่น น้ำมูกไหล จาม ลมพิษ",
        "dosage_administration": "ผู้ใหญ่: รับประทานครั้งละ 1 เม็ด (4 มก.) ทุก 4-6 ชั่วโมง (ไม่เกิน 6 เม็ด/วัน)",
        "contraindications": "ทารกแรกเกิด, เด็กคลอดก่อนกำหนด",
        "adverse_reactions": "ง่วงซึม, ปากแห้ง, คอแห้ง, ปัสสาวะคั่ง",
        "special_precautions": "ยานี้อาจทำให้ง่วงซึม ห้ามขับรถหรือทำงานกับเครื่องจักร",
    }
]

with open('sheserved_clinical_mock_dataset.csv', 'w', newline='', encoding='utf-8') as file:
    fieldnames = ['generic_name', 'indications', 'dosage_administration', 'contraindications', 'special_precautions', 'adverse_reactions']
    writer = csv.DictWriter(file, fieldnames=fieldnames)
    writer.writeheader()
    for row in clinical_data:
        writer.writerow(row)

print("Saved to sheserved_clinical_mock_dataset.csv successfully.")
