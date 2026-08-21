from flask import Flask, render_template, request, session, redirect, url_for, flash
from flask_sqlalchemy import SQLAlchemy
from flask_login import (UserMixin, login_user, logout_user,
                         LoginManager, login_required, current_user)
from werkzeug.security import generate_password_hash, check_password_hash
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from datetime import date, datetime
from functools import wraps
from urllib.parse import quote_plus
import os
import sys

_ENV_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.env')

try:
    from dotenv import load_dotenv
    # So values from PROJECT/.env win over empty DB_* vars from the OS / IDE launch env.
    load_dotenv(_ENV_PATH, override=True)
except ImportError:
    pass

if not os.getenv('DATABASE_URL') and not os.path.isfile(_ENV_PATH):
    print(
        f'HMS: Missing {_ENV_PATH}. Copy .env.example to .env and set DB_PASSWORD. '
        "MySQL error 1045 'using password: NO' means the app sent an empty password.",
        file=sys.stderr,
    )
# ──────────────────────────────────────────────────────────
# APP SETUP
# ──────────────────────────────────────────────────────────
app = Flask(__name__)
app.secret_key = 'hmsprojects_secure_key'

login_manager = LoginManager(app)
login_manager.login_view = 'login'

def build_database_uri():
    """
    Build DB URI from environment variables.
    Default host is 127.0.0.1 (more reliable than localhost on Windows).
    """
    db_uri = os.getenv('DATABASE_URL')
    if db_uri:
        return db_uri

    db_user = (os.getenv('DB_USER') or 'root').strip()
    db_password = (os.getenv('DB_PASSWORD') or '').strip()
    db_host = (os.getenv('DB_HOST') or '127.0.0.1').strip()
    db_port = (os.getenv('DB_PORT') or '3306').strip()
    db_name = (os.getenv('DB_NAME') or 'hms1').strip()
    # Quote password so characters like @, :, / work in the URI.
    safe_pwd = quote_plus(db_password)
    return f'mysql+pymysql://{db_user}:{safe_pwd}@{db_host}:{db_port}/{db_name}'


app.config['SQLALCHEMY_DATABASE_URI'] = build_database_uri()
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)


# ──────────────────────────────────────────────────────────
# MODELS  (mirror the normalized tables)
# ──────────────────────────────────────────────────────────

class Department(db.Model):
    __tablename__ = 'departments'
    dept_id   = db.Column(db.Integer, primary_key=True)
    dept_name = db.Column(db.String(100), unique=True, nullable=False)
    dept_head = db.Column(db.String(100))
    # relationship
    doctors   = db.relationship('DoctorProfile', backref='department', lazy=True)


class Slot(db.Model):
    __tablename__ = 'slots'
    slot_id    = db.Column(db.Integer, primary_key=True)
    slot_name  = db.Column(db.String(50), unique=True, nullable=False)
    start_time = db.Column(db.Time, nullable=False)
    end_time   = db.Column(db.Time, nullable=False)


class User(UserMixin, db.Model):
    __tablename__ = 'users'
    user_id    = db.Column(db.Integer, primary_key=True)
    username   = db.Column(db.String(50), nullable=False)
    usertype   = db.Column(db.Enum('Admin', 'Doctor', 'Patient'), nullable=False)
    email      = db.Column(db.String(100), unique=True, nullable=False)
    password   = db.Column(db.String(1000), nullable=False)
    is_active  = db.Column(db.Boolean, default=True)
    # DB column is NOT NULL DEFAULT CURRENT_TIMESTAMP; omitting server_default makes SQLAlchemy send NULL.
    created_at = db.Column(db.DateTime, nullable=False, server_default=text('CURRENT_TIMESTAMP'))

    # Flask-Login requires get_id() to return user_id
    def get_id(self):
        return str(self.user_id)


class DoctorProfile(db.Model):
    __tablename__ = 'doctor_profiles'
    doctor_id       = db.Column(db.Integer, primary_key=True)
    user_id         = db.Column(db.Integer, db.ForeignKey('users.user_id'), nullable=False, unique=True)
    dept_id         = db.Column(db.Integer, db.ForeignKey('departments.dept_id'), nullable=False)
    full_name       = db.Column(db.String(100), nullable=False)
    phone           = db.Column(db.String(15))
    qualification   = db.Column(db.String(100))
    experience_yrs  = db.Column(db.SmallInteger, default=0)


