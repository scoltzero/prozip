<p align="center">
  <img src="../../Resources/AppIcon-Preview.png" alt="Logo de ProZip" width="160">
</p>

<h1 align="center">ProZip</h1>

<p align="center">
  <strong>Un gestor de archivos comprimidos de código abierto moderno, elegante y de alto rendimiento para macOS</strong><br>
  Desarrollado con Swift y SwiftUI nativos · Arquitectura de cuatro motores · Indexación instantánea con SQLite · Integración profunda con el sistema
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="../zh-CN/README.md">简体中文</a> ·
  <a href="../zh-TW/README.md">繁體中文</a> ·
  <a href="../ja/README.md">日本語</a> ·
  <a href="../ko/README.md">한국어</a> ·
  <strong>Español</strong> ·
  <a href="../fr/README.md">Français</a> ·
  <a href="../de/README.md">Deutsch</a> ·
  <a href="../ru/README.md">Русский</a>
</p>

<p align="center">
  <a href="https://github.com/scoltzero/prozip/stargazers"><img src="https://img.shields.io/github/stars/scoltzero/prozip?style=flat-square&logo=github&label=Stars" alt="GitHub Stars"></a>
  <a href="https://github.com/scoltzero/prozip/forks"><img src="https://img.shields.io/github/forks/scoltzero/prozip?style=flat-square&logo=github&label=Forks" alt="GitHub Forks"></a>
  <a href="https://github.com/scoltzero/prozip/releases"><img src="https://img.shields.io/github/downloads/scoltzero/prozip/total?style=flat-square&label=Downloads" alt="GitHub Downloads"></a>
  <a href="https://github.com/scoltzero/prozip/releases/latest"><img src="https://img.shields.io/github/v/release/scoltzero/prozip?style=flat-square&label=Release" alt="Latest Release"></a>
  <a href="https://developer.apple.com/macos/"><img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="Platform macOS 14+"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/github/license/scoltzero/prozip?style=flat-square&label=License" alt="License"></a>
</p>

<p align="center">
  <a href="https://github.com/scoltzero/prozip/releases/latest"><img src="https://img.shields.io/badge/Download-Latest%20Release-0969DA?style=for-the-badge&logo=github&logoColor=white" alt="Descargar la última versión"></a>
  <a href="#inicio-rápido"><img src="https://img.shields.io/badge/Guide-Quick%20Start-334155?style=for-the-badge&logo=readthedocs&logoColor=white" alt="Inicio rápido"></a>
  <a href="https://github.com/scoltzero/prozip/issues"><img src="https://img.shields.io/badge/Feedback-Issues-2EA44F?style=for-the-badge&logo=github&logoColor=white" alt="Comentarios e incidencias"></a>
</p>

<p align="center">
  <img src="../../Resources/ProZip-Demo.gif" alt="Demostración de interfaz y funciones de ProZip" width="920">
</p>

> [!IMPORTANT]
> **Posicionamiento y propósito del proyecto**:
> ProZip es un proyecto independiente y completamente de código abierto creado con fines de aprendizaje, investigación y exploración técnica de la arquitectura moderna de escritorio en macOS, el diseño de interacción híbrido con SwiftUI + AppKit, las canalizaciones de transmisión de archivos entre motores y la ingeniería de software de sala limpia (*clean-room*).
>
> Este software está destinado únicamente al intercambio técnico y a fines educativos, y no pretende competir con ningún software comercial de compresión del mercado. Cada línea de código ha sido escrita de forma independiente desde cero, sin código fuente comercial descompilado ni recursos no autorizados, y se publica bajo la licencia [GNU General Public License v3.0](../../LICENSE). Invitamos cordialmente a otros desarrolladores de macOS y colaboradores de código abierto a explorarlo, debatirlo y mejorarlo juntos.

---

## Por qué elegir ProZip

