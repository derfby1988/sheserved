# แผนการทดสอบระบบทั้งหมดของ Sheserved
## Comprehensive Maestro E2E Test Plan

> **วันที่สร้าง/อัปเดต:** 2026-07-24 (อัปเดตล่าสุด: แก้ไข login flow + shared login)
> **เครื่องมือ:** Maestro (YAML flows)
> **ไฟล์เก็บ:** `/Users/apisekpanyakong/ProjectFlutter/sheserved/docs/guides/`
> **อุปกรณ์หลัก:** iPhone 16 Simulator (`A692F954-72BF-4D54-9557-FB61BCB5DBA6`, iOS 18.1)
> **App ID:** `com.example.treeLawZoo`

---

## 1. หลักการวางแผน (Principles)

- **หนึ่ง scenario หนึ่งสถานะการณ์** — แยก test flow ให้ล้มเหลวอิสระกัน
- **ใช้ role ที่ถูกต้อง** — ทดสอบทั้ง happy path และ unauthorized access
- **ยืนยันผลจริงจาก UI** — ไม่ใช้แค่ navigation ว่าหน้าเปิดได้
- **Reproducible** — กำหนดบัญชีทดสอบ ข้อมูล DB และลำดับก่อนหลังชัดเจน
- **Tag ตาม priority** — ใช้ Maestro tags (`smoke`, `regression`, `erp`, `admin`) สำหรับรันเลือกกลุ่ม

---

## 2. ระบบทั้งหมดใน Sheserved (17 ระบบหลัก)

| # | ระบบ | โฟลเดอร์หลัก | สถานะทดสอบ | ไฟล์ที่มีแล้ว |
|---|------|-------------|------------|--------------|
| 1 | **Authentication & Registration** | `features/auth/` | ✅ **สร้างแล้ว 7 scenarios** | `scenario_auth_01`–`07` |
| 2 | **Home & Navigation** | `features/home/`, `shared/widgets/` | ✅ **สร้างแล้ว 6 scenarios** | `scenario_home_01`–`06` |
| 3 | **Consultation & ChartBoard** | `features/consultation/` | ✅ **สร้างแล้ว 11 scenarios** | `scenario_cons_01`–`11` |
| 4 | **Chat & Video Call** | `features/chat/`, `features/video/` | ✅ **สร้างแล้ว 5 scenarios** | `scenario_chat_01`–`05` |
| 5 | **Pharmacy & Drug Risk** | `features/pharmacy/` | ✅ **ผ่าน 14 scenarios** | `scenario_02`–`13` (ไม่มี scenario_01) |
| 6 | **Donation** | `features/donation/` | ยังไม่มี | — |
| 7 | **Emergency & Rescue** | `features/video/` | ยังไม่มี | — |
| 8 | **Health & Articles** | `features/health/`, `features/articles/` | ยังไม่มี | — |
| 9 | **Profile & Settings** | `features/profile/`, `features/settings/` | ยังไม่มี | — |
| 10 | **ERP Dashboard & Settings** | `ERP Dashboard/`, `features/erp/presentation/pages` | ยังไม่มี | — |
| 11 | **ERP Inventory** | `features/erp/presentation/pages` | ยังไม่มี | — |
| 12 | **ERP Procurement** | `features/erp/presentation/pages` | ยังไม่มี | — |
| 13 | **ERP Sales & POS** | `features/erp/presentation/pages` | ยังไม่มี | — |
| 14 | **ERP Finance & HR** | `features/erp/presentation/pages` | ยังไม่มี | — |
| 15 | **ERP Clinical** | `features/erp/presentation/pages` | ยังไม่มี | — |
| 16 | **Admin & KPI** | `features/admin/`, `features/kpi/` | ยังไม่มี | — |
| 17 | **Community** | `features/community/` | ยังไม่มี | — |

---

## 3. ลำดับการทดสอบ (Priority)

### Phase 1: Core Flows (สำคัญสูงสุด)

**หมายเหตุ:** Phase 1 เป็น smoke tests ที่ต้องผ่านก่อน เพราะถ้า login หรือ navigation มีปัญหา ระบบอื่นจะทดสอบไม่ได้

> **Shared Login Flow:** ทุก scenario ที่ต้อง login ใช้ `runFlow: _shared_login.yaml` ซึ่งจัดการ login + แตะแท็บหน้าหลักหลังล็อกอิน (แก้ปัญหา donation tab redirect)

