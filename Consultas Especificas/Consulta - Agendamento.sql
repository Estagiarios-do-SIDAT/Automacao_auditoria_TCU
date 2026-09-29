USE mdb;
SET NOCOUNT ON;
--------------------------------------------------------------------------------
-- PARÂMETROS
--------------------------------------------------------------------------------
DECLARE @DataInicial VARCHAR(10) = '01/04/2026';
DECLARE @DataFinal   VARCHAR(10) = '30/04/2026';
DECLARE @Fornecedor VARBINARY(16) = 0xCE4FDD26D5053545BF4A11332BB07485;
DECLARE @From datetime2(0) = DATEADD(HOUR, 3, CONVERT(datetime2(0), @DataInicial + ' 00:00:00', 103));
DECLARE @To   datetime2(0) = DATEADD(HOUR, 3, CONVERT(datetime2(0), @DataFinal   + ' 23:59:59', 103));
DECLARE @FromEpoch int = DATEDIFF(SECOND, '1970-01-01', @From);
DECLARE @ToEpoch   int = DATEDIFF(SECOND, '1970-01-01', @To);
 
--------------------------------------------------------------------------------
-- 1) Filtra os chamados UMA VEZ. Tudo que vem depois (act_log) só olha
--    para call_req_id que já sabemos que interessam, em vez de varrer
--    a tabela inteira 3x como no original.
--------------------------------------------------------------------------------
;WITH Chamados AS (
    SELECT r.persid, r.ref_num, r.type, r.summary, r.close_date, r.group_id
    FROM dbo.call_req r
    WHERE r.group_id = @Fornecedor
      AND r.type IN ('I', 'R')
      AND r.close_date BETWEEN @FromEpoch AND @ToEpoch
      AND r.status IN ('CL', 'CLUNRSLV')
),
 
-- 2) Só as linhas de act_log tipo 'ST' relevantes (entrada/saída de 'Agendado'),
--    já restritas aos chamados filtrados.
StatusChanges AS (
    SELECT
        a.call_req_id,
        a.time_stamp,
        CASE WHEN a.description LIKE 'Status alterado de % para ''Agendado''.%' THEN 1 ELSE 0 END AS is_to_agendado,
        CASE WHEN a.description LIKE 'Status alterado de ''Agendado'' para %'   THEN 1 ELSE 0 END AS is_from_agendado
    FROM dbo.act_log a
    JOIN Chamados c ON c.persid = a.call_req_id
    WHERE a.type = 'ST'
      AND (a.description LIKE 'Status alterado de % para ''Agendado''.%'
           OR a.description LIKE 'Status alterado de ''Agendado'' para %')
),
 
-- 3) Para cada transição, acha o próximo "retorno" (Agendado -> outro status)
--    com uma window function (1 passada) em vez de um MIN() correlacionado
--    recalculado a cada linha do SELECT final.
StatusChangesWithNext AS (
    SELECT
        call_req_id,
        time_stamp,
        is_to_agendado,
        MIN(CASE WHEN is_from_agendado = 1 THEN time_stamp END)
            OVER (PARTITION BY call_req_id ORDER BY time_stamp
                  ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING) AS next_from_time
    FROM StatusChanges
),
 
Transicoes AS (
    SELECT
        s.call_req_id,
        s.time_stamp AS trans_time,
        COALESCE(s.next_from_time, c.close_date) AS interval_end,
        -- "dia local" calculado com aritmética de inteiro (epoch - 3h) / 86400,
        -- equivalente ao CAST(DATEADD(HOUR,-3,...) AS DATE) do original, mas
        -- sem converter tipo de data linha a linha.
        (s.time_stamp - 10800) / 86400 AS day_bucket
    FROM StatusChangesWithNext s
    JOIN Chamados c ON c.persid = s.call_req_id
    WHERE s.is_to_agendado = 1
),
 
