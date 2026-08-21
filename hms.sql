

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET FOREIGN_KEY_CHECKS = 0;
START TRANSACTION;
SET time_zone = "+00:00";
SET NAMES utf8mb4;

-- Create and select database (matches Flask default DB_NAME=hms1; change both if needed)
CREATE DATABASE IF NOT EXISTS `hms1` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `hms1`;

-- Registration (Flask PROJECT/main.py): signup uses SQLAlchemy ORM — INSERT into `users`
-- plus `patient_profiles` or `doctor_profiles`. Triggers (e.g. trg_users_before_insert)
-- and CHECK constraints apply the same as for `sp_register_user` below. The procedure is
-- kept for DBMS coursework, manual MySQL testing, and demos.
-- SECTION 1: DDL — DROP EXISTING TABLES (Clean Slate)

DROP TABLE IF EXISTS `audit_log`;
DROP TABLE IF EXISTS `appointments`;
DROP TABLE IF EXISTS `prescriptions`;
DROP TABLE IF EXISTS `patient_profiles`;
DROP TABLE IF EXISTS `doctor_profiles`;
DROP TABLE IF EXISTS `departments`;
DROP TABLE IF EXISTS `slots`;
DROP TABLE IF EXISTS `users`;

-- SECTION 2: DDL — CREATE NORMALIZED TABLES (3NF/BCNF)
--
-- Normalization rationale:
--   Original: patients stored dept as string, no FK to doctors,
--             no separation of user auth from profile data.
--   1NF  : All columns atomic, no repeating groups.
--   2NF  : No partial dependencies (all tables use surrogate PKs).
--   3NF  : Transitive deps removed — dept separated into its own
--           table; slot types extracted; user auth separated from
--           patient/doctor profile data.
--   BCNF : Every determinant is a candidate key in each table.

-- 2.1  DEPARTMENTS  (extracted to eliminate transitive dependency
--      dept_name → dept_head that existed in original patients table)

