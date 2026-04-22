USE mdb;
SET NOCOUNT ON;

--------------------------------------------------------------------------------
-- [PARAMETROS]
--------------------------------------------------------------------------------
DECLARE @From datetime2(0) = '2026-01-01 03:00:00';
DECLARE @To   datetime2(0) = '2027-01-01 02:59:59';
DECLARE @FromEpoch int = DATEDIFF(SECOND, '1970-01-01', @From);
DECLARE @ToEpoch   int = DATEDIFF(SECOND, '1970-01-01', @To);

DECLARE @COI varbinary(16) = 0x3C11B3A9EBCE5D498E2F7D7FF385F967;

DECLARE @URL      nvarchar(200)  = N'https://contas.tcu.gov.br/wikiti/index.php?title=';
DECLARE @AnexoSep nvarchar(10)   = N'; ';

--------------------------------------------------------------------------------
-- [0] BASE
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#BASE') IS NOT NULL DROP TABLE #BASE;
CREATE TABLE #BASE (
    id          int            NOT NULL PRIMARY KEY,
    ref_num     nvarchar(64)   COLLATE DATABASE_DEFAULT NOT NULL,
    [type]      char(1)        COLLATE DATABASE_DEFAULT NOT NULL,
    status_code nvarchar(30)   COLLATE DATABASE_DEFAULT NOT NULL,
    close_date  int            NOT NULL,
    summary     nvarchar(4000) COLLATE DATABASE_DEFAULT NULL,
    sumNoSpace  nvarchar(4000) COLLATE Latin1_General_CI_AI NULL
);

INSERT INTO #BASE(id, ref_num, [type], status_code, close_date, summary, sumNoSpace)
SELECT
    r.id,
    r.ref_num,
    r.[type],
    st.code,
    r.close_date,
    r.summary,
    REPLACE(
      LTRIM(
        REPLACE(REPLACE(REPLACE(REPLACE(
          CONVERT(nvarchar(4000), r.summary) COLLATE Latin1_General_CI_AI,
          NCHAR(160), N' '),
          CHAR(9),  N' '),
          CHAR(10), N' '),
          CHAR(13), N' ')
      ),
      N' ', N''
    ) COLLATE Latin1_General_CI_AI
FROM dbo.call_req AS r
JOIN dbo.cr_stat  AS st ON st.code = r.status
WHERE r.group_id = @COI
  AND r.type IN ('I','R')
  AND r.close_date IS NOT NULL
  AND r.close_date >= @FromEpoch
  AND r.close_date <= @ToEpoch
  AND st.code IN ('CL','CLUNRSLV');

CREATE INDEX IX_BASE_refnum ON #BASE(ref_num);
CREATE INDEX IX_BASE_close  ON #BASE(close_date);

--------------------------------------------------------------------------------
-- [A] anexos + long_texts
--------------------------------------------------------------------------------
DECLARE @att_tbl sysname =
CASE
  WHEN OBJECT_ID('dbo.attmnt')    IS NOT NULL THEN 'dbo.attmnt'
  WHEN OBJECT_ID('dbo.kd_attmnt') IS NOT NULL THEN 'dbo.kd_attmnt'
  ELSE NULL
END;

DECLARE @has_orig  bit = CASE WHEN @att_tbl IS NOT NULL AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(@att_tbl) AND name='orig_file_name') THEN 1 ELSE 0 END;
DECLARE @has_file  bit = CASE WHEN @att_tbl IS NOT NULL AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(@att_tbl) AND name='file_name')      THEN 1 ELSE 0 END;
DECLARE @has_fname bit = CASE WHEN @att_tbl IS NOT NULL AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(@att_tbl) AND name='filename')       THEN 1 ELSE 0 END;
DECLARE @has_name  bit = CASE WHEN @att_tbl IS NOT NULL AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(@att_tbl) AND name='name')           THEN 1 ELSE 0 END;
DECLARE @has_symA  bit = CASE WHEN @att_tbl IS NOT NULL AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(@att_tbl) AND name='sym')            THEN 1 ELSE 0 END;
DECLARE @has_del   bit = CASE WHEN @att_tbl IS NOT NULL AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(@att_tbl) AND name='delete_flag')    THEN 1 ELSE 0 END;

