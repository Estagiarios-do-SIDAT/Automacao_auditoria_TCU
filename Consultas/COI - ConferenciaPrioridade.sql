USE mdb;
SET NOCOUNT ON;

-- Janela (UTC equivalente ao mês cheio em -03:00)
DECLARE @From      datetime2(0) = '2026-01-01 03:00:00';
DECLARE @To        datetime2(0) = '2027-01-01 02:59:59';
DECLARE @FromEpoch int = DATEDIFF(SECOND, '1970-01-01', @From);
DECLARE @ToEpoch   int = DATEDIFF(SECOND, '1970-01-01', @To);

-- Grupo COI
DECLARE @COI varbinary(16) = 0x3C11B3A9EBCE5D498E2F7D7FF385F967;

--------------------------------------------------------------------------------
-- [0] Lista de padrões + regras CPU/MEM/DIS/PAR
--------------------------------------------------------------------------------
DECLARE @Lista TABLE (
    PadraoResumo            nvarchar(300) NOT NULL,
    PrioridadeEsperadaSigla nvarchar(10)  NULL,
    PrioridadeEsperadaEnum  int           NULL,   -- 1..5
    RegraEspecial           nvarchar(10)  NULL    -- 'CPU' | 'MEM' | 'DIS' | 'PAR' | NULL
);

