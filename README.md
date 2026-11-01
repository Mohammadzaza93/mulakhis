# مُلخِّص — تطبيق تلخيص المحاضرات والملفات

مشروع من جزأين: `backend/` (خادم FastAPI) و`app/` (تطبيق Flutter لأندرويد وآيفون).

## ما يعمل في هذه النسخة
- رفع PDF أو DOCX أو TXT، أو لصق نص → ملخص + نقاط رئيسية + مصطلحات (عربي/إنجليزي).
- تقسيم المحاضرات الطويلة تلقائياً ثم دمج النتائج.
- مكتبة محلية على الجهاز (حفظ، فتح، حذف مع تراجع)، ونسخ الملخص.
- واجهة عربية RTL مع وضع ليلي.

## ما لم يُبنَ بعد (حسب الخطة)
تسجيل الصوت وتحويله إلى نص، OCR للصور، حسابات المستخدمين، الاشتراكات (RevenueCat)، المزامنة السحابية.

## تشغيل الخادم
```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env        # ضع ANTHROPIC_API_KEY
export $(grep -v '^#' .env | xargs)
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```
بدون مفتاح، للتجربة فقط: `MOCK_AI=1 uvicorn main:app --reload`

الاختبارات: `pip install pytest httpx reportlab && python -m pytest -q`

## تشغيل التطبيق
المجلد `app/` يحوي كود Dart فقط. ولّد مجلدات المنصات مرة واحدة:
```bash
cd app
flutter create . --org com.yourname --project-name mulakhis
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```
- محاكي أندرويد: `http://10.0.2.2:8000` — محاكي آيفون: `http://127.0.0.1:8000` — جهاز حقيقي: عنوان IP لجهازك على الشبكة.
- للتطوير عبر HTTP على أندرويد أضف في `android/app/src/main/AndroidManifest.xml` على وسم `<application>`: `android:usesCleartextTraffic="true"` (احذفه في الإنتاج واستخدم HTTPS).
- أندرويد يحتاج إذن الإنترنت: `<uses-permission android:name="android.permission.INTERNET"/>` (يضيفه `flutter create` في نسخة debug فقط؛ تأكد منه في نسخة release).
- إن فعّلت `APP_API_KEY` في الخادم مرّره: `--dart-define=APP_API_KEY=...`

## قبل النشر
استضف الخادم على HTTPS، لا تضع مفاتيح الذكاء الاصطناعي في التطبيق أبداً، أضف حسابات وحدوداً للاستخدام لضبط التكلفة، وجهّز سياسة الخصوصية.
