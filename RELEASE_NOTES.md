# VaDa Network Discover 0.2.3

Actualización correctiva para documentos guardados por versiones anteriores que contienen accidentalmente más de un registro con la misma IP.

Incluye:

- evita que un refresco vuelva a conservar dos equipos con el mismo identificador;
- repara automáticamente los documentos afectados al abrirlos;
- conserva el registro descubierto más recientemente y las anotaciones manuales del equipo;
- corrige el estado inconsistente que podía mostrar el registro reparado como no detectado;
- evita el cierre inesperado de la App al reconstruir la comparación del último refresco;
- mantiene sin cambios el formato del documento y la compatibilidad con escaneos anteriores.

Esta versión no añade tráfico de red, telemetría ni servicios externos. La reparación se realiza localmente al abrir el archivo.

La build macOS está firmada ad-hoc y no notarizada por Apple.