INSERT INTO @Lista(PadraoResumo, PrioridadeEsperadaSigla, PrioridadeEsperadaEnum, RegraEspecial)
VALUES
    (N'Adicionar / Estender / Montar / Alocar Discos', N'P3', 3, NULL),
    (N'Alteração de Task', N'P3', 3, NULL),
    (N'Alteração de senhas de contas utilizadas nos telões do SIDAT', N'P3', 3, NULL),
    (N'Alterar Nomenclatura de Máquina Virtual', N'P3', 3, NULL),
    (N'Alerta Dispositivo não respondendo', N'P3', 3, NULL),
    (N'AMM - FAVR', N'P5', 5, NULL),
    (N'Análise de Vulnerabilidades', N'P5', 5, NULL),
    (N'Arquivar POP', N'P4', 4, NULL),
    (N'Avaliar o incidente na console de segurança da Microsoft', N'P2', 2, NULL),
    (N'Atualizar Documento', N'P4', 4, NULL),
    (N'Atualizar POP', N'P4', 4, NULL),
    (N'Backup - Alert: Aux copy job Failed Type: Job Management - Auxiliary Copy', N'P2', 2, NULL),
    (N'Backup - Alert: Midia Requerida na Library Type: Operation - Event Viewer Events', N'P1', 1, NULL),
    (N'Backup - Alert: Midias Removidas da Tape Library Type', N'P2', 2, NULL),
    (N'Backup - Aplicação de script no Commvault DB Maintenance', N'P3', 3, NULL),
    (N'Backup - Job Summary report', N'P3', 3, NULL),
    (N'Backup - Manutenção no banco de dados SQL do Commvault com DBmaintenance', N'P3', 3, NULL),
    (N'Backup - Realizar limpeza de ciclos presos em Storage Policy', N'P3', 3, NULL),
    (N'Backup - Revisão das Disk Libraries', N'P3', 3, NULL),
    (N'Backup - Rotina Diária - Gerar relatório de jobs suspensos e killed', N'P3', 3, NULL),
    (N'Backup - Storage Information Report - Media Information report', N'P2', 2, NULL),
    (N'Backup Commvault - Cofreamento diário, ciclo de backup', N'P2', 2, NULL),
    (N'BI-ANALYTICS - POWER BI', N'P3', 3, NULL),
    (N'BI-ANALYTICS - POWERCENTER', N'P4', 4, NULL),
    (N'Blackout', N'P1', 1, NULL),
    (N'Chamado massivo', N'P3', 3, NULL),
    (N'Checklist de Saúde do Desktop Virtual', N'P3', 3, NULL),
    (N'COI - Coleta de X Fitas Novas no Depósito Quarentena do SIDAT', N'P3', 3, NULL),
    (N'COI - Manutenção de documentação', N'P4', 4, NULL),
    (N'COI - Prazo de aquisição de certificação', N'P3', 3, NULL),
    (N'COI - Tempo de vida útil de ativo comissionado', N'P3', 3, NULL),
    (N'Comissionamento', N'P3', 3, NULL),
    (N'Conferência da fila do SDM', N'P4', 4, NULL),
    (N'Criação de Task', N'P3', 3, NULL),
    (N'Criar Política de Backup', N'P3', 3, NULL),
    (N'Credenciamento de Acessos', N'P4', 4, NULL),
    (N'Definir senha de acesso de usuário criado no e-Dados', N'P3', 3, NULL),
    (N'Descomissionamento', N'P3', 3, NULL),
    (N'Descomissionar Máquina Virtual (VM)', N'P3', 3, NULL),
    (N'Descredenciamento de Acessos', N'P3', 3, NULL),
    (N'Desligamento e Religamento do Datacenter', N'P4', 4, NULL),
    (N'Designação Técnica', N'P4', 4, NULL),
    (N'Desligamento e Religamento do Datacenter', N'P4', 4, NULL),
    (N'Descredenciamento de Acessos', N'P3', 3, NULL),
    (N'Desligamento e Religamento do Datacenter', N'P4', 4, NULL),
    (N'Descredenciamento de Acessos', N'P3', 3, NULL),
    (N'Disk read request responses are too high', N'P3', 3, NULL),
    (N'director_a2 - Port - 5/45: Status Offline', N'P2', 2, NULL),
    (N'Documentação Técnica', N'P4', 4, NULL),
    (N'Efetuar a verificação de todas as mídias Appendable do mês', N'P4', 4, NULL),
    (N'Embratel  - Descredenciamento', N'P4', 4, NULL),
    (N'Embratel - Credenciamento', N'P4', 4, NULL),
    (N'Embratel - Interface GE3 - Status Operacional Indisponível', N'P2', 2, NULL),
    (N'Embratel - sd-wan-ap - ICMP Ping', N'P3', 3, NULL),
    (N'Envio de relatórios de chamados ativos de fornecedores que não utilizam o SDM', N'P3', 3, NULL),
    (N'G4S - Credenciamento', N'P4', 4, NULL),
    (N'G4S - Descredenciamento', N'P4', 4, NULL),
    (N'G4S - Usuário solicita o conserto da catraca', N'P4', 4, NULL),
    (N'Gerar relatório de modificações semanais', N'P3', 3, NULL),
    (N'ICMP Ping response time', N'P3', 3, NULL),
    (N'Indisponibilidade de comunicação com Agente Zabbix', N'P2', 2, NULL),
    (N'Indisponibilidade de comunicação por protocolo ICMP', N'P2', 2, NULL),
    (N'Inativar Item de Configuração', N'P3', 3, NULL),
    (N'Inserir Mídia', N'P1', 1, NULL),
    (N'Jet Telecom – rt_tcu_jet_telecom', N'P3', 3, NULL),
    (N'Job Completed with Exit Status', N'P2', 2, NULL),
    (N'Job Management - Data Protection', N'P2', 2, NULL),
    (N'LCS - Biometria - Credenciar Biometria do Accesspe', N'P3', 3, NULL),
    (N'LCS - Checklist Diário', N'P3', 3, NULL),
    (N'LCS - Credenciamento', N'P4', 4, NULL),
    (N'LCS - Descredenciamento', N'P4', 4, NULL),
    (N'LCS - Revisão de documentação do DCIM', N'P3', 3, NULL),
    (N'LCS - Rotina Semanal - Envio consolidado de relatório de Health check do DCIM para o TCU', N'P3', 3, NULL),
    (N'LCS - Rotina Semanal - Inspeção no Datacenter e DCIM', N'P3', 3, NULL),
    (N'Link down', N'P2', 2, NULL),
    (N'Login - Concessão de acesso', N'P3', 3, NULL),
    (N'Login - Descredenciamento', N'P3', 3, NULL),
    (N'network link is down', N'P2', 2, NULL),
    (N'Number of APEX sessions exceeded the critical limit greater', N'P3', 3, NULL),
    (N'NSTI APLICAÇÃO- FAVR', N'P4', 4, NULL),
    (N'NSTI BI-ANALYTICS - FAVR', N'P4', 4, NULL),
    (N'NSTI COI- FAVR', N'P4', 4, NULL),
    (N'NSTI GCM - FAVR', N'P4', 4, NULL),
    (N'NSTI PPD- FAVR', N'P4', 4, NULL),
    (N'NSTI REDE - FAVR', N'P4', 4, NULL),
    (N'NSTI SEGURANÇA - FAVR', N'P4', 4, NULL),
    (N'O serviço AI DataAccessService está indisponível', N'P3', 3, NULL),
    (N'O serviço AI InfoService está indisponível', N'P3', 3, NULL),
    (N'O serviço AI Mobile Bridge está indisponível', N'P3', 3, NULL),
    (N'O serviço AI Watchdog está indisponível', N'P3', 3, NULL),
    (N'Passagem de turno', N'P3', 3, NULL),
    (N'POP - (Atualizar)', N'P4', 4, NULL),
    (N'Projeto RKE', N'P4', 4, NULL),
    (N'Protect4 - FAVR', N'P5', 5, NULL),
    (N'Recebimento de Material no SIDAT', N'P3', 3, NULL),
    (N'Recolher crachá de colaborador descredenciado', N'P4', 4, NULL),
    (N'Required for restore', N'P1', 1, NULL),
    (N'Relatório Semanal de IC''s criados', N'P3', 3, NULL),
    (N'Remover Mídia', N'P2', 2, NULL),
    (N'Remover o File System (share) do host', N'P3', 3, NULL),
    (N'Revisar e atualizar lista de acesso permanente de acesso junto a SEGUR', N'P3', 3, NULL),
    (N'Rotina Anual - Envio da Planilha de colaboradores para os fiscais', N'P3', 3, NULL),
    (N'Rotina Mensal - Avaliação de Recorrências de Incidentes para Registro de Problema', N'P4', 4, NULL),
    (N'Rotina Mensal - Envio de Chamados', N'P3', 3, NULL),
    (N'Rotina Semanal - Relatório de Chamados do Tipo Problema', N'P3', 3, NULL),
    (N'rt_tcu_jet_telecom', N'P3', 3, NULL),
    (N'Serviço Commvault Communications indisponível', N'P1', 1, NULL),
    (N'SNMP Trap', N'P2', 2, NULL),
    (N'Status Operacional Indisponível', N'P2', 2, NULL),
    (N'Suspensão de chamados automáticos de Inspeção no Datacenter e no DCIM', N'P3', 3, NULL),
    (N'Suspensão de Tasks de abertura automatizada de chamados', N'P3', 3, NULL),
    (N'Suspender Tasks de Chamados Automático', N'P3', 3, NULL),
    (N'TANDBERG  - Credenciamento', N'P4', 4, NULL),
    (N'Tandberg - Credenciamento', N'P4', 4, NULL),
    (N'Tandberg - Descredenciamento', N'P4', 4, NULL),
    (N'Task de Chamado Automático no SDM', N'P3', 3, NULL),
    (N'Task de Chamado Automático no SDM - Tasks do time de BI - Documento', N'P3', 3, NULL),
    (N'Verificação ambiente WIKi', N'P4', 4, NULL),
    (N'Verificação do ambiente moodle', N'P4', 4, NULL),
    (N'Verificar máquinas desligadas no vCenter', N'P5', 5, NULL),
    (N'VIRTUAL - Descredenciamento', N'P3', 3, NULL),
    (N'Vistoria no Ambiente do SIDAT', N'P3', 3, NULL),

    -- Regras dinâmicas (CPU/MEM/DIS/PAR)
    (N'Utilização de CPU',         NULL, NULL, N'CPU'),
    (N'Utilização de Memória',     NULL, NULL, N'MEM'),
    (N'Utilização do Disco',       NULL, NULL, N'DIS'),
    (N'Utilização da Partição',    NULL, NULL, N'PAR');

