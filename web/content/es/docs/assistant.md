---
title: Asistente
description: Describe en una frase la salida que quieres y Velorki la convierte en una ruta, con tu consentimiento, como mucho una posición aproximada y sin enviar tu historial de rutas.
order: 12
---

El asistente convierte una frase como "una ruta circular de gravel de unos 80 km con parada en un café" en una ruta en el planificador. Es la única parte de Velorki que envía lo que escribes a un servidor, así que primero te pide tu consentimiento y te dice exactamente qué se envía.

El asistente forma parte de [Velorki Plus](./velorki-plus).

## Abrirlo

Toca **Preguntar** en la barra de herramientas del panel de ruta, en la pestaña **Planificar**. La tarjeta del asistente ocupa el lugar del panel de ruta, con el título **Pide una ruta**: "Describe la salida que tienes en mente. Velorki la convierte en una petición y planifica la ruta en tu teléfono." El mapa de arriba sigue siendo el mapa: muévelo, haz zoom y tócalo igual que con el panel de ruta abierto. Desliza la tarjeta hacia abajo, o vuelve atrás, y el panel de ruta reaparece tal como lo dejaste; lo que escribiste y las respuestas se quedan para la próxima vez.

Si hay una ruta en el mapa, el panel se abre en **Esta ruta**, con una pregunta sobre esa ruta (consulta [Preguntar sobre esta ruta](#preguntar-sobre-esta-ruta)); **Ruta nueva**, encima, vuelve al otro modo.

Si no aparece el botón **Preguntar**, esta versión de Velorki no tiene ninguna dirección de servidor, como ocurre con una copia compilada por tu cuenta sin relay propio.

## Consentimiento, y qué sale del teléfono

La primera vez que envías algo, Velorki muestra **Antes de que el asistente pregunte**:

> Lo que escribes se envía al servidor de Velorki, que lo reenvía a nuestro proveedor de IA. No va nada más: ni nombre, ni cuenta, ni historial de rutas.
>
> Si lo permites, también se envía tu posición, redondeada a aproximadamente un kilómetro, para que "desde aquí" signifique algo.

Tres respuestas:

- **Permitir, con mi posición aproximada** envía tu texto y una posición redondeada a aproximadamente un kilómetro.
- **Permitir, solo texto** envía tu texto y nada más.
- **Ahora no** no envía nada y desactiva el asistente.

Lo que se envía realmente: tu texto, opcionalmente la posición redondeada, tus ajustes de idioma y unidades para que la respuesta encaje y, para la descripción de una ruta o una pregunta sobre una ruta, un resumen de la ruta (ver más abajo). En la petición no va ningún identificador tuyo ni de tu teléfono.

Puedes cambiar de opinión en cualquier momento en **Ajustes → Asistente de IA → Qué se envía**, cuyo subtítulo siempre indica en cuál de los cuatro estados estás, con un botón **Cambiar** al lado.

## Pedir algo

Escribe una frase y toca **Preguntar**. Hay tres ejemplos para tocar:

- **Una ruta circular llana de 30 km desde aquí**
- **60 km hasta Friburgo por carreteras tranquilas**
- **Una ruta circular de gravel de unos 80 km con parada en un café**

Otras cosas que funcionan bien: una distancia y una dirección, un lugar por el que pasar, un tipo de superficie, cuánto desnivel quieres, un inicio que no sea donde estás.

El panel muestra **Pensando…** mientras el modelo responde y luego **Buscando los lugares…** mientras los nombres de lugar se convierten en coordenadas. Después resume lo que ha entendido: "Ruta circular de unos 80 km", "Empezando donde estás" o "Empezando en Friburgo", y un chip por cada lugar por el que pasar.

Si un nombre coincide con varios lugares muy separados, Velorki pregunta **¿Qué Friburgo?** con hasta tres opciones. Al tocar una se resuelve en el teléfono, sin volver a consultar al modelo.

## Qué pasa con la respuesta

El panel se cierra solo y el planificador toma el relevo:

- **Una ruta circular sin ningún lugar concreto por el que pasar** abre el [panel de rutas circulares](./loops) con la búsqueda ya en marcha. Cuando termina la búsqueda, el panel de rutas circulares se cierra y el asistente vuelve en **Esta ruta**, con lo que pediste encima de la pregunta, para que puedas preguntar por la ruta circular enseguida. Si la búsqueda no encontró ninguna ruta circular, vuelve en **Ruta nueva** y lo dice. Si cierras el panel de rutas circulares o haces algo en él mientras busca, la búsqueda pasa a ser tuya: el asistente no interviene.
- **Una ruta circular por lugares con nombre** se convierte en puntos de paso con la ruta cerrada, y Velorki dice "La ruta está en el mapa."
- **Una ruta de punto a punto** se convierte en puntos de paso con el perfil de bici elegido, y de nuevo "La ruta está en el mapa."

A partir de ahí es una planificación normal: edítala, pide variantes, guárdala.

## Lo que no hace

El modelo nunca devuelve coordenadas ni calcula una ruta. Devuelve una petición estructurada, una distancia, una forma, algunos nombres de lugar y una o dos preferencias, y todo lo demás ocurre en tu teléfono. Por eso el asistente sirve para expresar lo que quieres, y no como fuente de datos sobre las carreteras.

También puede equivocarse. Si dice algo que no querías decir, reformúlalo con una distancia clara y un lugar claro.

## Preguntar sobre esta ruta

Con una ruta en el mapa del planificador, **Preguntar** se abre en **Esta ruta**: "Pregunta lo que quieras sobre la ruta del mapa." Ejemplos para tocar: **Revisa esta ruta**, **¿Dónde puedo tomar un café a mitad de camino?**, **¿Dónde puedo rellenar agua?**, **Evita la carretera principal**, **¿Sirve para bici de carretera?**

Lo que se envía: tu pregunta y el resumen de la ruta descrito en [Describir esta ruta](#describir-esta-ruta), con las posiciones. Tu propia posición no se envía en este modo.

La respuesta son unas pocas frases y hasta seis hallazgos a lo largo de la ruta, cada uno con dónde está. **Mostrar** lleva el mapa hasta allí. Un hallazgo sobre el que el planificador puede actuar tiene un botón:

- **Añadir como parada** hace pasar la ruta por un café, una fuente u otro lugar del resumen, insertado donde la ruta pasa junto a él.
- **Evitar** aparta al enrutador de ese tramo. Se dibuja discontinuo en el mapa, y el chip **Evitando 1 tramo** sobre el mapa tiene **Permitir de nuevo**.
- **Usar Gravel** (u otra bici) vuelve a planificar la ruta con ese perfil.

Cada uno es un solo paso que **Deshacer** revierte, y el panel sigue abierto y lo marca como **Aplicado**. El modelo solo sugiere lugares del resumen; nunca se inventa una parada ni una coordenada.

**Esta ruta** no está disponible para una ruta importada de Strava.

## Describir esta ruta

La otra cosa que hace el asistente es escribir un párrafo sobre una ruta que ya tienes. Abre una ruta en la biblioteca y toca **Describir esta ruta**; el panel empieza a escribir enseguida y **Guardar como descripción** guarda el texto con la ruta. **Volver a escribir** pide otro intento.

Antes de preguntar, el teléfono cruza la ruta con sus teselas de rutas y su búsqueda de lugares sin conexión y prepara un resumen: la distancia, el desnivel positivo, la proporción de asfalto y de tierra, los nombres de los puntos de paso, los tramos de la ruta con su tipo de vía, superficie y pendiente, sus subidas, las ciudades y pueblos por los que pasa, y los cafés, panaderías, fuentes de agua, aseos, miradores y tiendas de bicis a menos de 300 m, cada uno con su distancia a lo largo de la ruta y su posición. Sin teselas descargadas para la zona solo se envían las cifras. El modelo recibe también las posiciones, con unos 10 m de precisión, para saber por dónde va la salida; una ruta que empieza en tu puerta muestra dónde está tu puerta. Todos los lugares que nombra la descripción salen del resumen, así que puede decir "el café de Caniço en el km 9" y referirse a un café que existe. Escribe en el idioma y las unidades configurados en la app.

El botón no está disponible para una ruta importada de Strava, porque las condiciones de Strava no permiten entregar sus datos a un proveedor de IA.

## Límites y errores

El asistente tiene un límite de uso: veinte peticiones por hora y cien al día.

| Lo que dice el panel | Qué significa |
|---|---|
| "Demasiadas peticiones. Inténtalo de nuevo en 90 segundos." | has llegado al límite de uso |
| "El asistente de IA forma parte de Velorki Plus." | no hay suscripción |
| "El asistente necesita tu consentimiento antes de poder enviar nada." | falta el consentimiento o lo has rechazado |
| "No estoy seguro de haberlo entendido. Prueba a indicar una distancia y un lugar." | el modelo no estaba seguro |
| "No encontré «Friburgo». Prueba otra grafía o una localidad cercana." | no se pudo resolver el nombre del lugar |
| "Necesito saber dónde empezar. Activa la ubicación o indica un lugar de inicio." | "desde aquí" sin posición |
| "El asistente no pudo responder:" | ha fallado el servidor o el modelo |

**Reintentar** borra el error y conserva lo que escribiste.

## Informar de una respuesta errónea

**Ajustes → Asistente de IA → Informar sobre una respuesta de IA** abre un correo para nosotros: "Cuéntanos sobre una respuesta errónea o inapropiada." Úsalo, por favor. Las respuestas erróneas e inapropiadas son las que nos permiten corregir las instrucciones.

## Relacionado

- [Velorki Plus](./velorki-plus)
- [Rutas circulares](./loops)
- [Planificar una ruta](./planning-a-route)
- [Privacidad en el teléfono](./privacy-on-the-phone)
