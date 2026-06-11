# Security Policy

## Uso previsto

VaDa Network Discover está diseñado para descubrir equipos y puertos abiertos en redes locales propias o explícitamente autorizadas.

No está diseñado como herramienta ofensiva, no intenta explotar servicios y no debe ejecutarse contra redes de terceros sin permiso.

## Modelo de seguridad

- El descubrimiento se ejecuta localmente desde la máquina del usuario.
- No hay backend, telemetría ni envío de resultados a terceros.
- Los escaneos tienen timeouts, concurrencia limitada y un máximo de hosts por configuración.
- La huella HTTPS acepta certificados autofirmados porque muchos equipos locales usan certificados propios; no debe interpretarse como validación de identidad remota.
- La app no solicita credenciales, no intenta autenticarse en servicios detectados y no explota vulnerabilidades.

## Reportar problemas de seguridad

Para vulnerabilidades o comportamientos que puedan afectar a usuarios, abre un reporte privado mediante GitHub Security Advisories si está habilitado en el repositorio.

Si no puedes usar un advisory privado, abre un issue con una descripción general y evita publicar datos sensibles, credenciales, IPs privadas de clientes o pasos de abuso reproducibles contra terceros.

## Datos sensibles

Los ficheros JSON exportados por la app pueden contener IPs, nombres de host, MACs, puertos abiertos, secciones, anotaciones y mapas de red. Trátalos como información sensible de la instalación.

Consulta también [docs/security-best-practices.md](docs/security-best-practices.md) para la revisión ligera de buenas prácticas aplicada al proyecto.
