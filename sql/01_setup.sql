-- =============================================================
-- 01_setup.sql  (executar como SYSTEM no PDB FREEPDB1)
-- Cria os usuarios do laboratorio e o DIRECTORY do Data Pump.
-- Idempotente: pode ser executado mais de uma vez.
-- =============================================================
SET ECHO OFF FEEDBACK ON SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT >> Removendo usuarios de execucoes anteriores (se existirem)
DROP USER IF EXISTS lab_rh CASCADE;
DROP USER IF EXISTS lab_rh_restore CASCADE;

PROMPT >> Criando usuario de origem LAB_RH
CREATE USER lab_rh IDENTIFIED BY "LabRh2026"
  DEFAULT TABLESPACE users
  QUOTA UNLIMITED ON users;
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE, CREATE PROCEDURE TO lab_rh;

PROMPT >> Criando usuario de destino LAB_RH_RESTORE (usado no REMAP_SCHEMA)
CREATE USER lab_rh_restore IDENTIFIED BY "LabRh2026"
  DEFAULT TABLESPACE users
  QUOTA UNLIMITED ON users;
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE, CREATE PROCEDURE TO lab_rh_restore;

PROMPT >> Criando DIRECTORY do Data Pump apontando para /opt/oracle/dumps
CREATE OR REPLACE DIRECTORY dp_dir AS '/opt/oracle/dumps';
GRANT READ, WRITE ON DIRECTORY dp_dir TO lab_rh;

PROMPT >> Conferencia
SELECT directory_name, directory_path FROM all_directories WHERE directory_name = 'DP_DIR';
SELECT username, default_tablespace FROM dba_users WHERE username LIKE 'LAB_RH%' ORDER BY username;

EXIT
