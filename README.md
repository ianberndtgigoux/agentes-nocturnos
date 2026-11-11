# agentes-nocturnos

Cómo endurecí ocho agentes de Claude que corren solos de madrugada, sin supervisión, sobre
datos que un tercero puede escribir.

Esto es una extracción de un sistema privado en producción. El código de dominio no está —
lo que está es la parte que vale la pena copiar: el modelo de permisos, el runner y el
razonamiento de por qué quedó así.

---

## El sistema

Ocho agentes, uno por tipo de informe, cada uno con su horario en `launchd`. Cada corrida:

1. El **runner** resuelve qué período le toca analizar y se lo pasa resuelto al agente.
2. Invoca `claude -p` con el prompt del tipo y permisos acotados.
3. El agente consulta datos, redacta, publica y verifica — todo a través de herramientas
   con contrato fijo, nunca tocando la base directamente.
4. La última corrida programada del día manda un correo con lo que se publicó.

Una decisión temprana que se paga sola: **el agente no calcula fechas**. El runner le entrega
el período ya resuelto. Una fecha mal calculada por el modelo es un dato inventado, y "nunca
inventar datos" aplica también a las fechas.

## El problema

La primera versión corría con `--dangerously-skip-permissions`. Shell sin restricción y
lectura de archivos sin restricción, en el mismo directorio que un `.env.local` con la master
key de la base — lectura y escritura sobre **todos** los contenedores — más las credenciales
del proveedor bancario y del servicio de correo.

Y el agente analizaba movimientos bancarios.

En Chile cualquiera puede transferirte plata con la glosa que quiera. Esa glosa es texto
arbitrario, controlado por un desconocido, y llegaba literal al prompt.

Un vector de inyección de instrucciones con radio de daño total, operando de madrugada, sin
nadie mirando. El agente no necesitaba ser engañado de forma sofisticada: bastaba con que
siguiera una instrucción que llegó dentro de los datos.

## La corrección: tres capas

Ninguna de las tres depende de que el modelo "decida bien". Las tres son estructurales.

### 1. Permisos acotados por herramienta

```jsonc
{
  "permissions": {
    "defaultMode": "default",
    "allow": [
      "Bash(npx tsx scripts/consultar-datos.ts *)",
      "Bash(npx tsx scripts/leer-informes.ts *)",
      "Bash(npx tsx scripts/publicar-informe.ts *)",
      "Edit(//tmp/*)"
    ],
    "deny": [
      "Read(//ruta/al/repo/**)"
    ],
    "disableBypassPermissionsMode": "disable"
  }
}
```

Tres comandos exactos, por prefijo. `Edit` solo dentro de `/tmp`. Y un `deny` explícito de
`Read` sobre **todo el directorio del repo**, `.env.local` incluido: el agente no necesita
leer ningún archivo del proyecto, solo los que él mismo genera en `/tmp`.

Con `defaultMode: "default"` cualquier otra cosa se deniega sola. El agente no tiene que
abstenerse: no puede.

La regla al agregar un comando nuevo es **prefijo exacto, nunca comodín amplio**.
`Bash(npx *)` no es una restricción, es un permiso con pasos extra.

### 2. Recortar el set de herramientas

```
--tools="Bash,Read,Write"
```

Sin `Task`, sin `WebFetch`, sin `WebSearch`. Aunque el archivo de permisos no diga nada
sobre ellas, no existen para esta corrida. Un agente que procesa texto hostil no debería
poder hacer una request de salida.

### 3. Apagar los MCP

```
--strict-mcp-config        # y deliberadamente sin --mcp-config
```

Sin esto, los servidores MCP configurados en la cuenta para uso interactivo se cuelan en la
corrida desatendida. La cuenta tenía varios. Ninguno tiene por qué estar disponible a las
4 de la mañana.

## Lo que aprendí

**El radio de daño se diseña antes que el prompt.** No hay instrucción en un prompt que
compense tener la master key al alcance. La pregunta correcta no es "¿qué le pido al
agente?" sino "¿qué puede hacer si lo convencen de hacer otra cosa?".

**El texto de terceros es entrada hostil, siempre.** Una glosa bancaria, el asunto de un
correo, el nombre de un archivo subido. Si llega al prompt y alguien más lo escribió, es
superficie de ataque.

**Las herramientas son la superficie, así que las herramientas son lo que se testea.** El
sistema real tiene 103 tests sobre las seis herramientas que el agente puede invocar. El
prompt no se testea: se acota.

**Probalo con una corrida real.** Los tres flags de arriba se verificaron contra
`claude --help` y con una corrida de verdad antes de confiar en ellos. Un flag que no
existe falla en silencio o, peor, se ignora.

## Qué hay acá

| | |
|---|---|
| `permisos-agente.json` | El modelo de permisos, con las rutas generalizadas. |
| `runner/correr-agente.sh` | Runner mínimo que arma las tres capas e invoca `claude -p`. |
| `launchd/cl.agente.ejemplo.plist` | Plantilla de agente programado, con `RunAtLoad` en `false`. |

MIT.
