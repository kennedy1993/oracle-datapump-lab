# =============================================================
# Laboratorio Oracle Data Pump (expdp/impdp) - Windows PowerShell
# Uso: .\scripts\lab.ps1 <comando>
#   up | setup | baseline | export | disaster | import | verify | remap | all | down
# Se o Windows bloquear o script, execute antes (somente nesta janela):
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
# =============================================================
param([Parameter(Position = 0)][string]$Comando = "")

# "Continue": docker e Data Pump escrevem progresso no stderr; os erros
# reais sao tratados pelos codigos de saida ($LASTEXITCODE).
$ErrorActionPreference = "Continue"
$C        = "oracle-lab-datapump"
$SysConn  = "system/Oracle2026@localhost:1521/FREEPDB1"
$AppConn  = "lab_rh/LabRh2026@localhost:1521/FREEPDB1"
$Root     = Split-Path -Parent $PSScriptRoot
$Evid     = Join-Path $Root "evidencias"

Set-Location $Root
New-Item -ItemType Directory -Force -Path $Evid | Out-Null

function Log($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "`nERRO: $msg" -ForegroundColor Red; exit 1 }

function Save($lines, $file, [switch]$Append) {
    $path = Join-Path $Evid $file
    if ($Append) { $lines | Out-File -FilePath $path -Encoding utf8 -Append }
    else         { $lines | Out-File -FilePath $path -Encoding utf8 }
    $lines | ForEach-Object { Write-Host $_ }
}

function SqlPlus($conn, $script, $arg = $null) {
    $cmdArgs = @("exec", $C, "sqlplus", "-s", "-L", $conn, "@/tmp/lab/sql/$script")
    if ($arg) { $cmdArgs += $arg }
    $out = & docker @cmdArgs
    if ($LASTEXITCODE -ne 0) { $out | ForEach-Object { Write-Host $_ }; Fail "sqlplus falhou em $script (codigo $LASTEXITCODE)." }
    return $out
}

function DataPump($tool, $conn, $par) {
    & docker exec $C $tool $conn "parfile=/tmp/lab/parfiles/$par"
    $rc = $LASTEXITCODE
    # 0 = sucesso | 5 = concluido com avisos
    if ($rc -ne 0 -and $rc -ne 5) { Fail "$tool terminou com codigo $rc. Veja o log em evidencias/." }
    if ($rc -eq 5) { Write-Host "AVISO: $tool concluiu com avisos (codigo 5). Revise o log." -ForegroundColor Yellow }
}

function CopyLog($src, $dst) {
    & docker cp "${C}:/opt/oracle/dumps/$src" (Join-Path $Evid $dst) | Out-Null
    Write-Host "Log salvo em evidencias/$dst"
}

function Compare-Fingerprint($a, $b, $diffFile, $okMsg) {
    $left  = Get-Content (Join-Path $Evid $a)
    $right = Get-Content (Join-Path $Evid $b)
    $diff  = Compare-Object $left $right
    if ($null -eq $diff) {
        Save @($okMsg) $diffFile
    } else {
        Save ($diff | Format-Table -AutoSize | Out-String) $diffFile
        Fail "existem diferencas (veja evidencias/$diffFile)."
    }
}

function Cmd-Up {
    Log "Subindo o container Oracle 23ai Free (o primeiro download pode demorar)"
    docker compose up -d
    if ($LASTEXITCODE -ne 0) { Fail "docker compose falhou. Veja a mensagem acima (Docker aberto? porta 1522 livre?)." }
    Log "Aguardando o banco ficar pronto"
    $status = ""
    for ($i = 1; $i -le 80; $i++) {
        $status = (docker inspect -f "{{.State.Health.Status}}" $C 2>$null)
        if ($status -eq "healthy") { Write-Host "Banco pronto."; break }
        Write-Host -NoNewline "."; Start-Sleep -Seconds 15
    }
    if ($status -ne "healthy") { Fail "o banco nao ficou pronto a tempo. Veja: docker logs $C" }

    Log "Copiando scripts para o container e criando a pasta de dumps"
    docker exec -u 0 $C bash -c "rm -rf /tmp/lab && mkdir -p /tmp/lab /opt/oracle/dumps && chown oracle: /opt/oracle/dumps"
    docker cp (Join-Path $Root "sql") "${C}:/tmp/lab/"
    docker cp (Join-Path $Root "parfiles") "${C}:/tmp/lab/"
    docker exec -u 0 $C chmod -R a+rX /tmp/lab
}

function Cmd-Setup {
    Log "Criando usuarios e DIRECTORY (SYSTEM)"
    Save (SqlPlus $SysConn "01_setup.sql") "00_setup.txt"
    Log "Criando o schema LAB_RH com dados"
    Save (SqlPlus $AppConn "02_create_schema.sql") "00_setup.txt" -Append
}

function Cmd-Baseline {
    Log "Impressao digital ANTES do desastre"
    Save (SqlPlus $SysConn "03_validate.sql" "LAB_RH") "01_fingerprint_antes.txt"
}

function Cmd-Export {
    Log "Backup logico com expdp"
    DataPump "expdp" $AppConn "export_lab_rh.par"
    CopyLog "exp_lab_rh.log" "02_expdp.log"
    Save (docker exec $C ls -lh /opt/oracle/dumps) "02_arquivos_dump.txt"
}

function Cmd-Disaster {
    Log "Simulando o desastre (DROP TABLE ... PURGE)"
    Save (SqlPlus $AppConn "04_disaster.sql") "03_desastre.txt"
}

function Cmd-Import {
    Log "Restaurando as tabelas com impdp"
    DataPump "impdp" $AppConn "import_tables.par"
    CopyLog "imp_lab_rh.log" "04_impdp.log"
}

function Cmd-Verify {
    Log "Impressao digital DEPOIS da restauracao"
    Save (SqlPlus $SysConn "03_validate.sql" "LAB_RH") "05_fingerprint_depois.txt"
    Log "Comparando ANTES x DEPOIS"
    Compare-Fingerprint "01_fingerprint_antes.txt" "05_fingerprint_depois.txt" "06_diff.txt" "RESULTADO: restauracao identica ao estado original."
}

function Cmd-Remap {
    Log "Bonus: importando o dump no schema LAB_RH_RESTORE (REMAP_SCHEMA)"
    DataPump "impdp" $SysConn "import_remap.par"
    CopyLog "imp_remap_lab_rh_restore.log" "07_impdp_remap.log"
    Save (SqlPlus $SysConn "03_validate.sql" "LAB_RH_RESTORE") "08_fingerprint_restore.txt"
    Compare-Fingerprint "01_fingerprint_antes.txt" "08_fingerprint_restore.txt" "09_diff_remap.txt" "RESULTADO: LAB_RH_RESTORE identico ao LAB_RH original."
}

function Cmd-Down {
    Log "Removendo container e volume"
    docker compose down -v
}

switch ($Comando) {
    "up"       { Cmd-Up }
    "setup"    { Cmd-Setup }
    "baseline" { Cmd-Baseline }
    "export"   { Cmd-Export }
    "disaster" { Cmd-Disaster }
    "import"   { Cmd-Import }
    "verify"   { Cmd-Verify }
    "remap"    { Cmd-Remap }
    "all"      { Cmd-Up; Cmd-Setup; Cmd-Baseline; Cmd-Export; Cmd-Disaster; Cmd-Import; Cmd-Verify; Cmd-Remap
                 Log "Laboratorio concluido. Evidencias em: evidencias\" }
    "down"     { Cmd-Down }
    default    { Get-Content $PSCommandPath -TotalCount 7 | Select-Object -Skip 1; exit 1 }
}
