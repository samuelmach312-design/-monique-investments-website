WITH RECURSIVE fp (path, parent, id, parent_id, title) AS (
    SELECT
        title, NULL, id, parent_id, title FROM pem.cm_template_path
    WHERE parent_id IS NULL
    UNION
    SELECT
        fp.path || '/' || pem.cm_template_path.title, fp.path,
        pem.cm_template_path.id, pem.cm_template_path.parent_id,
        pem.cm_template_path.title
    FROM
        pem.cm_template_path, fp
    WHERE pem.cm_template_path.parent_id = fp.id
)
SELECT
    fp.id, fp.parent_id, fp.title,
    pem.cm_template.name AS template_name,
    pem.cm_template.id AS template_id
FROM fp
LEFT OUTER JOIN pem.cm_template
    ON (pem.cm_template.folder_id = fp.id)
ORDER BY fp.path, pem.cm_template.id;
