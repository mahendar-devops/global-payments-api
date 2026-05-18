-- deploy/init-db.sql
-- Runs automatically when the postgres container starts for the first time.
-- Creates both databases needed by the platform.

-- Payments database (used by payments-service)
CREATE DATABASE payments;
GRANT ALL PRIVILEGES ON DATABASE payments TO payments_user;

-- Reporting database (used by data-processing-service)
CREATE DATABASE payments_reporting;
GRANT ALL PRIVILEGES ON DATABASE payments_reporting TO payments_user;

-- Verify
\l payments
\l payments_reporting