--------------------------------------------------------------------------------
-- [0.1] Sinônimos (matching)
--------------------------------------------------------------------------------
DECLARE @Sinonimos TABLE (
  Canon    nvarchar(300) NOT NULL,
  Variante nvarchar(300) NOT NULL
);

-- "Alterar Task" ? "Alteração de Task"
INSERT INTO @Sinonimos(Canon, Variante)
VALUES (N'Alteração de Task', N'Alterar Task');

INSERT INTO @Sinonimos(Canon, Variante)
VALUES (N'Inserir Mídia', N'Inserir de Mídia');

INSERT INTO @Sinonimos(Canon, Variante)
VALUES (N'Comissionamento', N'Comissionar');

INSERT INTO @Sinonimos(Canon, Variante)
VALUES (N'Descomissionamento', N'Descomissionar');

-- Bloco de discos
INSERT INTO @Sinonimos(Canon, Variante)
VALUES (N'Adicionar / Estender / Montar / Alocar Discos', N'Adicionar disco');
INSERT INTO @Sinonimos(Canon, Variante)
VALUES (N'Adicionar / Estender / Montar / Alocar Discos', N'Estender disco');
INSERT INTO @Sinonimos(Canon, Variante)
VALUES (N'Adicionar / Estender / Montar / Alocar Discos', N'Montar disco');
INSERT INTO @Sinonimos(Canon, Variante)
VALUES (N'Adicionar / Estender / Montar / Alocar Discos', N'Alocar disco');

