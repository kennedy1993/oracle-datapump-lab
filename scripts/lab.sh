#!/usr/bin/env bash
# =============================================================
# Laboratorio Oracle Data Pump (expdp/impdp) - Linux, macOS, WSL ou Git Bash
# Uso: ./scripts/lab.sh <comando>
#   up        sobe o container e espera o banco ficar pronto
#   setup     cria usuarios, DIRECTORY e o schema LAB_RH com dados
#   baseline  gera a impressao digital ANTES do desastre
#   export    executa o expdp do schema LAB_RH
#   disaster  remove as tabelas com DROP TABLE ... PURGE
#   import    restaura as tabelas com impdp
#   verify    gera a impressao digital DEPOIS e compara com a de antes
#   remap     bonus: importa o dump em outro schema (REMAP_SCHEMA)
#   all       executa tudo em sequencia (up ate remap)
#   down      remove o container e o volume
# =============================================================
set -euo pipefail

C="oracle-lab-datapump"
SYS_CONN="system/Oracle2026@localhost:1521/FREEPDB1"
APP_CONN="lab_rh/LabRh2026@localhost:1521/FREEPDB1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVID="$ROOT_DIR/evidencias"

cd "$ROOT_DIR"
mkdir -p "$EVID"

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mERRO: %s\033[0m\n' "$*" >&2; exit 1; }

sqlplus_run() {  # sqlplus_run <conexao> <script.sql> [args...]
  local conn="$1" script="$2"; shift 2
  docker exec "$C" sqlplus -s -L "$conn" "@/tmp/lab/sql/$script" "$@"
}

datapump_run() {  # datapump_run <expdp|impdp> <conexao> <parfile>
  local tool="$1" conn="$2" par="$3" rc=0
  docker exec "$C" "$tool" "$conn" "parfile=/tmp/lab/parfiles/$par" || rc=$?
  # 0 = sucesso | 5 = concluido com avisos
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 5 ]; then
    fail "$tool terminou com codigo $rc. Veja o log em evidencias/."
  fi
  [ "$rc" -eq 5 ] && echo "AVISO: $tool concluiu com avisos (codigo 5). Revise o log."
  return 0
}

copy_log() {  # copy_log <arquivo-no-container> <destino>
  docker cp "$C:/opt/oracle/dumps/$1" "$EVID/$2" >/dev/null && echo "Log salvo em evidencias/$2"
}

cmd_up() {
  log "Subindo o container Oracle 23ai Free (o primeiro download pode demorar)"
  docker compose up -d
  log "Aguardando o banco ficar pronto"
  local i status
  for i in $(seq 1 80); do
    status="$(docker inspect -f '{{.State.Health.Status}}' "$C" 2>/dev/null || echo starting)"
    [ "$status" = "healthy" ] && { echo "Banco pronto."; break; }
    printf '.'; sleep 15
  done
  [ "$status" = "healthy" ] || fail "o banco nao ficou pronto a tempo. Veja: docker logs $C"

  log "Copiando scripts para o container e criando a pasta de dumps"
  docker exec -u 0 "$C" bash -c "rm -rf /tmp/lab && mkdir -p /tmp/lab /opt/oracle/dumps && chown oracle: /opt/oracle/dumps"
  docker cp "$ROOT_DIR/sql" "$C:/tmp/lab/"
  docker cp "$ROOT_DIR/parfiles" "$C:/tmp/lab/"
  docker exec -u 0 "$C" chmod -R a+rX /tmp/lab
}

cmd_setup() {
  log "Criando usuarios e DIRECTORY (SYSTEM)"
  sqlplus_run "$SYS_CONN" 01_setup.sql | tee "$EVID/00_setup.txt"
  log "Criando o schema LAB_RH com dados"
  sqlplus_run "$APP_CONN" 02_create_schema.sql | tee -a "$EVID/00_setup.txt"
}

cmd_baseline() {
  log "Impressao digital ANTES do desastre"
  sqlplus_run "$SYS_CONN" 03_validate.sql LAB_RH | tee "$EVID/01_fingerprint_antes.txt"
}

cmd_export() {
  log "Backup logico com expdp"
  datapump_run expdp "$APP_CONN" export_lab_rh.par
  copy_log exp_lab_rh.log 02_expdp.log
  docker exec "$C" ls -lh /opt/oracle/dumps | tee "$EVID/02_arquivos_dump.txt"
}

cmd_disaster() {
  log "Simulando o desastre (DROP TABLE ... PURGE)"
  sqlplus_run "$APP_CONN" 04_disaster.sql | tee "$EVID/03_desastre.txt"
}

cmd_import() {
  log "Restaurando as tabelas com impdp"
  datapump_run impdp "$APP_CONN" import_tables.par
  copy_log imp_lab_rh.log 04_impdp.log
}

cmd_verify() {
  log "Impressao digital DEPOIS da restauracao"
  sqlplus_run "$SYS_CONN" 03_validate.sql LAB_RH | tee "$EVID/05_fingerprint_depois.txt"
  log "Comparando ANTES x DEPOIS"
  if diff "$EVID/01_fingerprint_antes.txt" "$EVID/05_fingerprint_depois.txt" > "$EVID/06_diff.txt"; then
    echo "RESULTADO: restauracao identica ao estado original." | tee -a "$EVID/06_diff.txt"
  else
    cat "$EVID/06_diff.txt"; fail "existem diferencas entre antes e depois (veja evidencias/06_diff.txt)."
  fi
}

cmd_remap() {
  log "Bonus: importando o dump no schema LAB_RH_RESTORE (REMAP_SCHEMA)"
  datapump_run impdp "$SYS_CONN" import_remap.par
  copy_log imp_remap_lab_rh_restore.log 07_impdp_remap.log
  sqlplus_run "$SYS_CONN" 03_validate.sql LAB_RH_RESTORE | tee "$EVID/08_fingerprint_restore.txt"
  if diff "$EVID/01_fingerprint_antes.txt" "$EVID/08_fingerprint_restore.txt" > "$EVID/09_diff_remap.txt"; then
    echo "RESULTADO: LAB_RH_RESTORE identico ao LAB_RH original." | tee -a "$EVID/09_diff_remap.txt"
  else
    cat "$EVID/09_diff_remap.txt"; fail "existem diferencas no schema remapeado."
  fi
}

cmd_down() {
  log "Removendo container e volume"
  docker compose down -v
}

case "${1:-}" in
  up) cmd_up ;;
  setup) cmd_setup ;;
  baseline) cmd_baseline ;;
  export) cmd_export ;;
  disaster) cmd_disaster ;;
  import) cmd_import ;;
  verify) cmd_verify ;;
  remap) cmd_remap ;;
  all) cmd_up; cmd_setup; cmd_baseline; cmd_export; cmd_disaster; cmd_import; cmd_verify; cmd_remap
       log "Laboratorio concluido. Evidencias em: evidencias/" ;;
  down) cmd_down ;;
  *) sed -n '3,16p' "$0"; exit 1 ;;
esac
