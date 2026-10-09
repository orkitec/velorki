---
title: Búsqueda
description: Encuentra lugares, calles, números de portal y cosas como agua potable o aseos, en el teléfono donde hayas descargado una zona y en línea en todas las demás.
order: 4
---

El campo de búsqueda en la parte superior de la pestaña Planificar encuentra pueblos, calles, números de portal y puntos de interés como cafeterías, agua potable y tiendas de bicis. Donde has descargado una zona responde desde el teléfono, al instante y sin cobertura; en el resto pregunta a un geocodificador en línea.

## Cómo buscar

1. Abre la pestaña **Planificar** y toca el campo de arriba, con el texto **Busca un lugar**.
2. Escribe al menos tres caracteres. Los resultados aparecen en una ficha bajo el campo mientras escribes.
3. Toca un resultado. El mapa se mueve hasta el lugar, lo marca y abre su ficha.

Las coordenadas escritas o pegadas en el campo, `40.71747, -73.94840` o `40,71747° N, 73,94840° O` como las copian las apps de mapas, son el propio lugar: un resultado en ese punto, sin buscar nada y sin enviar nada. Un lugar compartido desde otra app se abre igual, consulta [importar y exportar](./import-and-export#un-lugar-desde-otra-app).

## La ficha de un lugar

Un resultado de búsqueda, una [parada en el mapa](./stops-on-the-map) o un lugar compartido desde otra app abre una ficha con el nombre del lugar, qué es, su población, a qué distancia está de ti y, con una ruta, a qué distancia de la ruta. No cambia nada hasta que eliges una acción, que depende del plan:

- **Aún no hay nada planificado**: **Ruta hasta aquí** va desde donde estás hasta el lugar; **Empezar aquí** lo convierte en el primer punto de la ruta.
- **Solo hay un inicio**: **Como destino** lo convierte en el final de la ruta.
- **Hay una ruta**: **Añadir como parada** lo mete en la ruta donde queda de camino; **Como destino** lo añade al final.

En la pestaña Grabar la ficha solo informa, sin acciones.

Debajo:

- **Detalles** descarga el lugar de OpenStreetMap, solo cuando lo tocas: horario con si está abierto ahora, sitio web, teléfono, tipo de cocina, acceso en silla de ruedas, terraza y su artículo de Wikipedia, en la medida en que estén cartografiados. Los detalles se guardan una semana en el teléfono, así que la próxima vez el lugar los muestra al instante. El botón no aparece para calles ni para lugares sin identificador de OpenStreetMap.
- **Abrir en…** muestra el lugar en Apple Maps, en Google Maps cuando está instalada (iPhone), en una app de mapas que elijas (Android) o en OpenStreetMap en el navegador, o lo pasa a **Compartir…**.

Cerrar la ficha (la **X**, deslizar hacia abajo o tocar el mapa) no cambia nada y borra la búsqueda.

## Sin conexión o en línea

Velorki decide por el **centro del mapa**, no por tu conexión. Cada tesela de rutas descargada trae consigo un índice de búsqueda de su zona, así que:

- si la tesela bajo el centro del mapa tiene su índice en el teléfono, la consulta se responde en el teléfono;
- si no, la consulta va en línea a Photon.

Sobre una zona descargada, hay una fila al pie de la ficha de resultados, y cuál es te dice de dónde vienen los resultados:

| Fila | Significa | Al tocarla |
|---|---|---|
| **Buscar «…» en línea** | estás viendo resultados sin conexión | lanza el mismo texto en línea |
| **Mostrar resultados sin conexión** | estás viendo resultados en línea | vuelve a lanzar el mismo texto en el teléfono |

Cuando la zona no tiene índice en el teléfono y los resultados vinieron en línea, un aviso abre la lista en su lugar: **Esta zona no está descargada**, una línea con el motivo y un botón **Descargar** que abre la pantalla sin conexión para la zona visible. Debajo, el rótulo **Resultados en línea** introduce las filas en línea. El aviso sigue visible mientras desplazas la lista y, si la búsqueda falló, queda sobre el mensaje de error, que es donde más importa.

## Qué encuentra

- **Lugares**: ciudades, pueblos, aldeas, caseríos, barrios, vecindarios, parajes e islas.
- **Calles**, con números de portal.
- **Puntos de interés**, cada uno con su icono y su etiqueta: Cafetería, Restaurante, Comida rápida, Heladería, Gasolinera, Bomba de aire, Agua potable, Aseos, Estación de reparación de bicis, Tienda de bicis, Alquiler de bicis, Aparcabicis, Carga de e-bikes, Refugio, Camping, Hotel, Hostel, Refugio de montaña, Supermercado, Panadería, Farmacia, Zona de pícnic, Estación, Terminal de ferri, Aeropuerto, Mirador, Cima, Puerto de montaña, Parque, Playa, Agua, Reserva natural, Atracción, Museo, Lugar histórico, Lugar de culto, Hospital, Universidad, Instalación deportiva, Centro comercial, Torre, Faro, Edificio.
- **Lugares conocidos en tu idioma**: «Parigi» encuentra París, y un monumento famoso va antes que sus homónimos.

Las filas sin conexión muestran bajo el nombre el tipo, la distancia y la población, en la medida en que se conocen: «Agua potable · 350 m», «Calle · Manhattan». Una fuente, un aseo, un refugio o un aparcabicis sin nombre propio aparece con el nombre de su tipo.

## Buscar por tipo

Escribe el nombre de un tipo en lugar del nombre de un lugar. «agua potable», «panadería», «aseos» y los demás funcionan todos, en el idioma en que esté la app.

La lista se abre entonces con los cinco más cercanos de ese tipo al centro del mapa, cada uno con su distancia, y debajo siguen las coincidencias normales por nombre. Velorki busca en un recuadro que crece de 5 a 50 km alrededor del centro del mapa hasta que tiene suficientes. Es la forma rápida de responder «¿dónde está la fuente más cercana?» en plena salida.

Una búsqueda por tipo no tiene en cuenta los interruptores de grupo descritos más abajo.

## Números de portal

Escribe el número donde lo pone tu país: «Calle Mayor 12», «400 W 42nd», «Via Roma 12/A», «Budapest, Fő utca 12». Velorki encuentra la calle y responde en la posición de ese número a lo largo de ella; la fila es la dirección como la escribiste, «400 West 42nd Street». Una población antes de la calle, con coma, o después, dice de qué lugar es la calle. Un código postal se ignora, y un número que forma parte del nombre de una calle, «Route 66», sigue siendo parte del nombre.

Donde el número cae entre dos que conoce el índice, Velorki estima su posición y la fila dice **≈ 400** para que veas que es una suposición.

## Erratas, formas cortas y otros alfabetos

La búsqueda sin conexión perdona una o dos letras mal, una palabra escrita junta o separada, y formas cortas como «St» o «Str.». Los nombres en cirílico o griego se pueden escribir con letras latinas, «aleksandar nevski» o «Nafplio». Cuando nada responde bien, Velorki prueba en su lugar las palabras más probables del índice y la ficha dice **Resultados para «…»** sobre la lista, con lo que realmente buscó.

## Ordenar los grupos

Los resultados sin conexión van agrupados, y tú decides qué grupos aparecen y en qué orden.

1. Abre **Ajustes**.
2. Toca **Búsqueda**, con el subtítulo «Qué muestra la búsqueda sin conexión y en qué orden. Arrastra para cambiar la prioridad.»
3. Arrastra una fila por su asa para subirla o bajarla. Usa el interruptor de la derecha para desactivar un grupo.

Los ocho grupos, en su orden por defecto: **Lugares**, **Calles y direcciones**, **Puntos de interés**, **Paradas en ruta**, **Alojamiento**, **Naturaleza**, **Transporte**, **Servicios**.

No hay botón de guardar; los cambios se aplican con la siguiente tecla que pulses. Un grupo desactivado desaparece de las coincidencias por nombre, y el orden desempata entre resultados que coinciden igual de bien con el texto.

## Cuando la búsqueda no funciona

- **«No se encontró nada.»** El texto no coincidió con nada, ni sin conexión ni en línea. Prueba la fila del final para cambiar de fuente (sobre una zona sin descargar, **Descargar** en el aviso de arriba), o menos palabras.
- **«Falló la búsqueda.»** con un motivo significa que no se pudo contactar con el geocodificador en línea. La búsqueda sin conexión sigue funcionando donde has descargado una zona.
- **«No hay servidor de búsqueda configurado; añade uno en Ajustes → Avanzado.»** significa que esta versión no tiene ni dirección de geocodificador ni ningún índice descargado. El campo está desactivado hasta que exista uno.

## Relacionado

- [Paradas en el mapa](./stops-on-the-map)
- [Mapas y rutas sin conexión](./offline-maps-and-routing)
- [Planificar una ruta](./planning-a-route)
- [Ajustes y apariencia](./settings-and-appearance)
- [Privacidad en el teléfono](./privacy-on-the-phone)
