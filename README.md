# مُلخِّص — تطبيق تلخيص المحاضرات والملفات

مشروع من جزأين: `backend/` (خادم FastAPI) و`app/` (تطبيق Flutter لأندرويد وآيفون).

## ما يعمل
- **المصادر:** ملف (PDF/DOCX/TXT)، تسجيل صوتي أو ملف صوتي، صور (كاميرا/معرض)، أو نص ملصوق.
- **النتيجة:** ملخص + نقاط رئيسية + مصطلحات (عربي/إنجليزي)، ومع الصوت والصور يظهر «النص الأصلي» للمراجعة.
- المحاضرات الطويلة تُقسَّم وتُدمج تلقائياً.
- **الحسابات:** تسجيل ودخول بالبريد (كلمات المرور مشفّرة بـ scrypt، والرمز JWT يُحفظ في التخزين الآمن للجهاز).
- **الحدود:** مجاني 5 ملخصات شهرياً، Pro 300 (قابلة للتعديل من `.env`). لا يُحتسب الملخص إلا عند نجاحه.
- **الاشتراكات:** RevenueCat + Webhook يرقّي الحساب تلقائياً.
- مكتبة محلية (حفظ/فتح/حذف مع تراجع)، نسخ الملخص، واجهة عربية RTL مع وضع ليلي.

## لم يُبنَ بعد
بطاقات المراجعة والاختبارات، «اسأل ملفك»، مزامنة المكتبة سحابياً (المكتبة الآن على الجهاز فقط)، تسجيل الدخول بـ Google/Apple، استعادة كلمة المرور، تحديد معدّل الطلبات (rate limiting).

## 1) تشغيل الخادم
```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env     # املأ المفاتيح (انظر الجدول)
set -a; source .env; set +a
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```
للتجربة بلا مفاتيح: `MOCK_AI=1 ALLOW_DEV_SECRET=1 uvicorn main:app --reload` (ناتج تجريبي).

| المتغير | الاستخدام |
|---|---|
| `ANTHROPIC_API_KEY` | التلخيص وقراءة الصور |
| `OPENAI_API_KEY` | تحويل الصوت إلى نص (Whisper API) |
| `JWT_SECRET` | سر طويل عشوائي للحسابات (إلزامي في الإنتاج) |
| `REVENUECAT_WEBHOOK_AUTH` | نص سري تضعه أيضاً في إعدادات Webhook بـ RevenueCat |
| `FREE_MONTHLY_LIMIT` / `PRO_MONTHLY_LIMIT` | حدود الاستخدام |

الاختبارات (30 اختباراً): `pip install pytest httpx reportlab && python -m pytest -q`

## 2) تشغيل التطبيق
المجلد `app/` يحوي كود Dart فقط. ولّد مجلدات المنصات مرة واحدة:
```bash
cd app
flutter create . --org com.yourname --project-name mulakhis
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```
عناوين الخادم: محاكي أندرويد `http://10.0.2.2:8000`، محاكي آيفون `http://127.0.0.1:8000`، جهاز حقيقي: عنوان IP لجهازك.

### أذونات المنصات (مهمة بعد `flutter create`)
**أندرويد** — `android/app/src/main/AndroidManifest.xml` داخل `<manifest>`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.CAMERA"/>
```
وللتطوير عبر HTTP أضف على وسم `<application>`: `android:usesCleartextTraffic="true"` (احذفه في الإنتاج). ورفع `minSdkVersion` إلى 23 في `android/app/build.gradle` (مطلوب لـ record وRevenueCat).

**آيفون** — `ios/Runner/Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key><string>لتسجيل المحاضرات وتلخيصها</string>
<key>NSCameraUsageDescription</key><string>لتصوير صفحات الكتاب والسبورة</string>
<key>NSPhotoLibraryUsageDescription</key><string>لاختيار صور المحاضرات</string>
```
وفعّل قدرة In-App Purchase في Xcode (Signing & Capabilities).

### تفعيل الاشتراكات (RevenueCat)
1. أنشئ مشروعاً في RevenueCat، وأضف تطبيقيك (أندرويد وآيفون) ومنتجات الاشتراك في المتجرين، وضعها في Offering افتراضي.
2. في Integrations ← Webhooks: الرابط `https://رابط-خادمك/webhooks/revenuecat` ورأس Authorization بقيمة `REVENUECAT_WEBHOOK_AUTH`.
3. شغّل التطبيق بالمفاتيح العامة: `--dart-define=REVENUECAT_ANDROID_KEY=... --dart-define=REVENUECAT_IOS_KEY=...`

التطبيق يضبط معرّف المستخدم في RevenueCat ليساوي معرّفه في خادمك، وبذلك يعرف الخادم من اشترى.

## قبل النشر
- استضف الخادم على **HTTPS** مع قاعدة بيانات دائمة (قرص ثابت أو PostgreSQL)، واضبط `CORS_ORIGINS` بدل `*`.
- أضف تحديد معدّل الطلبات عند البوابة (مثلاً Cloudflare) لحماية `/auth/*` من التخمين.
- سياسة الخصوصية وشروط الاستخدام، وزر حذف الحساب (يشترطه المتجران) — لم يُبنَ بعد.
- اضبط حدّ إنفاق على حساب Anthropic وOpenAI، وراقب تكلفة المحاضرة الواحدة قبل تثبيت الأسعار.
