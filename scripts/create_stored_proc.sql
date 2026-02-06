--Отчеты: хранимая процедура для отчета "Комплексный Анализ доходности и эффективности (RevPAR)"
GO
CREATE PROCEDURE sp_Hotel_Analytics
    @StartDate DATE = NULL,
    @EndDate DATE = NULL,
    @HotelID NVARCHAR(50) = NULL
AS
-- DECLARE @StartDate DATE = NULL;
-- DECLARE @EndDate DATE = NULL;
-- DECLARE @HotelID NVARCHAR(50) = '1,2,3';

BEGIN
    SET NOCOUNT ON;

    --если даты не указаны, то текущий год
    SET @StartDate = ISNULL(@StartDate, DATEFROMPARTS(YEAR(GETDATE()), 1, 1));
    SET @EndDate = ISNULL(@EndDate, DATEFROMPARTS(YEAR(GETDATE()), 12, 31));

    WITH RoomRevenue AS (
        --доход от проживания (через платежи, привязанные к брони), должен брать только те платежи, что попали в период
        SELECT 
            r.hotel_id,
            r.reservation_id,
            SUM(p.amount) as total_paid
        FROM prj_reservations r
            JOIN prj_payments p ON r.reservation_id = p.reservation_id
        WHERE p.payment_date BETWEEN @StartDate AND @EndDate
        GROUP BY r.hotel_id, r.reservation_id
    ),
    ServiceRevenue AS (
        --доход от доп. услуг, тоже за период
        SELECT 
            res.hotel_id,
            SUM(gs.quantity * s.service_price) as service_total
        FROM prj_guest_services gs
            JOIN prj_services s ON gs.service_id = s.service_id
            JOIN prj_check_info ci ON gs.check_in_id = ci.check_in_id
            JOIN prj_reservations res ON ci.reservation_id = res.reservation_id
        WHERE gs.service_date BETWEEN @StartDate AND @EndDate
        GROUP BY res.hotel_id
    ),
    Occupancy AS (
        --количество фактически завершенных броней и ночей
        SELECT 
            r.hotel_id,
            COUNT(ci.reservation_id) as total_stays,
            SUM(DATEDIFF(day, ci.check_in_fact, ci.check_out_fact)) as total_nights
        FROM prj_reservations r
            JOIN prj_check_info ci ON r.reservation_id = ci.reservation_id
        WHERE ci.check_in_fact >= @StartDate AND ci.check_out_fact <= @EndDate
        GROUP BY hotel_id
    )
    
    SELECT 
        h.hotel_name AS 'Отель',
        h.stars AS 'Звезд',
        occ.total_stays AS 'Кол.-во бронирований',
        occ.total_nights AS 'Продано ночей',
        
        --платежи, доходность
        ISNULL(rev.total_room_income, 0) AS 'Доход от номеров',
        ISNULL(srv.service_total, 0) AS 'Доход от услуг',
        ISNULL(rev.total_room_income, 0) + ISNULL(srv.service_total, 0) AS 'Общая выручка',
        
        --KPI (Key Performance Indicators) - Ключевые показатели эффективности
        CASE 
            WHEN occ.total_nights > 0 THEN CAST(ISNULL(rev.total_room_income, 0) / occ.total_nights AS DECIMAL(10,2)) 
            ELSE 0
        --ADR (Average Daily Rate)
        END AS 'ADR (Средняя цена за ночь)',
        
        --эффективность использования фонда: RevPAR (Revenue Per Available Room) - доход на один доступный номер, учитывает и цену, и заполняемость
        --RevPAR = Общая выручка от номеров / Общее кол-во доступных номеров в периоде
        CAST((ISNULL(rev.total_room_income, 0) / (h.total_rooms * DATEDIFF(day, @StartDate, DATEADD(day, 1, @EndDate)))) AS DECIMAL(10,2)) AS 'RevPAR',

        --лучший гость
        (SELECT TOP 1 g.last_name + ' ' + g.first_name 
         FROM prj_guests g
            JOIN prj_reservations r ON g.guest_id = r.guest_id
         WHERE r.hotel_id = h.hotel_id
         GROUP BY g.guest_id, g.last_name, g.first_name
         ORDER BY COUNT(r.reservation_id) DESC) AS 'Самый лояльный гость'

    FROM prj_hotels h
        LEFT JOIN (SELECT hotel_id, SUM(total_paid) as total_room_income FROM RoomRevenue GROUP BY hotel_id) rev ON h.hotel_id = rev.hotel_id
        LEFT JOIN ServiceRevenue srv ON h.hotel_id = srv.hotel_id
        LEFT JOIN Occupancy occ ON h.hotel_id = occ.hotel_id
    WHERE (@HotelID IS NULL OR h.hotel_id = @HotelID)
    ORDER BY 'Общая выручка' DESC;