DECLARE @nameExpr nvarchar(max) = N'';
IF @has_orig  = 1 SET @nameExpr = @nameExpr + N', NULLIF(LTRIM(RTRIM(a.orig_file_name)), '''')';
IF @has_file  = 1 SET @nameExpr = @nameExpr + N', NULLIF(LTRIM(RTRIM(a.file_name)),      '''')';
IF @has_fname = 1 SET @nameExpr = @nameExpr + N', NULLIF(LTRIM(RTRIM(a.filename)),       '''')';
IF @has_name  = 1 SET @nameExpr = @nameExpr + N', NULLIF(LTRIM(RTRIM(a.[name])),         '''')';
IF @has_symA  = 1 SET @nameExpr = @nameExpr + N', NULLIF(LTRIM(RTRIM(a.sym)),            '''')';

IF @nameExpr = N'' SET @nameExpr = N'CONVERT(nvarchar(4000), a.id)'
ELSE SET @nameExpr = N'COALESCE(' + STUFF(@nameExpr, 1, 2, N'') + N')';

DECLARE @delFilter nvarchar(200) = CASE WHEN @has_del=1 THEN N'AND ISNULL(a.delete_flag,0)=0' ELSE N'' END;

DECLARE @lt_tbl sysname = CASE WHEN OBJECT_ID('dbo.long_texts') IS NOT NULL THEN 'dbo.long_texts' ELSE NULL END;
DECLARE @lt_has_att  bit = CASE WHEN @lt_tbl IS NOT NULL AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(@lt_tbl) AND name='attmnt_id') THEN 1 ELSE 0 END;
DECLARE @lt_has_text bit = CASE WHEN @lt_tbl IS NOT NULL AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(@lt_tbl) AND name='text') THEN 1 ELSE 0 END;
DECLARE @lt_has_long bit = CASE WHEN @lt_tbl IS NOT NULL AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(@lt_tbl) AND name='long_text') THEN 1 ELSE 0 END;
DECLARE @lt_has_txt  bit = CASE WHEN @lt_tbl IS NOT NULL AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(@lt_tbl) AND name='txt') THEN 1 ELSE 0 END;
DECLARE @lt_has_val  bit = CASE WHEN @lt_tbl IS NOT NULL AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(@lt_tbl) AND name='value') THEN 1 ELSE 0 END;

DECLARE @ltxtExpr nvarchar(max) = N'NULL';
IF @lt_tbl IS NOT NULL AND @lt_has_att = 1
BEGIN
  SET @ltxtExpr = N'';
  IF @lt_has_text = 1 SET @ltxtExpr = @ltxtExpr + N', NULLIF(LTRIM(RTRIM(lt.[text])),      '''')';
  IF @lt_has_long = 1 SET @ltxtExpr = @ltxtExpr + N', NULLIF(LTRIM(RTRIM(lt.[long_text])), '''')';
  IF @lt_has_txt  = 1 SET @ltxtExpr = @ltxtExpr + N', NULLIF(LTRIM(RTRIM(lt.[txt])),       '''')';
  IF @lt_has_val  = 1 SET @ltxtExpr = @ltxtExpr + N', NULLIF(LTRIM(RTRIM(lt.[value])),     '''')';
  IF @ltxtExpr = N'' SET @ltxtExpr = N'NULL' ELSE SET @ltxtExpr = N'COALESCE(' + STUFF(@ltxtExpr,1,2,N'') + N')';
END;

--------------------------------------------------------------------------------
-- [B] #AX_URL (todas URLs validas) (sem excluir C034)
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#AX_URL') IS NOT NULL DROP TABLE #AX_URL;
CREATE TABLE #AX_URL (
  Chamado nvarchar(64)   COLLATE DATABASE_DEFAULT NOT NULL,
  Anexo   nvarchar(4000) COLLATE DATABASE_DEFAULT NOT NULL
);

IF @att_tbl IS NOT NULL AND OBJECT_ID('dbo.usp_lrel_attachments_requests') IS NOT NULL
BEGIN
  DECLARE @selectAnexo nvarchar(max) =
    N'CASE WHEN ' + @nameExpr + N' LIKE @URL + ''%'' THEN ' + @nameExpr + N' ELSE NULL END';

  DECLARE @urlPred nvarchar(max) =
    N'(' + @nameExpr + N' LIKE @URL + ''%''';

  IF @ltxtExpr <> N'NULL'
  BEGIN
    SET @selectAnexo =
      N'COALESCE(' + @selectAnexo + N', CASE WHEN ' + @ltxtExpr + N' LIKE @URL + ''%'' THEN ' + @ltxtExpr + N' ELSE NULL END)';
    SET @urlPred =
      @urlPred + N' OR (' + @ltxtExpr + N' LIKE @URL + ''%'')';
  END
  SET @urlPred = @urlPred + N')';

  DECLARE @ltJoin nvarchar(max) =
    CASE WHEN @lt_tbl IS NOT NULL AND @lt_has_att=1
         THEN N'LEFT JOIN ' + @lt_tbl + N' AS lt ON lt.attmnt_id = a.id'
         ELSE N'' END;

  DECLARE @sql nvarchar(max) = N'
    INSERT INTO #AX_URL(Chamado, Anexo)
    SELECT DISTINCT
           b.ref_num AS Chamado,
           ' + @selectAnexo + N' AS Anexo
    FROM dbo.usp_lrel_attachments_requests AS l
    CROSS APPLY (SELECT CAST(l.attmnt AS nvarchar(100)) AS att_raw,
                        CAST(l.cr     AS nvarchar(100)) AS cr_raw) R
    CROSS APPLY (SELECT
        CASE WHEN R.att_raw LIKE ''%:%''
             THEN TRY_CONVERT(int, PARSENAME(REPLACE(R.att_raw,'':'',''.''),1))
             ELSE TRY_CONVERT(int, R.att_raw) END AS att_id,
        CASE WHEN R.cr_raw  LIKE ''%:%''
             THEN TRY_CONVERT(int, PARSENAME(REPLACE(R.cr_raw, '':'',''.''),1))
             ELSE TRY_CONVERT(int, R.cr_raw)  END AS cr_id) X
    JOIN ' + @att_tbl + N' AS a   ON a.id = X.att_id
    ' + @ltJoin + N'
    JOIN #BASE AS b        ON b.id = X.cr_id
    WHERE X.att_id IS NOT NULL
      AND X.cr_id  IS NOT NULL
      ' + @delFilter + N'
      AND ' + @urlPred + N';';

  EXEC sp_executesql
    @sql,
    N'@URL nvarchar(200)',
    @URL=@URL;
