--1. Анализ доходности отелей. Этот запрос считает общую выручку каждого отеля, количество бронирований и средний чек. Используется агрегация данных и Join.
SELECT 
    h.hotel_name AS 'Отель',
    COUNT(r.reservation_id) AS 'Всего бронирований',
    SUM(p.amount) AS 'Всего выручка',
    ROUND(AVG(p.amount), 2) AS 'Средний чек'
FROM prj_hotels h
    JOIN prj_reservations r ON h.hotel_id = r.hotel_id
    LEFT JOIN prj_payments p ON r.reservation_id = p.reservation_id
GROUP BY h.hotel_name
ORDER BY SUM(p.amount) DESC;

--2. Популярность доп. услуг по категориям. В данном запросе используется CTE, чтобы сначала подготовить данные о продажах услуг, а затем объединить их с каталогом для финального анализа.
WITH ServiceStats AS (
    SELECT 
        gs.service_id, 
        SUM(gs.quantity) AS total_qty,
        --подсчет выручки
        SUM(gs.quantity * s.service_price) AS revenue_per_service
    FROM prj_guest_services gs
    --таблица с ценами
    JOIN prj_services s ON gs.service_id = s.service_id
    GROUP BY gs.service_id
)
SELECT 
    s.service_name AS 'Доп. услуга',
    ss.total_qty AS 'Кол.-во заказов услуги',
    ss.revenue_per_service AS 'Выручка по услуге'
FROM prj_services s
    JOIN ServiceStats ss ON s.service_id = ss.service_id
WHERE
    --возьмем только прибыльные услуги
    ss.revenue_per_service > 1000
ORDER BY ss.total_qty DESC;

--3. Рейтинг самых прибыльных гостей. Запрос использует оконную функцию DENSE_RANK(), чтобы составить топ гостей по сумме всех их трат во всех отелях сети.
SELECT 
    g.first_name AS 'Имя', 
    g.last_name AS 'Фамилия',
    SUM(p.amount) AS 'Всего потрачено',
    --функция присваивает рейтинг по величине затраченной суммы, с большей суммой - рейтинг 1, и т.д.
    DENSE_RANK() OVER (ORDER BY SUM(p.amount) DESC) AS 'Рейтинг гостя'
FROM prj_guests g
    JOIN prj_reservations r ON g.guest_id = r.guest_id
    JOIN prj_payments p ON r.reservation_id = p.reservation_id
GROUP BY g.guest_id, g.first_name, g.last_name
ORDER BY 4 ASC;

--4. Отчет по «плану-факту» проживания. 
--ситуация "оверстей" - клиент остался дольше запланированной даты
UPDATE prj_check_info
    SET [check_out_fact] = '2026-03-15'
WHERE
    [check_in_id] = 34;

--ситуация, когда клиент выезжает раньше запланированного
UPDATE prj_check_info
    SET [check_out_fact] = '2026-03-07'
WHERE
    [check_in_id] = 36;

--Запрос выявляет случаи, когда гости задерживались дольше запланированного или уезжали раньше, что важно для планирования уборки и брони.
SELECT
    g.last_name + ' ' + g.first_name AS 'Гость',
    r.check_in_plan AS 'Плановая дата заезда',
    r.check_out_plan AS 'Плановая дата выезда',
    ci.check_in_fact AS 'Фактическая дата заезда',
    ci.check_out_fact AS 'Фактическая дата выезда',
    DATEDIFF(day, r.check_in_plan, r.check_out_plan) AS 'Запланировано дней проживания',
    DATEDIFF(day, ci.check_in_fact, ci.check_out_fact) AS 'Фактически дней проживания',
    DATEDIFF(day, r.check_out_plan, ci.check_out_fact) AS 'Разница в днях',
    IIF(DATEDIFF(day, r.check_out_plan, ci.check_out_fact) > 0, 
        'Клиент прожил дольше на ' + CAST(DATEDIFF(day, r.check_out_plan, ci.check_out_fact) AS NVARCHAR(3)) + ' дн.',
        'Клиент выехал раньше на ' + CAST(ABS(DATEDIFF(day, r.check_out_plan, ci.check_out_fact)) AS NVARCHAR(3)) + ' дн.')
    AS 'Статус'
FROM prj_reservations r
    JOIN prj_guests g ON r.guest_id = g.guest_id
    JOIN prj_check_info ci ON r.reservation_id = ci.reservation_id
WHERE
    ci.check_out_fact IS NOT NULL 
    AND r.check_out_plan <> CAST(ci.check_out_fact AS DATE);

--5. Поиск самых востребованных типов номеров в каждом отеле. Используется вложенный подзапрос для расчета процента загрузки конкретного типа номера относительно общего количества броней в отеле.
SELECT 
    h.hotel_name AS 'Отель',
    rt.type_name AS 'Категория номера',
    COUNT(r.reservation_id) AS 'Кол.-во бронирований',
    (SELECT COUNT(*) FROM prj_reservations WHERE hotel_id = h.hotel_id) AS 'Общее кол.-во броней',
    ROUND(CAST(COUNT(r.reservation_id) AS FLOAT) / 
        (SELECT COUNT(*) FROM prj_reservations WHERE hotel_id = h.hotel_id) * 100, 2) AS '% загрузки'
FROM prj_hotels h
    JOIN prj_rooms rm ON h.hotel_id = rm.hotel_id
    JOIN prj_room_types rt ON rm.room_type_id = rt.room_type_id
    JOIN prj_reservations r ON rm.room_id = r.room_id
GROUP BY h.hotel_id, h.hotel_name, rt.type_name
ORDER BY [Отель], [Кол.-во бронирований] DESC;

