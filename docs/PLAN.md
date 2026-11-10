# План ядра Commodore VIC-20 для Karabas Go / Mini / Mini G

Цель: Commodore VIC-20 (6502, VIC 6561 PAL / 6560 NTSC, два 6522, расширения RAM 3K–35K, картриджи, Mega-Cart, дисковод 1541 с D64, магнитофон 1530 с TAP) на платах Karabas (XC6SLX25, ISE 14.7). Основа — [VIC20Nano](https://github.com/MiSTle-Dev/VIC20Nano). Файлы идут через прошивку (OSD, `FL`, `F`, `img_sdc`): загрузчика и soft-CPU в ядре нет. Репозиторий `andykarpov/karabas-go-core-vic20`, публичный.

## Что изучено (2026-11-11)

| Проект | Состояние | Что внутри |
|---|---|---|
| [MiSTle-Dev/VIC20Nano](https://github.com/MiSTle-Dev/VIC20Nano) 9089828 (2026-03-21), GPL v3 | зрелый (69 коммитов), платы Tang от Nano 9K до Console 138K | `vic20.vhd` (MikeJ / WoS): T65, `m6561.vhd` (VIC), `m6522.vhd` ×2, клавиатура-матрица, RAM 1K + 2K + 2K + цвет 1K×4, расширения 4 × 8K + картридж 8K — всё в BSRAM; ПЗУ char 4K / BASIC 8K в pROM, Kernal 8K загружаемый (SDPB). `c1541/` (darfpga): `c1541_sd` — D64 → GCR (`gcr_floppy`), `c1541_logic` (6502 + 2 × via6522), DOS ПЗУ 32K из SPI-флеша (CBM, Dolphin, SpeedDOS, JiffyDOS), чтение / запись сектора через `sd_card` (интерфейс `sd_lba` / `sd_rd` / `sd_wr` / `sd_byte_index`). `c1530.vhd` (TAP v0–2, FIFO), `megacart.v` + NVRAM (2 МБ в SDRAM), `loader_sd_card.sv` (PRG / CRT / Kernal / TAP / Mega-Cart читает сама ПЛИС из слотов SD), обвязка MiSTle (`sysctrl`, `mcu_spi`, `hid`, `osd_u8g2`, меню `vic20.xml`), видео: `scandoubler` → HDMI 720×576p@50 / 720×480p@60, клок ядра 35,775 / 32,94 МГц (PAL / NTSC, PLL перестраивается). Мышь c1351, пэдлы, RS232 VIC-1011 на user port |
| MiST / MiSTer VIC20 | живые | та же машина MikeJ; загрузка через HPS / ARM. Для нас ближе VIC20Nano: ему уже нужен внешний µC, как нашей прошивке |

Ресурсы: VIC20Nano без C1541 входит в Tang Nano 9K (GW1NR-9, 8,6K LUT4), полностью — в Nano 20K. Оценка для XC6SLX25: **~5–7K LUT из 15K**, проверить в Ф0. BRAM: ПЗУ 20K + RAM 5,5K + C1541 (ПЗУ 16–32K, RAM 2K, буфер дорожки) ≈ 45–60 КБ из 104 КБ — если всё держать в BRAM, места мало; поэтому расширения и картридж выносим в SRAM.

## Решения

Пользователь (2026-11-11): делаем VIC-20 (после обзора MiniMig / VIC20Nano); репозиторий `karabas-go-core-vic20` (создал сам, публичный).

Предложение (ждёт подтверждения; пока работаем по нему):

1. **Основа** — VIC20Nano: `vic20.vhd`, `m6561`, `m6522`, `t65`, `c1541/`, `c1530`, `megacart` как есть в `src/rtl/`, правки для XST с пометкой `-- karabas:` / `// karabas:`, SV через sv2v. Обвязка MiSTle (`sysctrl`, `sd_card`, `mcu_spi`, `hid`, `osd_u8g2`, `flash*`, `loader_sd_card`, `dualshock2`, `ws2812`, `video_lcd`) не нужна.
2. **Имя** `vic20` (`vic20.kg`, папка `/vic20`).
3. **Память.** Основная RAM (5K + цвет), ПЗУ char / BASIC / Kernal, RAM и ПЗУ C1541, буфер дорожки — BRAM. Расширения $0400 3K, $2000 / $4000 / $6000 по 8K, картридж $A000 8K, Mega-Cart 2 МБ, буфер TAP — в SRAM (2 × 2M×8 = 4 МБ, контроллер как в nanomig). SDRAM не нужна.
4. **Видео** — как в апстриме: родная развёртка VIC (PAL 312 строк / NTSC 261) → `scandoubler` → 720×576p@50 (PAL) / 720×480p@60 (NTSC) на HDMI (Go — VGA). Клоки из 50 МГц через `kg_pll` / DCM: подобрать к 35,469 / 32,727 МГц (8 × частота пикселя VIC) или взять апстримные 35,775 / 32,94; стандарт PAL / NTSC — из OSD с перезапуском PLL (как в апстриме) или два набора CE на одном клоке — решить в Ф0. Центрирование, широкий экран — из апстрима.
5. **Дискеты** — C1541 на D64 через `img_sdc` (F-слот, чтение и запись, LED активности); D64 по умолчанию `/vic20/disk8.d64`. Позже — второй привод (номер 9), G64 — если понадобится.
6. **Лента** — TAP: `FL`-файл кладём в SRAM, `c1530` играет из неё по `LOAD` (автостарт, как в апстриме). Звук ленты — выключаемый.
7. **Загрузчики** через `FL` (`kg_mcu` ROMLOAD): PRG в BASIC-память (инжект + указатели BASIC, как в апстриме), CRT / PRG-картридж по адресу из заголовка (2000 / 4000 / 6000 / A000, A000 последним — автостарт), Kernal 8K (.bin), Mega-Cart (.rom, 2 МБ).
8. **Клавиатура, джойстик** — свой `vic20_hid.v` поверх `kg_mcu_hid`: HID-код → матрица VIC-20 (раскладку взять из `vic20_keymap.v`), геймпад → джойстик Atari (порт VIA1 / VIA2), мышь → c1351 / пэдлы, numpad-джойстик. Сброс — Menu+F12, как в других ядрах; RESTORE — отдельная клавиша (как в апстриме).
9. **Звук** — 6-битный выход VIC + звук ленты → HDMI / PCM5102 / сигма-дельта.
10. **ПЗУ Commodore** (char, BASIC, Kernal PAL / NTSC, 1541 DOS) — ждёт решения: в репозитории и `.kg` (как в апстриме, кроме JiffyDOS) или файлы пользователя через `FL`. JiffyDOS / Dolphin / SpeedDOS — только файлом пользователя.
11. **Свой верх платы**, общий код через `modules` (`kg_mcu`, `img_sdc`, OSD, HDMI, PCM5102), Makefile как у atarist / archie. Первым — Mini G, затем Go и Mini. Mini G2: T3 = 0 (SDRAM ~CS). Физический дисковод Go не подходит (1541 — IEC, не Shugart): выходы `FDC_*` = 0. RS232 VIC-1011 — на UART / ESP (позже, по желанию).

## Архитектура

```
 VIC20 (vic20.vhd) ├── T65 ── шина ── BRAM: RAM 5K + цвет, ПЗУ char / BASIC, Kernal (FL)
                   ├── extmem ── vic20_sram ── SRAM: расширения 3K + 3 × 8K, картридж 8K, Mega-Cart 2 МБ, буфер TAP
                   ├── m6561 ── scandoubler ── OSD ── HDMI / VGA
                   ├── звук VIC ─┬───────────────────────── HDMI / PCM5102 / сигма-дельта
 c1530 (TAP из SRAM) ────────────┘
 клавиатура / джойстик / пэдлы ── vic20_hid ── kg_mcu HID
 IEC ── c1541_sd (6502 + 2 × VIA, DOS ПЗУ BRAM, GCR) ── sd_lba / sd_rd / sd_wr ── img_sdc ── kg_mcu (file mounter)
 FL: Kernal, PRG, CRT, TAP, Mega-Cart ── kg_mcu ROMLOAD ── BRAM / SRAM
```

## Фазы

Ветка и один PR на фазу, слияние в конце фазы.

- **Ф0. Импорт и fit.** `upstream/` (VIC20Nano без правок), `src/rtl/` с правками XST, Gowin-примитивы → инферируемые RAM из `modules/rtl/mem`, sv2v для SV, Makefile, `core.json`, `make vic20-xst` (машина + C1541 + C1530). Выбор клоков. Готово, когда XST собирает без защёлок и с ≥ 2× запасом по частоте.
- **Ф1. Симуляция.** Машина + модель SRAM: загрузка ПЗУ до заставки «CBM BASIC V2 … BYTES FREE», кадр в PNG; клавиатура; PRG-инжект; `LOAD"$",8` с D64 на модели `img_sdc`.
- **Ф2. Mini G.** Клоки, SRAM, видео → HDMI со звуком, HID, OSD, ПЗУ, расширения RAM, PRG / CRT через `FL`. Первый запуск на плате.
- **Ф3. Диск и лента.** C1541 на D64 (чтение, запись, смена диска, выбор DOS ПЗУ), TAP через `c1530`.
- **Ф4. Остальное.** Mega-Cart, джойстик / пэдлы / c1351, NTSC, центрирование; RS232 — по желанию.
- **Ф5. Go / Mini и релиз.** Верхи Go (VGA, PCM5102) и Mini, `cores.json`, README / GUIDE.

## Открытые вопросы

- ПЗУ Commodore (char, BASIC, Kernal, 1541 DOS) в репозитории и `.kg` или файлы пользователя.
- Стандарт по умолчанию: PAL (предложено) или NTSC; переключение PAL / NTSC на лету (перестройка клока) или только перезапуском.
- Примет ли монитор пользователя 720×576p@50 (PAL).
- Второй дисковод (номер 9) — нужен ли.
