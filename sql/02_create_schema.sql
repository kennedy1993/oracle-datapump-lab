-- =============================================================
-- 02_create_schema.sql  (executar como LAB_RH no PDB FREEPDB1)
-- Cria um schema de RH com tabelas, constraints nomeadas,
-- indices, sequence, view e procedure, e popula dados
-- deterministicos (mesmos valores a cada execucao).
-- =============================================================
SET ECHO OFF FEEDBACK ON SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

PROMPT >> Limpando objetos de execucoes anteriores
DROP VIEW IF EXISTS vw_folha_por_departamento;
DROP PROCEDURE IF EXISTS reajustar_salario;
DROP TABLE IF EXISTS funcionarios PURGE;
DROP TABLE IF EXISTS departamentos PURGE;
DROP SEQUENCE IF EXISTS seq_funcionarios;

PROMPT >> Criando tabelas
CREATE TABLE departamentos (
  id      NUMBER(4)     CONSTRAINT pk_departamentos PRIMARY KEY,
  nome    VARCHAR2(50)  CONSTRAINT nn_departamentos_nome NOT NULL,
  sigla   VARCHAR2(5)   CONSTRAINT nn_departamentos_sigla NOT NULL,
  CONSTRAINT uk_departamentos_sigla UNIQUE (sigla)
);

CREATE TABLE funcionarios (
  id              NUMBER(6)     CONSTRAINT pk_funcionarios PRIMARY KEY,
  nome            VARCHAR2(80)  CONSTRAINT nn_funcionarios_nome NOT NULL,
  email           VARCHAR2(120) CONSTRAINT nn_funcionarios_email NOT NULL,
  salario         NUMBER(10,2)  CONSTRAINT nn_funcionarios_salario NOT NULL,
  data_admissao   DATE          CONSTRAINT nn_funcionarios_admissao NOT NULL,
  dept_id         NUMBER(4)     CONSTRAINT nn_funcionarios_dept NOT NULL,
  CONSTRAINT uk_funcionarios_email UNIQUE (email),
  CONSTRAINT ck_funcionarios_salario CHECK (salario > 0),
  CONSTRAINT fk_funcionarios_departamento FOREIGN KEY (dept_id)
    REFERENCES departamentos (id)
);

CREATE INDEX ix_funcionarios_dept ON funcionarios (dept_id);
CREATE INDEX ix_funcionarios_admissao ON funcionarios (data_admissao);

CREATE SEQUENCE seq_funcionarios START WITH 1001 INCREMENT BY 1 NOCACHE;

PROMPT >> Populando dados
INSERT INTO departamentos (id, nome, sigla) VALUES (1, 'Tecnologia', 'TI');
INSERT INTO departamentos (id, nome, sigla) VALUES (2, 'Financeiro', 'FIN');
INSERT INTO departamentos (id, nome, sigla) VALUES (3, 'Recursos Humanos', 'RH');
INSERT INTO departamentos (id, nome, sigla) VALUES (4, 'Operacoes', 'OPS');
INSERT INTO departamentos (id, nome, sigla) VALUES (5, 'Comercial', 'COM');

INSERT INTO funcionarios (id, nome, email, salario, data_admissao, dept_id)
SELECT LEVEL,
       'Funcionario ' || LPAD(LEVEL, 4, '0'),
       'funcionario' || LPAD(LEVEL, 4, '0') || '@lab.local',
       3000 + MOD(LEVEL * 37, 9000),
       DATE '2020-01-01' + MOD(LEVEL * 13, 1800),
       MOD(LEVEL, 5) + 1
FROM dual
CONNECT BY LEVEL <= 1000;

COMMIT;

PROMPT >> Criando view e procedure
CREATE OR REPLACE VIEW vw_folha_por_departamento AS
SELECT d.sigla,
       d.nome,
       COUNT(f.id)    AS qtd_funcionarios,
       SUM(f.salario) AS folha_total
FROM departamentos d
LEFT JOIN funcionarios f ON f.dept_id = d.id
GROUP BY d.sigla, d.nome;

CREATE OR REPLACE PROCEDURE reajustar_salario (
  p_dept_id    IN departamentos.id%TYPE,
  p_percentual IN NUMBER
) AS
BEGIN
  IF p_percentual <= 0 OR p_percentual > 50 THEN
    RAISE_APPLICATION_ERROR(-20001, 'Percentual invalido: use valores entre 0 e 50.');
  END IF;

  UPDATE funcionarios
     SET salario = ROUND(salario * (1 + p_percentual / 100), 2)
   WHERE dept_id = p_dept_id;

  DBMS_OUTPUT.PUT_LINE(SQL%ROWCOUNT || ' salario(s) reajustado(s).');
END reajustar_salario;
/

PROMPT >> Coletando estatisticas
EXEC DBMS_STATS.GATHER_SCHEMA_STATS(USER);

PROMPT >> Resumo
SELECT * FROM vw_folha_por_departamento ORDER BY sigla;

EXIT