#### 1.1 Authentication & Registration
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| AUTH-01 | Login ด้วย username + password สำเร็จ (provider) | `scenario_auth_01_login_username.yaml` | `smoke` | ✅ สร้างแล้ว |
| AUTH-02 | Login ด้วย phone + password สำเร็จ | `scenario_auth_02_login_phone.yaml` | `smoke` | ✅ สร้างแล้ว |
| AUTH-03 | Login ผิดพลาด: username หรือรหัสผิด → แสดง error | `scenario_auth_03_login_fail.yaml` | `smoke` | ✅ สร้างแล้ว |
| AUTH-04 | Logout สำเร็จ กลับหน้า Home ในโหมด guest | `scenario_auth_04_logout.yaml` | `smoke` | ✅ สร้างแล้ว |
| AUTH-05 | Session persistence: ปิดแอปแล้วเปิดยัง login อยู่ | `scenario_auth_05_session_persist.yaml` | `smoke` | ✅ สร้างแล้ว |
| AUTH-06 | Register wizard flow: ลงทะเบียนผู้ใช้ใหม่ครบทุกขั้นตอน | `scenario_auth_06_register_wizard.yaml` | `registration` | ✅ สร้างแล้ว |
| AUTH-07 | Register simple: สร้างบัญชีเร่งด่วน | `scenario_auth_07_register_simple.yaml` | `registration` | ✅ สร้างแล้ว |

#### 1.2 Route Guards & Authorization
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| GUARD-01 | ไม่ login เข้า `/erp/dashboard` → redirect | `scenario_guard_01_erp_no_auth.yaml` | `security` | ✅ สร้างแล้ว |
| GUARD-02 | consumer เข้า `/erp/dashboard` → redirect ไป `/home` | `scenario_guard_02_erp_consumer.yaml` | `security` | ✅ สร้างแล้ว |
| GUARD-03 | provider ไม่มีสิทธิ์ admin → ไม่เห็นเมนู Admin | `scenario_guard_03_admin_provider.yaml` | `security` | ✅ สร้างแล้ว |
| GUARD-04 | admin เข้า ERP ได้ และเห็นเมนู Admin | `scenario_guard_04_admin_access.yaml` | `smoke` | ✅ สร้างแล้ว |

#### 1.3 Home & Navigation
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| HOME-01 | หน้า Home แสดง search bar และ category icons (guest) | `scenario_home_01_search_bar.yaml` | `smoke` | ✅ สร้างแล้ว |
| HOME-02 | หน้า Home แสดง donation cards / featured content | `scenario_home_02_donation_cards.yaml` | `smoke` | ✅ สร้างแล้ว |
| HOME-03 | Drawer เปิด/ปิด และแสดงเมนูตาม role | `scenario_home_03_drawer_open.yaml` | `smoke` | ✅ สร้างแล้ว |
| HOME-04 | Bottom navigation bar สลับ tab ได้ | `scenario_home_04_bottom_nav.yaml` | `smoke` | ✅ สร้างแล้ว |
| HOME-05 | Search บน home page ค้นหา (ร้านยา, ปรึกษาแพทย์, นวดสปา) | `scenario_home_05_search_medication.yaml` | `smoke` | ✅ สร้างแล้ว |
| HOME-06 | Notification bell icon แสดง badge/count | `scenario_home_06_notification.yaml` | `smoke` | ✅ สร้างแล้ว |

#### 1.4 Consultation & ChartBoard
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| CONS-01 | Provider เข้า `HealthProgramRequestDashboard` | `scenario_cons_01_dashboard.yaml` | `smoke, consultation` | ✅ สร้างแล้ว |
| CONS-02 | เปิด in_progress tab → เข้า ChartBoardPage | `scenario_cons_02_in_progress.yaml` | `consultation` | ✅ สร้างแล้ว |
| CONS-03 | ดู finished tab ของ dashboard | `scenario_cons_03_finished.yaml` | `consultation` | ✅ สร้างแล้ว |
| CONS-04 | เปิด `ChartBoardPage` จาก consultation | `scenario_cons_04_chartboard.yaml` | `consultation` | ✅ สร้างแล้ว |
| CONS-05 | ส่งข้อความใน `ChartBoardPage` | `scenario_cons_05_send_message.yaml` | `consultation` | ✅ สร้างแล้ว |
| CONS-06 | ปุ่ม "เครื่องมือแพทย์" เปิด medical tools panel | `scenario_cons_06_medical_tools.yaml` | `consultation` | ✅ สร้างแล้ว |
| CONS-07 | ออกใบสั่งยา → `PrescriptionEditorPage` | `scenario_cons_07_prescription_editor.yaml` | `consultation` | ✅ สร้างแล้ว |
| CONS-08 | สร้างใบสั่งยา draft และบันทึก | `scenario_cons_08_prescription_draft.yaml` | `consultation` | ✅ สร้างแล้ว |
| CONS-09 | ส่งใบสั่งยา (submit) และตรวจสอบ drug risk screening | `scenario_cons_09_prescription_submit.yaml` | `consultation` | ✅ สร้างแล้ว |
| CONS-10 | ปุ่ม "จบการรักษา" บน ChartBoardPage | `scenario_cons_10_finish.yaml` | `consultation` | ✅ สร้างแล้ว |
| CONS-11 | ยกเลิกการจบการรักษา (revert finish) | `scenario_cons_11_revert_finish.yaml` | `consultation` | ✅ สร้างแล้ว |