--6. Сверка задолженностей. Находит бронирования, по которым сумма оказанных услуг и стоимость проживания превышают фактически внесенные платежи. Используется Having и математический расчет.
SELECT
    r.reservation_id,
    g.guest_id,
    g.last_name + ' ' + g.first_name AS 'Гость',
    hp.price AS 'Цена',
    DATEDIFF(day, r.check_in_plan, r.check_out_plan) AS 'План.проживание(дн.)',
    --стоимость номера
    (hp.price * DATEDIFF(day, r.check_in_plan, r.check_out_plan)) AS 'План.стоимость номера',
    SUM(gs.quantity) AS 'Кол.-во оказ. услуг',
    ISNULL(SUM(gs.quantity * s.service_price), 0) AS 'Стоимость оказ.услуг',
    ISNULL(p.total_paid, 0) AS 'Всего оплачено',
    ((hp.price * DATEDIFF(day, r.check_in_plan, r.check_out_plan)) + ISNULL(SUM(gs.quantity * s.service_price), 0)) - ISNULL(p.total_paid, 0) AS 'Задолженность'
FROM prj_reservations r
    JOIN prj_guests g ON r.guest_id = g.guest_id
    LEFT JOIN prj_rooms room ON r.room_id = room.room_id
    JOIN prj_hotel_room_prices hp ON r.hotel_id = hp.hotel_id AND room.room_type_id = hp.room_type_id
    LEFT JOIN prj_check_info ci ON r.reservation_id = ci.reservation_id
    LEFT JOIN prj_guest_services gs ON ci.check_in_id = gs.check_in_id
    LEFT JOIN prj_services s ON gs.service_id = s.service_id
    LEFT JOIN 
        (SELECT reservation_id, SUM(amount) AS total_paid FROM prj_payments GROUP BY reservation_id) p 
        ON r.reservation_id = p.reservation_id
GROUP BY r.reservation_id, g.guest_id, g.last_name, g.first_name, hp.price, r.check_in_plan, r.check_out_plan, p.total_paid
--Having тут служит для проверки условия по агрегированным данным: что сумма плановой стоимости номера+стоимость оказанных услуг > фактически оплаченной суммы гостя
HAVING ((hp.price * DATEDIFF(day, r.check_in_plan, r.check_out_plan)) + ISNULL(SUM(gs.quantity * s.service_price), 0)) > ISNULL(p.total_paid, 0);

--оптимизированный вариант запроса 6 с использованием CTE без сложной группировки
--суммы по услугам
WITH ServiceTotals AS (
    SELECT 
        ci.reservation_id,
        SUM(gs.quantity) AS total_qty,
        SUM(gs.quantity * s.service_price) AS total_service_price
    FROM prj_check_info ci
    JOIN prj_guest_services gs ON ci.check_in_id = gs.check_in_id
    JOIN prj_services s ON gs.service_id = s.service_id
    GROUP BY ci.reservation_id
),
--платежи
PaymentTotals AS (
    SELECT 
        reservation_id, 
        SUM(amount) AS total_paid 
    FROM prj_payments 
    GROUP BY reservation_id
)
--теперь в основном запросе не обязательно использовать Having
SELECT
    r.reservation_id,
    g.guest_id,
    g.last_name + ' ' + g.first_name AS 'Гость',
    hp.price AS 'Цена',
    DATEDIFF(day, r.check_in_plan, r.check_out_plan) AS 'План.проживание(дн.)',
    (hp.price * DATEDIFF(day, r.check_in_plan, r.check_out_plan)) AS 'План.стоимость номера',
    ISNULL(st.total_qty, 0) AS 'Кол.-во оказ. услуг',
    ISNULL(st.total_service_price, 0) AS 'Стоимость оказ.услуг',
    ISNULL(pt.total_paid, 0) AS 'Всего оплачено',
    ((hp.price * DATEDIFF(day, r.check_in_plan, r.check_out_plan)) + ISNULL(st.total_service_price, 0)) - ISNULL(pt.total_paid, 0) AS 'Задолженность'
FROM prj_reservations r
    JOIN prj_guests g ON r.guest_id = g.guest_id
    LEFT JOIN prj_rooms room ON r.room_id = room.room_id
    JOIN prj_hotel_room_prices hp ON r.hotel_id = hp.hotel_id AND room.room_type_id = hp.room_type_id
    LEFT JOIN ServiceTotals st ON r.reservation_id = st.reservation_id
    LEFT JOIN PaymentTotals pt ON r.reservation_id = pt.reservation_id
WHERE 
    ((hp.price * DATEDIFF(day, r.check_in_plan, r.check_out_plan)) + ISNULL(st.total_service_price, 0)) > ISNULL(pt.total_paid, 0)
ORDER BY [Задолженность] DESC;

--7. ABC-анализ доп. услуг. A-самые прибыльные услуги, B-услуги со средней доходностью, C-не приносят денег
WITH ServiceRevenue AS (
    SELECT 
        s.service_name,
        SUM(gs.quantity * s.service_price) AS revenue,
        SUM(SUM(gs.quantity * s.service_price)) OVER() AS total_rev
    FROM prj_guest_services gs
    JOIN prj_services s ON gs.service_id = s.service_id
    GROUP BY s.service_name
),
RunningTotal AS (
    SELECT 
        service_name,
        revenue,
        SUM(revenue) OVER(ORDER BY revenue DESC) / total_rev * 100 AS cumulative_pct
    FROM ServiceRevenue
)
SELECT *,
    CASE 
        WHEN cumulative_pct <= 80 THEN 'A'
        WHEN cumulative_pct <= 95 THEN 'B'
        ELSE 'C'
    END AS abc_category

FROM RunningTotal;
