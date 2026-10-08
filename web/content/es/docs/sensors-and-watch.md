---
title: Sensores y tu reloj
description: Frecuencia cardiaca, cadencia y potencia de un sensor Bluetooth, un Apple Watch o la app de salud de tu teléfono, configurados una vez y guardados con cada salida.
order: 16
---

Velorki puede mostrar tu frecuencia cardiaca, tu cadencia de pedaleo y tu potencia mientras grabas, y guardar las tres con la salida después. Los datos vienen de un sensor Bluetooth, de un Apple Watch o de la propia app de salud del teléfono, y todo ello es gratis y funciona en el teléfono.

Nada de esto ocurre hasta que lo activas. Con todas las fuentes desactivadas, Velorki no le pide nada al sistema operativo y ninguna pantalla menciona un sensor.

## Qué puedes medir

| Fuente | Qué da | Qué necesita |
|---|---|---|
| Sensor Bluetooth | frecuencia cardiaca, cadencia, velocidad de rueda, potencia | el sensor, emparejado una vez en Velorki |
| Apple Watch | frecuencia cardiaca, y la salida en tu muñeca | un iPhone con un reloj emparejado |
| Apple Health o Health Connect | la frecuencia cardiaca que otra cosa escribió en el teléfono | la app de salud del teléfono, y un interruptor |

Cuando dos de ellas informan de lo mismo a la vez, el reloj gana a un sensor Bluetooth, y un sensor Bluetooth gana a la app de salud. Una lectura cuenta como actual durante diez segundos, y cuando la fuente que iba ganando se calla, la siguiente toma el relevo sola, así que una banda que te dejaste en casa simplemente no está.

## Activar una fuente

Todo está en **Ajustes → Sensores**, justo debajo de **Grabación**:

