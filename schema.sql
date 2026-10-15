-- ================================================================
--   DECENTRALIZED BLOOD BANK & EMERGENCY COORDINATION SYSTEM
--   Database Schema v1.0  |  DBMS Project
--   Engine: PostgreSQL 14+
-- ================================================================

-- ────────────────────────────────────────────────
--  CLEAN SLATE
-- ────────────────────────────────────────────────
DROP TABLE IF EXISTS audit_logs              CASCADE;
DROP TABLE IF EXISTS transfer_logs           CASCADE;
DROP TABLE IF EXISTS emergency_responses     CASCADE;
DROP TABLE IF EXISTS emergency_requests      CASCADE;
DROP TABLE IF EXISTS blood_requests          CASCADE;
DROP TABLE IF EXISTS blood_inventory         CASCADE;
DROP TABLE IF EXISTS blood_units             CASCADE;
DROP TABLE IF EXISTS donations               CASCADE;
DROP TABLE IF EXISTS donors                  CASCADE;
DROP TABLE IF EXISTS hospitals               CASCADE;
DROP TABLE IF EXISTS blood_banks             CASCADE;
DROP TABLE IF EXISTS compatibility_rules     CASCADE;
DROP TABLE IF EXISTS users                   CASCADE;

-- ================================================================
--  1. USERS  — staff / admins / coordinators
-- ================================================================
CREATE TABLE users (
    user_id       SERIAL       PRIMARY KEY,
    username      VARCHAR(60)  UNIQUE NOT NULL,
    full_name     VARCHAR(120) NOT NULL,
    email         VARCHAR(120) UNIQUE NOT NULL,
    phone         VARCHAR(20),
    password_hash VARCHAR(255) NOT NULL,
    role          VARCHAR(30)  NOT NULL DEFAULT 'staff'
                  CHECK (role IN ('super_admin','bank_admin','hospital_staff',
                                  'coordinator','donor','staff')),
    is_active     BOOLEAN      DEFAULT TRUE,
    last_login    TIMESTAMP,
    created_at    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

-- ================================================================
--  2. BLOOD BANKS  — decentralized nodes
-- ================================================================
CREATE TABLE blood_banks (
    bank_id       SERIAL        PRIMARY KEY,
    bank_name     VARCHAR(150)  NOT NULL,
    city          VARCHAR(80)   NOT NULL,
    state         VARCHAR(80)   NOT NULL,
    address       TEXT,
    latitude      NUMERIC(9,6),
    longitude     NUMERIC(9,6),
    phone         VARCHAR(20),
    email         VARCHAR(120),
    admin_user_id INT           REFERENCES users(user_id),
    capacity_units INT          NOT NULL DEFAULT 500,
    is_active     BOOLEAN       DEFAULT TRUE,
    is_24h        BOOLEAN       DEFAULT TRUE,
    established   DATE,
    last_sync     TIMESTAMP     DEFAULT CURRENT_TIMESTAMP   -- decentralized sync timestamp
);

-- ================================================================
--  3. HOSPITALS  — requesting entities
-- ================================================================
CREATE TABLE hospitals (
    hospital_id   SERIAL       PRIMARY KEY,
    hospital_name VARCHAR(150) NOT NULL,
    city          VARCHAR(80)  NOT NULL,
    state         VARCHAR(80)  NOT NULL,
    address       TEXT,
    latitude      NUMERIC(9,6),
    longitude     NUMERIC(9,6),
    phone         VARCHAR(20),
    email         VARCHAR(120),
    type          VARCHAR(30)  CHECK (type IN ('Government','Private','Trust','Clinic')),
    has_blood_bank BOOLEAN     DEFAULT FALSE,
    linked_bank_id INT         REFERENCES blood_banks(bank_id),
    emergency_contact VARCHAR(100)
);

-- ================================================================
--  4. BLOOD COMPATIBILITY RULES
-- ================================================================
CREATE TABLE compatibility_rules (
    rule_id        SERIAL      PRIMARY KEY,
    donor_group    VARCHAR(5)  NOT NULL,   -- A+, A-, B+, B-, O+, O-, AB+, AB-
    recipient_group VARCHAR(5) NOT NULL,
    is_compatible  BOOLEAN     NOT NULL,
    notes          TEXT,
    UNIQUE (donor_group, recipient_group)
);

-- ================================================================
--  5. DONORS
-- ================================================================
CREATE TABLE donors (
    donor_id        SERIAL       PRIMARY KEY,
    user_id         INT          REFERENCES users(user_id) ON DELETE SET NULL,
    full_name       VARCHAR(120) NOT NULL,
    date_of_birth   DATE         NOT NULL,
    gender          VARCHAR(10)  CHECK (gender IN ('Male','Female','Other')),
    blood_group     VARCHAR(5)   NOT NULL,
    phone           VARCHAR(20)  NOT NULL,
    email           VARCHAR(120),
    address         TEXT,
    city            VARCHAR(80),
    state           VARCHAR(80),
    weight_kg       NUMERIC(5,1),
    is_eligible     BOOLEAN      DEFAULT TRUE,
    last_donation   DATE,
    next_eligible   DATE,                 -- computed: last_donation + 90 days
    total_donations INT          DEFAULT 0,
    preferred_bank  INT          REFERENCES blood_banks(bank_id),
    registered_at   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

-- ================================================================
--  6. DONATIONS
-- ================================================================
CREATE TABLE donations (
    donation_id     SERIAL        PRIMARY KEY,
    donor_id        INT           NOT NULL REFERENCES donors(donor_id),
    bank_id         INT           NOT NULL REFERENCES blood_banks(bank_id),
    donation_date   DATE          NOT NULL DEFAULT CURRENT_DATE,
    blood_group     VARCHAR(5)    NOT NULL,
    units_donated   NUMERIC(4,1)  NOT NULL DEFAULT 1.0,   -- in units (1 unit ≈ 450 ml)
    hemoglobin_level NUMERIC(4,1),
    blood_pressure  VARCHAR(20),
    donation_type   VARCHAR(20)   DEFAULT 'Whole Blood'
                    CHECK (donation_type IN ('Whole Blood','Platelets','Plasma','Red Cells')),
    status          VARCHAR(20)   DEFAULT 'Collected'
                    CHECK (status IN ('Collected','Processing','Tested','Approved','Rejected','Used')),
    technician_id   INT           REFERENCES users(user_id),
    notes           TEXT,
    collected_at    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
);

-- ================================================================
--  7. BLOOD UNITS  — individual bag tracking
-- ================================================================
CREATE TABLE blood_units (
    unit_id         SERIAL       PRIMARY KEY,
    donation_id     INT          NOT NULL REFERENCES donations(donation_id),
    bank_id         INT          NOT NULL REFERENCES blood_banks(bank_id),
    blood_group     VARCHAR(5)   NOT NULL,
    component       VARCHAR(30)  NOT NULL DEFAULT 'Whole Blood'
                    CHECK (component IN ('Whole Blood','Packed RBC','Platelets',
                                         'Fresh Frozen Plasma','Cryoprecipitate')),
    unit_code       VARCHAR(30)  UNIQUE NOT NULL,  -- barcode / bag ID
    volume_ml       INT          DEFAULT 450,
    collected_date  DATE         NOT NULL,
    expiry_date     DATE         NOT NULL,          -- typically +35 days for whole blood
    status          VARCHAR(20)  NOT NULL DEFAULT 'Available'
                    CHECK (status IN ('Available','Reserved','Issued','Expired','Discarded','Transferred')),
    location_bank   INT          REFERENCES blood_banks(bank_id),  -- current location
    tested_for_hiv  BOOLEAN      DEFAULT FALSE,
    tested_for_hbv  BOOLEAN      DEFAULT FALSE,
    tested_for_hcv  BOOLEAN      DEFAULT FALSE,
    is_crossmatched BOOLEAN      DEFAULT FALSE,
    created_at      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

-- ================================================================
--  8. BLOOD INVENTORY  — aggregate stock per bank per group
-- ================================================================
CREATE TABLE blood_inventory (
    inventory_id    SERIAL       PRIMARY KEY,
    bank_id         INT          NOT NULL REFERENCES blood_banks(bank_id),
    blood_group     VARCHAR(5)   NOT NULL,
    component       VARCHAR(30)  NOT NULL DEFAULT 'Whole Blood',
    units_available INT          NOT NULL DEFAULT 0 CHECK (units_available >= 0),
    units_reserved  INT          NOT NULL DEFAULT 0 CHECK (units_reserved  >= 0),
    critical_level  INT          NOT NULL DEFAULT 5,
    last_updated    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (bank_id, blood_group, component)
);

-- ================================================================
--  9. BLOOD REQUESTS  — from hospitals / patients
-- ================================================================
CREATE TABLE blood_requests (
    request_id      SERIAL       PRIMARY KEY,
    hospital_id     INT          NOT NULL REFERENCES hospitals(hospital_id),
    requested_by    INT          NOT NULL REFERENCES users(user_id),
    patient_name    VARCHAR(120),
    patient_age     INT,
    blood_group     VARCHAR(5)   NOT NULL,
    component       VARCHAR(30)  NOT NULL DEFAULT 'Whole Blood',
    units_needed    INT          NOT NULL CHECK (units_needed > 0),
    units_fulfilled INT          NOT NULL DEFAULT 0,
    urgency         VARCHAR(20)  NOT NULL DEFAULT 'Normal'
                    CHECK (urgency IN ('Critical','Urgent','Normal','Elective')),
    reason          TEXT,
    status          VARCHAR(20)  NOT NULL DEFAULT 'Open'
                    CHECK (status IN ('Open','Partially Fulfilled','Fulfilled',
                                      'Cancelled','Expired')),
    assigned_bank   INT          REFERENCES blood_banks(bank_id),
    needed_by       TIMESTAMP,
    requested_at    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    fulfilled_at    TIMESTAMP
);

-- ================================================================
--  10. EMERGENCY REQUESTS  — mass casualty / disaster events
-- ================================================================
CREATE TABLE emergency_requests (
    emergency_id    SERIAL       PRIMARY KEY,
    title           VARCHAR(200) NOT NULL,
    description     TEXT,
    location        VARCHAR(200) NOT NULL,
    city            VARCHAR(80),
    state           VARCHAR(80),
    latitude        NUMERIC(9,6),
    longitude       NUMERIC(9,6),
    incident_type   VARCHAR(50)  CHECK (incident_type IN
                      ('Road Accident','Natural Disaster','Mass Casualty',
                       'Fire','Industrial Accident','Pandemic','Other')),
    severity        VARCHAR(20)  CHECK (severity IN ('Low','Medium','High','Critical')),
    reported_by     INT          NOT NULL REFERENCES users(user_id),
    coordinator_id  INT          REFERENCES users(user_id),
    casualties_est  INT,
    blood_needed    TEXT,        -- JSON-like: "O+:10, A+:5, B+:3"
    status          VARCHAR(20)  NOT NULL DEFAULT 'Active'
                    CHECK (status IN ('Active','Coordinating','Resolved','Closed')),
    reported_at     TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    resolved_at     TIMESTAMP
);

-- ================================================================
--  11. EMERGENCY RESPONSES  — which banks responded with what
-- ================================================================
CREATE TABLE emergency_responses (
    response_id     SERIAL       PRIMARY KEY,
    emergency_id    INT          NOT NULL REFERENCES emergency_requests(emergency_id),
    bank_id         INT          NOT NULL REFERENCES blood_banks(bank_id),
    responder_id    INT          NOT NULL REFERENCES users(user_id),
    blood_group     VARCHAR(5)   NOT NULL,
    component       VARCHAR(30)  DEFAULT 'Whole Blood',
    units_pledged   INT          NOT NULL CHECK (units_pledged > 0),
    units_dispatched INT         DEFAULT 0,
    dispatch_time   TIMESTAMP,
    eta_minutes     INT,
    status          VARCHAR(20)  DEFAULT 'Pledged'
                    CHECK (status IN ('Pledged','Dispatched','Delivered','Cancelled')),
    notes           TEXT,
    responded_at    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

-- ================================================================
--  12. TRANSFER LOGS  — inter-bank blood transfers
-- ================================================================
CREATE TABLE transfer_logs (
    transfer_id     SERIAL       PRIMARY KEY,
    unit_id         INT          NOT NULL REFERENCES blood_units(unit_id),
    from_bank_id    INT          NOT NULL REFERENCES blood_banks(bank_id),
    to_bank_id      INT          NOT NULL REFERENCES blood_banks(bank_id),
    request_id      INT          REFERENCES blood_requests(request_id),
    emergency_id    INT          REFERENCES emergency_requests(emergency_id),
    transferred_by  INT          NOT NULL REFERENCES users(user_id),
    reason          TEXT,
    transfer_date   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    received_at     TIMESTAMP,
    status          VARCHAR(20)  DEFAULT 'In Transit'
                    CHECK (status IN ('In Transit','Received','Lost','Rejected'))
);

-- ================================================================
--  13. AUDIT LOGS  — every critical action
-- ================================================================
CREATE TABLE audit_logs (
    log_id          SERIAL       PRIMARY KEY,
    user_id         INT          REFERENCES users(user_id),
    action          VARCHAR(100) NOT NULL,
    table_name      VARCHAR(60),
    record_id       INT,
    old_value       TEXT,
    new_value       TEXT,
    ip_address      VARCHAR(45),
    logged_at       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

-- ================================================================
--  INDEXES  — performance critical
-- ================================================================
CREATE INDEX idx_units_blood_group     ON blood_units(blood_group);
CREATE INDEX idx_units_bank            ON blood_units(bank_id);
CREATE INDEX idx_units_status          ON blood_units(status);
CREATE INDEX idx_units_expiry          ON blood_units(expiry_date);
CREATE INDEX idx_inventory_bank        ON blood_inventory(bank_id);
CREATE INDEX idx_inventory_group       ON blood_inventory(blood_group);
CREATE INDEX idx_requests_urgency      ON blood_requests(urgency);
CREATE INDEX idx_requests_status       ON blood_requests(status);
CREATE INDEX idx_requests_blood_group  ON blood_requests(blood_group);
CREATE INDEX idx_emergency_status      ON emergency_requests(status);
CREATE INDEX idx_emergency_city        ON emergency_requests(city);
CREATE INDEX idx_donors_blood_group    ON donors(blood_group);
CREATE INDEX idx_donors_city           ON donors(city);
CREATE INDEX idx_donors_eligible       ON donors(is_eligible);
CREATE INDEX idx_donations_donor       ON donations(donor_id);
CREATE INDEX idx_donations_bank        ON donations(bank_id);
CREATE INDEX idx_transfer_unit         ON transfer_logs(unit_id);
CREATE INDEX idx_audit_user            ON audit_logs(user_id);
CREATE INDEX idx_audit_time            ON audit_logs(logged_at);

-- ================================================================
--  VIEWS
-- ================================================================

-- Live inventory across all banks
CREATE OR REPLACE VIEW vw_network_inventory AS
SELECT
    bb.bank_id, bb.bank_name, bb.city, bb.state,
    bi.blood_group, bi.component,
    bi.units_available,
    bi.units_reserved,
    bi.units_available - bi.units_reserved AS net_available,
    bi.critical_level,
    CASE WHEN bi.units_available <= bi.critical_level
         THEN 'CRITICAL' ELSE 'OK' END AS stock_status,
    bb.last_sync
FROM blood_inventory bi
JOIN blood_banks bb ON bi.bank_id = bb.bank_id
WHERE bb.is_active = TRUE;

-- Open blood requests with urgency
CREATE OR REPLACE VIEW vw_open_requests AS
SELECT
    r.request_id, r.urgency, r.blood_group, r.component,
    r.units_needed, r.units_fulfilled,
    r.units_needed - r.units_fulfilled AS units_pending,
    r.status, r.requested_at, r.needed_by,
    h.hospital_name, h.city,
    CONCAT(u.full_name) AS requested_by,
    EXTRACT(EPOCH FROM (r.needed_by - NOW()))/3600 AS hours_left
FROM blood_requests r
JOIN hospitals h ON r.hospital_id = h.hospital_id
JOIN users     u ON r.requested_by = u.user_id
WHERE r.status IN ('Open','Partially Fulfilled')
ORDER BY
    CASE r.urgency
        WHEN 'Critical' THEN 1 WHEN 'Urgent' THEN 2
        WHEN 'Normal'   THEN 3 ELSE 4 END,
    r.requested_at;

-- Donor eligibility view
CREATE OR REPLACE VIEW vw_eligible_donors AS
SELECT
    d.donor_id, d.full_name, d.blood_group,
    d.phone, d.email, d.city, d.state,
    d.last_donation, d.next_eligible,
    d.total_donations,
    bb.bank_name AS preferred_bank
FROM donors d
LEFT JOIN blood_banks bb ON d.preferred_bank = bb.bank_id
WHERE d.is_eligible = TRUE
  AND (d.next_eligible IS NULL OR d.next_eligible <= CURRENT_DATE);

-- Blood units expiring within 7 days
CREATE OR REPLACE VIEW vw_expiring_soon AS
SELECT
    bu.unit_id, bu.unit_code, bu.blood_group, bu.component,
    bu.expiry_date,
    (bu.expiry_date - CURRENT_DATE) AS days_left,
    bb.bank_name, bb.city
FROM blood_units bu
JOIN blood_banks bb ON bu.location_bank = bb.bank_id
WHERE bu.status = 'Available'
  AND bu.expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
ORDER BY bu.expiry_date;

-- Active emergency summary
CREATE OR REPLACE VIEW vw_active_emergencies AS
SELECT
    e.emergency_id, e.title, e.incident_type, e.severity,
    e.location, e.city, e.casualties_est, e.blood_needed,
    e.status, e.reported_at,
    u.full_name AS reported_by,
    c.full_name AS coordinator,
    COUNT(er.response_id)         AS banks_responded,
    SUM(er.units_pledged)         AS total_units_pledged,
    SUM(er.units_dispatched)      AS total_units_dispatched
FROM emergency_requests e
JOIN users u ON e.reported_by = u.user_id
LEFT JOIN users c ON e.coordinator_id = c.user_id
LEFT JOIN emergency_responses er ON e.emergency_id = er.emergency_id
WHERE e.status IN ('Active','Coordinating')
GROUP BY e.emergency_id, e.title, e.incident_type, e.severity,
         e.location, e.city, e.casualties_est, e.blood_needed,
         e.status, e.reported_at, u.full_name, c.full_name;

-- ================================================================
--  STORED FUNCTIONS
-- ================================================================

-- ── 1. FULFILL BLOOD REQUEST (atomic, cross-bank)
CREATE OR REPLACE FUNCTION fulfill_request(
    p_request_id INT,
    p_bank_id    INT,
    p_units      INT
) RETURNS TEXT AS $$
DECLARE
    v_req      blood_requests%ROWTYPE;
    v_avail    INT;
    v_new_fulfilled INT;
BEGIN
    SELECT * INTO v_req FROM blood_requests
    WHERE request_id = p_request_id FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'Request #% not found.', p_request_id; END IF;
    IF v_req.status = 'Fulfilled' THEN RAISE EXCEPTION 'Request already fulfilled.'; END IF;
    IF v_req.status = 'Cancelled' THEN RAISE EXCEPTION 'Request has been cancelled.'; END IF;

    -- Check bank stock
    SELECT units_available - units_reserved INTO v_avail
    FROM blood_inventory
    WHERE bank_id = p_bank_id
      AND blood_group = v_req.blood_group
      AND component   = v_req.component
    FOR UPDATE;

    IF v_avail IS NULL OR v_avail < p_units THEN
        RAISE EXCEPTION 'Insufficient stock at bank %. Available: %', p_bank_id, COALESCE(v_avail,0);
    END IF;

    -- Deduct inventory
    UPDATE blood_inventory
    SET units_available = units_available - p_units,
        last_updated    = NOW()
    WHERE bank_id     = p_bank_id
      AND blood_group = v_req.blood_group
      AND component   = v_req.component;

    -- Mark units as Issued (FIFO: oldest expiry first)
    UPDATE blood_units
    SET status = 'Issued'
    WHERE unit_id IN (
        SELECT unit_id FROM blood_units
        WHERE bank_id    = p_bank_id
          AND blood_group = v_req.blood_group
          AND component   = v_req.component
          AND status      = 'Available'
        ORDER BY expiry_date ASC
        LIMIT p_units
    );

    -- Update request
    v_new_fulfilled := v_req.units_fulfilled + p_units;
    UPDATE blood_requests
    SET units_fulfilled = v_new_fulfilled,
        assigned_bank   = p_bank_id,
        status = CASE WHEN v_new_fulfilled >= v_req.units_needed
                      THEN 'Fulfilled' ELSE 'Partially Fulfilled' END,
        fulfilled_at = CASE WHEN v_new_fulfilled >= v_req.units_needed
                            THEN NOW() ELSE NULL END
    WHERE request_id = p_request_id;

    RETURN 'OK: ' || p_units || ' units of ' || v_req.blood_group
           || ' dispatched from bank ' || p_bank_id;
END;
$$ LANGUAGE plpgsql;


-- ── 2. REGISTER DONATION + UPDATE INVENTORY
CREATE OR REPLACE FUNCTION register_donation(
    p_donor_id    INT,
    p_bank_id     INT,
    p_blood_group VARCHAR,
    p_units       NUMERIC,
    p_type        VARCHAR DEFAULT 'Whole Blood'
) RETURNS INT AS $$
DECLARE
    v_donation_id INT;
    v_unit_code   VARCHAR;
    v_expiry      DATE;
BEGIN
    -- Insert donation record
    INSERT INTO donations (donor_id, bank_id, blood_group, units_donated, donation_type, status)
    VALUES (p_donor_id, p_bank_id, p_blood_group, p_units, p_type, 'Approved')
    RETURNING donation_id INTO v_donation_id;

    -- Generate unit code
    v_unit_code := 'BU-' || TO_CHAR(NOW(),'YYYYMMDD') || '-' ||
                   LPAD(v_donation_id::TEXT,6,'0');
    -- Expiry: 35 days for whole blood, 5 days platelets
    v_expiry := CURRENT_DATE + CASE p_type WHEN 'Platelets' THEN 5 ELSE 35 END;

    -- Insert blood unit
    INSERT INTO blood_units
        (donation_id, bank_id, blood_group, component, unit_code,
         collected_date, expiry_date, location_bank, status)
    VALUES
        (v_donation_id, p_bank_id, p_blood_group, p_type, v_unit_code,
         CURRENT_DATE, v_expiry, p_bank_id, 'Available');

    -- Update aggregate inventory (upsert)
    INSERT INTO blood_inventory (bank_id, blood_group, component, units_available)
    VALUES (p_bank_id, p_blood_group, p_type, p_units::INT)
    ON CONFLICT (bank_id, blood_group, component)
    DO UPDATE SET units_available = blood_inventory.units_available + p_units::INT,
                  last_updated    = NOW();

    -- Update donor record
    UPDATE donors
    SET last_donation   = CURRENT_DATE,
        next_eligible   = CURRENT_DATE + 90,
        total_donations = total_donations + 1,
        is_eligible     = FALSE   -- re-enabled after 90 days by scheduled job
    WHERE donor_id = p_donor_id;

    RETURN v_donation_id;
END;
$$ LANGUAGE plpgsql;


-- ── 3. FIND NEAREST AVAILABLE BLOOD (network search)
CREATE OR REPLACE FUNCTION find_blood(
    p_blood_group VARCHAR,
    p_component   VARCHAR,
    p_units_needed INT,
    p_city        VARCHAR DEFAULT NULL
) RETURNS TABLE (
    bank_id     INT,
    bank_name   VARCHAR,
    city        VARCHAR,
    available   INT,
    distance_km NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        bb.bank_id,
        bb.bank_name,
        bb.city,
        bi.units_available - bi.units_reserved AS available,
        NULL::NUMERIC AS distance_km
    FROM blood_inventory bi
    JOIN blood_banks bb ON bi.bank_id = bb.bank_id
    WHERE bi.blood_group = p_blood_group
      AND bi.component   = p_component
      AND bi.units_available - bi.units_reserved >= p_units_needed
      AND bb.is_active   = TRUE
      AND (p_city IS NULL OR bb.city ILIKE '%' || p_city || '%')
    ORDER BY bb.city = p_city DESC, available DESC;
END;
$$ LANGUAGE plpgsql;


-- ── 4. INTER-BANK TRANSFER
CREATE OR REPLACE FUNCTION transfer_blood(
    p_unit_id      INT,
    p_from_bank    INT,
    p_to_bank      INT,
    p_user_id      INT,
    p_reason       TEXT
) RETURNS INT AS $$
DECLARE v_transfer_id INT;
BEGIN
    -- Validate unit is Available at source
    IF NOT EXISTS (
        SELECT 1 FROM blood_units
        WHERE unit_id = p_unit_id
          AND location_bank = p_from_bank
          AND status = 'Available'
    ) THEN
        RAISE EXCEPTION 'Unit % not available at bank %.', p_unit_id, p_from_bank;
    END IF;

    -- Mark in transit
    UPDATE blood_units
    SET status = 'Transferred', location_bank = p_to_bank
    WHERE unit_id = p_unit_id;

    -- Update inventory: deduct source, add destination
    UPDATE blood_inventory bi
    SET units_available = units_available - 1
    FROM blood_units bu
    WHERE bi.bank_id    = p_from_bank
      AND bi.blood_group = bu.blood_group
      AND bi.component   = bu.component
      AND bu.unit_id     = p_unit_id;

    UPDATE blood_inventory bi
    SET units_available = units_available + 1
    FROM blood_units bu
    WHERE bi.bank_id    = p_to_bank
      AND bi.blood_group = bu.blood_group
      AND bi.component   = bu.component
      AND bu.unit_id     = p_unit_id;

    -- Log transfer
    INSERT INTO transfer_logs
        (unit_id, from_bank_id, to_bank_id, transferred_by, reason)
    VALUES (p_unit_id, p_from_bank, p_to_bank, p_user_id, p_reason)
    RETURNING transfer_id INTO v_transfer_id;

    RETURN v_transfer_id;
END;
$$ LANGUAGE plpgsql;


-- ── 5. COORDINATE EMERGENCY (auto-assign nearest banks)
CREATE OR REPLACE FUNCTION coordinate_emergency(
    p_emergency_id INT,
    p_coordinator_id INT
) RETURNS TEXT AS $$
DECLARE
    v_emergency emergency_requests%ROWTYPE;
    v_msg TEXT := '';
BEGIN
    SELECT * INTO v_emergency FROM emergency_requests
    WHERE emergency_id = p_emergency_id FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'Emergency #% not found.', p_emergency_id; END IF;

    UPDATE emergency_requests
    SET status = 'Coordinating', coordinator_id = p_coordinator_id
    WHERE emergency_id = p_emergency_id;

    -- Log coordination action
    INSERT INTO audit_logs (user_id, action, table_name, record_id, new_value)
    VALUES (p_coordinator_id, 'COORDINATE_EMERGENCY', 'emergency_requests',
            p_emergency_id, 'Status → Coordinating');

    v_msg := 'Emergency #' || p_emergency_id
          || ' is now being coordinated by user ' || p_coordinator_id;
    RETURN v_msg;
END;
$$ LANGUAGE plpgsql;


-- ── 6. EXPIRE OLD BLOOD UNITS (maintenance)
CREATE OR REPLACE FUNCTION expire_blood_units()
RETURNS INT AS $$
DECLARE v_count INT;
BEGIN
    UPDATE blood_units
    SET status = 'Expired'
    WHERE status = 'Available' AND expiry_date < CURRENT_DATE;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    -- Deduct expired from inventory
    UPDATE blood_inventory bi
    SET units_available = GREATEST(0, units_available - sub.expired_count),
        last_updated    = NOW()
    FROM (
        SELECT location_bank, blood_group, component, COUNT(*) AS expired_count
        FROM blood_units
        WHERE status = 'Expired' AND expiry_date = CURRENT_DATE - 1
        GROUP BY location_bank, blood_group, component
    ) sub
    WHERE bi.bank_id    = sub.location_bank
      AND bi.blood_group = sub.blood_group
      AND bi.component   = sub.component;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql;


-- ================================================================
--  TRIGGERS
-- ================================================================

-- Auto-log inventory changes for audit
CREATE OR REPLACE FUNCTION audit_inventory_change() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_logs (action, table_name, record_id, old_value, new_value)
    VALUES (
        'INVENTORY_UPDATE',
        'blood_inventory',
        NEW.inventory_id,
        'units=' || OLD.units_available,
        'units=' || NEW.units_available
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_inventory
AFTER UPDATE ON blood_inventory
FOR EACH ROW
WHEN (OLD.units_available <> NEW.units_available)
EXECUTE FUNCTION audit_inventory_change();

-- Auto set donor ineligible after donation, re-enable after 90 days
CREATE OR REPLACE FUNCTION update_donor_eligibility() RETURNS TRIGGER AS $$
BEGIN
    -- Enable eligibility when next_eligible date has passed
    UPDATE donors
    SET is_eligible = TRUE
    WHERE is_eligible = FALSE
      AND next_eligible <= CURRENT_DATE;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ================================================================
--  COMPATIBILITY RULES  (standard transfusion medicine)
-- ================================================================
INSERT INTO compatibility_rules (donor_group, recipient_group, is_compatible, notes) VALUES
('O-','O-',TRUE,'Universal donor for O-'),('O-','O+',TRUE,NULL),
('O-','A-',TRUE,NULL),('O-','A+',TRUE,NULL),
('O-','B-',TRUE,NULL),('O-','B+',TRUE,NULL),
('O-','AB-',TRUE,NULL),('O-','AB+',TRUE,'Universal donor'),
('O+','O+',TRUE,NULL),('O+','A+',TRUE,NULL),
('O+','B+',TRUE,NULL),('O+','AB+',TRUE,NULL),
('O+','O-',FALSE,'Rh incompatible'),('O+','A-',FALSE,NULL),
('A-','A-',TRUE,NULL),('A-','A+',TRUE,NULL),
('A-','AB-',TRUE,NULL),('A-','AB+',TRUE,NULL),
('A+','A+',TRUE,NULL),('A+','AB+',TRUE,NULL),
('B-','B-',TRUE,NULL),('B-','B+',TRUE,NULL),
('B-','AB-',TRUE,NULL),('B-','AB+',TRUE,NULL),
('B+','B+',TRUE,NULL),('B+','AB+',TRUE,NULL),
('AB-','AB-',TRUE,NULL),('AB-','AB+',TRUE,NULL),
('AB+','AB+',TRUE,'Universal recipient can only receive AB+'),
('AB+','AB-',FALSE,NULL);


-- ================================================================
--  SAMPLE DATA
-- ================================================================

-- Users
INSERT INTO users (username,full_name,email,phone,password_hash,role) VALUES
('superadmin',  'System Admin',          'admin@bloodnet.in',     '9900000001','hash','super_admin'),
('coord_delhi',  'Rahul Verma',           'rahul@bloodnet.in',     '9811000001','hash','coordinator'),
('coord_mumbai', 'Priya Nair',            'priya@bloodnet.in',     '9822000002','hash','coordinator'),
('bank_admin1',  'Suresh Kumar',          'suresh@aiims.in',       '9833000003','hash','bank_admin'),
('bank_admin2',  'Meena Pillai',          'meena@kgh.in',          '9844000004','hash','bank_admin'),
('hosp_staff1',  'Dr. Anjali Singh',      'anjali@apollo.com',     '9855000005','hash','hospital_staff'),
('hosp_staff2',  'Dr. Karan Mehta',       'karan@fortis.com',      '9866000006','hash','hospital_staff'),
('donor_arjun',  'Arjun Sharma',          'arjun@gmail.com',       '9877000007','hash','donor'),
('donor_priya',  'Priya Desai',           'priya.d@gmail.com',     '9888000008','hash','donor'),
('donor_rohit',  'Rohit Patel',           'rohit@gmail.com',       '9899000009','hash','donor');

-- Blood Banks (Decentralized Nodes)
INSERT INTO blood_banks (bank_name,city,state,address,latitude,longitude,phone,email,admin_user_id,capacity_units,is_24h) VALUES
('AIIMS Blood Bank',           'New Delhi',  'Delhi',       'Ansari Nagar, New Delhi',     28.568446, 77.209744,'011-26588700','aiims@bloodnet.in',  4,1000,TRUE),
('KEM Hospital Blood Bank',    'Mumbai',     'Maharashtra', 'Acharya Donde Marg, Mumbai',  18.982012, 72.840073,'022-24107000','kem@bloodnet.in',    5, 800,TRUE),
('NIMHANS Blood Bank',         'Bengaluru',  'Karnataka',   'Hosur Road, Bengaluru',       12.938614, 77.593140,'080-46110000','nimhans@bloodnet.in',4, 600,TRUE),
('Postgraduate Medical Blood', 'Chandigarh', 'Punjab',      'Sector 12, Chandigarh',       30.765130, 76.786940,'0172-2756565','pgimer@bloodnet.in', 4, 500,TRUE),
('Osmania Hospital Blood Bank','Hyderabad',  'Telangana',   'Afzalgunj, Hyderabad',        17.386690, 78.472432,'040-24600235','osmania@bloodnet.in',5, 700,FALSE);

-- Hospitals
INSERT INTO hospitals (hospital_name,city,state,address,latitude,longitude,phone,type,linked_bank_id,emergency_contact) VALUES
('Apollo Hospital Delhi',       'New Delhi', 'Delhi',       'Sarita Vihar',         28.530100,77.284000,'011-71791090','Private', 1,'Dr. Sharma 9811001100'),
('Fortis Hospital Mumbai',      'Mumbai',    'Maharashtra', 'Mulund West',          19.173700,72.956400,'022-42082020','Private', 2,'Dr. Nair 9822001100'),
('All India Medical Delhi',     'New Delhi', 'Delhi',       'ITO New Delhi',        28.635100,77.235600,'011-23234567','Government',1,'Dr. Verma 9833001100'),
('Manipal Hospital Bengaluru',  'Bengaluru', 'Karnataka',   'HAL Airport Road',     12.960000,77.640000,'080-25024444','Private', 3,'Dr. Rao 9844001100'),
('Government Hyderabad General','Hyderabad', 'Telangana',   'Nampally, Hyderabad',  17.394100,78.468600,'040-23450000','Government',5,'Dr. Reddy 9855001100');

-- Donors
INSERT INTO donors (user_id,full_name,date_of_birth,gender,blood_group,phone,email,city,state,weight_kg,is_eligible,last_donation,next_eligible,total_donations,preferred_bank) VALUES
(8, 'Arjun Sharma', '1992-03-15','Male',  'O+', '9877000007','arjun@gmail.com',  'New Delhi','Delhi',      72.5,TRUE, '2025-12-15','2026-03-15',8,1),
(9, 'Priya Desai',  '1995-07-22','Female','A+', '9888000008','priya.d@gmail.com','Mumbai',   'Maharashtra',60.0,TRUE, '2026-01-10','2026-04-10',3,2),
(10,'Rohit Patel',  '1988-11-08','Male',  'B+', '9899000009','rohit@gmail.com',  'Bengaluru','Karnataka',  80.0,TRUE, '2025-11-20','2026-02-20',12,3),
(NULL,'Sneha Rao',  '1990-05-30','Female','AB+','9877100010','sneha@gmail.com',  'Hyderabad','Telangana',  57.0,FALSE,'2026-03-01','2026-06-01',2,5),
(NULL,'Vikram Singh','1985-09-14','Male', 'O-', '9877200011','vikram@gmail.com', 'New Delhi','Delhi',       88.0,TRUE, '2025-10-10','2026-01-10',20,1),
(NULL,'Kavita Nair', '1993-02-18','Female','A-','9877300012','kavita@gmail.com', 'Mumbai',   'Maharashtra',55.0,TRUE, '2026-02-01','2026-05-01',5,2);

-- Donations (sample)
INSERT INTO donations (donor_id,bank_id,donation_date,blood_group,units_donated,donation_type,status,hemoglobin_level) VALUES
(1,1,'2026-01-15','O+', 1.0,'Whole Blood','Approved',13.5),
(2,2,'2026-02-10','A+', 1.0,'Whole Blood','Approved',12.8),
(3,3,'2026-01-28','B+', 1.0,'Platelets',  'Approved',14.2),
(5,1,'2026-03-01','O-', 1.0,'Whole Blood','Approved',15.0),
(6,2,'2026-03-05','A-', 1.0,'Whole Blood','Approved',12.5);

-- Blood Inventory (aggregates per bank)
INSERT INTO blood_inventory (bank_id,blood_group,component,units_available,units_reserved,critical_level) VALUES
-- AIIMS Delhi
(1,'O+', 'Whole Blood',45,2,10),(1,'O-', 'Whole Blood',12,1,5),
(1,'A+', 'Whole Blood',30,0,8), (1,'A-', 'Whole Blood',8, 0,4),
(1,'B+', 'Whole Blood',25,1,8), (1,'B-', 'Whole Blood',4, 0,4),
(1,'AB+','Whole Blood',10,0,3), (1,'AB-','Whole Blood',3, 0,2),
-- KEM Mumbai
(2,'O+', 'Whole Blood',38,3,10),(2,'O-', 'Whole Blood',6, 2,5),
(2,'A+', 'Whole Blood',42,1,8), (2,'A-', 'Whole Blood',5, 0,4),
(2,'B+', 'Whole Blood',20,2,8), (2,'B-', 'Whole Blood',3, 0,4),
(2,'AB+','Whole Blood',8, 0,3), (2,'AB-','Whole Blood',2, 0,2),
-- NIMHANS Bengaluru
(3,'O+', 'Whole Blood',22,0,10),(3,'O-', 'Whole Blood',3, 0,5),
(3,'A+', 'Whole Blood',18,0,8), (3,'B+', 'Whole Blood',15,0,8),
-- Chandigarh PGIMER
(4,'O+', 'Whole Blood',31,1,10),(4,'A+', 'Whole Blood',24,0,8),
(4,'B+', 'Whole Blood',16,0,8), (4,'O-', 'Whole Blood',9, 0,5),
-- Osmania Hyderabad
(5,'O+', 'Whole Blood',28,2,10),(5,'A+', 'Whole Blood',19,1,8),
(5,'B+', 'Whole Blood',11,0,8), (5,'O-', 'Whole Blood',4, 1,5);

-- Blood Units (a few sample bags)
INSERT INTO blood_units (donation_id,bank_id,blood_group,component,unit_code,volume_ml,collected_date,expiry_date,status,location_bank,tested_for_hiv,tested_for_hbv,tested_for_hcv) VALUES
(1,1,'O+', 'Whole Blood','BU-20260115-000001',450,'2026-01-15','2026-02-19','Available',1,TRUE,TRUE,TRUE),
(2,2,'A+', 'Whole Blood','BU-20260210-000002',450,'2026-02-10','2026-03-17','Available',2,TRUE,TRUE,TRUE),
(3,3,'B+', 'Platelets',  'BU-20260128-000003',300,'2026-01-28','2026-02-02','Expired',  3,TRUE,TRUE,TRUE),
(4,1,'O-', 'Whole Blood','BU-20260301-000004',450,'2026-03-01','2026-04-05','Available',1,TRUE,TRUE,TRUE),
(5,2,'A-', 'Whole Blood','BU-20260305-000005',450,'2026-03-05','2026-04-09','Available',2,TRUE,TRUE,TRUE);

-- Blood Requests
INSERT INTO blood_requests (hospital_id,requested_by,patient_name,patient_age,blood_group,component,units_needed,units_fulfilled,urgency,reason,status,assigned_bank,needed_by) VALUES
(1,6,'Rajan Gupta',    45,'O+','Whole Blood',4,2,'Critical','Major surgery — cardiac bypass',  'Partially Fulfilled',1,NOW()+INTERVAL '2 hours'),
(2,7,'Meera Kulkarni', 28,'A+','Whole Blood',2,0,'Urgent',  'Post-delivery haemorrhage',       'Open',              NULL,NOW()+INTERVAL '4 hours'),
(3,6,'Unknown Patient',NULL,'O-','Whole Blood',6,0,'Critical','Road accident — trauma bay',    'Open',              NULL,NOW()+INTERVAL '1 hour'),
(4,7,'Suresh Babu',    62,'B+','Whole Blood',3,3,'Normal',  'Elective surgery preparation',   'Fulfilled',         3,NOW()-INTERVAL '2 hours'),
(5,6,'Fatima Sheikh',  35,'AB+','Platelets',  2,0,'Urgent',  'Chemotherapy — low platelet count','Open',           NULL,NOW()+INTERVAL '6 hours');

-- Emergency Requests
INSERT INTO emergency_requests (title,description,location,city,state,latitude,longitude,incident_type,severity,reported_by,coordinator_id,casualties_est,blood_needed,status) VALUES
('NH-8 Multi-Vehicle Pile-up',
 '14-vehicle accident near Gurgaon toll, 23 casualties, 8 critical',
 'NH-8, Kherki Daula Toll, Gurugram',
 'Gurugram','Haryana',28.459497,77.026638,
 'Road Accident','Critical',2,2,23,'O+:10,O-:6,A+:4,B+:3','Coordinating'),

('Yamuna Flood Relief — Blood Camp',
 'Flood displacement camp needs blood stock for 500+ affected persons',
 'Yamuna Ghat Relief Camp, Delhi',
 'New Delhi','Delhi',28.652960,77.244970,
 'Natural Disaster','High',2,NULL,NULL,'O+:20,A+:10,B+:8,O-:5','Active'),

('Chemical Plant Explosion — Manesar',
 'Industrial explosion at Maruti factory, burn victims',
 'IMT Manesar, Haryana',
 'Manesar','Haryana',28.369570,76.937130,
 'Industrial Accident','Critical',3,3,11,'AB+:4,O+:8,A+:5','Active');

-- Emergency Responses
INSERT INTO emergency_responses (emergency_id,bank_id,responder_id,blood_group,component,units_pledged,units_dispatched,dispatch_time,eta_minutes,status) VALUES
(1,1,'2','O+','Whole Blood', 10,8,NOW()-INTERVAL '30 min',45,'Dispatched'),
(1,4,'2','O-','Whole Blood',  6,6,NOW()-INTERVAL '20 min',90,'Dispatched'),
(1,1,'2','A+','Whole Blood',  4,4,NOW()-INTERVAL '25 min',45,'Delivered'),
(2,1,'3','O+','Whole Blood', 15,0,NULL,NULL,'Pledged'),
(2,2,'3','A+','Whole Blood', 10,0,NULL,NULL,'Pledged'),
(3,1,'2','O+','Whole Blood',  8,8,NOW()-INTERVAL '1 hour',60,'Delivered'),
(3,2,'3','AB+','Whole Blood', 4,2,NOW()-INTERVAL '45 min',120,'Dispatched');

-- Audit Logs (sample)
INSERT INTO audit_logs (user_id,action,table_name,record_id,new_value) VALUES
(2,'COORDINATE_EMERGENCY','emergency_requests',1,'Status → Coordinating'),
(3,'FULFILL_REQUEST',      'blood_requests',   4,'Fulfilled 3 units B+ from bank 3'),
(4,'REGISTER_DONATION',    'donations',        1,'Donor 1, O+, 1 unit at bank 1');

-- Transfer log (sample)
INSERT INTO transfer_logs (unit_id,from_bank_id,to_bank_id,transferred_by,reason,status) VALUES
(4,1,2,2,'Emergency supply for KEM Mumbai','Received');
