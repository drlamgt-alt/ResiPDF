# ResiPDF — lector y subrayador de PDF para iPad

App nativa para iPad (mini, normal, Air y Pro, iPadOS 17 o superior) hecha con SwiftUI + PDFKit, pensada para **residentes de cirugía**.

## Funciones

**Marcado**
- **Abre el PDF sin importarlo.** Lo eliges en Archivos (iCloud Drive, En mi iPad, Drive…) y los cambios **se guardan solos en ese mismo archivo**. Las marcas son PDF estándar: también se ven en Adobe, Preview o GoodNotes.
- **Perfiles de color**: Cirugía, Anatomía quirúrgica, Clínico y Mínimo. Cada perfil tiene hasta 9 marcadores (color + estilo + significado) y se cambia con 🎨.
- El resaltado, subrayado, tachado o recuadro **se ajusta a las palabras**, aunque el trazo salga torcido. En PDF escaneados se dibuja un trazo recto.
- Otras herramientas: lápiz libre, **flecha**, **círculo/óvalo**, **comentario** (escrito a mano con Scribble), **sellos** (Q, Dx, Tx, Cx, Qx, ⭐, ❓…) y borrador.
- **Tapas de autoevaluación**: tapas etiquetas, cifras o pasos quirúrgicos y un toque las destapa. 👁 tapa o destapa todas a la vez. Al guardar siempre quedan tapadas.

**Velocidad**
- **Solo el Pencil anota.** El dedo desplaza y hace zoom, así que puedes apoyar la palma.
- **Paleta para la mano izquierda**: se arrastra y se pega al borde. Se puede plegar y tiene 3 tamaños de botón.
- **Modo resorte**: si **mantienes pulsado** un color con el pulgar mientras marcas, al soltar vuelves al color anterior.
- **Rueda de colores junto al lápiz**: al apretar el Pencil Pro, o con doble toque si lo configuras.
- Doble toque del Pencil: vuelve a la herramienta anterior (configurable).
- **Toque con 2 dedos = deshacer**, con 3 dedos = rehacer.
- **Vuelta automática al marcador** después de una flecha, círculo, sello o comentario.
- Teclado: **1–9** cambian de marcador y **⌘F** busca.

**Repaso**
- **Buscar** texto o **ir a página**.
- **Lista de anotaciones** filtrable por significado o por sello. Por ejemplo: todas las «Pregunta de examen» o todos los sellos «Q».
- **Exportar resumen** en Markdown, listo para Anki o Notas.

---

## Instalar SIN App Store y SIN conectar el iPad a una computadora

Una app de iPad tiene que compilarse en un Mac. Aquí lo hace **GitHub** por ti, gratis. Hay dos caminos:

| | **A. TestFlight** (recomendado) | **B. SideStore** (gratis) |
|---|---|---|
| Costo | Apple Developer: 99 USD/año | Gratis |
| ¿Necesita computadora? | **Nunca** | **Solo una vez**, para la configuración inicial |
| Caducidad | Cada compilación dura 90 días; con cada actualización se renueva | 7 días; se renueva **desde el iPad** con un toque |
| Actualizaciones | Llegan solas a la app TestFlight | Desde SideStore (fuente `apps.json`) |
| Revisión de Apple | No (pruebas internas) | No |

### A. TestFlight: todo desde el iPad (Safari)

1. Inscríbete en **Apple Developer Program** en developer.apple.com (99 USD/año).
2. En **App Store Connect** (appstoreconnect.apple.com):
   - **Apps → ＋ Nueva app**, plataforma iOS.
   - Elige un **Bundle ID** propio (ej. `com.tunombre.resipdf`).
   - **No hace falta publicarla.**
3. App Store Connect → **Usuarios y acceso → Integraciones → Claves de API de App Store Connect**. Crea una clave con rol **Administrador** y apunta su *Key ID* y el *Issuer ID*. Descarga el `.p8`.
4. En **GitHub** (también desde Safari), en tu repositorio → **Settings → Secrets and variables → Actions**:
   - Variables: `BUNDLE_ID`, `TEAM_ID`.
   - Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (abre el `.p8` y pega todo su texto).
5. GitHub → **Actions → TestFlight → Run workflow**. En unos 10 min la compilación aparece en App Store Connect → TestFlight.
6. En App Store Connect → TestFlight → **Pruebas internas**, añádete como probador.
7. Instala la app **TestFlight** del App Store en el iPad y abre ResiPDF desde ahí. Las nuevas versiones te llegan solas.

### B. SideStore: gratis, se renueva desde el iPad

👉 **Guía completa paso a paso: [SIDESTORE.md](SIDESTORE.md)**. Lo que sigue es solo el resumen.

1. **Una sola vez con una computadora** (puede ser la de un amigo): sigue la guía oficial de **docs.sidestore.io**, que instala SideStore y genera el archivo de emparejamiento.
2. Desde entonces todo es en el iPad:
   - En Safari abre `https://github.com/TU_USUARIO/ResiPDF/releases/latest`, toca **ResiPDF.ipa** y ábrelo con SideStore.
   - O mejor, en SideStore → **Fuentes → ＋**, añade `https://github.com/TU_USUARIO/ResiPDF/releases/download/latest/apps.json`. Así cada versión nueva aparece como actualización.
3. Cada 7 días abre SideStore y toca **Refresh**. Tus PDF y anotaciones no se pierden porque están en Archivos.

> Para que los enlaces de descarga funcionen sin iniciar sesión, el repositorio debe ser **público**. El código no contiene datos personales.

### Subir el código a GitHub

1. Crea el repositorio `ResiPDF` en github.com.
2. Desde esta carpeta, en PowerShell:
   ```powershell
   git init
   git add .
   git commit -m "ResiPDF"
   git branch -M main
   git remote add origin https://github.com/TU_USUARIO/ResiPDF.git
   git push -u origin main
   ```
3. Cada `push` compila y publica una versión nueva en **Releases** (workflow *Build IPA*).

> ⚠️ El código **no se ha compilado todavía**: lo escribí desde Windows. La primera compilación en GitHub Actions es la prueba. Si sale en rojo, descarga **build-log** y pásamelo.

---

## Limitaciones conocidas
- Los PDF **muy grandes** (cientos de MB) pueden tardar unos segundos en autoguardarse.
- La búsqueda en libros de miles de páginas puede tardar unos segundos.
- Los PDF protegidos con contraseña no se abren.

## Estructura
```
project.yml                         definición del proyecto (XcodeGen)
.github/workflows/build-ipa.yml     compila .ipa + Releases + fuente SideStore
.github/workflows/testflight.yml    firma y sube a TestFlight
ResiPDF/App                         entrada (DocumentGroup)
ResiPDF/Document                    lectura/escritura del PDF original
ResiPDF/Editor                      PDFView, motor del Pencil, paleta, rueda, búsqueda
ResiPDF/Annotations                 lista, filtros y exportación
ResiPDF/Settings                    preferencias, perfiles y marcadores
ResiPDF/Model                       perfiles, ajustes, tapas, colores
```
