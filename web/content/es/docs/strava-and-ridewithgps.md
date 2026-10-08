---
title: Strava y Ride with GPS
description: Conecta tu cuenta de Strava o de Ride with GPS para subir salidas grabadas e importar rutas, y entiende por qué enviar una ruta a Strava es un archivo.
order: 11
---

Velorki puede hablar con Strava y con Ride with GPS en tu nombre: subir una salida que grabaste y traer a tu biblioteca las rutas de esas cuentas. Conectar cualquiera de los dos servicios forma parte de [Velorki Plus](./velorki-plus); los archivos GPX, FIT y TCX siguen siendo gratis y hacen lo mismo a mano.

No se envía nada a ninguno de los dos servicios hasta que conectas tú la cuenta y luego pides algo.

## Conectar una cuenta

1. Abre **Ajustes** y busca la sección **Conexiones**.
2. Toca **Conectar con Strava** o **Conectar con Ride with GPS**.
3. Se abre en un navegador la propia página de inicio de sesión del servicio. Inicia sesión allí y aprueba el acceso.
4. Vuelves a Velorki, y la fila muestra tu nombre en lugar de **No conectado**.

Tu teléfono guarda el token de acceso en su almacenamiento seguro, en una forma que solo el servidor de Velorki puede abrir. A partir de ahí cada subida e importación pasa por ese servidor, que comprueba tu suscripción, abre el token para esa única petición y la reenvía. No guarda ni el archivo ni el token, y no puede usar el token por su cuenta.

Si falla un intento de conexión, Velorki dice «No se pudo conectar:» con el motivo. Cancelar la página de inicio de sesión no dice nada.

Una fila que dice **No disponible en esta versión** significa que esta versión de Velorki se compiló sin las claves de ese servicio, que es lo que pasa con una copia compilada por tu cuenta hasta que pongas las tuyas.

## Desconectar

Toca **Desconectar** en la fila conectada. Velorki pregunta «¿Desconectar Strava?» y explica: «Velorki olvida el token de acceso. Las rutas y salidas que ya están en la biblioteca se quedan.»

Desconectar también le pide al servicio que revoque el acceso de Velorki, cuando se puede contactar con el servidor. No elimina nada de Strava ni de Ride with GPS, ni nada de tu biblioteca.

## Subir una salida

1. Abre la salida en **Biblioteca → Salidas**.
2. Toca el botón de la nube arriba a la derecha, con la etiqueta **Subir**.
3. Elige **Subir a Strava** o **Subir a Ride with GPS**.

Velorki dice «Subiendo a Strava…» y luego «Subida a Strava» con una acción **Ver en Strava** que la abre. Una salida que ya está allí nunca se sube dos veces: la entrada del menú pasa a ser **Ver en Strava** o **Abrir en Ride with GPS**.

Una subida a Strava puede tardar un rato, porque Strava procesa el archivo antes de que exista como actividad; Velorki lo espera y enlaza al resultado.

## Importar rutas

1. Abre la pestaña **Biblioteca**.
2. Toca el botón de la nube arriba a la derecha y elige **Importar de Strava** o **Importar de Ride with GPS**.
3. La lista se titula **Rutas de Strava** o **Rutas de Ride with GPS**. Cada fila muestra el nombre, la distancia, el desnivel y la fecha.
4. Toca **Importar** en la que quieras. Llega a tu biblioteca como una ruta normal, y Velorki dice «Vuelta alpina importada».

El pie dice **Leídas 16 sept 2026**, el momento en que se descargó la lista. Velorki la guarda hasta siete días, como exigen las condiciones de Strava, y **Actualizar** arriba a la derecha la vuelve a descargar.

Si la cuenta no está conectada, la pantalla dice «Primero conecta Strava en Ajustes → Conexiones.»

## Enviar una ruta a Ride with GPS

Abre la ruta, toca **Enviar** y elige **Enviar a Ride with GPS**. Se sube a tu cuenta y Velorki ofrece **Abrir** para verla allí.

## Enviar una ruta a Strava

La API de Strava puede leer rutas pero no crearlas, así que Velorki no tiene adónde subirla. Por eso, elegir **Enviar a Strava** abre una explicación:

> **Strava no puede recibir rutas** La API de Strava puede leer rutas, pero no crearlas. En su lugar, Velorki exporta un archivo GPX: compártelo e impórtalo en strava.com.

Toca **Exportar GPX**, guarda o envía el archivo y súbelo como ruta en strava.com. Ese camino es gratis y no necesita ninguna conexión.

## Qué es gratis y qué necesita Plus

| | Necesita Plus |
|---|---|
| Conectar Strava o Ride with GPS | sí |
| Subir una salida a cualquiera de los dos | sí |
| Importar rutas de cualquiera de los dos | sí |
| Enviar una ruta a Ride with GPS | sí |
| Exportar GPX, FIT o TCX y subirlo tú mismo | no |
| Importar un archivo GPX, FIT o TCX de cualquiera de los dos servicios | no |

## Una nota sobre el asistente y Strava

**Describir esta ruta** no se ofrece para una ruta que vino de Strava. Las condiciones de la API de Strava no permiten enviar sus datos a un proveedor de IA, así que Velorki oculta el botón en lugar de incumplirlas.

## Relacionado

- [Velorki Plus](./velorki-plus)
- [Importar y exportar](./import-and-export)
- [Biblioteca](./library)
- [Asistente](./assistant)
- [Privacidad en el teléfono](./privacy-on-the-phone)