END;

CREATE INDEX IX_AX_URL_Chamado ON #AX_URL(Chamado) INCLUDE (Anexo);

--------------------------------------------------------------------------------
-- [B.1] #TITLE_MAP (preserva – e —)
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#TITLE_MAP') IS NOT NULL DROP TABLE #TITLE_MAP;
CREATE TABLE #TITLE_MAP (
  Anexo      nvarchar(4000) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
  TitleHuman nvarchar(4000) COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #TITLE_MAP(Anexo, TitleHuman)
SELECT DISTINCT ax.Anexo, NULL
FROM #AX_URL ax;

UPDATE tm
SET TitleHuman = NULLIF(LTRIM(RTRIM(s13.x)), N'')
FROM #TITLE_MAP tm
CROSS APPLY (SELECT x = REPLACE(tm.Anexo, @URL, N'')) s0
CROSS APPLY (SELECT x = REPLACE(REPLACE(REPLACE(s0.x, N'+', N' '), N'_', N' '), N'%20', N' ')) s1
CROSS APPLY (SELECT x = REPLACE(s1.x,  N'%2D', N'-')) s1h
CROSS APPLY (SELECT x = REPLACE(s1h.x, N'%27', N'''')) s1i
CROSS APPLY (SELECT x = REPLACE(s1i.x, N'%E2%80%93', N'–')) s1j
CROSS APPLY (SELECT x = REPLACE(s1j.x, N'%E2%80%94', N'—')) s1k
CROSS APPLY (SELECT x = REPLACE(REPLACE(s1k.x, N'%E2%80%9C', N'"'), N'%E2%80%9D', N'"')) s1l
CROSS APPLY (SELECT x = REPLACE(REPLACE(s1l.x, N'%E2%80%98', N''''), N'%E2%80%99', N'''')) s1m

CROSS APPLY (SELECT x = REPLACE(REPLACE(REPLACE(REPLACE(s1m.x, N'%C3%A1', N'á'), N'%C3%A0', N'à'), N'%C3%A2', N'â'), N'%C3%A3', N'ã')) s2
CROSS APPLY (SELECT x = REPLACE(REPLACE(REPLACE(REPLACE(s2.x,  N'%C3%81', N'Á'), N'%C3%80', N'À'), N'%C3%82', N'Â'), N'%C3%83', N'Ã')) s3
CROSS APPLY (SELECT x = REPLACE(REPLACE(REPLACE(s3.x,  N'%C3%A9', N'é'), N'%C3%AA', N'ê'), N'%C3%A8', N'è')) s4
CROSS APPLY (SELECT x = REPLACE(REPLACE(REPLACE(s4.x,  N'%C3%89', N'É'), N'%C3%8A', N'Ê'), N'%C3%88', N'È')) s5
CROSS APPLY (SELECT x = REPLACE(REPLACE(REPLACE(REPLACE(s5.x, N'%C3%AD', N'í'), N'%C3%AC', N'ì'), N'%C3%8D', N'Í'), N'%C3%8C', N'Ì')) s6

CROSS APPLY (SELECT x = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(s6.x,
    N'%C3%B3', N'ó'), N'%C3%B4', N'ô'), N'%C3%B5', N'õ'), N'%C3%B2', N'ò'),
    N'%C3%93', N'Ó'), N'%C3%94', N'Ô'), N'%C3%95', N'Õ'), N'%C3%92', N'Ò')) s7

CROSS APPLY (SELECT x = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(s7.x,
    N'%C3%BA', N'ú'), N'%C3%B9', N'ù'), N'%C3%9A', N'Ú'), N'%C3%99', N'Ù'),
    N'%C3%A7', N'ç'), N'%C3%87', N'Ç')) s8

CROSS APPLY (SELECT x = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(s8.x,
    N'%28', N'('), N'%29', N')'), N'%2C', N','), N'%2F', N'/'), N'%3A', N':'), N'%3B', N';')) s9
CROSS APPLY (SELECT pHash = NULLIF(CHARINDEX(N'#', s9.x), 0),
                    pTxt  = NULLIF(CHARINDEX(N':~:text=', s9.x), 0)) p
CROSS APPLY (SELECT pCut =
    CASE
      WHEN p.pHash IS NULL THEN p.pTxt
      WHEN p.pTxt  IS NULL THEN p.pHash
      WHEN p.pHash < p.pTxt THEN p.pHash ELSE p.pTxt
    END
) cut
CROSS APPLY (SELECT x = CASE WHEN cut.pCut IS NOT NULL THEN LEFT(s9.x, cut.pCut - 1) ELSE s9.x END) s10
CROSS APPLY (SELECT x = REPLACE(REPLACE(REPLACE(s10.x, N'  ', N' '), N'  ', N' '), N'  ', N' ')) s13;

CREATE INDEX IX_TITLE_MAP_Anexo ON #TITLE_MAP(Anexo) INCLUDE (TitleHuman);

--------------------------------------------------------------------------------
-- [B.2] #ANEXO_ITEM + #ANEXO_AGG
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#ANEXO_ITEM') IS NOT NULL DROP TABLE #ANEXO_ITEM;
SELECT DISTINCT
  ax.Chamado,
  Item = COALESCE(tm.TitleHuman, REPLACE(ax.Anexo, @URL, N''))
INTO #ANEXO_ITEM
FROM #AX_URL ax
LEFT JOIN #TITLE_MAP tm
  ON tm.Anexo = ax.Anexo;

CREATE INDEX IX_ANEXO_ITEM_Chamado ON #ANEXO_ITEM(Chamado) INCLUDE (Item);

IF OBJECT_ID('tempdb..#ANEXO_AGG') IS NOT NULL DROP TABLE #ANEXO_AGG;
CREATE TABLE #ANEXO_AGG (
  Chamado nvarchar(64) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
  Anexo   nvarchar(max) COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #ANEXO_AGG(Chamado, Anexo)
SELECT
  c.Chamado,
  NULLIF(
    STUFF((
      SELECT @AnexoSep + ai2.Item
      FROM #ANEXO_ITEM ai2
      WHERE ai2.Chamado COLLATE DATABASE_DEFAULT = c.Chamado COLLATE DATABASE_DEFAULT
      ORDER BY ai2.Item
      FOR XML PATH(''), TYPE
    ).value('.', 'nvarchar(max)'), 1, LEN(@AnexoSep), N'')
  , N'')
FROM (SELECT DISTINCT Chamado FROM #ANEXO_ITEM) c;

--------------------------------------------------------------------------------
-- [C] POP extraido dos anexos
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#POP_EXTRACT') IS NOT NULL DROP TABLE #POP_EXTRACT;
CREATE TABLE #POP_EXTRACT (
  Chamado nvarchar(64) COLLATE DATABASE_DEFAULT NOT NULL,
  POPcode nvarchar(10) COLLATE DATABASE_DEFAULT NOT NULL,
  PRIMARY KEY (Chamado, POPcode)
);

INSERT INTO #POP_EXTRACT(Chamado, POPcode)
SELECT DISTINCT
  ax.Chamado,
  UPPER(p.POPcode)
FROM #AX_URL ax
CROSS APPLY (
  SELECT POPcode =
    CASE
      WHEN PATINDEX('%[A-Za-z][A-Za-z][0-9][0-9][0-9]%', ax.Anexo) > 0
        THEN SUBSTRING(ax.Anexo, PATINDEX('%[A-Za-z][A-Za-z][0-9][0-9][0-9]%', ax.Anexo), 5)
      WHEN PATINDEX('%[A-Za-z][0-9][0-9][0-9]%', ax.Anexo) > 0
        THEN SUBSTRING(ax.Anexo, PATINDEX('%[A-Za-z][0-9][0-9][0-9]%', ax.Anexo), 4)
      ELSE NULL
    END
) p
WHERE p.POPcode IS NOT NULL;

CREATE INDEX IX_POP_EXTRACT_Chamado ON #POP_EXTRACT(Chamado) INCLUDE (POPcode);

--------------------------------------------------------------------------------
-- [D] LISTA + SINONIMOS + #PATTERNS (COI)
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#POP_LIST') IS NOT NULL DROP TABLE #POP_LIST;
CREATE TABLE #POP_LIST (
  ResumoFull   nvarchar(4000) COLLATE DATABASE_DEFAULT,
  POPEsperado  nvarchar(20)   COLLATE DATABASE_DEFAULT
);

INSERT INTO #POP_LIST(ResumoFull, POPEsperado) VALUES
(N'A2B - Teste de Restore VM', 'C202'),
(N'Alterar Nomenclatura', 'C118'),
(N'BI-ANALYTICS', 'C108'),
(N'Backup - Análise de Vulnerabilidades', 'D090'),
(N'Backup - Job Summary report', 'D083'),
(N'Backup - Manutenção no banco de dados SQL do Commvault com DBmaintenance', 'D140'),
(N'Backup - Realizar limpeza de ciclos presos em Storage Policy', 'D158'),
(N'Backup - Revisão das Disk Libraries', 'D137'),
(N'Backup - Rotina Diária - Gerar relatório de jobs suspensos e killed', 'D147'),
(N'Backup - Rotina Mensal - Efetuar a verificação de todas as mídias Appendable', 'D129'),
(N'Backup - Rotina Semanal- Gerar relatório de modificações semanais', 'D151'),
(N'Backup - Storage Information Report - Media Information report', 'D063'),
(N'Backup Commvault - Cofreamento diário, ciclo de backup', 'C031'),
(N'Biometria', 'C144'),
(N'Blackout', 'C078'),
(N'Casa - Recolhimento de Itens Armazenados', 'C235'),
(N'COI - Crise (Sala Técnica)', 'C212'),
(N'COI - Rotina Mensal - Alteração de senhas de contas utilizadas nos telões do SIDAT', 'C201'),
(N'COI - Rotina Mensal - Envio de Chamados "Em Teste na TI", "Em Homologação pelo fiscal" e "Backlog Aberto"', 'C134'),
(N'COI - Rotina Semanal - Envio de relatórios de chamados ativos de fornecedores que não utilizam o SDM', 'C227'),
(N'COI - Rotina Semanal - Relatório Semanal de IC''s criados', 'C147'),
(N'COI - Rotina Semanal - Inspeção no Datacenter e DCIM', 'C204'),
(N'COI - Rotina Semanal - Relatório de Chamados do Tipo Problema', 'C213'),
(N'COI- Rotina Semanal - Inspeção no Datacenter e DCIM', 'C204'),
(N'Comissionamento', 'C238'),
(N'Comissionamento Lógico de Host', 'C094'),
(N'Credenciamento', 'C144'),
(N'Descomissionamento', 'C239'),
(N'Descomissionar Máquina Virtual (VM)', 'C239'),
(N'Descredenciamento', 'C159'),
(N'Embratel', 'C004'),
(N'Embratel', 'C017'),
(N'Fitas', 'C150'),
(N'G4S', 'C061'),
(N'G4S - Relogio', 'C061'),
(N'Inativar Item de Configuração', 'C065'),
(N'Inserir Mídias', 'C043'),
(N'LCS', 'C149'),
(N'LCS - Checklist Diário - Validação das principais funcionalidades do DCIM', 'TC011'),
(N'LCS - Rotina Semanal - Inspeção no Datacenter e DCIM', 'C219'),
(N'LCS - Rotinas Semanal - Envio consolidado de relatório de Health check do DCIM para o TCU', 'TC011'),
(N'lista de acesso permanente de acesso junto a SEGUR', 'C159'),
(N'Passagem de turno', 'C021'),
(N'Prazo de aquisição de certificação', 'C144'),
(N'Recebimento de Material no SIDAT', 'C221'),
(N'Recolher crachá', 'C159'),
(N'Remover Mídias', 'C043'),
(N'Rotina Anual - Envio da Planilha de colaboradores para os fiscais', 'C232'),
(N'Rotina Mensal – Conferência da fila do SDM “Setic/Diamb/Sidat - Infraestrutura de Operação e CPD', 'C241'),
(N'Rotina Mensal – Conferência da fila do SDM “Setid/Diamb/Sidat - Infraestrutura de Operação e CPD”', 'C241'),
(N'Rotinal Semanal COI - Checklist de Saúde do Desktop Virtual', 'C125'),
(N'Substituição de VM', 'C167'),
(N'Supressão de alerta', 'C236'),
(N'Task', 'C108'),
(N'Type: Job Management', 'C230'),
(N'Utilização de CPU', 'D101'),
(N'Utilização do Disco', 'D177'),
(N'Vistoria no Ambiente do SIDAT', 'C023');

DECLARE @Sinonimos TABLE (Canon nvarchar(4000) NOT NULL, Variante nvarchar(4000) NOT NULL);
INSERT INTO @Sinonimos(Canon, Variante) VALUES (N'Inserir Mídias',     N'Inserir Mídia');
INSERT INTO @Sinonimos(Canon, Variante) VALUES (N'Inserir Mídias',     N'Inserir de Mídia');
INSERT INTO @Sinonimos(Canon, Variante) VALUES (N'Comissionamento',    N'Comissionar');
INSERT INTO @Sinonimos(Canon, Variante) VALUES (N'Descomissionamento', N'Descomissionar');

IF OBJECT_ID('tempdb..#PATTERNS') IS NOT NULL DROP TABLE #PATTERNS;
SELECT DISTINCT
  POPEsperado = x.POPEsperado,
  TextNoSpace = x.TextNoSpace COLLATE Latin1_General_CI_AI
INTO #PATTERNS
FROM (
  SELECT pl.POPEsperado, REPLACE(pl.ResumoFull,  N' ', N'') AS TextNoSpace FROM #POP_LIST pl
  UNION ALL
  SELECT pl.POPEsperado, REPLACE(pl.POPEsperado, N' ', N'') AS TextNoSpace FROM #POP_LIST pl
  UNION ALL
  SELECT plc.POPEsperado, REPLACE(s.Variante,    N' ', N'') AS TextNoSpace
  FROM @Sinonimos s
  JOIN #POP_LIST plc ON plc.ResumoFull = s.Canon
) x;

CREATE INDEX IX_PATTERNS_Text ON #PATTERNS(TextNoSpace) INCLUDE (POPEsperado);

--------------------------------------------------------------------------------
-- [E] POP esperado (CLUNRSLV nao entra no calculo porque no COI é fixo C054)
--     BLINDAGEM NUMERICA: se o padrão termina em dígito, o próximo caractere
--     não pode ser outro dígito (evita 2 casar com 200 etc.)
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#POP_EXPECT') IS NOT NULL DROP TABLE #POP_EXPECT;
CREATE TABLE #POP_EXPECT (
  Chamado nvarchar(64) COLLATE DATABASE_DEFAULT NOT NULL,
  POPcode nvarchar(20) COLLATE DATABASE_DEFAULT NOT NULL,
  PRIMARY KEY (Chamado, POPcode)
);

INSERT INTO #POP_EXPECT(Chamado, POPcode)
SELECT DISTINCT
  b.ref_num,
  p.POPEsperado
FROM #BASE b
JOIN #PATTERNS p
  ON b.status_code <> N'CLUNRSLV'
CROSS APPLY (SELECT pos = CHARINDEX(p.TextNoSpace, ISNULL(b.sumNoSpace, N''))) m
WHERE m.pos > 0
  AND (
        RIGHT(p.TextNoSpace, 1) NOT LIKE N'[0-9]'
        OR SUBSTRING(ISNULL(b.sumNoSpace, N''), m.pos + LEN(p.TextNoSpace), 1) NOT LIKE N'[0-9]'
      )
  AND NOT (
      EXISTS (SELECT 1 FROM #PATTERNS dp WHERE dp.TextNoSpace = N'Des' + p.TextNoSpace)
      AND CHARINDEX(N'Des' + p.TextNoSpace, ISNULL(b.sumNoSpace, N'')) > 0
  );

CREATE INDEX IX_POP_EXPECT_Chamado ON #POP_EXPECT(Chamado) INCLUDE (POPcode);

IF OBJECT_ID('tempdb..#POPLIST_AGG') IS NOT NULL DROP TABLE #POPLIST_AGG;
CREATE TABLE #POPLIST_AGG (
  Chamado nvarchar(64) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
  POPEsperadoNaLista nvarchar(max) COLLATE DATABASE_DEFAULT NULL
);

INSERT INTO #POPLIST_AGG(Chamado, POPEsperadoNaLista)
SELECT
  c.Chamado,
  NULLIF(
    STUFF((
      SELECT N'/' + e2.POPcode
      FROM #POP_EXPECT e2
      WHERE e2.Chamado COLLATE DATABASE_DEFAULT = c.Chamado COLLATE DATABASE_DEFAULT
      ORDER BY e2.POPcode
      FOR XML PATH(''), TYPE
    ).value('.', 'nvarchar(max)'), 1, 1, N'')
  , N'')
FROM (SELECT DISTINCT Chamado FROM #POP_EXPECT) c;

--------------------------------------------------------------------------------
-- [F] SAIDA FINAL (COI)
--     - CLUNRSLV => POPEsperadoNaLista = 'C054'
--     - REGRA: Anexo='--' => POPConfere='NÃO'
--     - CLUNRSLV com anexo => valida C054 (SIM/NÃO)
--------------------------------------------------------------------------------
SELECT
  b.ref_num AS Chamado,
  b.summary AS Resumo,
  COALESCE(a.Anexo, N'--') AS Anexo,

  CASE b.status_code
    WHEN 'CL'       THEN N'Resolvido, concluído'
    WHEN 'CLUNRSLV' THEN N'Não resolvido, fechado'
    ELSE b.status_code
  END AS [Status],

  CASE
    WHEN b.status_code = 'CLUNRSLV' THEN N'C054'
    ELSE COALESCE(pl.POPEsperadoNaLista, N'--')
  END AS POPEsperadoNaLista,

  CASE
    WHEN COALESCE(a.Anexo, N'--') = N'--' THEN N'NÃO'

    WHEN b.status_code = 'CLUNRSLV' THEN
      CASE
        WHEN EXISTS (SELECT 1 FROM #POP_EXTRACT pe WHERE pe.Chamado = b.ref_num AND pe.POPcode = N'C054')
          THEN N'SIM'
        ELSE N'NÃO'
      END

    WHEN EXISTS (SELECT 1 FROM #POP_EXPECT ex WHERE ex.Chamado = b.ref_num)
     AND EXISTS (SELECT 1 FROM #POP_EXTRACT pe WHERE pe.Chamado = b.ref_num)
     AND NOT EXISTS (
        SELECT 1
        FROM #POP_EXPECT ex
        WHERE ex.Chamado = b.ref_num
          AND NOT EXISTS (
            SELECT 1
            FROM #POP_EXTRACT pe
            WHERE pe.Chamado = b.ref_num
              AND pe.POPcode = ex.POPcode
          )
     )
      THEN N'SIM'

    WHEN EXISTS (SELECT 1 FROM #POP_EXPECT ex WHERE ex.Chamado = b.ref_num)
     AND EXISTS (SELECT 1 FROM #POP_EXTRACT pe WHERE pe.Chamado = b.ref_num)
      THEN N'NÃO'

    ELSE N'N/A'
  END AS POPConfere

FROM #BASE b
LEFT JOIN #ANEXO_AGG   a  ON a.Chamado COLLATE DATABASE_DEFAULT = b.ref_num COLLATE DATABASE_DEFAULT
LEFT JOIN #POPLIST_AGG pl ON pl.Chamado COLLATE DATABASE_DEFAULT = b.ref_num COLLATE DATABASE_DEFAULT
ORDER BY
  CASE WHEN b.type = 'I' THEN 0 ELSE 1 END,
  b.close_date DESC,
  COALESCE(a.Anexo, N'--')
OPTION (RECOMPILE);
