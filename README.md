# 🩸 BloodNet — Decentralized Blood Bank & Emergency Coordination
## DBMS Project v1.0

---

## 📁 Project Structure

```
bloodbank_dbms/
├── index.html          ← Web Dashboard (open in browser)
├── README.md           ← This file
└── sql/
    ├── schema.sql      ← Full schema + functions + triggers + sample data
    └── queries.sql     ← SQL query reference sheet
```

---

## 🗃️ Database Tables (13 Tables)

| Table                  | Purpose                                            |
|------------------------|----------------------------------------------------|
| `users`                | Staff, coordinators, donors, admins                |
| `blood_banks`          | Decentralized bank nodes with geolocation          |
| `hospitals`            | Requesting entities linked to banks                |
| `compatibility_rules`  | ABO + Rh compatibility matrix (28 rules)           |
| `donors`               | Donor registry with eligibility tracking           |
| `donations`            | Individual donation collection records             |
| `blood_units`          | Per-bag tracking with barcode, expiry, location    |
| `blood_inventory`      | Aggregate stock per bank per blood group           |
| `blood_requests`       | Hospital requests with urgency triage              |
| `emergency_requests`   | Mass casualty / disaster events                    |
| `emergency_responses`  | Bank response pledges and dispatch tracking        |
| `transfer_logs`        | Inter-bank blood unit routing                      |
| `audit_logs`           | Full action audit trail                            |

---

## ⚡ Key DBMS Features

### Stored Functions (6)
| Function | Description |
|----------|-------------|
| `fulfill_request(request_id, bank_id, units)` | Atomic fulfillment with FIFO expiry-first dispatch |
| `register_donation(donor_id, bank_id, group, units, type)` | One-call donation → unit → inventory update |
| `find_blood(group, component, units, city)` | Network-wide blood search with optional city filter |
| `transfer_blood(unit_id, from, to, user, reason)` | Inter-bank transfer with inventory sync |
| `coordinate_emergency(emergency_id, coordinator_id)` | Assign coordinator + activate response tracking |
| `expire_blood_units()` | Maintenance: mark expired units + deduct inventory |

### Views (5)
| View | Purpose |
|------|---------|
| `vw_network_inventory` | Live stock with CRITICAL/OK status across all banks |
| `vw_open_requests` | Priority-sorted open requests with hours_left |
| `vw_eligible_donors` | Donors ready to donate right now |
| `vw_expiring_soon` | Units expiring within 7 days |
| `vw_active_emergencies` | Emergency summary with response counts |

### Triggers (2)
- `trg_audit_inventory` — auto-logs every inventory change
- `update_donor_eligibility()` — auto-resets donor eligibility after 90 days

### Key Constraints
- `CHECK` on urgency, status, incident_type, role, gender, severity
- `UNIQUE` on (bank_id, blood_group, component) in inventory
- `UNIQUE` on unit_code (barcode)
- FIFO dispatch: oldest expiry first via `ORDER BY expiry_date ASC`
- 90-day donor cooldown enforced in `register_donation()`

---

## 🚀 Setup

### Prerequisites
- PostgreSQL 14+

### Steps

```bash
# 1. Create database
createdb bloodbank_db

# 2. Run full schema (tables, views, functions, compatibility rules, sample data)
psql -U postgres -d bloodbank_db -f sql/schema.sql

# 3. Explore queries
psql -U postgres -d bloodbank_db -f sql/queries.sql

# 4. Open dashboard
open index.html
```

### Quick test commands:
```sql
-- Check network inventory
SELECT * FROM vw_network_inventory WHERE stock_status = 'CRITICAL';

-- Find O- blood in Delhi
SELECT * FROM find_blood('O-', 'Whole Blood', 2, 'Delhi');

-- Register a donation
SELECT register_donation(5, 1, 'O-', 1.0, 'Whole Blood');

-- Fulfill critical request
SELECT fulfill_request(3, 1, 6);

-- Check active emergencies
SELECT * FROM vw_active_emergencies;
```

---

## 📊 Sample Data

| Entity | Records |
|--------|---------|
| Users | 10 (1 super admin, 2 coordinators, 2 bank admins, 2 hospital staff, 3 donors) |
| Blood Banks | 5 (Delhi, Mumbai, Bengaluru, Chandigarh, Hyderabad) |
| Hospitals | 5 (Apollo, Fortis, AIIM, Manipal, Govt General) |
| Donors | 6 |
| Donations | 5 |
| Blood Units | 5 bags |
| Inventory | 24 entries across 5 banks × 8 groups |
| Blood Requests | 5 (3 open, 1 partial, 1 fulfilled) |
| Emergency Requests | 3 (2 Critical, 1 High) |
| Emergency Responses | 7 |
| Compatibility Rules | 28 (complete ABO + Rh matrix) |

---

## 🌐 Dashboard Pages

| Page | Key Features |
|------|--------------|
| Dashboard | Network inventory grid, priority requests, bank status |
| Emergency Centre | Active emergencies with response tracker |
| Blood Requests | Urgency triage with fulfillment SQL |
| Network Inventory | Per-bank stock, critical alerts, expiry tracking |
| Donors | Eligibility registry with cooldown status |
| Donations | Donation history with Hb levels |
| Transfers | Inter-bank routing log |
| ER Schema | All 13 table boxes with field details |
| SQL Queries | Complete reference for all key queries |

---

*DBMS Project — Decentralized Blood Bank & Emergency Coordination System*
