# zhura_stats — Handoff (исследование Blizzard_MacroUI)

Дата: 2026-06-20. Ветка: `claude/focused-feynman-8qpj3q`. Изменений нет — сессия исследовательская.

## Что делали

Проверили устройство базы знаний и попытались найти структуру окна макросов.

### Подтверждено: база знаний в `docs/wow-api/`

Построена из `wow-ui-source` скриптом `scripts/gen_api_index.py`. Парсит только `Interface/AddOns/Blizzard_APIDocumentationGenerated/*Documentation.lua`. Содержит:
- `INDEX.md` — 573 системы, 9906 функций/событий (билд 12.0.7.68256)
- `SECRET-VALUES.md` — Secret-значения (ключевое для аддона)
- `ADDON-RESTRICTIONS.md` — енумы ограничений
- `api-index.json` — машиночитаемый дайджест с сигнатурами

### Что нашли по макросам в базе

Система `UIMacros` — только 5 записей:
- `GetMacroName(macroId)` → `name`
- `GetSelectedMacroIcon(macroId)` → `textureNum`
- `RunMacroText(text, button)`
- `SetMacroExecuteLineCallback(cb)`
- событие `UPDATE_MACROS`

Это только задокументированный API. Само окно макросов (фрейм, кнопки, редактор) — в `Blizzard_MacroUI`, который наш дайджест не покрывает.

## Что сделать локально

Посмотреть устройство окна макросов:

```
C:\dev\wow-ui-source\Interface\AddOns\Blizzard_MacroUI\
```

Интересные файлы там (вероятно):
- `Blizzard_MacroUI.lua` — основная логика фрейма
- `Blizzard_MacroUI.xml` — XML-разметка фреймов (если есть)
- `Blizzard_MacroUI.toc` — список файлов аддона

---

# NE Stats / zhura_stats — Handoff (layout + DR refactor)

Дата: 2026-05-31. Ветка: `feature/ref-accord-wow-api`. Дерево было чистое в начале сессии (изменения НЕ закоммичены — закоммить сам).

## Что делали
Рефакторили отображение статов: с плоских склеенных строк (`FormatStatValue` → одна FontString) на **сегментную grid-модель** (label / rating / sep / percent / dr / ref — каждый своя FontString, выровненная по суб-колонкам). Чинили разрывы layout, переделывали отображение diminishing returns.

## Затронутые файлы
- `Format.lua` — `BuildStatSegments` (новый, источник сегментов), `BuildReferenceSegment` (ref-сегмент с цветом). Старый строковый `FormatStatValue`/`FormatReferenceRatingSuffix` НЕ трогали (живут для совместимости/тестов).
- `Frame.lua` — пул сегментных FontString на row (`row.segments`), хелперы `AcquireRowSegment`/`HideRowSegmentsFrom`. Якорь фрейма по textAlign переведён на TOP* (`FRAME_ANCHOR_BY_TEXT_ALIGN = {LEFT=TOPLEFT, CENTER=TOP, RIGHT=TOPRIGHT}`), `GetCurrentAnchorOffsets` пересчитан под top-якоря.
- `Render.lua` — зональная раскладка: `ComputeColumnMetrics` + `ComputeColumnOffsets`, модель `[icon][label][BAND][TAIL]`. `ResolveSegmentColor`. `ApplyTextAlignmentToVisibleLines` теперь = `RefreshStats()`.
- `tests/test_format.lua` — добавлены тесты на сегменты, DR, стрелки.

## Готово и задеплоено (work)
1. **Сегментный grid** — числа выровнены по суб-колонкам.
2. **Зоны вместо накопительных суб-колонок:**
   - BAND = rating/sep/percent, right-aligned в зоне `max(bandWidth, valueWidth)`. `value` (нерейтинговые AGI/DURA/ILVL/GOLD) right-aligned к той же зоне.
   - TAIL = dr+ref, единая right-aligned зона, ширина = max(dr+ref) по строкам. **DR у одной строки НЕ двигает ref других** (это чинило разрыв layout).
3. **Ширина колонки = ширина текста** (нет растяжки на ширину фрейма).
4. **Якорь по верхней точке** — добавление строк/DR не сдвигает anchor (LEFT→top-left, CENTER→top-center, RIGHT→top-right). Дефолт профиля уже `point=TOPLEFT, y=-240`.
5. **DR-отображение:** убран мусор `(DR -20%)` inline и synthetic `-1197 DR`. Теперь: сегмент `col="dr"` = `DR(-N)` где N = `statResult.dr.loss` округлённый (реальная потеря рейтинга от диминишинга из `Stats.GetDRInfo`, НЕ reference-delta). Percent + DR-тег красятся `GetDRColor` по `dr.penalty`. При loss→0 показывает просто `DR`. `drFlag` протаскивается через measured-сегмент в `ResolveSegmentColor`.
6. **Инверсия знака reference-delta ИСПРАВЛЕНА** (был критичный баг): `d = playerR - archonR`. Раньше перекап (`d>0`) показывался как `-1197`, недобор как `+`. Теперь стрелки: `d>0` → `↑<d>` (REF_COLOR_OVER оранжевый), `d<0` → `↓<-d>` (REF_COLOR_UNDER жёлтый), `d==0` → `ok` (зелёный). Исправлено в обоих путях (сегментный `BuildReferenceSegment` + строковый `FormatReferenceRatingSuffix`).

