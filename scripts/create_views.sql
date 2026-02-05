-- VIEW1: список услуг по гостиницам в разрезе гостей. Может применяться в отчётах по доп. услугам, детализация чеков гостей и т.д.
CREATE VIEW prj_guest_services_by_hotel
AS
SELECT
    h.hotel_id,
    h.hotel_name,
    g.guest_id,
    CONCAT(g.last_name, ' ', g.first_name) AS guest_name,
    s.service_name,
    gs.service_date,
    gs.quantity,
    s.service_price,
    gs.quantity * s.service_price AS total_amount
FROM prj_guest_services gs
    JOIN prj_check_info ci ON gs.check_in_id = ci.check_in_id
    JOIN prj_reservations r ON ci.reservation_id = r.reservation_id
    JOIN prj_hotels h ON r.hotel_id = h.hotel_id
    JOIN prj_guests g ON r.guest_id = g.guest_id
    JOIN prj_services s ON gs.service_id = s.service_id;

--VIEW2: агрегированные услуги по гостю и гостинице. Сумма услуг одного гостя в одной гостинице. Реализовано с CTE. Применение: анализ популярности услуг.
GO
CREATE VIEW prj_guest_service_summary
AS
WITH ServiceCTE AS (
    SELECT
        h.hotel_id,
        h.hotel_name,
        g.guest_id,
        CONCAT(g.last_name, ' ', g.first_name) AS guest_name,
        s.service_name,
        gs.quantity * s.service_price AS service_amount
    FROM prj_guest_services gs
    JOIN prj_check_info ci ON gs.check_in_id = ci.check_in_id
    JOIN prj_reservations r ON ci.reservation_id = r.reservation_id
    JOIN prj_hotels h ON r.hotel_id = h.hotel_id
    JOIN prj_guests g ON r.guest_id = g.guest_id
    JOIN prj_services s ON gs.service_id = s.service_id
)
SELECT
    hotel_name,
    guest_name,
    service_name,
    SUM(service_amount) AS total_service_amount
FROM ServiceCTE
GROUP BY hotel_name, guest_name, service_name;

--VIEW3: доля услуг в общем чеке гостя. Используются оконные функции SUM() OVER (). Может применяться для анализа структуры расходов гостя, персональных предложений, маркетинговой аналитика
GO
CREATE VIEW prj_guest_service_share
AS
WITH TotalPerGuest AS (
    SELECT
        g.guest_id,
        CONCAT(g.last_name, ' ', g.first_name) AS guest_name,
        h.hotel_name,
        s.service_name,
        gs.quantity * s.service_price AS service_amount,
        SUM(gs.quantity * s.service_price) OVER (
            PARTITION BY g.guest_id, h.hotel_id
        ) AS total_guest_services
    FROM prj_guest_services gs
    JOIN prj_check_info ci ON gs.check_in_id = ci.check_in_id
    JOIN prj_reservations r ON ci.reservation_id = r.reservation_id
    JOIN prj_hotels h ON r.hotel_id = h.hotel_id
    JOIN prj_guests g ON r.guest_id = g.guest_id
    JOIN prj_services s ON gs.service_id = s.service_id
)
SELECT
    hotel_name,
    guest_name,
    service_name,
    service_amount,
    total_guest_services,
    CAST(service_amount * 100.0 / total_guest_services AS DECIMAL(5,2)) AS service_share_percent
FROM TotalPerGuest;

--VIEW4: ТОП-3 услуги по каждой гостинице (RANK). Применение: KPI гостиницы, оптимизация сервиса, отчёты руководству
GO
CREATE VIEW prj_top_services_by_hotel
AS
WITH ServiceRank AS (
    SELECT
        h.hotel_name,
        s.service_name,
        SUM(gs.quantity * s.service_price) AS revenue,
        RANK() OVER (
            PARTITION BY h.hotel_id
            ORDER BY SUM(gs.quantity * s.service_price) DESC
        ) AS service_rank
    FROM prj_guest_services gs
    JOIN prj_check_info ci ON gs.check_in_id = ci.check_in_id
    JOIN prj_reservations r ON ci.reservation_id = r.reservation_id
    JOIN prj_hotels h ON r.hotel_id = h.hotel_id
    JOIN prj_services s ON gs.service_id = s.service_id
    GROUP BY h.hotel_id, h.hotel_name, s.service_name
)
SELECT *
FROM ServiceRank
WHERE service_rank <= 3;

--VIEW5: средний чек услуг на гостя в гостинице
GO
CREATE VIEW prj_avg_service_check_by_hotel
AS
WITH GuestTotals AS (
    SELECT
        h.hotel_name,
        g.guest_id,
        SUM(gs.quantity * s.service_price) AS guest_service_total
    FROM prj_guest_services gs
    JOIN prj_check_info ci ON gs.check_in_id = ci.check_in_id
    JOIN prj_reservations r ON ci.reservation_id = r.reservation_id
    JOIN prj_hotels h ON r.hotel_id = h.hotel_id
    JOIN prj_guests g ON r.guest_id = g.guest_id
    JOIN prj_services s ON gs.service_id = s.service_id
    GROUP BY h.hotel_name, g.guest_id
)
SELECT
    hotel_name,
    AVG(guest_service_total) AS avg_service_check
FROM GuestTotals
GROUP BY hotel_name;

--Отчеты: view для отчета по гео-аналитике
GO
CREATE VIEW prj_Hotel_KPIs AS
WITH HotelKPIs AS (
    SELECT 
        h.hotel_id,
        h.hotel_name,
        --преобразование GEOGRAPHY в читаемые координаты
        h.location.Lat AS Latitude,
        h.location.Long AS Longitude,
        h.total_rooms,
        --доход (размер пузырька)
        SUM(p.amount) AS TotalRevenue,
        --загрузка (цвет пузырька)
        CAST(COUNT(DISTINCT ci.check_in_id) * 100.0 / (h.total_rooms * 30) AS DECIMAL(10,2)) AS OccupancyRate
    FROM prj_hotels h
    LEFT JOIN prj_reservations r ON h.hotel_id = r.hotel_id
    LEFT JOIN prj_check_info ci ON r.reservation_id = ci.reservation_id
    LEFT JOIN prj_payments p ON r.reservation_id = p.reservation_id
    --фильтр за последний месяц
    WHERE r.check_in_plan >= DATEADD(month, -1, GETDATE())
    GROUP BY h.hotel_id, h.hotel_name, h.location.Lat, h.location.Long, h.total_rooms
)
SELECT * FROM HotelKPIs;
