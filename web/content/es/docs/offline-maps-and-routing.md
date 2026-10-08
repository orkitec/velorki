---
title: Mapas y enrutamiento sin conexión
description: Descarga el mapa que ves y los datos de rutas con los que se calculan tus rutas, para que la planificación, la búsqueda y la navegación sigan funcionando sin cobertura.
order: 6
---

Dos descargas separadas hacen que Velorki funcione sin conexión: el **mapa**, que es lo que ves, y los **datos de rutas**, que es con lo que se calculan las rutas y la búsqueda sin conexión. Descarga los dos para la zona por la que sales antes de una salida en la que vayas a quedarte sin cobertura.

## Los dos tipos

| | Mapa | Datos de rutas |
|---|---|---|
| Se muestra como | **Mapa** | **Datos de rutas** |
| Qué es | teselas de mapa vectorial de OpenFreeMap, dibujadas a partir de OpenStreetMap | teselas de BRouter del espejo de Velorki, creadas a partir de OpenStreetMap |
| Cubre | exactamente el rectángulo que tenías en pantalla | un cuadrado fijo de 5° × 5° del mundo |
| Tamaño | decenas de megabytes para una ciudad | a menudo de 125 a 250 MB por tesela |
| Sin él | teselas grises donde el mapa no está en caché | sin enrutamiento ni búsqueda sin conexión en esa zona |

Los datos de rutas también incluyen el índice de lugares, así que en una zona descargada también se puede buscar sin conexión y se ven sus [paradas en el mapa](./stops-on-the-map). Por eso la pantalla de teselas de rutas dice "Una región descargada también sirve para buscar lugares sin cobertura." Esa misma región descargada es la que da a una salida grabada su desglose de superficies, consulta [la biblioteca](./library).

## Descargar una zona

1. En la pestaña **Planificar**, mueve el mapa para que la zona que quieres llene la pantalla. No alejes más de lo necesario: la descarga del mapa sigue exactamente lo que hay en pantalla.
2. Toca el botón **Datos sin conexión** en la columna de la derecha del mapa. En una pantalla pequeña como la de un iPhone SE la columna no tiene sitio para él: ahí, toca **Descarga esta zona para buscar sin conexión** al final de los resultados del campo de búsqueda, o el botón de descarga bajo una ruta que necesite teselas, y gestiona lo que tienes en **Ajustes → Datos sin conexión**.
3. Lee las dos tarjetas y toca **Descargar la zona visible** abajo.
4. El diálogo **Descargar la zona visible** enumera lo que vas a descargar: "Mapa de la zona visible · tamaño conocido tras la descarga" para el mapa, y luego una línea por tesela de rutas con su tamaño, por ejemplo `E5_N45 · 187 MB`, o "Los datos de rutas de esta zona ya están en el dispositivo".
5. Toca **Descargar**.

Las dos descargas se hacen mientras la app está abierta. Las tarjetas muestran **Descargando el mapa…** y **Descargando E5_N45…** con barras de progreso.

La pantalla te avisa por una razón: "Las teselas son grandes, a menudo de 125–250 MB cada una, y Velorki no distingue entre wifi y datos móviles. Empieza las descargas cuando estés con wifi."

También puedes llegar a esta pantalla desde **Ajustes → Datos sin conexión**, pero abierta así no hay mapa detrás, de modo que el botón de descarga está desactivado y la nota dice "Abre esta pantalla desde el mapa para descargar la zona que estás viendo."

## Gestionar las zonas del mapa

**Gestionar** en la tarjeta **Mapa** abre **Mapas sin conexión**, con una fila por zona descargada:

- El nombre que le dio Velorki, **Zona de mapa 1**, **Zona de mapa 2** y así sucesivamente.
- Su tamaño y la fecha, "12,3 MB · Descargada el 14 sept 2026".
- **Actualización disponible** en naranja cuando la zona tiene más de dos meses, con un botón **Actualizar** al lado. Una actualización es una descarga completa de nuevo.
- Un botón **Eliminar**, que pregunta "¿Eliminar la zona sin conexión?" con "Las teselas descargadas se eliminan de este dispositivo."

