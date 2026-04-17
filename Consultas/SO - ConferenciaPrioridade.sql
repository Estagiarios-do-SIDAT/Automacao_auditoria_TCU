USE mdb;
SET NOCOUNT ON;

-- Janela (UTC equivalente ao mês cheio em -03:00)
DECLARE @From      datetime2(0) = '2026-01-01 03:00:00';
DECLARE @To        datetime2(0) = '2027-01-01 02:59:59';
DECLARE @FromEpoch int = DATEDIFF(SECOND, '1970-01-01', @From);
DECLARE @ToEpoch   int = DATEDIFF(SECOND, '1970-01-01', @To);

-- Grupo NSTI SO
DECLARE @NSTISO varbinary(16) = 0x193E44F2390FF543BB8E98A6C238914C;

--------------------------------------------------------------------------------
-- [0] Lista de padrões + regras dinâmicas (CPU/MEM/DIS)
--------------------------------------------------------------------------------
DECLARE @Lista TABLE (
    PadraoResumo            nvarchar(300) NOT NULL,
    PrioridadeEsperadaSigla nvarchar(10)  NULL,
    PrioridadeEsperadaEnum  int           NULL,   -- 1..5
    RegraEspecial           nvarchar(10)  NULL    -- 'CPU' | 'MEM' | 'DIS' | 'PAR' | NULL
);

INSERT INTO @Lista(PadraoResumo, PrioridadeEsperadaSigla, PrioridadeEsperadaEnum, RegraEspecial)
VALUES
(N'Tratamento de vulnerabilidades', N'P4', 4, NULL),
(N'NSTI S.O. - Checklist diário', N'P3', 3, NULL),
(N'NSTI SO.STORAGE - Checklist diário', N'P3', 3, NULL),
(N'NSTI SO.STORAGE - Indicadores Institucionais', N'P3', 3, NULL),
(N'Estender Discos', N'P3', 3, NULL),
(N'Comissionamento', N'P3', 3, NULL),
(N'Descomissionamento', N'P3', 3, NULL),
(N'Recomissionar', N'P3', 3, NULL),
(N'Atualização da documentação dos servidores do ambiente de TI do TCU', N'P3', 3, NULL),
(N'Atividade de rotina de verificação de discos dos servidores WFS', N'P3', 3, NULL),
(N'Análise de Vulnerabilidades', N'P5', 5, NULL),
(N'Alteração de Nomenclatura de Servidor - Checklist SO', N'P2', 2, NULL),
(N'Alteração de Nomenclatura de Nome Físico - Checklist', N'P3', 3, NULL),
(N'Atualização Servidores Windows Server do SINAP', N'P3', 3, NULL),
(N'Validação de teste de restore', N'P4', 4, NULL),
(N'Atualização manual de clientes ARC', N'P4', 4, NULL),

-- Regras dinâmicas CPU/MEM/DIS
(N'Utilização de CPU',       NULL, NULL, N'CPU'),
(N'Utilização de Memória',   NULL, NULL, N'MEM'),
(N'Utilização do Disco',     NULL, NULL, N'DIS'),

(N'Adicionar/ Criar/ Expandir Volume ou Luns', N'P3', 3, NULL),
(N'Estender', N'P3', 3, NULL),
(N'Adicionar Discos', N'P3', 3, NULL),
(N'Expansão de disco', N'P3', 3, NULL),
(N'Criar Luns', N'P3', 3, NULL),
(N'Adicionar Luns', N'P3', 3, NULL),
(N'Formatar e instalar o SO Linux', N'P3', 3, NULL),
(N'Instalação de Patchs e reboot nas VMs do Cluster', N'P3', 3, NULL),
(N'NSTI S.O. - Rotina Semestral - Health-check de saúde do sistema operacional', N'P3', 3, NULL),
(N'SO.STORAGE - Alterar senha do usuário de serviço', N'P3', 3, NULL),
(N'Validação de testes de restore', N'P3', 3, NULL),
(N'Validação de testes de restauração', N'P3', 3, NULL),
(N'Adicionar / Estender / Montar / Alocar Discos', N'P3', 3, NULL),
(N'Restaurar configurações de fábrica', N'P3', 3, NULL),
(N'Teste de Restore VM', N'P4', 4, NULL),
(N'Atualizar VMware Tools para corrigir vulnerabilidade', N'P3', 3, NULL),
(N'Alocar disco', N'P3', 3, NULL),
(N'Estender disco', N'P3', 3, NULL);

--------------------------------------------------------------------------------
-- [0.1] Sinônimos (Canon/Variante)
--------------------------------------------------------------------------------
DECLARE @Sinonimos TABLE (
  Canon    nvarchar(300) NOT NULL,
  Variante nvarchar(300) NOT NULL
);

INSERT INTO @Sinonimos(Canon, Variante) VALUES (N'Comissionamento', N'Comissionar');
INSERT INTO @Sinonimos(Canon, Variante) VALUES (N'Análise de Vulnerabilidades', N'Análise de Vulnerabilidade');
INSERT INTO @Sinonimos(Canon, Variante) VALUES (N'Estender', N'Estender disco');
INSERT INTO @Sinonimos(Canon, Variante) VALUES (N'Descomissionamento', N'Descomissionar');

--------------------------------------------------------------------------------
-- [1] Base + Patterns (igual ao COI, sem “regra do início”)
--------------------------------------------------------------------------------
;WITH Base AS (
    SELECT
        r.ref_num,
        r.summary,
        r.priority,
        r.close_date
    FROM dbo.call_req AS r
    JOIN dbo.cr_stat  AS st ON st.code = r.status
    WHERE r.group_id = @NSTISO
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

-- TOP 1 padrão (Canon/Variante) + cálculo CPU/MEM/DIS/PAR quando aplicável
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
