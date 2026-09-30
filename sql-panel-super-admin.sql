-- Columnas nuevas en sistema_clinica_v2.clinicas, necesarias para:
-- 1) Register/index.html: guardar plan_nombre (etiqueta legible, ej. "Plan
--    Básico") y plan_monto_mensual (monto real a cobrar) por separado del
--    campo `plan` (la clave corta que ya existe y se usa para buscar en
--    planes_clinica.nombre — "Gratis"/"Basico"/"Profesional"/"Clinica").
-- 2) Dashboard/index.html: mostrar el monto real en el banner de
--    vencimiento (bloque de instrucciones de pago).
-- 3) Proyecto-Super-Admin/index.html: el modal "Renovar Plan" actualiza
--    estas 2 columnas junto con fecha_vencimiento.
ALTER TABLE sistema_clinica_v2.clinicas ADD COLUMN IF NOT EXISTS plan_nombre TEXT;
ALTER TABLE sistema_clinica_v2.clinicas ADD COLUMN IF NOT EXISTS plan_monto_mensual NUMERIC;
