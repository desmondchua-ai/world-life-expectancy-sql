USE world_life_expectancy;   -- schema name; the table inside is worldlifeexpectancy

-- =====================================================================
-- WORLD LIFE EXPECTANCY  ·  ACT 2: EXPLORATORY DATA ANALYSIS
-- The clean data answers one question: what is associated with a long life?
-- Narrative arc:
--   A. Life rose globally over 15 years
--   B. ...but very unevenly across countries
--   C. The divide tracks DEVELOPMENT STATUS and WEALTH (the headline drivers)
--   D. Technique demos: BMI relationship + rolling-total window function
-- Note: all queries exclude any leftover 0 / blank life-expectancy defensively,
--   though Act 1 cleaning should have removed them.
-- =====================================================================

SELECT *
FROM worldlifeexpectancy;


-- =====================================================================
-- A · THE BIG PICTURE — has life expectancy improved over time?
-- =====================================================================
-- Average life expectancy per year, globally. Expect a clear upward climb.
SELECT Year,
       ROUND(AVG(`Life expectancy`), 2) AS avg_life_expectancy
FROM worldlifeexpectancy
WHERE `Life expectancy` <> 0          -- defensive: ignore any uncleaned zeros
GROUP BY Year
ORDER BY Year;
-- FINDING: ~66.8 (2007) climbing to ~71.7 (2022) — roughly +5 years in 15.


-- =====================================================================
-- B · THE UNEVENNESS — who improved, and who barely moved?
-- =====================================================================
-- Each country's 15-year gain (max minus min life expectancy).
-- Sorting ASC surfaces the countries that improved LEAST — often already-rich
-- nations near a ceiling, OR struggling ones. Sorting DESC shows biggest gains.
SELECT Country,
       MIN(`Life expectancy`) AS min_life_exp,
       MAX(`Life expectancy`) AS max_life_exp,
       ROUND(MAX(`Life expectancy`) - MIN(`Life expectancy`), 1) AS life_gain_15yr
FROM worldlifeexpectancy
WHERE `Life expectancy` <> 0
GROUP BY Country
HAVING min_life_exp <> 0               -- guard against any country with no clean data
   AND max_life_exp <> 0
ORDER BY life_gain_15yr DESC;          -- flip to ASC to see the smallest movers
-- FINDING: gains range from ~0 (already-high, e.g. developed nations) to 20+
--   years (developing nations catching up). Inequality in the RATE of progress.


-- =====================================================================
-- C · THE DRIVERS — what separates long-life countries from short-life ones?
-- =====================================================================

-- C1 · DEVELOPMENT STATUS GAP — the starkest single split.
-- COUNT(DISTINCT Country) guards against the row-count imbalance (far more
-- Developing rows than Developed) skewing how we read the averages.
SELECT Status,
       COUNT(DISTINCT Country) AS countries,
       ROUND(AVG(`Life expectancy`), 1) AS avg_life_expectancy
FROM worldlifeexpectancy
WHERE `Life expectancy` <> 0
GROUP BY Status;
-- FINDING: Developed ~79.2 vs Developing ~67.1 — a ~12-YEAR gap. Headline.


-- C2 · WEALTH GAP — does GDP track longevity?
-- Split countries at GDP 1500 into high vs low and compare average life exp.
-- NOTE: strict boundary (< 1500 vs >= 1500) so no row is double-counted.
SELECT
    SUM(CASE WHEN GDP >= 1500 THEN 1 ELSE 0 END)                              AS high_gdp_count,
    ROUND(AVG(CASE WHEN GDP >= 1500 THEN `Life expectancy` ELSE NULL END),1) AS high_gdp_life_exp,
    SUM(CASE WHEN GDP <  1500 THEN 1 ELSE 0 END)                              AS low_gdp_count,
    ROUND(AVG(CASE WHEN GDP <  1500 THEN `Life expectancy` ELSE NULL END),1)  AS low_gdp_life_exp
FROM worldlifeexpectancy
WHERE `Life expectancy` <> 0;
-- FINDING: high-GDP avg ~74.4 vs low-GDP ~65.0 — a ~9.4-YEAR gap. Wealth tracks
--   longevity, reinforcing the status story from C1.

-- C2b · The per-country GDP detail behind the split (supports C2, good for a chart)
SELECT Country,
       ROUND(AVG(`Life expectancy`), 1) AS avg_life_exp,
       ROUND(AVG(GDP), 1)               AS avg_gdp
FROM worldlifeexpectancy
GROUP BY Country
HAVING avg_life_exp > 0
   AND avg_gdp > 0
ORDER BY avg_gdp DESC;


-- =====================================================================
-- D · ADDITIONAL EXPLORATIONS (technique demonstrations)
-- =====================================================================

-- D1 · BMI vs life expectancy by country.
-- Interesting counter-intuitive angle: in this dataset higher average BMI often
-- correlates with HIGHER life expectancy — because BMI here proxies for
-- nutrition/development, not individual health. A good "correlation != cause" note.
SELECT Country,
       ROUND(AVG(`Life expectancy`), 1) AS avg_life_exp,
       ROUND(AVG(BMI), 1)               AS avg_bmi
FROM worldlifeexpectancy
GROUP BY Country
HAVING avg_life_exp > 0
   AND avg_bmi > 0
ORDER BY avg_bmi DESC;

-- D2 · Window function demo — running total with SUM() OVER().
-- OVER() works with any aggregate, not just ROW_NUMBER/RANK.
--   • SUM() GROUP BY  → collapses rows into one grand total
--   • SUM() OVER()    → keeps every row, shows the total beside each
-- ORDER BY Year    → makes it cumulative (each row = sum up to that row)
-- PARTITION BY Country → restarts the running total for each country
SELECT Country,
       Year,
       `Life expectancy`,
       `Adult Mortality`,
       SUM(`Adult Mortality`) OVER (PARTITION BY Country ORDER BY Year) AS rolling_adult_mortality
FROM worldlifeexpectancy
WHERE Country LIKE '%United States%';

-- D2 · Window function demo — year-over-year change with LAG().
-- LAG() pulls the previous row's value (per the ORDER BY sequence), letting us
-- compare each year to the one before. PARTITION BY Country resets per country.
SELECT Country,
       Year,
       `Life expectancy`,
       LAG(`Life expectancy`) OVER (PARTITION BY Country ORDER BY Year) AS prev_year_life_exp,
       ROUND(`Life expectancy` -
             LAG(`Life expectancy`) OVER (PARTITION BY Country ORDER BY Year), 1) AS yoy_change
FROM worldlifeexpectancy
WHERE Country LIKE '%United States%';
