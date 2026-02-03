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

 


SELECT * FROM prj_Hotel_KPIs