class PatientProfile(db.Model):
    __tablename__ = 'patient_profiles'
    patient_id = db.Column(db.Integer, primary_key=True)
    user_id    = db.Column(db.Integer, db.ForeignKey('users.user_id'), nullable=False, unique=True)
    full_name  = db.Column(db.String(100), nullable=False)
    gender     = db.Column(db.Enum('Male', 'Female', 'Other'), nullable=False)
    dob        = db.Column(db.Date)
    phone      = db.Column(db.String(15), nullable=False)
    address    = db.Column(db.String(255))


class Appointment(db.Model):
    __tablename__ = 'appointments'
    appt_id    = db.Column(db.Integer, primary_key=True)
    patient_id = db.Column(db.Integer, db.ForeignKey('patient_profiles.patient_id'), nullable=False)
    doctor_id  = db.Column(db.Integer, db.ForeignKey('doctor_profiles.doctor_id'), nullable=False)
    slot_id    = db.Column(db.Integer, db.ForeignKey('slots.slot_id'), nullable=False)
    appt_date  = db.Column(db.Date, nullable=False)
    disease    = db.Column(db.String(100), nullable=False)
    status     = db.Column(db.Enum('Scheduled', 'Completed', 'Cancelled'), default='Scheduled')
    created_at = db.Column(db.DateTime, nullable=False, server_default=text('CURRENT_TIMESTAMP'))


class Prescription(db.Model):
    __tablename__ = 'prescriptions'
    rx_id     = db.Column(db.Integer, primary_key=True)
    appt_id   = db.Column(db.Integer, db.ForeignKey('appointments.appt_id'), nullable=False)
    medicine  = db.Column(db.String(200), nullable=False)
    dosage    = db.Column(db.String(100), nullable=False)
    notes     = db.Column(db.Text)
    issued_at = db.Column(db.DateTime, nullable=False, server_default=text("CURRENT_TIMESTAMP"))


class AuditLog(db.Model):
    __tablename__ = 'audit_log'
    log_id      = db.Column(db.Integer, primary_key=True)
    table_name  = db.Column(db.String(50), nullable=False)
    record_id   = db.Column(db.Integer, nullable=False)
    action      = db.Column(db.Enum('INSERT', 'UPDATE', 'DELETE'), nullable=False)
    performed_by_email = db.Column(db.String(100))
    description = db.Column(db.String(255))
    timestamp   = db.Column(db.DateTime)


class AuditSummary(db.Model):
    __tablename__ = 'vw_audit_summary'
    __table_args__ = {'info': {'is_view': True}}
    table_name = db.Column(db.String(50), primary_key=True)
    action = db.Column(db.String(20), primary_key=True)
    occurrences = db.Column(db.Integer)
    last_occurred = db.Column(db.DateTime)


def roles_required(*roles):
    """Restrict route access to specific user roles."""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            if not current_user.is_authenticated:
                return login_manager.unauthorized()
            if current_user.usertype not in roles:
                flash("You are not authorized to access this page.", "danger")
                return redirect(url_for('index'))
            return func(*args, **kwargs)
        return wrapper
    return decorator


# ──────────────────────────────────────────────────────────
# AUTH
# ──────────────────────────────────────────────────────────

@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))


def _friendly_registration_error(msg):
    """Map common DB errors to clearer signup messages."""
    if not msg:
        return "Registration could not be completed."
    m = msg.lower()
    if "duplicate" in m and ("uq_user_email" in m or "users.email" in m):
        return "That email is already registered. Log in or choose a different email."
    if "chk_user_email" in m:
        return "Email format is invalid (must look like name@domain.com)."
    if "chk_phone_len" in m:
        return "Phone must be at least 10 characters in the database profile."
    return msg


