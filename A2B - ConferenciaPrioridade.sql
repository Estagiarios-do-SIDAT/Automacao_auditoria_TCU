USE mdb;
SET NOCOUNT ON;

-- Janela (UTC equivalente ao mês cheio em -03:00)
DECLARE @From      datetime2(0) = '2025-11-01 03:00:00';
DECLARE @To        datetime2(0) = '2025-12-01 02:59:59';
DECLARE @FromEpoch int = DATEDIFF(SECOND, '1970-01-01', @From);
DECLARE @ToEpoch   int = DATEDIFF(SECOND, '1970-01-01', @To);

-- Grupo A2B (ID BINÁRIO CORRETO DO A2B)
DECLARE @A2B varbinary(16) = 0xCE4FDD26D5053545BF4A11332BB07485;

--------------------------------------------------------------------------------
-- [0] Lista de padrões (A2B) + regras dinâmicas (CPU/MEM/DIS)
--------------------------------------------------------------------------------
DECLARE @Lista TABLE (
    PadraoResumo            nvarchar(300) NOT NULL,
    PrioridadeEsperadaSigla nvarchar(10)  NULL,
    PrioridadeEsperadaEnum  int           NULL,   -- 1..5
    RegraEspecial           nvarchar(10)  NULL    -- 'CPU' | 'MEM' | 'DIS' | 'PAR' | NULL
);

INSERT INTO @Lista(PadraoResumo, PrioridadeEsperadaSigla, PrioridadeEsperadaEnum, RegraEspecial)
VALUES
(N'Passagem de turno', N'P3', 3, NULL),
(N'Backup Job Summary report da Equipe', N'P3', 3, NULL),
(N'Atualização Mensal do As-Built do Serviço de Backup', N'P3', 3, NULL),
(N'Relatório de provisionamento de fitas', N'P3', 3, NULL),
(N'Suspender o Scheduler', N'P1', 1, NULL),
(N'Alterar senha do usuário de serviço', N'P3', 3, NULL),
(N'Alteração de agendamento de backup', N'P3', 3, NULL),
(N'Análise de Vulnerabilidades', N'P5', 5, NULL),
(N'Backup One-time-ful e Descomissionamento das rotinas de backup', N'P3', 3, NULL),
(N'Comissionamento nas rotinas de backup', N'P3', 3, NULL),
(N'Relatório de Indicadores Institucionais', N'P2', 2, NULL),
(N'Teste de Restore VM', N'P4', 4, NULL),
(N'Alteração mensal da senha do usuário de serviços', N'P3', 3, NULL),
(N'Comissionamento', N'P3', 3, NULL),
(N'Descomissionamento', N'P3', 3, NULL),
(N'Recuperação de arquivos', N'P2', 2, NULL),
(N'Verificação Semanal de Alteração de Políticas de Backup', N'P3', 3, NULL),
(N'Backup One-time-full e Descomissionamento de File System das rotinas de backup', N'P3', 3, NULL),
(N'Revisão mensal das tags', N'P3', 3, NULL),
(N'Alteração no agendamento de backup do banco', N'P3', 3, NULL),
(N'Job Completed with Exit Status', N'P2', 2, NULL),
(N'Chamado massivo', N'P3', 3, NULL),
(N'Estado da Library', N'P3', 3, NULL),
(N'Serviço NetBackup Anomaly Detection Management Service Indisponível', N'P1', 1, NULL),
(N'Restore de arquivos', N'P3', 3, NULL),
(N'Verificar máquinas desligadas no vCenter', N'P3', 3, NULL),
(N'Alert Raised', N'P2', 2, NULL),
(N'Required for restore', N'P1', 1, NULL),
(N'User granted reduced permissions due to role misconfiguration', N'P1', 1, NULL),
(N'Estado do Drive', N'P3', 3, NULL),
(N'Estado da Mídia', N'P3', 3, NULL),
(N'Restauração de backup', N'P3', 3, NULL),
(N'NetBackup backup exit', N'P2', 2, NULL),
(N'Atualizar os clients do NetBackup', N'P3', 3, NULL),
(N'Alteração mensal das políticas de backup dos compartilhamentos de arquivos', N'P3', 3, NULL),

-- Regras dinâmicas (CPU/MEM/DIS)
(N'Utilização de CPU',       NULL, NULL, N'CPU'),
(N'Utilização de Memória',   NULL, NULL, N'MEM'),
(N'Utilização do Disco',     NULL, NULL, N'DIS');

--------------------------------------------------------------------------------
-- [0.1] Sinônimos (se quiser, preencha; mantém Canon/Variante)
--------------------------------------------------------------------------------
DECLARE @Sinonimos TABLE (
  Canon    nvarchar(300) NOT NULL,
  Variante nvarchar(300) NOT NULL
);

-- (vazio por padrão; pode inserir depois)

--------------------------------------------------------------------------------
-- [1] Base + Patterns (mesmo modelo)
--------------------------------------------------------------------------------
;WITH Base AS (
    SELECT
        r.ref_num,
        r.summary,
        r.priority,
        r.close_date
    FROM dbo.call_req AS r
    JOIN dbo.cr_stat  AS st ON st.code = r.status
    WHERE r.group_id = @A2B
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

-- Normalização (NBSP/TAB/CR/LF + TRIM + remove espaços) para matching
CROSS APPLY (SELECT CONVERT(nvarchar(max), COALESCE(b.summary, N'')) COLLATE Latin1_General_CI_AI AS sumAI) AS S
CROSS APPLY (
    SELECT LTRIM(
             REPLACE(REPLACE(REPLACE(REPLACE(S.sumAI, NCHAR(160), N' '), CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ')
           ) AS sumClean
) AS ASN
CROSS APPLY (SELECT REPLACE(ASN.sumClean, N' ', N'') AS sumNoSpace) AS NS

-- Extração de % (CPU/MEM/DIS/PAR) do resumo
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
    ORDER BY
        CASE WHEN p.RegraEspecial IN (N'CPU',N'MEM',N'DIS',N'PAR') THEN 0 ELSE 1 END,
        LEN(p.TextoMatch) DESC,
        p.TextoMatch ASC
) AS L
ORDER BY b.close_date DESC, b.ref_num;
