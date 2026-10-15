-- ================================================================
--   DECENTRALIZED BLOOD BANK & EMERGENCY COORDINATION
--   SQL Query Reference Sheet
-- ================================================================

-- ─────────────────────────────────────────
-- 1. INVENTORY QUERIES
-- ─────────────────────────────────────────

-- Full network inventory (all banks, all groups)
SELECT bank_name, city, blood_group, component,
       units_available, units_reserved, net_available, stock_status
FROM vw_network_inventory
ORDER BY stock_status DESC, bank_name, blood_group;

-- Critical stock alert across network
SELECT bank_name, city, blood_group, net_available, critical_level
FROM vw_network_inventory
WHERE stock_status = 'CRITICAL'
ORDER BY net_available ASC;

-- Find blood across network (stored function)
SELECT * FROM find_blood('O-', 'Whole Blood', 2, 'Delhi');
SELECT * FROM find_blood('O-', 'Whole Blood', 2);  -- search all cities

-- Blood units expiring within 7 days
SELECT * FROM vw_expiring_soon;

-- Inventory by blood group (network total)
SELECT blood_group, component,
       SUM(units_available) AS total_network,
       SUM(units_reserved)  AS total_reserved,
       COUNT(DISTINCT bank_id) AS banks_stocking
FROM blood_inventory
GROUP BY blood_group, component
ORDER BY blood_group;


-- ─────────────────────────────────────────
-- 2. REQUEST QUERIES
-- ─────────────────────────────────────────

-- All open / urgent requests
SELECT * FROM vw_open_requests;

-- Critical requests only
SELECT request_id, hospital_name, city, blood_group,
       units_needed, units_pending, hours_left
FROM vw_open_requests
WHERE urgency = 'Critical'
ORDER BY hours_left ASC NULLS LAST;

-- Fulfill a blood request (stored function)
SELECT fulfill_request(
    1,    -- request_id
    1,    -- bank_id (AIIMS Delhi)
    2     -- units to fulfill
);

-- Request fulfillment rate
SELECT
    urgency,
    COUNT(*)                                           AS total,
    SUM(CASE WHEN status='Fulfilled' THEN 1 ELSE 0 END) AS fulfilled,
    ROUND(SUM(CASE WHEN status='Fulfilled' THEN 1 ELSE 0 END)::NUMERIC
          / COUNT(*) * 100, 1)                         AS fulfillment_pct,
    AVG(EXTRACT(EPOCH FROM (fulfilled_at - requested_at))/60) AS avg_minutes
FROM blood_requests
GROUP BY urgency
ORDER BY CASE urgency WHEN 'Critical' THEN 1 WHEN 'Urgent' THEN 2 ELSE 3 END;


-- ─────────────────────────────────────────
-- 3. DONOR QUERIES
-- ─────────────────────────────────────────

-- Eligible donors right now
SELECT * FROM vw_eligible_donors;

-- Find eligible donors by blood group in a city
SELECT donor_id, full_name, blood_group, phone, city, total_donations
FROM vw_eligible_donors
WHERE blood_group = 'O-' AND city = 'New Delhi'
ORDER BY total_donations DESC;

-- Register a donation (stored function)
SELECT register_donation(
    1,             -- donor_id (Arjun Sharma)
    1,             -- bank_id (AIIMS)
    'O+',          -- blood_group
    1.0,           -- units
    'Whole Blood'  -- type
);

-- Donor statistics
SELECT
    blood_group,
    COUNT(*)                            AS total_donors,
    COUNT(*) FILTER (WHERE is_eligible) AS eligible_now,
    SUM(total_donations)                AS total_donations
FROM donors
GROUP BY blood_group
ORDER BY blood_group;

-- Top donors by lifetime donations
SELECT full_name, blood_group, city,
       total_donations, last_donation, next_eligible
FROM donors
ORDER BY total_donations DESC
LIMIT 10;


-- ─────────────────────────────────────────
-- 4. EMERGENCY COORDINATION QUERIES
-- ─────────────────────────────────────────

-- Active emergencies summary
SELECT * FROM vw_active_emergencies;

-- Coordinate an emergency
SELECT coordinate_emergency(2, 3);  -- emergency_id, coordinator_user_id

-- Emergency response tracker
SELECT
    er.emergency_id, eq.title, eq.severity,
    bb.bank_name, bb.city,
    er.blood_group, er.units_pledged, er.units_dispatched,
    er.status, er.eta_minutes,
    er.responded_at
FROM emergency_responses er
JOIN emergency_requests eq ON er.emergency_id = eq.emergency_id
JOIN blood_banks        bb ON er.bank_id       = bb.bank_id
WHERE eq.status IN ('Active','Coordinating')
ORDER BY eq.severity DESC, er.responded_at;