#### 1.5 Chat & Video Call
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| CHAT-01 | ChartBoardPage แสดง chat history | `scenario_chat_01_history.yaml` | `chat` | ✅ สร้างแล้ว |
| CHAT-02 | ส่งข้อความใหม่ใน ChartBoardPage | `scenario_chat_02_send.yaml` | `chat` | ✅ สร้างแล้ว |
| CHAT-03 | ส่งรูปภาพใน ChartBoardPage | `scenario_chat_03_send_image.yaml` | `chat` | ✅ สร้างแล้ว |
| CHAT-04 | ส่งไฟล์เสียง (voice message) ใน ChartBoardPage | `scenario_chat_04_voice.yaml` | `chat` | ✅ สร้างแล้ว |
| CHAT-05 | กดปุ่ม "ถามผู้เชี่ยวชาญ" เพื่อเริ่มคำปรึกษาใหม่ | `scenario_chat_05_ask_expert.yaml` | `chat` | ✅ สร้างแล้ว |

### Phase 2: Business Flows (สำคัญสูง)

#### 2.1 Pharmacy & Drug Risk (สำเร็จแล้ว 14 scenarios)
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| DRUG-02 | Admin ตั้ง Organization Override (`scenario_02_organization_override.yaml`) | `scenario_02_organization_override.yaml` | `drug-risk, regression` | ✅ ผ่าน |
| DRUG-03 | Member ไม่มีสิทธิ์ (`scenario_03_member_no_permission.yaml`) | `scenario_03_member_no_permission.yaml` | `drug-risk, regression` | ✅ ผ่าน |
| DRUG-04 | Editor คนที่สองเห็น History (`scenario_04_second_editor_history.yaml`) | `scenario_04_second_editor_history.yaml` | `drug-risk` | ✅ ผ่าน |
| DRUG-05 | คลินิกอื่นไม่เห็น Override (`scenario_05_other_clinic_no_override.yaml`) | `scenario_05_other_clinic_no_override.yaml` | `drug-risk` | ✅ ผ่าน |
| DRUG-06 | Telemedicine legal ความเสี่ยงยา (`scenario_06_telemedicine_legal.yaml`) | `scenario_06_telemedicine_legal.yaml` | `drug-risk` | ✅ ผ่าน |
| DRUG-07 | Remove Override (`scenario_07_remove_override.yaml`) | `scenario_07_remove_override.yaml` | `drug-risk` | ✅ ผ่าน |
| DRUG-08 | Fallback history (`scenario_08_fallback_history.yaml`) | `scenario_08_fallback_history.yaml` | `drug-risk` | ✅ ผ่าน |
| DRUG-08a | Set override ทดสอบ fallback (`scenario_08a_set_override.yaml`) | `scenario_08a_set_override.yaml` | `drug-risk` | ✅ ผ่าน |
| DRUG-08b | Verify fallback (`scenario_08b_verify_fallback.yaml`) | `scenario_08b_verify_fallback.yaml` | `drug-risk` | ✅ ผ่าน |
| DRUG-09 | Fallback system (`scenario_09_fallback_system.yaml`) | `scenario_09_fallback_system.yaml` | `drug-risk` | ✅ ผ่าน |
| DRUG-10 | Personal Override for profession_id IS NULL (`scenario_10_personal_override_history.yaml`) | `scenario_10_personal_override_history.yaml` | `drug-risk` | ✅ ผ่าน |
| DRUG-12 | Prescription Editor แสดง Effective Risk (`scenario_12_prescription_editor.yaml`) | `scenario_12_prescription_editor.yaml` | `drug-risk` | ✅ ผ่าน |
| DRUG-12b | Prescription Editor Effective Risk เฉพาะกรณี (`scenario_12_prescription_editor_effective_risk.yaml`) | `scenario_12_prescription_editor_effective_risk.yaml` | `drug-risk` | ✅ ผ่าน |
| DRUG-13 | Personal Override Badge ชนะ Org (`scenario_13_personal_override_badge.yaml`) | `scenario_13_personal_override_badge.yaml` | `drug-risk` | ✅ ผ่าน |

