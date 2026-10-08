---
title: Biblioteca
description: Dónde están tus rutas guardadas y tus salidas grabadas, qué muestra la tarjeta de una ruta o de una salida, y cómo renombrarlas o eliminarlas.
order: 9
---

La pestaña Biblioteca guarda todo lo que has conservado: las rutas que planificaste y las salidas que grabaste. Es una tarjeta sobre el mapa, como las pestañas Planificar y Grabar: su contenido se desplaza a cualquier altura, y el asa de arriba la mueve; cuando no hay nada que desplazar, se mueve la tarjeta entera. Súbela para tener más espacio, bájala del todo y la tarjeta se pliega en la barra de navegación y deja el mapa. Ven aquí para volver a abrir una ruta, leer los gráficos y parciales de una salida, y meter y sacar archivos.

Todo lo que hay en la biblioteca está en el teléfono. No hay cuenta y no se sincroniza nada en ninguna parte.

## Rutas y Salidas

Un selector bajo el título de la tarjeta elige la lista: **Rutas** o **Salidas**. Velorki recuerda cuál estabas mirando la última vez.

- Una fila de **ruta** muestra su nombre y, debajo, la fecha, la distancia y el desnivel positivo.
- Una fila de **salida** muestra su nombre y, debajo, la fecha, la distancia y el tiempo en movimiento. Encima de la lista hay un recuento, "12 salidas".

Toca una fila para abrirla en la tarjeta, con la ruta o la salida dibujada en el mapa de arriba. La flecha de arriba a la izquierda de la tarjeta, o el botón atrás del sistema, devuelve la lista.

Las listas vacías se explican solas: "Aún no hay rutas guardadas. Planifica una ruta en la pestaña Planificar y guárdala." y "Aún no hay salidas."

## Renombrar y eliminar

**Rutas**: el menú a la derecha de la fila tiene **Renombrar** y **Eliminar**. Deslizar una fila hacia la izquierda también la elimina. En ambos casos el mensaje que aparece después incluye **Deshacer**.

**Salidas**: desliza la fila hacia la izquierda para eliminarla, también con **Deshacer**. Renombrar una salida y eliminarla con confirmación están en la tarjeta de la salida, en el menú a la derecha de su cabecera.

Los dos diálogos para renombrar son iguales: un campo, **Nombre**, y luego **Cancelar** o **Guardar**.

## La tarjeta de una ruta

Al abrir una ruta se dibuja en el mapa, ajustada a la parte de la pantalla que queda sobre la tarjeta, con sus puntos de interés como pequeños marcadores con nombre si se importó con ellos. La tarjeta muestra, de arriba abajo:

- la fecha, el perfil de bici y el desnivel positivo,
- la descripción, si la ruta tiene una,
- **Distancia**, **Subida**, **Bajada** y **Duración**,
- la tarjeta en sí se abre hasta arriba cuando la lista en pantalla tiene más de dos entradas, y se queda a media altura si no; una vez que la has arrastrado, vuelve a donde la dejaste hasta que se reinicia la app,
- bajo el nombre, de dónde viene una ruta importada: el formato de archivo y quién lo escribió, por ejemplo "Importada de GPX · Garmin Connect"; una ruta planificada aquí no dice nada ahí,
- las acciones de abajo, con **Abrir en el planificador** primero para que se vea a la altura de reposo de la tarjeta,
- una fila **Descripción** y una fila **Enlace**, cada una con un lápiz: la descripción es la del archivo, la del asistente o la tuya, el enlace es el `<link>` del archivo o uno que escribas, y al tocarlo se abre la página,
- el desglose de superficies: las cifras del propio enrutador para una ruta planificada aquí, y para una leída de un archivo la misma comparación con el mapa que se hace con una salida, ver más abajo,
- el perfil de altitud,
- **Puntos de interés**: los puntos de la ruta que no están en su track, cada uno con el icono de su tipo, su nombre y su nota: los que traía un archivo fuera del recorrido y los lugares que marcaste junto a la ruta en el planificador; los que están en el track son líneas de la hoja de ruta,
- para una ruta importada con giros o puntos de interés, o con puntos a los que pusiste nombre o una nota en el planificador, la hoja de ruta: cada giro y punto con su distancia desde el inicio; al tocar una línea el mapa se desplaza hasta allí con tu zoom, y al tocar un marcador la tarjeta se desplaza hasta esa línea.

Las acciones:

- **Abrir en el planificador** la carga en la pestaña Planificar con todos sus puntos, incluidos los puntos de paso y sus nombres, tipos y notas, donde puedes editarla y volver a guardarla. Una ruta importada en lugar de planificada se abre con la línea exacta del archivo y con puntos solo en sus extremos y en los puntos propios del archivo que están en el track, que vienen con su tipo y su nota; una edición solo recalcula los tramos de al lado, y la línea del archivo se mantiene en todo lo demás. La línea del archivo se guarda con la ruta en cada edición y cada guardado, así que **Restaurar** en el planificador puede recuperarla. Los puntos fuera del track vienen como lugares junto a la ruta, donde se les puede poner nombre o tipo, moverlos a la ruta o quitarlos como cualquier otro punto. El siguiente Guardar escribe los dos conjuntos, así que un lugar que eliminas en el planificador también desaparece de la tarjeta.
- **Exportar** ofrece **Ruta GPX** y **Recorrido FIT**, consulta [importar y exportar](./import-and-export).
- **Enviar** ofrece **Enviar a Ride with GPS** y **Enviar a Strava**, consulta [Strava y Ride with GPS](./strava-and-ridewithgps).
- **Compartir enlace** la convierte en un enlace, consulta [compartir](./sharing).
- **Describir esta ruta** pide al asistente que escriba un párrafo sobre ella, consulta [asistente](./assistant).

## La tarjeta de una salida

