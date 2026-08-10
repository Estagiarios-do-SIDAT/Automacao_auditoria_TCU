USE mdb;

--------------------------------------------------------------------------------
-- [PARÂMETROS DE PERÍODO E FORNECEDOR]
--------------------------------------------------------------------------------
DECLARE @From datetime2(0) = '2026-08-09 03:00:00';
DECLARE @To   datetime2(0) = '2026-08-10 02:59:59';
DECLARE @FromEpoch int = DATEDIFF(SECOND, '1970-01-01', @From);
DECLARE @ToEpoch   int = DATEDIFF(SECOND, '1970-01-01', @To);

DECLARE @COI varbinary(16) = 0x3C11B3A9EBCE5D498E2F7D7FF385F967;

--------------------------------------------------------------------------------
-- [CONSULTA - SOMENTE LEITURA]
--------------------------------------------------------------------------------
SELECT 
    r.ref_num          AS [Número do Chamado],
    r.summary          AS [Resumo],
    st.sym             AS [Status],
    ci.resource_name   AS [Item de Configuração]
FROM 
    dbo.call_req AS r
LEFT JOIN 
    dbo.cr_stat AS st ON st.code = r.status
LEFT JOIN 
    dbo.ca_owned_resource AS ci ON ci.own_resource_uuid = r.affected_rc
WHERE 
    r.group_id = @COI
    AND r.close_date IS NOT NULL
    AND r.close_date >= @FromEpoch
    AND r.close_date <= @ToEpoch;