CREATE TABLE `departments` (
    `dept_id`    INT(11)      NOT NULL AUTO_INCREMENT,
    `dept_name`  VARCHAR(100) NOT NULL,
    `dept_head`  VARCHAR(100)          DEFAULT NULL,  -- optional
    PRIMARY KEY (`dept_id`),
    UNIQUE KEY `uq_dept_name` (`dept_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Lookup table for hospital departments (3NF: removes dept transitive dependency)';

-- 2.2  SLOTS  (new lookup — eliminates repeating 'morning'/'evening'
--      string literals scattered across patients rows)

CREATE TABLE `slots` (
    `slot_id`   INT(11)     NOT NULL AUTO_INCREMENT,
    `slot_name` VARCHAR(50) NOT NULL,
    `start_time` TIME       NOT NULL,
    `end_time`   TIME       NOT NULL,
    PRIMARY KEY (`slot_id`),
    UNIQUE KEY `uq_slot_name` (`slot_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Appointment slot lookup (morning / evening / night)';

-- 2.3  USERS  (authentication only — separated from profile data)

CREATE TABLE `users` (
    `user_id`   INT(11)       NOT NULL AUTO_INCREMENT,
    `username`  VARCHAR(50)   NOT NULL,
    `usertype`  ENUM('Admin','Doctor','Patient') NOT NULL DEFAULT 'Patient',
    `email`     VARCHAR(100)  NOT NULL,
    `password`  VARCHAR(1000) NOT NULL,
    `is_active` TINYINT(1)    NOT NULL DEFAULT 1,
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`user_id`),
    UNIQUE KEY `uq_user_email` (`email`),
    CONSTRAINT `chk_user_email` CHECK (`email` LIKE '%@%.%')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='User authentication table (separated from profile — 3NF)';

-- 2.4  DOCTOR_PROFILES  (profile data separated from auth)

CREATE TABLE `doctor_profiles` (
    `doctor_id`   INT(11)      NOT NULL AUTO_INCREMENT,
    `user_id`     INT(11)      NOT NULL,              -- FK → users
    `dept_id`     INT(11)      NOT NULL,              -- FK → departments
    `full_name`   VARCHAR(100) NOT NULL,
    `phone`       VARCHAR(15)           DEFAULT NULL,
    `qualification` VARCHAR(100)        DEFAULT NULL,
    `experience_yrs` SMALLINT           DEFAULT 0,
    PRIMARY KEY (`doctor_id`),
    UNIQUE KEY `uq_doc_user` (`user_id`),
    CONSTRAINT `fk_doc_user`  FOREIGN KEY (`user_id`) REFERENCES `users`(`user_id`) ON DELETE CASCADE,
    CONSTRAINT `fk_doc_dept`  FOREIGN KEY (`dept_id`) REFERENCES `departments`(`dept_id`) ON UPDATE CASCADE,
    CONSTRAINT `chk_exp`      CHECK (`experience_yrs` >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Doctor profile — linked to users and departments';

-- 2.5  PATIENT_PROFILES  (profile data separated from auth)

CREATE TABLE `patient_profiles` (
    `patient_id`  INT(11)      NOT NULL AUTO_INCREMENT,
    `user_id`     INT(11)      NOT NULL,              -- FK → users
    `full_name`   VARCHAR(100) NOT NULL,
    `gender`      ENUM('Male','Female','Other') NOT NULL,
    `dob`         DATE                  DEFAULT NULL,
    `phone`       VARCHAR(15)  NOT NULL,
    `address`     VARCHAR(255)          DEFAULT NULL,
    PRIMARY KEY (`patient_id`),
    UNIQUE KEY `uq_pat_user` (`user_id`),
    CONSTRAINT `fk_pat_user`  FOREIGN KEY (`user_id`) REFERENCES `users`(`user_id`) ON DELETE CASCADE,
    CONSTRAINT `chk_phone_len` CHECK (CHAR_LENGTH(`phone`) >= 10)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Patient profile — linked to users table';

-- 2.6  APPOINTMENTS  (was "patients" — now properly relational)
--      Replaces the flat "patients" table; dept derived via
--      doctor_profiles to avoid redundancy (BCNF compliance).

CREATE TABLE `appointments` (
    `appt_id`    INT(11)      NOT NULL AUTO_INCREMENT,
    `patient_id` INT(11)      NOT NULL,              -- FK → patient_profiles
    `doctor_id`  INT(11)      NOT NULL,              -- FK → doctor_profiles
    `slot_id`    INT(11)      NOT NULL,              -- FK → slots
    `appt_date`  DATE         NOT NULL,
    `disease`    VARCHAR(100) NOT NULL,
    `status`     ENUM('Scheduled','Completed','Cancelled') NOT NULL DEFAULT 'Scheduled',
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`appt_id`),
    CONSTRAINT `fk_appt_patient` FOREIGN KEY (`patient_id`) REFERENCES `patient_profiles`(`patient_id`) ON DELETE CASCADE,
    CONSTRAINT `fk_appt_doctor`  FOREIGN KEY (`doctor_id`)  REFERENCES `doctor_profiles`(`doctor_id`) ON UPDATE CASCADE,
    CONSTRAINT `fk_appt_slot`    FOREIGN KEY (`slot_id`)    REFERENCES `slots`(`slot_id`) ON UPDATE CASCADE,
    CONSTRAINT `chk_appt_date`   CHECK (`appt_date` >= '2000-01-01')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Core appointment/booking table — normalized, FK-constrained';

-- 2.7  PRESCRIPTIONS  (new — extends system scope)

CREATE TABLE `prescriptions` (
    `rx_id`      INT(11)       NOT NULL AUTO_INCREMENT,
    `appt_id`    INT(11)       NOT NULL,             -- FK → appointments
    `medicine`   VARCHAR(200)  NOT NULL,
    `dosage`     VARCHAR(100)  NOT NULL,
    `notes`      TEXT                   DEFAULT NULL,
    `issued_at`  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`rx_id`),
    CONSTRAINT `fk_rx_appt` FOREIGN KEY (`appt_id`) REFERENCES `appointments`(`appt_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Prescription records linked to appointments';

-- 2.8  AUDIT_LOG  (replaces "trigr" — more descriptive, typed)

CREATE TABLE `audit_log` (
    `log_id`     INT(11)      NOT NULL AUTO_INCREMENT,
    `table_name` VARCHAR(50)  NOT NULL,
    `record_id`  INT(11)      NOT NULL,
    `action`     ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    `performed_by_email` VARCHAR(100) DEFAULT NULL,
    `description` VARCHAR(255)        DEFAULT NULL,
    `timestamp`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`log_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Audit trail for all DML operations (replaces trigr)';

-- SECTION 3: DML — SEED DATA

-- Departments
INSERT INTO `departments` (`dept_name`, `dept_head`) VALUES
('Cardiology',        'Dr. Sharma'),
('Dermatology',       'Dr. Mehta'),
('Anaesthesiology',   'Dr. Rao'),
('Endocrinology',     'Dr. Iyer'),
('Infectious Disease','Dr. Khan'),
('Orthopaedics',      'Dr. Verma'),
('General Medicine',  'Dr. Gupta');

-- Slots
INSERT INTO `slots` (`slot_name`, `start_time`, `end_time`) VALUES
('Morning',   '08:00:00', '12:00:00'),
('Afternoon', '12:00:00', '16:00:00'),
('Evening',   '16:00:00', '20:00:00'),
('Night',     '20:00:00', '23:59:59');

-- Users (default logins after import)
-- Admin:   admin@hms.com   / Admin@123
-- Doctors: abc@gmail.com / Doctor@123
--          xyz@gmail.com / Doctor@123
--          pqr@gmail.com / Doctor@123
-- Patients: ijk@gmail.com / Patient@123
--           mno@gmail.com  / Patient@123
--           def@gmail.com / Patient@123
INSERT INTO `users` (`username`, `usertype`, `email`, `password`) VALUES
('admin',    'Admin',   'admin@hms.com',          'scrypt:32768:8:1$6KUOLbsgxUs4LW7d$d636f4ba79675f1b8365a3e95d335a628d303bfd2e1047ff2b720825cbb69dfaa8a5ac95583119f9dfd0833cd2843a86f8d9b8f55ec5578888d6c88a6c6bc80d'),
('abc',      'Doctor',  'abc@gmail.com',          'scrypt:32768:8:1$xihevkodbScOJ1fK$ce9e10b4e5d93ee153d272103a0eb146c52c8d9f3430185885a307225cc09ee9f162aa14b408bd23f31ba8255daeb0777977c48447243e90868328a7cb5a19fc'),
('xyz',      'Doctor',  'xyz@gmail.com',          'scrypt:32768:8:1$B14tNcV7hStMLwVv$dc5598a96d678f367933a6e002a4a55df1708aee639b90550a646f83c6420d9b35d6e748a62ddfc8e2f59dc6c59a8b1caf1db19a3d56c2c33a7682e713f59a43'),
('pqr',      'Doctor',  'pqr@gmail.com',          'scrypt:32768:8:1$QoNqCTaSXRFyA8Nc$6de4d0d66951fdbb7bf71513af13883947ae2a4951304348719532372456b5328fc94566d67167cd295df813cbc959b4e69ba639b58cfca717c10b7b1e40db37'),
('ijk',      'Patient', 'ijk@gmail.com',          'scrypt:32768:8:1$A3cGwCAlhciR5gF2$4d23cf69995ccbb9e96003054905fe4fda6cb67076cc646c6cc85ea754c61448613430d66df69b2637cf7d434e3680debaec3fe21e8fe75e91ceceb383c43427'),
('mno',      'Patient', 'mno@gmail.com',          'scrypt:32768:8:1$ggNRx93F35hmk5e0$8b85f0828c13656b010d5ea3a6899ed24cb042c3d6e378b8b1edd898df0249352bbc97f4ffe30bf45638c19e67bbb759e32aed1516f57421e89778b59378df21'),
('def',      'Patient', 'def@gmail.com',          'scrypt:32768:8:1$yJ137sdf242QK6te$feaa2c190e55c990ee44d925711db47b747d36aa63475bebce157e762765b2203d877f4c274fb1cd936a2a66f6367fcb8b0b5635d9d6b6b2b8aa878a012715f3');

-- Doctor profiles  (user_id references above inserts: abc=2, xyz=3, pqr=4)
INSERT INTO `doctor_profiles` (`user_id`, `dept_id`, `full_name`, `qualification`, `experience_yrs`) VALUES
(2, 1, 'Dr. Abc',     'MBBS, MD Cardiology',   8),
(3, 2, 'Dr. Xyz',     'MBBS, MD Dermatology',  5),
(4, 3, 'Dr. Pqr',     'MBBS, DA Anaesthesia',  6);

-- Patient profiles  (ijk=5, mno=6, def=7)
INSERT INTO `patient_profiles` (`user_id`, `full_name`, `gender`, `dob`, `phone`) VALUES
(5, 'Ijk',   'Female', '1998-05-12', '9874563210'),
(6, 'Mno',   'Female', '2000-07-19', '9874587496'),
(7, 'Def',   'Male',   '1995-03-10', '9874563210');

-- Appointments  (seed sample rows)
INSERT INTO `appointments` (`patient_id`, `doctor_id`, `slot_id`, `appt_date`, `disease`, `status`) VALUES
(3, 1, 3, '2020-11-18', 'Fever',  'Completed'),   -- def → Dr.Abc, cardiology evening
(3, 2, 3, '2020-11-05', 'Cold',   'Completed'),   -- def → Dr.Xyz, dermatology evening
(3, 1, 3, '2020-12-09', 'Fever',  'Completed'),   -- def → Dr.Abc, cardiology evening
(1, 3, 1, '2021-01-23', 'Corona', 'Completed'),   -- ijk → Dr.Pqr, anaesthesia morning
(1, 3, 3, '2021-01-23', 'Fever',  'Scheduled'),   -- ijk → Dr.Pqr, evening
(2, 3, 1, '2021-01-23', 'Corona', 'Completed'),   -- mno → Dr.Pqr, morning
(2, 3, 3, '2021-01-31', 'Fever',  'Scheduled');   -- mno → Dr.Pqr, evening

COMMIT;

-- SECTION 4: VIEWS — Abstracted query interfaces

-- 4.1 Full appointment details (join across 5 tables)
CREATE OR REPLACE VIEW `vw_appointment_details` AS
SELECT
    a.appt_id,
    pp.full_name       AS patient_name,
    u_pat.email        AS patient_email,
    pp.gender,
    pp.phone,
    dp.full_name       AS doctor_name,
    d.dept_name,
    s.slot_name,
    s.start_time       AS slot_start,
    a.appt_date,
    a.disease,
    a.status
FROM `appointments`     a
JOIN `patient_profiles` pp    ON a.patient_id = pp.patient_id
JOIN `users`            u_pat ON pp.user_id   = u_pat.user_id
JOIN `doctor_profiles`  dp    ON a.doctor_id  = dp.doctor_id
JOIN `departments`      d     ON dp.dept_id   = d.dept_id
JOIN `slots`            s     ON a.slot_id    = s.slot_id;

-- 4.2 Doctor workload summary
CREATE OR REPLACE VIEW `vw_doctor_workload` AS
SELECT
    dp.full_name   AS doctor_name,
    d.dept_name,
    COUNT(a.appt_id)                                          AS total_appointments,
    SUM(a.status = 'Completed')                               AS completed,
    SUM(a.status = 'Scheduled')                               AS upcoming,
    SUM(a.status = 'Cancelled')                               AS cancelled
FROM `doctor_profiles` dp
JOIN `departments`     d  ON dp.dept_id   = d.dept_id
LEFT JOIN `appointments` a ON dp.doctor_id = a.doctor_id
GROUP BY dp.doctor_id, dp.full_name, d.dept_name;

-- 4.3 Audit summary per table
CREATE OR REPLACE VIEW `vw_audit_summary` AS
SELECT
    table_name,
    action,
    COUNT(*) AS occurrences,
    MAX(timestamp) AS last_occurred
FROM `audit_log`
GROUP BY table_name, action;

-- SECTION 5: STORED PROCEDURES
-- (See note after USE hms1: Flask signup uses ORM; procedures remain for SQL clients / syllabus.)

DELIMITER $$

-- 5.1 Book a new appointment with validation
CREATE PROCEDURE `sp_book_appointment`(
    IN  p_patient_id   INT,
    IN  p_doctor_id    INT,
    IN  p_slot_id      INT,
    IN  p_date         DATE,
    IN  p_disease      VARCHAR(100),
    OUT p_appt_id      INT,
    OUT p_message      VARCHAR(255)
)
BEGIN
    DECLARE v_doc_exists  INT DEFAULT 0;
    DECLARE v_slot_exists INT DEFAULT 0;
    DECLARE v_duplicate   INT DEFAULT 0;

    -- Exception handler
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_appt_id = -1;
        SET p_message = 'ERROR: Transaction rolled back due to SQL exception.';
    END;

    START TRANSACTION;

    -- Validate doctor exists
    SELECT COUNT(*) INTO v_doc_exists
    FROM `doctor_profiles` WHERE `doctor_id` = p_doctor_id;

    -- Validate slot exists
    SELECT COUNT(*) INTO v_slot_exists
    FROM `slots` WHERE `slot_id` = p_slot_id;

    -- Check duplicate booking (same patient, doctor, date, slot)
    SELECT COUNT(*) INTO v_duplicate
    FROM `appointments`
    WHERE patient_id = p_patient_id
      AND doctor_id  = p_doctor_id
      AND slot_id    = p_slot_id
      AND appt_date  = p_date
      AND status     != 'Cancelled';

    IF v_doc_exists = 0 THEN
        ROLLBACK;
        SET p_appt_id = -1;
        SET p_message = 'ERROR: Doctor not found.';

    ELSEIF v_slot_exists = 0 THEN
        ROLLBACK;
        SET p_appt_id = -1;
        SET p_message = 'ERROR: Slot not found.';

    ELSEIF v_duplicate > 0 THEN
        ROLLBACK;
        SET p_appt_id = -1;
        SET p_message = 'ERROR: Duplicate appointment exists.';

    ELSEIF p_date < CURDATE() THEN
        ROLLBACK;
        SET p_appt_id = -1;
        SET p_message = 'ERROR: Cannot book appointment in the past.';

    ELSE
        INSERT INTO `appointments`
            (patient_id, doctor_id, slot_id, appt_date, disease, status)
        VALUES
            (p_patient_id, p_doctor_id, p_slot_id, p_date, p_disease, 'Scheduled');

        SET p_appt_id = LAST_INSERT_ID();
        COMMIT;
        SET p_message = CONCAT('SUCCESS: Appointment booked with ID ', p_appt_id);
    END IF;
END$$


-- 5.2 Cancel an appointment
CREATE PROCEDURE `sp_cancel_appointment`(
    IN  p_appt_id   INT,
    IN  p_email     VARCHAR(100),
    OUT p_message   VARCHAR(255)
)
BEGIN
    DECLARE v_exists INT DEFAULT 0;
    DECLARE v_status VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_message = 'ERROR: Cancellation failed due to SQL exception.';
    END;

    START TRANSACTION;

    SELECT COUNT(*), status
    INTO   v_exists, v_status
    FROM   `appointments`
    WHERE  appt_id = p_appt_id;

    IF v_exists = 0 THEN
        ROLLBACK;
        SET p_message = 'ERROR: Appointment not found.';
    ELSEIF v_status = 'Cancelled' THEN
        ROLLBACK;
        SET p_message = 'INFO: Appointment is already cancelled.';
    ELSEIF v_status = 'Completed' THEN
        ROLLBACK;
        SET p_message = 'ERROR: Cannot cancel a completed appointment.';
    ELSE
        UPDATE `appointments`
        SET    status = 'Cancelled'
        WHERE  appt_id = p_appt_id;

        INSERT INTO `audit_log`
            (table_name, record_id, action, performed_by_email, description)
        VALUES
            ('appointments', p_appt_id, 'UPDATE', p_email, 'Appointment cancelled');

        COMMIT;
        SET p_message = 'SUCCESS: Appointment cancelled.';
    END IF;
END$$

DROP PROCEDURE IF EXISTS `sp_register_user`$$

-- 5.3 Register a new user + profile in one transaction (same rows/columns as Flask ORM signup)
CREATE PROCEDURE `sp_register_user`(
    IN  p_username  VARCHAR(50),
    IN  p_usertype  VARCHAR(20),
    IN  p_email     VARCHAR(100),
    IN  p_password  VARCHAR(1000),
    IN  p_fullname  VARCHAR(100),
    IN  p_gender    VARCHAR(10),
    IN  p_phone     VARCHAR(15),
    IN  p_dob       DATE,
    IN  p_address   VARCHAR(255),
    OUT p_user_id   INT,
    OUT p_message   VARCHAR(255)
)
BEGIN
    DECLARE v_email_exists INT DEFAULT 0;
    DECLARE v_new_user_id  INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @sp_register_err = MESSAGE_TEXT;
        ROLLBACK;
        SET p_user_id = -1;
        SET p_message = LEFT(COALESCE(@sp_register_err, 'Registration failed.'), 255);
    END;

    START TRANSACTION;

    -- Match stored emails case-insensitively (consistent with trg_users_before_insert).
    SELECT COUNT(*) INTO v_email_exists
    FROM `users` WHERE LOWER(TRIM(`email`)) = LOWER(TRIM(p_email));

    IF v_email_exists > 0 THEN
        ROLLBACK;
        SET p_user_id = -1;
        SET p_message = 'ERROR: Email already registered.';
    ELSE
        INSERT INTO `users` (username, usertype, email, password)
        VALUES (p_username, p_usertype, p_email, p_password);

        SET v_new_user_id = LAST_INSERT_ID();

        IF p_usertype = 'Patient' THEN
            INSERT INTO `patient_profiles` (user_id, full_name, gender, phone, dob, address)
            VALUES (v_new_user_id, p_fullname, p_gender, p_phone, p_dob, p_address);
        END IF;

        COMMIT;
        SET p_user_id = v_new_user_id;
        SET p_message = CONCAT('SUCCESS: User registered with ID ', v_new_user_id);
    END IF;
END$$
-- Manual test (patient; use NULL for optional dob/address):
--   SET @u := 0; SET @m := '';
--   CALL sp_register_user('demo','Patient','demo@example.com','<password_hash>','Demo User','Male','9876543210', NULL, NULL, @u, @m);
--   SELECT @u AS new_user_id, @m AS msg;


-- 5.4 Get all appointments for a patient using cursor (cursor demo)
CREATE PROCEDURE `sp_patient_appointment_history`(
    IN p_patient_id INT
)
BEGIN
    DECLARE v_appt_id   INT;
    DECLARE v_doc_name  VARCHAR(100);
    DECLARE v_dept      VARCHAR(100);
    DECLARE v_date      DATE;
    DECLARE v_disease   VARCHAR(100);
    DECLARE v_status    VARCHAR(20);
    DECLARE v_done      INT DEFAULT 0;

    -- Cursor over patient's appointments
    DECLARE cur_appts CURSOR FOR
        SELECT a.appt_id, dp.full_name, d.dept_name,
               a.appt_date, a.disease, a.status
        FROM   `appointments`     a
        JOIN   `doctor_profiles`  dp ON a.doctor_id = dp.doctor_id
        JOIN   `departments`      d  ON dp.dept_id  = d.dept_id
        WHERE  a.patient_id = p_patient_id
        ORDER  BY a.appt_date DESC;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    -- Temp result table
    CREATE TEMPORARY TABLE IF NOT EXISTS `tmp_appt_history` (
        appt_id   INT,
        doctor    VARCHAR(100),
        dept      VARCHAR(100),
        appt_date DATE,
        disease   VARCHAR(100),
        status    VARCHAR(20)
    );

    TRUNCATE TABLE `tmp_appt_history`;

    OPEN cur_appts;

    read_loop: LOOP
        FETCH cur_appts INTO v_appt_id, v_doc_name, v_dept, v_date, v_disease, v_status;
        IF v_done = 1 THEN
            LEAVE read_loop;
        END IF;
        INSERT INTO `tmp_appt_history`
        VALUES (v_appt_id, v_doc_name, v_dept, v_date, v_disease, v_status);
    END LOOP;

    CLOSE cur_appts;

    SELECT * FROM `tmp_appt_history`;
    DROP TEMPORARY TABLE `tmp_appt_history`;
END$$


-- 5.5 Register doctor (user + doctor profile) in one operation
CREATE PROCEDURE `sp_register_doctor`(
    IN  p_username        VARCHAR(50),
    IN  p_email           VARCHAR(100),
    IN  p_password        VARCHAR(1000),
    IN  p_fullname        VARCHAR(100),
    IN  p_phone           VARCHAR(15),
    IN  p_dept_id         INT,
    IN  p_qualification   VARCHAR(100),
    IN  p_experience_yrs  SMALLINT,
    OUT p_user_id         INT,
    OUT p_doctor_id       INT,
    OUT p_message         VARCHAR(255)
)
BEGIN
    DECLARE v_email_exists INT DEFAULT 0;
    DECLARE v_dept_exists  INT DEFAULT 0;
    DECLARE v_new_user_id  INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_user_id = -1;
        SET p_doctor_id = -1;
        SET p_message = 'ERROR: Doctor registration failed.';
    END;

    START TRANSACTION;

    SELECT COUNT(*) INTO v_email_exists FROM `users` WHERE email = LOWER(p_email);
    SELECT COUNT(*) INTO v_dept_exists FROM `departments` WHERE dept_id = p_dept_id;

    IF v_email_exists > 0 THEN
        ROLLBACK;
        SET p_user_id = -1;
        SET p_doctor_id = -1;
        SET p_message = 'ERROR: Email already registered.';
    ELSEIF v_dept_exists = 0 THEN
        ROLLBACK;
        SET p_user_id = -1;
        SET p_doctor_id = -1;
        SET p_message = 'ERROR: Department not found.';
    ELSEIF p_experience_yrs < 0 THEN
        ROLLBACK;
        SET p_user_id = -1;
        SET p_doctor_id = -1;
        SET p_message = 'ERROR: Experience cannot be negative.';
    ELSE
        INSERT INTO `users` (username, usertype, email, password)
        VALUES (p_username, 'Doctor', LOWER(p_email), p_password);

        SET v_new_user_id = LAST_INSERT_ID();

        INSERT INTO `doctor_profiles`
            (user_id, dept_id, full_name, phone, qualification, experience_yrs)
        VALUES
            (v_new_user_id, p_dept_id, p_fullname, p_phone, p_qualification, p_experience_yrs);

        SET p_user_id = v_new_user_id;
        SET p_doctor_id = LAST_INSERT_ID();
        COMMIT;
        SET p_message = CONCAT('SUCCESS: Doctor registered with user_id=', p_user_id, ', doctor_id=', p_doctor_id);
    END IF;
END$$


-- 5.6 Create admin user (for controlled admin onboarding)
CREATE PROCEDURE `sp_create_admin_user`(
    IN  p_username  VARCHAR(50),
    IN  p_email     VARCHAR(100),
    IN  p_password  VARCHAR(1000),
    OUT p_user_id   INT,
    OUT p_message   VARCHAR(255)
)
BEGIN
    DECLARE v_email_exists INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_user_id = -1;
        SET p_message = 'ERROR: Admin creation failed.';
    END;

    START TRANSACTION;

    SELECT COUNT(*) INTO v_email_exists FROM `users` WHERE email = LOWER(p_email);

    IF v_email_exists > 0 THEN
        ROLLBACK;
        SET p_user_id = -1;
        SET p_message = 'ERROR: Email already registered.';
    ELSE
        INSERT INTO `users` (username, usertype, email, password)
        VALUES (p_username, 'Admin', LOWER(p_email), p_password);

        SET p_user_id = LAST_INSERT_ID();

        INSERT INTO `audit_log` (table_name, record_id, action, performed_by_email, description)
        VALUES ('users', p_user_id, 'INSERT', LOWER(p_email), 'Admin user created via sp_create_admin_user');

        COMMIT;
        SET p_message = CONCAT('SUCCESS: Admin created with user_id=', p_user_id);
    END IF;
END$$


-- 5.7 Update appointment status safely (doctor/admin operations)
CREATE PROCEDURE `sp_update_appointment_status`(
    IN  p_appt_id         INT,
    IN  p_new_status      VARCHAR(20),
    IN  p_actor_email     VARCHAR(100),
    OUT p_message         VARCHAR(255)
)
BEGIN
    DECLARE v_exists INT DEFAULT 0;
    DECLARE v_old_status VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_message = 'ERROR: Status update failed due to SQL exception.';
    END;

    START TRANSACTION;

    SELECT COUNT(*), status
    INTO v_exists, v_old_status
    FROM `appointments`
    WHERE appt_id = p_appt_id;

    IF v_exists = 0 THEN
        ROLLBACK;
        SET p_message = 'ERROR: Appointment not found.';
    ELSEIF p_new_status NOT IN ('Scheduled','Completed','Cancelled') THEN
        ROLLBACK;
        SET p_message = 'ERROR: Invalid status value.';
    ELSEIF v_old_status = p_new_status THEN
        ROLLBACK;
        SET p_message = 'INFO: Appointment already has this status.';
    ELSE
        UPDATE `appointments`
        SET status = p_new_status
        WHERE appt_id = p_appt_id;

        INSERT INTO `audit_log` (table_name, record_id, action, performed_by_email, description)
        VALUES (
            'appointments',
            p_appt_id,
            'UPDATE',
            LOWER(p_actor_email),
            CONCAT('Status changed from ', v_old_status, ' to ', p_new_status, ' via sp_update_appointment_status')
        );

        COMMIT;
        SET p_message = 'SUCCESS: Appointment status updated.';
    END IF;
END$$

DELIMITER ;

-- SECTION 6: STORED FUNCTIONS

DELIMITER $$

-- 6.1 Count total appointments for a doctor
CREATE FUNCTION `fn_doctor_appointment_count`(
    p_doctor_id INT
)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_count INT;
    SELECT COUNT(*) INTO v_count
    FROM `appointments`
    WHERE doctor_id = p_doctor_id;
    RETURN v_count;
END$$


-- 6.2 Get department name from dept_id
CREATE FUNCTION `fn_get_dept_name`(
    p_dept_id INT
)
RETURNS VARCHAR(100)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_name VARCHAR(100);
    SELECT dept_name INTO v_name
    FROM `departments`
    WHERE dept_id = p_dept_id;
    RETURN IFNULL(v_name, 'Unknown');
END$$


-- 6.3 Check if a patient has any scheduled upcoming appointments
CREATE FUNCTION `fn_has_upcoming_appointment`(
    p_patient_id INT
)
RETURNS TINYINT(1)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_count INT;
    SELECT COUNT(*) INTO v_count
    FROM `appointments`
    WHERE patient_id = p_patient_id
      AND status     = 'Scheduled'
      AND appt_date  >= CURDATE();
    RETURN IF(v_count > 0, 1, 0);
END$$

DELIMITER ;

-- SECTION 7: TRIGGERS
DELIMITER $$

-- 7.1 AFTER INSERT on appointments → audit log
CREATE TRIGGER `trg_appointment_after_insert`
AFTER INSERT ON `appointments`
FOR EACH ROW
BEGIN
    INSERT INTO `audit_log`
        (table_name, record_id, action, description)
    VALUES
        ('appointments', NEW.appt_id, 'INSERT',
         CONCAT('Appointment booked for patient_id=', NEW.patient_id,
                ' with doctor_id=', NEW.doctor_id,
                ' on ', NEW.appt_date));
END$$


-- 7.2 AFTER UPDATE on appointments → audit log
CREATE TRIGGER `trg_appointment_after_update`
AFTER UPDATE ON `appointments`
FOR EACH ROW
BEGIN
    INSERT INTO `audit_log`
        (table_name, record_id, action, description)
    VALUES
        ('appointments', NEW.appt_id, 'UPDATE',
         CONCAT('Status changed from ', OLD.status, ' to ', NEW.status));
END$$


-- 7.3 BEFORE DELETE on appointments → audit log
CREATE TRIGGER `trg_appointment_before_delete`
BEFORE DELETE ON `appointments`
FOR EACH ROW
BEGIN
    INSERT INTO `audit_log`
        (table_name, record_id, action, description)
    VALUES
        ('appointments', OLD.appt_id, 'DELETE',
         CONCAT('Appointment deleted: patient_id=', OLD.patient_id,
                ', doctor_id=', OLD.doctor_id));
END$$


-- 7.4 BEFORE INSERT on users → enforce lowercase email
CREATE TRIGGER `trg_users_before_insert`
BEFORE INSERT ON `users`
FOR EACH ROW
BEGIN
    SET NEW.email = LOWER(NEW.email);
END$$


-- 7.5 AFTER INSERT on patient_profiles → audit log
CREATE TRIGGER `trg_patient_after_insert`
AFTER INSERT ON `patient_profiles`
FOR EACH ROW
BEGIN
    INSERT INTO `audit_log`
        (table_name, record_id, action, description)
    VALUES
        ('patient_profiles', NEW.patient_id, 'INSERT',
         CONCAT('New patient profile created: ', NEW.full_name));
END$$


-- 7.6 AFTER DELETE on patient_profiles → audit log
CREATE TRIGGER `trg_patient_after_delete`
AFTER DELETE ON `patient_profiles`
FOR EACH ROW
BEGIN
    INSERT INTO `audit_log`
        (table_name, record_id, action, description)
    VALUES
        ('patient_profiles', OLD.patient_id, 'DELETE',
         CONCAT('Patient profile deleted: ', OLD.full_name));
END$$

DELIMITER ;

-- SECTION 8: SELECT QUERIES
--            (Joins, Subqueries, Aggregates, GROUP BY, HAVING)

-- 8.1 INNER JOIN — All appointment details
SELECT * FROM `vw_appointment_details`;

-- 8.2 LEFT JOIN — Doctors with or without appointments
SELECT
    dp.full_name   AS doctor,
    d.dept_name    AS department,
    COUNT(a.appt_id) AS total_bookings
FROM `doctor_profiles` dp
JOIN  `departments`    d  ON dp.dept_id  = d.dept_id
LEFT JOIN `appointments` a ON dp.doctor_id = a.doctor_id
GROUP BY dp.doctor_id, dp.full_name, d.dept_name
ORDER BY total_bookings DESC;

-- 8.3 Subquery — Patients who have more than 2 appointments
SELECT full_name, phone
FROM `patient_profiles`
WHERE patient_id IN (
    SELECT patient_id
    FROM   `appointments`
    GROUP  BY patient_id
    HAVING COUNT(*) > 2
);

-- 8.4 Aggregate — appointments per department
SELECT
    d.dept_name,
    COUNT(a.appt_id)           AS total,
    SUM(a.status='Scheduled')  AS scheduled,
    SUM(a.status='Completed')  AS completed,
    SUM(a.status='Cancelled')  AS cancelled
FROM `departments`    d
JOIN `doctor_profiles` dp ON d.dept_id   = dp.dept_id
JOIN `appointments`    a  ON dp.doctor_id = a.doctor_id
GROUP BY d.dept_id, d.dept_name
HAVING total > 0
ORDER BY total DESC;

-- 8.5 Scalar subquery — most busy doctor
SELECT full_name AS busiest_doctor,
       fn_doctor_appointment_count(doctor_id) AS appt_count
FROM `doctor_profiles`
ORDER BY appt_count DESC
LIMIT 1;

-- 8.6 Function usage
SELECT fn_get_dept_name(1) AS dept_name_for_id_1;
SELECT fn_has_upcoming_appointment(1) AS ijk_has_upcoming;

-- SECTION 9: TRANSACTION EXAMPLES
--            (COMMIT, ROLLBACK, SAVEPOINT)

-- Example 1: Successful multi-step transaction
START TRANSACTION;

    SAVEPOINT before_prescription;

    INSERT INTO `prescriptions` (appt_id, medicine, dosage, notes)
    VALUES (1, 'Aspirin 75mg', 'Once daily after food', 'Review in 2 weeks');

    -- Simulate a check (in real app this would be conditional)
    -- ROLLBACK TO SAVEPOINT before_prescription;  -- would undo just prescription

    COMMIT;  -- persist changes

-- Example 2: Demonstrate ROLLBACK on error simulation
START TRANSACTION;

    UPDATE `appointments`
    SET    status = 'Completed'
    WHERE  appt_id = 2;

    SAVEPOINT after_status_update;

    -- If any subsequent step fails, rollback to savepoint
    -- ROLLBACK TO SAVEPOINT after_status_update;

    COMMIT;

-- SECTION 10: RE-ENABLE FOREIGN KEY CHECKS
SET FOREIGN_KEY_CHECKS = 1;
