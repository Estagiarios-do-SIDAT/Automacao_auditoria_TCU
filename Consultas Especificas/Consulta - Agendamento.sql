USE mdb;
SET NOCOUNT ON;

--------------------------------------------------------------------------------
-- 1. ESTRUTURA ÚNICA (Sem multiplos JOINS, sem risco de erro de coluna)
--------------------------------------------------------------------------------
DECLARE @DataInicial VARCHAR(10) = '01/04/2026';
DECLARE @DataFinal   VARCHAR(10) = '30/04/2026';
DECLARE @Fornecedor VARBINARY(16) = 0xCE4FDD26D5053545BF4A11332BB07485;

DECLARE @From datetime2(0) = DATEADD(HOUR, 3, CONVERT(datetime2(0), @DataInicial + ' 00:00:00', 103));
DECLARE @To   datetime2(0) = DATEADD(HOUR, 3, CONVERT(datetime2(0), @DataFinal   + ' 23:59:59', 103));
DECLARE @FromEpoch int = DATEDIFF(SECOND, '1970-01-01', @From);
DECLARE @ToEpoch   int = DATEDIFF(SECOND, '1970-01-01', @To);

SELECT 
    r.ref_num AS [N° chamado],
    CASE r.type WHEN 'R' THEN N'Solicitação' WHEN 'I' THEN N'Incidente' ELSE N'N/A' END AS [Tipo],
    f.last_name AS [Fornecedor],
    r.summary AS [Resumo],
    DATEADD(HOUR, -3, DATEADD(SECOND, r.close_date, '1970-01-01')) AS [Data de fechamento],
    
    -- Lógica de Agendamento adequado
    CASE 
        WHEN NOT EXISTS (SELECT 1 FROM dbo.act_log st WHERE st.call_req_id = r.persid AND st.type = 'ST' AND st.description LIKE 'Status alterado de % para ''Agendado''.%') THEN N' - '
        WHEN EXISTS (
            SELECT 1 FROM dbo.act_log st 
            WHERE st.call_req_id = r.persid 
              AND st.type = 'ST' 
              AND st.description LIKE 'Status alterado de % para ''Agendado''.%'
              AND NOT EXISTS (
                  SELECT 1 FROM dbo.act_log l 
                  WHERE l.call_req_id = st.call_req_id 
                    AND l.type = 'LOG'
                    AND CAST(DATEADD(HOUR, -3, DATEADD(SECOND, l.time_stamp, '1970-01-01')) AS DATE) = 
                        CAST(DATEADD(HOUR, -3, DATEADD(SECOND, st.time_stamp, '1970-01-01')) AS DATE)
              )
        ) THEN N'NÃO'
        ELSE N'SIM'
    END AS [Agendamento adequado],

    -- Data/Hora do erro (Busca o primeiro ST sem log no mesmo dia)
    (SELECT TOP 1 
        CONVERT(VARCHAR(10), DATEADD(HOUR, -3, DATEADD(SECOND, st.time_stamp, '1970-01-01')), 103) + ' ' +
        CONVERT(VARCHAR(8), DATEADD(HOUR, -3, DATEADD(SECOND, st.time_stamp, '1970-01-01')), 108)
     FROM dbo.act_log st
     WHERE st.call_req_id = r.persid
       AND st.type = 'ST'
       AND st.description LIKE 'Status alterado de % para ''Agendado''.%'
       AND NOT EXISTS (
           SELECT 1 FROM dbo.act_log l 
           WHERE l.call_req_id = st.call_req_id 
             AND l.type = 'LOG'
             AND CAST(DATEADD(HOUR, -3, DATEADD(SECOND, l.time_stamp, '1970-01-01')) AS DATE) = 
                 CAST(DATEADD(HOUR, -3, DATEADD(SECOND, st.time_stamp, '1970-01-01')) AS DATE)
       )
    ) AS [Data/Hora Agendamento S/ Justificativa]

FROM dbo.call_req r
LEFT JOIN dbo.ca_contact f ON f.contact_uuid = r.group_id
WHERE r.group_id = @Fornecedor
  AND r.type IN ('I', 'R')
  AND r.close_date BETWEEN @FromEpoch AND @ToEpoch
  AND r.status IN ('CL', 'CLUNRSLV')
ORDER BY r.close_date DESC;