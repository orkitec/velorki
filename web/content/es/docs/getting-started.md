---
title: Primeros pasos
description: Instala Velorki, conoce las cuatro pestañas, mira qué permisos pide y por qué, y configura tus unidades. No hace falta cuenta.
order: 1
---

Velorki es un planificador de rutas en bici y grabador de salidas gratuito y de código abierto para iPhone y Android, basado en datos de OpenStreetMap. Esta página trata los primeros diez minutos: instalarlo, qué te pide, cómo está organizada la app y el ajuste que la mayoría de ciclistas quiere cambiar enseguida.

## Lo que necesitas

- Un iPhone con iOS 15 o posterior, o un teléfono Android con Android 8.0 o posterior.
- Ninguna cuenta. Velorki no tiene registro, ni inicio de sesión, ni contraseña. No se guarda nada sobre ti en ningún servidor.
- Ninguna conexión, una vez descargada una zona. La planificación, el enrutamiento, la búsqueda de lugares, la navegación y la grabación funcionan en el teléfono.

## Instalarlo

1. Instala Velorki desde la App Store o Google Play, como cualquier otra app.
2. Ábrelo. No hay pantalla de registro ni tutorial que pasar; la app se abre en el mapa.

Velorki es de código abierto. Si prefieres compilarlo tú mismo, o tener tus propios servidores para las partes que los usan, el código y las instrucciones están en [github.com/orkitec/velorki](https://github.com/orkitec/velorki).

## El primer inicio

Velorki se abre en la pestaña **Planificar**, con un mapa del mundo. Todavía no se ha descargado nada ni se ha pedido ningún permiso.

Una buena primera sesión:

1. Mueve el mapa hasta donde sales en bici y pellizca para acercar.
2. Toca el mapa para fijar el inicio y vuelve a tocar para añadir un destino. En un momento aparece una ruta.
3. Toca el botón de descarga a la derecha del mapa (**Datos sin conexión**) y descarga la zona, para que el mapa y el enrutamiento sigan funcionando cuando no haya cobertura. Consulta [mapas y enrutamiento sin conexión](./offline-maps-and-routing) para saber qué son las dos descargas y cuánto ocupan.
4. Configura tus unidades en **Ajustes → Apariencia → Unidades** si la app no acertó.

## Los permisos que pide, y por qué

Velorki no pide nada al arrancar. Cada permiso se solicita en el momento en que se necesita por primera vez, y cada uno se explica antes de que aparezca el diálogo del sistema.

### Ubicación

Se pide la primera vez que tocas **Mostrar mi posición**, empiezas una salida o pides una ruta circular desde donde estás.

Velorki muestra primero su propio diálogo, titulado **¿Mostrar tu posición?**: "Velorki usa tu ubicación para centrar el mapa en ti y para grabar salidas. La posición se queda en este dispositivo; nunca se sube." Puedes responder **Ahora no** y seguir usando la app; solo dejan de funcionar las funciones que necesitan saber dónde estás.

Con el permiso concedido, el mapa se abre donde lo dejaste y luego se desliza hasta tu posición: enseguida hasta donde el teléfono te situó por última vez si eso fue hace menos de una hora, y hasta la primera posición nueva si no, o si esa posición te sitúa a más de unos 300 m de allí, tanto al arrancar la app como al volver a ella tras media hora o más. No se mueve mientras haya una planificación en la pestaña Planificar, una tarjeta de ruta o de salida abierta, una salida en grabación, ya estés a la vista o hayas movido tú el mapa.

"Mientras se usa la app" es suficiente. En Android, Velorki **no** pide a propósito la ubicación en segundo plano: la grabación de la salida funciona como servicio en primer plano con una notificación. En iOS, "Cuando se use la app" junto con el modo de ubicación en segundo plano cubre una salida grabada con la pantalla apagada.

### Notificaciones (Android)

Se piden la primera vez que empiezas una salida. La grabación funciona dentro de una notificación que muestra tu distancia y tu tiempo, y Android detiene la grabación si no se puede publicar esa notificación. Si lo rechazas, Velorki te lo dice: "Sin el permiso de notificaciones, Android detiene la grabación cuando sales de la app."

### Optimización de batería (Android)

Se pide una sola vez, la primera vez que empiezas una salida: **Seguir grabando en segundo plano**: "Android puede detener la grabación mientras el teléfono está en reposo. Si permites que Velorki ignore la optimización de batería, el track queda completo. Solo se te pregunta una vez." Responde **Permitir** o **Ahora no**; no se vuelve a preguntar.

### Archivos

Ningún permiso permanente. Cuando importas un archivo GPX, FIT o TCX, el selector de archivos del sistema le pasa ese archivo a la app; cuando exportas, el menú de compartir del sistema se lo lleva de nuevo.

Velorki no pide nada más. En ninguna parte de la app hay acceso a contactos, fotos, micrófono, salud ni publicidad.

## Las cuatro pestañas

La barra de abajo tiene cuatro pestañas.

| Pestaña | Qué hay en ella |
|---|---|
| **Planificar** | El mapa, la búsqueda de lugares, el planificador de rutas, las rutas circulares inteligentes y el asistente. |
| **Grabar** | Empezar, pausar y terminar una salida, las cifras en directo y tus salidas recientes. |
| **Biblioteca** | Todo lo que has guardado: **Rutas** y **Salidas**, con importación y exportación. |
| **Ajustes** | Apariencia y unidades, opciones de navegación y grabación, datos sin conexión, búsqueda, conexiones, suscripción y las páginas legales. |

La barra flota sobre el contenido, así que las listas se desplazan por debajo.

## Unidades

Velorki muestra las distancias en kilómetros y metros, o en millas y pies, y usa tu elección en todas partes: las estadísticas, los controles deslizantes, los ejes de los gráficos, el banner de giros y los avisos de voz.

1. Abre **Ajustes**.
2. En **Apariencia**, busca **Unidades**.
3. Elige **Métrico** o **Imperial**.

Hasta que elijas, Velorki sigue el país del teléfono: imperial solo donde el país lo usa, métrico en todos los demás.

## Dónde está cada cosa

- **Los controles del mapa** están en una columna a la derecha del mapa: mostrar mi posición, la capa ciclista, datos sin conexión, acercar y alejar. Mientras se graba una salida se les suma un botón de brújula, que alterna entre **Norte arriba** y **El mapa gira contigo**.
- **El campo de búsqueda** está arriba en la pestaña Planificar.
- **El perfil de bici** (Trekking, Carretera, Gravel, MTB, Directo) es la fila de chips bajo el campo de búsqueda.
- **El panel de ruta** es el panel de la parte inferior de la pestaña Planificar. Arrástralo hacia arriba para ver el perfil de altitud y el desglose de superficies, hacia abajo para ver más mapa.

## Relacionado

- [Planificar una ruta](./planning-a-route)
- [Mapas y enrutamiento sin conexión](./offline-maps-and-routing)
- [Grabar una salida](./recording-a-ride)
- [Ajustes y apariencia](./settings-and-appearance)
- [Privacidad en el teléfono](./privacy-on-the-phone)
