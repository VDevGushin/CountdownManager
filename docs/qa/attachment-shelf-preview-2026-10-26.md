# Полка вложений, компактные детали и быстрый просмотр

Дата: 26 октября 2026. Статус: реализация и выбранная продуктовая приёмка завершены в рабочей
ветке `codex/attachment-shelf-preview`. Новый релиз не публиковался.

## Согласованный объём

**A:** первые четыре файла в полке 2×2 desktop; первые три в раскрытой мини-панели.
Один файл остаётся в первой колонке, пустой раздел скрыт, полный набор доступен через All.
**C:** компактная desktop-шапка, дата с температурой в общей строке, единые заголовки и скрытая
пустая заметка. **B:** крупный нативный просмотр, навигация по всем сохранённым файлам и явное
внешнее открытие. Лимит 15, старые коллекции, исходные файлы и истечение события сохраняют
прежние правила.

Дизайн-разведка выполнена до реализации с `macos-desktop-design`. Платформенное исследование
использовало `macos-platform-research`, реализация и независимое ревью — `swift-code-quality`,
а приёмка после зелёных автоматических проверок — `product-qa`. Дизайнер, исследователь/разработчик
просмотра и агент сценариев проверяли отдельные части; родитель координировал сборки и GUI-запуски.

## Доказательства

Точный native executable: `0316e4fbd00ab8bada98924201af32f6bb2d116820f74f919c2da26bbde6f8ce`.
Метаданные тестового пакета пока 1.17.0/32. Все профили, файлы и defaults изолированы;
производственные события не использовались как изменяемые фикстуры.

| Поверхность | Результат | Что подтверждено |
| --- | --- | --- |
| Strict SwiftLint | 0 нарушений / 75 файлов | Итоговый код и тесты |
| `./verify.sh fast` | PASS CoreChecks и UIChecks | Доменные, Store, presentation и новые preview-sequence проверки |
| Детерминированные preview sequences | 4 seed × 180 команд | 720 воспроизводимых переходов с независимым oracle, а не 720 отдельных пользовательских сценариев |
| Общий desktop native | 27/27, 52,507 с | Окно, обе поверхности, редакторы, timer, split, appearance, weather и копии файлов |
| Focused attachments native | 7/7, 21,005 с | Полка, просмотр, возврат, ресурсы, удаление и controlled expiry |
| Focused external XCUITest | 2/2 | Настоящие clicks, Escape, Back, backdrop, поиск и AX exclusion |
| Eval runner | 33/33 | Новые `attachments` / `attachments-capture` распознаются как build/UI операции |
| Ручная CUA-приёмка | PASS в указанном объёме | Реальные QL-пиксели, внешний Preview и возврат, byte/inventory comparison |

Полные receipts, исходные хеши и выбранные снимки: [provenance](../images/v1.17.0/attachment-shelf-preview-unreleased/PROVENANCE.md).
Нативные наборы содержат 110 и 42 PNG. В README используются свежие выбранные изображения;
исторические релизные изображения сохранены.

## Матрица существенных пользовательских рисков

