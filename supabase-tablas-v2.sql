-- ============================================================
-- sistema_clinica_v2 — tablas operativas de la clínica
-- (pacientes, citas, médicos, facturación, etc.)
-- ============================================================
-- No hay service_role key disponible en este entorno, así que esta lista
-- de tablas y columnas NO sale de una consulta real a information_schema
-- (que pedías correr) — sale de reconstruir el uso real en el código de
-- las 4 apps v1 (PortalAdmin-Simple, PortalPacientes, EmergenciaMovil,
-- SyscobfactMASTER: cada `.from('tabla').insert({...})`/`.update({...})`
-- que aparece ahí), cruzado con:
--   - Proyecto-Clinica/SyscobfactCLINIC/supabase-shema.sql (pacientes,
--     citas, chat_memory — con columnas completas)
--   - Proyecto-Clinica/PortalAdmin-Simple/supabase_audit_log.sql
--     (audit_log completo)
-- El archivo supabase-shema.sql resultó estar desactualizado en varios
-- puntos respecto a lo que el código realmente usa — quedó documentado
-- en cada tabla donde encontré una diferencia concreta.
--
-- TABLAS QUE **NO** SE RECREAN ACÁ (ya existen en v2 o fueron reemplazadas
-- a propósito por el diseño multi-tenant nuevo — ver supabase-schema-v2.sql):
--   - clinicas, usuarios_clinica, planes_clinica → ya existen.
--   - suscripciones (v1) → en v2 sus columnas (plan/estado/fecha_vencimiento)
--     ya viven directo en `clinicas`. Crear una `suscripciones` aparte acá
--     sería duplicar/desincronizar esa info. Si más adelante hace falta
--     guardar mensualidad/histórico de suscripción por separado, avisame.
--   - usuarios (v1, Supabase Auth) → reemplazada por `usuarios_clinica`
--     (password propio hasheado, sin Supabase Auth).
--
-- CAMBIO IMPORTANTE respecto a v1 — UNIQUE por clínica, no global:
-- v1 tenía `pacientes.cedula UNIQUE` y `pacientes.email UNIQUE` GLOBALES
-- en toda la tabla. Eso "funcionaba" en v1 porque sistema_clinica es de
-- una sola clínica — en v2 (multi-tenant real) una cédula/email global
-- única rompería apenas dos clínicas distintas tuvieran un paciente en
-- común (ej. la misma persona atendida en dos clínicas). Acá quedan como
-- UNIQUE(clinica_id, cedula) / UNIQUE(clinica_id, email) — únicos dentro
-- de cada clínica, no en todo el sistema.
--
-- medico_id (en citas/historial_clinico/facturas/incapacidades/examenes/
-- recetas) queda como UUID simple, SIN foreign key — igual que en v1.
-- No es descuido: en el código real a veces apunta a medicos.id y a veces
-- a usuarios_clinica.id (currentUser.id, cuando el que atiende es un
-- usuario con rol médico logueado directo, no un registro en `medicos`).
-- Ponerle FK a una sola tabla habría roto ese caso real.
--
-- Todas las tablas: RLS habilitado + policy "acceso_publico" (USING true
-- WITH CHECK true) — mismo criterio de permisividad que planes_clinica/
-- clinicas/usuarios_clinica en supabase-schema-v2.sql (el control de
-- acceso real vive en la lógica de cada app, no en RLS). GRANT USAGE del
-- schema ya está dado (supabase-schema-v2.sql) — no hace falta repetirlo.

