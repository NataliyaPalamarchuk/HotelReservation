--ЗАМЕЧАНИЕ 1 - prj_reservations хранит и hotel_id, и room_id
--подумать про консистентность данных чтобы не получилось что room из одного отеля, а hotel_id другой

--в таблице prj_rooms надо добавить уникальность по 2м полям: hotel_id + room_id 
ALTER TABLE prj_rooms ADD CONSTRAINT UQ_Room_Hotel UNIQUE (hotel_id, room_id);


--также надо внести изменения в таблицу prj_reservations
--надо удалить старое ограничение, если оно есть
ALTER TABLE [dbo].[prj_reservations] DROP CONSTRAINT [FK__prj_reser__room___10111A78];

--исправить ошибочные данные, где отели не совпадают
UPDATE [dbo].[prj_reservations]
SET hotel_id = r.hotel_id
FROM [dbo].[prj_reservations] res
LEFT JOIN [dbo].[prj_rooms] r ON res.room_id = r.room_id
WHERE
    --отели не совпадают
    res.hotel_id <> r.hotel_id;

--надо добавить новый составной ключ
ALTER TABLE [dbo].[prj_reservations] WITH CHECK 
ADD CONSTRAINT FK_Reservation_Room_Hotel 
FOREIGN KEY (hotel_id, room_id) 
REFERENCES [dbo].[prj_rooms] (hotel_id, room_id);


--ЗАМЕЧАНИЕ 2 - триггер овербукинга у вас сейчас INSTEAD OF INSERT. Но нет ничего про UPDATE. Можно сломать бронь апдейтом.
GO
CREATE OR ALTER TRIGGER trg_no_overbooking
ON prj_reservations
--должен срабатывать и при вставке, и при изменении
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN prj_reservations r ON r.room_id = i.room_id
        WHERE 
            --проверка пересечения дат
            i.check_in_plan < r.check_out_plan 
            AND i.check_out_plan > r.check_in_plan
            --не сравнение запись с самой собой при UPDATE
            AND i.reservation_id <> r.reservation_id
    )
    BEGIN
        RAISERROR (N'Ошибка: Номер уже забронирован на указанный период или пересекается с существующей бронью.', 16, 1);
        ROLLBACK TRANSACTION;
    END
END;
GO

--ЗАМЕЧАНИЕ 3 - триггер trg_AfterCheckIn - тут есть небольшая ошибка. Он берёт один @RoomID из inserted. Если вставят несколько строк — обновит только один номер.
CREATE OR ALTER TRIGGER trg_AfterCheckIn
ON prj_check_info
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE prj_rooms
    --'Занят'
    SET status_id = 2 
    FROM prj_rooms r
        JOIN prj_reservations res ON r.room_id = res.room_id
        JOIN inserted i ON res.reservation_id = i.reservation_id;
END;