#!/bin/bash
# Axolotl-PM 릴리스 원본에 patches/*.patch 를 이름 순서로 붙여 PocketMine-MP.phar 를 만든다.
#
#   bash build.sh 5.51.2              태그를 받아 패치를 붙여 빌드 → ~/ezgame-engine/dist/
#   bash build.sh 5.51.2 --vanilla    패치 없이 (공식 판과 같은지 비교할 때)
#
# 공식 릴리스(.github/workflows/draft-release.yml)와 같은 방법으로 만든다:
#   composer install --no-dev --prefer-dist --ignore-platform-reqs
#   build/server-phar.php --git <커밋> --build <번호>
# 빌드 번호는 OFFICIAL=<공식 phar 경로> 를 주면 거기서 읽고, 없으면 0.
# PHP 는 phar 를 쓸 수 있는 8.4 (PocketMine 용 PHP 바이너리 권장), PHP=<경로> 로 바꿀 수 있다.
set -euo pipefail
TAG=${1:?태그를 적어 주세요 (예: 5.51.2)}
VANILLA=0; [ "${2:-}" = "--vanilla" ] && VANILLA=1
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$HOME/ezgame-engine"
PHP=${PHP:-php}
SRC="$WORK/src-$TAG"
mkdir -p "$WORK/bin" "$WORK/dist"
if [ ! -f "$WORK/bin/composer.phar" ]; then
	curl -fsSL -o "$WORK/bin/composer.phar" https://getcomposer.org/download/latest-stable/composer.phar
	echo "$(curl -fsSL https://getcomposer.org/download/latest-stable/composer.phar.sha256sum | awk '{print $1}')  $WORK/bin/composer.phar" | sha256sum -c -
fi
# 패치를 붙이므로 매번 깨끗하게 새로 받는다
rm -rf "$SRC"
git clone -q --depth 1 --branch "$TAG" https://github.com/axolotl-pm/PocketMine-MP.git "$SRC" 2>/dev/null
COMMIT=$(git -C "$SRC" rev-parse HEAD)
PATCHES=()
if [ $VANILLA -eq 0 ]; then
	for p in "$HERE"/patches/*.patch; do
		[ -e "$p" ] || continue
		git -C "$SRC" apply --check "$p" || { echo "[중단] $(basename "$p") 가 $TAG 에 안 붙는다 — 새 판에 맞게 고쳐야 함" >&2; exit 1; }
		git -C "$SRC" apply "$p"
		PATCHES+=("$(basename "$p" .patch)")
	done
fi
( cd "$SRC" && COMPOSER_HOME="$WORK/.composer" "$PHP" "$WORK/bin/composer.phar" install --no-dev --prefer-dist --no-interaction --ignore-platform-reqs --quiet )
BUILD=0
if [ -n "${OFFICIAL:-}" ] && [ -f "$OFFICIAL" ]; then
	BUILD=$("$PHP" -r '$m=(new Phar($argv[1]))->getMetadata(); echo (int)($m["build"]??0);' "$OFFICIAL" 2>/dev/null || echo 0)
fi
SUFFIX=$([ $VANILLA -eq 1 ] && echo "vanilla" || echo "ez${#PATCHES[@]}")
OUT="$WORK/dist/PocketMine-MP-$TAG-$SUFFIX.phar"
( cd "$SRC" && "$PHP" -dphar.readonly=0 build/server-phar.php --git "$COMMIT" --build "$BUILD" --out "$OUT" >/dev/null )
# 붙인 패치 목록을 phar 메타데이터(ez_patches)에 적어 둔다. 플러그인이 읽어서 상태판에 보여 준다
if [ $VANILLA -eq 0 ]; then
	"$PHP" -dphar.readonly=0 -r '$p=new Phar($argv[1]); $m=$p->getMetadata(); $m["ez_patches"]=array_slice($argv,2); $p->setMetadata($m);' "$OUT" "${PATCHES[@]+"${PATCHES[@]}"}"
fi
sha256sum "$OUT" | awk '{print $1}' > "$OUT.sha256"
printf '%s\n' "${PATCHES[@]+"${PATCHES[@]}"}" > "$OUT.patches"
echo "빌드: $OUT ($(stat -c %s "$OUT") bytes · sha256 $(cut -c1-16 "$OUT.sha256") · 패치 ${#PATCHES[@]}개${PATCHES[*]:+: ${PATCHES[*]}})"