END;

EXEC sp_Hotel_Analytics --'20260101', '20261231', 1


--Отчеты: хранимая процедура для отчета "Ведомость контроля бронирования и статуса прибытия гостей"
CREATE PROCEDURE dbo.sp_GetBookedRoomsReport
    @TargetDate DATE,         --дата, на которую смотрим брони
    @HotelID NVARCHAR(50),             --фильтр по отелям
    @RoomTypeID NVARCHAR(50) = NULL    --фильтр по типам номеров (необязательный)
AS
BEGIN
    SET NOCOUNT ON;

    -- DECLARE @TargetDate DATE = '20260107'; --GETDATE();
    -- DECLARE @HotelID NVARCHAR(50) = '1,2,3';
    -- DECLARE @RoomTypeID NVARCHAR(50) = '1,2,3,4,5,6,7,8,9';

    SELECT 
        h.hotel_name AS [HotelName],
        r.room_number AS [RoomNumber],
        rt.type_name AS [RoomType],
        g.last_name + ' ' + g.first_name AS [GuestFullName],
        g.phone AS [GuestPhone],
        res.check_in_plan AS [CheckInPlan],
        res.check_out_plan AS [CheckOutPlan],
        ci.check_in_fact AS [CheckInFact],
        ci.check_out_fact AS [CheckOutFact],
        --стоимость проживания (цена * кол-во ночей)
        hp.price AS [DailyPrice],
        DATEDIFF(DAY, res.check_in_plan, res.check_out_plan) AS [Nights],
        (hp.price * DATEDIFF(DAY, res.check_in_plan, res.check_out_plan)) AS [TotalStayAmount],
        --статус для отчета
        CASE 
            --бронь есть, но гость не заехал
            WHEN ci.check_in_fact IS NULL THEN 'Не заехал'
            --бронь есть, но гость заехал позже запланированного
            WHEN CAST(ci.check_in_fact AS DATE) > res.check_in_plan THEN 'Просрочен заезд'
            WHEN res.check_in_plan = @TargetDate THEN 'Ожидается сегодня'
            ELSE 'Будущий резерв'
        END AS [ArrivalStatus]
    FROM prj_reservations res
        JOIN prj_hotels h ON res.hotel_id = h.hotel_id
        JOIN prj_rooms r ON res.room_id = r.room_id AND r.hotel_id = res.hotel_id
        JOIN prj_room_types rt ON r.room_type_id = rt.room_type_id
        JOIN prj_guests g ON res.guest_id = g.guest_id
        --ценs для конкретного отеля и типа номера
        JOIN prj_hotel_room_prices hp ON h.hotel_id = hp.hotel_id AND rt.room_type_id = hp.room_type_id
        --есть ли факт заселения
        LEFT JOIN prj_check_info ci ON res.reservation_id = ci.reservation_id
    WHERE 
        res.hotel_id IN (SELECT PH.[value] FROM string_split(@HotelID, ',') PH)
        --гость забронировал номер на эту дату
        AND @TargetDate BETWEEN res.check_in_plan AND res.check_out_plan
        --но запись о фактическом заезде отсутствует
        --AND ci.check_in_id IS NULL
        AND (@RoomTypeID IS NULL OR rt.room_type_id IN (SELECT PR.[value] FROM string_split(@RoomTypeID, ',') PR))
    ORDER BY 
        rt.type_name, r.room_number;

END;
GO

DECLARE @Today DATE = '20260107'; --GETDATE();
EXEC dbo.sp_GetBookedRoomsReport
    @TargetDate = @Today, 
    @HotelID = '1,2,3', 
    @RoomTypeID = '1,2,3'
