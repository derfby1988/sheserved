// ปุ่ม Google Sign-In ทางการ (Google Identity Services) สำหรับ web —
// conditional export: impl จริงเฉพาะ web, platform อื่นได้ stub
export 'google_web_sign_in_button_stub.dart'
    if (dart.library.html) 'google_web_sign_in_button_web.dart';