-- ── PACIENTES ──────────────────────────────────────────────
CREATE TABLE sistema_clinica_v2.pacientes (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clinica_id           UUID NOT NULL REFERENCES sistema_clinica_v2.clinicas(id),
    nombre_completo      TEXT NOT NULL,
    cedula               TEXT,
    telefono             TEXT,
    email                TEXT,
    fecha_nacimiento     DATE,
    genero               TEXT CHECK (genero IN ('masculino', 'femenino', 'otro')),
    tipo_sangre          TEXT,
    alergias             TEXT,
    seguro_medico        TEXT,
    contacto_emergencia  TEXT,
    tel_emergencia       TEXT,
    estado               TEXT NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo', 'inactivo')),
    password             TEXT,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (clinica_id, cedula),
    UNIQUE (clinica_id, email)
);

-- ── CITAS ──────────────────────────────────────────────────
-- estado: schema v1 documentaba 'completada', pero el código real de
-- PortalAdmin-Simple usa 'atendida' (nunca 'completada') — se incluyen
-- ambos valores por compatibilidad, sin sacar ninguno.
CREATE TABLE sistema_clinica_v2.citas (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clinica_id     UUID NOT NULL REFERENCES sistema_clinica_v2.clinicas(id),
    paciente_id    UUID NOT NULL REFERENCES sistema_clinica_v2.pacientes(id) ON DELETE CASCADE,
    medico_id      UUID,
    fecha          DATE NOT NULL,
    hora           TIME NOT NULL,
    motivo         TEXT,
    estado         TEXT NOT NULL DEFAULT 'pendiente'
                       CHECK (estado IN ('pendiente', 'confirmada', 'cancelada', 'atendida', 'completada')),
    canal          TEXT,
    fecha_atencion TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── MÉDICOS ────────────────────────────────────────────────
CREATE TABLE sistema_clinica_v2.medicos (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clinica_id       UUID NOT NULL REFERENCES sistema_clinica_v2.clinicas(id),
    nombre_completo  TEXT NOT NULL,
    especialidad     TEXT,
    email            TEXT,
    estado           TEXT NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo', 'inactivo')),
    fecha_ingreso    DATE,
    fecha_retiro     DATE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── COLABORADORES (personal administrativo/no médico) ─────
CREATE TABLE sistema_clinica_v2.colaboradores (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clinica_id       UUID NOT NULL REFERENCES sistema_clinica_v2.clinicas(id),
    nombre_completo  TEXT NOT NULL,
    rol              TEXT,
    cedula           TEXT,
    telefono         TEXT,
    email            TEXT,
    salario          NUMERIC,
    estado           TEXT NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo', 'inactivo')),
    fecha_ingreso    DATE,
    fecha_retiro     DATE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── HISTORIAL CLÍNICO ──────────────────────────────────────
CREATE TABLE sistema_clinica_v2.historial_clinico (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clinica_id            UUID NOT NULL REFERENCES sistema_clinica_v2.clinicas(id),
    paciente_id           UUID NOT NULL REFERENCES sistema_clinica_v2.pacientes(id) ON DELETE CASCADE,
    medico_id             UUID,
    medico_nombre_manual  TEXT,
    fecha                 DATE NOT NULL,
    peso                  TEXT,
    estatura              TEXT,
    presion               TEXT,
    temperatura            TEXT,
    sintomas              TEXT,
    diagnostico           TEXT,
    tratamiento           TEXT,
    observaciones         TEXT,
    origen                TEXT DEFAULT 'consulta',
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── EXÁMENES ───────────────────────────────────────────────
CREATE TABLE sistema_clinica_v2.examenes (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clinica_id        UUID NOT NULL REFERENCES sistema_clinica_v2.clinicas(id),
    paciente_id       UUID NOT NULL REFERENCES sistema_clinica_v2.pacientes(id) ON DELETE CASCADE,
    medico_id         UUID,
    tipo              TEXT NOT NULL,
    fecha             DATE NOT NULL,
    resultado         TEXT DEFAULT 'Pendiente',
    resultado_texto   TEXT,
    interpretacion    TEXT,
    imagen_url        TEXT,
    fecha_resultado   DATE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── RECETAS ────────────────────────────────────────────────
CREATE TABLE sistema_clinica_v2.recetas (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clinica_id    UUID NOT NULL REFERENCES sistema_clinica_v2.clinicas(id),
    paciente_id   UUID NOT NULL REFERENCES sistema_clinica_v2.pacientes(id) ON DELETE CASCADE,
    medico_id     UUID,
    medicamento   TEXT NOT NULL,
    dosis         TEXT,
    frecuencia    TEXT,
    fecha         DATE NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── INCAPACIDADES (certificados de reposo médico) ─────────
CREATE TABLE sistema_clinica_v2.incapacidades (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clinica_id     UUID NOT NULL REFERENCES sistema_clinica_v2.clinicas(id),
    paciente_id    UUID NOT NULL REFERENCES sistema_clinica_v2.pacientes(id) ON DELETE CASCADE,
    medico_id      UUID,
    medico_nombre  TEXT,
    numero         TEXT,
    fecha_emision  DATE NOT NULL,
    fecha_inicio   DATE NOT NULL,
    fecha_fin      DATE NOT NULL,
    dias_reposo    INTEGER,
    diagnostico    TEXT,
    tipo           TEXT,
    observaciones  TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── FACTURAS ───────────────────────────────────────────────
CREATE TABLE sistema_clinica_v2.facturas (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clinica_id        UUID NOT NULL REFERENCES sistema_clinica_v2.clinicas(id),
    clinica_nombre    TEXT,
    paciente_id       UUID REFERENCES sistema_clinica_v2.pacientes(id),
    paciente_nombre   TEXT,
    medico_id         UUID,
    medico_nombre     TEXT,
    numero            TEXT,
    concepto          TEXT,
    monto             NUMERIC NOT NULL DEFAULT 0,
    fecha             DATE NOT NULL,
    forma_pago        TEXT,
    referencia        TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── ÍTEMS DE FACTURA ───────────────────────────────────────
CREATE TABLE sistema_clinica_v2.factura_items (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    factura_id  UUID NOT NULL REFERENCES sistema_clinica_v2.facturas(id) ON DELETE CASCADE,
    clinica_id  UUID NOT NULL REFERENCES sistema_clinica_v2.clinicas(id),
    concepto    TEXT NOT NULL,
    cantidad    NUMERIC NOT NULL DEFAULT 1,
    precio      NUMERIC NOT NULL DEFAULT 0,
    subtotal    NUMERIC NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── PAGOS GENERALES (nómina y gastos operativos) ──────────
CREATE TABLE sistema_clinica_v2.pagos (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clinica_id           UUID NOT NULL REFERENCES sistema_clinica_v2.clinicas(id),
    numero               TEXT,
    tipo                 TEXT NOT NULL,
    periodo              TEXT,
    fecha_inicio         DATE,
    fecha_fin            DATE,
    concepto             TEXT,
    bruto                NUMERIC DEFAULT 0,
    descuentos           NUMERIC DEFAULT 0,
    bonos                NUMERIC DEFAULT 0,
    neto                 NUMERIC NOT NULL DEFAULT 0,
    metodo               TEXT,
    referencia           TEXT,
    observaciones        TEXT,
    fecha                DATE NOT NULL,
    colaborador_id       UUID REFERENCES sistema_clinica_v2.colaboradores(id),
    colaborador_nombre   TEXT,
    rol                  TEXT,
    categoria            TEXT,
    categoria_label      TEXT,
    proveedor            TEXT,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── PAGOS DE SUSCRIPCIÓN (la clínica pagándole a Syscobfact) ─
CREATE TABLE sistema_clinica_v2.pagos_suscripcion (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clinica_id    UUID NOT NULL REFERENCES sistema_clinica_v2.clinicas(id),
    monto         NUMERIC NOT NULL,
    metodo_pago   TEXT,
    fecha_pago    DATE NOT NULL DEFAULT CURRENT_DATE,
    notas         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── NOTIFICACIONES ─────────────────────────────────────────
CREATE TABLE sistema_clinica_v2.notificaciones (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clinica_id  UUID NOT NULL REFERENCES sistema_clinica_v2.clinicas(id),
    titulo      TEXT NOT NULL,
    mensaje     TEXT,
    tipo        TEXT,
    leida       BOOLEAN NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── AUDITORÍA ──────────────────────────────────────────────
CREATE TABLE sistema_clinica_v2.audit_log (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clinica_id       UUID NOT NULL REFERENCES sistema_clinica_v2.clinicas(id),
    tabla            TEXT NOT NULL,
    operacion        TEXT NOT NULL CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE')),
    registro_id      UUID,
    descripcion      TEXT,
    usuario_nombre   TEXT,
    usuario_rol      TEXT,
    datos_nuevos     JSONB,
    created_at       TIMESTAMPTZ DEFAULT now()
);

-- ── CHAT MEMORY (bot de WhatsApp "Clara", n8n) ────────────
-- clinica_id nullable a propósito: el workflow de n8n resuelve la clínica
-- a partir del número de WhatsApp DESPUÉS de guardar el mensaje en algunos
-- pasos — forzar NOT NULL acá rompería ese flujo. Sigue siendo la única
-- tabla de las 14 sin clinica_id obligatorio; el resto si lo exige.
CREATE TABLE sistema_clinica_v2.chat_memory (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clinica_id  UUID REFERENCES sistema_clinica_v2.clinicas(id),
    session_id  TEXT NOT NULL,
    message     TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── ÍNDICES ────────────────────────────────────────────────
CREATE INDEX ON sistema_clinica_v2.pacientes (clinica_id);
CREATE INDEX ON sistema_clinica_v2.citas (clinica_id);
CREATE INDEX ON sistema_clinica_v2.citas (paciente_id);
CREATE INDEX ON sistema_clinica_v2.citas (medico_id);
CREATE INDEX ON sistema_clinica_v2.citas (fecha);
CREATE INDEX ON sistema_clinica_v2.medicos (clinica_id);
CREATE INDEX ON sistema_clinica_v2.colaboradores (clinica_id);
CREATE INDEX ON sistema_clinica_v2.historial_clinico (clinica_id);
CREATE INDEX ON sistema_clinica_v2.historial_clinico (paciente_id);
CREATE INDEX ON sistema_clinica_v2.examenes (clinica_id);
CREATE INDEX ON sistema_clinica_v2.examenes (paciente_id);
CREATE INDEX ON sistema_clinica_v2.recetas (clinica_id);
CREATE INDEX ON sistema_clinica_v2.recetas (paciente_id);
CREATE INDEX ON sistema_clinica_v2.incapacidades (clinica_id);
CREATE INDEX ON sistema_clinica_v2.incapacidades (paciente_id);
CREATE INDEX ON sistema_clinica_v2.facturas (clinica_id);
CREATE INDEX ON sistema_clinica_v2.factura_items (factura_id);
CREATE INDEX ON sistema_clinica_v2.factura_items (clinica_id);
CREATE INDEX ON sistema_clinica_v2.pagos (clinica_id);
CREATE INDEX ON sistema_clinica_v2.pagos_suscripcion (clinica_id);
CREATE INDEX ON sistema_clinica_v2.notificaciones (clinica_id);
CREATE INDEX ON sistema_clinica_v2.audit_log (clinica_id, created_at DESC);
CREATE INDEX ON sistema_clinica_v2.audit_log (tabla, operacion);
CREATE INDEX ON sistema_clinica_v2.chat_memory (session_id);

-- ── TRIGGER updated_at (solo las tablas que lo usan en v1) ─
CREATE OR REPLACE FUNCTION sistema_clinica_v2.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_pacientes_updated_at
    BEFORE UPDATE ON sistema_clinica_v2.pacientes
    FOR EACH ROW EXECUTE FUNCTION sistema_clinica_v2.set_updated_at();

CREATE TRIGGER trg_citas_updated_at
    BEFORE UPDATE ON sistema_clinica_v2.citas
    FOR EACH ROW EXECUTE FUNCTION sistema_clinica_v2.set_updated_at();

CREATE TRIGGER trg_colaboradores_updated_at
    BEFORE UPDATE ON sistema_clinica_v2.colaboradores
    FOR EACH ROW EXECUTE FUNCTION sistema_clinica_v2.set_updated_at();

-- ── RLS + GRANT (mismo criterio que planes_clinica/clinicas/usuarios_clinica) ─
ALTER TABLE sistema_clinica_v2.pacientes           ENABLE ROW LEVEL SECURITY;
ALTER TABLE sistema_clinica_v2.citas               ENABLE ROW LEVEL SECURITY;
ALTER TABLE sistema_clinica_v2.medicos             ENABLE ROW LEVEL SECURITY;
ALTER TABLE sistema_clinica_v2.colaboradores       ENABLE ROW LEVEL SECURITY;
ALTER TABLE sistema_clinica_v2.historial_clinico   ENABLE ROW LEVEL SECURITY;
ALTER TABLE sistema_clinica_v2.examenes            ENABLE ROW LEVEL SECURITY;
ALTER TABLE sistema_clinica_v2.recetas             ENABLE ROW LEVEL SECURITY;
ALTER TABLE sistema_clinica_v2.incapacidades       ENABLE ROW LEVEL SECURITY;
ALTER TABLE sistema_clinica_v2.facturas            ENABLE ROW LEVEL SECURITY;
ALTER TABLE sistema_clinica_v2.factura_items       ENABLE ROW LEVEL SECURITY;
ALTER TABLE sistema_clinica_v2.pagos               ENABLE ROW LEVEL SECURITY;
ALTER TABLE sistema_clinica_v2.pagos_suscripcion   ENABLE ROW LEVEL SECURITY;
ALTER TABLE sistema_clinica_v2.notificaciones      ENABLE ROW LEVEL SECURITY;
ALTER TABLE sistema_clinica_v2.audit_log           ENABLE ROW LEVEL SECURITY;
ALTER TABLE sistema_clinica_v2.chat_memory         ENABLE ROW LEVEL SECURITY;

CREATE POLICY "acceso_publico" ON sistema_clinica_v2.pacientes         FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "acceso_publico" ON sistema_clinica_v2.citas             FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "acceso_publico" ON sistema_clinica_v2.medicos           FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "acceso_publico" ON sistema_clinica_v2.colaboradores     FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "acceso_publico" ON sistema_clinica_v2.historial_clinico FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "acceso_publico" ON sistema_clinica_v2.examenes          FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "acceso_publico" ON sistema_clinica_v2.recetas           FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "acceso_publico" ON sistema_clinica_v2.incapacidades     FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "acceso_publico" ON sistema_clinica_v2.facturas          FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "acceso_publico" ON sistema_clinica_v2.factura_items     FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "acceso_publico" ON sistema_clinica_v2.pagos             FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "acceso_publico" ON sistema_clinica_v2.pagos_suscripcion FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "acceso_publico" ON sistema_clinica_v2.notificaciones    FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "acceso_publico" ON sistema_clinica_v2.audit_log         FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "acceso_publico" ON sistema_clinica_v2.chat_memory       FOR ALL USING (true) WITH CHECK (true);

-- Re-otorga sobre TODAS las tablas del schema (las 3 viejas + las 14
-- nuevas de este archivo) — GRANT ALL ON ALL TABLES solo alcanza a las
-- tablas que existen en el momento en que se corre, por eso hay que
-- repetirlo acá en vez de asumir que el GRANT de supabase-schema-v2.sql
-- ya las cubre.
GRANT ALL ON ALL TABLES IN SCHEMA sistema_clinica_v2 TO anon, authenticated;
