# Security Best Practices Notes

## Resumen ejecutivo

Se ha revisado VaDa Network Discover con la skill `security-best-practices`. La skill no incluye referencias específicas para Swift, SwiftUI o apps macOS, así que esta revisión aplica buenas prácticas generales: entrada de usuario, límites de ejecución, llamadas de red, procesos del sistema, datos exportados y alcance responsable.

No se han encontrado hallazgos críticos en esta pasada. La documentación pública debe dejar claro que la herramienta solo se usa en redes propias o autorizadas, que los resultados son sensibles y que la huella HTTPS es permisiva para facilitar inventario local.

## Controles existentes

| Control | Evidencia | Comentario |
| --- | --- | --- |
| Límite de hosts | `Sources/NetworkDiscoveryCore/Models.swift#L84-L106`, `Sources/NetworkDiscoveryCore/IPv4Network.swift#L56-L80` | La configuración incluye `maximumHosts` y el parser IPv4 rechaza segmentos demasiado grandes. |
| Validación de puertos | `Sources/NetworkDiscoveryCore/PortCatalog.swift#L39-L82` | Solo acepta puertos `1...65535`, deduplica y reporta errores de formato. |
| Timeouts | `Sources/NetworkDiscoveryCore/HTTPFingerprint.swift#L15-L23`, `Sources/NetworkDiscoveryCore/PingProbe.swift#L25-L35`, `Sources/NetworkDiscoveryCore/MACAddressProbe.swift#L23-L42` | Las pruebas de red y procesos externos no quedan abiertas indefinidamente. |
| Procesos sin shell | `Sources/NetworkDiscoveryCore/PingProbe.swift#L8-L19`, `Sources/NetworkDiscoveryCore/MACAddressProbe.swift#L8-L18` | `ping` y `arp` usan rutas absolutas y argumentos estructurados con `Process`, no interpolación en shell. |
| Sesión HTTP efímera | `Sources/NetworkDiscoveryCore/HTTPFingerprint.swift#L15-L23` | No persiste cookies ni caché durante fingerprinting. |
| Exportación explícita | `Sources/NetworkDiscoverApp/AppModel.swift#L516-L575` | CSV/JSON se escriben solo mediante panel elegido por el usuario. |
| Apertura de documentos acotada | `Sources/NetworkDiscoverApp/AppModel.swift#L590-L609` | La carga está restringida a JSON seleccionado por el usuario. |

## Decisiones conscientes

### HTTPS permisivo para inventario local

`PermissiveHTTPSDelegate` acepta el trust del servidor cuando la app toma huellas HTTPS. Esto evita que certificados autofirmados de equipos locales impidan leer cabecera `Server` o título HTML.

Esta decisión es aceptable para el alcance actual porque:

- la app no envía credenciales;
- la conexión se usa como señal de inventario, no como canal de confianza;
- el resultado se limita a metadatos de servicio;
- el README y `SECURITY.md` lo documentan explícitamente.

Si en el futuro la app autentica usuarios o envía secretos a servicios descubiertos, esta decisión debe revisarse antes de añadir esa funcionalidad.

### Build firmada ad-hoc

La release inicial se firma ad-hoc y no está notarizada por Apple. Es válido para una primera publicación open source, pero conviene documentarlo para evitar falsas expectativas sobre Gatekeeper.

## Buenas prácticas operativas

1. Ejecutar escaneos solo con autorización explícita.
2. Empezar por segmentos pequeños, por ejemplo `/24` o rangos concretos.
3. Ajustar `timeout` y `concurrency` según la red para evitar ruido innecesario.
4. Tratar JSON, CSV, PNG y Mermaid exportados como inventario sensible.
5. No adjuntar capturas reales de redes de cliente en issues públicos.
6. Revisar cualquier cambio que añada autenticación, credenciales, descubrimiento remoto no local o subida de datos.

## Mejoras futuras recomendadas

- Añadir notarización para releases macOS cuando haya certificado de distribución.
- Añadir una confirmación visible antes de escanear segmentos grandes.
- Añadir una opción para desactivar fingerprint HTTP/HTTPS si una instalación quiere solo TCP connect.
- Añadir tests de límites para CLI cuando se pasen timeouts o concurrencias extremos.
- Añadir un ejemplo de JSON anonimizado para documentación y pruebas.

## Alcance fuera de esta revisión

- Auditoría criptográfica.
- Threat model completo.
- Revisión de supply chain de GitHub Actions.
- Pruebas dinámicas en redes reales.
- Notarización y distribución App Store.
