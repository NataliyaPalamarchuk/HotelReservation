-- MS SQL SERVER
------------------------------------------------------------------------------------

USE master;
GO
IF EXISTS (SELECT * FROM sys.databases WHERE name = 'hotel_reserv') DROP DATABASE hotel_reserv;
GO
CREATE DATABASE hotel_reserv;
GO
USE hotel_reserv;
GO


-- ВСПОМОГАТЕЛЬНЫЕ СПРАВОЧНИКИ
------------------------------------------------------------------------------------

--Статусы номеров
CREATE TABLE prj_room_statuses (
    status_id INT PRIMARY KEY,
    status_name NVARCHAR(50) NOT NULL
);

--Способы оплаты
CREATE TABLE prj_payment_methods (
    payment_method_id INT PRIMARY KEY,
    method_name NVARCHAR(50) NOT NULL
);


-- ОТЕЛИ
------------------------------------------------------------------------------------

--Отели
CREATE TABLE prj_hotels (
    hotel_id INT PRIMARY KEY,
    hotel_name NVARCHAR(100) NOT NULL,
    address NVARCHAR(255),
    phone NVARCHAR(20),
    email NVARCHAR(100),
    stars INT CHECK (stars BETWEEN 1 AND 5),
    total_rooms INT CHECK (total_rooms > 0),
    location GEOGRAPHY
);

--Категории номеров
CREATE TABLE prj_room_types (
    room_type_id INT IDENTITY PRIMARY KEY,
    type_name NVARCHAR(50) NOT NULL,
    capacity INT CHECK (capacity > 0)
);

--Ценовая сетка
CREATE TABLE prj_hotel_room_prices (
    hotel_id INT NOT NULL,
    room_type_id INT NOT NULL,
    price DECIMAL(10,2) CHECK (price > 0),
    PRIMARY KEY (hotel_id, room_type_id),
    FOREIGN KEY (hotel_id) REFERENCES prj_hotels(hotel_id),
    FOREIGN KEY (room_type_id) REFERENCES prj_room_types(room_type_id)
);


------------------------------------------------------------------------------------

--Номера
CREATE TABLE prj_rooms (
    room_id INT IDENTITY PRIMARY KEY,
    hotel_id INT NOT NULL,
    room_type_id INT NOT NULL,
    room_number NVARCHAR(10) NOT NULL,
    floor INT,
    status_id INT NOT NULL,
    FOREIGN KEY (hotel_id) REFERENCES prj_hotels(hotel_id),
    FOREIGN KEY (room_type_id) REFERENCES prj_room_types(room_type_id),
    FOREIGN KEY (status_id) REFERENCES prj_room_statuses(status_id),
    CONSTRAINT UQ_Hotel_Room UNIQUE (hotel_id, room_number)
);

--Гости
CREATE TABLE prj_guests (
    guest_id INT IDENTITY PRIMARY KEY,
    first_name NVARCHAR(50),
    last_name NVARCHAR(50),
    passport_number NVARCHAR(20) UNIQUE,
    phone NVARCHAR(20),
    email NVARCHAR(100)
);

--Бронирование/заявки на бронь
CREATE TABLE prj_reservations (
    reservation_id INT IDENTITY PRIMARY KEY,
    hotel_id INT NOT NULL,
    room_id INT NOT NULL,
    guest_id INT NOT NULL,
    check_in_plan DATE NOT NULL,
    check_out_plan DATE NOT NULL,
    reservation_date DATETIME DEFAULT GETDATE(),
    CHECK (check_out_plan > check_in_plan),
    FOREIGN KEY (hotel_id) REFERENCES prj_hotels(hotel_id),
    FOREIGN KEY (room_id) REFERENCES prj_rooms(room_id),
    FOREIGN KEY (guest_id) REFERENCES prj_guests(guest_id)
);

--Журнал фактического пребывания
CREATE TABLE prj_check_info (
    check_in_id INT IDENTITY PRIMARY KEY,
    reservation_id INT UNIQUE,
    check_in_fact DATETIME,
    check_out_fact DATETIME,
    FOREIGN KEY (reservation_id) REFERENCES prj_reservations(reservation_id)
);


-- УСЛУГИ
------------------------------------------------------------------------------------

--Каталог услуг
CREATE TABLE prj_services (
    service_id INT IDENTITY PRIMARY KEY,
    service_name NVARCHAR(100),
    service_price DECIMAL(10,2) CHECK (service_price > 0)
);

--Потребленные услуги
CREATE TABLE prj_guest_services (
    guest_service_id INT IDENTITY PRIMARY KEY,
    check_in_id INT NOT NULL,
    service_id INT NOT NULL,
    service_date DATETIME DEFAULT GETDATE(),
    quantity INT DEFAULT 1 CHECK (quantity > 0),
    FOREIGN KEY (check_in_id) REFERENCES prj_check_info(check_in_id),
    FOREIGN KEY (service_id) REFERENCES prj_services(service_id)
);

--Оплаты
CREATE TABLE prj_payments (
    payment_id INT IDENTITY PRIMARY KEY,
    reservation_id INT NOT NULL,
    payment_date DATETIME DEFAULT GETDATE(),
    amount DECIMAL(10,2) CHECK (amount > 0),
    payment_method_id INT NOT NULL,
    FOREIGN KEY (reservation_id) REFERENCES prj_reservations(reservation_id),
    FOREIGN KEY (payment_method_id) REFERENCES prj_payment_methods(payment_method_id)
);
