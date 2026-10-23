-- Lo que hace falta de una entrega para decidir A QUIÉN y CÓMO avisarle a PEDIDO
-- (`alcance.AvisoDeLaEntrega`). Las consultas de paradas no traen `folio` ni `factura_numero`.
-- Sin alcance, como el buzón: lo llama quien ya tiene los ids dentro de su alcance, o el espejo.

-- name: EntregasParaAvisar :many
SELECT id, source, external_id, folio, factura_numero
FROM orders
WHERE id = ANY(sqlc.arg('ids')::uuid[]);
