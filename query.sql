-- ЗАДАЧА 1: Оценка времени активности объявлений и расчет средних показателей сегментов

-- 1. Вычисляем перцентили для определения границ выбросов и аномалий в данных
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- 2. Отбираем ID квартир, очищенные от выбросов по площади, комнатам, балконам и высоте потолков
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- 3. Формируем основную витрину: размечаем категории по сроку продажи и вычисляем цену за квадрат
prepared_data AS (
	SELECT
		*,
		CASE WHEN days_exposition >= 1 AND days_exposition <= 30 THEN '1-30 days'
		WHEN days_exposition > 30 AND days_exposition <= 90 THEN '31-90 days'
		WHEN days_exposition > 90 AND days_exposition <= 180 THEN '91-180 days'
		WHEN days_exposition > 180 THEN '181+ days'
		ELSE 'non category' END AS category_flats,
		CASE WHEN c.city = 'Санкт-Петербург' THEN c.city
		ELSE 'Ленинградская область' END AS region,
		a.last_price / f.total_area AS sqm_price
	FROM real_estate.advertisement AS a
	JOIN real_estate.flats AS f USING (id)
	JOIN real_estate.city AS c USING(city_id)
	JOIN real_estate."type" AS t USING (type_id)
	WHERE EXTRACT(YEAR FROM a.first_day_exposition) BETWEEN 2015 AND 2018 
	AND t.TYPE = 'город' 
	AND f.id IN (SELECT * FROM filtered_id)
)
-- 4. Агрегируем итоговые метрики в разрезе региона и категории времени активности
	SELECT
		region,
		category_flats,
		COUNT(id) AS flats_cnt,
		ROUND(AVG(sqm_price)::numeric, 2) AS avg_sqm_price,
		ROUND(AVG(total_area)::numeric, 2) AS avg_area,
		PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rooms) AS med_rooms,
		PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY balcony) AS med_balc,
		PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY floors_total) AS med_total_floor
	FROM prepared_data
	GROUP BY 1, 2
	ORDER BY 1 DESC, 3 DESC;


/*======================================================================================*/


-- ЗАДАЧА 2: Анализ сезонности на рынке

-- 1. Вычисляем перцентили для очистки от аномалий
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- 2. Фильтруем ID квартир от выбросов
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- 3. Выделяем месяцы публикации и расчетные месяцы снятия объявлений
prepared_data AS (
	SELECT
		*,
		a.last_price / f.total_area AS sqm_price,
		EXTRACT(MONTH FROM a.first_day_exposition) AS pub_month,
		EXTRACT(MONTH FROM (a.first_day_exposition + a.days_exposition::int)) AS remove_month
	FROM real_estate.advertisement AS a
	JOIN real_estate.flats AS f USING (id)
	JOIN real_estate.city AS c USING(city_id)
	JOIN real_estate.type AS t USING (type_id)
	WHERE t.type = 'город' AND EXTRACT(YEAR FROM a.first_day_exposition) BETWEEN 2015 AND 2018 
	AND f.id IN (SELECT * FROM filtered_id)
),
-- 4. Агрегируем метрики по месяцу выхода объявления на рынок
pub_stats AS (
	SELECT
		pub_month,
		COUNT(id) AS pub_cnt,
		ROUND(AVG(sqm_price)::numeric, 2) AS pub_avg_sqm_price,
		ROUND(AVG(total_area)::NUMERIC, 2) AS pub_avg_area
	FROM prepared_data
	GROUP BY 1
),
-- 5. Агрегируем метрики по месяцу продажи/снятия
remove_stats AS (
	SELECT
		remove_month,
		COUNT(id) AS remove_cnt,
		ROUND(AVG(sqm_price)::numeric, 2) AS remove_avg_sqm_price,
		ROUND(AVG(total_area)::NUMERIC, 2) AS remove_avg_area
	FROM prepared_data
	WHERE remove_month IS NOT NULL
	GROUP BY 1
)
-- 6. Джоиним статистики для итогового сравнения сезонности продавцов и покупателей
SELECT
	pub_month AS month,
	ps.pub_cnt,
	rs.remove_cnt,
	ps.pub_avg_sqm_price ,
	rs.remove_avg_sqm_price,
	ps.pub_avg_area,
	rs.remove_avg_area
FROM pub_stats AS ps
JOIN remove_stats AS rs ON ps.pub_month = rs.remove_month
ORDER BY 1;