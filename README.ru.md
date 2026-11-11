# Ядро Commodore VIC-20 для Karabas Go / Mini / Mini G

[English version](README.md)

Commodore VIC-20 для плат семейства Karabas Go (Xilinx Spartan-6 XC6SLX25): порт
[VIC20Nano](https://github.com/MiSTle-Dev/VIC20Nano) (MiSTle-Dev), который сам основан на VIC-20
MiST / MiSTer от MikeJ и WoS с дисководом C1541 от darfpga. Вся работа с файлами (программы,
картриджи, образы дисков, ленты, ПЗУ) идёт через OSD и файловый браузер прошивки платы: своего
загрузчика в ядре нет. Руководство пользователя — `docs/GUIDE.md`, план и решения — `docs/PLAN.md`.

| Плата | Файл ядра | Видео | Звук | Состояние |
|---|---|---|---|---|
| Karabas Mini G | `vic20.kg` | HDMI, 720x576 50 Гц (PAL) / 720x480 60 Гц (NTSC) | HDMI, ЦАП I2S (PCM5102) | проверено на плате |
| Karabas Mini | `vic20.kg` | HDMI, как Mini G | HDMI, аналоговый выход (сигма-дельта) | собрано, на плате не проверялось |
| Karabas Go | `vic20.kg` | VGA, как Mini G | ЦАП I2S (PCM5102) | собрано, на плате не проверялось |

Файл ядра — `src/vic20.kg`, один на все три платы, ПЗУ Commodore встроены. Нужна прошивка
v26103113 или новее. Пункты OSD ищут файлы в папке `/vic20` SD-карты.

## Что умеет

- **Машина:** 6502 (T65) на 1,1 МГц (PAL) / 1,02 МГц (NTSC), VIC 6561 (PAL) или 6560 (NTSC) со
  звуком, два 6522, 5 КБ ОЗУ, BASIC V2 и Kernal своего стандарта (901486-07 PAL / 901486-06 NTSC).
  PAL / NTSC — пункт Video (машина перезапускается).
- **Расширения ОЗУ:** 3K, 8K, 16K, 24K, 3K+24K, 35K (пункт RAM), в SRAM платы.
- **Программы:** `.prg` кладётся в память работающей машины по своему адресу, указатели BASIC
  ставятся после него: сразу `RUN` или `LIST`.
- **Картриджи:** файл с двухбайтовым адресом загрузки (`.prg`, `.a0`, `.crt` в формате MiSTer),
  от 8 КБ, в блоки $2000 / $4000 / $6000 / $A000 (только чтение); картридж с $A000 запускается сам.
  Картридж из нескольких файлов (`-2000`, `-a000`, ...) загружается по файлу; файл на уже занятый
  блок начинает новый картридж. Eject cart (Menu+E) вынимает его.
- **Mega-Cart:** образ Mega-Cart 2 МБ (`.rom`, `.bin`) в SRAM, со своим меню. Его NVRAM 8 КБ
  (сохранения игр) хранится в файле: пункт MC NVRAM, файл 8 КБ (`sd/vic20/megacart.nvr` этого
  репозитория, пустой), записывается вскоре после того, как машина его изменила.
- **Дисковод 8:** C1541 (6502, два VIA, DOS 325302-01 / 901229-06AA) на образах `.d64` и `.g64`,
  чтение и запись (запись идёт в файл образа); файл только для чтения или Disk 8 WP — защищённый
  диск. Другую DOS (16 КБ или последние 16 КБ образа 32 КБ) можно загрузить из файла (1541 DOS).
- **Магнитофон:** файлы `.tap` (до 1 МБ) проигрываются в C1530; PLAY нажимается при выборе файла,
  так что `LOAD` сразу находит программу; Tape play (Menu+P) — клавиша PLAY / STOP.
- **Kernal:** другой Kernal 8 КБ из файла (например, JiffyDOS) заменяет встроенный.
- **Ввод:** USB-клавиатура как клавиатура VIC-20 (раскладки Symbolic и Positional, см. ниже),
  джойстик платы или USB-геймпад как джойстик, USB-мышь как два пэдла (пункт Mouse).
- **Видео:** картинка VIC удвоена до 576p50 / 480p60, по центру, с OSD.

Проверено на Mini G: BASIC, обе раскладки, PRG / картридж / расширения ОЗУ, PAL и NTSC, звук,
каталог D64, `LOAD` и `SAVE` (файл попадает в образ), загрузка с TAP, Mega-Cart и Eject, DOS из
файла, пэдлы, картридж из двух файлов, NVRAM Mega-Cart сохраняется между запусками ядра. Нет:
второго дисковода, RS-232 порта пользователя,
записи на ленту.

## OSD

Открывается Menu+Esc («Menu» — клавиша Windows).

| Пункт | Что делает | Клавиша |
|---|---|---|
| Disk 8 | образ диска дисковода 8 (`.d64`, `.g64`) | Menu+F1 |
| PRG | программа в память | Menu+F2 |
| Cartridge | файл картриджа (машина перезапускается с ним) | Menu+F3 |
| Tape | файл `.tap` в магнитофон | Menu+F4 |
| Kernal | файл Kernal 8 КБ вместо встроенного | Menu+F5 |
| Mega-Cart | образ Mega-Cart 2 МБ | Menu+F6 |
| MC NVRAM | файл NVRAM Mega-Cart 8 КБ (`.nvr`) | |
| 1541 DOS | файл ПЗУ DOS дисковода | Menu+F7 |
| RAM | None / 3K / 8K / 16K / 24K / 3K+24K / 35K (затем Reset) | Menu+M |
| Video | PAL / NTSC | Menu+V |
| Keyboard | Symbolic / Positional | Menu+K |
| Mouse | Off / Paddles | |
| Disk 8 WP | Off / On: защита диска от записи | |
| Tape play | клавиша PLAY / STOP магнитофона | Menu+P |
| Eject cart | вынимает картридж или Mega-Cart (с перезапуском) | Menu+E |
| Reset | перезапуск машины | Menu+F12 |

## Клавиатура

Symbolic (по умолчанию): символ, набранный на американской клавиатуре ПК, даёт тот же символ на
VIC (`Shift+=` — `+`, `Shift+;` — `:`, `'` и `"` — это `Shift+7` / `Shift+2` VIC). Positional:
клавиши ПК на местах клавиш VIC, Shift ПК как есть (как в апстриме).

| VIC-20 | ПК |
|---|---|
| RUN/STOP | Esc |
| RESTORE | F11 |
| C= (Commodore) | Alt, Caps Lock |
| CTRL | Ctrl |
| CLR/HOME | Home |
| INST/DEL | Backspace, Delete (Insert — INST) |
| f1 / f3 / f5 / f7 | F1 / F3 / F5 / F7 (F2 / F4 / F6 / F8 — с Shift) |
| £ | \ |
| ← | ` |
| ↑ | F9 |
| курсор | стрелки |

## Сборка

Ядро собирается Xilinx ISE 14.7 под Linux: `cd src && make` (все три платы по очереди) или
`make go`, `make mini`, `make minig`; `make minig-report` показывает занятость и тайминг последней
сборки. Правится верх Mini G: верхи Go и Mini из него делает `src/tools/mktops.py` (его запускает
Makefile). Модули плат — подмодуль `modules/`
([karabas-go-modules](https://github.com/andykarpov/karabas-go-modules)): клонировать с
`git clone --recursive` или выполнить `git submodule update --init`. Для упаковки `.kg` рядом
должен лежать репозиторий [karabas-go-tools](https://github.com/andykarpov/karabas-go-tools).

Модели — в `src/sim`: вся машина в verilator (`run_boot.sh`, VHDL через ghdl: загрузка, PRG с
`RUN`, экран читается как текст), тесты iverilog загрузчика, клавиатуры и ленты (`run_loader.sh`,
`run_hid.sh`, `run_tape.sh`). `src/tools/mkd64.py` и `prg2tap.py` делают тестовые образы диска и
ленты. В `CLAUDE.md` — устройство проекта и правила.

Прошивка платы — [karabas-go-firmware](https://github.com/andykarpov/karabas-go-firmware).

## Авторы и лицензия

- [VIC20Nano](https://github.com/MiSTle-Dev/VIC20Nano): MiSTle-Dev (порт на Tang, Mega-Cart,
  проигрыватель ленты C1530).
- VIC-20 от MikeJ (fpgaarcade) и WoS (MiST / MiSTer); T65: Daniel Wallner, MikeJ и другие.
- C1541 от darfpga.
- Платы Karabas Go и порт: Andy Karpov.

VIC20Nano — GPL v3; части Karabas — GPL v3 (`LICENSE`). Импортированные файлы сохраняют свои
заголовки. ПЗУ Commodore в `src/rom` (BASIC, Kernal, знакогенератор, DOS 1541) — те, что
поставляет MiSTer VIC20_MiSTer; они встроены в файл ядра.