Al abrir una salida se dibuja en el mapa **el track coloreado por velocidad**, de lento a rápido, ajustado sobre la tarjeta, con una leyenda **lento**/**rápido** arriba de la tarjeta. Las franjas son los cuantiles de esa misma salida, así que los colores comparan la salida consigo misma y no con una escala fija. Una salida sin marcas de tiempo se dibuja como una línea simple. La tarjeta muestra, de arriba abajo:

- la fecha,
- siete cifras: **Distancia**, **En movimiento**, **Tiempo**, **Media**, **Máx.**, **Subida**, **Bajada**. **En movimiento** no cuenta el tiempo que estuviste parado; **Tiempo** es la salida entera de principio a fin.
- el gráfico **Perfil de altitud**, la altura frente a la distancia, que solo se dibuja si el track traía alturas,
- el gráfico de **Velocidad**, cuyo eje siempre empieza en cero,
- el gráfico de **Frecuencia cardiaca**, si la salida la traía; donde se perdió la lectura durante un tramo la línea se corta, y si la lectura no cubre la mayor parte de la salida el título dice cuánto, "Frecuencia cardiaca · 24 % de la salida", para que una media de esos minutos no se tome por la de la salida,
- la tabla de **Parciales**.

Toca un gráfico y arrastra a lo largo de él para ver una lectura del tipo `12,3 km · 340 m`. Pellizca un gráfico para ampliar un tramo, arrastra para desplazarte con el zoom puesto, y tócalo dos veces o toca **Toda la salida** para volver a ver toda la salida; los tres gráficos se amplían juntos.

### Ruta y puntos de interés

Una salida que siguió una ruta muestra esa ruta bajo el track, en el color más discreto de una alternativa del planificador, y los puntos de interés de la ruta como marcadores en el mapa y como marcas en el gráfico **Perfil de altitud** en el punto en que pasaste por ellos, solo para los puntos a los que la salida se acercó a menos de 60 m. Al tocar un marcador se fija con su nombre; la lectura nombra la marca sobre la que está el dedo. El botón de ruta arriba en la columna de controles del mapa lo oculta todo, y la elección se recuerda.

### Cifras de un sensor

Una salida grabada con una banda de frecuencia cardiaca, un Apple Watch o un medidor de potencia trae más que las siete: **Pulso medio**, **Pulso máx.**, **Cadencia media**, **Cadencia máx.**, **Potencia media**, **Potencia máx.** y **Potencia norm.** se suman a las cifras, cada una solo si la salida la tiene, y el gráfico de **Frecuencia cardiaca** se dibuja bajo el de velocidad. **Potencia norm.** son las lecturas del medidor ponderadas como las sienten las piernas: la potencia en una cuadrícula de un segundo, su media móvil de 30 s, cada media elevada a la cuarta potencia, se promedian y se saca la raíz cuarta. Una salida regular sale con su media; una salida de arreones y descansos sale más alta. Necesita al menos medio minuto de lecturas seguidas, y un hueco de más de cinco segundos en el medidor empieza un tramo nuevo. Con **Zonas de potencia** activado y un umbral configurado, aparece al lado **Intensidad**: la potencia normalizada dividida por tu potencia umbral, de modo que 0,80 es una salida a cuatro quintos de lo que puedes mantener durante una hora. Una salida grabada sin sensor no muestra nada de esto, y una salida importada de un archivo GPX, FIT o TCX muestra lo que traiga ese archivo. Consulta [sensores y tu reloj](./sensors-and-watch).

### Calorías, zonas de frecuencia cardiaca, zonas de potencia y potencia estimada

Las cuatro están desactivadas hasta que las activas en Ajustes → Ciclista, y las cuatro se calculan en el teléfono a partir de los propios puntos de la salida, así que las salidas antiguas también las tienen.

**Calorías** es una estimación, y la línea pequeña bajo la cifra dice en qué se basa. Con un medidor de potencia en toda la salida es el trabajo realizado, "por potencia": un kilojulio de pedaleo es casi exactamente una kilocaloría quemada. Si no, con frecuencia cardiaca en toda la salida y tu peso, año de nacimiento y sexo, es "por frecuencia cardiaca". Si no, con **Estimar potencia** activado, es "por potencia est.", de nuevo el trabajo estimado en kilojulios. Si no, es "por velocidad", a partir de tu peso y de lo rápido que fuiste. En todos los casos necesita tu peso.

**Potencia est.** solo aparece con el interruptor activado y solo en salidas sin medidor de potencia; una salida con medidor muestra el medidor y nada más. Es la media de lo que el modelo de potencia de Martin dice que tuviste que poner en los pedales para moverte a ti y a tu bici a la velocidad a la que fuiste por la pendiente por la que fuiste: a partir de tu velocidad, la pendiente y el peso total de ciclista y bici, suponiendo que no hay viento ni rebufo, un ciclista con las manos en las manetas, una resistencia a la rodadura fija por tipo de bici, una pérdida del 2,5 % en la transmisión y aire más fino con la altitud. Las alturas se suavizan sobre 50 m porque las alturas GPS dan saltos, y el trabajo se suma por medios minutos antes de descartar lo que quede por debajo de cero, así que una altura que sube y baja no cuesta nada; ir sin pedalear y frenar cuentan como cero, y acelerar se calcula con velocidades promediadas sobre diez segundos, que en ciudad es la mayor parte del trabajo. Espera que sea razonable en subidas largas, donde domina el peso; demasiado alta en un grupo rápido y errónea con viento, que no puede ver. Es una cifra para comparar tus propias salidas, no un medidor de potencia.

**Zonas de frecuencia cardiaca** es una barra bajo el gráfico de frecuencia cardiaca, dividida en cinco zonas de tu frecuencia cardiaca máxima, con una fila por zona: su rango, el tiempo en ella y su parte del tiempo con frecuencia cardiaca de la salida. La zona 1 es todo lo que está por debajo del 60 %, la zona 5 todo desde el 90 %. El título indica la máxima usada: la que introdujiste, o 220 menos tu edad.

**Zonas de potencia** es la misma barra para salidas con medidor de potencia, dividida en siete zonas de tu potencia umbral: por debajo del 55 %, 55–75, 75–90, 90–105, 105–120, 120–150 y desde el 150 %. Cada segundo de la salida va a la zona de la lectura del medidor en ese momento; el tiempo parado no cuenta en ninguna. El título indica el umbral, "Zonas de potencia · umbral 250 W". Necesita el interruptor y tu potencia umbral en Ajustes → Ciclista, y pone la cifra de **Intensidad** entre las casillas.

### Parciales

Una fila por parcial, con cuatro columnas: **Parcial**, **En movimiento**, **Media** y **Subida**. El título dice cuánto mide un parcial, "Parciales, cada 5 km". Por defecto la longitud se adapta a la salida: un kilómetro hasta 30 km, cinco hasta 150 km, diez a partir de ahí, en millas con unidades imperiales, para que la tabla siga siendo corta en una salida larga; **Longitud de los parciales** en Ajustes → Grabación la fija en 1, 5 o 10. La última fila es el resto, así que puede ser más corta que las demás. Detrás de cada fila, una barra muestra la velocidad media de ese parcial frente a tu parcial más rápido, lo que deja ver de un vistazo los tramos duros. Toca una fila para ver ese parcial sombreado en los gráficos y dibujado sobre el track en el mapa, donde un chip lo nombra, "Parcial 3 · 2–3 km"; vuelve a tocar la fila o el chip para quitarlo.

### Subidas

Bajo los parciales, en una salida que tuvo alguna, una tabla de **Subidas**: una fila por subida con **Inicio** (en qué punto de la salida empezó, "en el km 12,3"), **Longitud**, **Subida** y **Pendiente**, y una línea más discreta debajo con el tiempo en movimiento, la VAM y, si la salida los traía, la frecuencia cardiaca y la potencia medias en la subida. La VAM son los metros de altura ganados por hora de tiempo en movimiento, la medida habitual de lo rápido que se subió un puerto: 1000 m/h son cien metros cada seis minutos. Detrás de cada fila, una barra muestra el ascenso de esa subida frente a la mayor. Toca una fila para ver esa subida sombreada en los gráficos y dibujada sobre el track en el mapa, donde un chip la nombra, "Subida 1 · 0,5–2,5 km"; vuelve a tocar la fila o el chip para quitarla. Solo se resalta un tramo a la vez, sea un parcial o una subida.

Una subida se detecta igual que el perfil del panel de grabación detecta la que estás subiendo: empieza donde los siguientes 100 m de carretera suben al menos un 3 %, y termina en su punto más alto una vez que la carretera ha bajado 10 m por debajo de él, así que un descenso dentro de una subida larga no la parte en dos. No se muestran las subidas de menos de 300 m, de menos de 20 m de desnivel o con una media inferior al 3 % de pie a cima. Antes se suavizan las alturas sobre 50 m, como para la estimación de potencia, y las pausas no cuentan ni para el tiempo ni para la altura.

### Superficie

Una ruta leída de un archivo obtiene su **Superficie** del mismo modo, y por la misma razón: nadie la enrutó nunca, así que nada dijo nunca de qué está pavimentada. La primera vez que se abre una ruta así, su track se superpone a las teselas de rutas sin conexión y las proporciones se leen de las vías sobre las que cae, y se guardan con la ruta para que se calcule una sola vez. Valen las mismas salvedades (hay que tener descargada la región de enrutamiento, y un track que el mapa no puede seguir lo indica), y una ruta planificada aquí no se toca, porque el enrutador ya respondió. Las rutas guardadas de un archivo antes de que existiera esto se comparan la primera vez que las abres.

Bajo las subidas, una barra de **Superficie** como la de la tarjeta de una ruta: cuánto de la salida fue asfaltado, sin asfaltar o desconocido, con la proporción de carril bici y de carretera con tráfico al lado. La salida nunca se planificó, así que la app lo averigua después: superpone el track grabado a las teselas de rutas sin conexión del teléfono y lee la superficie de las vías sobre las que cae. Para esto ningún track sale del teléfono. Necesita que esté descargada la región de enrutamiento de la zona; hasta entonces, la sección lo indica. Un track que el mapa no puede seguir, por un parque, en un ferry o por un atajo, muestra en su lugar "No se pudo ajustar el track al mapa", y el resultado, en cualquier caso, se guarda con la salida, así que se calcula una sola vez. Una tesela de rutas nueva le da otra oportunidad a una salida sin ajustar.

### Acciones de la salida

- El botón de la nube a la derecha de la cabecera de la tarjeta sube la salida a un servicio conectado.
- El menú de al lado: **Exportar track GPX**, **Exportar actividad FIT**, **Continuar esta salida**, **Renombrar**, **Eliminar**.
- Abajo del todo: las mismas dos exportaciones y **Compartir enlace**.

## Meter archivos y rutas

Los dos botones a la derecha de la cabecera de la tarjeta:

- **Importar archivo** abre el selector de archivos del teléfono para un archivo GPX, FIT o TCX.
- El botón de la nube ofrece **Importar de Strava** e **Importar de Ride with GPS**, si esos servicios están configurados.

Ambos se explican en [importar y exportar](./import-and-export) y en [Strava y Ride with GPS](./strava-and-ridewithgps).

## Relacionado

- [Grabar una salida](./recording-a-ride)
- [Sensores y tu reloj](./sensors-and-watch)
- [Importar y exportar](./import-and-export)
- [Compartir](./sharing)
- [Strava y Ride with GPS](./strava-and-ridewithgps)
- [Planificar una ruta](./planning-a-route)
