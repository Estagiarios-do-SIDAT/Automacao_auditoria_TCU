USE mdb;
SET NOCOUNT ON;

-- Janela (UTC equivalente ao mês cheio em -03:00)
DECLARE @From  datetime2(0) = '2025-11-01 03:00:00';
DECLARE @To    datetime2(0) = '2025-12-01 02:59:59';
DECLARE @FromEpoch int = DATEDIFF(SECOND, '1970-01-01', @From);
DECLARE @ToEpoch   int = DATEDIFF(SECOND, '1970-01-01', @To);

-- Grupo A2B (ID BINÁRIO CORRETO DO A2B)
DECLARE @A2B varbinary(16) = 0xCE4FDD26D5053545BF4A11332BB07485;

;WITH Pais AS (
    SELECT
        r.persid,
        r.ref_num,
        r.summary,
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
Filhos AS (
    SELECT
        f.parent     AS parent_persid,
        f.close_date AS filho_close
    FROM dbo.call_req AS f
    JOIN dbo.cr_stat  AS sf ON sf.code = f.status
    JOIN Pais         AS p  ON p.persid = f.parent
    WHERE f.close_date IS NOT NULL
      AND sf.code IN ('CL','CLUNRSLV')
)
SELECT
    p.ref_num AS Chamado,
    p.summary AS Resumo,
    DATEADD(SECOND, p.close_date, '1970-01-01') AS DataFechamento,
    CASE
        WHEN NOT EXISTS (SELECT 1 FROM Filhos f WHERE f.parent_persid = p.persid) THEN N'-'
        WHEN EXISTS (SELECT 1 FROM Filhos f WHERE f.parent_persid = p.persid AND f.filho_close > p.close_date) THEN N'NÃO'
        ELSE N'SIM'
    END AS FilhoAntesDoPai
FROM Pais p
ORDER BY DataFechamento DESC;
