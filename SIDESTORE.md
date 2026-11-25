# Instalar ResiPDF con SideStore (gratis)

Necesitas la computadora **una sola vez** (fase 2). Después todo se hace en el iPad.

> Pasos basados en la documentación oficial (docs.sidestore.io, noviembre de 2026). SideStore está en beta pública y a veces cambia. Si algo no coincide, manda la guía oficial.

---

## Fase 1: subir ResiPDF a GitHub (en la PC, unos 10 min)

GitHub compila la app en un Mac gratis y deja un enlace de descarga.

1. Crea una cuenta en **github.com**.
2. Activa la privacidad del correo: **Settings → Emails → «Keep my email addresses private»**. Copia la dirección `…@users.noreply.github.com` que aparece ahí.
3. Crea un repositorio nuevo: **＋ → New repository**.
   - Nombre: `ResiPDF`.
   - Tipo: **Public**, para que el iPad pueda descargar sin iniciar sesión.
   - No marques «Add README».
4. En PowerShell, dentro de la carpeta `ResiPDF` (el repositorio git ya está preparado), ejecuta:
   ```powershell
   git config user.name "TU_USUARIO_GITHUB"
   git config user.email "TU_NUMERO+TU_USUARIO@users.noreply.github.com"
   git commit -m "ResiPDF"
   git remote add origin https://github.com/TU_USUARIO_GITHUB/ResiPDF.git
   git push -u origin main
   ```
   Si te pide iniciar sesión, se abre el navegador para autorizar.
5. En GitHub abre **Actions** (si te lo pregunta, actívalas) y espera a que «Build IPA» quede en ✅ verde (5–10 min).
   - Si sale ❌ rojo, abre la ejecución, descarga **build-log** y pásamelo.
6. Comprueba que en **Releases → «ResiPDF (última versión)»** aparecen `ResiPDF.ipa` y `apps.json`.

---

## Fase 2: instalar SideStore (en la PC, una sola vez, unos 20 min)

**En el iPad primero:**
1. Pon un **código de desbloqueo** (es obligatorio).
2. Instala **LocalDevVPN** desde el App Store. Ábrela, toca **Connect** y acepta «Permitir configuraciones VPN».

**En la PC (Windows 10/11 de 64 bits):**
1. Instala **iTunes**. La documentación recomienda la versión de la web de Apple (apple.com/itunes/download/win64) en lugar de la de Microsoft Store. Si no funciona, prueba la app **Apple Devices** de Microsoft Store.
2. Instala **iloader**, el instalador de SideStore: github.com/nab138/iloader/releases. Descarga `iloader-windows-x64.msi`.
3. Conecta el iPad por cable, toca **Confiar** y escribe el código.
4. En iloader:
   - Inicia sesión con un Apple ID. Puede ser uno **secundario** creado solo para esto, y distingue mayúsculas.
   - Elige tu iPad.
   - Pulsa **Install SideStore (Stable)**.

**De nuevo en el iPad:**
1. **Ajustes → General → VPN y gestión de dispositivos →** toca tu Apple ID → **Confiar** (en iPadOS 18: «Permitir y reiniciar»).
2. **Ajustes → Privacidad y seguridad →** al final, **Modo de desarrollador → Activar**. El iPad se reinicia.
3. Abre **LocalDevVPN → Connect**.
4. Abre **SideStore** e inicia sesión con el **mismo Apple ID** que usaste en iloader.
5. Ve a **My Apps** y toca el contador **«7 DAYS»** junto a SideStore para refrescarlo. Si pregunta por el certificado, responde **Sí / Refresh Now**. Hazlo **antes** de instalar cualquier otra app.

✅ Desde aquí ya **no necesitas la computadora**.

---

## Fase 3: instalar ResiPDF (solo en el iPad)

**Opción A: como fuente (recomendada, recibes actualizaciones)**
1. Con **LocalDevVPN conectada**, abre Safari y escribe:
   ```
   sidestore://source?url=https://github.com/TU_USUARIO_GITHUB/ResiPDF/releases/download/latest/apps.json
   ```
   Si no funciona, en SideStore ve a **Sources → ＋** y pega la URL que va después de `url=`.
2. Abre la fuente **ResiPDF** y pulsa **Get / Install**.
3. Cada vez que subas cambios a GitHub, la versión nueva aparece como actualización en SideStore.

**Opción B: el archivo directamente**
1. En Safari abre `github.com/TU_USUARIO_GITHUB/ResiPDF/releases/latest` y descarga **ResiPDF.ipa**.
2. En SideStore ve a **My Apps → ＋** y elige el `.ipa` en Archivos.

---

## Mantenimiento: cada semana (30 segundos)

- La firma gratuita dura **7 días**. SideStore intenta refrescar solo en segundo plano, pero requiere la **VPN activa**.
- **Rutina segura:** un día fijo a la semana (por ejemplo, el domingo):
  1. Abre LocalDevVPN y conéctala.
  2. Abre SideStore → **My Apps → Refresh All**.
- Si caduca no pasa nada: tus PDF y anotaciones están en **Archivos**, no dentro de la app. Refresca y vuelve a abrir.

## Límites del Apple ID gratuito

- Máximo **3 apps** sideloaded a la vez, **contando SideStore**. ResiPDF ocupa una, así que te queda una libre.
- Máximo **10 App IDs nuevos por semana**. Reinstalar mucho seguido puede agotarlos; actualizar no gasta.

## Problemas frecuentes

| Problema | Solución |
|---|---|
| SideStore no instala ni refresca | ¿Está LocalDevVPN **conectada**? Usa Wi-Fi |
| Errores de «pairing file» tras actualizar iPadOS | Con la PC y en iloader: **Manage Pairing File → Place** junto a SideStore |
| La app no abre («no disponible») | Caducó: Refresh en SideStore |
| Falla la compilación en GitHub | Pásame el `build-log` |
