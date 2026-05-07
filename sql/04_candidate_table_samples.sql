SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

SELECT TOP 25
    'clients__Reference64' AS probe,
    CONVERT(varchar(32), c._IDRRef, 2) AS client_ref,
    c._Code AS client_code,
    c._Description AS client_fio,
    c._Fld3811 AS first_name,
    c._Fld3835 AS patronymic,
    c._Fld3822 AS date_a,
    c._Fld3810 AS date_b,
    c._Fld3812 AS text_a,
    c._Fld3816 AS text_b,
    c._Fld3819 AS text_c,
    c._Fld3829 AS text_d,
    c._Fld3843 AS text_e,
    c._Fld8120 AS text_f
FROM dbo._Reference64 AS c
ORDER BY c._Code;
GO

SELECT
    '_Reference59_owner_rt_distribution' AS probe,
    CONVERT(varchar(8), card._Fld3750_RTRef, 2) AS owner_rt,
    COUNT_BIG(*) AS rows_count,
    COUNT(DISTINCT CONVERT(varchar(32), card._Fld3750_RRRef, 2)) AS distinct_owners
FROM dbo._Reference59 AS card
GROUP BY CONVERT(varchar(8), card._Fld3750_RTRef, 2)
ORDER BY rows_count DESC;
GO

SELECT TOP 25
    'plastic_cards__Reference59' AS probe,
    CONVERT(varchar(32), card._IDRRef, 2) AS card_ref,
    card._Code AS card_code,
    card._Description AS card_description,
    card._Fld3751 AS issue_date_candidate,
    card._Fld3753 AS card_number_candidate_a,
    card._Fld3756 AS card_number_candidate_b,
    CONVERT(varchar(8), card._Fld3750_RTRef, 2) AS owner_rt,
    CONVERT(varchar(32), card._Fld3750_RRRef, 2) AS owner_ref,
    c._Code AS client_code,
    c._Description AS client_fio
FROM dbo._Reference59 AS card
LEFT JOIN dbo._Reference64 AS c
    ON card._Fld3750_RTRef = 0x00000040
   AND card._Fld3750_RRRef = c._IDRRef
ORDER BY card._Code;
GO

SELECT TOP 25
    'contracts__Reference46' AS probe,
    CONVERT(varchar(32), contract._IDRRef, 2) AS contract_ref,
    contract._Code AS contract_code,
    contract._Description AS contract_description,
    contract._Fld3620 AS contract_number_candidate,
    contract._Fld3618 AS contract_prefix_candidate,
    contract._Fld3624 AS contract_date_candidate,
    contract._Fld9976 AS date_b,
    LEFT(contract._Fld3629, 160) AS html_or_text_sample,
    LEFT(contract._Fld9980, 120) AS text_sample
FROM dbo._Reference46 AS contract
ORDER BY contract._Code;
GO

SELECT TOP 25
    'document152' AS probe,
    d._Number AS doc_number,
    d._Date_Time AS doc_date,
    CONVERT(varchar(2), d._Posted, 2) AS posted,
    p._Code AS client_code,
    p._Description AS client_fio,
    d._Fld1064 AS date_a,
    d._Fld1065 AS date_b,
    d._Fld1059 AS num_a,
    d._Fld7819 AS text_a,
    LEFT(d._Fld1082, 120) AS text_b,
    LEFT(d._Fld1068, 120) AS text_c,
    d._Fld1069 AS num_b,
    d._Fld1073 AS text_d,
    d._Fld1078 AS text_e,
    LEFT(d._Fld1075, 120) AS text_f,
    d._Fld1076 AS text_g,
    LEFT(d._Fld1077, 120) AS text_h,
    d._Fld1079 AS num_c,
    LEFT(d._Fld7822, 120) AS text_i,
    LEFT(d._Fld7826, 120) AS text_j
FROM dbo._Document152 AS d
LEFT JOIN dbo._Reference64 AS p
    ON d._Fld1057_RTRef = 0x00000040
   AND d._Fld1057_RRRef = p._IDRRef
ORDER BY d._Date_Time DESC;
GO

SELECT TOP 25
    'document163' AS probe,
    d._Number AS doc_number,
    d._Date_Time AS doc_date,
    CONVERT(varchar(2), d._Posted, 2) AS posted,
    p._Code AS client_code,
    p._Description AS client_fio,
    d._Fld5402 AS date_a,
    d._Fld1450 AS date_b,
    d._Fld1452 AS num_a,
    d._Fld1454 AS num_b,
    d._Fld1458 AS num_c,
    LEFT(d._Fld1495, 120) AS text_a,
    d._Fld8775 AS text_b,
    d._Fld1461 AS num_d,
    d._Fld1463 AS num_e,
    d._Fld1464 AS num_f,
    d._Fld1465 AS num_g,
    d._Fld1466 AS num_h,
    d._Fld1467 AS num_i,
    d._Fld1468 AS num_j,
    d._Fld7852 AS text_c,
    LEFT(d._Fld5404, 120) AS text_d,
    d._Fld8779 AS date_c,
    d._Fld8776 AS date_d,
    LEFT(d._Fld7855, 120) AS text_e,
    d._Fld8778 AS date_e,
    LEFT(d._Fld7857, 120) AS text_f,
    d._Fld1481 AS num_k,
    d._Fld1482 AS date_f,
    d._Fld1485 AS num_l,
    d._Fld1486 AS num_m,
    d._Fld1493 AS num_n
FROM dbo._Document163 AS d
LEFT JOIN dbo._Reference64 AS p
    ON d._Fld1447_RTRef = 0x00000040
   AND d._Fld1447_RRRef = p._IDRRef