@app.route('/signup', methods=['POST', 'GET'])
def signup():
    depts = Department.query.order_by(Department.dept_name.asc()).all()
    if request.method == "POST":
        username = (request.form.get('username') or '').strip()
        usertype = (request.form.get('usertype') or 'Patient').strip().title()
        email    = (request.form.get('email') or '').lower().strip()
        password = request.form.get('password')
        gender   = request.form.get('gender', 'Male')
        phone    = (request.form.get('phone') or '').strip()
        dob_raw  = (request.form.get('dob') or '').strip()
        address  = (request.form.get('address') or '').strip()
        fullname = (request.form.get('fullname') or username).strip()
        dept_id  = request.form.get('dept_id')
        qualification = request.form.get('qualification', '').strip()
        exp_raw = request.form.get('experience_yrs', '0').strip()
        is_doctor_signup = (usertype == 'Doctor')

        if len(phone) != 10 or not phone.isdigit():
            flash("Please enter a valid 10-digit phone number.", "warning")
            return render_template('signup.html', depts=depts)

        if not password:
            flash("Please enter a password.", "warning")
            return render_template('signup.html', depts=depts)

        if User.query.filter_by(email=email).first():
            flash("Email already registered.", "warning")
            return render_template('signup.html', depts=depts)

        if is_doctor_signup:
            if not dept_id:
                flash("Please select a department for doctor registration.", "warning")
                return render_template('signup.html', depts=depts)
            if not qualification:
                flash("Please enter qualification for doctor registration.", "warning")
                return render_template('signup.html', depts=depts)
            try:
                experience_yrs = int(exp_raw)
                if experience_yrs < 0:
                    raise ValueError()
            except ValueError:
                flash("Experience years must be a non-negative number.", "warning")
                return render_template('signup.html', depts=depts)

        try:
            # ORM path avoids MySQL CALL / OUT params / connection-pool issues with sp_register_user.
            pwd_hash = generate_password_hash(password)
            new_user = User(
                username=username,
                usertype=usertype,
                email=email,
                password=pwd_hash,
            )
            db.session.add(new_user)
            db.session.flush()

            if is_doctor_signup:
                db.session.add(
                    DoctorProfile(
                        user_id=new_user.user_id,
                        dept_id=int(dept_id),
                        full_name=fullname,
                        phone=phone,
                        qualification=qualification,
                        experience_yrs=experience_yrs,
                    )
                )
            else:
                pat_dob = None
                if dob_raw:
                    try:
                        pat_dob = datetime.strptime(dob_raw, "%Y-%m-%d").date()
                    except ValueError:
                        pat_dob = None
                db.session.add(
                    PatientProfile(
                        user_id=new_user.user_id,
                        full_name=fullname,
                        gender=gender,
                        phone=phone,
                        dob=pat_dob,
                        address=(address or None),
                    )
                )

            db.session.commit()
            flash(
                "Doctor registration successful. Please login."
                if is_doctor_signup
                else "Registration successful. Please login.",
                "success",
            )
            return redirect(url_for('login'))
        except IntegrityError as e:
            db.session.rollback()
            err = str(e.orig) if getattr(e, "orig", None) else str(e)
            flash(_friendly_registration_error(err), "danger")
        except Exception as e:
            db.session.rollback()
            flash(f"Error: {str(e)}", "danger")

    return render_template('signup.html', depts=depts)


@app.route('/login', methods=['POST', 'GET'])
def login():
    if request.method == "POST":
        email    = request.form.get('email').lower()
        password = request.form.get('password')
        user     = User.query.filter_by(email=email).first()

        if user and check_password_hash(user.password, password):
            if not user.is_active:
                flash("Your account is inactive. Please contact admin.", "danger")
                return render_template('login.html')
            login_user(user)
            flash("Login successful.", "primary")
            return redirect(url_for('index'))
        else:
            flash("Invalid credentials.", "danger")

    return render_template('login.html')


@app.route('/logout')
@login_required
def logout():
    logout_user()
    flash("Logged out successfully.", "warning")
    return redirect(url_for('login'))


@app.route('/profile')
@login_required
def profile():
    """Show account/profile details including dormant columns."""
    patient_profile = None
    if current_user.usertype == 'Patient':
        patient_profile = PatientProfile.query.filter_by(user_id=current_user.user_id).first()
    return render_template('profile.html', patient_profile=patient_profile)


# ──────────────────────────────────────────────────────────
# MAIN ROUTES
# ──────────────────────────────────────────────────────────

@app.route('/')
def index():
    return render_template('index.html')


