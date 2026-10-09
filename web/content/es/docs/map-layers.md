---
title: Capas del mapa
description: El mapa ciclista sin conexión y sus partes, el mapa ciclista en línea y las paradas, todo en el panel Capas.
order: 6
---

**Capas** está en la columna de botones a la derecha del mapa, en las pestañas Planificar y Grabar. Su panel contiene el mapa ciclista, el mapa ciclista en línea y las paradas. El botón se resalta mientras uno de ellos está activo.

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

## Paradas

**Paradas** es un interruptor en el mismo panel, desactivado hasta que lo actives. Dibuja agua potable, cafés, aseos, estaciones de reparación de bicis y más a partir del índice de lugares del teléfono. Los tipos, la zona que miras y la ruta por delante se describen en [paradas en el mapa](./stops-on-the-map).
