# iOS Runtime Performance และ Launch Troubleshooting

## อาการที่พบ

เมื่อสั่งรัน Flutter บน iPhone จริงด้วย `flutter run --profile` หรือ `flutter run --release` อาจพบอาการดังนี้:

- หน้าจอขาวหรือไม่มี UI
- แอปใช้เวลานานก่อนแสดงหน้าจอแรก
- `Unhandled Exception: type 'Null' is not a subtype of type 'bool'`
- `ChatMessageAdapter.read` หรือ `HiveImpl.openBox` อยู่ใน stack trace
- `SIGKILL`
- `The Dart VM Service was not discovered after 60 seconds`
- `CompileStoryboard failed with a nonzero exit code`

## สาเหตุหลัก

### 1. Hive ข้อมูลเก่าไม่ตรงกับ model ปัจจุบัน

เมื่อเพิ่มหรือเปลี่ยน Hive field เช่น `ChatMessage.isRequired` ข้อมูลที่บันทึกอยู่ในอุปกรณ์อาจไม่มี field นั้น หรือมีค่า `null` แต่ adapter รุ่นใหม่ cast เป็น `bool` โดยตรง:

```dart
fields[11] as bool
```

การอ่านข้อมูลจึง throw exception ระหว่าง `main()` และ `runApp()` ยังไม่ถูกเรียก ทำให้เห็นหน้าจอว่าง

จุดที่เกี่ยวข้อง:

- `lib/main.dart` — การเปิด Hive boxes
- `lib/features/chat/data/models/chat_models.dart` — Hive models
- `lib/features/chat/data/models/chat_models.g.dart` — generated adapters

### 2. Startup รอ network แบบเรียงลำดับ

ก่อนแสดง UI แอปเดิมรอหลายขั้นตอนต่อเนื่อง:

1. Supabase initialization
2. โหลด `SyncConfig` จาก Supabase
3. เปิด Hive boxes
4. ตรวจสอบ local API ที่ `172.20.10.13:8080`
5. เริ่ม SyncService

หาก iPhone เข้า local server ไม่ได้หรือ network ตอบช้า แอปจะใช้เวลานานมากก่อนแสดง UI แม้ตัวแอปจะทำงานได้ตามปกติ

### 3. Profile mode ต้องใช้ Dart VM Service

`flutter run --profile` มีไว้สำหรับ profiling และต้องเชื่อมต่อ Dart VM Service กับอุปกรณ์จริง หาก CoreDevice/Xcode connection หลุด จะพบ `SIGKILL` หรือรอ VM Service จนครบ 60 วินาที

สำหรับการใช้งานปกติไม่ควรใช้ profile mode

### 4. Xcode storyboard/cache build ชั่วคราว

บางครั้ง `flutter run` รายงานเพียง:

```text
CompileStoryboard failed with a nonzero exit code
```

แต่ไม่มีรายละเอียดเพียงพอใน output ปกติ สาเหตุอาจเป็น Xcode build cache หรือ build state ชั่วคราว ไม่ได้แปลว่า storyboard เสียเสมอไป

## วิธีแก้ไขที่ใช้ในโปรเจกต์

### Hive: เปิด box แบบปลอดภัย

`main.dart` ใช้ helper `_openBoxSafe<T>()` ดังนี้:

- พยายามเปิด box ตามปกติ
- หากอ่านข้อมูลเก่าไม่ได้ ให้ลบ box ที่เสียจาก disk
- สร้าง box ใหม่และเปิดอีกครั้ง

นอกจากนี้ adapter ต้องรองรับค่า null สำหรับ boolean field ที่เพิ่มภายหลัง:

```dart
isRequired: fields[11] as bool? ?? false
isActive: fields[9] as bool? ?? true
```

หมายเหตุ: การลบ box จะลบ cache แชตในเครื่อง แต่ไม่ลบข้อมูลหลักจาก Supabase

### Startup: ไม่รอ sync network

`ServiceLocator.initialize()` ต้องทำเฉพาะการสร้าง repository และ dependency ที่จำเป็นต่อการวาดหน้าแรก:

- Initial sync ให้ทำเบื้องหลังด้วย `unawaited(...)`
- Local health check ใช้ timeout สั้น ๆ ไม่เกิน 1 วินาที
- ห้ามให้การเชื่อมต่อ local API ที่ล้มเหลวขัดขวาง `runApp()`

### ATS สำหรับ local HTTP

หากใช้ local API ผ่าน HTTP ให้ตรวจ `ios/Runner/Info.plist` ว่า IP ที่ใช้งานจริงอยู่ใน `NSExceptionDomains` เช่น `172.20.10.13` และเปิด `NSAllowsLocalNetworking` แล้ว

ควรใช้ HTTPS ใน production แทนการอนุญาต HTTP แบบ exception

## คำสั่งรันที่แนะนำ

### ใช้งานปกติและต้องการความเร็ว

```bash
flutter run --release --no-pub -d 00008120-000058A41A40C01E
```

`--release` ไม่ต้องพึ่ง Dart VM Service และเหมาะกับการใช้งานจริง

### Debug พร้อม hot reload

```bash
flutter run --debug --no-pub -d 00008120-000058A41A40C01E
```

ใช้เมื่อต้องดู log หรือแก้โค้ดแบบ hot reload

### Profile สำหรับวัด performance เท่านั้น

```bash
flutter run --profile --no-pub -d 00008120-000058A41A40C01E
```

ต้องรอ Dart VM Service และไม่ควรใช้เป็นคำสั่งรันประจำ

## ขั้นตอนตรวจสอบเมื่อเกิดปัญหาอีก

1. อ่าน log หา `ChatMessageAdapter.read`, `HiveImpl.openBox` หรือ `type 'Null' is not a subtype of type 'bool'`
2. หากพบ ให้ตรวจ Hive adapter และใช้ `_openBoxSafe<T>()`
3. หากแอปช้าก่อนมี UI ให้ตรวจ await ใน `main()` และ `ServiceLocator.initialize()`
4. หากพบ `SIGKILL` หรือ VM Service timeout ให้หยุด process เดิม แล้วรันด้วย `--release --no-pub`
5. หากพบ `CompileStoryboard` ให้รัน build verbose เพื่อดึง error จริง:

```bash
flutter build ios --debug --no-pub -v
```

6. หาก verbose build ผ่าน แต่ `flutter run` ล้มเหลว ให้รัน `flutter run` ใหม่โดยไม่เปลี่ยน storyboard แบบสุ่ม เพราะปัญหามักเป็น Xcode cache/state ชั่วคราว
7. หาก build ยังไม่ผ่าน ค่อยตรวจ `ios/Runner/Base.lproj/LaunchScreen.storyboard`, `Main.storyboard`, Xcode version และ signing configuration

## บทเรียนสำคัญ

- หน้าจอขาวไม่ได้หมายความว่า ATS เป็นสาเหตุเสมอไป ต้องอ่าน stack trace ก่อน
- Exception ใน `main()` ก่อน `runApp()` ทำให้แอปดูเหมือนว่างเปล่า
- Local network และ initial sync ไม่ควร block การแสดง UI แรก
- `--profile` ใช้สำหรับวัด performance ไม่ใช่คำสั่งรันปกติ
- หลังแก้ Hive schema ต้องออกแบบ migration หรือ fallback สำหรับข้อมูลเก่าบนอุปกรณ์จริงเสมอ
