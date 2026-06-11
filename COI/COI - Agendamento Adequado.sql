USE mdb;
SET NOCOUNT ON;
 
--------------------------------------------------------------------------------
-- [PARÂMETROS]
--------------------------------------------------------------------------------
DECLARE @DataInicial VARCHAR(10) = '01/05/2026';
DECLARE @DataFinal   VARCHAR(10) = '30/05/2026';
 
-- COI:               0x3C11B3A9EBCE5D498E2F7D7FF385F967
-- NSTI SO:           0x193E44F2390FF543BB8E98A6C238914C
-- Fornecedores A2B:  0xCE4FDD26D5053545BF4A11332BB07485
DECLARE @Fornecedor VARBINARY(16) = 0x3C11B3A9EBCE5D498E2F7D7FF385F967;
 
DECLARE @From datetime2(0) = DATEADD(HOUR, 3, CONVERT(datetime2(0), @DataInicial + ' 00:00:00', 103));
DECLARE @To   datetime2(0) = DATEADD(HOUR, 3, CONVERT(datetime2(0), @DataFinal   + ' 23:59:59', 103));
 
DECLARE @FromEpoch int = DATEDIFF(SECOND, '1970-01-01', @From);
DECLARE @ToEpoch   int = DATEDIFF(SECOND, '1970-01-01', @To);
 
--------------------------------------------------------------------------------
-- LIMPEZA DAS TEMPORÁRIAS
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#BaseChamados') IS NOT NULL DROP TABLE #BaseChamados;
IF OBJECT_ID('tempdb..#AgendamentoChamado') IS NOT NULL DROP TABLE #AgendamentoChamado;
IF OBJECT_ID('tempdb..#DadosFinais') IS NOT NULL DROP TABLE #DadosFinais;
 
--------------------------------------------------------------------------------
-- 1. FILTRA PRIMEIRO OS CHAMADOS AUDITÁVEIS
--    Isso evita consultar act_log para chamados fora do fornecedor/data/status.
--------------------------------------------------------------------------------
SELECT
    r.persid AS call_req_id,
    r.ref_num,
    r.type AS tipo_chamado,
    ISNULL(f.last_name, N'N/A') AS nome_fornecedor,
    pc.sym AS simbolo,
    r.summary,
    ci.resource_name AS item_configuracao,
    r.priority,
    r.close_date,
    r.assignee
INTO #BaseChamados
FROM dbo.call_req AS r
LEFT JOIN dbo.ca_contact AS f
    ON f.contact_uuid = r.group_id
LEFT JOIN dbo.prob_ctg AS pc
    ON pc.persid = r.category
LEFT JOIN dbo.ca_owned_resource AS ci
    ON ci.own_resource_uuid = r.affected_rc
WHERE r.group_id = @Fornecedor
  AND r.type IN ('I', 'R')
  AND r.close_date IS NOT NULL
  AND r.close_date >= @FromEpoch
  AND r.close_date <= @ToEpoch
  AND r.status IN ('CL', 'CLUNRSLV');
 
CREATE CLUSTERED INDEX IX_BaseChamados_call_req_id
ON #BaseChamados(call_req_id);
 
--------------------------------------------------------------------------------
-- 2. AVALIA AGENDAMENTO SOMENTE DOS CHAMADOS FILTRADOS
--    Regra:
--    - Agendamento: act_log.type = 'ST'
--    - Descrição do agendamento: Status alterado de qualquer status para 'Agendado'
--    - Justificativa: act_log.type = 'LOG'
--    - Janela: 5 minutos antes ou 5 minutos depois
--------------------------------------------------------------------------------
SELECT
    b.call_req_id,
    MIN(
        CASE
            WHEN j.TemJustificativa = 1 THEN 1
            ELSE 0
        END
    ) AS Agendamento100PctCorreto
INTO #AgendamentoChamado
FROM #BaseChamados AS b
INNER LOOP JOIN dbo.act_log AS ag
    ON ag.call_req_id = b.call_req_id
   AND ag.type = 'ST'
   AND ag.description LIKE 'Status alterado de % para ''Agendado''.'
