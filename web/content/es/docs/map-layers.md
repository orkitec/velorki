---
title: Capas del mapa
description: El mapa ciclista sin conexión y sus partes, el mapa ciclista en línea, el radar de lluvia, las nubes y las paradas, todo en el panel Capas.
order: 6
---

**Capas** está en la columna de botones a la derecha del mapa, en las pestañas Planificar y Grabar. Su panel contiene el mapa ciclista, el mapa ciclista en línea, el radar de lluvia, las nubes y las paradas. El botón se resalta mientras uno de ellos está activo.

<!-- screenshot: layers -->

## Mapa ciclista

**Mapa ciclista**: "Carriles bici, sendas y rutas ciclistas de tus zonas descargadas · funciona sin conexión · al acercar el mapa". La dibuja la app con los datos de rutas del teléfono, así que no necesita conexión, y solo donde hay una zona descargada.

El mapa ciclista aparece gradualmente entre el zoom 12 y 13, y se desvanece al alejar. Dibuja lo que los datos de rutas saben de ir en bici. Activado, bajo el interruptor se despliega un chip por parte, cada uno con una muestra de su línea como leyenda. Toca un chip para mostrar u ocultar la parte; la elección se conserva. Las flechas y puntos que se muestran desde el zoom 15 aparecen gradualmente durante el paso de zoom anterior.

| Parte | Dibujada como |
| --- | --- |
| **Carriles bici** | Vías ciclistas en azul continuo, calles ciclistas con una banda pálida; carriles bici segregados continuos y carriles en trazos, al borde de la calzada, más afuera en las vías grandes. Carriles compartidos (carriles bus que las bicis pueden usar, carriles marcados solo con símbolos de bici, arcenes, aceras que las bicis pueden usar) como trazos espaciados azul claro junto a la calzada. Las vías ciclistas de doble sentido y los carriles bici y carriles de doble sentido se dibujan más anchos que los de sentido único |
| **Flechas de sentido único** | Galones del azul propio del carril indican hacia dónde circular: en vías ciclistas y sendas recorridas en un solo sentido desde el zoom 15, y en carriles bici y carriles de sentido único junto a la calzada desde aproximadamente el zoom 15,5 |
| **Sendas compartidas** | Sendas compartidas con peatones en trazos verdeazulados, aceras que las bicis pueden usar en puntos gris azulado |
| **Calles de sentido único** | Un galón gris en el centro de las calles que también son de sentido único para las bicis, apuntando hacia donde va el tráfico, desde el zoom 15. Las calles de sentido único que las bicis pueden recorrer en ambos sentidos muestran en su lugar la señal de dos colores de **Doble sentido bici**. Donde un carril o una vía ciclista junto a la calle muestra su propio sentido, la calle no lleva galón propio |
| **Doble sentido bici** | En calles de sentido único que las bicis pueden recorrer en ambos sentidos, desde el zoom 15 un galón gris muestra el sentido del tráfico y uno azul el de las bicis en contra |
| **Rutas nacionales**, **Rutas regionales**, **Rutas locales** | Rutas ciclistas señalizadas como un halo violeta, más fuerte cuanto más lejos llega la ruta |
| **Sin asfaltar y bacheado** | Grava con un trazo ocre, terreno accidentado para bici de montaña con un trazo marrón, pavimento bacheado con marcas rojas |
| **Barreras y escaleras** | Puertas, bolardos y portillos como puntos desde el zoom 15; en rojo donde hay que llevar la bici en brazos. Escaleras como peldaños marrones desde el zoom 15, con una franja azul al lado donde hay rampa para bicis |
| **Calles tranquilas** | Calles teñidas según su tranquilidad: cian para 30 km/h (20 mph) o menos, verde para 20 km/h o calles residenciales, verde pálido para paso de peatón, verde vivo sin tráfico motorizado; vías cerradas a las bicis en gris |
| **Bici de montaña** | Marcas de dificultad en los senderos desde el zoom 14: azul para fácil (S0–S1), rojo para S2, negro para S3 y más difícil (blanco en el mapa nocturno); rutas de bici de montaña como un halo naranja |
| **Subidas** | Tramos empinados de las vías que puede usar una bici, como una banda: amarillo desde el 6 %, naranja desde el 10 %, rojo desde el 15 %; las flechas apuntan cuesta arriba desde el zoom 15. Las alturas vienen del modelo del terreno de los datos de rutas. Una subida solo cuenta si dura al menos 150 m y 10 m de desnivel, así que las rampas cortas no salen; en centros urbanos con edificios altos aún puede mostrar una subida que no existe o no ver una. Puentes y túneles quedan fuera. En los centros densos de las ciudades más grandes, donde las alturas son las de los edificios, no se dibujan subidas. |