-- 4) Log (justificativas) restrito aos chamados filtrados.
Logs AS (
    SELECT
        l.call_req_id,
        l.time_stamp,
        (l.time_stamp - 10800) / 86400 AS day_bucket
    FROM dbo.act_log l
    JOIN Chamados c ON c.persid = l.call_req_id
    WHERE l.type = 'LOG'
),
 
-- 5) Para cada transição p/ Agendado, calcula UMA VEZ se foi justificada
--    (dentro do intervalo OU no mesmo dia antes da transição).
TransicoesAvaliadas AS (
    SELECT
        t.call_req_id,
        t.trans_time,
        CASE WHEN EXISTS (
                SELECT 1 FROM Logs lg
                WHERE lg.call_req_id = t.call_req_id
                  AND lg.time_stamp > t.trans_time
                  AND lg.time_stamp <= t.interval_end
             )
             OR EXISTS (
                SELECT 1 FROM Logs lg
                WHERE lg.call_req_id = t.call_req_id
                  AND lg.time_stamp <= t.trans_time
                  AND lg.day_bucket = t.day_bucket
             )
             THEN 1 ELSE 0
        END AS justificado
    FROM Transicoes t
),
 
-- 6) Agrega por chamado (1 linha por call_req_id): essa é a peça que elimina
--    a duplicação — antes o mesmo NOT EXISTS aninhado era calculado 2x
--    (uma vez para a coluna "Agendamento adequado", outra para a coluna
--    "Data/Hora"). Agora as duas colunas do SELECT final só fazem LOOKUP
--    nesse resumo já pronto.
Resumo AS (
    SELECT
        call_req_id,
        MIN(justificado) AS todas_justificadas,                              -- 0 = existe alguma sem justificativa
        MIN(CASE WHEN justificado = 0 THEN trans_time END) AS primeira_sem_justificativa
    FROM TransicoesAvaliadas
    GROUP BY call_req_id
)
 
--------------------------------------------------------------------------------
-- SELECT final
--------------------------------------------------------------------------------
SELECT
    c.ref_num AS [N° chamado],
    CASE c.type WHEN 'R' THEN N'Solicitação' WHEN 'I' THEN N'Incidente' ELSE N'N/A' END AS [Tipo],
    f.last_name AS [Fornecedor],
    c.summary AS [Resumo],
    DATEADD(HOUR, -3, DATEADD(SECOND, c.close_date, '1970-01-01')) AS [Data de fechamento],
    CASE
        WHEN res.call_req_id IS NULL THEN N' - '
        WHEN res.todas_justificadas = 0 THEN N'NÃO'
        ELSE N'SIM'
    END AS [Agendamento adequado],
    CASE WHEN res.primeira_sem_justificativa IS NOT NULL THEN
        CONVERT(VARCHAR(10), DATEADD(HOUR, -3, DATEADD(SECOND, res.primeira_sem_justificativa, '1970-01-01')), 103) + ' ' +
        CONVERT(VARCHAR(8),  DATEADD(HOUR, -3, DATEADD(SECOND, res.primeira_sem_justificativa, '1970-01-01')), 108)
    END AS [Data/Hora Agendamento S/ Justificativa]
FROM Chamados c
LEFT JOIN dbo.ca_contact f ON f.contact_uuid = c.group_id
LEFT JOIN Resumo res ON res.call_req_id = c.persid
ORDER BY c.close_date DESC;
 
--------------------------------------------------------------------------------
-- ÍNDICES RECOMENDADOS (crie se ainda não existirem — confirme com o DBA):
--
-- CREATE INDEX IX_act_log_callreq_type_time
--     ON dbo.act_log (call_req_id, type, time_stamp) INCLUDE (description);
--
-- CREATE INDEX IX_call_req_group_status_close
--     ON dbo.call_req (group_id, status, close_date) INCLUDE (persid, ref_num, type, summary);
--
-- Sem o índice em act_log(call_req_id, type, ...), o ganho da reescrita cai
-- bastante, porque o JOIN com Chamados ainda provoca um scan grande na tabela.
--------------------------------------------------------------------------------