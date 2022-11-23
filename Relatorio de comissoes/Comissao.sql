WITH sub AS (
-- Venda de Produtos por Categoria por Atendente
WITH RECURSIVE niveis(id_categoria_item, id_categoria_item_pai) AS (
	SELECT	id_categoria_item,
		id_categoria_item_pai,
		1 AS nivel
	FROM	categoria_item
	WHERE	id_categoria_item = 399
	UNION ALL
	SELECT	ci.id_categoria_item,
		ci.id_categoria_item_pai,
		nv.nivel +1
	FROM	categoria_item AS ci
		INNER JOIN niveis AS nv ON (nv.id_categoria_item = ci.id_categoria_item_pai))
SELECT se.nome AS nome_empresa,
 ci.denominacao AS categoria_produto,
 i.id_item,
 i.codigo AS cod_produto,
 i.denominacao AS denominacao_produto,
 um.sigla AS unidade,
 pe.nome AS atendente,
 pe.id_pessoa,
 mvt.data_movimento,
 (CASE WHEN rr.id_chave_registro_a = ivc.id_item_venda_cf THEN ROUND(0, 3)
   ELSE ROUND(SUM((ivc.total_bruto - (ivc.desconto + ivc.desconto_automatico + ivc.desconto_rateado + ivc.desconto_ajuste_rateado + ivc.desconto_automatico_rateado + ivc.desconto_fidelidade_rateado) +
   (ivc.acrescimo + ivc.acrescimo_automatico + ivc.acrescimo_rateado + ivc.acrescimo_ajuste_rateado + ivc.acrescimo_automatico_rateado)) / ivc.quantidade), 3) END) AS preco_unit,
 CASE WHEN rr.id_chave_registro_a = ivc.id_item_venda_cf THEN SUM(ivc.quantidade - infe.quantidade)  ELSE SUM(ivc.quantidade) END AS quantidade,
 CASE WHEN rr.id_chave_registro_a = ivc.id_item_venda_cf THEN SUM(ivc.total_bruto - infe.total_produto) ELSE SUM(ivc.total_bruto) END AS total_bruto,
 CASE WHEN rr.id_chave_registro_a = ivc.id_item_venda_cf THEN ROUND(0, 2) ELSE SUM(ivc.desconto + ivc.desconto_automatico + ivc.desconto_rateado + ivc.desconto_ajuste_rateado + ivc.desconto_automatico_rateado + ivc.desconto_fidelidade_rateado) END AS desconto,
 CASE WHEN rr.id_chave_registro_a = ivc.id_item_venda_cf THEN ROUND(0, 2) ELSE SUM(ivc.acrescimo + ivc.acrescimo_automatico + ivc.acrescimo_rateado + ivc.acrescimo_ajuste_rateado + ivc.acrescimo_automatico_rateado) END AS acrescimo,
 CASE WHEN rr.id_chave_registro_a = ivc.id_item_venda_cf THEN ROUND(0, 2) ELSE SUM(me.valor) END AS custo
FROM movimento_venda_terminal AS mvt
 INNER JOIN venda_cf AS vc ON (vc.id_movimento_venda_terminal = mvt.id_movimento_venda_terminal)
 INNER JOIN item_venda_cf AS ivc ON (ivc.id_venda_cf = vc.id_venda_cf)
 LEFT OUTER JOIN movimento_estoque AS me ON (me.id_movimento_estoque = ivc.id_movimento_estoque)
 INNER JOIN item AS i ON (ivc.id_item = i.id_item)
 INNER JOIN categoria_item AS ci ON (i.id_categoria_item = ci.id_categoria_item)
 INNER JOIN unidade_medida AS um ON (i.id_unidade_medida = um.id_unidade_medida)
 INNER JOIN sis_empresa AS se ON (se.id_empresa = mvt.id_empresa)
 INNER JOIN pessoa AS pe ON (pe.id_pessoa = ivc.id_atendente)
 LEFT OUTER JOIN sis_referencia_registro AS rr ON (rr.id_chave_registro_a = ivc.id_item_venda_cf AND rr.tipo_referencia = 'ref_0830_0415_item_nota_fiscal_devolucao')
 LEFT OUTER JOIN item_nfe AS infe ON (infe.id_item_nfe = rr.id_chave_registro_b AND rr.tipo_referencia = 'ref_0830_0415_item_nota_fiscal_devolucao')
WHERE mvt.id_empresa = :IdEmpresa
AND     mvt.data_movimento BETWEEN :DataInicial AND :DataFinal
AND DATE(vc.data_cupom) BETWEEN :DataInicial AND :DataFinal
AND DATE(ivc.data_venda) BETWEEN :DataInicial AND :DataFinal
AND	ci.id_categoria_item IN (SELECT id_categoria_item FROM niveis)
AND (ivc.cancelado = 'N' AND vc.cancelada = 'N')
AND i.id_item IN (:IdCombustivelMult)
GROUP BY se.nome,
 ci.denominacao,
 i.codigo,
 i.id_item,
 i.denominacao,
 vc.id_venda_cf,
 um.sigla,
 mvt.data_movimento,
 pe.nome,
 pe.id_pessoa,
 rr.id_chave_registro_a,
 ivc.id_item_venda_cf 
ORDER BY se.nome,
 pe.nome,
 ci.denominacao,
 i.denominacao),
 
 totais AS (
   SELECT atendente,
   EXTRACT(DAY FROM data_movimento) AS dia,
   nome_empresa,
   SUM(CASE WHEN (quantidade >= :QuantidadeLitro) THEN 1 ELSE 0 END) AS contador,
   SUM(CASE WHEN (id_item = 12577) THEN quantidade ELSE 0 END) AS total_gca,
   SUM(CASE WHEN (id_item = 12578) THEN quantidade ELSE 0 END) AS total_gc,
   SUM(CASE WHEN (id_item = 12576) THEN quantidade ELSE 0 END) AS total_et,
   SUM(quantidade) AS total_geral
   FROM sub 
   GROUP BY 1,2,3
 ),
 
 comissao AS ( 
   SELECT atendente, nome_empresa, dia, comissao_carro, comissao_comb, comissao_geral, contador FROM ( 
     SELECT 
     atendente,
     nome_empresa,
     dia,
     contador,
     CASE WHEN (contador >= :QuantidadeCarro) THEN :ValorPremiacao ELSE 0 END AS comissao_carro,
     CASE WHEN (total_gca >= :VolumeCombustivel) THEN :ValorPremiacao
     WHEN (total_gc >= :VolumeCombustivel) THEN :ValorPremiacao
     WHEN (total_et >= :VolumeCombustivel) THEN :ValorPremiacao ELSE 0 END AS comissao_comb,
     CASE WHEN (total_geral >= :VolumeTotal) THEN :ValorPremiacao ELSE 0 END AS comissao_geral
     FROM totais
     GROUP BY 1,2,3,4,5,6,7
     ORDER BY 1,2
   ) AS x
   GROUP BY 1,2,3,4,5,6,7
   ORDER BY 1,3
 )

 select atendente,