@app.route('/doctors', methods=['POST', 'GET'])
@login_required
@roles_required('Admin')
def doctors():
    """Add a new doctor (Admin only in a full system)."""
    depts = Department.query.all()
    if request.method == "POST":
        full_name  = request.form.get('doctorname')
        dept_id    = request.form.get('dept_id')
        email      = request.form.get('email').lower()
        password   = generate_password_hash(request.form.get('password', 'default123'))
        phone      = request.form.get('phone', '')
        qual       = request.form.get('qualification', '')
        experience = request.form.get('experience_yrs', '0').strip()

        try:
            experience_yrs = int(experience)
            if experience_yrs < 0:
                raise ValueError()
        except ValueError:
            flash("Experience years must be a non-negative number.", "warning")
            return render_template('doctor.html', depts=depts)

        try:
            db.session.execute(
                text(
                    "CALL sp_register_doctor(:uname, :email, :pwd, :fname, :phone, :dept, :qual, :exp, @uid, @did, @msg)"
                ),
                {
                    'uname': full_name,
                    'email': email,
                    'pwd': password,
                    'fname': full_name,
                    'phone': phone,
                    'dept': int(dept_id),
                    'qual': qual,
                    'exp': experience_yrs
                }
            )
            db.session.commit()
            row = db.session.execute(text("SELECT @uid AS uid, @did AS did, @msg AS msg")).fetchone()
            if row.uid and int(row.uid) > 0:
                flash(f"Doctor registered successfully (Doctor ID: {row.did}).", "primary")
            else:
                flash(row.msg or "Doctor registration failed.", "danger")
        except Exception as e:
            db.session.rollback()
            flash(f"Failed to register doctor: {str(e)}", "danger")

    return render_template('doctor.html', depts=depts)


@app.route('/delete-doctor/<int:doctor_id>', methods=['POST'])
@login_required
@roles_required('Admin')
def delete_doctor(doctor_id):
    """Delete a doctor account (only when no appointments are linked)."""
    doctor = DoctorProfile.query.get_or_404(doctor_id)
    linked_appts = Appointment.query.filter_by(doctor_id=doctor_id).count()

    if linked_appts > 0:
        flash("Cannot delete doctor: appointments are linked to this doctor.", "danger")
        return redirect(url_for('admin_dashboard'))

    user = User.query.get(doctor.user_id)
    if not user:
        flash("Doctor user account not found.", "warning")
        return redirect(url_for('admin_dashboard'))

    try:
        # Deleting user cascades to doctor_profiles (fk_doc_user ON DELETE CASCADE).
        db.session.delete(user)
        db.session.commit()
        flash("Doctor deleted successfully.", "success")
    except Exception as e:
        db.session.rollback()
        flash(f"Failed to delete doctor: {str(e)}", "danger")

    return redirect(url_for('admin_dashboard'))


@app.route('/delete-user/<int:user_id>', methods=['POST'])
@login_required
@roles_required('Admin')
def delete_user(user_id):
    """Delete a user account with role-based safety checks."""
    user = User.query.get_or_404(user_id)

    if user.user_id == current_user.user_id:
        flash("You cannot delete your own account while logged in.", "warning")
        return redirect(url_for('admin_dashboard'))

    if user.usertype == 'Admin':
        flash("Admin accounts cannot be deleted from this panel.", "warning")
        return redirect(url_for('admin_dashboard'))

    if user.usertype == 'Doctor':
        doctor_profile = DoctorProfile.query.filter_by(user_id=user.user_id).first()
        if doctor_profile:
            linked_appts = Appointment.query.filter_by(doctor_id=doctor_profile.doctor_id).count()
            if linked_appts > 0:
                flash("Cannot delete this doctor user: appointments are linked.", "danger")
                return redirect(url_for('admin_dashboard'))

    try:
        db.session.delete(user)
        db.session.commit()
        flash("User deleted successfully.", "success")
    except Exception as e:
        db.session.rollback()
        flash(f"Failed to delete user: {str(e)}", "danger")

    return redirect(url_for('admin_dashboard'))