- **Apple Health** en un iPhone, **Health Connect** en Android, con la línea «Lee el pulso que otras apps guardan en Salud, como la app Entreno del reloj. Se consulta cada pocos segundos, así que va con retraso; una banda o la app de Velorki para el reloj toman el relevo cuando envían datos». Activarlo es lo único de Velorki que puede mostrar la solicitud de permiso de salud. Si la rechazas, Velorki dice «Velorki no tiene acceso a tus datos de salud.» y deja el interruptor apagado.
- **Guardar salidas en Salud** debajo, «Cada salida terminada se guarda en Salud como un entrenamiento de ciclismo con su inicio, final y distancia», que puedes desactivar por separado. No hace nada mientras el interruptor de encima está apagado.
- **Apple Watch**, con la línea «La app de Velorki para el reloj: mide tu pulso en directo durante toda la salida, muestra la salida y tiene Iniciar, Pausa y Terminar en la muñeca. Gasta batería del reloj». La fila solo aparece en un iPhone que tiene un reloj emparejado. **Reposo del sensor en pausa**, debajo, se explica en [batería en la muñeca](#batería-en-la-muñeca).
- **Sensores Bluetooth**, con la línea «Bandas de pulso, sensores de velocidad y cadencia, potenciómetros», o «1 sensor vinculado» cuando ya tienes uno. Abre una pantalla propia.

## Sensores Bluetooth

### Emparejar un sensor

1. Despierta el sensor: ponte la banda o gira las bielas. La mayoría de los sensores no dicen nada hasta que se usan.
2. Abre **Ajustes → Sensores → Sensores Bluetooth** y toca **Buscar**. En un iPhone la pantalla avisa «iOS pide permiso de Bluetooth la primera vez que buscas.» antes de que toques. Una búsqueda dura unos quince segundos.
3. En **Encontrados**, toca el sensor que reconozcas. Cada fila tiene su nombre, pequeños iconos de lo que mide y la intensidad de su señal en dBm, con el más fuerte arriba.
4. Velorki se conecta una vez para preguntarle al dispositivo qué tiene realmente, lo guarda en **Vinculados** y lo vuelve a soltar.

Mientras esa pantalla está abierta tus sensores emparejados están conectados, así que cada fila muestra lo que está diciendo ahora mismo en lugar de **Conectado**, **Conectando…** o **No conectado**. Al salir de la pantalla se vuelven a desconectar, salvo que se esté grabando una salida. **Olvidar**, en el menú a la derecha de una fila emparejada, elimina un sensor.

### Con qué se empareja Velorki

Los tres perfiles estándar de ciclismo, que es lo que habla casi todo lo que se vende como sensor de bici:

- **bandas de frecuencia cardiaca** y brazaletes,
- **sensores de velocidad y cadencia**, en la rueda, en la biela o un único dispositivo que hace ambas cosas,
- **potenciómetros**, cuyos contadores de biela también dan una cadencia, así que con un potenciómetro no hace falta un sensor de cadencia aparte.

Un dispositivo que no habla ninguno de los tres no se ofrece. Velorki se empareja con sensores, no con ciclocomputadores: una unidad de manillar es otra cosa y aquí no se conecta.

### Circunferencia de la rueda

Un sensor de velocidad cuenta vueltas de rueda, así que hay que decirle a Velorki cuánto mide una vuelta. El campo **Circunferencia de la rueda** aparece al pie de la pantalla en cuanto un sensor emparejado informa de velocidad, con la indicación «Milímetros por vuelta de rueda. 2105 corresponde a una cubierta 700x25c.» y **mm** tras el número.

Mientras un sensor de rueda informa, su velocidad sustituye a la velocidad GPS en el panel de Grabar, que es justo para lo que sirve: una rueda acierta a paso de peatón, bajo los árboles y en un túnel, donde el GPS no. Nada más en la salida la usa.

### Cuando no se encuentra un sensor

- **«Nada por ahora. Despierta el sensor: ponte la banda o gira las bielas.»** Una banda sin contacto con la piel y una biela parada son invisibles. Muévete y vuelve a buscar.
- **«Activa el Bluetooth para encontrar tus sensores.»** La radio del teléfono está apagada.
- **«Velorki no tiene permiso para usar Bluetooth.»** Se rechazó el permiso. Concédeselo a Velorki en los ajustes del teléfono y vuelve a buscar.
- **El sensor está hablando con otra cosa.** Estos sensores atienden a un dispositivo a la vez. Cierra la otra app o apaga la unidad de manillar.
- **Un sensor emparejado que dice Sin conectar** está fuera de alcance, dormido o sin batería. Velorki sigue intentándolo mientras se graba una salida o esa pantalla está abierta, esperando un poco más tras cada intento.

## Apple Watch

La app del reloj es una pantalla y un sensor, nunca una segunda grabadora. El teléfono graba la salida; el reloj envía lo que mide y lo que tocas, y dibuja lo que el teléfono le devuelve.

### Conseguir la app del reloj

La app de Velorki para el reloj viene dentro de la app del iPhone. Llega al reloj sola si tu reloj instala automáticamente las apps complementarias; si no, abre la app **Watch** en el iPhone e instala Velorki desde la lista de apps disponibles. Después activa **Apple Watch** en **Ajustes → Sensores**; eso también pide una vez permiso para enviar notificaciones, para la que se describe bajo los botones. La primera vez que empieza un entrenamiento en el reloj, el reloj pide permiso para leer tu frecuencia cardiaca. Esa solicitud viene del reloj, no del teléfono.

### Qué muestra el reloj

- Tu **frecuencia cardiaca** en cifras grandes, con el corazón latiendo mientras el reloj mide; dos guiones mientras no mide nada, y la última lectura atenuada mientras la salida está en pausa. El corazón y los botones toman el color de acento que elegiste en la app.
- Una línea en naranja cuando algo va mal: acceso a Salud rechazado, un entrenamiento que el reloj no quiso iniciar o un teléfono que no respondió.
- Mientras corre una salida, su distancia, el cronómetro y la velocidad, y **En pausa** cuando está en pausa. Todo lo formatea el teléfono, así que está en tus unidades y tu idioma.
- El siguiente giro con su icono, su nombre y la distancia hasta él, como en la pantalla de bloqueo, en naranja mientras estás fuera de la ruta; en cuanto se calcula un camino de vuelta o una ruta nueva, sus giros.
- Un toque en la muñeca cuando toca una indicación de giro, y uno cuando te sales de la ruta. Un reloj que se ha dormido durante tres giros da un solo toque en lugar de tres.

Las palabras propias del reloj, es decir, los botones y las dos notas al pie, están en inglés sea cual sea el idioma del teléfono. Todavía no hay complicaciones.

### Qué hacen los botones

| Botón | Qué hace |
|---|---|
| **Iniciar salida** | empieza la grabación en el teléfono |
| **Pausa**, **Reanudar** | pausan la salida y continúan, como en el teléfono |
| **Terminar** | detiene la grabación; "Tras «Terminar», guardas la salida en el teléfono." |
| **Dejar de medir** | termina la medición en el reloj mientras sigue la salida |
| **Medir el pulso** | la vuelve a empezar, o la empieza para una salida en la que la app del reloj se abrió tarde |

Cuando empieza una salida en el teléfono, la app del reloj se abre sola y empieza a medir, así que no hay nada que tocar en la muñeca. Al revés, **Iniciar salida** en el reloj empieza la grabación en el teléfono y lleva el teléfono a su pestaña **Grabar**. Un teléfono en el bolsillo, con Velorki en segundo plano, recibe una notificación, «Salida iniciada desde tu reloj», y al tocarla se abre la app; eso importa porque iOS no da GPS a una app despertada en segundo plano hasta que se ha abierto una vez, así que el track empieza entonces. Una app que has cerrado del todo deslizándola no puede despertarla el reloj de ninguna manera, que es una regla de iOS; tras unos intentos el reloj dice "El teléfono no responde. Abre Velorki en el teléfono y vuelve a intentarlo." Una salida que terminas desde la muñeca se guarda como cualquier otra: la grabación se detiene, y el panel de guardar te espera en el teléfono la próxima vez que lo mires.

### Batería en la muñeca

Medir el pulso durante horas es lo que le cuesta al reloj su día. La medición dura toda la salida, pausas incluidas: watchOS duerme en menos de un minuto a una app del reloj que deja de medir, y después ya no oye nada del teléfono, así que mantenerla despierta es lo que mantiene llegando el pulso. El teléfono no graba pulso mientras la salida está en pausa. Para salidas con muchas paradas, **Reposo del sensor en pausa**, bajo el interruptor de Apple Watch en Ajustes, hace que el reloj deje de medir en cada pausa. El precio: el sensor descansa en cada parada, pero el teléfono tiene que volver a despertar el reloj cuando sigues pedaleando, el primer pulso tras cada parada tarda un momento, y si falla el despertar el pulso falta hasta que el teléfono lo vuelve a intentar. Déjalo desactivado para un pulso sin cortes. Si el reloj se calla tres cuartos de minuto en plena salida, el teléfono vuelve a abrir su app solo. **Dejar de medir** termina la medición sin tocar la salida. La nota al pie de la pantalla dice el resto, "Con el modo de bajo consumo en los ajustes del reloj, la batería aguanta una salida larga." Desactivar **Apple Watch** en Ajustes también termina una sesión que siga en marcha.

## Apple Health y Health Connect

Esta fuente es la frecuencia cardiaca que tu teléfono ya conoce: lo que un Apple Watch escribió con su propio entrenamiento, o lo que otra app guardó en el almacén. Es la más lenta y la menos en directo de las tres, y una banda o un reloj que informan directamente le toman el relevo al instante.

### Qué se lee y qué se escribe

- **Se lee**: la frecuencia cardiaca, y nada más. Mientras se graba una salida, Velorki pide al almacén muestras nuevas cada cinco segundos, o cada treinta con **Ahorro de batería** activado.
- **Se completa después**: al guardar la salida, las muestras del almacén rellenan los puntos del track que no tienen frecuencia cardiaca, siempre que haya una muestra a menos de medio minuto del punto, y se vuelven a calcular las cifras de la salida. Un punto que recibió una lectura en directo de una banda o un reloj conserva esa.
- **Se escribe**: un entrenamiento de ciclismo por salida, con su inicio, su final y su distancia, y solo con **Guardar salidas en Salud** activado. Cada salida se escribe una vez. Con ese interruptor desactivado, Velorki solo lee.

## Dónde aparecen las cifras

### Mientras pedaleas

En el panel de Grabar aparece una tercera fila de cifras con lo que se haya recibido durante la salida: **Frecuencia cardiaca** con la **Pulso medio** de la salida debajo, **Cadencia** y **Potencia**, así que un reloj solo añade una casilla y sin sensores no se añade nada. Un sensor que se calla conserva su casilla, atenuada y marcada con un enlace roto, hasta que termina la salida. En un iPhone el pulso se suma a las cifras de la tarjeta de la pantalla de bloqueo y de la Dynamic Island.

### En una salida guardada

La ficha de una salida en la [biblioteca](./library) añade lo que esa salida realmente lleva:

- **Pulso medio**, **Pulso máx.**, **Cadencia media** y **Potencia media** entre las cifras, cada una solo si la salida la tiene,
- un gráfico de **Frecuencia cardiaca** bajo el de velocidad, que puedes recorrer arrastrando para leer el valor a cualquier distancia.

La tabla de **Parciales** no cambia: **Parcial**, **En movimiento**, **Media** y **Subida**, sin columnas de sensores. Una salida importada de un archivo GPX, FIT o TCX trae su frecuencia cardiaca, cadencia y potencia y las muestra igual.

## Qué se guarda y qué sale del teléfono

Las lecturas forman parte de la salida: un valor de frecuencia cardiaca, uno de cadencia y uno de potencia en cada punto del track, y las medias y la frecuencia cardiaca máxima entre sus cifras. Viven en el almacenamiento propio de Velorki en el teléfono, con el track.

No se sube nada por sí solo. Una exportación GPX, FIT o TCX lleva los valores junto con el track, así que una salida que exportas o envías a Strava o Ride with GPS llega completa. El intercambio con Apple Health o Health Connect ocurre en el teléfono. Consulta [privacidad en el teléfono](./privacy-on-the-phone) para verlo entero.

## Relacionado

- [Grabar una salida](./recording-a-ride)
- [Biblioteca](./library)
- [Ajustes y apariencia](./settings-and-appearance)
- [Privacidad en el teléfono](./privacy-on-the-phone)
- [Solución de problemas](./troubleshooting)
