USE mdb;
SET NOCOUNT ON;

SELECT
    c.last_name                              AS nome_grupo,
    c.userid,
    c.inactive,
    c.contact_type,
    c.last_update_date,
    CONVERT(varchar(34), c.contact_uuid, 1) AS codigo_hex,
    c.contact_uuid,
    COUNT(gm.member)                        AS qtd_membros
FROM ca_contact c
INNER JOIN grpmem gm
    ON gm.group_id = c.contact_uuid
WHERE c.inactive = 0
GROUP BY
    c.last_name,
    c.userid,
    c.inactive,
    c.contact_type,
    c.last_update_date,
    c.contact_uuid
ORDER BY
    c.last_name;