--------------------------------------------------------------------------------
-- [1] Base + Patterns (igual aos outros)
--------------------------------------------------------------------------------
;WITH Base AS (
    SELECT
        r.ref_num,
        r.summary,
        r.priority,
        r.close_date
    FROM dbo.call_req AS r
    JOIN dbo.cr_stat  AS st ON st.code = r.status
    WHERE r.group_id = @COI
      AND r.type IN ('I','R')
      AND r.close_date IS NOT NULL
      AND r.close_date >= @FromEpoch
      AND r.close_date <= @ToEpoch
      AND st.code IN ('CL','CLUNRSLV')
),
Patterns AS (
    SELECT
        li.PadraoResumo AS TextoMatch,
        li.PadraoResumo AS Canon,
        li.PrioridadeEsperadaEnum,
        li.RegraEspecial
    FROM @Lista li

    UNION ALL

    SELECT
        s.Variante AS TextoMatch,
        s.Canon    AS Canon,
        li.PrioridadeEsperadaEnum,
        li.RegraEspecial
    FROM @Sinonimos s
    JOIN @Lista li ON li.PadraoResumo = s.Canon
)
SELECT
    b.ref_num AS Chamado,
    LTRIM(RTRIM(CONVERT(nvarchar(max), b.summary))) AS Resumo,

    CASE L.PrioridadeEsperadaEnumCalc
        WHEN 1 THEN N'1 - Máxima'
        WHEN 2 THEN N'2 - Alta'
        WHEN 3 THEN N'3 - Média'
        WHEN 4 THEN N'4 - Baixa'
        WHEN 5 THEN N'5 - Mínima'
        ELSE N'N/A'
    END AS PrioridadeEsperadaNaLista,

    CASE b.priority
        WHEN 1 THEN N'1 - Máxima'
        WHEN 2 THEN N'2 - Alta'
        WHEN 3 THEN N'3 - Média'
        WHEN 4 THEN N'4 - Baixa'
        WHEN 5 THEN N'5 - Mínima'
        ELSE N'N/A'
    END AS PrioridadeDoChamado,

    CASE
        WHEN L.Canon IS NULL                             THEN N'N/A'
        WHEN L.PrioridadeEsperadaEnumCalc IS NULL        THEN N'NÃO'
        WHEN b.priority <= L.PrioridadeEsperadaEnumCalc  THEN N'SIM'
        ELSE N'NÃO'
    END AS PrioridadeConfere
FROM Base b

