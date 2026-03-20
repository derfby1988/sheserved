# คู่มือ Format External Drive เป็น APFS

## ⚠️ คำเตือนสำคัญ

**การ format จะลบข้อมูลทั้งหมดใน drive!**
- ✅ Backup ข้อมูลสำคัญก่อน format
- ✅ ตรวจสอบให้แน่ใจว่าเลือก drive ถูกต้อง
- ✅ ไม่สามารถกู้คืนข้อมูลได้หลัง format

---

## ขั้นตอนการ Format

### ขั้นตอนที่ 1: ตรวจสอบ External Drives

รันคำสั่งนี้เพื่อดู external drives ที่มี:

```bash
diskutil list
```

หรือดู drives ที่ mount อยู่:

```bash
df -h | grep Volumes | grep -v "/System/Volumes"
```

**ตัวอย่าง output:**
```
/dev/disk3s1    223Gi   223Gi   66Mi   100%   /Volumes/Dave_240G
/dev/disk4s1    931Gi   350Gi   582Gi   38%   /Volumes/Dave_1T
```

---

### ขั้นตอนที่ 2: Unmount External Drive

**เลือก drive ที่ต้องการ format** (เช่น `/dev/disk3` สำหรับ Dave_240G)

```bash
# วิธีที่ 1: Unmount โดยใช้ mount point
diskutil unmountDisk /Volumes/Dave_240G

# วิธีที่ 2: Unmount โดยใช้ device name
diskutil unmountDisk /dev/disk3
```

**ตรวจสอบว่า unmount สำเร็จ:**
```bash
diskutil list
# drive ควรไม่มี mount point แล้ว
```

---

### ขั้นตอนที่ 3: Format เป็น APFS

**⚠️ ระวัง: ข้อมูลทั้งหมดจะถูกลบ!**

```bash
# Format เป็น APFS
# เปลี่ยน disk3 เป็น device name ที่ถูกต้อง
diskutil eraseDisk APFS "PostgreSQL" /dev/disk3
```

**หรือถ้าต้องการ APFS Encrypted:**

```bash
# Format เป็น APFS Encrypted (แนะนำสำหรับ database)
diskutil eraseDisk APFS "PostgreSQL" /dev/disk3
# จากนั้น enable encryption:
diskutil apfs encryptVolume /dev/disk3s1
```

---

### ขั้นตอนที่ 4: ตรวจสอบผลลัพธ์

```bash
# ตรวจสอบ filesystem
diskutil info /Volumes/PostgreSQL | grep "File System"

# ควรแสดง: File System Personality: APFS
```

---

## คำสั่งแบบครบถ้วน (Copy-Paste)

**สำหรับ drive ที่ mount อยู่ที่ `/Volumes/Dave_240G`:**

```bash
# 1. หา device name
DEVICE=$(diskutil info /Volumes/Dave_240G | grep "Device Node" | awk '{print $3}')
echo "Device: $DEVICE"

# 2. Unmount
diskutil unmountDisk "$DEVICE"

# 3. Format เป็น APFS
diskutil eraseDisk APFS "PostgreSQL" "$DEVICE"

# 4. ตรวจสอบ
diskutil info /Volumes/PostgreSQL | grep "File System"
```

---

## หลังจาก Format เสร็จ

1. **Drive จะ mount อัตโนมัติ** ที่ `/Volumes/PostgreSQL`

2. **Setup PostgreSQL:**
   ```bash
   cd /Users/dave_macmini/tree_law_zoo
   ./setup-postgresql-external-hfs.sh
   ```
   
   เมื่อ script ถาม external drive ให้ใส่:
   ```
   /Volumes/PostgreSQL
   ```

---

## Troubleshooting

### ปัญหา: "Resource busy" หรือ "Device is busy"

**แก้ไข:**
```bash
# ตรวจสอบว่า drive ถูกใช้อยู่หรือไม่
lsof | grep /Volumes/Dave_240G

# Force unmount (ระวัง!)
diskutil unmountDisk force /dev/disk3
```

### ปัญหา: "Permission denied"

**แก้ไข:**
```bash
# ใช้ sudo (ถ้าจำเป็น)
sudo diskutil eraseDisk APFS "PostgreSQL" /dev/disk3
```

### ปัญหา: Format ไม่สำเร็จ

**ตรวจสอบ:**
```bash
# ดู error log
diskutil list

# ตรวจสอบว่า drive เสียหรือไม่
diskutil verifyDisk /dev/disk3
```

---

## หมายเหตุ

- **APFS** ใช้ได้กับ macOS High Sierra (10.13) ขึ้นไป
- **APFS Encrypted** ปลอดภัยกว่า แต่ต้องใส่ password เมื่อ mount
- **APFS** ไม่สามารถอ่านได้จาก Windows/Linux โดยตรง
- สำหรับ PostgreSQL แนะนำใช้ **APFS** (ไม่ต้อง encrypted ก็ได้)

---

## สรุป

1. ✅ Backup ข้อมูลสำคัญ
2. ✅ Unmount drive
3. ✅ Format เป็น APFS
4. ✅ Setup PostgreSQL ด้วย script

**หลังจาก format เสร็จแล้ว บอกได้เลย จะช่วย setup PostgreSQL ต่อ!** 🚀