Al principio todas las partes están activas salvo **Sin asfaltar y bacheado**, **Calles de sentido único**, **Calles tranquilas**, **Bici de montaña** y **Subidas**. Una parte añadida en una versión posterior empieza con su valor por defecto; las elecciones anteriores se conservan.

En la pestaña Planificar, con el mapa ciclista activo sobre una zona no descargada, un chip dice **No hay mapa ciclista aquí – zona no descargada**, con **Descargar**; al tocarlo se abre la descarga de la zona visible. Si también vale el chip de las paradas, este va primero.

## Mapa ciclista en línea

**Mapa ciclista en línea**: "El mapa de CyclOSM con tiendas y aparcamientos de bicis · necesita conexión". La capa de CyclOSM, que se pide en línea. Los dos mapas ciclistas se turnan: activar uno desactiva el otro.

## Radar de lluvia y nubes

**Radar de lluvia**: "Ahora: radar en Alemania y EE. UU., en el resto de Europa y África una estimación por satélite. Después: previsión radar de 2 horas en Alemania, previsión de modelo hasta 24 horas (cada hora en Europa, cada 6 horas en el resto)". **Nubes**: "Europa, África y América · cada hora en Europa". Los dos son gratis, están desactivados hasta que los activas y necesitan conexión.

La lluvia viene de tres tipos de fuente. Ahora: el radar del servicio meteorológico alemán (Deutscher Wetterdienst) sobre Alemania y sus alrededores y del servicio meteorológico de EE. UU. (National Weather Service) sobre EE. UU., y alrededor, sobre el resto de Europa, África y el Atlántico, la lluvia que H SAF de EUMETSAT estima a partir del satélite Meteosat, cada diez minutos. Una estimación por satélite es más tosca que el radar y no ve parte de la lluvia débil; nunca se dibuja sobre las zonas de los radares, así que los dos nunca se contradicen en el mapa. Las próximas dos horas: en Alemania la previsión radar del Deutscher Wetterdienst, la lluvia del radar desplazada en cuartos de hora; en todas partes, y a partir de tres horas en todas, la previsión de su modelo meteorológico ICON, hora a hora sobre Europa y en pasos de seis horas en el resto. La app busca imágenes más nuevas cada cinco minutos. Con el mapa más alejado que un continente aproximadamente, la lluvia no se dibuja, salvo el radar **Tal como se mide**.

Con el radar de lluvia activo, su control de tiempo está arriba en el panel de Planificar y en la tarjeta de Grabar, bajo las cifras durante una salida: un control deslizante de **Ahora** en cuartos de hora hasta dos horas adelante, y luego en horas hasta 24 horas adelante. Su etiqueta dice el paso, la hora de la imagen sobre el centro del mapa y, hacia adelante, qué es, por ejemplo **Ahora · 20:25**, **+45 min · 21:30 · Previsión radar** o **+3 h · 23:00 · Previsión**. El paso es el mismo en todas las pestañas y vuelve a **Ahora** cuando la app vuelve tras más de media hora fuera. La Biblioteca muestra la hora en una pequeña etiqueta sobre el mapa.

Las nubes son imágenes de satélite dibujadas en blanco sobre el mapa: Meteosat de EUMETSAT sobre Europa, África y alrededores, con una imagen nueva cada hora en punto, y los satélites GOES a través de la NASA sobre América. Siempre muestran su imagen más reciente, diga lo que diga el control de la lluvia, y una pequeña etiqueta sobre el mapa dice su hora. Las nubes más gruesas y frías se ven más claras; la niebla y las nubes bajas se ven débiles o nada.

Si un servicio no responde, el mapa dice **Radar de lluvia no disponible ahora mismo**, **Lluvia por satélite no disponible ahora mismo**, **Previsión de lluvia no disponible ahora mismo** o **Nubes no disponibles ahora mismo**, para que un mapa vacío no se tome por un día seco y despejado. La app carga las imágenes directamente del Deutscher Wetterdienst, la NOAA, la NASA y EUMETSAT, no a través de Velorki, así que esos servicios ven la zona del mapa pedida. Sus créditos aparecen en la línea al pie del mapa mientras una capa está dibujada.

## Paradas

**Paradas** es un interruptor en el mismo panel, desactivado hasta que lo actives. Dibuja agua potable, cafés, aseos, estaciones de reparación de bicis y más a partir del índice de lugares del teléfono. Los tipos, la zona que miras y la ruta por delante se describen en [paradas en el mapa](./stops-on-the-map).