> **หมายเหตุ:** ไม่มี scenario 01 ใน repo; หมายเลข 11 ถูกใช้สำหรับ unit tests (`drug_risk_screening_service_test.dart`)

#### 2.2 Donation
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| DON-01 | ดู `DonationDashboardPage` (guest → redirect login) | `scenario_donation_01_guest.yaml` | `donation` | รอสร้าง |
| DON-02 | ดู `DonationDashboardPage` (logged in) | `scenario_donation_02_logged_in.yaml` | `donation` | รอสร้าง |
| DON-03 | สร้างคำขอรับบริจาค (`DonationCreatePage`) | `scenario_donation_03_create.yaml` | `donation` | รอสร้าง |
| DON-04 | ดูรายการบริจาค (`DonationListPage`) | `scenario_donation_04_list.yaml` | `donation` | รอสร้าง |
| DON-05 | ดูรายละเอียดบริจาค (`DonationDetailPage`) | `scenario_donation_05_detail.yaml` | `donation` | รอสร้าง |
| DON-06 | Admin จัดการบริจาค (`DonationAdminPage`) | `scenario_donation_06_admin.yaml` | `donation, admin` | รอสร้าง |
| DON-07 | Leader verification (`LeaderVerificationPage`) | `scenario_donation_07_leader.yaml` | `donation` | รอสร้าง |

#### 2.3 Emergency & Rescue
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| EMG-01 | ปุ่ม SOS → หน้า `EmergencyLivePage` (หรือ redirect login) | `scenario_emergency_01_sos.yaml` | `emergency` | รอสร้าง |
| EMG-02 | `EmergencyLivePage` แสดงวิดีโอ | `scenario_emergency_02_live.yaml` | `emergency` | รอสร้าง |
| EMG-03 | หน้า `RescuePage` (rescue map) | `scenario_emergency_03_rescue_map.yaml` | `emergency` | รอสร้าง |

#### 2.4 Health & Articles
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| HLT-01 | หน้า `HealthPage` แสดงข้อมูลสุขภาพ | `scenario_health_01_main.yaml` | `health` | รอสร้าง |
| HLT-02 | บันทึกข้อมูลสุขภาพ (`HealthDataEntryPage`) | `scenario_health_02_data_entry.yaml` | `health` | รอสร้าง |
| HLT-03 | อ่านบทความสุขภาพ (`HealthArticlePage`) | `scenario_health_03_article.yaml` | `health` | รอสร้าง |
| HLT-04 | ขอ Tag สำหรับบทความ (`ArticleTagRequestsPage`) | `scenario_health_04_tag_request.yaml` | `health` | รอสร้าง |
| HLT-05 | รายการบทความ (`ArticlesPage`) | `scenario_health_05_articles.yaml` | `health` | รอสร้าง |

### Phase 3: ERP System (สำคัญปานกลาง)

> **หมายเหตุ:** ERP เป็นระบบขนาดใหญ่ แนะนำให้แบ่งรันทีละ module ด้วย tags และใช้ admin ที่มี `employee_roles` ใน profession ที่ต้องการ

#### 3.1 ERP Dashboard & Settings
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| ERP-01 | เข้า `ErpDashboardPage` (มีสิทธิ์) | `scenario_erp_01_dashboard.yaml` | `erp` | รอสร้าง |
| ERP-02 | เข้า ERP (ไม่มีสิทธิ์ → redirect ไป `/home`) | `scenario_erp_02_no_access.yaml` | `erp, security` | รอสร้าง |
| ERP-03 | ตั้งค่า `OrganizationSettingsPage` | `scenario_erp_03_org_settings.yaml` | `erp` | รอสร้าง |
| ERP-04 | เปลี่ยน `ThemeSettingsPage` (dark/light) | `scenario_erp_04_theme.yaml` | `erp` | รอสร้าง |
| ERP-05 | จัดการ `ModuleLayoutSettingsPage` | `scenario_erp_05_module_layout.yaml` | `erp` | รอสร้าง |
| ERP-06 | ปรับ `GlassmorphismSettingsPage` | `scenario_erp_06_glass.yaml` | `erp` | รอสร้าง |
| ERP-07 | สลับ Branch จาก AppBar | `scenario_erp_07_branch.yaml` | `erp` | รอสร้าง |
| ERP-08 | `DashboardAnalyticsPage` แสดงตัวชี้วัด | `scenario_erp_08_analytics.yaml` | `erp` | รอสร้าง |