@app.route('/patients', methods=['POST', 'GET'])
@login_required
def patient():
    """Book an appointment."""
    doctors_list = DoctorProfile.query.all()
    slots_list   = Slot.query.all()

    pat_profile = PatientProfile.query.filter_by(user_id=current_user.user_id).first()

    if request.method == "POST":
        doctor_id = int(request.form.get('doctor_id'))
        slot_id   = int(request.form.get('slot_id'))
        appt_date = request.form.get('date')
        disease   = request.form.get('disease')

        if not pat_profile:
            flash("Patient profile not found. Please complete your profile.", "warning")
            return render_template('patient.html', doctors=doctors_list, slots=slots_list,today=date.today())

        # Call stored procedure
        try:
            db.session.execute(
                text("CALL sp_book_appointment(:pid, :did, :sid, :dt, :dis, @aid, @msg)"),
                {'pid': pat_profile.patient_id, 'did': doctor_id,
                 'sid': slot_id, 'dt': appt_date, 'dis': disease}
            )
            db.session.commit()
            row = db.session.execute(text("SELECT @aid AS aid, @msg AS msg")).fetchone()
            if row.aid and int(row.aid) > 0:
                flash(f"Booking confirmed! Appointment ID: {row.aid}", "info")
            else:
                flash(f"Booking failed: {row.msg}", "danger")
        except Exception as e:
            db.session.rollback()
            flash(f"Error: {str(e)}", "danger")

    return render_template('patient.html', doctors=doctors_list, slots=slots_list, patient_profile=pat_profile, today=date.today())


@app.route('/bookings')
@login_required
def bookings():
    """View appointments — doctors see all, patients see own."""
    has_upcoming = None
    if current_user.usertype == 'Doctor':
        query = db.session.execute(text("SELECT * FROM vw_appointment_details")).fetchall()
    elif current_user.usertype == 'Admin':
        query = db.session.execute(text("SELECT * FROM vw_appointment_details")).fetchall()
    else:
        pat = PatientProfile.query.filter_by(user_id=current_user.user_id).first()
        if pat:
            query = db.session.execute(
                text("SELECT * FROM vw_appointment_details WHERE patient_email = :em"),
                {'em': current_user.email}
            ).fetchall()
            has_upcoming = db.session.execute(
                text("SELECT fn_has_upcoming_appointment(:pid) AS has_upcoming"),
                {'pid': pat.patient_id}
            ).fetchone().has_upcoming
        else:
            query = []
    created_at_map = {}
    if query:
        for row in query:
            appt = Appointment.query.get(int(row.appt_id))
            created_at_map[int(row.appt_id)] = appt.created_at if appt else None

    return render_template('booking.html', query=query, has_upcoming=has_upcoming, created_at_map=created_at_map)


@app.route('/edit/<int:appt_id>', methods=['POST', 'GET'])
@login_required
def edit(appt_id):
    appt = Appointment.query.get_or_404(appt_id)
    slots_list = Slot.query.all()
    doctors_list = DoctorProfile.query.all()
    pat_profile = PatientProfile.query.filter_by(user_id=current_user.user_id).first()
    doctor_profile = DoctorProfile.query.filter_by(user_id=current_user.user_id).first()

    can_access = (
        current_user.usertype == 'Admin' or
        (current_user.usertype == 'Patient' and pat_profile and appt.patient_id == pat_profile.patient_id) or
        (current_user.usertype == 'Doctor' and doctor_profile and appt.doctor_id == doctor_profile.doctor_id)
    )
    if not can_access:
        flash("You are not allowed to edit this appointment.", "danger")
        return redirect(url_for('bookings'))

    if request.method == "POST":
        new_status = request.form.get('status', appt.status)
        if current_user.usertype == 'Doctor':
            try:
                db.session.execute(
                    text("CALL sp_update_appointment_status(:aid, :status, :email, @msg)"),
                    {'aid': appt_id, 'status': new_status, 'email': current_user.email}
                )
                db.session.commit()
                row = db.session.execute(text("SELECT @msg AS msg")).fetchone()
                flash(row.msg, "info")
            except Exception as e:
                db.session.rollback()
                flash(f"Update failed: {str(e)}", "danger")
            return redirect(url_for('bookings'))
        else:
            appt.slot_id   = int(request.form.get('slot_id'))
            appt.appt_date = datetime.strptime(request.form.get('date'), '%Y-%m-%d').date()
            appt.disease   = request.form.get('disease')
        try:
            db.session.commit()
            if new_status != appt.status:
                db.session.execute(
                    text("CALL sp_update_appointment_status(:aid, :status, :email, @msg)"),
                    {'aid': appt_id, 'status': new_status, 'email': current_user.email}
                )
                db.session.commit()
                row = db.session.execute(text("SELECT @msg AS msg")).fetchone()
                flash(f"Appointment updated. {row.msg}", "success")
            else:
                flash("Appointment updated.", "success")
        except Exception as e:
            db.session.rollback()
            flash(f"Update failed: {str(e)}", "danger")
        return redirect(url_for('bookings'))

    return render_template('edit.html', appt=appt, slots=slots_list, doctors=doctors_list)


