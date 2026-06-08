USE world_life_expectancy;   -- schema name; the table inside is worldlifeexpectancy

-- =====================================================================
-- WORLD LIFE EXPECTANCY  ·  ACT 1: DATA CLEANING
-- Goal: take the raw import to an analysis-ready state we can trust.
-- 2,941 rows · 193 countries · 2007–2022
-- Cleaning order: duplicates → blank Status → blank/zero Life expectancy
-- Golden rule: preview every SELECT before promoting it to UPDATE/DELETE.
-- =====================================================================

-- Baseline look at the raw table
SELECT *
FROM worldlifeexpectancy;


-- ---------------------------------------------------------------------
-- 1 · REMOVE DUPLICATE Country+Year RECORDS
-- A country-year should be unique. CONCAT(Country, Year) is our natural key.
-- ---------------------------------------------------------------------

-- 1a · Find the duplicates: any Country+Year key that appears more than once
SELECT Country, Year, CONCAT(Country, Year) AS country_year,
       COUNT(CONCAT(Country, Year)) AS occurrences
FROM worldlifeexpectancy
GROUP BY Country, Year, CONCAT(Country, Year)
HAVING COUNT(CONCAT(Country, Year)) > 1;          -- expect 3 keys: Ireland 2022, Senegal 2009, Zimbabwe 2019

-- 1b · Pinpoint the exact duplicate ROWS with ROW_NUMBER.
-- PARTITION BY the key restarts the counter per country-year; the first copy
-- gets Row_Num = 1 (the keeper), the second copy gets Row_Num = 2 (to delete).
SELECT *
FROM (
    SELECT Row_ID,
           CONCAT(Country, Year) AS country_year,
           ROW_NUMBER() OVER (PARTITION BY CONCAT(Country, Year)
                              ORDER BY CONCAT(Country, Year)) AS Row_Num
    FROM worldlifeexpectancy
) AS row_table
WHERE Row_Num > 1;                                 -- the 3 duplicate rows to remove

-- 1c · Delete them: remove every Row_ID the CTE flagged as Row_Num > 1
DELETE FROM worldlifeexpectancy
WHERE Row_ID IN (
    SELECT Row_ID
    FROM (
        SELECT Row_ID,
               ROW_NUMBER() OVER (PARTITION BY CONCAT(Country, Year)
                                  ORDER BY CONCAT(Country, Year)) AS Row_Num
        FROM worldlifeexpectancy
    ) AS row_table
    WHERE Row_Num > 1
);
-- Table now has 2,938 rows (2,941 - 3 duplicates).


-- ---------------------------------------------------------------------
-- 2 · POPULATE BLANK Status VALUES
-- 8 rows have a blank Status. Status is a country-level attribute, so we can
-- borrow it from another row of the SAME country (self-join).
-- ---------------------------------------------------------------------

-- MISSING-VALUE AUDIT — count blanks/NULLs across every column
-- Run this BEFORE cleaning, to see where the gaps actually are.
SELECT
  SUM(Country = '' OR Country IS NULL)                         AS m_country,
  SUM(Year = '' OR Year IS NULL)                               AS m_year,
  SUM(Status = '' OR Status IS NULL)                           AS m_status,
  SUM(`Life expectancy` = '' OR `Life expectancy` IS NULL)     AS m_life_exp,
  SUM(`Adult Mortality` = '' OR `Adult Mortality` IS NULL)     AS m_adult_mort,
  SUM(GDP = '' OR GDP IS NULL)                                 AS m_gdp,
  SUM(BMI = '' OR BMI IS NULL)                                 AS m_bmi
FROM worldlifeexpectancy;

-- AUDIT RESULT: status=8, life_exp=2, adult_mort=10, gdp=448, bmi=34; keys clean.
--
-- WHAT TO FIX (legitimate, knowable fix + analysis needs it):
--   • Status (8)       -> self-join: status is a fixed country attribute
--   • Life expectancy  -> interpolate: headline metric, must be clean
--                         (also fixes 10 zeros = missing coded as 0)
--
-- WHAT TO LEAVE (no honest fix; exclude per-query instead of inventing):
--   • GDP (448 ≈ 15%)  -> too many to fabricate; EDA filters with GDP > 0
--   • BMI (34), Adult Mortality (10) -> measures, not used as keys; exclude when needed
--
-- Principle: cleaning = fix what's fixable AND needed; exclude the rest
-- transparently. Filling a blank is a DECISION, not a default.

-- 2a · See the blanks
SELECT *
FROM worldlifeexpectancy
WHERE Status = '';                                 -- 8 rows

