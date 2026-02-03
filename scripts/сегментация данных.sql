--Агрегация и сегментация данных
--Запрос 1: разделение жильцов по сегментам "VIP", "Лояльный" и "Новичок"
SELECT 
    g.last_name AS 'Фамилия', 
    g.first_name AS 'Имя',
    COUNT(r.reservation_id) AS 'Кол.-во проживаний',
    SUM(p.amount) AS 'Всего затрачено',
    CASE 
        WHEN COUNT(r.reservation_id) > 3 AND SUM(p.amount) > 100000 THEN 'VIP'
        WHEN COUNT(r.reservation_id) > 1 AND SUM(p.amount) BETWEEN 50000 AND 100000 THEN 'Лояльный'
        ELSE 'Новичок'
    END AS 'Сегмент'
FROM prj_guests g
    JOIN prj_reservations r ON g.guest_id = r.guest_id
    JOIN prj_payments p ON r.reservation_id = p.reservation_id
GROUP BY g.guest_id, g.last_name, g.first_name
ORDER BY 3 DESC;

--Запрос 2: можно усложнить такое сегментирование и использовать классический RFM-анализ (Давность-Частота-Деньги)
SELECT 
    g.last_name AS 'Фамилия', 
    g.first_name AS 'Имя',
    --Recency (Давность) - от даты фактического заезда (check_in_fact)
    DATEDIFF(day, MAX(ci.check_in_fact), GETDATE()) AS 'Давность(дней)',
    --Frequency (Частота) - только те бронирования, по которым был реальный заезд
    COUNT(ci.check_in_id) AS 'Частота(визитов)',
    --Monetary (Деньги) - сумма платежей по факту проживания
    SUM(p.amount) AS 'Сумма',
    
    CASE 
        --клиент был недавно и часто посещает
        WHEN COUNT(ci.check_in_id) >= 2 AND DATEDIFF(day, MAX(ci.check_in_fact), GETDATE()) <= 30 THEN 'Активный лояльный'
        
        --был один раз и очень давно (фактически заехал, но не вернулся)
        WHEN COUNT(ci.check_in_id) = 1 AND DATEDIFF(day, MAX(ci.check_in_fact), GETDATE()) > 30 THEN 'Разовый (ушедший)'
        
        --много визитов, но последний был больше полугода назад
        WHEN COUNT(ci.check_in_id) >= 3 AND DATEDIFF(day, MAX(ci.check_in_fact), GETDATE()) > 180 THEN 'Спящий VIP'
        
        --оставил много денег за последний визит
        WHEN SUM(p.amount) > 40000 AND DATEDIFF(day, MAX(ci.check_in_fact), GETDATE()) <= 30 THEN 'Ценный гость'
        
        ELSE 'Прочие'
    END AS 'RFM-сегмент(факт.)'

FROM prj_guests g
    JOIN prj_reservations r ON g.guest_id = r.guest_id
    --INNER JOIN, чтобы исключить брони без заезда
    INNER JOIN prj_check_info ci ON r.reservation_id = ci.reservation_id
    JOIN prj_payments p ON r.reservation_id = p.reservation_id
GROUP BY g.guest_id, g.last_name, g.first_name
ORDER BY 3 ASC;

--Запрос 3: Анализ популярности и доходности услуг. Сегментирование дополнительных услуг, чтобы понять, какие из них приносят основной доход.
SELECT 
    s.service_name AS 'Услуга',
    SUM(gs.quantity) AS 'Кол.-во заказов',
    SUM(gs.quantity * s.service_price) AS 'Выручка',
    CASE
        --если выручка по услуге > 20% от общей выручки - закон Парето: «20% видов услуг приносят 80% всей выручки»
        WHEN SUM(gs.quantity * s.service_price) > (SELECT SUM(quantity * service_price) * 0.2 FROM prj_guest_services JOIN prj_services ON prj_guest_services.service_id = prj_services.service_id) THEN 'Ключевой актив'
        ELSE 'Второстепенная услуга'
    END AS 'Категория'
FROM prj_services s
LEFT JOIN prj_guest_services gs ON s.service_id = gs.service_id
GROUP BY s.service_id, s.service_name;

--Запрос 4: Сегментация по загрузке отелей. Анализ того, насколько эффективно используются разные типы номеров в разных отелях.
--переменная, чтобы подставить любой месяц
DECLARE @DaysInMonth INT = DAY(EOMONTH(GETDATE()));
WITH HotelCapacity AS (
    --сколько ночей может продать отель за @DaysInMonth дней
    SELECT 
        h.hotel_id,
        h.hotel_name,
        rt.room_type_id,
        rt.type_name,
        COUNT(r.room_id) AS total_rooms,
        --емкость за @DaysInMonth
        COUNT(r.room_id) * @DaysInMonth AS potential_nights
    FROM prj_hotels h
        JOIN prj_rooms r ON h.hotel_id = r.hotel_id
        JOIN prj_room_types rt ON r.room_type_id = rt.room_type_id
    GROUP BY h.hotel_id, h.hotel_name, rt.room_type_id, rt.type_name
),
ActualOccupancy AS (
    --сколько ночей было фактически прожито (из таблицы check_info)
    SELECT 
        r.hotel_id,
        room.room_type_id,
        SUM(DATEDIFF(day, ci.check_in_fact, ISNULL(ci.check_out_fact, GETDATE()))) AS actual_nights,
        AVG(p.price) AS avg_real_price
    FROM prj_reservations r
        JOIN prj_rooms room ON room.room_id = r.room_id
        JOIN prj_check_info ci ON r.reservation_id = ci.reservation_id
        JOIN prj_hotel_room_prices p ON r.hotel_id = p.hotel_id AND room.room_type_id = p.room_type_id
    --анализ за последние @DaysInMonth дней
    WHERE ci.check_in_fact >= DATEADD(day, -@DaysInMonth, GETDATE())
    GROUP BY r.hotel_id, room.room_type_id
)
SELECT 
    hc.hotel_name AS "Отель",
    hc.type_name AS "Категория номера",
    hc.total_rooms AS "Кол-во номеров",
    ISNULL(ao.actual_nights, 0) AS "Продано ночей",
    hc.potential_nights AS "Емкость за мес.",
    CAST(ISNULL(ao.actual_nights, 0) * 100.0 / hc.potential_nights AS DECIMAL(10,2)) AS "Загрузка %",
    CASE 
        WHEN (ISNULL(ao.actual_nights, 0) * 100.0 / hc.potential_nights) > 35 THEN 'Высокий спрос (Пора повышать цены)'
        WHEN (ISNULL(ao.actual_nights, 0) * 100.0 / hc.potential_nights) BETWEEN 30 AND 35 THEN 'Оптимально'
        WHEN (ISNULL(ao.actual_nights, 0) * 100.0 / hc.potential_nights) BETWEEN 10 AND 29 THEN 'Недозагрузка (Нужны акции)'
        ELSE 'Критический простой'
    END AS "Маркетинговая стратегия"
FROM HotelCapacity hc
    LEFT JOIN ActualOccupancy ao ON hc.hotel_id = ao.hotel_id AND hc.room_type_id = ao.room_type_id
ORDER BY 6 DESC;