@app.route('/delete/<int:appt_id>')
@login_required
def delete(appt_id):
    appt = Appointment.query.get_or_404(appt_id)
    pat_profile = PatientProfile.query.filter_by(user_id=current_user.user_id).first()

    if current_user.usertype not in ('Admin', 'Patient'):
        flash("Only Admin or Patient can cancel appointments.", "danger")
        return redirect(url_for('bookings'))
    if current_user.usertype == 'Patient' and (not pat_profile or appt.patient_id != pat_profile.patient_id):
        flash("You are not allowed to cancel this appointment.", "danger")
        return redirect(url_for('bookings'))

    try:
        db.session.execute(
            text("CALL sp_cancel_appointment(:aid, :em, @msg)"),
            {'aid': appt_id, 'em': current_user.email}
        )
        db.session.commit()
        row = db.session.execute(text("SELECT @msg AS msg")).fetchone()
        flash(row.msg, "info")
    except Exception as e:
        db.session.rollback()
        flash(f"Error: {str(e)}", "danger")
    return redirect(url_for('bookings'))


@app.route('/details')
@login_required
@roles_required('Admin', 'Doctor')
def details():
    """Audit log — Admin/Doctor view."""
    logs = AuditLog.query.order_by(AuditLog.timestamp.desc()).all()
    summary = db.session.execute(
        text("SELECT table_name, action, occurrences, last_occurred FROM vw_audit_summary ORDER BY last_occurred DESC")
    ).fetchall()
    return render_template('trigers.html', posts=logs, summary=summary)


@app.route('/workload')
@login_required
@roles_required('Admin', 'Doctor')
def workload():
    """Doctor workload summary view."""
    rows = db.session.execute(text("SELECT * FROM vw_doctor_workload")).fetchall()
    return render_template('workload.html', rows=rows)


@app.route('/history')
@login_required
def history():
    """Patient appointment history via stored procedure cursor."""
    if current_user.usertype == 'Patient':
        pat = PatientProfile.query.filter_by(user_id=current_user.user_id).first()
        if not pat:
            flash("Patient profile not found.", "warning")
            return redirect(url_for('bookings'))
        patient_id = pat.patient_id
    else:
        patient_id = request.args.get('patient_id', type=int)
        if not patient_id:
            flash("Please provide a patient ID.", "warning")
            return redirect(url_for('bookings'))

    rows = db.session.execute(text("CALL sp_patient_appointment_history(:pid)"), {'pid': patient_id}).fetchall()
    return render_template('history.html', rows=rows, patient_id=patient_id)


