# Dbms-project-hospital-management-system# 
🏥 Hospital Management System

> A full-stack web application built with **Flask** and **MySQL**, developed as a DBMS course project (UCS310 · Semester 4 · Thapar Institute of Engineering and Technology).

The system demonstrates end-to-end database engineering — normalized schema design, stored procedures, triggers, functions, cursors, transactions, and a live web application that consumes all of it.

---

## 👥 Team

| Name | Roll Number |
|---|---|
| Krish Kumar | 1024170184 |
| Aditya Anand Boro | 1024170185 |
| Lavdeep Singh | 1024170197 |

---

## 📋 Table of Contents

- [Features](#features)
- [Tech Stack](#tech-stack)
- [Database Design](#database-design)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Default Credentials](#default-credentials)
- [Database Concepts Implemented](#database-concepts-implemented)
- [Role-Based Access](#role-based-access)

---

## ✨ Features

- **Patient portal** — register, book appointments, view appointment history, manage prescriptions
- **Doctor portal** — view assigned appointments, update appointment status
- **Admin dashboard** — manage doctors, patients, appointments; view audit log and doctor workload
- **Automated audit trail** — every INSERT, UPDATE, and DELETE on key tables is logged automatically via triggers
- **Atomic transactions** — all multi-step operations (register, book, cancel) are wrapped in transactions with full rollback on failure
- **Role-based access control** — Admin, Doctor, and Patient roles with separate views and permissions

---

## 🛠 Tech Stack

| Layer | Technology |
|---|---|
| Backend | Python · Flask 2.3.3 |
| ORM | Flask-SQLAlchemy 3.1.1 · SQLAlchemy 2.0.49 |
| Database | MySQL (InnoDB · utf8mb4) |
| DB Driver | PyMySQL 1.1.0 |
| Auth | Flask-Login 0.6.3 · Werkzeug password hashing |
| Frontend | Jinja2 templates · HTML · CSS |
| Config | python-dotenv 1.0.1 |

---

## 🗄 Database Design

### Tables (8 total — normalized to BCNF)

| Table | Purpose |
|---|---|
| `departments` | Lookup — hospital departments |
| `slots` | Lookup — appointment time slots (Morning / Afternoon / Evening / Night) |
| `users` | Authentication — stores hashed passwords, usertype |
| `doctor_profiles` | Doctor info linked to users + departments |
| `patient_profiles` | Patient demographics linked to users |
| `appointments` | Core booking table — links patient, doctor, slot, date |
| `prescriptions` | Prescriptions linked to appointments |
| `audit_log` | Automatic audit trail for all DML operations |

### Key Design Decisions

- **1NF** — eliminated repeating slot strings; extracted `slots` as a lookup table
- **2NF** — all tables use single-column surrogate PKs (`AUTO_INCREMENT`), removing partial dependencies
- **3NF** — separated user auth from profile data; extracted departments and slots to remove transitive dependencies
- **BCNF** — department is derived via `doctor_profiles → departments`, never stored redundantly in `appointments`

---

## 📁 Project Structure

```
Dbms-project-hospital-management-system/
│
├── PROJECT/
│   └── main.py               # Flask application (routes, models, auth)
│
├── hms.sql                   # Complete database script:
│                             #   §1 DROP existing tables
│                             #   §2 CREATE normalized tables (DDL)
│                             #   §3 Seed data (DML)
│                             #   §4 Views (3 views)
│                             #   §5 Stored Procedures (7)
│                             #   §6 Stored Functions (3)
│                             #   §7 Triggers (6)
│                             #   §8 SELECT queries (joins, subqueries, aggregates)
│                             #   §9 Transaction examples
│
├── requirements.txt          # Python dependencies
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites

- Python 3.9+
- MySQL 8.0+
- pip

### 1. Clone the repository

```bash
git clone https://github.com/Krish001122/Dbms-project-hospital-management-system.git
cd Dbms-project-hospital-management-system
```

### 2. Install Python dependencies

```bash
pip install -r requirements.txt
```

### 3. Set up the database

Open MySQL and run the SQL script to create the database, tables, views, procedures, functions, and triggers:

```bash
mysql -u root -p < hms.sql
```

This creates a database named `hms1` and populates it with seed data.

### 4. Configure environment variables

Create a `.env` file inside the `PROJECT/` directory:

```env
DB_USER=root
DB_PASSWORD=your_mysql_password
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=hms1
```

### 5. Run the application

```bash
cd PROJECT
python main.py
```

The app will be available at `http://127.0.0.1:5000`.

---

## 🔑 Default Credentials

After importing `hms.sql`, the following accounts are available:

| Role | Email | Password |
|---|---|---|
| Admin | admin@hms.com | Admin@123 |
| Doctor | abc@gmail.com | Doctor@123 |
| Doctor | xyz@gmail.com | Doctor@123 |
| Doctor | pqr@gmail.com | Doctor@123 |
| Patient | ijk@gmail.com | Patient@123 |
| Patient | mno@gmail.com | Patient@123 |
| Patient | def@gmail.com | Patient@123 |

---

## 🧠 Database Concepts Implemented

### DDL
- `CREATE TABLE` with `InnoDB` engine and `utf8mb4` charset
- `AUTO_INCREMENT` surrogate primary keys on all 8 tables
- `ENUM` types for `usertype`, `status`, `gender`, and `action`
- `CHECK` constraints — email format, phone length, experience ≥ 0, date ≥ 2000-01-01
- `UNIQUE` keys on email, dept_name, slot_name, and user–profile links
- `ON DELETE CASCADE` and `ON UPDATE CASCADE` for referential integrity

### DML & SELECT
- `INSERT` seed data for all tables
- `UPDATE` via stored procedures with validation
- `DELETE` with cascading cleanup
- `INNER JOIN` — `vw_appointment_details` joins 6 tables
- `LEFT JOIN` — `vw_doctor_workload` includes doctors with zero appointments
- Subquery with `HAVING COUNT(*) > 2` — patients with multiple appointments
- Aggregate queries with `GROUP BY`, `SUM`, and `COUNT` per department

### Views (3)
| View | Description |
|---|---|
| `vw_appointment_details` | 6-table join — full appointment info |
| `vw_doctor_workload` | Per-doctor appointment counts by status |
| `vw_audit_summary` | Grouped audit log by table and action |

### Stored Procedures (7)
| Procedure | Purpose |
|---|---|
| `sp_book_appointment` | Validates and books an appointment atomically |
| `sp_cancel_appointment` | Cancels appointment with status validation |
| `sp_register_user` | Registers patient user + profile in one transaction |
| `sp_register_doctor` | Registers doctor user + profile in one transaction |
| `sp_create_admin_user` | Creates admin and auto-logs the event |
| `sp_update_appointment_status` | Safely transitions status with audit logging |
| `sp_patient_appointment_history` | Fetches appointment history using an explicit cursor |

### Stored Functions (3)
| Function | Returns |
|---|---|
| `fn_doctor_appointment_count(doctor_id)` | Total appointments for a doctor |
| `fn_get_dept_name(dept_id)` | Department name (or 'Unknown') |
| `fn_has_upcoming_appointment(patient_id)` | 1 if patient has a scheduled future appointment |

### Triggers (6)
| Trigger | Event | Purpose |
|---|---|---|
| `trg_appointment_after_insert` | AFTER INSERT | Logs new booking to audit_log |
| `trg_appointment_after_update` | AFTER UPDATE | Logs status change to audit_log |
| `trg_appointment_before_delete` | BEFORE DELETE | Logs deletion to audit_log |
| `trg_users_before_insert` | BEFORE INSERT | Normalises email to lowercase |
| `trg_patient_after_insert` | AFTER INSERT | Logs new patient profile creation |
| `trg_patient_after_delete` | AFTER DELETE | Logs patient profile deletion |

### Transactions & Exception Handling
- All 7 stored procedures use `START TRANSACTION` / `COMMIT` / `ROLLBACK`
- `DECLARE EXIT HANDLER FOR SQLEXCEPTION` in every procedure — guarantees no partial commits on failure
- `SAVEPOINT` examples included in `hms.sql §9`

### Cursor
- Explicit cursor in `sp_patient_appointment_history` — `DECLARE` → `OPEN` → `FETCH` loop → `CLOSE` — results stored in a temporary table and returned as a result set

---

## 👤 Role-Based Access

| Feature | Admin | Doctor | Patient |
|---|:---:|:---:|:---:|
| View all appointments | ✅ | ❌ | ❌ |
| View own appointments | ✅ | ✅ | ✅ |
| Book appointment | ❌ | ❌ | ✅ |
| Cancel appointment | ✅ | ❌ | ✅ |
| Update appointment status | ✅ | ✅ | ❌ |
| Add / delete doctor | ✅ | ❌ | ❌ |
| Add admin | ✅ | ❌ | ❌ |
| View audit log | ✅ | ❌ | ❌ |
| View doctor workload | ✅ | ❌ | ❌ |
| Manage prescriptions | ✅ | ✅ | 👁 view only |

---

## 📄 License

This project was developed for academic purposes as part of UCS310 · DBMS · Thapar Institute of Engineering and Technology · Jan–May 2026.