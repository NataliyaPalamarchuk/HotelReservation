------------------------------------------------------------------------------------
-- ТРИГГЕРЫ
------------------------------------------------------------------------------------

--Запрет пересечения бронирований
GO
CREATE TRIGGER trg_no_overbooking
ON prj_reservations
INSTEAD OF INSERT
AS
BEGIN
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN prj_reservations r
          ON r.room_id = i.room_id
         AND i.check_in_plan < r.check_out_plan
         AND i.check_out_plan > r.check_in_plan
    )
    BEGIN
        RAISERROR (N'Номер уже забронирован на указанный период', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END

    INSERT INTO prj_reservations
    (hotel_id, room_id, guest_id, check_in_plan, check_out_plan, reservation_date)
    SELECT hotel_id, room_id, guest_id, check_in_plan, check_out_plan, reservation_date
    FROM inserted;
END;
GO


--Автоматическое изменение статуса номера
CREATE TRIGGER trg_AfterCheckIn
ON prj_check_info
AFTER INSERT
AS
BEGIN
    --найти ID номера через связь с бронированием
    DECLARE @RoomID INT;
    SELECT @RoomID = r.room_id
    FROM prj_reservations r
    JOIN inserted i ON r.reservation_id = i.reservation_id;

    --обновить статус на &#39;Занят&#39; (ID статуса = 2)
    UPDATE prj_rooms
    SET status_id = 2
    WHERE room_id = @RoomID;
END;