-- Total blood dispatched per emergency
SELECT
    eq.title, eq.city, eq.severity, eq.casualties_est,
    SUM(er.units_dispatched)  AS dispatched,
    SUM(er.units_pledged)     AS pledged,
    COUNT(DISTINCT er.bank_id) AS banks_involved
FROM emergency_requests eq
JOIN emergency_responses er ON eq.emergency_id = er.emergency_id
GROUP BY eq.emergency_id, eq.title, eq.city, eq.severity, eq.casualties_est
ORDER BY dispatched DESC;

-- Response time analysis
SELECT
    bb.bank_name,
    COUNT(er.response_id)                    AS responses,
    AVG(er.units_pledged)                    AS avg_units_pledged,
    SUM(er.units_dispatched)                 AS total_dispatched,
    AVG(er.eta_minutes)                      AS avg_eta_min
FROM emergency_responses er
JOIN blood_banks bb ON er.bank_id = bb.bank_id
GROUP BY bb.bank_id, bb.bank_name
ORDER BY total_dispatched DESC;


-- ─────────────────────────────────────────
-- 5. TRANSFER QUERIES
-- ─────────────────────────────────────────

-- Transfer a blood unit between banks
SELECT transfer_blood(
    4,             -- unit_id
    1,             -- from_bank_id (AIIMS)
    2,             -- to_bank_id (KEM Mumbai)
    2,             -- transferred_by (coordinator)
    'Emergency supply for road accident response'
);

-- Transfer log report
SELECT
    tl.transfer_id,
    bu.unit_code, bu.blood_group, bu.component,
    fb.bank_name AS from_bank,
    tb.bank_name AS to_bank,
    tl.status,
    tl.transfer_date
FROM transfer_logs tl
JOIN blood_units bu ON tl.unit_id     = bu.unit_id
JOIN blood_banks fb ON tl.from_bank_id = fb.bank_id
JOIN blood_banks tb ON tl.to_bank_id   = tb.bank_id
ORDER BY tl.transfer_date DESC;


-- ─────────────────────────────────────────
-- 6. COMPATIBILITY QUERIES
-- ─────────────────────────────────────────

-- What blood groups can donate to AB+?
SELECT donor_group, notes
FROM compatibility_rules
WHERE recipient_group = 'AB+' AND is_compatible = TRUE;

-- What groups can O- donate to?
SELECT recipient_group
FROM compatibility_rules
WHERE donor_group = 'O-' AND is_compatible = TRUE;

-- Full compatibility matrix
SELECT donor_group,
    STRING_AGG(recipient_group, ', ' ORDER BY recipient_group)
        FILTER (WHERE is_compatible = TRUE) AS can_donate_to
FROM compatibility_rules
GROUP BY donor_group
ORDER BY donor_group;


-- ─────────────────────────────────────────
-- 7. ANALYTICS & REPORTS
-- ─────────────────────────────────────────

-- Monthly donation trends
SELECT
    TO_CHAR(donation_date,'YYYY-MM') AS month,
    blood_group,
    COUNT(*)         AS donations,
    SUM(units_donated) AS total_units
FROM donations
WHERE status = 'Approved'
GROUP BY TO_CHAR(donation_date,'YYYY-MM'), blood_group
ORDER BY month DESC, blood_group;

-- Bank performance score
SELECT
    bb.bank_name, bb.city,
    COUNT(DISTINCT d.donation_id)   AS donations_received,
    COUNT(DISTINCT r.request_id)    AS requests_handled,
    COUNT(DISTINCT er.response_id)  AS emergency_responses,
    SUM(bi.units_available)         AS current_stock
FROM blood_banks bb
LEFT JOIN donations        d  ON bb.bank_id = d.bank_id
LEFT JOIN blood_requests   r  ON bb.bank_id = r.assigned_bank
LEFT JOIN emergency_responses er ON bb.bank_id = er.bank_id
LEFT JOIN blood_inventory  bi ON bb.bank_id = bi.bank_id
GROUP BY bb.bank_id, bb.bank_name, bb.city
ORDER BY emergency_responses DESC;

-- Expire blood units (maintenance call)
SELECT expire_blood_units();

-- Audit trail for last 24h
SELECT
    u.full_name, al.action, al.table_name,
    al.record_id, al.new_value, al.logged_at
FROM audit_logs al
LEFT JOIN users u ON al.user_id = u.user_id
WHERE al.logged_at >= NOW() - INTERVAL '24 hours'
ORDER BY al.logged_at DESC;
