-- =============================================================
-- 04_disaster.sql  (executar como LAB_RH no PDB FREEPDB1)
-- Simula um erro humano: as tabelas sao removidas com PURGE,
-- ou seja, NAO vao para a lixeira (recyclebin). Assim o
-- FLASHBACK TABLE ... TO BEFORE DROP nao e uma opcao e a
-- recuperacao depende do backup logico (Data Pump).
-- =============================================================
SET ECHO OFF FEEDBACK ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT >> Simulando o desastre: DROP TABLE ... PURGE
DROP TABLE funcionarios PURGE;
DROP TABLE departamentos PURGE;

PROMPT >> Tabelas restantes no schema (esperado: 0)
SELECT COUNT(*) AS tabelas FROM user_tables;

PROMPT >> Objetos na lixeira (esperado: 0, flashback drop impossivel)
SELECT COUNT(*) AS lixeira FROM user_recyclebin;

PROMPT >> Objetos que dependiam das tabelas (esperado: INVALID)
SELECT object_type, object_name, status FROM user_objects
WHERE object_type IN ('VIEW', 'PROCEDURE') ORDER BY object_name;

EXIT