La tarjeta de la pantalla sin conexión resume lo mismo: "3 zonas, 48 MB" y "2 zonas tienen más de dos meses y se pueden actualizar".

## Gestionar las teselas de rutas

**Gestionar** en la tarjeta **Datos de rutas** abre **Datos de rutas sin conexión**. Cada fila es una tesela de 5° × 5° con su nombre, su tamaño y su estado:

| Estado | Significa |
|---|---|
| **En este dispositivo** | lista: el enrutamiento y la búsqueda sin conexión funcionan aquí |
| **Actualización disponible** | el espejo ha regenerado esta tesela; **Actualizar** la vuelve a descargar |
| **La actualización necesita un Velorki más reciente** | la tesela regenerada está en un formato de datos que esta versión de la app no sabe leer |
| **Descargando…** | en curso |
| **No descargada** | el espejo la conoce, pero no está en el teléfono |

También en la pantalla:

- **Necesarias para esta ruta** aparece cuando llegas desde el aviso de teselas que faltan del planificador, con las teselas que necesita esa ruta ya seleccionadas y un botón que las cuenta, por ejemplo **Descargar 1 tesela (187 MB)**.
- **Descargar para la zona visible** abajo, con el total de todo lo que tienes: "3 teselas, 540 MB".
- **Espejo generado el 1 sept 2026** bajo cada fila, que es la fecha en que el espejo generó esa tesela por última vez.
- Un botón **Eliminar** en cada fila, que avisa "La tesela se elimina de este dispositivo. Las rutas en esa zona volverán a necesitar el servidor de rutas."
- Un botón **Cancelar descarga** en la cabecera de progreso mientras hay una en curso.

Velorki comprueba cada semana si el espejo ha regenerado algo de lo que tienes. Si es así, la fila **Datos sin conexión** de Ajustes se vuelve naranja, muestra "2 teselas tienen actualizaciones" y pone un contador sobre la flecha.

## El nomenclátor, o índice de búsqueda

Cada tesela de rutas que publica el espejo tiene al lado un pequeño índice de búsqueda, y Velorki descarga los dos juntos. No aparece como ajuste ni como descarga aparte.

Si el índice no se descarga, la tesela en sí sigue bien: la zona sigue siendo enrutable y su búsqueda simplemente pasa a hacerse en línea. Lo mismo ocurre con un índice en un formato que esta versión de la app no sabe leer: se omite, las demás zonas siguen respondiendo sin conexión y esa zona busca en línea.

## Dónde se guarda todo y cómo borrarlo

Todo está dentro del almacenamiento propio de la app en el teléfono, no en tus documentos ni en tu fototeca, y no se copia nada a una copia de seguridad en la nube.

Para liberar espacio:

- elimina zonas de mapa sueltas en **Mapas sin conexión**,
- elimina teselas de rutas sueltas en **Datos de rutas sin conexión**,
- o desinstala la app, lo que lo borra todo, junto con tus rutas y salidas. Exporta antes lo que quieras conservar, consulta [importar y exportar](./import-and-export).

## "Primero actualiza Velorki"

De vez en cuando, las teselas de rutas cambian de formato. Cuando el espejo ofrece una tesela que esta versión de la app no sabe leer, Velorki lo dice en lugar de descargar basura: **Primero actualiza Velorki**, "Estas teselas tienen el formato de datos 5, y esta versión de Velorki lee hasta el 4. Necesitan un Velorki más reciente; descárgalas cuando lo hayas actualizado." Responde **Ahora no**, o **Abrir tienda** para ir a actualizar.

Las teselas que ya tienes siguen funcionando.

## Relacionado

- [Búsqueda](./search)
- [Planificar una ruta](./planning-a-route)
- [Navegación paso a paso](./navigation)
- [Solución de problemas](./troubleshooting)
