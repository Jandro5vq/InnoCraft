# InnoCraft

Modpack de **Fabric** para **Minecraft 1.21.1**, publicado con [packwiz](https://packwiz.infra.link/) + GitHub Pages para auto-actualización en **Prism Launcher**.

- **URL del pack:** `https://jandro5vq.github.io/InnoCraft/pack.toml`
- **Endpoint de versión (texto plano):** `https://jandro5vq.github.io/InnoCraft/version.txt` → devuelve p.ej. `1.6.0`
- **Endpoint de versión (FancyMenu markdown):** `https://jandro5vq.github.io/InnoCraft/version.md` → título centrado con `^^^`
- **Endpoint de changelog (FancyMenu markdown):** `https://jandro5vq.github.io/InnoCraft/changelog.md` → título + bullets, máx 10 líneas. Soporta `**bold**`, `%#HEX%color%#%`, `^^^...^^^` centrado, `|||...|||` derecha, `- bullets`, `---` separador. Ver [docs FancyMenu](https://docs.fancymenu.net/docs/en-US/text-formatting).
- **Repo:** https://github.com/Jandro5vq/InnoCraft

---

## Para jugadores — instalar en Prism Launcher

1. Descarga `packwiz-installer-bootstrap.jar` de las [releases del bootstrap](https://github.com/packwiz/packwiz-installer-bootstrap/releases).
2. En Prism: **Add Instance → Vanilla → Minecraft 1.21.1**, y en *Mod Loader* elige **Fabric**.
3. Click derecho en la instancia → **Folder**, y copia el `.jar` dentro de la carpeta `.minecraft/`.
4. Click derecho → **Edit → Settings → Custom commands**, marca *Custom commands* y en **Pre-launch command** pon:

   ```
   "$INST_JAVA" -jar "$INST_MC_DIR/packwiz-installer-bootstrap.jar" https://jandro5vq.github.io/InnoCraft/pack.toml
   ```

5. Lanza el juego. Cada vez que arranques, el bootstrap descarga/actualiza solo lo que haya cambiado.

---

## Para el mantenedor — publicar una nueva versión

> Este repo **no se genera con `packwiz import`** (esa orden ya no existe para `.mrpack` de Modrinth en packwiz actual). Se reconstruye desde el `.mrpack` con el script `build_packwiz.py` incluido.

### Requisitos (ya instalados en esta máquina, sin sudo)

Go y packwiz están en `~/.local/go/bin` y `~/go/bin`, pero **no en el PATH permanente**. Antes de cualquier comando packwiz:

```bash
export PATH="$HOME/.local/go/bin:$HOME/go/bin:$PATH" GOPATH="$HOME/go"
```

(Para hacerlo permanente, añade esa línea a `~/.bashrc`.)

### Opción A — automatizado con `publish.sh` (recomendado)

Exporta el `.mrpack` desde tu launcher, déjalo en la raíz del repo y ejecuta:

```bash
./publish.sh -c "- Añadido X
- Arreglado Y
- %#FFD66B%Resaltado en color%#%"
```

`publish.sh` elige el `.mrpack` más nuevo, hace reconstrucción limpia, genera `version.md`/`changelog.md` con sintaxis FancyMenu, valida (≤10 líneas), commitea, pushea, tag, y verifica que Pages sirve la nueva versión.

Alternativa: crea `CHANGELOG_NEXT.md` con el body del changelog y luego `./publish.sh` (lo consume y lo borra automáticamente).

Usa `--force` para republicar una versión cuyo tag ya existe.

### Opción B — manual desde `.mrpack` (sin `publish.sh`)

Por si quieres hacerlo paso a paso:

```bash
export PATH="$HOME/.local/go/bin:$HOME/go/bin:$PATH" GOPATH="$HOME/go"
cd "/home/alejandro/InnoCraft Git"

# 1. borrar contenido generado de la versión anterior
rm -rf mods config data fancymenu_data shaderpacks resourcepacks icon.png servers.dat pack.toml index.toml

# 2. regenerar desde el nuevo .mrpack
python3 build_packwiz.py "InnoCraft X.Y.Z.mrpack"

# 3. construir el índice
printf 'hash-format = "sha256"\n' > index.toml
packwiz refresh

# 4. verificar
packwiz list | wc -l          # == nº de mods esperado
grep -c '\.claude' index.toml # debe ser 0
grep '^version' pack.toml      # == X.Y.Z

# 5. publicar
git add -A
git commit -m "InnoCraft X.Y.Z — descripción de cambios"
git push origin main
git tag -a vX.Y.Z -m "InnoCraft X.Y.Z"
git push origin vX.Y.Z
```

Pages tarda ~40 s en desplegar. Verifica:

```bash
curl -s https://jandro5vq.github.io/InnoCraft/pack.toml | grep version
```

### Opción C — cambios sueltos sin `.mrpack`

```bash
packwiz modrinth add <slug>     # añadir un mod de Modrinth
packwiz remove <slug>           # quitar un mod
packwiz update --all            # actualizar todos
packwiz refresh                 # SIEMPRE antes de commitear
# si cambiaste la versión en pack.toml, regenera el endpoint:
grep -m1 '^version' pack.toml | sed -E 's/.*"(.*)".*/\1/' > version.txt
git add -A && git commit -m "..." && git push
```

---

## ⚠️ Notas importantes

- **El bug del 404 (`.claude/settings.local.json`):** `packwiz refresh` indexa **todos** los archivos del directorio salvo los listados en `.packwizignore` (y `pack.toml`/`index.toml`). Si un archivo local no versionado entra en `index.toml`, el bootstrap falla con `404`. El `.packwizignore` ya excluye `.claude/`, `*.mrpack`, `*.py`, `README.md`, etc. **Si vuelve a aparecer un 404, añade el archivo culpable al `.packwizignore` y repite `packwiz refresh` + push.**
- **Mods no-Modrinth:** algunos mods (p.ej. `chupachups`, `streamotes`) vienen como `.jar` sueltos dentro de `overrides/mods/` en el `.mrpack`. Se distribuyen directamente desde el repo y **no se auto-actualizan** con `packwiz update`.
- **Emojis en nombres:** `build_packwiz.py` usa un escapador TOML propio (no `json.dumps`) porque títulos como "Jade 🔍" rompen el TOML si se escapan como surrogate pairs.

---

## Estructura del repo

```
pack.toml            Configuración principal (versiones MC/Fabric, índice)
index.toml           Índice con hashes de todos los archivos (generado)
mods/*.pw.toml       Metadatos de cada mod (URL + hash + update.modrinth)
mods/*.jar           Mods no-Modrinth incluidos directamente
config/, data/, ...  Overrides (configs, fancymenu, etc.)
build_packwiz.py     Generador .mrpack → packwiz (no se distribuye)
.packwizignore       Qué NO indexar/distribuir
```