#### 3.2 ERP Inventory
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| INV-01 | ดู `InventoryPage` หลัก | `scenario_erp_inventory_01_main.yaml` | `erp, inventory` | รอสร้าง |
| INV-02 | ดู `InventoryDashboardPage` | `scenario_erp_inventory_02_dashboard.yaml` | `erp, inventory` | รอสร้าง |
| INV-03 | `StockTransferPage` ระหว่างสาขา | `scenario_erp_inventory_03_transfer.yaml` | `erp, inventory` | รอสร้าง |
| INV-04 | `StockAdjustmentPage` | `scenario_erp_inventory_04_adjustment.yaml` | `erp, inventory` | รอสร้าง |
| INV-05 | `StockMovementTrackingPage` | `scenario_erp_inventory_05_movements.yaml` | `erp, inventory` | รอสร้าง |
| INV-06 | `GoodsReceiptPage` | `scenario_erp_inventory_06_receipt.yaml` | `erp, inventory` | รอสร้าง |
| INV-07 | `StocktakeConfigPage` | `scenario_erp_inventory_07_stocktake.yaml` | `erp, inventory` | รอสร้าง |

#### 3.3 ERP Procurement
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| PROC-01 | ดู `ProcurementPage` (suppliers) | `scenario_erp_procurement_01_suppliers.yaml` | `erp, procurement` | รอสร้าง |
| PROC-02 | ดู `SupplierDetailPage` | `scenario_erp_procurement_02_supplier_detail.yaml` | `erp, procurement` | รอสร้าง |
| PROC-03 | `ProcurementDashboardPage` | `scenario_erp_procurement_03_dashboard.yaml` | `erp, procurement` | รอสร้าง |
| PROC-04 | `ReorderSuggestionPage` | `scenario_erp_procurement_04_reorder.yaml` | `erp, procurement` | รอสร้าง |
| PROC-05 | `ProcurementReportPage` | `scenario_erp_procurement_05_report.yaml` | `erp, procurement` | รอสร้าง |
| PROC-06 | `ProcurementSettingsPage` | `scenario_erp_procurement_06_settings.yaml` | `erp, procurement` | รอสร้าง |

#### 3.4 ERP Sales & POS
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| SALE-01 | ดู `ProductListPage` | `scenario_erp_sales_01_products.yaml` | `erp, sales` | รอสร้าง |
| SALE-02 | ดู `CustomerListPage` | `scenario_erp_sales_02_customers.yaml` | `erp, sales` | รอสร้าง |
| SALE-03 | เพิ่มสินค้าลง `CartPage` | `scenario_erp_sales_03_cart.yaml` | `erp, sales` | รอสร้าง |
| SALE-04 | `CheckoutPage` สั่งซื้อ | `scenario_erp_sales_04_checkout.yaml` | `erp, sales` | รอสร้าง |
| SALE-05 | ดู `DeliveryOrdersPage` | `scenario_erp_sales_05_delivery.yaml` | `erp, sales` | รอสร้าง |
| SALE-06 | `CounterPosPage` | `scenario_erp_sales_06_counter_pos.yaml` | `erp, sales` | รอสร้าง |
| SALE-07 | `ClinicPosPage` | `scenario_erp_sales_07_clinic_pos.yaml` | `erp, sales` | รอสร้าง |
| SALE-08 | `OrderSuccessPage` หน้ายืนยัน | `scenario_erp_sales_08_order_success.yaml` | `erp, sales` | รอสร้าง |
| SALE-09 | `RefundListPage` | `scenario_erp_sales_09_refunds.yaml` | `erp, sales` | รอสร้าง |
| SALE-10 | `LoyaltyRulesPage` | `scenario_erp_sales_10_loyalty.yaml` | `erp, sales` | รอสร้าง |
| SALE-11 | การแจ้งเตือน `NotificationListPage` | `scenario_erp_sales_11_notifications.yaml` | `erp, sales` | รอสร้าง |

