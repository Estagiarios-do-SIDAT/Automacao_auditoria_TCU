USE mdb;
SET NOCOUNT ON;

-- Janela (UTC equivalente ao ano cheio em -03:00)
DECLARE @From      datetime2(0) = '2026-01-01 03:00:00';
DECLARE @To        datetime2(0) = '2027-01-01 02:59:59';
DECLARE @FromEpoch int = DATEDIFF(SECOND, '1970-01-01', @From);
DECLARE @ToEpoch   int = DATEDIFF(SECOND, '1970-01-01', @To);

-- Grupo COI
DECLARE @COI varbinary(16) = 0x3C11B3A9EBCE5D498E2F7D7FF385F967;

SELECT
    r.ref_num AS Chamado,
    r.summary AS Resumo,
    i.Nome AS Interessado,
    o.Nome AS Responsavel,
    CASE
      WHEN i.Nome COLLATE Latin1_General_CI_AI
         = o.Nome COLLATE Latin1_General_CI_AI
      THEN N'NÃO' ELSE N'SIM'
    END AS InteressadoDiferenteDoResponsavel
FROM dbo.call_req AS r
JOIN dbo.cr_stat  AS st  ON st.code = r.status
LEFT JOIN dbo.ca_contact AS req ON req.contact_uuid = r.customer
LEFT JOIN dbo.ca_contact AS own ON own.contact_uuid = r.assignee
CROSS APPLY (
  SELECT LTRIM(RTRIM(
    CASE
      WHEN (ISNULL(req.first_name,'') <> '' OR ISNULL(req.last_name,'') <> '')
        THEN CONCAT(ISNULL(req.first_name,''), ' ', ISNULL(req.last_name,''))
      WHEN ISNULL(req.userid,'') <> '' THEN req.userid
      ELSE N'N/A'
    END
  )) AS Nome
) AS i
CROSS APPLY (
  SELECT LTRIM(RTRIM(
    CASE
      WHEN (ISNULL(own.first_name,'') <> '' OR ISNULL(own.last_name,'') <> '')
        THEN CONCAT(ISNULL(own.first_name,''), ' ', ISNULL(own.last_name,''))
      WHEN ISNULL(own.userid,'') <> '' THEN own.userid
      ELSE N'N/A'
    END
  )) AS Nome
) AS o
WHERE r.group_id = @COI
  AND r.type IN ('I','R')
  AND r.close_date IS NOT NULL
  AND r.close_date BETWEEN @FromEpoch AND @ToEpoch
  AND st.code IN ('CL','CLUNRSLV')
ORDER BY r.close_date DESC;