REPLACE(CAST(SUM(case when (dia = 1) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X')as ger01,
REPLACE(CAST(SUM(case when (dia = 2) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X')as ger02,
REPLACE(CAST(SUM(case when (dia = 3) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X')as ger03,
REPLACE(CAST(SUM(case when (dia = 4) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X')as ger04,
REPLACE(CAST(SUM(case when (dia = 5) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X')as ger05,
REPLACE(CAST(SUM(case when (dia = 6) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X')as ger06,
REPLACE(CAST(SUM(case when (dia = 7) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X')as ger07,
REPLACE(CAST(SUM(case when (dia = 8) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X')as ger08,
REPLACE(CAST(SUM(case when (dia = 9) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X')as ger09,
REPLACE(CAST(SUM(case when (dia = 10) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger10,
REPLACE(CAST(SUM(case when (dia = 11) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger11,
REPLACE(CAST(SUM(case when (dia = 12) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger12,
REPLACE(CAST(SUM(case when (dia = 13) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger13,
REPLACE(CAST(SUM(case when (dia = 14) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger14,
REPLACE(CAST(SUM(case when (dia = 15) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger15,
REPLACE(CAST(SUM(case when (dia = 16) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger16,
REPLACE(CAST(SUM(case when (dia = 17) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger17,
REPLACE(CAST(SUM(case when (dia = 18) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger18,
REPLACE(CAST(SUM(case when (dia = 19) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger19,
REPLACE(CAST(SUM(case when (dia = 20) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger20,
REPLACE(CAST(SUM(case when (dia = 21) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger21,
REPLACE(CAST(SUM(case when (dia = 22) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger22,
REPLACE(CAST(SUM(case when (dia = 23) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger23,
REPLACE(CAST(SUM(case when (dia = 24) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger24,
REPLACE(CAST(SUM(case when (dia = 25) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger25,
REPLACE(CAST(SUM(case when (dia = 26) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger26,
REPLACE(CAST(SUM(case when (dia = 27) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger27,
REPLACE(CAST(SUM(case when (dia = 28) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger28,
REPLACE(CAST(SUM(case when (dia = 29) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger29,
REPLACE(CAST(SUM(case when (dia = 30) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger30,
REPLACE(CAST(SUM(case when (dia = 31) and (comissao_geral = 3) then 1 end) AS CHAR), '1', 'X') as ger31,
REPLACE(CAST(SUM(case when (dia = 1) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X')as car01,
REPLACE(CAST(SUM(case when (dia = 2) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X')as car02,
REPLACE(CAST(SUM(case when (dia = 3) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X')as car03,
REPLACE(CAST(SUM(case when (dia = 4) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X')as car04,
REPLACE(CAST(SUM(case when (dia = 5) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X')as car05,
REPLACE(CAST(SUM(case when (dia = 6) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X')as car06,
REPLACE(CAST(SUM(case when (dia = 7) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X')as car07,
REPLACE(CAST(SUM(case when (dia = 8) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X')as car08,
REPLACE(CAST(SUM(case when (dia = 9) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X')as car09,
REPLACE(CAST(SUM(case when (dia = 10) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car10,
REPLACE(CAST(SUM(case when (dia = 11) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car11,
REPLACE(CAST(SUM(case when (dia = 12) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car12,
REPLACE(CAST(SUM(case when (dia = 13) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car13,
REPLACE(CAST(SUM(case when (dia = 14) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car14,
REPLACE(CAST(SUM(case when (dia = 15) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car15,
REPLACE(CAST(SUM(case when (dia = 16) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car16,
REPLACE(CAST(SUM(case when (dia = 17) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car17,
REPLACE(CAST(SUM(case when (dia = 18) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car18,
REPLACE(CAST(SUM(case when (dia = 19) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car19,
REPLACE(CAST(SUM(case when (dia = 20) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car20,
REPLACE(CAST(SUM(case when (dia = 21) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car21,
REPLACE(CAST(SUM(case when (dia = 22) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car22,
REPLACE(CAST(SUM(case when (dia = 23) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car23,
REPLACE(CAST(SUM(case when (dia = 24) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car24,
REPLACE(CAST(SUM(case when (dia = 25) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car25,
REPLACE(CAST(SUM(case when (dia = 26) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car26,
REPLACE(CAST(SUM(case when (dia = 27) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car27,
REPLACE(CAST(SUM(case when (dia = 28) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car28,
REPLACE(CAST(SUM(case when (dia = 29) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car29,
REPLACE(CAST(SUM(case when (dia = 30) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car30,
REPLACE(CAST(SUM(case when (dia = 31) and (comissao_carro = 3) then 1 end) AS CHAR), '1', 'X') as car31,
REPLACE(CAST(SUM(case when (dia = 1) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X')as comb01,
REPLACE(CAST(SUM(case when (dia = 2) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X')as comb02,
REPLACE(CAST(SUM(case when (dia = 3) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X')as comb03,
REPLACE(CAST(SUM(case when (dia = 4) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X')as comb04,
REPLACE(CAST(SUM(case when (dia = 5) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X')as comb05,
REPLACE(CAST(SUM(case when (dia = 6) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X')as comb06,
REPLACE(CAST(SUM(case when (dia = 7) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X')as comb07,
REPLACE(CAST(SUM(case when (dia = 8) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X')as comb08,
REPLACE(CAST(SUM(case when (dia = 9) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X')as comb09,
REPLACE(CAST(SUM(case when (dia = 10) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb10,
REPLACE(CAST(SUM(case when (dia = 11) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb11,
REPLACE(CAST(SUM(case when (dia = 12) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb12,
REPLACE(CAST(SUM(case when (dia = 13) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb13,
REPLACE(CAST(SUM(case when (dia = 14) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb14,
REPLACE(CAST(SUM(case when (dia = 15) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb15,
REPLACE(CAST(SUM(case when (dia = 16) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb16,
REPLACE(CAST(SUM(case when (dia = 17) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb17,
REPLACE(CAST(SUM(case when (dia = 18) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb18,
REPLACE(CAST(SUM(case when (dia = 19) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb19,
REPLACE(CAST(SUM(case when (dia = 20) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb20,
REPLACE(CAST(SUM(case when (dia = 21) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb21,
REPLACE(CAST(SUM(case when (dia = 22) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb22,
REPLACE(CAST(SUM(case when (dia = 23) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb23,
REPLACE(CAST(SUM(case when (dia = 24) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb24,
REPLACE(CAST(SUM(case when (dia = 25) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb25,
REPLACE(CAST(SUM(case when (dia = 26) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb26,
REPLACE(CAST(SUM(case when (dia = 27) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb27,
REPLACE(CAST(SUM(case when (dia = 28) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb28,
REPLACE(CAST(SUM(case when (dia = 29) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb29,
REPLACE(CAST(SUM(case when (dia = 30) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb30,
REPLACE(CAST(SUM(case when (dia = 31) and (comissao_comb = 3) then 1 end) AS CHAR), '1', 'X') as comb31
 from comissao
 group by 1