#### 3.5 ERP Finance & HR
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| FIN-01 | `GlEntriesPage` | `scenario_erp_finance_01_gl.yaml` | `erp, finance` | รอสร้าง |
| FIN-02 | `DashboardAnalyticsPage` | `scenario_erp_finance_02_analytics.yaml` | `erp, finance` | รอสร้าง |
| FIN-03 | `ChartOfAccountsPage` | `scenario_erp_finance_03_coa.yaml` | `erp, finance` | รอสร้าง |
| FIN-04 | `AccountsReceivablePage` | `scenario_erp_finance_04_ar.yaml` | `erp, finance` | รอสร้าง |
| FIN-05 | `AccountsPayablePage` | `scenario_erp_finance_05_ap.yaml` | `erp, finance` | รอสร้าง |
| FIN-06 | `SettlementPayoutPage` | `scenario_erp_finance_06_settlement.yaml` | `erp, finance` | รอสร้าง |
| FIN-07 | `PaymentChannelsPage` | `scenario_erp_finance_07_payment_channels.yaml` | `erp, finance` | รอสร้าง |
| FIN-08 | `VendorContractsPage` | `scenario_erp_finance_08_vendor_contracts.yaml` | `erp, finance` | รอสร้าง |
| FIN-09 | `ReportExportPage` | `scenario_erp_finance_09_report.yaml` | `erp, finance` | รอสร้าง |
| HR-01 | `EmployeeListPage` | `scenario_erp_hr_01_employees.yaml` | `erp, hr` | รอสร้าง |
| HR-02 | `PayrollPage` / `PayrollItemDetailPage` | `scenario_erp_hr_02_payroll.yaml` | `erp, hr` | รอสร้าง |
| HR-03 | `HrSettingsPage` | `scenario_erp_hr_03_settings.yaml` | `erp, hr` | รอสร้าง |
| HR-04 | `ShiftManagementPage` | `scenario_erp_hr_04_shifts.yaml` | `erp, hr` | รอสร้าง |
| HR-05 | `EmployeeRoleAssignmentPage` | `scenario_erp_hr_05_role_assignment.yaml` | `erp, hr` | รอสร้าง |
| HR-06 | `MyPermissionsPage` | `scenario_erp_hr_06_my_permissions.yaml` | `erp, hr` | รอสร้าง |
| HR-07 | `PermissionManagementPage` | `scenario_erp_hr_07_permission_mgmt.yaml` | `erp, hr` | รอสร้าง |
| HR-08 | `RoleManagementPage` | `scenario_erp_hr_08_role_mgmt.yaml` | `erp, hr` | รอสร้าง |
| HR-09 | `FeatureFlagsPage` | `scenario_erp_hr_09_feature_flags.yaml` | `erp, hr` | รอสร้าง |

#### 3.6 ERP Clinical
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| CLIN-01 | `EmrListPage` | `scenario_erp_clinical_01_emr.yaml` | `erp, clinical` | รอสร้าง |
| CLIN-02 | `OpdVisitPage` | `scenario_erp_clinical_02_opd.yaml` | `erp, clinical` | รอสร้าง |
| CLIN-03 | `PrescriptionPage` (ERP) | `scenario_erp_clinical_03_prescriptions.yaml` | `erp, clinical` | รอสร้าง |
| CLIN-04 | `LabResultsPage` | `scenario_erp_clinical_04_lab.yaml` | `erp, clinical` | รอสร้าง |
| CLIN-05 | `PatientCohortPage` | `scenario_erp_clinical_05_cohorts.yaml` | `erp, clinical` | รอสร้าง |

### Phase 4: Admin & Settings (สำคัญปานกลาง)