Стрелки сейчас: `↑` = `\226\134\145` (U+2191), `↓` = `\226\134\147` (U+2193).

Последний деплой Format.lua: 22:37. Тесты: **94/94 зелёные**, luacheck 0/0 по Render/Frame/Format.

## НЕ ДОДЕЛАНО — старт нового чата отсюда

### A. Стрелки рисуются как КВАДРАТЫ (тофу) — ГЛАВНОЕ
Шрифт **Friz Quadrata TT** (дефолт `fontKey`) НЕ содержит глифы U+2191/U+2193 → в игре тофу-квадраты. Нужно заменить на символы, которые точно рендерятся.
Варианты (выбрать/протестить):
- ASCII `^` / `v` (грубо, но 100% есть)
- Игровые текстуры-стрелки через `|T...:0|t` (атлас/иконка) — самые красивые, но надо подобрать путь текстуры
- Юникод-стрелки из набора, который Friz реально поддерживает (надо проверить эмпирически)

Где менять: `Format.lua` → `BuildReferenceSegment`, константы `ARROW_UP`/`ARROW_DOWN` (плюс строковый аналог в `FormatReferenceRatingSuffix`, там инлайн `\226\134\145`/`\226\134\147`). И обновить тесты в `test_format.lua` (`delta mode emits up arrow...` / `...down arrow...` ассертят именно `\226\134\145`/`\226\134\147`).

### B. Дебаг-дамп символов по тройному middle-click на замочке (lockButton)
Юзер просил: по 3× кликов средней кнопкой по lockButton отрисовать таблицу символов-кандидатов в стрелки, чтобы вживую увидеть какие рендерятся, какие тофу. Это инструмент для подбора рабочего глифа под пункт A.
- lockButton создаётся в `Frame.lua` → `EnsureStatsFrame`, уже `RegisterForClicks("LeftButtonUp","RightButtonUp")` — добавить MiddleButton + счётчик тройного клика (тайм-окно ~0.5с).
- Набор кандидатов для дампа (юзер выбирал из этого списка, финально НЕ подтвердил — переспросить): `↑↓▲▼⬆⬇^v›‹` и пр., каждый с подписью кодпойнта; рисовать в отдельном фрейме/строках, чтобы видеть тофу.
- ВОПРОС который завис (переспросить юзера): формат дампа — (1) узкий набор кандидатов-стрелок, (2) широкий Unicode-дамп блоками, или (3) сразу пробовать текстуры `|T..|t` вместо шрифтовых глифов.

### C. Stale-dim — «не всю строку уменьшать яркость» (висит с прошлого)
Сейчас `ResolveSegmentColor` тускнит ВСЕ сегменты на `STALE_DIM_FACTOR=0.70` когда значение не live (Secret в бою/M+/encounter/PvP, source=snapshot/cache/stale). Юзер хочет НЕ тускнить всю строку — вероятно оставить дим только на числах (rating/percent/value), а label/icon яркими. Уточнить и поправить в `ResolveSegmentColor` (Render.lua ~строка 395).

## Важный контекст (чтобы не путаться как я)
- **Два РАЗНЫХ числа на строке, не дублируют друг друга:**
  - `DR(-N)` — потеря рейтинга от diminishing returns (реальный игровой расчёт, `Stats.GetDRInfo`, `ratingBonus` vs пороги `DR_THRESHOLDS={30,39,47,54,66}` в процентах).
  - `↑N`/`↓N` (ref) — отклонение твоего рейтинга от Archon-эталона (`playerR - archonR`). archonRating берётся из `WoWLogsStatsPrio` по спеке/режиму (m+/raid).
- Archon-эталон для BM Hunter M+ (пример из скрина): Crit 979, Mastery 839, Haste 468, Vers 126. (Я однажды выдумал 3233 — НЕ доверять числам из головы, всегда проверять по факту/данным.)
- Юзер: BM Hunter, перекап mastery — нормальная ситуация для него.

## Команды
- Тесты: `powershell -ExecutionPolicy Bypass -File .\scripts\run-tests.ps1`
- Luacheck: `powershell -ExecutionPolicy Bypass -File .\scripts\run-luacheck.ps1 <files> --config .luacheckrc`
- Deploy: `powershell -ExecutionPolicy Bypass -File .\scripts\deploy-local.ps1` (цель: `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\ZhuraStats`)
- После деплоя в игре: `/reload`
- ВАЖНО: при правке Lua всегда гонять luacheck + tests перед деплоем. FontString-рендер юнит-тестами не покрыт (проверять в игре).