@app.route('/prescriptions')
@login_required
def prescriptions():
    """List prescriptions with appointment context."""
    if current_user.usertype == 'Patient':
        pat = PatientProfile.query.filter_by(user_id=current_user.user_id).first()
        if not pat:
            flash("Patient profile not found.", "warning")
            return render_template('prescriptions.html', rows=[], appointments=[])
        rows = db.session.execute(text("""
            SELECT p.rx_id, p.appt_id, p.medicine, p.dosage, p.notes, p.issued_at,
                   dp.full_name AS doctor_name, a.appt_date, a.status
            FROM prescriptions p
            JOIN appointments a ON p.appt_id = a.appt_id
            JOIN doctor_profiles dp ON a.doctor_id = dp.doctor_id
            WHERE a.patient_id = :pid
            ORDER BY p.issued_at DESC
        """), {'pid': pat.patient_id}).fetchall()
        appointments = db.session.execute(text("""
            SELECT a.appt_id, a.appt_date, dp.full_name AS doctor_name, a.status
            FROM appointments a
            JOIN doctor_profiles dp ON a.doctor_id = dp.doctor_id
            WHERE a.patient_id = :pid
            ORDER BY a.appt_date DESC
        """), {'pid': pat.patient_id}).fetchall()
    elif current_user.usertype == 'Doctor':
        doc = DoctorProfile.query.filter_by(user_id=current_user.user_id).first()
        rows = db.session.execute(text("""
            SELECT p.rx_id, p.appt_id, p.medicine, p.dosage, p.notes, p.issued_at,
                   pp.full_name AS patient_name, a.appt_date, a.status
            FROM prescriptions p
            JOIN appointments a ON p.appt_id = a.appt_id
            JOIN patient_profiles pp ON a.patient_id = pp.patient_id
            WHERE a.doctor_id = :did
            ORDER BY p.issued_at DESC
        """), {'did': doc.doctor_id}).fetchall()
        appointments = db.session.execute(text("""
            SELECT a.appt_id, a.appt_date, pp.full_name AS patient_name, a.status
            FROM appointments a
            JOIN patient_profiles pp ON a.patient_id = pp.patient_id
            WHERE a.doctor_id = :did
            ORDER BY a.appt_date DESC
        """), {'did': doc.doctor_id}).fetchall()
    else:
        rows = db.session.execute(text("""
            SELECT p.rx_id, p.appt_id, p.medicine, p.dosage, p.notes, p.issued_at,
                   pp.full_name AS patient_name, dp.full_name AS doctor_name, a.appt_date, a.status
            FROM prescriptions p
            JOIN appointments a ON p.appt_id = a.appt_id
            JOIN patient_profiles pp ON a.patient_id = pp.patient_id
            JOIN doctor_profiles dp ON a.doctor_id = dp.doctor_id
            ORDER BY p.issued_at DESC
        """)).fetchall()
        appointments = db.session.execute(text("""
            SELECT a.appt_id, a.appt_date, pp.full_name AS patient_name, dp.full_name AS doctor_name, a.status
            FROM appointments a
            JOIN patient_profiles pp ON a.patient_id = pp.patient_id
            JOIN doctor_profiles dp ON a.doctor_id = dp.doctor_id
            ORDER BY a.appt_date DESC
        """)).fetchall()

    return render_template('prescriptions.html', rows=rows, appointments=appointments)


@app.route('/prescriptions/add', methods=['POST'])
@login_required
@roles_required('Admin', 'Doctor')
def add_prescription():
    appt_id = request.form.get('appt_id', type=int)
    medicine = (request.form.get('medicine') or '').strip()
    dosage = (request.form.get('dosage') or '').strip()
    notes = (request.form.get('notes') or '').strip()
    if not appt_id or not medicine or not dosage:
        flash("Appointment, medicine and dosage are required.", "warning")
        return redirect(url_for('prescriptions'))

    appt = Appointment.query.get_or_404(appt_id)
    if current_user.usertype == 'Doctor':
        doc = DoctorProfile.query.filter_by(user_id=current_user.user_id).first()
        if not doc or appt.doctor_id != doc.doctor_id:
            flash("You can only prescribe for your own appointments.", "danger")
            return redirect(url_for('prescriptions'))

    try:
        rx = Prescription(
            appt_id=appt_id,
            medicine=medicine,
            dosage=dosage,
            notes=notes or None,
            issued_at=datetime.utcnow()
        )
        db.session.add(rx)
        db.session.commit()
        flash("Prescription added successfully.", "success")
    except Exception as e:
        db.session.rollback()
        flash(f"Failed to add prescription: {str(e)}", "danger")
    return redirect(url_for('prescriptions'))


@app.route('/prescriptions/delete/<int:rx_id>', methods=['POST'])
@login_required
@roles_required('Admin', 'Doctor')
def delete_prescription(rx_id):
    rx = Prescription.query.get_or_404(rx_id)
    appt = Appointment.query.get(rx.appt_id)
    if current_user.usertype == 'Doctor':
        doc = DoctorProfile.query.filter_by(user_id=current_user.user_id).first()
        if not doc or not appt or appt.doctor_id != doc.doctor_id:
            flash("You are not allowed to delete this prescription.", "danger")
            return redirect(url_for('prescriptions'))
    try:
        db.session.delete(rx)
        db.session.commit()
        flash("Prescription deleted.", "info")
    except Exception as e:
        db.session.rollback()
        flash(f"Failed to delete prescription: {str(e)}", "danger")
    return redirect(url_for('prescriptions'))