-- 2b · Confirm the only valid values (so we know what we're filling with)
SELECT DISTINCT Status
FROM worldlifeexpectancy
WHERE Status <> '';                                -- 'Developing', 'Developed'

-- 2c · Fill blanks for countries that ARE Developing.
-- Self-join: t1 = the blank row, t2 = a populated row of the same country.
SELECT t1.Country, t1.Status AS blank_status, t2.Status AS source_status
FROM worldlifeexpectancy t1
JOIN worldlifeexpectancy t2 ON t1.Country = t2.Country
WHERE t1.Status = '' AND t2.Status = 'Developing';   -- preview which rows will be filled

UPDATE worldlifeexpectancy t1
JOIN worldlifeexpectancy t2 ON t1.Country = t2.Country
SET t1.Status = 'Developing'
WHERE t1.Status = '' AND t2.Status = 'Developing';

-- 2d · Same for Developed countries
UPDATE worldlifeexpectancy t1
JOIN worldlifeexpectancy t2 ON t1.Country = t2.Country
SET t1.Status = 'Developed'
WHERE t1.Status = '' AND t2.Status = 'Developed';

-- Verify: zero blanks remain
SELECT COUNT(*) AS blank_status_remaining
FROM worldlifeexpectancy
WHERE Status = '';                                 -- expect 0


-- ---------------------------------------------------------------------
-- 3 · FIX MISSING Life expectancy  (the headline metric)
-- TWO kinds of missing here — this is the data-quality catch:
--   (a) 2 rows are BLANK ('')
--   (b) 10 rows are literally 0  (all tiny nations in 2020 — missing source
--       data coded as zero, not a real life expectancy of 0 years)
-- Both must be fixed, or every downstream average is wrong.
-- ---------------------------------------------------------------------

-- 3a · See BOTH kinds of missing value together
SELECT Country, Year, `Life expectancy`
FROM worldlifeexpectancy
WHERE `Life expectancy` = '' OR `Life expectancy` = 0
ORDER BY Country, Year;                            -- 2 blanks + 10 zeros = 12 rows

-- 3b · Interpolate from adjacent years.
-- Triple self-join: t1 = the missing row, t2 = the year BEFORE, t3 = the year AFTER.
-- Average the neighbouring years to estimate the gap.
-- (Assumption: both neighbouring years exist and are populated — true for all
--  12 rows here. Worth noting as a caveat: first/last-year gaps wouldn't fill.)
SELECT t1.Country, t1.Year, t1.`Life expectancy` AS missing_value,
       t2.Year AS prev_year, t2.`Life expectancy` AS prev_le,
       t3.Year AS next_year, t3.`Life expectancy` AS next_le,
       ROUND((t2.`Life expectancy` + t3.`Life expectancy`) / 2, 1) AS interpolated
FROM worldlifeexpectancy t1
JOIN worldlifeexpectancy t2
    ON t1.Country = t2.Country AND t1.Year = t2.Year - 1
JOIN worldlifeexpectancy t3
    ON t1.Country = t3.Country AND t1.Year = t3.Year + 1
WHERE t1.`Life expectancy` = '' OR t1.`Life expectancy` = 0;   -- preview the fills

-- 3c · Apply the interpolation to BOTH blanks and zeros
UPDATE worldlifeexpectancy t1
JOIN worldlifeexpectancy t2
    ON t1.Country = t2.Country AND t1.Year = t2.Year - 1
JOIN worldlifeexpectancy t3
    ON t1.Country = t3.Country AND t1.Year = t3.Year + 1
SET t1.`Life expectancy` = ROUND((t2.`Life expectancy` + t3.`Life expectancy`) / 2, 1)
WHERE t1.`Life expectancy` = '' OR t1.`Life expectancy` = 0;

-- 3d. Convert impossible "0" life-expectancy to NULL.
-- A life expectancy of 0 isn't real — it's missing data coded as 0. These 10 rows
-- are single-year countries (e.g. Cook Islands = 2020 only), so no adjacent years
-- exist to interpolate from. NULL is the honest label for "unknown" and AVG/COUNT
-- skip it automatically — a 0 would be counted and drag averages down.
UPDATE worldlifeexpectancy
SET `Life expectancy` = NULL
WHERE `Life expectancy` = 0;

-- Verify: no blanks and no zeros remain
SELECT COUNT(*) AS missing_life_exp_remaining
FROM worldlifeexpectancy
WHERE `Life expectancy` = '' OR `Life expectancy` = 0;   -- expect 0
-- ---------------------------------------------------------------------
-- FINAL CHECK — clean, trustworthy table ready for analysis
-- ---------------------------------------------------------------------
SELECT *
FROM worldlifeexpectancy;

SELECT Country, Year, `Life expectancy`
FROM worldlifeexpectancy
WHERE Country IN (
  SELECT Country FROM worldlifeexpectancy WHERE `Life expectancy` = 0
)
ORDER BY Country, Year;