#### 4.1 Admin Pages
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| ADM-01 | `ProfessionAdminPage` (CRUD) | `scenario_admin_01_professions.yaml` | `admin` | รอสร้าง |
| ADM-02 | `ApplicationReviewPage` | `scenario_admin_02_applications.yaml` | `admin` | รอสร้าง |
| ADM-03 | `BodyRegionAdminPage` | `scenario_admin_03_body_regions.yaml` | `admin` | รอสร้าง |
| ADM-04 | `PackageAdminPage` | `scenario_admin_04_packages.yaml` | `admin` | รอสร้าง |
| ADM-05 | `UserCategoryAdminPage` | `scenario_admin_05_user_categories.yaml` | `admin` | รอสร้าง |
| ADM-06 | `PharmacyFiltersAdminPage` | `scenario_admin_06_pharmacy_filters.yaml` | `admin` | รอสร้าง |
| ADM-07 | `VideoAdminPage` | `scenario_admin_07_video.yaml` | `admin` | รอสร้าง |
| ADM-08 | `WatermarkManagementPage` | `scenario_admin_08_watermark.yaml` | `admin` | รอสร้าง |
| ADM-09 | `PlatformSettingsPage` | `scenario_admin_09_platform_settings.yaml` | `admin` | รอสร้าง |
| ADM-10 | `SystemMonitorPage` | `scenario_admin_10_system_monitor.yaml` | `admin` | รอสร้าง |
| ADM-11 | `RegistrationFieldAdminPage` | `scenario_admin_11_registration_fields.yaml` | `admin` | รอสร้าง |
| ADM-12 | `GroupMembersAdminPage` | `scenario_admin_12_group_members.yaml` | `admin` | รอสร้าง |

#### 4.2 KPI
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| KPI-01 | `KpiDashboardPage` | `scenario_admin_kpi_01_dashboard.yaml` | `kpi` | รอสร้าง |
| KPI-02 | `KpiTargetFormPage` | `scenario_admin_kpi_02_target_form.yaml` | `kpi` | รอสร้าง |
| KPI-03 | `KpiRefreshHistoryPage` | `scenario_admin_kpi_03_refresh_history.yaml` | `kpi` | รอสร้าง |

#### 4.3 Profile & Settings
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| PROF-01 | ดูข้อมูล `ProfilePage` | `scenario_profile_01_view.yaml` | `profile` | รอสร้าง |
| PROF-02 | แก้ไขโปรไฟล์/รูปภาพ | `scenario_profile_02_edit.yaml` | `profile` | รอสร้าง |
| PROF-03 | `SyncSettingsPage` | `scenario_profile_03_sync_settings.yaml` | `profile` | รอสร้าง |

#### 4.4 Community
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| COMM-01 | หน้า `CommunityPage` แสดง feed | `scenario_community_01_feed.yaml` | `community` | รอสร้าง |

### Phase 5: Security & Edge Cases (สำคัญต่ำ แต่จำเป็น)

#### 5.1 Security
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| SEC-01 | Input Validation: รหัสผ่านสั้นเกินไป/เบอร์โทรผิดรูปแบบ | `scenario_security_01_input_validation.yaml` | `security` | รอสร้าง |
| SEC-02 | Route guard: ไม่ login เข้า admin route → redirect | `scenario_security_02_route_guard.yaml` | `security` | รอสร้าง |
| SEC-03 | Role guard: consumer เข้า provider page → 403 | `scenario_security_03_role_guard.yaml` | `security` | รอสร้าง |
| SEC-04 | Password hashing: รหัสผ่านไม่ส่ง plaintext ไปเซิร์ฟเวอร์ | `scenario_security_04_password_hash.yaml` | `security` | รอสร้าง |
| SEC-05 | Session: token หมดอายุ แสดงหน้า login | `scenario_security_05_session_expiry.yaml` | `security` | รอสร้าง |

#### 5.2 Edge Cases
| Scenario | คำอธิบาย | ไฟล์ | Tags | สถานะ |
|----------|----------|------|------|--------|
| EDGE-01 | ไม่มี internet แสดง error/empty state | `scenario_edge_01_no_internet.yaml` | `edge` | รอสร้าง |
| EDGE-02 | Slow network timeout | `scenario_edge_02_slow_network.yaml` | `edge` | รอสร้าง |
| EDGE-03 | Empty state (ไม่มีข้อมูล) | `scenario_edge_03_empty_state.yaml` | `edge` | รอสร้าง |
| EDGE-04 | App background/foreground | `scenario_edge_04_background.yaml` | `edge` | รอสร้าง |

---

## 6. สถานะรวม

| Phase | ระบบ | จำนวน scenarios | สร้างแล้ว | ผ่าน | รอสร้าง |
|-------|------|-----------------|-----------|------|---------|
| 1 | Core (Auth, Guard, Home, Consultation, Chat) | 33 | 33 | 3 | 0 |
| 2 | Business (Drug Risk, Donation, Emergency, Health) | 29 | 14 | 14 | 15 |
| 3 | ERP (Dashboard, Inventory, Procurement, Sales, Finance, Clinical, HR) | 55 | 0 | 0 | 55 |
| 4 | Admin, KPI, Profile, Community | 19 | 0 | 0 | 19 |
| 5 | Security & Edge Cases | 9 | 0 | 0 | 9 |
| **รวม** | | **145** | **47** | **17** | **98** |

