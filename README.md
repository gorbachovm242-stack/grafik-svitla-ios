# Графік світла для iPhone: нативний застосунок

Застосунок на Swift/SwiftUI з віджетами WidgetKit. Це той самий «Графік світла», що й скрипт для Scripting
(`scripting/scripts/Графік світла/`), але тепер це окремий застосунок для App Store і TestFlight.
Mac не потрібен: збирає й підписує машина macOS на GitHub Actions.

## Що всередині

| Тека | Що там |
|---|---|
| `SvitloCore/` | Ядро без iOS: графік (сайт ЗОЕ та спільні дані), датчики СвітлоБота, тривоги, сховище й мережа, рішення про сповіщення, таймлайн віджета, палітра B. Пакет Swift із тестами XCTest |
| `Shared/` | Спільне для застосунку й віджета: вигляди (будинок, плитки, гірлянда, батарея, кільце), усі розкладки віджета, кнопки App Intents, сповіщення |
| `App/` | Застосунок: вкладки «Світло», «Тривога», «Віджет», значок |
| `Widget/` | Розширення WidgetKit: малий, середній, великий віджет і три віджети для екрана блокування |
| `AppTests/` | Тест на симуляторі: малює всі віджети в PNG (артефакт `widget-previews`) |
| `project.yml` | Опис проєкту Xcode для XcodeGen (`.xcodeproj` створюється на CI) |
| `.github/workflows/ios.yml` | Збирання, тести, TestFlight |
| `tools/test-core.ps1` | Тести ядра на цьому ПК (Swift для Windows) |
| `tools/AppIcon.java` | Малює значок 1024×1024 |

Відмінності від скрипта:
- Кожна зміна графіка й кожна година — окремий запис таймлайну. Тож о 23:30 віджет сам переходить на «Без світла», не чекаючи, поки iOS його оновить (у Scripting такого не було).
- Адресу (першу чи другу) обирають у налаштуваннях віджета: утримати віджет → «Редагувати віджет» → «Адреса».
- «Напівпрозорого» фону немає: у звичайному віджеті iOS шпалер не показує. У прозорому й тонованому режимах робочого екрана iOS фарбує віджет сама.

## Як перевіряється

- **Логіка на ПК** (Windows, Swift 6.4 у `D:\DevTools\Swift`):
  ```powershell
  & "ios\tools\test-core.ps1"
  ```
  Скрипт копіює пакет у теку з латиницею (шлях проєкту кириличний) і запускає `swift test` у середовищі MSVC.
- **Застосунок і віджети** збирає лише Xcode, тобто GitHub Actions. На Windows перевіряється тільки синтаксис.
  Workflow `iOS` після кожного push у `main`:
  1. запускає тести ядра;
  2. збирає застосунок із віджетом;
  3. проганяє тест на симуляторі iPhone;
  4. викладає картинки всіх віджетів (артефакт `widget-previews` на сторінці запуску).

## Що потрібно зробити вам

Акаунти, оплату, ключі й секрети робите ви. Ключ `.p8` нікому не пересилайте, у тому числі в чат.

### 1. Apple Developer Program, $99 на рік

