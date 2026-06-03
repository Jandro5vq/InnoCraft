#!/usr/bin/env bash
#
# publish.sh — publica el .mrpack más nuevo como nueva versión de InnoCraft.
#
#   ./publish.sh -c "- cambio 1
#   - cambio 2"                  # publica con changelog (sintaxis FancyMenu)
#   ./publish.sh                 # usa CHANGELOG_NEXT.md si existe; si no, error
#   ./publish.sh "msg commit"    # mensaje de commit personalizado
#   ./publish.sh --force         # republica aunque el tag ya exista (reescribe tag)
#
# El changelog debe respetar el formato de FancyMenu y caber en <=10 líneas
# tras añadirle la cabecera "^^^ # InnoCraft vX.Y.Z ^^^" (3 líneas + blanco).
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
CHANGELOG_BODY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--force) FORCE=1; shift ;;
    -c|--changelog) CHANGELOG_BODY="${2:-}"; shift 2 ;;
    *) MSG="$1"; shift ;;
  esac
done

# Fuente del changelog: -c "body"  >  fichero CHANGELOG_NEXT.md  >  error
CHANGELOG_NEXT_FILE="CHANGELOG_NEXT.md"
if [[ -z "$CHANGELOG_BODY" && -s "$CHANGELOG_NEXT_FILE" ]]; then
  CHANGELOG_BODY="$(cat "$CHANGELOG_NEXT_FILE")"
  CHANGELOG_FROM_FILE=1
fi
if [[ -z "$CHANGELOG_BODY" ]]; then
  # Patches (1.x.Y) heredan el changelog del minor: si ya existe changelog.md en el
  # repo, lo reutilizamos tal cual (no se regenera). Para forzar uno nuevo, usa -c.
  if [[ -s changelog.md ]]; then
    KEEP_CHANGELOG=1
    echo "==> reutilizando changelog.md existente (patch hereda changelog del minor)"
  else
    echo "ERROR: falta el changelog. Pásalo con  -c \"body\"  o crea $CHANGELOG_NEXT_FILE."
    exit 1
  fi
fi

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

# --- changelog.md (sintaxis FancyMenu: ^^^ centra, # encabezado, - bullets) ---
if [[ "${KEEP_CHANGELOG:-0}" == "1" ]]; then
  # Patch: conserva el body, solo refresca el número de versión del título
  sed -i -E "s/^# InnoCraft v[0-9][0-9.]*\$/# InnoCraft v$VERSION/" changelog.md
else
  {
    printf '^^^\n# InnoCraft v%s\n^^^\n\n' "$VERSION"
    printf '%s\n' "$CHANGELOG_BODY"
  } > changelog.md
fi
TOTAL_LINES="$(wc -l < changelog.md)"
if (( TOTAL_LINES > 10 )); then
  echo "⚠️  changelog.md tiene $TOTAL_LINES líneas (recomendado ≤10). Continúo igualmente."
fi
echo "==> changelog.md generado ($TOTAL_LINES líneas, recomendado ≤10)"
# si el body venía de CHANGELOG_NEXT.md, ya cumplió su función → eliminar
[[ "${CHANGELOG_FROM_FILE:-0}" == "1" ]] && rm -f "$CHANGELOG_NEXT_FILE"

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
