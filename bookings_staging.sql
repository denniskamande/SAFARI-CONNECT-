CREATE SCHEMA IF NOT EXISTS safari_connect;
SET search_path TO safari_connect;

-- Staging table: ALL columns TEXT - accepts dirty data without failing
CREATE TABLE IF NOT EXISTS bookings_staging (
    booking_id       TEXT,
    passenger_name    TEXT, 
    passenger_phone  TEXT,
    passenger_gender TEXT, 
    passenger_city    TEXT, 
    route_code       TEXT,
    route_from       TEXT, 
    route_to          TEXT, 
    vehicle_plate    TEXT,
    vehicle_type     TEXT, 
    driver_name       TEXT, 
    driver_rating    TEXT,
    departure_date   TEXT, 
    departure_time    TEXT, 
    seat_class       TEXT,
    seats_booked     TEXT, 
    fare_per_seat     TEXT, 
    total_fare       TEXT,
    payment_method   TEXT, 
    booking_status    TEXT, 
    trip_rating      TEXT
);

select* from bookings_staging;


-- 1. Name casing problems
SELECT DISTINCT passenger_name FROM bookings_staging ORDER BY passenger_name LIMIT 30;

-- 2. Gender variants - should be only Male/Female
SELECT DISTINCT passenger_gender, COUNT(*) FROM bookings_staging GROUP BY passenger_gender;

-- 3. seat_class variants
SELECT DISTINCT seat_class, COUNT(*) FROM bookings_staging GROUP BY seat_class;

-- 4. payment_method variants
SELECT DISTINCT payment_method FROM bookings_staging;

-- 5. booking_status variants
SELECT DISTINCT booking_status FROM bookings_staging;

-- 6. Date format problems
SELECT booking_id, departure_date FROM bookings_staging
WHERE departure_date NOT SIMILAR TO '[0-9]{4}-[0-9]{2}-[0-9]{2}';

-- 7. Phone format problems
SELECT booking_id, passenger_phone FROM bookings_staging
WHERE passenger_phone LIKE '+254%' OR passenger_phone LIKE '%-%';

-- 8. Fares stored as text
SELECT booking_id, total_fare, fare_per_seat FROM bookings_staging
WHERE total_fare LIKE 'KES%' OR fare_per_seat LIKE 'KES%';

-- 9. Invalid trip ratings
SELECT booking_id, trip_rating FROM bookings_staging
WHERE trip_rating NOT IN ('1','2','3','4','5','');

-- 10. Duplicate booking_ids
SELECT booking_id, COUNT(*) FROM bookings_staging
GROUP BY booking_id HAVING COUNT(*) > 1;

-- 11. Negative seats_booked
SELECT booking_id, seats_booked FROM bookings_staging
WHERE NULLIF(REGEXP_REPLACE(seats_booked,'[^0-9-]','','g'),'')::INTEGER < 1;


--Clean 1 - passenger_name casing + whitespace
SELECT booking_id, passenger_name FROM bookings_staging
WHERE passenger_name != INITCAP(TRIM(passenger_name));

UPDATE bookings_staging
SET passenger_name = INITCAP(TRIM(passenger_name))
WHERE passenger_name != INITCAP(TRIM(passenger_name));

Clean 2 - passenger_phone (dashes, +254, empty)
-- Remove dashes
UPDATE bookings_staging
SET passenger_phone = REGEXP_REPLACE(passenger_phone,'[^0-9]','','g')
WHERE passenger_phone LIKE '%-%';

-- Fix +254 prefix
UPDATE bookings_staging
SET passenger_phone = '0' || SUBSTRING(REGEXP_REPLACE(passenger_phone,'[^0-9]','','g'),4)
WHERE passenger_phone LIKE '+254%';

-- Set empty to NULL
UPDATE bookings_staging SET passenger_phone = NULL
WHERE TRIM(passenger_phone) = '';