| Función principal | Descripción |
|---|---|
| **Rendimiento y acabado nativos** | Desarrollado íntegramente en Swift y SwiftUI con jerarquía visual nativa de macOS, óptica Liquid Glass y respuesta táctil fluida. |
| **Sinergia de cuatro motores** | Combina `NativeZipEngine` (lectura directa sin copias), 7-Zip (LZMA2 multihilo), `libarchive` del sistema y montaje de imágenes de disco mediante `hdiutil`. |
| **Indexación instantánea de doble tabla en SQLite** | Construye una base de datos de índice jerárquico local al abrir un archivo: expande, filtra y extrae selectivamente decenas de miles de entradas en milisegundos. |
| **Espacio de trabajo flexible de modo dual** | Alterna sin interrupciones (`⌥⌘M`) entre el espacio de trabajo multicolumna completo de `1040×740` y el explorador Mini esmerilado compacto de `560×422`. |
| **Flujo inteligente sensible al contexto (Flow)** | Inspecciona automáticamente el contenido del archivo (apps, tipos de letra, documentos, etc.) y recomienda acciones contextuales como **Instalar en Aplicaciones**, **Instalar tipo de letra** o apertura directa. |
| **Bandeja temporal en la barra de menús (ProZip Box)** | Zona de arrastre siempre disponible en la barra de menús para reunir archivos de distintas carpetas, explorar directorios en línea y comprimir por lotes con un clic. |
| **Libreta de contraseñas segura y Touch ID** | Bóveda local cifrada con AES-GCM protegida por el Llavero (Keychain) de macOS y Touch ID, con rotación automática de múltiples contraseñas al desbloquear archivos. |
| **Extensiones profundas del sistema** | Incluye una extensión de menú contextual para el Finder (`FinderSync`) y un módulo de Vista rápida (`Quick Look`) instantánea con la barra espaciadora. |

---

## Matriz de formatos compatibles

| Categoría | Formatos y capacidades compatibles |
|---|---|
| **Extracción y exploración** | ZIP, 7Z, RAR (v4 / v5 / multivolumen), TAR, GZ, TGZ, BZ2, TBZ2, XZ, TXZ, ZST, TZST, CPIO, CAB, ISO, DMG y más |
| **Creación de archivos** | ZIP (nivel de compresión Deflate configurable, cifrado AES-256, volúmenes divididos), 7Z (alta relación LZMA2, cifrado de cabeceras, volúmenes divididos), TAR |
| **Edición y guardado in situ** | Añade, elimina y renombra entradas directamente dentro de archivos existentes de un solo volumen mediante transacciones atómicas y protección de reversión automática |

---

## Requisitos del sistema

- **Sistema operativo**: macOS 14.0 (Sonoma) o posterior
- **Arquitectura**: Compatibilidad nativa con Apple Silicon (serie M) e Intel (`x86_64`)
- **Privacidad y entorno**: Ejecución 100 % local sin conexión; sin rastreo de red, telemetría ni analíticas remotas activadas por omisión

---

## Inicio rápido

