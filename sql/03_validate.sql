-- =============================================================
-- 03_validate.sql  (executar como SYSTEM no PDB FREEPDB1)
-- Uso: @03_validate.sql <SCHEMA>
-- Gera uma "impressao digital" do schema: objetos, constraints,
-- contagens e hash dos dados. A saida nao contem o nome do
-- schema, entao pode ser comparada entre LAB_RH e LAB_RH_RESTORE.
-- =============================================================
SET ECHO OFF FEEDBACK OFF HEADING OFF VERIFY OFF PAGESIZE 0 LINESIZE 200 TRIMSPOOL ON
WHENEVER SQLERROR EXIT SQL.SQLCODE
DEFINE schema = '&1'

-- Recompila objetos que ficaram invalidos apos o DROP/IMPORT
EXEC DBMS_UTILITY.COMPILE_SCHEMA(schema => UPPER('&schema'), compile_all => FALSE);

PROMPT === OBJETOS ===
SELECT RPAD(object_type, 12) || ' ' || RPAD(object_name, 32) || ' ' || status
FROM   all_objects
WHERE  owner = UPPER('&schema')
AND    object_name NOT LIKE 'SYS\_%' ESCAPE '\'
ORDER  BY object_type, object_name;

PROMPT === CONSTRAINTS ===
SELECT constraint_type || ' ' || RPAD(constraint_name, 32) || ' ' || RPAD(table_name, 15) || ' ' || status
FROM   all_constraints
WHERE  owner = UPPER('&schema')
AND    constraint_name NOT LIKE 'SYS\_%' ESCAPE '\'
AND    constraint_name NOT LIKE 'BIN$%'
ORDER  BY constraint_name;

PROMPT === DADOS ===
SELECT 'DEPARTAMENTOS  linhas=' || COUNT(*) FROM &schema..departamentos;
SELECT 'FUNCIONARIOS   linhas=' || COUNT(*)
       || ' soma_salarios=' || TO_CHAR(SUM(salario), 'FM999999999990.00')
       || ' hash=' || SUM(ORA_HASH(id || '|' || nome || '|' || email || '|' || salario || '|'
                                   || TO_CHAR(data_admissao, 'YYYY-MM-DD') || '|' || dept_id))
FROM   &schema..funcionarios;

EXIT