1. Відкрийте [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll/) і увійдіть своїм Apple ID. Потрібна двофакторна автентифікація.
2. Оберіть «Individual» (фізична особа) і оплатіть. Погодження зазвичай займає від кількох годин до двох днів.
3. Team ID потім видно в [developer.apple.com/account](https://developer.apple.com/account) → Membership details: 10 символів, наприклад `AB12CD34EF`.

### 2. Bundle ID і App Group

У [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) → Identifiers → «+»:

1. **App Groups**: `group.ua.maiak.grafik`.
2. **App IDs → App**: Bundle ID `ua.maiak.grafik` (Explicit). У Capabilities увімкніть:
   - **App Groups** (кнопка Configure → оберіть групу з кроку 1);
   - **Time Sensitive Notifications**.
3. **App IDs → App**: `ua.maiak.grafik.widgets` (віджет), Capabilities → **App Groups** → та сама група.

Хочете інші назви? Змініть `APP_BUNDLE_ID` і `APP_GROUP_ID` у `project.yml`: віджет отримає `APP_BUNDLE_ID.widgets` сам.
Після першого завантаження в App Store Connect Bundle ID змінити вже не можна.

### 3. Запис застосунку в App Store Connect

[appstoreconnect.apple.com](https://appstoreconnect.apple.com) → Apps → «+» → New App:

| Поле | Значення |
|---|---|
| Платформа | iOS |
| Назва | Графік світла (у App Store назва має бути унікальна; якщо зайнята, допишіть щось) |
| Основна мова | Ukrainian |
| Bundle ID | `ua.maiak.grafik` |
| SKU | будь-який, наприклад `grafik-svitla-ios` |

### 4. Ключ App Store Connect API і секрети GitHub

1. App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → «+».
2. Назва `GitHub Actions`, роль **Admin**: хмарний сертифікат підпису інакше не створюється.
3. Завантажте `.p8`. Apple дає завантажити його **лише один раз**, тож збережіть файл.
4. Запишіть **Key ID** (біля ключа) та **Issuer ID** (над таблицею).
5. У репозиторії GitHub → Settings → Secrets and variables → Actions → New repository secret:

| Секрет | Що вставити |
|---|---|
| `ASC_KEY_ID` | Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8` | увесь текст файлу `.p8`, разом із рядками `-----BEGIN PRIVATE KEY-----` і `-----END PRIVATE KEY-----` |
| `APPLE_TEAM_ID` | Team ID з кроку 1 |

### 5. Репозиторій на GitHub

Уже є: публічний [grafik-svitla-ios](https://github.com/gorbachovm242-stack/grafik-svitla-ios) (хвилини macOS
у публічному репозиторії безкоштовні). Його корінь — вміст теки `ios/`; це не той `grafik-svitla`, з якого
друзі ставлять скрипт. Публікація, як і для скрипта, з копії `github-ios/` (свій `.git`, автор — noreply-адреса):
```powershell
python tools/publish_ios.py "Що змінилося"
```
Секрети з кроку 4 додаються в цьому репозиторії: Settings → Secrets and variables → Actions.

### 6. Збірка й TestFlight

1. Кожен push запускає Actions → **iOS** (близько 7 хвилин). Картинки всіх віджетів і журнал збирання —
   в артефакті `widget-previews` унизу сторінки запуску.
2. Для TestFlight: Actions → iOS → Run workflow → позначте **testflight** → Run. Збірка підпишеться й піде в App Store Connect. Номер збірки — номер запуску workflow, версія — `MARKETING_VERSION` у `project.yml`.
3. Через 5–30 хвилин збірка з'явиться в App Store Connect → TestFlight. Питання про шифрування не буде: у застосунку вже вказано «лише HTTPS» (`ITSAppUsesNonExemptEncryption = false`).
4. **Ви самі**: TestFlight → Internal Testing → «+» → додайте себе. На iPhone поставте застосунок **TestFlight** з App Store і прийміть запрошення.
5. **Друзі**: External Testing → нова група → додайте збірку → Apple проводить коротку бета-перевірку (зазвичай до доби). Потім вмикається публічне посилання-запрошення.

### Без $99: поставити собі самому (сайдлоад)

Хто має Mac (або сам збере на GitHub Actions), може поставити застосунок без акаунта розробника й App Store,
підписавши його своїм безкоштовним Apple ID: Xcode напряму, або готовий `.ipa` через AltStore, SideStore чи Sideloadly.
- У `project.yml` поставити свої `APP_BUNDLE_ID` і `APP_GROUP_ID` (ці ідентифікатори унікальні на весь світ).
- Якщо безкоштовний акаунт не дає підписати з «Time Sensitive Notifications», прибрати рядок
  `com.apple.developer.usernotifications.time-sensitive` у `project.yml`: попередження прийдуть звичайними.
- Такий застосунок працює 7 днів, потім його треба підписати знову (AltStore і SideStore роблять це самі);
  одночасно можна мати до 3 таких застосунків.
- Якщо віджет пише «Оберіть чергу», хоча в застосунку її обрано, інструмент перейменував спільну групу
  застосунку й віджета (App Group): про це варто написати в Issues.

### 7. Перед App Store (пізніше)

- **Політика конфіденційності**: посилання обовʼязкове. Є `PRIVACY.md` у `grafik-svitla`; додати туди абзац про iPhone-застосунок.
- **Анкета App Privacy**: «Data Not Collected». Місце для тривог не надсилається, телефон сам обирає свої тривоги.
- **Скриншоти** iPhone 6,9 дюйма: зі скриншотів із TestFlight на телефоні, а віджети — з картинок `widget-previews`.

## Що вже перенесено, а що ні

Перенесено:
- уся логіка `logic.ts`, `alerts.ts`, `store.ts`, `notifications.ts` (у ядрі, з тестами);
- три вкладки застосунку;
- віджети: малий, середній, великий, екран блокування (прямокутний, круглий, рядок);
- пʼять виглядів і лампочка, палітра B, стовпчик значків тривоги;
- кнопки «↻» і перемикання сторінок (App Intents);
- друга адреса, датчик СвітлоБота, канал моніторингу Telegram;
- три локальні сповіщення;
- фонове оновлення застосунку (BGAppRefreshTask): «графік змінився» приходить і без віджета на екрані, коли iOS дасть застосунку час (зазвичай кілька разів на день);
- **Live Activity тривоги** на екрані блокування й у Dynamic Island: таймер від початку тривоги, місце, що летить, «↻».
  Обмеження iOS: без push-сервера вона починається лише тоді, коли застосунок відкрито під час тривоги;
  оновлюється, коли застосунок відкривають, торкаються «↻» на ній або iOS дає фонове оновлення, а після відбою
  зникає з наступним оновленням. Коли дані старші за 30 хвилин, вона пише, що дані можуть бути застарілі.
  Вимикач — на вкладці «Тривога».

Ще ні:
- автостарт Live Activity, щойно оголосили тривогу: потрібні push-сповіщення ActivityKit від посередника
  (ключ APNs з акаунта Apple Developer і зміни у `worker/maiak-alerts.mjs`);
- справжня перевірка на iPhone.