### 1. Descargar una versión precompilada
Visita la página de la [última versión (Latest Release)](https://github.com/scoltzero/prozip/releases/latest) para descargar `ProZip-v0.1.5-macos.dmg` o `ProZip-v0.1.5-macos.zip` (consulta [CHANGELOG.md](CHANGELOG.md) para ver las notas de la versión).

### 2. Instalar e iniciar
1. Abre la imagen de disco `.dmg` y arrastra `ProZip.app` a la carpeta `Applications` (Aplicaciones).
2. Haz doble clic para abrir ProZip. Si macOS muestra un aviso de desarrollador no identificado, ve a **Ajustes del Sistema → Privacidad y seguridad** y haz clic en **Abrir igualmente**.
3. Sigue el asistente de bienvenida en el primer inicio para activar la extensión del Finder y el módulo de Vista rápida (`Quick Look`) según prefieras.

---

## Arquitectura

ProZip adopta una arquitectura limpia en capas que desacopla la presentación de la interfaz, el estado de sesión, la indexación de entradas y los motores de compresión de bajo nivel:

```text
┌─────────────────────────────────────────────────────────────┐
│              ProZip App & Extensions Layer                  │
│   (WorkspaceWindowView / MiniWindowView / MenuBarShelf)     │
│   (ProZipFinderSync Extension / ProZipQuickLook Plugin)     │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                    ProZipUI & ViewModels                    │
│   - AppViewModel (Orquestación de sesión y decisiones Flow) │
│   - ProZipTheme (Estilo nativo, color y animación fluida)   │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                    ProZipCore Engine Layer                  │
│   - ArchiveBrowsingSession (Ciclo de sesión y preparación)  │
│   - EntryIndex (Índice SQLite veloz de carpetas y entradas) │
│   - PasswordBook (Bóveda AES-GCM + Llavero + Touch ID)      │
│   - ManagedTemporaryArtifactRegistry (Gestión temporal)     │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                   Archive Engine Broker                     │
│   ├─ NativeZipEngine   : Lectura/escritura directa en Swift │
│   ├─ SevenZipEngine    : 7-Zip LZMA2 / AES / multiformato   │
│   ├─ LibarchiveEngine  : Flujo libarchive del sistema       │
│   └─ DiskImageEngine   : Montaje de imágenes con hdiutil    │
└─────────────────────────────────────────────────────────────┘
```

---

## Compilación desde el código fuente

ProZip se gestiona con Swift Package Manager e incluye scripts automatizados de empaquetado:

### Requisitos previos
- macOS 14.0+ con Xcode 15+ o las herramientas de línea de comandos de Xcode instaladas
- `7zz` instalado mediante Homebrew (utilizado para empaquetar el subconjunto integrado del motor 7-Zip):
  ```bash
  brew install sevenzip
  ```

### Pasos de compilación
1. **Clonar el repositorio**:
   ```bash
   git clone https://github.com/scoltzero/prozip.git
   cd prozip
   ```

2. **Compilar los módulos principales de Swift**:
   ```bash
   swift build -c release
   ```

3. **Empaquetar el paquete completo `.app` para macOS** (incluidas las extensiones Finder Sync y Vista rápida):
   ```bash
   bash scripts/build_app.sh release
   ```
   Al finalizar, el paquete de la aplicación estará disponible en `build/ProZip.app`.

---

## Implementación independiente y declaración de código abierto

<details>
<summary><strong>Haz clic para desplegar la filosofía de diseño y los límites de sala limpia</strong></summary>

1. **Propósito de investigación y aprendizaje**:
   ProZip nació para explorar las fronteras de la ingeniería moderna de interfaces gráficas de escritorio en macOS. Durante el desarrollo estudiamos patrones de interacción, cadencia de animaciones, enrutamiento multimotor y canalizaciones de flujo en las principales utilidades de archivos de la industria, y luego diseñamos e implementamos todo de forma independiente en Swift y SwiftUI puros.

2. **Ingeniería de sala limpia (Clean-Room)**:
   Este repositorio no contiene código fuente descompilado, recursos protegidos ni certificados privados de ningún software propietario. Toda la lógica de negocio, las estructuras de datos y las vistas de interfaz se han escrito desde cero siguiendo principios de ingeniería de sala limpia.

3. **Intercambio abierto y finalidad no comercial**:
   Este proyecto se publica como código abierto para fomentar el intercambio técnico entre desarrolladores interesados en aplicaciones de escritorio para macOS, procesamiento de flujos del sistema de archivos e interoperabilidad nativa entre C y Swift. Respetamos profundamente la propiedad intelectual y el trabajo artesanal de todos los autores de software comercial, y este repositorio no pretende sustituir ningún producto comercial.

</details>

---

## Créditos y agradecimientos

ProZip se apoya en infraestructuras y bibliotecas de código abierto excepcionales. Nuestro sincero agradecimiento a los mantenedores de estos proyectos:

| Proyecto | Función y contribución | Licencia |
|---|---|---|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | Base nativa en Swift para análisis y lectura/escritura en flujo de archivos ZIP | MIT |
| [7-Zip / p7zip](https://www.7-zip.org/) | Compresión 7z, LZMA2 y motor de extracción multiformato | LGPL-2.1+ / unRAR License |
| [libarchive](https://www.libarchive.org/) | Capa de compatibilidad de archivos en flujo multiformato | BSD |
| [libdeflate](https://github.com/ebiggers/libdeflate) | Referencia de compresión Deflate / zlib de alto rendimiento | MIT |

---

## Soporte y comunidad

Si disfrutas usando ProZip o te resulta útil para aprender o en tu flujo de trabajo diario:
- ¡Dale una **Star** ⭐️ al repositorio en GitHub para mostrar tu apoyo!
- ¿Has encontrado un fallo o tienes una idea? ¡No dudes en abrir un [Issue](https://github.com/scoltzero/prozip/issues) o enviar un Pull Request!

---

## Licencia

El código fuente principal de ProZip se distribuye bajo la licencia **[GNU General Public License v3.0](../../LICENSE)** (GPL-3.0).  
Los componentes de código abierto de terceros referenciados siguen rigiéndose por sus respectivas licencias originales.
