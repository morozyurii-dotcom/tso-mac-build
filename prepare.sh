#!/usr/bin/env bash
# Готовит staging-папку AIR-приложения из публичного репозитория fedorovvl/tso_client.
# Тяжёлые .swf берём из upstream прямо в CI — вручную не заливаем.
set -euo pipefail

UPSTREAM_URL="https://github.com/fedorovvl/tso_client.git"
SRC="upstream/client/files/content"
STAGE="staging"

echo "==> clone upstream"
rm -rf upstream
git clone --depth 1 "$UPSTREAM_URL" upstream

echo "==> assemble staging"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$SRC"/. "$STAGE"/

# Сама игра (client.swf) лежит в КОРНЕ репозитория — оригинальный лаунчер
# докачивает её отдельно рядом с index.html. Повторяем это.
cp upstream/client.swf "$STAGE"/client.swf

# Дескриптор приложения кладём в корень staging.
cp "$SRC/META-INF/AIR/application.xml" "$STAGE"/application.xml

# Старые подписанные META-INF и mimetype убираем — adt сгенерит свои.
rm -rf "$STAGE/META-INF" "$STAGE/mimetype"

# Windows-заглушки (.exe) для мультиоконности через NativeProcess — в macOS-бандле
# запрещены adt и для основной игры не нужны.
rm -f "$STAGE"/*.exe

echo "==> patch application.xml"
python3 - <<'PY'
import re
p = "staging/application.xml"
s = open(p, encoding="utf-8").read()

# 1) Поднять namespace AIR до уровня SDK 51 (в исходнике стоит 15.0).
s = re.sub(r'xmlns="http://ns\.adobe\.com/air/application/[0-9.]+"',
           'xmlns="http://ns.adobe.com/air/application/51.0"', s)

# 2) Убрать блок <icon> — этих png в комплекте нет, упаковка бы упала.
s = re.sub(r'\s*<icon>.*?</icon>', '', s, flags=re.S)

# 2b) Убрать allowBrowserInvocation — для captive bundle не поддерживается (adt error 116).
s = re.sub(r'\s*<allowBrowserInvocation>.*?</allowBrowserInvocation>', '', s, flags=re.S)

# 3) Добавить профиль extendedDesktop — index.html использует NativeProcess.
#    По XSD supportedProfiles идёт последним перед </application>, поэтому
#    после удаления <icon> вставка сюда сохраняет правильный порядок элементов.
if "<supportedProfiles>" not in s:
    s = s.replace("</application>",
                  "  <supportedProfiles>extendedDesktop desktop</supportedProfiles>\n</application>")

# Нативный путь: вместо мёртвой HTML-оболочки (index.html+WebKit) запускаем
# нашу AS3-оболочку TSOLoader.swf, которая сама грузит library.swf + client.swf.
s = s.replace("<content>index.html</content>", "<content>TSOLoader.swf</content>")
s = s.replace("<renderMode>auto</renderMode>", "<renderMode>direct</renderMode>")

open(p, "w", encoding="utf-8").write(s)
print("patched:")
print(s)
PY

echo "==> compiling native AS3 loader (TSOLoader.swf)"
"$AIR_HOME/bin/mxmlc" TSOLoader.as -output="$STAGE/TSOLoader.swf" +configname=air 2>&1 | tail -25
test -f "$STAGE/TSOLoader.swf" && echo "TSOLoader.swf compiled OK ($(du -h "$STAGE/TSOLoader.swf" | cut -f1))" || { echo "!! COMPILE FAILED"; exit 1; }

echo "==> staging ready:"
ls -la "$STAGE" | head -40
