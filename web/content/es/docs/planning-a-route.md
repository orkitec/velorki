---
title: Planificar una ruta
description: Toca puntos de paso en el mapa, elige un perfil de bici, compara variantes, consulta los datos de altitud y superficie, y guarda la ruta en tu biblioteca.
order: 2
---

La pestaña Planificar convierte toques en el mapa en una ruta en bici, calculada en tu teléfono allí donde hayas descargado los datos de rutas. Úsala siempre que quieras decidir una salida de antemano, ajustarla y guardarla.

## Fijar el inicio y el destino

1. Abre la pestaña **Planificar** y mueve el mapa hasta donde quieres empezar.
2. **Toca el mapa** para fijar el inicio. El panel de abajo dice "Toca el mapa otra vez para añadir un destino."
3. **Vuelve a tocar** para el siguiente punto. Cada toque añade un punto al final de la ruta, y el último, el destino, lleva una bandera. Para poner un punto en medio, **toca la línea de la ruta** donde debe ir: el punto cae ahí sobre la línea, y puedes arrastrarlo como cualquier otro.
4. Velorki espera un momento tras tu última edición y luego calcula la ruta. Mientras trabaja, el panel muestra un indicador de carga y **Calculando ruta…**; después aparecen las cifras.

También puedes empezar desde un lugar en lugar de un toque. Escribe en el campo de búsqueda de arriba y elige un resultado, o toca una [parada en el mapa](./stops-on-the-map); mientras la planificación sigue vacía, la [ficha del lugar](./search#la-ficha-de-un-lugar) ofrece:

- **Ruta hasta aquí** va desde donde estás hasta el lugar.
- **Empezar aquí** hace del lugar el primer punto de la ruta.

Con solo un inicio, ofrece **Como destino**. Una vez que se está planificando una ruta, la tarjeta ofrece **Añadir como parada**, que mete el lugar en la ruta donde queda de camino, y **Como destino**, que lo añade al final. Consulta [búsqueda](./search) para saber qué puede encontrar el campo de búsqueda.

## Marcar un lugar junto a la ruta

**Mantén pulsado el mapa** donde haya algo que valga la pena recordar, y se abre el panel de punto para un lugar ahí: una fuente, una estación, un camping. La ruta no se dibuja pasando por él. El marcador lleva el icono del tipo que elijas, con su nombre al lado, y al tocarlo se vuelve a abrir el panel.

Para mover un punto que ya tienes, **arrastra su marcador**. En una ruta circular cerrada, arrastrar el marcador de inicio mueve los dos extremos para que la ruta siga cerrada. Una edición solo recalcula los tramos junto al punto que tocó; el resto de la ruta se queda como estaba.

## En la ruta o junto a ella

Cada punto es una de dos cosas, y el selector de arriba de su panel dice cuál:

- **En la ruta**: un punto por el que pasa la salida. Lleva un disco numerado, el destino una bandera con su número al lado, y el enrutador desvía la ruta para pasar por él.
- **Junto a la ruta**: un lugar por delante del que pasa la salida. Lleva el icono de su tipo, y la ruta no lo tiene en cuenta.

Cambia un punto a **Junto a la ruta** y sale de la ruta, que se vuelve a dibujar sin él; el marcador se queda donde está. Cámbialo a **En la ruta** y se convierte en un punto intermedio, en el lugar de la ruta donde queda, y la ruta se vuelve a dibujar pasando por él. En ambos casos el nombre, el tipo y la nota van con él.

## Cambiar o quitar un punto

Toca un marcador para abrir su panel. De arriba abajo:

- **En la ruta** o **Junto a la ruta**, el selector de arriba,
- **Nombre**, con el icono del tipo delante, relleno con el nombre del punto o, para un punto de la ruta sin nombre, con su número; un número que se deja tal cual no da nombre a nada. Un lugar junto a la ruta se abre con el nombre vacío,
- **Tipo**: una cuadrícula de casillas, cuatro filas de cuatro, todas a la vista a cualquier anchura: **Peligro**, **Agua**, **Comida**, **Otro**, **Cima**, **Mirador**, **Refugio**, **Tienda**, **Taller de bicis**, **Primeros auxilios**, **Aseo**, **Camping**, **Alojamiento**, **Aparcamiento**, **Transporte** y **Giro**. **Alojamiento** es una cama y no una parcela: un hotel, un albergue, una casa de huéspedes. Un **Giro** lleva debajo una **Dirección** (izquierda, derecha, ligeramente, bruscamente, mantenerse a la izquierda o a la derecha, recto, cambio de sentido) y se convierte en una línea de la hoja de ruta, así que el banner de giros y la voz lo dicen ahí; una ruta importada con hoja de ruta se abre con sus giros escritos como puntos de este tipo, listos para cambiarlos. **Giro** solo se ofrece para un punto de la ruta: una indicación de una calle que la salida no toma no dice nada,
- **Nota**,
- **Visitar antes** y **Visitar después**, que intercambian enseguida el punto con su vecino en el orden y dejan el panel abierto, para poder mover y nombrar un punto de una vez. Solo para un punto de la ruta; un lugar junto a ella no tiene sitio en el orden,
- **Quitar punto**, para ambos tipos,
- **Listo**, que aplica el selector, el nombre, el tipo y la nota. Desliza el panel hacia abajo para dejarlos como estaban.

Un intercambio, una eliminación, un cambio de tipo de punto y un Listo que cambió algo son cada uno un paso que se puede deshacer. Un punto con nombre en la ruta muestra su nombre en el marcador en lugar de su número, con el icono de su tipo al lado. Los detalles se guardan con la ruta y vuelven cuando se abre de nuevo en el planificador; en una ruta abierta desde la biblioteca se guardan en la biblioteca al momento, siempre que la ruta no se haya recalculado desde entonces, así que no hay que pulsar Guardar solo por un nombre o una nota.

## En qué se convierte cada punto en un archivo exportado

Los dos tipos se exportan, y un ciclocomputador los distingue tan bien como le permite el formato:

- **GPX**: cada lugar junto a la ruta, y cada punto de la ruta con nombre o nota, se escribe como un `<wpt>` con su tipo y su nota. Los puntos de la ruta son además la lista `<rtept>`, para que el archivo se pueda volver a planificar.
- **FIT** y **TCX**: los dos tipos se convierten en puntos del recorrido, junto a los giros de la hoja de ruta. FIT tiene un tipo propio para agua, comida, peligro, cima, primeros auxilios, aseo y camping; TCX solo para agua, comida, peligro, cima y primeros auxilios. Alojamiento, aparcamiento y transporte no tienen tipo en ninguno de los dos, y salen como puntos genéricos del recorrido con su nombre. Todo lo demás sale como punto genérico del recorrido con su nombre.
- Un punto que vino de un archivo conserva la palabra que usaba ese archivo para él. Expórtalo de nuevo sin cambiar su tipo y se vuelve a escribir esa palabra, así que una categoría de puerto, un sprint o un marcador de segmento (cosas para las que Velorki no tiene tipo propio) sobreviven al viaje de ida y vuelta. Si cambias el tipo, se escribe la palabra del nuevo tipo.

## Elegir la bici

La fila de chips bajo el campo de búsqueda es el perfil de bici, y decide qué carreteras y caminos prefiere el enrutador:

| Perfil | Para qué sirve |
|---|---|
| **Trekking** | el predeterminado: una mezcla sensata de carreteras tranquilas y carriles bici |
| **Carretera** | asfalto, menos rodeos, evita las superficies irregulares |
| **Gravel** | a gusto en pistas y superficies sin asfaltar |
| **MTB** | senderos y singletrack |
| **Directo** | el camino más corto, con la menor consideración por la comodidad |

Todos los perfiles salvo **Directo** son los propios de BRouter con un cambio de Velorki: no te mandará en sentido contrario por una calle de sentido único ni por una acera para ahorrarte una manzana. Cambiar el perfil recalcula toda la planificación, incluida una ruta de un archivo, y quita las variantes que tuvieras cargadas; **Deshacer** devuelve la ruta y el perfil. Velorki conserva el último perfil que elegiste para la próxima vez.

## Una ruta de un archivo

Una ruta abierta desde un archivo conserva la línea exacta del archivo, con puntos solo en su inicio, en su final y en los lugares con nombre de su track. Mover, añadir o quitar un punto solo recalcula los tramos de al lado; en todo lo demás la línea sigue siendo la del archivo. Mientras la ruta difiere del archivo, la línea del archivo se dibuja atenuada debajo y un chip sobre el mapa dice **Difiere del archivo**; su **Restaurar** devuelve la ruta del archivo, en un paso que Deshacer puede revertir.

## La barra de herramientas

La fila de botones dentro del panel de ruta:

- **Deshacer** revierte la última edición. No hay límite ni rehacer. Añadir, insertar, mover, quitar y reordenar puntos, **Invertir**, **Borrar**, cambiar el perfil de bici, **Restaurar**, cerrar una ruta circular y tomar otra vuelta se pueden deshacer; cambiar de variante y cargar una ruta guardada no.
- **Invertir** recorre la ruta en sentido contrario.
- **Borrar** descarta la planificación. También se puede deshacer.
- **Variantes** pide alternativas (ver más abajo).
- **Circular** abre el panel de rutas circulares inteligentes, descrito en [rutas circulares](./loops).
- **Preguntar** abre el [asistente](./assistant). Solo aparece cuando la versión se comunica con un servidor de Velorki.

Bajo la fila está el botón **Guardar**, a todo lo ancho.

## Variantes

Velorki no busca alternativas por su cuenta, porque cada una es un cálculo de ruta aparte. Toca **Variantes** y pide hasta cuatro rutas para los mismos puntos.

Entonces aparece una fila de chips sobre la barra de herramientas: **Principal**, **Alt. 1**, **Alt. 2**, **Alt. 3**, cada uno con un punto de color que coincide con su línea en el mapa. Al tocar un chip se cambia al instante, sin calcular nada nuevo, y esa línea se dibuja encima.

Las variantes son rutas completas que dibujó el enrutador, así que en una ruta de un archivo sustituyen la línea del archivo; **Deshacer** la recupera. A menudo vuelven menos de cuatro; lo que encontró el enrutador es lo que obtienes. Si no vuelve ninguna, Velorki dice "No hay alternativas disponibles." Editar un punto de paso o cambiar el perfil de bici quita las variantes, así que vuelve a pedirlas después.

## Leer la ruta

La cabecera del panel muestra cuatro cifras: **Distancia**, **Subida**, **Bajada** y **Duración** El tiempo estimado sale de la velocidad típica del perfil de bici elegido, no de un servidor, y no tiene en cuenta tus paradas para tomar café.

El panel se desplaza a cualquier altura; arrastra su asa o su título hacia arriba para tener más espacio, o cualquier parte de él cuando no hay nada que desplazar. Bajado del todo, se pliega en la barra de navegación y solo deja el asa sobre las pestañas, para que el mapa quede libre; arrastra el asa hacia arriba para recuperarlo.

### Perfil de altitud

El gráfico **Perfil de altitud** dibuja la altura frente a la distancia. Tócalo y arrastra a lo largo de él: aparece una lectura junto al título, del tipo `12,3 km · 340 m`, que sigue a tu dedo. Levántalo y la lectura desaparece. Una ruta sin datos de altura dice "No hay datos de altitud para esta ruta."

### Superficie

La barra de **Superficie** es una única barra apilada de tres partes que suman toda la ruta, **Asfaltado**, **Sin asfaltar** y **Desconocido**, con una leyenda de porcentajes debajo. Otras dos entradas de la leyenda, **Carril bici** y **Mucho tráfico**, se solapan con las tres primeras en lugar de sumarse a ellas: te dicen qué parte de la ruta va por un carril bici propio y qué parte por una carretera grande. Para una ruta que no es toda del propio enrutador, con la línea de un archivo en ella, toda la línea se superpone a los datos de rutas para obtener las cifras, lo que necesita la región descargada.

## Guardarla

1. Toca **Guardar**.
2. El diálogo **Guardar ruta** propone un nombre: el que tenía al guardarla antes, o **Ruta 17 sept 2026** con la fecha de hoy.
3. Escribe tu propio nombre, o déjalo, y toca **Guardar**.

Aparece "Ruta guardada", y la ruta está en **Biblioteca → Rutas**. Guardar una ruta que ya habías guardado actualiza esa misma entrada en lugar de crear otra.

## Cuando no calcula la ruta

- **"Esta ruta necesita teselas de rutas que no están en este dispositivo."** aparece en lugar de las cifras cuando tu teléfono no tiene datos de rutas para la zona ni un servidor de rutas al que recurrir. El botón de debajo cuenta las teselas y su tamaño, por ejemplo **Descargar 3 teselas (412 MB)**, y abre la pantalla sin conexión con exactamente esas teselas seleccionadas. Consulta [mapas y enrutamiento sin conexión](./offline-maps-and-routing).
- **"No hay servidor de rutas configurado; añade uno en Ajustes → Avanzado."** es una tarjeta bajo los chips de bici, y significa que esta versión no tiene ninguna dirección de servidor.
- Cualquier otra cosa aparece como **No se pudo calcular la ruta:** con el motivo.

## Relacionado

- [Rutas circulares](./loops)
- [Búsqueda](./search)
- [Mapas y enrutamiento sin conexión](./offline-maps-and-routing)
- [Biblioteca](./library)
- [Navegación paso a paso](./navigation)