OUTER APPLY (
    SELECT TOP (1)
        1 AS TemJustificativa
    FROM dbo.act_log AS l
    WHERE l.call_req_id = ag.call_req_id
      AND l.type = 'LOG'
      AND l.time_stamp >= ag.time_stamp - 300
      AND l.time_stamp <= ag.time_stamp + 300
) AS j
GROUP BY
    b.call_req_id
OPTION (RECOMPILE);
 
CREATE CLUSTERED INDEX IX_AgendamentoChamado_call_req_id
ON #AgendamentoChamado(call_req_id);
 
--------------------------------------------------------------------------------
-- 3. RESULTADO FINAL
--------------------------------------------------------------------------------
SELECT
    b.ref_num AS [N° chamado],
 
    CASE b.tipo_chamado
        WHEN 'R' THEN N'Solicitação'
        WHEN 'I' THEN N'Incidente'
        ELSE N'N/A'
    END AS [Tipo],
 
    b.nome_fornecedor AS [Fornecedor],
 
    ISNULL(b.simbolo, N'N/A') AS [Símbolo],
 
    LTRIM(RTRIM(b.summary)) AS [Resumo],
 
    ISNULL(b.item_configuracao, N'N/A') AS [Item de configuração],
 
    CASE b.priority
        WHEN 1 THEN N'1 - Máxima'
        WHEN 2 THEN N'2 - Alta'
        WHEN 3 THEN N'3 - Média'
        WHEN 4 THEN N'4 - Baixa'
        WHEN 5 THEN N'5 - Mínima'
        ELSE N'N/A'
    END AS [Prioridade],
 
    CASE
        WHEN resp.contact_uuid IS NULL THEN N'N/A'
        WHEN nome.first_name_limpo IS NOT NULL OR nome.last_name_limpo IS NOT NULL
            THEN LTRIM(RTRIM(
                ISNULL(nome.first_name_limpo, N'') +
                CASE
                    WHEN nome.first_name_limpo IS NOT NULL
                     AND nome.last_name_limpo IS NOT NULL
                    THEN N' '
                    ELSE N''
                END +
                ISNULL(nome.last_name_limpo, N'')
            ))
        WHEN nome.userid_limpo IS NOT NULL THEN nome.userid_limpo
        ELSE N'N/A'
    END AS [Responsável],
 
    DATEADD(HOUR, -3, DATEADD(SECOND, b.close_date, '1970-01-01')) AS [Data de fechamento],
 
    CASE
        WHEN ag.call_req_id IS NULL THEN N' - '
        WHEN ag.Agendamento100PctCorreto = 1 THEN N'SIM'
        ELSE N'NÃO'
    END AS [Agendamento adequado]
 
INTO #DadosFinais
FROM #BaseChamados AS b
LEFT JOIN #AgendamentoChamado AS ag
    ON ag.call_req_id = b.call_req_id
LEFT JOIN dbo.ca_contact AS resp
    ON resp.contact_uuid = b.assignee
OUTER APPLY (
    SELECT
        NULLIF(LTRIM(RTRIM(ISNULL(resp.first_name, N''))), N'') AS first_name_limpo,
        NULLIF(LTRIM(RTRIM(ISNULL(resp.last_name,  N''))), N'') AS last_name_limpo,
        NULLIF(LTRIM(RTRIM(ISNULL(resp.userid,     N''))), N'') AS userid_limpo
) AS nome;
 
--------------------------------------------------------------------------------
-- RESULTADO 1: APENAS SOLICITAÇÕES
--------------------------------------------------------------------------------
SELECT *
FROM #DadosFinais
WHERE [Tipo] = N'Solicitação'
ORDER BY [Data de fechamento] DESC, [Fornecedor], [N° chamado];
 
--------------------------------------------------------------------------------
-- RESULTADO 2: APENAS INCIDENTES
--------------------------------------------------------------------------------
SELECT *
FROM #DadosFinais
WHERE [Tipo] = N'Incidente'
ORDER BY [Data de fechamento] DESC, [Fornecedor], [N° chamado];