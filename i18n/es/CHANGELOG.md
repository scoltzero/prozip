# Registro de cambios

[English](../../CHANGELOG.md) · [简体中文](../zh-CN/CHANGELOG.md) · [繁體中文](../zh-TW/CHANGELOG.md) · [日本語](../ja/CHANGELOG.md) · [한국어](../ko/CHANGELOG.md) · **Español** · [Français](../fr/CHANGELOG.md) · [Deutsch](../de/CHANGELOG.md) · [Русский](../ru/CHANGELOG.md)

Todos los cambios notables en **ProZip** se documentarán en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y este proyecto se adhiere al [Versionado Semántico](https://semver.org/lang/es/).

---

## [0.1.5] - 2026-11-23

### Añadido
- **Actualización automática integrada (descarga, verificación y reinicio)**:
  - Se añadió el botón de un clic **Actualizar ahora** dentro del diálogo Buscar actualizaciones para que los usuarios ya no tengan que descargar e instalar manualmente desde el navegador.
  - Descarga en flujo el paquete `.zip` desde GitHub Releases mostrando el progreso en directo, verifica `SHA256SUMS.txt` mediante `CryptoKit` y valida `CFBundleIdentifier`, extrae con `/usr/bin/ditto`, reemplaza `ProZip.app` de forma atómica (con reversión automática en caso de fallo y solicitud de permisos de administrador cuando es necesario) y reinicia la aplicación automáticamente.

### Corregido y modificado
- **Icono monocromo de plantilla en la barra de menús y alineación del panel**:
  - Se sustituyó el icono en color de la barra de menús por un icono de plantilla de macOS independiente de la resolución (`isTemplate = true`) que conserva únicamente la **P** de la marca y su sombra al 33 % de opacidad, adaptándose automáticamente al modo claro y oscuro.
  - Se ajustó el margen superior del panel de la bandeja en la barra de menús y se ancló al borde inferior de la barra de menús para eliminar la separación excesiva, manteniendo alineada la vista previa en Ajustes.
- **Progreso de extracción en tiempo real**: Se habilitó la transmisión de progreso de extracción en directo para archivos RAR divididos en volúmenes y todos los formatos compatibles.

---

## [0.1.4] - 2026-11-21

### Añadido
- **Preferencia para mostrar u ocultar en el Dock**: Se añadió la opción **Mostrar en el Dock** en Ajustes → General → Inicio, que cambia `NSApplication.ActivationPolicy` (`.regular` / `.accessory`) en vivo sin reiniciar y conservando el foco de la ventana activa; además, se incorporó un acceso rápido **Ajustes…** al menú contextual (clic secundario) de ProZip Box en la barra de menús, con localizaciones en chino simplificado, chino tradicional e inglés.
- **Limpieza detallada de la cola de tareas y ventana independiente redimensionable de creación**:
  - Se añadieron botones para descartar tareas individuales, **Limpiar finalizadas** (incluidas las tareas fallidas) y **Limpiar todo** en `ArchiveProgressWindowView`.
  - Se alojó `ArchiveCreationDialogView` en una ventana independiente redimensionable con memoria de dimensiones, convirtiendo las filas de limpieza y compatibilidad del resumen en controles directamente interactivos.

### Modificado
- **Recuperación de memoria en reposo y cero activaciones en segundo plano**:
  - Se vinculó la rotación de titulares de `ProZipLandingView` a `isWindowActive` para que las ventanas en segundo plano, sin foco o minimizadas pausen de inmediato el bucle de animación con cero activaciones de CPU en reposo.
  - Se liberan las jerarquías `NSHostingView` y los búferes gráficos al cerrar la ventana de bienvenida, la ventana de Ajustes (conservando el tamaño recordado), el panel de la bandeja de la barra de menús, el panel de progreso de tareas y las ventanas de alerta; además, se evita materializar anticipadamente la ventana de bienvenida cuando ya existe una sesión de archivo activa.
  - Se convirtió `ProZipResourceImageLoader` en un `NSCache` con límite de coste (que se vacía al cerrar la ventana de Ajustes) y se rasterizó el icono de estado de la barra de menús a `18×18` en lugar de retener el mapa de bits original completo de `512×512`.
- **Progreso de compresión en flujo en tiempo real y precalentamiento de motores**: Se añadió notificación de progreso por bloques de 512 KiB en `NativeZipEngine` y transmisión de progreso en directo con `-bsp1` en `SevenZipEngine` (reenviando el número de hilos `-mmt` configurado y las exclusiones `-xr!.DS_Store/__MACOSX/._*`), junto con precalentamiento de motores en segundo plano fuera de `@MainActor`.

---

## [0.1.3] - 2026-11-14

### Añadido
- **Conmutación con barra espaciadora en el Finder para ProZip Mini**: Se añadió `FinderSpacebarMonitor` mediante permisos de Accesibilidad y Automatización (`AppleEvents`) de macOS para que pulsar la barra espaciadora en el Finder sobre un archivo compatible abra directamente ProZip Mini, y volver a pulsarla dentro de Mini cierre la ventana y devuelva el foco al Finder; configurable con asistente de permisos y selectores de formatos en Ajustes → ProZip Mini.
- **Recuperación de autorización del Llavero y restablecimiento de respaldo para la libreta de contraseñas**: Conserva las bóvedas cifradas existentes cuando un binario de código abierto o re-firmado ad-hoc invalida las listas ACL heredadas del Llavero (Keychain); se añadió **Autorizar y recuperar libreta de contraseñas** (solicita permiso una sola vez mediante el diálogo del Llavero del sistema, descifra las entradas guardadas y rota a una nueva clave vinculada a la firma actual de la app para futuros inicios silenciosos) junto con la opción de respaldo en dos pasos **Restablecer y reconstruir libreta de contraseñas** en Ajustes → Libreta de contraseñas y en el diálogo de protección.

### Modificado
- **Tamaño del archivo en la cabecera de ProZip Mini**: Se actualizó el subtítulo de la ventana Mini para mostrar tanto el número de elementos como el tamaño formateado del archivo comprimido.
- **Gestión de compilaciones ad-hoc para desbloqueo rápido con Touch ID**: Desactiva de forma elegante el selector de desbloqueo rápido con Touch ID en compilaciones sin un Team ID de Apple, manteniendo intacta la implementación completa de Data Protection Keychain para futuras compilaciones comerciales firmadas.
- **GIF interactivo de demostración en el README**: Se añadió `Resources/ProZip-Demo.gif` en [README.md](README.md) para mostrar los modos de interfaz y los flujos de trabajo.

### Corregido
- Se corrigió un problema por el que arrastrar la cabecera, el pie o el área de fondo de la hoja de opciones de creación de archivos (`ArchiveCreationDialogView`) no movía la ventana anfitriona (resolución de la cadena de ventanas padre en `WindowDragArea.resolveRootWindow` + seguimiento de arrastre del ratón).
- Se corrigió un fallo por el que la barra espaciadora no cerraba la ventana de ProZip Mini tras abrirla mediante la vista previa con barra espaciadora desde el Finder.

---

## [0.1.2] - 2026-11-12

### Añadido
- **Servicio de actualización automática con GitHub Releases e integración en la interfaz**: Se introdujo `AppUpdateService` para consultar la API de GitHub Releases, comparar versiones semánticas, mostrar resúmenes de notas de versión y abrir enlaces directos de descarga `.dmg` / `.zip`, integrado en el diálogo Buscar actualizaciones, el panel Ajustes → Acerca de y las comprobaciones silenciosas al iniciar limitadas a cada 24 horas.
- **Sistema de diseño Liquid Glass nativo para macOS 26+**: Se crearon modificadores Liquid Glass unificados en formato cápsula, circular y de esquinas continuas impulsados por `.glassEffect` y `GlassEffectContainer` nativos, con alternativas esmeriladas graduales para macOS 14–15.

### Modificado
- **Refracción óptica y pulido de interacción en la ventana Mini**:
  - Se calibró la refracción de bordes Liquid Glass de la ventana Mini, el radio continuo de esquina de `20pt` y la translucidez sobre fondos claros y oscuros, eliminando artefactos en los marcos de las esquinas.
  - Se actualizaron los controles circulares inferiores izquierdos (Cerrar, Fijar con halo azul cielo y Expandir) y la cápsula inferior derecha `Vista previa + Extraer todo` a Liquid Glass interactivo nativo con tinte suave por segmento al pasar el cursor y respuesta direccional de lente al pulsar.
  - Se hizo transparente el carril de desplazamiento vertical de Mini y se refinó la máscara inferior de desvanecimiento progresivo.
- **Actualización a Liquid Glass en el espacio de trabajo y la ventana de bienvenida**:
  - Se actualizaron a Liquid Glass nativo la cápsula superior derecha de cambio de vista, los botones circulares Eliminar/Guardar/Buscar (incluido el botón de cristal carmesí activo Eliminar y la barra de búsqueda desplegada), la píldora de ruta de navegación y la barra de acciones inferior izquierda.
  - Se eliminaron el velo blanco estático inferior y los divisores verticales redundantes en el modo Espacio de trabajo para que las filas de archivos desplazadas se refracten directamente a través de la cápsula flotante Liquid Glass.
  - Se refinaron el borde luminoso de cristal del botón principal de Flow y el indicador de tarjeta apilada asomando, desplegando suavemente la acción secundaria `Extraer` al pasar el cursor.
  - Se unificaron los controles `Abrir archivo`, `Crear archivo` y `Ajustes` de la ventana de bienvenida con Liquid Glass nativo.

### Corregido
- Se corrigió un problema por el que las insignias de atajos de teclado (`⏎` / `Espacio`) dentro de la cápsula de acciones inferior del espacio de trabajo se mostraban en blanco sobre blanco al pasar el cursor.

---

## [0.1.0] - 2026-11-12

### Añadido
- **Primera publicación de código abierto (GPL-3.0)**:
  - Arquitectura de motor de archivos de cuatro niveles que combina `NativeZipEngine` (lector ZIP puro en Swift sin copias), 7-Zip (LZMA2 multihilo), `libarchive` del sistema y montaje de imágenes de disco con `hdiutil`.
  - Indexación jerárquica de entradas de alta velocidad en SQLite (`EntryIndex`) para explorar y buscar al instante en archivos de gran tamaño.
  - Flujo de trabajo de modo dual con cambio fluido (`⌥⌘M`) entre el espacio de trabajo multivista de `1040×740` (Iconos, Lista, Columnas) y el explorador compacto Mini de `560×422`.
  - Motor de recomendaciones Flow sensible al contexto (instalación de paquetes de aplicaciones, instalación de tipos de letra, apertura directa segura mediante lista blanca y extracción con un clic).
  - Bandeja persistente en la barra de menús (Shelf) para reunir archivos arrastrados desde múltiples orígenes, explorar carpetas y archivos comprimidos en línea, y comprimir o extraer por lotes.
  - Libreta de contraseñas local cifrada con AES-GCM respaldada por el Llavero (Keychain) de macOS, desbloqueo con Touch ID y coincidencia automática de contraseñas.
  - Extensión integrada de menú contextual del Finder (`ProZipFinderSync`) y extensión de Vista rápida (`ProZipQuickLook`).

[0.1.5]: https://github.com/scoltzero/prozip/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/scoltzero/prozip/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/scoltzero/prozip/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/scoltzero/prozip/compare/v0.1.0...v0.1.2
[0.1.0]: https://github.com/scoltzero/prozip/releases/tag/v0.1.0