-- Normalização (NBSP/TAB/CR/LF + TRIM + remove espaços)
CROSS APPLY (SELECT CONVERT(nvarchar(max), COALESCE(b.summary, N'')) COLLATE Latin1_General_CI_AI AS sumAI) AS S
CROSS APPLY (
    SELECT LTRIM(
             REPLACE(REPLACE(REPLACE(REPLACE(S.sumAI, NCHAR(160), N' '), CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ')
           ) AS sumClean
) AS ASN
CROSS APPLY (SELECT REPLACE(ASN.sumClean, N' ', N'') AS sumNoSpace) AS NS

-- Regra extra do COI: “tem que estar no começo”
CROSS APPLY (
    SELECT
      CASE WHEN LEFT(NS.sumNoSpace, LEN(REPLACE(N'Arquivar POP',       N' ', N''))) = REPLACE(N'Arquivar POP',       N' ', N'') THEN 1 ELSE 0 END AS ArquivarPOPAtStart,
      CASE WHEN LEFT(NS.sumNoSpace, LEN(REPLACE(N'Atualizar POP',      N' ', N''))) = REPLACE(N'Atualizar POP',      N' ', N'') THEN 1 ELSE 0 END AS AtualizarPOPAtStart,
      CASE WHEN LEFT(NS.sumNoSpace, LEN(REPLACE(N'Blackout',           N' ', N''))) = REPLACE(N'Blackout',           N' ', N'') THEN 1 ELSE 0 END AS BlackoutAtStart,
      CASE WHEN LEFT(NS.sumNoSpace, LEN(REPLACE(N'Comissionamento',    N' ', N''))) = REPLACE(N'Comissionamento',    N' ', N'') THEN 1 ELSE 0 END AS ComissAtStart,
      CASE WHEN LEFT(NS.sumNoSpace, LEN(REPLACE(N'Criação de Task',    N' ', N''))) = REPLACE(N'Criação de Task',    N' ', N'') THEN 1 ELSE 0 END AS CriacaoTaskAtStart,
      CASE WHEN LEFT(NS.sumNoSpace, LEN(REPLACE(N'Descomissionamento', N' ', N''))) = REPLACE(N'Descomissionamento', N' ', N'') THEN 1 ELSE 0 END AS DescomissAtStart
) AS KB

-- Extração de % (CPU/MEM/DIS/PAR)
CROSS APPLY (
    SELECT
        NULLIF(CHARINDEX(REPLACE(N'Utilização de CPU',      N' ', N''), NS.sumNoSpace), 0) AS posCPU,
        NULLIF(CHARINDEX(REPLACE(N'Utilização de Memória',  N' ', N''), NS.sumNoSpace), 0) AS posMEM,
        NULLIF(CHARINDEX(REPLACE(N'Utilização do Disco',    N' ', N''), NS.sumNoSpace), 0) AS posDIS,
        NULLIF(CHARINDEX(REPLACE(N'Utilização da Partição', N' ', N''), NS.sumNoSpace), 0) AS posPAR
) AS P
CROSS APPLY (
    SELECT
        CASE WHEN P.posCPU IS NOT NULL THEN SUBSTRING(NS.sumNoSpace, P.posCPU, 200) END AS segCPU,
        CASE WHEN P.posMEM IS NOT NULL THEN SUBSTRING(NS.sumNoSpace, P.posMEM, 200) END AS segMEM,
        CASE WHEN P.posDIS IS NOT NULL THEN SUBSTRING(NS.sumNoSpace, P.posDIS, 200) END AS segDIS,
        CASE WHEN P.posPAR IS NOT NULL THEN SUBSTRING(NS.sumNoSpace, P.posPAR, 200) END AS segPAR
) AS SEG
CROSS APPLY (
    SELECT
        NULLIF(PATINDEX('%[0-9][0-9][0-9][%]%', ISNULL(SEG.segCPU, N'')), 0) AS pCPU3,
        NULLIF(PATINDEX('%[0-9][0-9][%]%',      ISNULL(SEG.segCPU, N'')), 0) AS pCPU2,
        NULLIF(PATINDEX('%[0-9][0-9][0-9][%]%', ISNULL(SEG.segMEM, N'')), 0) AS pMEM3,
        NULLIF(PATINDEX('%[0-9][0-9][%]%',      ISNULL(SEG.segMEM, N'')), 0) AS pMEM2,
        NULLIF(PATINDEX('%[0-9][0-9][0-9][%]%', ISNULL(SEG.segDIS, N'')), 0) AS pDIS3,
        NULLIF(PATINDEX('%[0-9][0-9][%]%',      ISNULL(SEG.segDIS, N'')), 0) AS pDIS2,
        NULLIF(PATINDEX('%[0-9][0-9][0-9][%]%', ISNULL(SEG.segPAR, N'')), 0) AS pPAR3,
        NULLIF(PATINDEX('%[0-9][0-9][%]%',      ISNULL(SEG.segPAR, N'')), 0) AS pPAR2
) AS PCTPOS
CROSS APPLY (
    SELECT
        CASE WHEN PCTPOS.pCPU3 IS NOT NULL THEN TRY_CONVERT(int, SUBSTRING(SEG.segCPU, PCTPOS.pCPU3, 3))
             WHEN PCTPOS.pCPU2 IS NOT NULL THEN TRY_CONVERT(int, SUBSTRING(SEG.segCPU, PCTPOS.pCPU2, 2))
             ELSE NULL END AS CpuPercent,

        CASE WHEN PCTPOS.pMEM3 IS NOT NULL THEN TRY_CONVERT(int, SUBSTRING(SEG.segMEM, PCTPOS.pMEM3, 3))
             WHEN PCTPOS.pMEM2 IS NOT NULL THEN TRY_CONVERT(int, SUBSTRING(SEG.segMEM, PCTPOS.pMEM2, 2))
             ELSE NULL END AS MemPercent,

        CASE WHEN PCTPOS.pDIS3 IS NOT NULL THEN TRY_CONVERT(int, SUBSTRING(SEG.segDIS, PCTPOS.pDIS3, 3))
             WHEN PCTPOS.pDIS2 IS NOT NULL THEN TRY_CONVERT(int, SUBSTRING(SEG.segDIS, PCTPOS.pDIS2, 2))
             ELSE NULL END AS DiskPercent,

        CASE WHEN PCTPOS.pPAR3 IS NOT NULL THEN TRY_CONVERT(int, SUBSTRING(SEG.segPAR, PCTPOS.pPAR3, 3))
             WHEN PCTPOS.pPAR2 IS NOT NULL THEN TRY_CONVERT(int, SUBSTRING(SEG.segPAR, PCTPOS.pPAR2, 2))
             ELSE NULL END AS ParPercent
) AS VAL

OUTER APPLY (
    SELECT TOP (1)
        p.Canon,
        CASE
            WHEN p.RegraEspecial = N'CPU' THEN
                CASE WHEN VAL.CpuPercent BETWEEN 90 AND 94 THEN 3
                     WHEN VAL.CpuPercent BETWEEN 95 AND 96 THEN 2
                     WHEN VAL.CpuPercent >= 97              THEN 1
                     ELSE NULL END
            WHEN p.RegraEspecial = N'MEM' THEN
                CASE WHEN VAL.MemPercent BETWEEN 90 AND 94 THEN 3
                     WHEN VAL.MemPercent BETWEEN 95 AND 96 THEN 2
                     WHEN VAL.MemPercent >= 97              THEN 1
                     ELSE NULL END
            WHEN p.RegraEspecial = N'DIS' THEN
                CASE WHEN VAL.DiskPercent BETWEEN 90 AND 94 THEN 3
                     WHEN VAL.DiskPercent BETWEEN 95 AND 96 THEN 2
                     WHEN VAL.DiskPercent >= 97              THEN 1
                     ELSE NULL END
            WHEN p.RegraEspecial = N'PAR' THEN
                CASE WHEN VAL.ParPercent BETWEEN 90 AND 94 THEN 3
                     WHEN VAL.ParPercent BETWEEN 95 AND 96 THEN 2
                     WHEN VAL.ParPercent >= 97              THEN 1
                     ELSE NULL END
            ELSE p.PrioridadeEsperadaEnum
        END AS PrioridadeEsperadaEnumCalc,
        p.TextoMatch
    FROM Patterns p
    WHERE NS.sumNoSpace LIKE N'%' + REPLACE(p.TextoMatch, N' ', N'') + N'%'
      AND (p.Canon <> N'Arquivar POP'        OR KB.ArquivarPOPAtStart  = 1)
      AND (p.Canon <> N'Atualizar POP'       OR KB.AtualizarPOPAtStart = 1)
      AND (p.Canon <> N'Blackout'            OR KB.BlackoutAtStart     = 1)
      AND (p.Canon <> N'Comissionamento'     OR KB.ComissAtStart       = 1)
      AND (p.Canon <> N'Criação de Task'     OR KB.CriacaoTaskAtStart  = 1)
      AND (p.Canon <> N'Descomissionamento'  OR KB.DescomissAtStart    = 1)
    ORDER BY
      CASE
        WHEN p.Canon = N'Arquivar POP'        AND KB.ArquivarPOPAtStart  = 1 THEN 0
        WHEN p.Canon = N'Atualizar POP'       AND KB.AtualizarPOPAtStart = 1 THEN 0
        WHEN p.Canon = N'Blackout'            AND KB.BlackoutAtStart     = 1 THEN 0
        WHEN p.Canon = N'Comissionamento'     AND KB.ComissAtStart       = 1 THEN 0
        WHEN p.Canon = N'Criação de Task'     AND KB.CriacaoTaskAtStart  = 1 THEN 0
        WHEN p.Canon = N'Descomissionamento'  AND KB.DescomissAtStart    = 1 THEN 0
        ELSE CASE WHEN p.RegraEspecial IN (N'CPU',N'MEM',N'DIS',N'PAR') THEN 0 ELSE 1 END
      END,
      LEN(p.TextoMatch) DESC,
      p.TextoMatch ASC
) AS L
ORDER BY b.close_date DESC, b.ref_num;
