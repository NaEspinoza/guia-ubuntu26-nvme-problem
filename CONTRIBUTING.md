# 🤝 Contribuir a ubuntu-26-upgrade-recovery

Primero que nada: gracias por querer ayudar.  
Esta guía nació de un caso real documentado en tiempo real. Cada persona que contribuye un caso, una corrección o una mejora hace que la próxima persona que googlee este error a las 2 de la madrugada encuentre la solución más rápido.

---

## 📋 Índice

- [¿Cómo puedo contribuir?](#cómo-puedo-contribuir)
- [Reportar un caso exitoso](#reportar-un-caso-exitoso)
- [Reportar un caso donde la guía no funcionó](#reportar-un-caso-donde-la-guía-no-funcionó)
- [Proponer mejoras a la guía o los scripts](#proponer-mejoras-a-la-guía-o-los-scripts)
- [Traducir la guía](#traducir-la-guía)
- [Formato para reportar un caso](#formato-para-reportar-un-caso)
- [Qué NO necesitamos](#qué-no-necesitamos)
- [Código de conducta](#código-de-conducta)

---

## ¿Cómo puedo contribuir?

Hay cuatro formas de ayudar, de menor a mayor esfuerzo:

### ⭐ 1. Dale una estrella al repo
Es la forma más rápida de ayudar a que más gente encuentre esta guía en GitHub. No requiere ningún conocimiento técnico.

### 🐛 2. Abrí un Issue
Usá Issues para:
- Reportar que la guía funcionó en tu hardware (casos de éxito)
- Reportar que un paso no funcionó o tiene un error
- Preguntar algo que no está cubierto en la guía
- Sugerir una mejora

### 📝 3. Documentá tu caso
Si pasaste por este problema con hardware diferente al documentado (otro fabricante, otro modelo de NVMe, otra configuración de particiones), tu caso ayuda a cubrir más variantes. Ver [Formato para reportar un caso](#formato-para-reportar-un-caso).

### 🔧 4. Abrí un Pull Request
Para correcciones de comandos, mejoras a los scripts, o agregar tu caso documentado al directorio `cases/`.

---

## Reportar un caso exitoso

Si seguiste la guía y tu sistema volvió a funcionar, **abrí un Issue** con el título:

```
✅ Caso exitoso — [tu hardware] — [tu configuración]
```

Por ejemplo:
```
✅ Caso exitoso — HP EliteBook 840 G9 — NVMe Samsung 990 Pro — dual boot Windows 11
```

Incluí la información del [Formato para reportar un caso](#formato-para-reportar-un-caso).  
Estos casos son los más valiosos porque confirman qué pasos son necesarios en cada configuración de hardware.

---

## Reportar un caso donde la guía no funcionó

Si seguiste todos los pasos y el sistema sigue sin arrancar, abrí un Issue con el título:

```
❌ Guía no funcionó — [tu hardware] — [síntoma que persiste]
```

Por ejemplo:
```
❌ Guía no funcionó — Asus Zenbook — modprobe nvme sigue dando Exec format error
```

**Información necesaria para que podamos ayudarte:**

```
## Mi hardware
- Fabricante y modelo del equipo:
- Tipo y modelo del disco NVMe:
- Versión de Ubuntu origen:
- Versión de Ubuntu destino:
- ¿Dual boot?: Sí/No (con qué OS)

## Qué hice
- Pasos que seguí de la guía:
- Comandos exactos que ejecuté:

## Qué pasó
- Salida exacta del error (copiá el texto, o pegá una foto si es en la pantalla de arranque):
- Salida de `modinfo -F vermagic /lib/modules/KVER/kernel/drivers/nvme/host/nvme.ko.zst`:
- Salida de `dpkg -l | grep linux`:
- Salida de `lsinitrd /boot/initrd.img-KVER | grep nvme`:
```

---

## Proponer mejoras a la guía o los scripts

### Para correcciones menores (errores tipográficos, un comando incorrecto)
Abrí un Issue describiendo el problema y la corrección. Si querés, también podés abrir un PR directamente.

### Para mejoras más grandes (nueva sección, nuevo script, reorganización)
Primero abrí un Issue para discutirlo antes de invertir tiempo en escribirlo. Así coordinamos y evitamos trabajo duplicado.

### Para los scripts
- Los scripts deben funcionar en bash (no zsh ni sh exclusivo)
- Mantener la compatibilidad con Ubuntu Live y Linux Mint Live
- Los mensajes deben estar en español (el público principal de esta guía)
- Mantener el estilo de colores y formato existente
- Todo comando destructivo debe pedir confirmación

---

## Traducir la guía

Si querés traducir la guía a otro idioma:

1. Abrí un Issue con el título `🌐 Traducción — [idioma]` para avisarnos
2. Creá una carpeta `translations/[codigo-idioma]/` (ej: `translations/en/`, `translations/pt/`)
3. Copiá los archivos `.md` y traducílos
4. Los scripts pueden quedar en español o traducirse — a tu criterio
5. Abrí un PR cuando estés listo

Traducciones en progreso o planeadas:
- [ ] Inglés (en)
- [ ] Portugués (pt-BR)

---

## Formato para reportar un caso

Ya sea en un Issue o en un archivo bajo `cases/`, usá este formato:

```markdown
# Caso: [Fabricante] [Modelo] — [NVMe] — [fecha]

## Hardware
- **Equipo:** [fabricante, modelo, año]
- **Disco NVMe:** [marca y modelo]
- **Firmware:** UEFI / BIOS Legacy
- **RAM:** [cantidad]
- **Configuración:** Single boot / Dual boot con [OS]

## Sistema
- **Ubuntu origen:** 24.04 LTS (o la versión que tenías)
- **Ubuntu destino:** 26.04 LTS
- **Kernel resultante:** 7.0.0-XX-generic (o el que quedó)

## Síntoma inicial
[Descripción de lo que aparecía en pantalla al arrancar]

## Diagnóstico
- ¿dracut instalado?: Sí / No
- ¿Módulos correctos? (vermagic coincidía): Sí / No
- ¿Paquetes en estado half-installed?: Sí / No

## Pasos que funcionaron
[Lista de pasos de la guía que resolvieron el problema]

## Pasos que no aplicaron o fallaron
[Si algún paso no aplicó a tu caso o dio error]

## Notas adicionales
[Cualquier particularidad de tu hardware o configuración]
```

---

## Qué NO necesitamos

Para mantener la guía enfocada y de calidad:

- ❌ **Casos de otros problemas de arranque** no relacionados con el upgrade 24→26 (hay otras guías para eso)
- ❌ **Sugerencias de reinstalar Ubuntu** como primera opción (esta guía existe precisamente para evitar eso)
- ❌ **Cambios de estilo sin justificación técnica** (el tono y formato están pensados para ser accesibles)
- ❌ **Dependencias nuevas en los scripts** que no estén disponibles en todos los Live USB basados en Ubuntu

---

## Código de conducta

Este proyecto sigue un principio simple:

**Toda persona que llegó acá lo hizo porque su sistema no arrancaba.** Tratá los Issues y comentarios con esa empatía. No hay preguntas "demasiado básicas" — si alguien pregunta algo que parece obvio, probablemente sea una señal de que la guía necesita ser más clara.

Específicamente:
- Respondé en el idioma en el que te escriben
- No des por sentado conocimiento previo
- Si una pregunta ya está respondida en la guía, señalá la sección específica en lugar de solo decir "está en el README"
- Los errores de principiante son válidos — todos empezamos desde algún lado

---

*¿Dudas sobre cómo contribuir? Abrí un Issue con el título `Pregunta sobre contribuciones` y lo charlamos.*
