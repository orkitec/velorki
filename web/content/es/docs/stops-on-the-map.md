---
title: Paradas en el mapa
description: Muestra agua, cafés, aseos, reparación de bicis y otras paradas en el mapa, en la zona que miras o a lo largo de la ruta por delante, y activa el mapa ciclista.
order: 5
---

Velorki puede dibujar en el mapa los lugares donde se para en una salida: agua potable, cafés, panaderías, aseos, estaciones de reparación de bicis y más. Salen del índice de lugares de los datos de rutas del teléfono, así que necesitan la zona descargada (consulta [mapas y enrutamiento sin conexión](./offline-maps-and-routing)), funcionan sin cobertura y no envían nada a ninguna parte.

## El botón Capas

**Capas** está en la columna de botones a la derecha del mapa, en las pestañas Planificar y Grabar. Su panel contiene:

- **Mapa ciclista**: "Carriles bici, sendas y rutas ciclistas de tus zonas descargadas · funciona sin conexión · al acercar el mapa". La dibuja la app con los datos de rutas del teléfono, así que no necesita conexión, y solo donde hay una zona descargada. Sus partes se despliegan bajo el interruptor, ver [el mapa ciclista](#el-mapa-ciclista).
- **Mapa ciclista en línea**: "El mapa de CyclOSM con tiendas y aparcamientos de bicis · necesita conexión". La capa de CyclOSM, que se pide en línea. Los dos mapas ciclistas se turnan: activar uno desactiva el otro.
- **Paradas**, un interruptor, desactivado hasta que lo actives. Debajo, los tipos que mostrar, por grupo: **Paradas en ruta**, **Alojamiento** y **Puntos de interés**. Toca un tipo para mostrarlo u ocultarlo. La primera vez están elegidos agua potable, cafés, panaderías, aseos y estaciones de reparación de bicis. Con el interruptor desactivado los tipos se pliegan; tu elección se conserva para la próxima vez.

El botón se resalta mientras el mapa ciclista, el mapa ciclista en línea o las paradas están activos.

## El mapa ciclista

El mapa ciclista aparece gradualmente entre el zoom 12 y 13, y se desvanece al alejar. Dibuja lo que los datos de rutas saben de ir en bici. Activado, bajo el interruptor se despliega un chip por parte, cada uno con una muestra de su línea como leyenda. Toca un chip para mostrar u ocultar la parte; la elección se conserva. Las flechas y puntos que se muestran desde el zoom 15 aparecen gradualmente durante el paso de zoom anterior.

| Parte | Dibujada como |
| --- | --- |
| **Carriles bici** | Vías ciclistas en azul continuo, calles ciclistas con una banda pálida; carriles bici segregados continuos y carriles en trazos, al borde de la calzada, más afuera en las vías grandes. Carriles compartidos (carriles bus que las bicis pueden usar, carriles marcados solo con símbolos de bici, arcenes, aceras que las bicis pueden usar) como trazos espaciados azul claro junto a la calzada. Las vías ciclistas de doble sentido y los carriles bici y carriles de doble sentido se dibujan más anchos que los de sentido único |
| **Flechas de sentido único** | Galones del azul propio del carril indican hacia dónde circular: en vías ciclistas y sendas recorridas en un solo sentido desde el zoom 15, y en carriles bici y carriles de sentido único junto a la calzada desde aproximadamente el zoom 15,5 |
| **Sendas compartidas** | Sendas compartidas con peatones en trazos verdeazulados, aceras que las bicis pueden usar en puntos gris azulado |
| **Calles de sentido único** | Un galón gris en el centro de las calles que también son de sentido único para las bicis, apuntando hacia donde va el tráfico, desde el zoom 15. Las calles de sentido único que las bicis pueden recorrer en ambos sentidos muestran en su lugar la señal de dos colores de **Doble sentido bici** |
| **Doble sentido bici** | En calles de sentido único que las bicis pueden recorrer en ambos sentidos, desde el zoom 15 un galón gris muestra el sentido del tráfico y uno azul el de las bicis en contra |
| **Rutas nacionales**, **Rutas regionales**, **Rutas locales** | Rutas ciclistas señalizadas como un halo violeta, más fuerte cuanto más lejos llega la ruta |
| **Sin asfaltar y bacheado** | Grava con un trazo ocre, terreno accidentado para bici de montaña con un trazo marrón, pavimento bacheado con marcas rojas |
| **Barreras y escaleras** | Puertas, bolardos y portillos como puntos desde el zoom 15; en rojo donde hay que llevar la bici en brazos. Escaleras como peldaños marrones desde el zoom 15, con una franja azul al lado donde hay rampa para bicis |
| **Calles tranquilas** | Calles teñidas según su tranquilidad: cian para 30 km/h (20 mph) o menos, verde para 20 km/h o calles residenciales, verde pálido para paso de peatón, verde vivo sin tráfico motorizado; vías cerradas a las bicis en gris |
| **Bici de montaña** | Marcas de dificultad en los senderos desde el zoom 14: azul para fácil (S0–S1), rojo para S2, negro para S3 y más difícil (blanco en el mapa nocturno); rutas de bici de montaña como un halo naranja |

Al principio todas las partes están activas salvo **Sin asfaltar y bacheado**, **Calles de sentido único**, **Calles tranquilas** y **Bici de montaña**. Una parte añadida en una versión posterior empieza con su valor por defecto; las elecciones anteriores se conservan.

En la pestaña Planificar, con el mapa ciclista activo sobre una zona no descargada, un chip dice **No hay mapa ciclista aquí – zona no descargada**, con **Descargar**; al tocarlo se abre la descarga de la zona visible. Si también vale el chip de las paradas, este va primero.

## En la zona que miras

Con **Paradas** activado, las paradas de la parte del mapa que ves aparecen a partir del zoom 11. Alejado, las paradas cercanas se agrupan en burbujas con un número; desde el zoom 15 se separan en paradas sueltas con sus iconos. Toca una burbuja para acercar hasta donde se separa.

Más alejado que eso, un chip dice **Acerca el mapa para ver paradas**; tócalo y el mapa se acerca hasta donde se muestran.

Cuando la zona no está descargada, el chip dice en su lugar **No hay paradas aquí – zona no descargada**, con **Descargar**; un toque abre la descarga de la zona visible.

## A lo largo de la ruta

Con una ruta elegida en **Seguir una ruta** en la pestaña Grabar, las paradas son las que están a menos de 300 m de la ruta que queda por delante, hasta 50 km, con cualquier zoom. Una línea sobre el mapa enumera la siguiente de cada tipo con su distancia a lo largo de la ruta, "Agua potable · 2,4 km"; toca una entrada para ver la parada en el mapa. Mientras el mapa te sigue en una salida, sigue contigo y la parada solo se destaca.

Cuando nada de los próximos 50 km de la ruta está descargado, el mismo chip ocupa el lugar de esa línea.

**A lo largo de la ruta** y **En esta zona** en el panel Capas alternan entre las dos.

## Toca una parada

Una parada abre su ficha, la misma que abre un resultado de búsqueda: nombre, tipo, población, a qué distancia está de ti y, con una ruta, a qué distancia de ella. En la pestaña Planificar ofrece qué hacer con el lugar, **Ruta hasta aquí**, **Empezar aquí**, **Añadir como parada** o **Como destino**; en la pestaña Grabar solo informa. **Detalles** y **Abrir en…** están en ambas. Consulta [la ficha de un lugar](./search#la-ficha-de-un-lugar).

## Relacionado

- [Búsqueda](./search)
- [Planificar una ruta](./planning-a-route)
- [Navegación paso a paso](./navigation)
- [Mapas y enrutamiento sin conexión](./offline-maps-and-routing)
