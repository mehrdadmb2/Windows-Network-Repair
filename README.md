# Windows Network Repair Pro 2.0

ابزار تشخیص، اصلاح و مانیتورینگ تنظیمات سازگاری SMB در ویندوز؛ با پشتیبان‌گیری قبل از تغییر، راستی‌آزمایی بعد از تغییر و داشبورد GitHub Pages برای مشاهده گزارش واقعی سیستم.

> **هشدار امنیتی:** این پروژه برای سناریوهای محدودِ سازگاری با NAS یا دستگاه‌های قدیمی طراحی شده است. فعال‌کردن ورود Guest بدون احراز هویت و کاهش SMB signing می‌تواند امنیت ارتباط و داده‌ها را کاهش دهد. فقط در شبکه مورد اعتماد و زمانی اجرا کنید که واقعاً لازم است. مستندات Microsoft: [SMB insecure guest logons](https://learn.microsoft.com/en-us/windows-server/storage/file-server/enable-insecure-guest-logons-smb2-and-smb3) و [SMB signing](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-signing-overview).

## مهم‌ترین تغییر نسخه 2.0

**گزینهٔ ۳، مسیر اصلی برنامه است.** با فشردن Enter در منوی اصلی نیز همین گزینه انتخاب می‌شود. این مسیر:

1. وضعیت واقعی سیستم را قبل از تغییر Snapshot می‌کند.
2. از کلیدهای رجیستری و وضعیت Binding کارت‌های شبکه نسخهٔ پشتیبان می‌گیرد.
3. قبل از هر تغییری، Policyهای مسدودکننده را بررسی می‌کند؛ اگر Guest صریحاً مسدود یا SMB signing اجباری شده باشد، کل عملیات بدون تغییر متوقف می‌شود.
4. ابتدا الزام SMB signing را غیرفعال می‌کند تا امکان استفاده از Guest در سناریوهای سازگار فراهم شود.
5. ورود SMB Guest را فعال می‌کند؛ اما Policy را دور نمی‌زند. اگر یکی از دو پیش‌نیاز اصلی تأیید نشود، مراحل بعدی به‌صورت Fail-fast متوقف می‌شوند.
6. Binding مربوط به Client for Microsoft Networks را از طریق APIهای رسمی ویندوز غیرفعال می‌کند؛ از حذف اجباری Component یا netcfg استفاده نمی‌کند.
7. هر مرحله را جداگانه بررسی و نتیجهٔ واقعی را ثبت می‌کند. پس از اجرا، هر دو ثانیه وضعیت را نمونه‌برداری می‌کند و گزارش Before / After، رویدادها و Monitor Samples می‌سازد.

توجه: گزینهٔ ۳ عمداً یک مرحلهٔ تأیید دوم دارد؛ باید عبارت `APPLY` را تایپ کنید. غیرفعال‌کردن Client for Microsoft Networks ممکن است دسترسی همان کارت شبکه به Shareهای ویندوز را مختل کند.

## قابلیت‌ها

- تشخیص Windows، Build، معماری، CPU، RAM، BIOS و نسخه PowerShell
- تشخیص کارت‌های شبکه، IP، Gateway، DNS، پاسخ ICMP از Gateway و آزمایش Resolve دامنه `example.com` با DNS تنظیم‌شده
- بررسی وضعیت SMB Guest، SMB client signing و Client for Microsoft Networks Binding
- بررسی سرویس‌های Workstation / Server / Discovery و گروه‌های Firewall در صورت پشتیبانی سیستم
- Snapshot و مقایسهٔ واقعی قبل و بعد از تغییر
- مانیتورینگ دوره‌ای با Sampleهای زمان‌دار (گزینهٔ ۱۰)
- Backup و Restore برای کلیدهای رجیستری، وجود/نوع/مقدار دقیق Valueهای تغییر داده‌شده و Bindingهای ذخیره‌شده؛ همچنین بازیابی Snapshotهای قدیمی نسخهٔ 1
- گزارش JSON و TXT
- داشبورد واکنش‌گرای GitHub Pages با Import گزارش، مقایسه، Timeline و جزئیات سیستم
- فایل Build برای ترکیب ماژول‌ها و ساخت یک EXE بدون نیاز به پوشهٔ Modules در کنار فایل اجرایی
- انتشار خودکار EXE در GitHub Releases هنگام Push کردن Tag نسخه

## ساختار پروژه

```text
.
├── NetworkRepair.ps1
├── NetworkRepair.cmd
├── Restore.ps1
├── Restore.cmd
├── Modules/
│   ├── Console.psm1
│   ├── System.psm1
│   ├── Logging.psm1
│   ├── Backup.psm1
│   ├── ThreeFixes.psm1
│   └── Diagnostics.psm1
├── Build/
│   └── Build-Executable.ps1
├── assets/
│   └── WindowsNetworkRepair.ico
├── docs/
│   ├── index.html
│   └── assets/
│       ├── app.js
│       ├── config.js
│       ├── styles.css
│       └── logo.svg
└── .github/workflows/
    ├── build-release.yml
    └── pages.yml
```

## اجرای برنامه در ویندوز

### اجرای سورس

1. ZIP را Extract کنید.
2. روی `NetworkRepair.cmd` راست‌کلیک کنید و **Run as administrator** را بزنید.
3. در منو Enter را بزنید تا گزینهٔ ۳ باز شود، یا شمارهٔ ۳ را انتخاب کنید.
4. هشدارهای امنیتی و وضعیت فعلی را بررسی کنید.
5. فقط در صورت اطمینان `APPLY` را وارد کنید.

برای بازگردانی تنظیمات، `Restore.cmd` را با دسترسی Administrator اجرا کنید.

### محل ذخیره داده‌ها

به‌صورت پیش‌فرض گزارش‌ها، لاگ‌ها و Backupها در مسیر زیر ذخیره می‌شوند:

```text
%ProgramData%\WindowsNetworkRepairPro\
├── Backup\
├── Logs\
└── Reports\
```

این مسیر مستقل از محل قرارگیری سورس یا EXE است؛ در نتیجه اگر EXE را از پوشهٔ Downloads اجرا کنید، داده‌ها در پوشهٔ برنامه ذخیره نمی‌شوند. اگر دسترسی نوشتن به `%ProgramData%` ممکن نباشد، برنامه به مسیر `Data` کنار سورس/EXE برمی‌گردد.

## مانیتورینگ و داشبورد وب

### چه چیزی واقعاً مانیتور می‌شود؟

مانیتورینگ واقعی رجیستری، Binding، سرویس‌ها، کارت‌های شبکه، Firewall، پاسخ ICMP از Gateway و Resolve شدن `example.com` با DNS تنظیم‌شده توسط خود برنامهٔ PowerShell در ویندوز انجام می‌شود. پاسخ ندادن به Ping الزاماً به معنی قطع بودن Gateway نیست؛ ممکن است ICMP در روتر یا Firewall مسدود شده باشد. داشبورد GitHub Pages فایل گزارش JSON ایجادشده توسط برنامه را در مرورگر می‌خواند و آن را نمایش می‌دهد.

**GitHub Pages به‌تنهایی نمی‌تواند رجیستری یا سرویس‌های ویندوز کاربر را بخواند.** بنابراین داشبورد هیچ وضعیت ساختگی یا Live جعلی نشان نمی‌دهد. تا وقتی گزارش جدید وارد نشود، آخرین Snapshot واردشده را نمایش می‌دهد. اطلاعات محدود مرورگر نیز جدا از مشخصات واقعی سیستم برچسب‌گذاری شده است.

### انتشار GitHub Pages

1. کل محتوای پروژه را در Repository قرار دهید و به شاخهٔ `main` یا `master` Push کنید.
2. در GitHub به `Settings → Pages` بروید.
3. در قسمت **Build and deployment → Source** گزینهٔ **GitHub Actions** را انتخاب کنید.
4. Workflow با نام `Deploy project dashboard to GitHub Pages` اجرا می‌شود.
5. آدرس صفحه معمولاً به شکل زیر است:

```text
https://OWNER.github.io/REPOSITORY/
```

در حالت GitHub Pages استاندارد، مالک و نام Repository از URL تشخیص داده می‌شود. برای دامنهٔ اختصاصی یا ساختاری غیرمعمول، فایل `docs/assets/config.js` را ویرایش کنید:

```javascript
window.WNR_CONFIG = {
  owner: 'YOUR_GITHUB_USERNAME',
  repo: 'YOUR_REPOSITORY_NAME',
  releaseUrl: ''
};
```

### استفاده از داشبورد

1. برنامه را در ویندوز اجرا کنید و گزینهٔ ۳ یا ۱۰ را انجام دهید.
2. فایل `ApplyReport_*.json` یا `MonitorReport_*.json` را از مسیر `Reports` پیدا کنید.
3. در GitHub Pages روی **Import monitoring report** بزنید و JSON را انتخاب کنید؛ امکان Drag & Drop و واردکردن چند گزارش نیز وجود دارد.
4. از بخش Before / After، وضعیت تنظیمات، تغییرات، نمونه‌های مانیتورینگ، سیستم، کارت‌ها و سرویس‌ها را بررسی کنید.

فایل گزارش در مرورگر خوانده می‌شود و به سرور پروژه ارسال نمی‌شود. پاک‌کردن صفحه، دادهٔ بارگذاری‌شده را از حافظهٔ همان صفحه حذف می‌کند.

## ساخت یک فایل EXE مستقل از پوشه Modules

پروژه شامل Build Script است که سورس ماژول‌ها را در یک فایل موقت ادغام می‌کند و سپس PS2EXE را اجرا می‌کند؛ در نتیجه در کنار فایل خروجی به پوشهٔ `Modules` نیاز نیست.

### روش اول: ساخت خودکار از GitHub Actions (پیشنهادی)

1. سورس را Push کنید.
2. یک Tag نسخه بسازید و Push کنید:

```bash
git tag v2.0.0
git push origin v2.0.0
```

3. در GitHub به `Actions` بروید و Workflow با نام **Build Windows EXE and publish release** را بررسی کنید.
4. بعد از موفقیت Workflow، در بخش `Releases` دو فایل خواهید داشت:
   - `WindowsNetworkRepair.exe`
   - `WindowsNetworkRepair-source.zip`

همچنین اجرای دستی Workflow از تب Actions امکان Build و دریافت Artifact را می‌دهد؛ اما Release عمومی فقط هنگام Push شدن Tag ساخته می‌شود.

### روش دوم: ساخت روی ویندوز خودتان

Windows PowerShell 5.1 را باز کنید، وارد پوشهٔ پروژه شوید و اجرا کنید. برای Build کردن به دسترسی Administrator نیاز نیست؛ اتصال اینترنت برای دریافت PS2EXE از PowerShell Gallery لازم است:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\Build\Build-Executable.ps1 -OutputPath .\dist -Version '2.0.0.0'
```

فایل خروجی:

```text
dist\WindowsNetworkRepair.exe
```

فایل EXE با آیکون اختصاصی پروژه و اطلاعات نسخه ساخته می‌شود. این Build به‌صورت پیش‌فرض `AnyCPU` است و از PS2EXE استفاده می‌کند؛ نسخهٔ PS2EXE روی `1.0.18` ثابت شده تا خروجی Build بین اجراها قابل‌تکرارتر باشد؛ این نسخه اسکریپت‌های سازگار با PowerShell 5.x را به باینری‌های .NET 4.x تبدیل می‌کند. برای جزئیات گزینه‌های Compile به [مخزن رسمی PS2EXE](https://github.com/MScholtes/PS2EXE) مراجعه کنید. Workflow پیش از Build، Syntax تمام فایل‌های PowerShell و JavaScript داشبورد را نیز بررسی می‌کند.

### آیا EXE واقعاً هیچ پیش‌نیازی ندارد؟

EXE تمام اسکریپت و ماژول‌های همین پروژه را در خودش دارد و فایل ماژول جداگانه نمی‌خواهد؛ اما **به معنی همراه‌داشتن نسخهٔ کامل Windows PowerShell و .NET درون EXE نیست**. برای اجرای سورس، Windows PowerShell 3.0 یا جدیدتر لازم است. Build فایل EXE با Windows PowerShell 5.1 انجام می‌شود و EXE نیز به اجزای سیستمی .NET Framework 4.x متکی است؛ این اجزا داخل فایل EXE کپی نمی‌شوند. Windows 10/11 معمولاً PowerShell 5.1 و .NET Framework لازم را دارند. Windows 7 SP1 برای PowerShell 5.1 به WMF 5.1 و .NET Framework 4.5.2 یا بالاتر نیاز دارد. Windows 8 معمولاً PowerShell 3 و Windows 8.1 معمولاً PowerShell 4 دارد؛ در این سیستم‌ها نسخهٔ سورس قابل استفاده است، اما ممکن است برخی APIها در دسترس نباشند. اجرای EXE روی هر نسخهٔ قدیمی را قبل از انتشار نهایی روی همان نسخه آزمایش کنید. لینک رسمی: [WMF 5.1 برای Windows 7 و Server 2008 R2](https://support.microsoft.com/en-us/topic/update-for-windows-management-framework-5-1-for-windows-7-and-windows-server-2008-r2-918077a1-ebc1-289f-bc04-8cc4546eafd0).

کد PowerShell داخل EXE رمزگذاری‌شده نیست و PS2EXE امکان استخراج اسکریپت را دارد؛ بنابراین هیچ رمز، Token یا Secret را داخل سورس یا فایل اجرایی قرار ندهید. فایل EXE امضای دیجیتال Code Signing ندارد؛ در نتیجه ممکن است Windows SmartScreen یا آنتی‌ویروس دربارهٔ فایل ناشناس هشدار دهد. برای انتشار عمومی بهتر است بعداً فایل با گواهی Code Signing معتبر امضا شود.

## سازگاری و محدودیت‌ها

- هدف سورس: Windows PowerShell 3.0 به بالا روی Windows 7 SP1 / 8 / 8.1 / 10 / 11؛ بعضی APIهای شبکه و SMB فقط روی نسخه‌های جدیدتر در دسترس‌اند و در سیستم‌های قدیمی به‌صورت Skip گزارش می‌شوند. Build فایل EXE با Windows PowerShell 5.1 انجام می‌شود.
- نبود API برای Adapter Binding به معنی **Skip** است؛ ابزار هیچ Componentای را با روش‌های جایگزین پرخطر حذف نمی‌کند.
- نام گروه‌های Firewall در بعضی ویندوزهای Localized ممکن است متفاوت باشد.
- قابلیت SMB1 فقط در صورت وجود Windows Optional Feature و با هشدار مجزا فعال می‌شود.
- Reset کردن Winsock یا TCP/IP ممکن است تنظیمات شبکه را تحت تأثیر قرار دهد و به Restart نیاز داشته باشد.
- این پروژه جایگزین عیب‌یابی NAS، احراز هویت، مجوز Share یا تنظیمات Firewall سمت سرور نیست.

## حریم خصوصی

گزارش‌ها ممکن است شامل نام کامپیوتر، مدل سخت‌افزار، آدرس IP داخلی، نام رابط شبکه و وضعیت سرویس‌ها باشند. قبل از انتشار عمومی گزارش JSON، اطلاعات حساس محیط خود را بررسی و در صورت نیاز حذف کنید. داشبورد به‌صورت پیش‌فرض گزارش‌ها را آپلود یا ذخیرهٔ دائمی نمی‌کند.

## نسخه

`2.0.0` — 2026-11-17
