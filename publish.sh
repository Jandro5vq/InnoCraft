#!/usr/bin/env bash
#
# publish.sh — publica el .mrpack más nuevo como nueva versión de InnoCraft.
#
#   ./publish.sh                 # publica el .mrpack más reciente del repo
#   ./publish.sh "mensaje"       # con mensaje de commit personalizado
#   ./publish.sh --force         # republica aunque el tag ya exista (reescribe tag)
#
# Hace: elegir mrpack más nuevo -> reconstrucción limpia con build_packwiz.py ->
# packwiz refresh -> validar -> commit + push + tag -> verificar GitHub Pages.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO"

# --- toolchain (Go/packwiz instalados localmente, no en PATH permanente) ---
export GOPATH="${GOPATH:-$HOME/go}"
export PATH="$HOME/.local/go/bin:$GOPATH/bin:$PATH"

PAGES_VERSION_URL="https://jandro5vq.github.io/InnoCraft/version.txt"

# --- argumentos ---
FORCE=0
MSG=""
for a in "$@"; do
  case "$a" in
    -f|--force) FORCE=1 ;;
    *) MSG="$a" ;;
  esac
done

# --- comprobaciones previas ---
command -v packwiz >/dev/null 2>&1 || { echo "ERROR: packwiz no está disponible en el PATH."; exit 1; }
[[ -f build_packwiz.py ]] || { echo "ERROR: falta build_packwiz.py en $REPO."; exit 1; }

# --- elegir el .mrpack más nuevo (por fecha de modificación) ---
MRPACK="$(ls -t -- *.mrpack 2>/dev/null | head -1 || true)"
[[ -n "$MRPACK" ]] || { echo "ERROR: no hay ningún .mrpack en $REPO."; exit 1; }

# --- versión real desde el índice interno del mrpack (autoritativa) ---
VERSION="$(python3 - "$MRPACK" <<'PY'
import sys, zipfile, json
z = zipfile.ZipFile(sys.argv[1])
print(json.loads(z.read('modrinth.index.json')).get('versionId', '').strip())
PY
)"
[[ -n "$VERSION" ]] || { echo "ERROR: no pude leer versionId de $MRPACK."; exit 1; }

echo "==> mrpack más nuevo: $MRPACK  (versión $VERSION)"
TAG="v$VERSION"

# --- guardia: no republicar una versión ya etiquetada salvo --force ---
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  if [[ $FORCE -eq 0 ]]; then
    echo "ERROR: el tag $TAG ya existe (versión $VERSION ya publicada)."
    echo "       Usa --force para republicarla (reescribe el tag)."
    exit 1
  fi
  echo "    (--force) se reescribirá el tag $TAG"
fi

# --- reconstrucción limpia ---
echo "==> limpiando contenido generado de la versión anterior..."
rm -rf mods config data fancymenu_data shaderpacks resourcepacks icon.png servers.dat pack.toml index.toml

echo "==> generando pack desde $MRPACK..."
python3 build_packwiz.py "$MRPACK" >/dev/null

printf 'hash-format = "sha256"\n' > index.toml
echo "==> packwiz refresh..."
packwiz refresh >/dev/null

# --- validaciones ---
MODS="$(packwiz list 2>/dev/null | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | grep -c . || true)"
CLAUDE="$(grep -c '\.claude' index.toml || true)"
echo "==> validación: $MODS mods | .claude en index: $CLAUDE | version.txt: $(cat version.txt)"
[[ "$CLAUDE" == "0" ]] || { echo "ERROR: .claude está en el índice; revisa .packwizignore antes de publicar."; exit 1; }
[[ "$(cat version.txt)" == "$VERSION" ]] || { echo "ERROR: version.txt no coincide con $VERSION."; exit 1; }

# --- commit + push ---
COMMIT_MSG="${MSG:-InnoCraft $VERSION}"
git add -A
if git diff --cached --quiet; then
  echo "==> sin cambios de contenido respecto a lo ya publicado."
else
  git commit -q -m "$COMMIT_MSG

Publicado con publish.sh"
  echo "==> commit: $COMMIT_MSG"
fi
git push -q origin main

# --- tag ---
if [[ $FORCE -eq 1 ]]; then
  git tag -f -a "$TAG" -m "InnoCraft $VERSION"
  git push -f -q origin "$TAG"
else
  git tag -a "$TAG" -m "InnoCraft $VERSION"
  git push -q origin "$TAG"
fi
echo "==> push a main + tag $TAG hechos."

# --- verificar GitHub Pages ---
echo "==> esperando despliegue de GitHub Pages (~1 min)..."
for i in $(seq 1 30); do
  if [[ "$(curl -s "$PAGES_VERSION_URL")" == "$VERSION" ]]; then
    echo "✅ Publicado. Pages sirve la versión $VERSION."
    echo "   pack:    https://jandro5vq.github.io/InnoCraft/pack.toml"
    echo "   version: $PAGES_VERSION_URL"
    exit 0
  fi
  sleep 10
done
echo "⚠️  GitHub Pages aún no refleja $VERSION tras ~5 min."
echo "   El push y el tag SÍ se hicieron; comprueba en unos minutos: $PAGES_VERSION_URL"
