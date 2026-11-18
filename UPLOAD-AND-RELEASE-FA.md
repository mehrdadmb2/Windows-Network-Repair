# راهنمای جایگزینی و انتشار نسخه 2.0.1

## ۱) جایگزینی فایل‌های مخزن

1. فایل ZIP این بسته را Extract کنید.
2. وارد پوشه `Windows-Network-Repair-Pro-v2.0.1` شوید.
3. تمام محتویات داخل آن، از جمله پوشه مخفی/نقطه‌ای `.github`، را در ریشه مخزن `mehrdadmb2/Windows-Network-Repair` کپی و فایل‌های قبلی را جایگزین کنید.
4. هنگام کپی، حذف فایل‌های قدیمی را هم تأیید کنید؛ نسخه جدید فایل ZIP قدیمیِ تودرتو و Log نمونه را نگه نمی‌دارد.

با Git از ریشه مخزن:

```bash
git add -A
git commit -m "Fix release pipeline and harden standalone EXE build"
git push origin main
```

## ۲) انتشار Release با اجرای دستی (پیشنهادی)

1. در GitHub مخزن را باز کنید و وارد تب **Actions** شوید.
2. Workflow با نام **Build Windows EXE and publish release** را انتخاب کنید.
3. روی **Run workflow** بزنید و Branch را روی `main` قرار دهید.
4. مقدار `release_tag` را `v2.0.1` بگذارید.
5. برای نسخه پایدار، گزینه `prerelease` را خاموش نگه دارید.
6. دوباره **Run workflow** را بزنید.

این Workflow در حالت اجرای دستی، Tag نسخه را در صورت نبودن ایجاد می‌کند، EXE و بسته سورس را می‌سازد، Release را ایجاد/به‌روزرسانی می‌کند و در آخر Assets منتشرشده را از API گیت‌هاب بررسی می‌کند. برای این روش لازم نیست دستور `git tag` را جداگانه اجرا کنید.

## ۳) فایل‌هایی که باید در Release دیده شوند

در صفحه Releases و زیر Assets نسخه `v2.0.1` باید دقیقاً این خروجی‌ها موجود باشند:

- `WindowsNetworkRepair.exe`
- `WindowsNetworkRepair-source.zip`
- `release-manifest.json`
- `SHA256SUMS.txt`

Artifact قابل دانلود در صفحه اجرای Actions نسخه پشتیبان ۳۰ روزه خروجی Build است و با Assets صفحه Releases تفاوت دارد.

## ۴) انتشار با Tag به‌جای اجرای دستی

روش جایگزین این است که پس از Push سورس، Tag جدید بسازید و Push کنید:

```bash
git tag v2.0.1
git push origin v2.0.1
```

از یکی از دو روش استفاده کنید: اجرای دستی Workflow یا Push کردن Tag. هر دو همزمان لازم نیستند.

اگر Tag از قبل به Commit دیگری اشاره کند، Workflow برای جلوگیری از انتشار باینری اشتباه متوقف می‌شود. برای Commit جدید، شماره نسخه جدید مثل `v2.0.2` انتخاب کنید؛ Tag منتشرشده را برای جا زدن Build جدید جابه‌جا نکنید.

## ۵) مجوزهای GitHub Actions

فایل Workflow مجوز `contents: write` را در سطح Job انتشار درخواست می‌کند. اگر مرحله Release با خطای `Resource not accessible by integration` یا `write permission` متوقف شد، به مسیر زیر بروید:

`Settings → Actions → General → Workflow permissions`

در صورت محدود نبودن سیاست سازمانی، گزینه **Read and write permissions** را فعال کنید. برای مخزن عمومی شخصی، `GITHUB_TOKEN` خود Workflow کافی است و نیازی به افزودن PAT یا Secret جداگانه نیست.

## ۶) نتیجه موفقیت

موفقیت Build به‌تنهایی کافی نیست. آخرین مرحله با نام **Verify that GitHub Release actually contains every asset** باید سبز شود و چهار فایل بالا را از GitHub API پیدا کند. اگر Release ناقص باشد، خود Workflow به‌صورت Failed پایان می‌یابد تا مشکل پنهان نماند.

## ۷) ساخت محلی در ویندوز

در Windows PowerShell 5.1 از ریشه پروژه اجرا کنید:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\Build\Build-Executable.ps1 -OutputPath .\dist -Version '2.0.1.0'
.\Build\Prepare-Release.ps1 -SourceRoot . -OutputPath .\dist -Version '2.0.1' -Tag 'v2.0.1' -CommitSha 'local-build'
```

خروجی EXE باید فایل `dist\WindowsNetworkRepair.exe` به‌تنهایی باشد؛ فایل `WindowsNetworkRepair.exe.config` نباید در کنار آن تولید شود.