ORDER BY d._Date_Time DESC;
GO

SELECT TOP 25
    'info5233' AS probe,
    p._Code AS client_code,
    p._Description AS client_fio,
    r._Fld5235 AS text_a,
    r._Fld5238 AS text_b,
    r._Fld5239 AS text_c,
    r._Fld5240 AS date_a,
    r._Fld5241 AS date_b,
    r._Fld5242 AS date_c,
    r._Fld5243_S AS text_d,
    LEFT(r._Fld5244, 120) AS text_e,
    r._Fld5246 AS flag_a,
    r._Fld5248 AS flag_b,
    r._Fld5249_S AS text_f,
    r._Fld5942 AS text_g,
    r._Fld7950 AS text_h,
    LEFT(r._Fld5254, 120) AS text_i,
    r._Fld5253 AS num_a
FROM dbo._InfoRg5233 AS r
LEFT JOIN dbo._Reference64 AS p
    ON r._Fld5252_RTRef = 0x00000040
   AND r._Fld5252_RRRef = p._IDRRef
ORDER BY r._Fld5240 DESC;
GO

SELECT TOP 25
    'reference115' AS probe,
    CONVERT(varchar(32), r._IDRRef, 2) AS ref115_ref,
    r._Description AS description,
    p._Code AS client_code,
    p._Description AS client_fio,
    r._Fld4589 AS date_a,
    r._Fld8312 AS date_b,
    r._Fld4590 AS date_c,
    r._Fld4591 AS flag_a,
    r._Fld4592 AS num_a,
    LEFT(r._Fld4593, 120) AS text_a,
    r._Fld4594 AS flag_b,
    r._Fld4595 AS text_b,
    r._Fld4600 AS date_d,
    r._Fld4601 AS date_e,
    r._Fld4602 AS text_c,
    r._Fld4603 AS num_b,
    r._Fld8315 AS num_c,
    r._Fld8316 AS text_d,
    LEFT(r._Fld4604, 120) AS text_e,
    r._Fld4605 AS num_d,
    r._Fld4606 AS text_f,
    r._Fld4608 AS flag_c,
    r._Fld8320 AS text_g
FROM dbo._Reference115 AS r
LEFT JOIN dbo._Reference64 AS p
    ON r._Fld4588_RTRef = 0x00000040
   AND r._Fld4588_RRRef = p._IDRRef
ORDER BY r._Fld4589 DESC;
GO

SELECT TOP 25
    'info7156' AS probe,
    p._Code AS client_code,
    p._Description AS client_fio,
    r._Fld7159 AS date_a,
    r._Fld7161 AS num_a,
    r._Fld7162 AS num_b,
    r._Fld7163 AS text_a,
    LEFT(r._Fld7164, 120) AS text_b,
    r._Fld7165 AS flag_a,
    r._Fld7166 AS num_c,
    r._Fld7167 AS text_c,
    r._Fld7169 AS flag_b,
    r._Fld7171 AS flag_c
FROM dbo._InfoRg7156 AS r
LEFT JOIN dbo._Reference64 AS p
    ON r._Fld7160_RTRef = 0x00000040
   AND r._Fld7160_RRRef = p._IDRRef
ORDER BY r._Fld7159 DESC;
GO

SELECT TOP 25
    'info6941' AS probe,
    p._Code AS client_code,
    p._Description AS client_fio,
    r._Fld6943 AS flag_a,
    r._Fld6944 AS text_a
FROM dbo._InfoRg6941 AS r
LEFT JOIN dbo._Reference64 AS p
    ON r._Fld6942_RTRef = 0x00000040
   AND r._Fld6942_RRRef = p._IDRRef
ORDER BY p._Code;
GO

SELECT TOP 25
    'info2188' AS probe,
    r._Period,
    p._Code AS client_code,
    p._Description AS client_fio,
    r._Fld2191 AS date_a,
    LEFT(r._Fld2192, 120) AS text_a,
    r._Fld2193 AS text_b,
    r._Fld2194 AS text_c,
    LEFT(r._Fld2195, 120) AS text_d,
    r._Fld2196 AS text_e,
    r._Fld2197 AS date_b,
    r._Fld2198 AS flag_a,
    r._Fld2199 AS flag_b
FROM dbo._InfoRg2188 AS r
LEFT JOIN dbo._Reference64 AS p
    ON r._Fld2190_RTRef = 0x00000040
   AND r._Fld2190_RRRef = p._IDRRef
ORDER BY r._Period DESC;
GO

SELECT TOP 25
    'info2436' AS probe,
    p._Code AS client_code,
    p._Description AS client_fio,
    r._Fld2438 AS flag_a,
    r._Fld2439 AS text_a
FROM dbo._InfoRg2436 AS r
LEFT JOIN dbo._Reference64 AS p
    ON r._Fld2437_RTRef = 0x00000040
   AND r._Fld2437_RRRef = p._IDRRef
ORDER BY p._Code;
GO

SELECT TOP 25
    'info5226' AS probe,
    r._Period,
    p._Code AS client_code,
    p._Description AS client_fio,
    r._Fld5227_S AS typed_text,
    r._Fld5228 AS flag_a,
    LEFT(r._Fld5231, 120) AS text_a
FROM dbo._InfoRg5226 AS r
LEFT JOIN dbo._Reference64 AS p
    ON r._Fld5227_RTRef = 0x00000040
   AND r._Fld5227_RRRef = p._IDRRef
ORDER BY r._Period DESC;
GO