@app.route('/admins', methods=['GET', 'POST'])
@login_required
@roles_required('Admin')
def admins():
    if request.method == 'POST':
        username = (request.form.get('username') or '').strip()
        email = (request.form.get('email') or '').strip().lower()
        password = request.form.get('password') or ''
        if not username or not email or not password:
            flash("All fields are required.", "warning")
            return render_template('admins.html')
        try:
            db.session.execute(
                text("CALL sp_create_admin_user(:uname, :email, :pwd, @uid, @msg)"),
                {'uname': username, 'email': email, 'pwd': generate_password_hash(password)}
            )
            db.session.commit()
            row = db.session.execute(text("SELECT @uid AS uid, @msg AS msg")).fetchone()
            if row.uid and int(row.uid) > 0:
                flash(f"Admin user created with ID {row.uid}.", "success")
            else:
                flash(row.msg or "Admin creation failed.", "danger")
        except Exception as e:
            db.session.rollback()
            flash(f"Admin creation failed: {str(e)}", "danger")
    return render_template('admins.html')


@app.route('/search', methods=['POST', 'GET'])
@login_required
def search():
    if request.method == "POST":
        query_str = request.form.get('search', '').strip()
        dept = Department.query.filter(
            Department.dept_name.ilike(f'%{query_str}%')
        ).first()
        doc = DoctorProfile.query.filter(
            DoctorProfile.full_name.ilike(f'%{query_str}%')
        ).first()
        if dept or doc:
            flash(f"Found: {'Department — ' + dept.dept_name if dept else ''} "
                  f"{'Doctor — ' + doc.full_name if doc else ''}", "info")
        else:
            flash("No matching doctor or department found.", "danger")
    return render_template('index.html')


@app.route('/admin')
@login_required
@roles_required('Admin')
def admin_dashboard():
    stats = {
        'users': User.query.count(),
        'doctors': DoctorProfile.query.count(),
        'patients': PatientProfile.query.count(),
        'appointments': Appointment.query.count(),
        'scheduled': Appointment.query.filter_by(status='Scheduled').count(),
        'completed': Appointment.query.filter_by(status='Completed').count(),
        'cancelled': Appointment.query.filter_by(status='Cancelled').count(),
    }
    recent_logs = AuditLog.query.order_by(AuditLog.timestamp.desc()).limit(10).all()
    audit_summary = db.session.execute(
        text("SELECT table_name, action, occurrences, last_occurred FROM vw_audit_summary ORDER BY last_occurred DESC")
    ).fetchall()
    recent_appointments = db.session.execute(text("""
        SELECT v.*, a.created_at
        FROM vw_appointment_details v
        JOIN appointments a ON v.appt_id = a.appt_id
        ORDER BY v.appt_id DESC
        LIMIT 10
    """)).fetchall()
    doctors_for_admin = db.session.execute(text("""
        SELECT dp.doctor_id, dp.full_name, fn_get_dept_name(dp.dept_id) AS dept_name, u.email,
               dp.phone, dp.experience_yrs
        FROM doctor_profiles dp
        JOIN users u ON dp.user_id = u.user_id
        ORDER BY dp.doctor_id DESC
    """)).fetchall()
    users_for_admin = User.query.order_by(User.user_id.desc()).all()
    return render_template(
        'admin.html',
        stats=stats,
        recent_logs=recent_logs,
        audit_summary=audit_summary,
        recent_appointments=recent_appointments,
        doctors_for_admin=doctors_for_admin,
        users_for_admin=users_for_admin
    )


@app.route('/test')
def test():
    try:
        db.session.execute(text("SELECT 1"))
        return 'Database connection OK ✓'
    except Exception as e:
        return f'Database connection FAILED: {str(e)}'


# ──────────────────────────────────────────────────────────
# RUN
# ──────────────────────────────────────────────────────────
if __name__ == '__main__':
    app.run(debug=True)