---

## 7. บัญชีทดสอบ (Test Accounts)

| บัญชี | รหัส | Role | Profession / สิทธิ์ | ใช้ทดสอบ |
|-------|------|------|---------------------|----------|
| `apisek` | (ใช้รหัสจริง) | `admin` | เป็น admin เต็มรูปแบบ | Admin, ERP ทุกส่วน, Drug Risk Global |
| `sister` | `123456` | `provider` | `profession_id = 00000000-...001`, `can_manage_drug_risk = false` | Consultation, Chat, แต่ **ไม่** Drug Risk Admin |
| `firm` | `123456` | `provider` | `can_manage_drug_risk = false` | Member flows, Prescription Editor |
| `independent` | `123456` | `consumer` | `profession_id = NULL` | Personal Override, Consumer flows |

---

## 8. Environment & Pre-requisites

- **App ID:** `com.example.treeLawZoo`
- **Primary device:** iPhone 16 Simulator (`A692F954-72BF-4D54-9557-FB61BCB5DBA6`, iOS 18.1)
- **Alternative device:** iPhone 14 Pro Max physical (`00008120-000058A41A40C01E`, iOS 26.5) — ต้อง unlock + trust ก่อนรัน release build
- **Backend:** Supabase live (`psxcgdwcwjdbpaemkozq.supabase.co`)
- **Pre-build:** รัน `flutter build ios --simulator --debug` และ `xcrun simctl install` ก่อนรัน Maestro
- **Tags:** ใช้ `tags: [smoke, regression, erp, admin, security]` ใน YAML เพื่อรันเลือกกลุ่ม

---

## 9. วิธีรันทดสอบ

```bash
# รัน scenario เดียว
maestro test docs/guides/scenario_XX_*.yaml --udid A692F954-72BF-4D54-9557-FB61BCB5DBA6

# รันทุก scenario ในโฟลเดอร์
maestro test docs/guides/ --udid A692F954-72BF-4D54-9557-FB61BCB5DBA6

# รันเฉพาะ regression ที่ผ่านแล้ว
maestro test docs/guides --include-tags=regression --udid A692F954-72BF-4D54-9557-FB61BCB5DBA6

# รันเฉพาะ smoke tests
maestro test docs/guides --include-tags=smoke --udid A692F954-72BF-4D54-9557-FB61BCB5DBA6

# รันเฉพาะ ERP
maestro test docs/guides --include-tags=erp --udid A692F954-72BF-4D54-9557-FB61BCB5DBA6
```

---

## 10. Checklist ก่อนรันแต่ละครั้ง

- [ ] App บน simulator เป็น build ล่าสุด
- [ ] Supabase backend พร้อมและมี test data ถูกต้อง
- [ ] บัญชีทดสอบยังใช้งานได้
- [ ] ตั้งค่า `clearState: true` ใน `launchApp` เมื่อต้องการเริ่มสะอาด
- [ ] ตรวจสอบว่า iOS tab labels มี suffix (ใช้ regex เช่น `"ประวัติการตั้งค่า.*"`)
- [ ] บันทึกผลการทดสอบกลับมาอัปเดตใน `TEST_PLAN.md`

---

## 11. หมายเหตุการแก้ไขล่าสุด (2026-07-24)

### ปัญหา: Login flow ส่งไปหน้า Donation Dashboard แทน Home Page
- **สาเหตุ:** แท็บบริจาค (point 174,809) ส่ง redirect args `{'route': '/main-app', 'args': {'index': 1}}` ทำให้หลัง login แสดง Donation Dashboard (index 1) แทน Home (index 0)
- **วิธีแก้:** สร้าง `_shared_login.yaml` ที่เพิ่มขั้นตอนแตะแท็บหน้าหลัก (point 50,809) หลัง login เพื่อสลับกลับไปหน้า Home
- **ไฟล์ที่แก้:** 40 scenario files ที่ใช้ login + `scenario_auth_03_login_fail.yaml` (แยกต่างหาก) + `scenario_debug_login.yaml`
- **ทดสอบผ่าน:** `scenario_debug_login`, `scenario_auth_01_login_username`, `scenario_cons_01_dashboard`
