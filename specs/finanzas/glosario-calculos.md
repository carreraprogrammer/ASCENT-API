# Glosario de cálculos — fuente de verdad del lenguaje

> 📋 Auditoría completa de fórmulas (ubicación exacta, respaldo bibliográfico y
> banderas de inconsistencia 🟢🟡🟠🔴): ver **`reporte-calculos.md`**.
> Estado: ✅ documento vivo — actualizar cuando cambie una fórmula
> Creado: 2026-06-12
> Regla ASCENT: la UI y el agente SIEMPRE usan el nombre plano. El término técnico
> es interno (código y prompts de sistema); nunca se le muestra al usuario.
> Cada número visible debe poder responder "¿de dónde sale?" con la explicación plana
> y los números del propio usuario.

| Nombre plano (lo que ve el usuario) | Término interno | Dónde se calcula |
|---|---|---|
| Margen libre / Cuánto puedes mover | `commitment_gap` | `CashFlowRunway` |
| Tu ritmo | `daily_necessary_burn` | `CashFlowRunway#compute_daily_burn` |
| Lo que tienes hoy | `confirmed_balance` | `SummaryController` |
| Días de colchón | `buffer_days` | `CashFlowRunway` |
| Tu estado (tranquilo/justo/en rojo) | `health_status` | `CashFlowRunway#classify_status` |
| Disponible real | `net_balance` | `TransactionRepository#balance` |
| Saldo arrastrado | `carryover_from_previous_month` | `SummaryController` |
| Meses de colchón (fondo) | `emergency_fund.months_covered` | `HealthMetrics` |
| Proyección a fin de mes | burn rate proyectado | `BurnRateCalculator` |
| Carga fija sobre tu ingreso | `ratio_gastos_fijos` | `HealthMetrics` |
| Carga de deudas sobre tu ingreso | `dti` | `HealthMetrics` |
| Lo que ahorras de tu ingreso | `tasa_ahorro` | `HealthMetrics` |
| Edad de tu plata | `age_of_money` | `HealthMetrics` |
| Ingreso extra del mes | `realized_overflow` | `SummaryController` |
| Prioridad del excedente | `coaching_priority` | `HealthMetrics` |

---

## Fórmulas y explicación plana

### Margen libre (`commitment_gap`)
```
margen_libre = lo_que_tienes_hoy
             − pagos_que_vencen_antes_del_próximo_ingreso (lo no pagado aún)
             − (tu_ritmo × días_hasta_el_próximo_ingreso)
```
**Explicación plana:** "Tomamos lo que tienes hoy, le restamos los pagos fijos que
vencen antes de tu próximo ingreso y lo que vas a necesitar para el día a día hasta
esa fecha. Lo que queda es tuyo para mover sin poner nada en riesgo."

### Tu ritmo (`daily_necessary_burn`)
```
ritmo = suma de gastos confirmados de categoría "necessary"
        de los últimos 30 días ÷ 30
```
- **NO incluye** pagos comprometidos (arriendo, cuotas, suscripciones) — esos se
  cuentan aparte como compromisos. Tampoco gasto flexible, inversión ni social.
- Requiere ≥ 14 días de historial; si no hay, usa $30.000/día como estimado
  (`has_sufficient_history: false` → la UI debe decir "estimado").

**Explicación plana:** "Es el promedio diario de tus gastos del día a día (mercado,
transporte, comida) en los últimos 30 días. Tus pagos fijos no entran aquí — esos
los contamos aparte."

### Lo que tienes hoy (`confirmed_balance`)
```
lo_que_tienes_hoy = ingresos confirmados − gastos confirmados + saldo arrastrado del mes anterior
```

### Días de colchón (`buffer_days`)
```
colchón = ((lo_que_tienes_hoy − pagos_antes_del_próximo_ingreso) ÷ tu_ritmo)
        − días_hasta_el_próximo_ingreso
```
**Plana:** "Cuántos días de respiro te quedan después de llegar a tu próximo ingreso."

### Tu estado (`health_status`)
- **En rojo (critical):** lo que tienes hoy ≤ 0, o el margen libre es negativo.
- **Justo (warning):** el colchón es menor a 2 días.
- **Tranquilo (comfortable):** el resto.

### Próximo ingreso
El día más cercano en el futuro entre las fechas esperadas de tus fuentes de ingreso
activas (incluye quincenas con schedules). El ingreso de HOY ya está dentro de
"lo que tienes hoy", por eso no cuenta. Sin fuentes → fin de mes.

### Disponible real (`net_balance`)
```
disponible_real = balance_del_mes + saldo_arrastrado
```
donde `balance_del_mes = ingresos confirmados − gastos confirmados del mes`.

### Meses de colchón del fondo de emergencia (`months_covered`)
```
meses = saldo_del_fondo ÷ suma de TODAS las obligaciones mensuales activas
        (incluye mínimos de deuda — en Colombia no pagarlos reporta a DataCrédito)
```
Metas: 1 mes (starter) · 3 meses (suficiente) · 6 meses (óptimo).

### Proyección a fin de mes (burn rate proyectado, por gaveta)
```
proyección = (gastado_en_la_gaveta ÷ días_transcurridos) × días_del_mes
```
**Plana:** "Si sigues a este paso, así terminas el mes."

### Carga fija sobre tu ingreso (`ratio_gastos_fijos`)
```
carga_fija = obligaciones recurrentes mensuales ÷ ingreso base del plan × 100
```
≤50% excelente · 51-65% saludable · 66-75% alerta · >75% crítico (problema
estructural, no de disciplina).

### Carga de deudas (`dti`)
```
dti = pagos mínimos mensuales de deudas activas ÷ ingreso base × 100
```
≤20% segura · 21-35% advertencia · >35% estrés.

### Lo que ahorras (`tasa_ahorro`)
```
tasa = aportes mensuales a metas activas ÷ ingreso base × 100
```

### Edad de tu plata (`age_of_money`)
Promedio de días entre que la plata entró y se gastó (últimos 10 egresos, FIFO
aproximado). ≥30 días = ya no vives quincena a quincena.

### Prioridad del excedente (`coaching_priority`)
Secuencia fija (NC-3): fondo starter de 1 mes → atacar deuda → fondo de 3 meses →
invertir. La calcula la API; los agentes la obedecen sin re-derivarla.

---

## Notas de drift
- `safe_to_deploy` ya no existe como interactor (`LiquidityProjection` referenciado
  en CLAUDE.md no está en el código). El guardarraíl real es `commitment_gap`.
