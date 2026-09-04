# Espacio

App nativa para macOS 26 (Swift 6 + SwiftUI + Liquid Glass) que muestra qué
archivos y aplicaciones ocupan más disco y ayuda a borrarlos.

## Qué hace

- **Resumen**: anillo de uso del volumen por categoría, contadores, archivos más
  grandes y una sección de *Limpieza rápida* (cachés, DerivedData, Docker.raw,
  simuladores, npm/pnpm/brew, backups de iPhone…).
- **Aplicaciones**: inventario de `/Applications` y `~/Applications` con tamaño,
  versión y último uso. Al elegir una app busca sus restos (Application Support,
  Caches, Preferences, Containers, Saved State, Logs, LaunchAgents…) y los
  desinstala junto con la app. Si la app requiere permisos de administrador,
  delega el borrado en Finder (pide contraseña).
- **Archivos grandes**: tabla de los 2.000 archivos más pesados con filtro por
  tipo, búsqueda, y acciones (Finder, abrir, Papelera).
- **Explorador**: treemap *squarified* interactivo (clic para entrar, hover para
  detalles, clic derecho para acciones) con lista lateral. El mapa se rasteriza
  con CoreGraphics una vez por carpeta/tamaño; hover y selección son overlays.

Paleta: superficies grafito neutras, un solo acento ámbar, rojo tomate para lo
destructivo y diez tonos apagados (azul acero, ocre, oliva, terracota, teal…)
para categorías y treemap. Todo está en `Theme` y `FileCategory.color`.

Todo borrado va a la Papelera (nunca se elimina definitivamente sin pasar por ella).

## Motor de escaneo

- `getattrlistbulk(2)`: una sola llamada al sistema devuelve nombre, tipo, tamaño
  asignado, mtime e inode de cientos de entradas por directorio. Es la misma API
  que usan Finder y `du`, y evita un `stat` por archivo.
- Pool de hilos (por defecto 12) con cola LIFO compartida y descenso local: cada
  hilo sigue bajando por la última subcarpeta que leyó sin pasar por el lock.
- Tamaño *asignado* en disco (`ATTR_FILE_ALLOCSIZE`), así que archivos
  comprimidos, dispersos o de iCloud sin descargar cuentan lo que ocupan de verdad.
- Hard links contados una sola vez; no cruza a otros volúmenes (usa el device id)
  y salta `/System/Volumes` para no contar dos veces el volumen de datos
  (firmlinks).
- Los archivos menores a 64 KB se agrupan en un nodo por carpeta para mantener la
  memoria plana: ~270 MB de RSS con 5 M de archivos.

Medido en esta Mac: 5,0 M de archivos / 928 K carpetas / 435 GB en ~26-32 s con
caché fría; `~/Documents` (1,7 M archivos) en 6 s contra 30 s de `du -s`.

## Compilar

Sin Xcode project (SwiftPM + script de empaquetado):

```bash
./scripts/build-app.sh          # deja build/Espacio.app firmada ad-hoc
open build/Espacio.app
```

Con Xcode:

```bash
xcodegen generate               # brew install xcodegen
open Espacio.xcodeproj
```

Modo benchmark del motor (sin UI):

```bash
.build/release/Espacio --bench ~/Documents
```

Capturas automáticas para verificar la UI (recorre las secciones, guarda
`<sección>-real.png` con `screencapture -l` y sale):

```bash
ESPACIO_SNAPSHOT_DIR=/tmp/snap ESPACIO_ROOT=/Applications ESPACIO_SNAPSHOT_APP=Docker build/Espacio.app/Contents/MacOS/Espacio
```

Otras variables: `ESPACIO_SNAPSHOT_ONLY=explorer`, `ESPACIO_SNAPSHOT_RETINA=1`,
`ESPACIO_TRACE=1` (trazas de arranque en stderr), `ESPACIO_THREADS=n`.

## Permisos

- **Acceso total al disco**: sin él, macOS bloquea la lectura de `~/Library/Mail`,
  Safari, Mensajes, etc. La app avisa cuántas carpetas no pudo leer y abre el
  panel de Privacidad. Como la firma es ad-hoc, cada compilación nueva cambia el
  hash y hay que volver a activar el permiso.
- **Automatización (Finder)**: solo se pide si hay que mover a la Papelera algo que
  el usuario actual no puede mover (apps instaladas con `.pkg`, propiedad de root).

## Estructura

```
Sources/Espacio/
  Scanner/   FSNode, DiskScanner (getattrlistbulk + pool), TopFiles (heap)
  Apps/      AppInventory (apps, restos)
  Services/  TrashService (Papelera, Finder, Finder reveal)
  Support/   ByteFormat, FileCategory
  App/       AppState (modelo @Observable), EspacioApp, Bench, Snapshot
  UI/        Overview, Apps, LargestFiles, Explorer + Treemap, Components
scripts/     build-app.sh, make-icon.swift
Resources/   Info.plist, AppIcon.icns
```