| ID | Сценарии и проверяемый исход | Доказательства |
| --- | --- | --- |
| A1 | 0/1/3/4/6/15 файлов; 2/3 колонки; одна левая ячейка; равные captions; fallback сохраняет размеры; правильный All-порог | Native обеих поверхностей, геометрия фактического viewport и просмотр Light/Dark |
| A2 | Legacy 17 файлов; существующие копии не обрезаются, сторонние поля сохраняются, навигация по всему массиву | Core/Store и preview-session checks |
| C1 | Узкая/широкая деталь, длинный title, пустая заметка, пустые/заполненные подзадачи; один редактор | Native desktop и текущие снимки |
| C2 | Pending/loaded/missing/global OFF/per-event OFF прогнозы; дата и следующие блоки остаются на месте | Gated native provider, live NSView geometry, реальные pending/loaded изображения |
| B1 | Первый/последний файл, повторные Next/Previous, недопустимый ID, два независимых surface sessions | Session sequences и native кнопки без wrap |
| B2 | A → B → поздний A; close → reopen того же UUID; missing/non-file URL; поздний external completion | Управляемые continuation gates, identity/origin и generation assertions |
| B3 | Открытие из полного/отфильтрованного списка; переход по всему saved array; Back возвращает query и ненулевой scroll offset | Native query + clip/document-size receipt, external поиск после возврата |
| B4 | Current file удалён из shared Store; владелец удалён/истёк; у соседнего события данные сохраняются | Реальные views + Store/repository, cleanup UUID-папок, original-byte checks, hosted injected clock |
| B5 | Скрыть/показать мини через production status-item action; old renderer/item освобождены; новый renderer не autoplay | Native visibility/key/occlusion и strong-old-reference assertions |
| B6 | Close/Escape/backdrop; родитель не принимает ввод; hidden library не читается через AX | Физические XCUI inputs, скрытый поиск отсутствует на обеих поверхностях, selection/divider/JSON сохранены |
| B7 | PNG, PDF page zero, MP4 poster, TXT/RTF, corrupt/missing/unknown fallback; увеличенный raster ограничен | Thumbnail checks, native binding и отдельные compositor screenshots |
| D1 | Просмотр/поиск/листание не меняют JSON, owned bytes, markers или inventory; intentional deletion удаляет только свои копии | Native tree snapshots и отдельные mutation receipts |
| D2 | «Открыть в приложении» передаёт owned URL, активация внешнего приложения скрывает mini, возврат сохраняет тот же файл | Ручной Preview URL и mini 1/15; 31 read-only файл до/после идентичен |

## Найденные и исправленные дефекты

- Физический клик в промежуток строки файла мог не вызвать её действие. Label теперь занимает
  всю ширину с прямоугольной hit area. Внешний тест оставлен с одним обычным кликом.
- Скрытая библиотека оставалась в AX-дереве под активным просмотром. Явные контейнеры разделяют
  экраны; строгая внешняя проверка отсутствия поиска проходит на desktop и mini.
- До окончания native dismissal очищались content/размеры; закрытие во время resolve могло
  показать ложный unavailable state. Presentation сохраняется до `onDismiss`, поздний результат
  отклоняется, final close очищает состояние.
- Retained окно могло сохранять QL resource после hide. Host теперь освобождает renderer/item
  по видимости своего окна и создаёт новый при show с `autostarts = false`.

Драйверы также приведены к реальному сценарию: lazy shelf сначала прокручивается в viewport,
геометрия сравнивается в одной live native системе координат, cached SwiftUI sheet records
оцениваются по реальному окну/selection/resources, а скрытие панели идёт через её владельца.
Размеры, containment, identity, отсутствие фонового ввода и проверки байтов не ослаблялись.

## Визуальная и ручная приёмка

Дизайнер просмотрел текущие desktop/mini Light/Dark, narrow metadata, empty note, четыре
desktop tile и три mini tile; видимых дефектов не обнаружил. Фото, PDF, 20-секундный movie
poster и mini-фото дополнительно сняты реальным экранным захватом: `cacheDisplay` не содержит
пиксели Quick Look service и не используется как доказательство содержимого.

Внешний `com.apple.Preview` открыл точный путь application-owned PNG. Возврат через штатное
меню окна и мини-панель сохранил имя и позицию 1/15. JSON + 15 копий + 15 markers до/после
совпали по SHA-256 и составу. Закрыт только тестовый внешний документ; тестовое приложение завершено.

## Границы

Проверен macOS 26.6.2 / 25G83 / arm64. Реальный VoiceOver, запуск на macOS 13,
password-protected документы, все сторонние Quick Look extensions и произвольные очень большие
медиа отдельно не сертифицированы. У MP4 подтверждён poster и отсутствие автозапуска;
ручное inline-воспроизведение этим провайдером не было подтверждено. Освобождение renderer/item
проверено отдельно и не заменяет слуховую/видеопроверку любого проигрывателя.

Hosted controlled-clock expiry не является переводом системных часов или полной проверкой
Mission Control/Spaces. Static captures не доказывают отсутствие всех промежуточных transient
frames. Полный старый XCUITest suite не запускался: выбраны два изменённых end-to-end маршрута.
Это ограниченная, воспроизводимая приёмка существенных рисков, а не перечисление всех возможных действий.