--Clean 3 - passenger_gender (7 variants → Male / Female)
UPDATE bookings_staging
SET passenger_gender = CASE
    WHEN UPPER(TRIM(passenger_gender)) IN ('MALE','M') THEN 'Male'
    WHEN UPPER(TRIM(passenger_gender)) IN ('FEMALE','F') THEN 'Female'
    ELSE passenger_gender
END;

--Clean 4 - passenger_city (casing + empty)
UPDATE bookings_staging
SET passenger_city = INITCAP(TRIM(passenger_city))
WHERE passenger_city != INITCAP(TRIM(passenger_city));

UPDATE bookings_staging SET passenger_city = 'Unknown'
WHERE TRIM(passenger_city) = '' OR passenger_city IS NULL;

--Clean 5 - departure_date (3 formats)
-- Fix DD/MM/YYYY
UPDATE bookings_staging
SET departure_date = TO_DATE(departure_date,'DD/MM/YYYY')::TEXT
WHERE departure_date LIKE '%/%';

-- Fix DD-MM-YY (length = 8)
UPDATE bookings_staging
SET departure_date = TO_DATE(departure_date,'DD-MM-YY')::TEXT
WHERE departure_date LIKE '%-%' AND LENGTH(departure_date) = 8;

-- Fix MM-DD-YYYY (length=10, day part > 12 confirms it's MM-DD not DD-MM)
UPDATE bookings_staging
SET departure_date = TO_DATE(departure_date,'MM-DD-YYYY')::TEXT
WHERE departure_date LIKE '%-%'
  AND LENGTH(departure_date) = 10
  AND SPLIT_PART(departure_date,'-',2)::INTEGER > 12;

--Clean 6 - seat_class (abbreviations + casing)
UPDATE bookings_staging
SET seat_class = CASE
    WHEN UPPER(TRIM(seat_class)) IN ('ECONOMY','ECO','ECONOMY CLASS') THEN 'Economy'
    WHEN UPPER(TRIM(seat_class)) IN ('BUSINESS','BUS','BUSINESS CLASS') THEN 'Business'
    ELSE seat_class
END;

--Clean 7 - payment_method and booking_status
UPDATE bookings_staging
SET payment_method = CASE
    WHEN UPPER(TRIM(payment_method)) IN ('MPESA','M-PESA','M PESA') THEN 'M-Pesa'
    WHEN UPPER(TRIM(payment_method)) = 'CASH'                              THEN 'Cash'
    WHEN UPPER(TRIM(payment_method)) = 'CARD'                              THEN 'Card'
    ELSE payment_method
END;

UPDATE bookings_staging
SET booking_status = CASE
    WHEN UPPER(TRIM(booking_status)) = 'COMPLETED'  THEN 'Completed'
    WHEN UPPER(TRIM(booking_status)) = 'CANCELLED'  THEN 'Cancelled'
    WHEN UPPER(TRIM(booking_status)) = 'NO SHOW'     THEN 'No Show'
    ELSE booking_status
END;

--Clean 8 - fare_per_seat and total_fare (strip KES)
UPDATE bookings_staging
SET total_fare = REGEXP_REPLACE(total_fare,'[^0-9.]','','g')
WHERE total_fare SIMILAR TO '%[^0-9.]%';

UPDATE bookings_staging
SET fare_per_seat = REGEXP_REPLACE(fare_per_seat,'[^0-9.]','','g')
WHERE fare_per_seat SIMILAR TO '%[^0-9.]%';

--Clean 9 - driver_name casing
UPDATE bookings_staging
SET driver_name = INITCAP(TRIM(driver_name))
WHERE driver_name != INITCAP(TRIM(driver_name));

--Clean 10 - vehicle_type casing
UPDATE bookings_staging
SET vehicle_type = INITCAP(TRIM(vehicle_type))
WHERE vehicle_type != INITCAP(TRIM(vehicle_type));

--Clean 11 - trip_rating (invalid values → NULL)
UPDATE bookings_staging
SET trip_rating = NULL
WHERE TRIM(trip_rating) NOT IN ('1','2','3','4','5','');

--Clean 12 - Remove negative seats and duplicates
-- Delete rows with negative seats
DELETE FROM bookings_staging
WHERE NULLIF(REGEXP_REPLACE(seats_booked,'[^0-9-]','','g'),'')::INTEGER < 1;

-- Remove exact duplicates (keep first ctid)
DELETE FROM bookings_staging
WHERE ctid NOT IN 
    (SELECT MIN(ctid) FROM bookings_staging GROUP BY booking_id);

--Clean 13- passenger_phone
 select passenger_phone
 from bookings_staging;

--adding zero infront of the number
--making the 254 -07

select regexp_replace(passenger_phone,'[^0-9]','','g') as phones
from bookings_staging;



update bookings_staging
set  passenger_phone =
    case 
        when  passenger_phone IS NULL
             or  TRIM(passenger_phone) = ''
        then  passenger_phone

        when  REGEXP_REPLACE(passenger_phone, '[^0-9]', '', 'g') like  '0%'
        then  REGEXP_REPLACE(passenger_phone, '[^0-9]', '', 'g')

        else  '0' || REGEXP_REPLACE(passenger_phone, '[^0-9]', '', 'g')
    end;

        
        
 --Step 5 - Create Production Table & Load Clean Data

CREATE TABLE IF NOT EXISTS bookings (
    booking_id        VARCHAR(10) PRIMARY KEY,
    passenger_name    VARCHAR(100),  passenger_phone  VARCHAR(15),
    passenger_gender  VARCHAR(10),   passenger_city   VARCHAR(60),
    route_code        VARCHAR(10),   route_from       VARCHAR(60),
    route_to          VARCHAR(60),   vehicle_plate    VARCHAR(15),
    vehicle_type      VARCHAR(20),   driver_name      VARCHAR(100),
    driver_rating     NUMERIC(3,1),  departure_date   DATE,
    departure_time    VARCHAR(10),   seat_class       VARCHAR(20),
    seats_booked      INTEGER,       fare_per_seat    NUMERIC(10,2),
    total_fare        NUMERIC(12,2), payment_method   VARCHAR(20),
    booking_status    VARCHAR(20),   trip_rating      INTEGER
);

INSERT INTO bookings
SELECT
    booking_id, TRIM(passenger_name),
    NULLIF(TRIM(passenger_phone),''),
    passenger_gender, COALESCE(NULLIF(TRIM(passenger_city),''),'Unknown'),
    route_code, route_from, route_to, vehicle_plate, INITCAP(TRIM(vehicle_type)),
    TRIM(driver_name),
    NULLIF(REGEXP_REPLACE(driver_rating,'[^0-9.]','','g'),'')::NUMERIC,
    departure_date::DATE,  departure_time, seat_class,
    NULLIF(REGEXP_REPLACE(seats_booked,'[^0-9]','','g'),'')::INTEGER,
    NULLIF(REGEXP_REPLACE(fare_per_seat,'[^0-9.]','','g'),'')::NUMERIC,
    NULLIF(REGEXP_REPLACE(total_fare,'[^0-9.]','','g'),'')::NUMERIC,
    payment_method, booking_status,
    NULLIF(trip_rating,'')::INTEGER
FROM bookings_staging
WHERE departure_date SIMILAR TO '[0-9]{4}-[0-9]{2}-[0-9]{2}'
  AND NULLIF(REGEXP_REPLACE(seats_booked,'[^0-9]','','g'),'')::INTEGER > 0;

-- Verify
SELECT COUNT(*) FROM bookings;  -- expect ~280+
SELECT DISTINCT booking_status FROM bookings; -- exactly: Completed, Cancelled, No Show
SELECT DISTINCT seat_class FROM bookings;     -- exactly: Economy, Business
       
--Step 6 - Create v_clean_trips View

CREATE OR REPLACE VIEW v_clean_trips AS
SELECT *,
    TO_CHAR(departure_date, 'YYYY-MM')    AS travel_month,
    TO_CHAR(departure_date, 'Month YYYY') AS month_label,
    TO_CHAR(departure_date, 'Day')        AS day_name,
    EXTRACT(MONTH FROM departure_date)    AS month_num,
    EXTRACT(DOW FROM departure_date)      AS day_of_week,
    (fare_per_seat * seats_booked)           AS calculated_fare,
    CASE
        WHEN trip_rating BETWEEN 4 AND 5 THEN 'Satisfied'
        WHEN trip_rating = 3 THEN 'Neutral'
        WHEN trip_rating BETWEEN 1 AND 2 THEN 'Unsatisfied'
        ELSE 'No Rating'
    END AS satisfaction
FROM bookings
WHERE booking_status = 'Completed';

-- Test
SELECT * FROM v_clean_trips LIMIT 10;



        
select count(*) 
from bookings_staging

select* from bookings_staging;

select*, data_type
from bookings_staging
where table_schema= bookings_staging;

select 
    column_name,
    data_type
from  information_schema.columns
where  table_schema = 'safari_connect'
  and  table_name = 'bookings_staging'
order by  ordinal_position;


---Converting 

--BUSINESS QUESTIONS TO ANSWER FROM THE DATA

-- 1.
/* Route Analysis Which routes earn the most? 
  Which are most popular? Which is most efficient per seat sold?
  */

SELECT
    route_code,
    route_from || ' → ' || route_to      AS route,
    COUNT(*)                              AS total_bookings,
    SUM(seats_booked)                   AS total_seats,
    SUM(total_fare)                     AS total_revenue,
    ROUND(AVG(fare_per_seat), 2)     AS avg_fare,
    ROUND(AVG(trip_rating), 2)       AS avg_rating
FROM v_clean_trips
GROUP BY route_code, route_from, route_to
ORDER BY total_revenue DESC;


--Route ranking with window function
--Rank all routes by total revenue using RANK(). Also show each route's percentage of total company revenue.

WITH route_rev AS (
    SELECT route_code, route_from || ' → ' || route_to AS route,
           SUM(total_fare) AS revenue
    FROM v_clean_trips GROUP BY route_code, route_from, route_to
)
SELECT
    route, revenue,
    RANK() OVER (ORDER BY revenue DESC) AS revenue_rank,
    ROUND(revenue * 100.0 / SUM(revenue) OVER (), 1) AS pct_of_total
FROM route_rev ORDER BY revenue_rank;


--1D - Vehicle type performance
/*Compare Bus vs Matatu vs Minibus - total bookings, revenue, avg rating. 
 * 
 *Which vehicle type is most profitable?
 */
select route_code,vehicle_type,total_fare
from bookings_staging;


SELECT
    vehicle_type,
    COUNT(*) AS total_bookings,
    SUM(total_fare) AS total_revenue,
    ROUND(AVG(trip_rating), 2) AS avg_rating
FROM v_clean_trips GROUP BY vehicle_type
ORDER BY total_revenue DESC;

/*Question 2 - Driver Performance

Business need: HR wants to know who to promote, who needs training, and whether driver rating affects passenger satisfaction.

2A - Driver summary
Show: driver_name, total_trips, total_seats_carried, total_revenue, avg_trip_rating, driver_rating. Order by total_revenue descending.

*/

SELECT
    driver_name,
    COUNT(*) AS total_trips,
    SUM(seats_booked) AS total_seats,
    SUM(total_fare) AS total_revenue,
    AVG(driver_rating) AS avg_driver_rating,
    ROUND(AVG(trip_rating), 2) AS avg_trip_rating
FROM v_clean_trips vct
GROUP BY vct.driver_name
ORDER BY SUM(total_fare) DESC;

-- 2B - Driver ranking - overall + by vehicle type
/*Using a CTE for driver totals, rank drivers overall by 
 revenue AND within their vehicle type using PARTITION BY vehicle_type.
 */

WITH driver_totals AS (
    SELECT
        driver_name,
        vehicle_type,
        COUNT(*)             AS total_trips,
        SUM(total_fare)    AS total_revenue,
        ROUND(AVG(trip_rating),2) AS avg_passenger_rating
    FROM v_clean_trips
    GROUP BY driver_name, vehicle_type
)
SELECT
    driver_name, vehicle_type, total_trips, total_revenue, avg_passenger_rating,
    RANK() OVER (ORDER BY total_revenue DESC)                        AS overall_rank,
    RANK() OVER (PARTITION BY vehicle_type ORDER BY total_revenue DESC) AS vehicle_rank
FROM driver_totals
ORDER BY overall_rank;

/*2C - Does driver rating predict passenger satisfaction?
Group drivers into high-rated (≥ 4.5) and standard (< 4.5). Compare average passenger trip_rating for each group. Does a higher driver rating lead to happier passengers?
*/
SELECT
    driver_name,
    driver_rating,
    COUNT(*) AS total_trips,
    ROUND(AVG(trip_rating), 2) AS avg_passenger_rating
FROM v_clean_trips
GROUP BY driver_name, driver_rating
ORDER BY total_trips desc,driver_rating;


SELECT
    CASE
        WHEN driver_rating >= 4.5 THEN 'High-rated'
        ELSE 'Standard'
    END AS driver_group,
    round(AVG(trip_rating),2) AS avg_passenger_rating
FROM v_clean_trips
GROUP BY
    CASE
        WHEN driver_rating >= 4.5 THEN 'High-rated'
        ELSE 'Standard'
    END;

---No the driver ratings does not predict customer satisfaction


/*Question 3 - Revenue Trends

Business need: The Director wants to see if Safari Connect is growing and which months to focus on for expansion.
*/

--3A - Monthly revenue with month-over-month change (CTE + LAG)

WITH monthly AS (
    SELECT
        TO_CHAR(departure_date, 'YYYY-MM') AS month,
        COUNT(*)                                AS bookings,
        SUM(total_fare)                       AS revenue
    FROM v_clean_trips
    GROUP BY TO_CHAR(departure_date, 'YYYY-MM')
)
SELECT
    month, bookings, revenue,
    LAG(revenue) OVER (ORDER BY month)   AS prev_month,
    revenue - LAG(revenue) OVER (ORDER BY month)    AS change,
    ROUND((revenue - LAG(revenue) OVER (ORDER BY month))
        / NULLIF(LAG(revenue) OVER (ORDER BY month),0) * 100, 1)  AS change_pct
FROM monthly ORDER BY month;

/*3B - Running total of revenue
Show each month with its revenue and a cumulative running total from January onwards.
*/

SELECT
    TO_CHAR(departure_date, 'YYYY-MM') AS month,
    SUM(total_fare) AS monthly_revenue,
    SUM(SUM(total_fare)) OVER (
        ORDER BY TO_CHAR(departure_date, 'YYYY-MM')
    ) AS running_total
FROM v_clean_trips
GROUP BY TO_CHAR(departure_date, 'YYYY-MM')
ORDER BY month;


/*3C - Best and worst 3 months
Using a CTE for monthly revenue, show the top 3 months and the bottom 3 months by revenue. Use RANK().

*/
--Step 1 — Monthly revenue CTE

WITH monthly_revenue AS (
    SELECT
        TO_CHAR(departure_date, 'YYYY-MM') AS month,
        SUM(total_fare) AS revenue),
    FROM v_clean_trips
    GROUP BY TO_CHAR(departure_date, 'YYYY-MM');


WITH monthly_revenue AS (
    SELECT
        TO_CHAR(departure_date, 'YYYY-MM') AS month,
        SUM(total_fare) AS revenue
    FROM v_clean_trips
    GROUP BY TO_CHAR(departure_date, 'YYYY-MM')
),

ranked_months AS (
    SELECT
        month,
        revenue,
        RANK() OVER (ORDER BY revenue DESC) AS best_rank,
        RANK() OVER (ORDER BY revenue ASC) AS worst_rank
    FROM monthly_revenue
)

SELECT
    month,
    revenue,
    best_rank,
    worst_rank
FROM ranked_months
WHERE best_rank <= 3
   OR worst_rank <= 3
ORDER BY revenue DESC;



WITH monthly AS (
    SELECT
        TO_CHAR(departure_date, 'YYYY-MM') AS month,
        COUNT(*)                                AS bookings,
        SUM(total_fare)                       AS revenue
    FROM v_clean_trips
    GROUP BY TO_CHAR(departure_date, 'YYYY-MM')
    order by month
),
ranked as (SELECT
    month, bookings, revenue,
    rank() over(order by revenue desc) as revenue_rank
FROM monthly 
ORDER BY revenue desc) 

select *  from ranked
where revenue_rank in (1,2,3,11,12,13) ;


/* 3D - Revenue by route per month (pivot)
Show one row per month with separate columns for the top 3 routes (RT001, RT002, RT003) using CASE WHEN + SUM.
*/

SELECT
    TO_CHAR(departure_date, 'YYYY-MM') AS month,

    SUM(
        CASE
            WHEN route_code = 'RT001' THEN total_fare
            ELSE 0
        END
    ) AS rt001_revenue,

    SUM(
        CASE
            WHEN route_code = 'RT002' THEN total_fare
            ELSE 0
        END
    ) AS rt002_revenue,

    SUM(
        CASE
            WHEN route_code = 'RT003' THEN total_fare
            ELSE 0
        END
    ) AS rt003_revenue

FROM v_clean_trips

GROUP BY TO_CHAR(departure_date, 'YYYY-MM')

ORDER BY month;



select* from bookings_staging;


/*4A - Top passenger cities
Show: passenger_city, total_bookings, total_seats, total_revenue,
 avg_fare. Order by total_bookings descending. Only include cities with 3+ bookings.
*/

SELECT
    passenger_city,
    COUNT(*) AS total_bookings,
    SUM(seats_booked) AS total_seats,
    SUM(total_fare) AS total_revenue,
    ROUND(AVG(total_fare), 2) AS avg_fare
FROM v_clean_trips
GROUP BY passenger_city
HAVING COUNT(*) >= 3
ORDER BY total_bookings DESC;

/*4B - Gender split and seat class preference
Show bookings and revenue broken down by passenger_gender 
and seat_class. Use a CASE WHEN pivot to show Economy and Business as separate columns.
*/

SELECT
    passenger_gender,
    COUNT(*) AS total_bookings,

    SUM(
        CASE
            WHEN seat_class = 'Economy' THEN total_fare
            ELSE 0
        END
    ) AS economy_revenue,

    SUM(
        CASE
            WHEN seat_class = 'Business' THEN total_fare
            ELSE 0
        END
    ) AS business_revenue

FROM v_clean_trips

GROUP BY passenger_gender
ORDER BY passenger_gender;

/* 4C - Satisfaction breakdown (CTE)
Using a CTE, count how many trips fall into each satisfaction 
category (Satisfied / Neutral / Unsatisfied / No Rating). 
Show count and percentage of total completed trips.
*/
WITH sat_counts AS (
    SELECT satisfaction, COUNT(*) AS cnt
    FROM v_clean_trips
    GROUP BY satisfaction
)
SELECT
    satisfaction,
    cnt,
    ROUND(cnt * 100.0 / SUM(cnt) OVER (), 1) AS pct
FROM sat_counts ORDER BY cnt DESC;

/*4D - Passenger quartiles by spend (NTILE)
Using a CTE for total spend per passenger, divide 
passengers into 4 quartiles using NTILE(4). 
Show: passenger_name, total_spent, quartile. Label quartile 4 as 'Top Spender'.
*/


--Calculate total spend per passenger

    SELECT
        passenger_name,
        SUM(total_fare) AS total_spent
    FROM v_clean_trips
    GROUP BY passenger_name

--Divide them into 4 quartiles
    
WITH passenger_spend AS (
    SELECT
        passenger_name,
        SUM(total_fare) AS total_spent
    FROM v_clean_trips
    GROUP BY passenger_name
)

SELECT
    passenger_name,
    total_spent,
    NTILE(4) OVER (
        ORDER BY total_spent desc
    ) AS quartile
FROM passenger_spend;

--Label Quartile 4 as "Top Spender"

WITH passenger_spend AS (
    SELECT
        passenger_name,
        SUM(total_fare) AS total_spent
    FROM v_clean_trips
    GROUP BY passenger_name
)

SELECT
    passenger_name,
    total_spent,
    NTILE(4) OVER (
        ORDER BY total_spent 
    ) AS quartile,
    CASE
        WHEN NTILE(4) OVER (ORDER BY total_spent) = 4
            THEN 'Top Spender'
        ELSE 'Regular'
    END AS spender_category
FROM passenger_spend
order by total_spent desc;






/* 5 - Cancellations & Lost Revenue

Overall status breakdown
*/

SELECT
    booking_status,
    COUNT(*) AS total_bookings
FROM safari_connect.bookings_staging
GROUP BY booking_status
ORDER BY total_bookings DESC;


/*Cancellation rate by route
Show: route_code, route, total_bookings, completed, cancelled, no_show, cancellation_rate_pct.
*/

SELECT
    route_code,
    route_from || ' → ' || route_to                           AS route,
    COUNT(*)                                                              AS total,
    SUM(CASE WHEN booking_status = 'Completed' THEN 1 ELSE 0 END) AS completed,
    SUM(CASE WHEN booking_status = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled,
    SUM(CASE WHEN booking_status = 'No Show'  THEN 1 ELSE 0 END) AS no_show,
    ROUND(SUM(CASE WHEN booking_status IN ('Cancelled','No Show')
             THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS cancel_rate_pct
FROM bookings
GROUP BY route_code, route_from, route_to
ORDER BY cancel_rate_pct DESC;


-- 5C - Revenue lost from cancellations and no-shows


---making column total_fare numeric
select total_fare  from bookings_staging;
							---showing the column

alter table bookings_staging
alter column total_fare type numeric
using total_fare ::numeric


SELECT
    booking_status,
    COUNT(*) AS total_bookings,
    SUM(total_fare) AS lost_revenue
FROM safari_connect.bookings_staging
WHERE booking_status IN ('Cancelled', 'No Show')
GROUP BY booking_status
ORDER BY lost_revenue DESC;


/*Question 6 - Operational Patterns

Business need: Operations wants to schedule more vehicles during peak times and fewer during quiet times.
*/
--6A - Revenue by day of week

SELECT
    EXTRACT(DOW FROM departure_date)          AS day_num,
    TO_CHAR(departure_date, 'Day')            AS day_name,
    COUNT(*)                                  AS total_bookings,
    SUM(total_fare)                         AS total_revenue,
    ROUND(AVG(total_fare), 2)          AS avg_booking_value
FROM v_clean_trips
GROUP BY EXTRACT(DOW FROM departure_date), TO_CHAR(departure_date, 'Day')
ORDER BY day_num;

/* 6B - Busiest departure times
Group by departure_time. Show which time slots carry the most passengers and generate the most revenue.
*/
alter table safari_connect.bookings_staging
alter column seats_booked type numeric
using seats_booked ::numeric;



SELECT
    departure_time,
    sum(seats_booked) AS total_passengers,
    SUM(total_fare) AS total_revenue
FROM safari_connect.bookings_staging
GROUP BY departure_time
ORDER BY total_passengers DESC;


select* from v_clean_trips;



/*6C - Seat utilisation by vehicle type
Compare how full each vehicle type typically runs. Show: vehicle_type, avg_seats_booked, and a label - 'High Load' if avg > 3, 'Medium Load' if 2-3, 'Low Load' if below 2.
*/

SELECT
    vehicle_type,
    ROUND(AVG(seats_booked), 2) AS avg_seats_booked,
    CASE
        WHEN AVG(seats_booked) > 3 THEN 'High Load'
        WHEN AVG(seats_booked) >= 2 THEN 'Medium Load'
        ELSE 'Low Load'
    END AS load_label
FROM bookings_staging
GROUP BY vehicle_type
order by avg_seats_booked desc;




--Create Your Views - Hand Off to BI Developer


-- View 1: Route performance
CREATE OR REPLACE VIEW v_route_performance AS
-- paste your 1A query here
SELECT
    route_code,
    route_from || ' → ' || route_to      AS route,
    COUNT(*)                              AS total_bookings,
    SUM(seats_booked)                   AS total_seats,
    SUM(total_fare)                     AS total_revenue,
    ROUND(AVG(fare_per_seat), 2)     AS avg_fare,
    ROUND(AVG(trip_rating), 2)       AS avg_rating
FROM v_clean_trips
GROUP BY route_code, route_from, route_to
ORDER BY total_revenue DESC;



-- View 2: Driver performance
CREATE OR REPLACE VIEW v_driver_performance AS
-- paste your 2A query here

SELECT
    driver_name,
    COUNT(*) AS total_trips,
    SUM(seats_booked) AS total_seats,
    SUM(total_fare) AS total_revenue,
    AVG(driver_rating) AS avg_driver_rating,
    ROUND(AVG(trip_rating), 2) AS avg_trip_rating
FROM v_clean_trips vct
GROUP BY vct.driver_name
ORDER BY SUM(total_fare) DESC;


-- View 3: Monthly revenue trend
CREATE OR REPLACE VIEW v_monthly_revenue AS
-- paste your 3A query (the CTE) here

WITH monthly AS (
    SELECT
        TO_CHAR(departure_date, 'YYYY-MM') AS month,
        COUNT(*)                                AS bookings,
        SUM(total_fare)                       AS revenue
    FROM v_clean_trips
    GROUP BY TO_CHAR(departure_date, 'YYYY-MM')
)
SELECT
    month, bookings, revenue,
    LAG(revenue) OVER (ORDER BY month)   AS prev_month,
    revenue - LAG(revenue) OVER (ORDER BY month)    AS change,
    ROUND((revenue - LAG(revenue) OVER (ORDER BY month))
        / NULLIF(LAG(revenue) OVER (ORDER BY month),0) * 100, 1)  AS change_pct
FROM monthly ORDER BY month;

-- View 4: Cancellation analysis
CREATE OR REPLACE VIEW v_cancellation_analysis AS
-- paste your 5B query here

SELECT
    route_code,
    route_from || ' → ' || route_to                           AS route,
    COUNT(*)                                                              AS total,
    SUM(CASE WHEN booking_status = 'Completed' THEN 1 ELSE 0 END) AS completed,
    SUM(CASE WHEN booking_status = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled,
    SUM(CASE WHEN booking_status = 'No Show'  THEN 1 ELSE 0 END) AS no_show,
    ROUND(SUM(CASE WHEN booking_status IN ('Cancelled','No Show')
             THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS cancel_rate_pct
FROM bookings
GROUP BY route_code, route_from, route_to
ORDER BY cancel_rate_pct DESC;


-- View 5: Passenger city insights
CREATE OR REPLACE VIEW v_passenger_insights AS
-- paste your 4A query here


SELECT
    passenger_city,
    COUNT(*) AS total_bookings,
    SUM(seats_booked) AS total_seats,
    SUM(total_fare) AS total_revenue,
    ROUND(AVG(total_fare), 2) AS avg_fare
FROM v_clean_trips
GROUP BY passenger_city
HAVING COUNT(*) >= 3
ORDER BY total_bookings DESC;


--Add Indexes

CREATE INDEX idx_bookings_depdate
ON bookings (departure_date);

CREATE INDEX idx_bookings_route
ON bookings (route_code);

CREATE INDEX idx_bookings_driver
ON bookings (driver_name);

CREATE INDEX idx_bookings_status
ON bookings (booking_status);

CREATE INDEX idx_bookings_payment
ON bookings (payment_method);

CREATE INDEX idx_bookings_vehicle
ON bookings (vehicle_type);

CREATE INDEX idx_bookings_passcity
ON bookings (passenger_city);


SELECT
    tablename,
    indexname
FROM pg_indexes
WHERE schemaname = 'safari_connect';


