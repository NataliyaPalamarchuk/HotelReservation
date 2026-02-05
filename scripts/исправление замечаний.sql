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