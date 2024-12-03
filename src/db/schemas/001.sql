-- This ID sequence is shared by users, organizations, and admins tables
CREATE SEQUENCE shared_id_seq;

CREATE TYPE GENDER AS ENUM ('male', 'female');
CREATE TYPE ID_TYPE AS ENUM ('id_card', 'passport');
CREATE TYPE FIDE_TITLE AS ENUM ('GM', 'IM', 'FM', 'CM', 'WGM', 'WIM', 'WFM', 'WCM');

CREATE TABLE users (
    id BIGINT PRIMARY KEY DEFAULT nextval('shared_id_seq'),
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email BYTEA NOT NULL UNIQUE,
    CONSTRAINT valid_email CHECK (
        email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'
    ),
    hashed_password VARCHAR(255) NOT NULL,
    gender GENDER,
    phone_no BYTEA UNIQUE,
    CONSTRAINT valid_phone_no CHECK (
        phone_no ~* '^\+[1-9][0-9]{1,14}$'
    ),
    birth_date DATE,
    CONSTRAINT valid_birth_date CHECK (
        birth_date <= CURRENT_DATE
    ),
    id_type ID_TYPE,
    id_no BYTEA,
    nationality VARCHAR(30),
    fide_id BIGINT UNIQUE,
    fide_title FIDE_TITLE,
    fide_rating SMALLINT,
    CONSTRAINT valid_fide_rating CHECK (fide_rating >= 0 AND fide_rating <= 3000),
    mcf_id BIGINT UNIQUE,
    mcf_rating SMALLINT,
    CONSTRAINT valid_mcf_rating CHECK (mcf_rating >= 0 AND mcf_rating <= 3000),
    is_oku BOOLEAN DEFAULT FALSE,
    -- For refund purposes
    bank_account_no BYTEA UNIQUE,
    bank_name BYTEA,
    profile_picture_url VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    verified_at TIMESTAMP,
    deleted_at TIMESTAMP
);

CREATE TYPE TIME_CONTROL_TYPE AS ENUM ('simple', 'increment', 'delay', 'multi_stage');

CREATE TABLE time_controls (
    id SMALLSERIAL PRIMARY KEY,
    type TIME_CONTROL_TYPE NOT NULL,
    -- For simple format like '1h30m'
    base_time INTERVAL NOT NULL,
    -- For increment/delay in seconds
    increment_seconds INTEGER,
    -- For multi-stage controls (like World Championship)
    stages JSONB,
    -- Example stages format:
    -- [
    --   {
    --     "moves": 40,
    --     "time": "2 hours",
    --     "increment_seconds": 0
    --   },
    --   {
    --     "moves": null,  -- null means "rest of the game"
    --     "time": "30 minutes",
    --     "increment_seconds": 30
    --   }
    -- ]
    CONSTRAINT valid_increment CHECK (increment_seconds >= 0),
    CONSTRAINT valid_stages CHECK (
        type != 'multi_stage' OR 
        (
            stages IS NOT NULL AND
            jsonb_typeof(stages) = 'array' AND
            jsonb_array_length(stages) > 0
        )
    )
);

-- OTB = On The Board (physical tournament)
CREATE TYPE TOURNAMENT_MODE AS ENUM ('otb', 'online');
CREATE TYPE TOURNAMENT_FORMAT AS ENUM ('swiss', 'round_robin', 'single_elimination', 'double_elimination');
CREATE TYPE TOURNAMENT_CATEGORY AS ENUM ('open', 'women', 'junior', 'senior');
CREATE TYPE TOURNAMENT_STATUS AS ENUM ('planned', 'ongoing', 'completed', 'postponed', 'cancelled');
CREATE TYPE GAME_VARIANT AS ENUM ('standard', 'chess960');
CREATE TYPE GAME_SPEED AS ENUM ('blitz', 'rapid', 'classical');

CREATE TABLE tournaments (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    mode TOURNAMENT_MODE NOT NULL DEFAULT 'otb',
    format TOURNAMENT_FORMAT NOT NULL DEFAULT 'swiss',
    category TOURNAMENT_CATEGORY NOT NULL DEFAULT 'open',
    status TOURNAMENT_STATUS NOT NULL DEFAULT 'planned',
    game_variant GAME_VARIANT NOT NULL DEFAULT 'standard',
    game_speed GAME_SPEED NOT NULL DEFAULT 'classical',
    time_control_id SMALLINT REFERENCES time_controls(id) ON DELETE SET NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    CONSTRAINT valid_dates CHECK (
        end_date >= start_date
    ),
    location VARCHAR(100) NOT NULL,
    state VARCHAR(50),
    country VARCHAR(50),
    is_fide_rated BOOLEAN DEFAULT FALSE,
    is_mcf_rated BOOLEAN DEFAULT FALSE,
    registration_fee NUMERIC(5,2) NOT NULL,
    CONSTRAINT positive_registration_fee CHECK (registration_fee > 0 AND registration_fee <= 1000),
    registration_opens_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    registration_closes_at TIMESTAMP NOT NULL DEFAULT (start_date::timestamp - INTERVAL '1 day'),
    CONSTRAINT valid_registration CHECK (
        registration_opens_at < registration_closes_at AND
        registration_closes_at <= start_date::timestamp
    ),
    max_players SMALLINT NOT NULL,
    CONSTRAINT valid_max_players CHECK (max_players > 0),
    min_rating SMALLINT,
    CONSTRAINT valid_min_rating CHECK (min_rating >= 0),
    max_rating SMALLINT,
    CONSTRAINT valid_max_rating CHECK (max_rating >= 0),
    CONSTRAINT valid_rating_range CHECK (
        IF (
            min_rating IS NOT NULL AND
            max_rating IS NOT NULL,
            min_rating <= max_rating,
            TRUE
        )
    ),
    poster_url VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    updated_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
    deleted_at TIMESTAMP
) PARTITION BY RANGE (start_date);

CREATE TABLE tournaments_2025
    PARTITION OF tournaments
    FOR VALUES FROM ('2025-01-01') TO ('2025-12-31');

CREATE TABLE schedules (
    tournament_id BIGINT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
    agenda VARCHAR(20) NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP NOT NULL,
    CONSTRAINT valid_schedule_times CHECK (end_time > start_time),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
    PRIMARY KEY (tournament_id, agenda)
);

CREATE TABLE prizes (
    tournament_id BIGINT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
    prize_rank VARCHAR(10) NOT NULL,
    prize_amount NUMERIC(7,2) NOT NULL,
    CONSTRAINT positive_prize_amount CHECK (prize_amount > 0),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
    PRIMARY KEY (tournament_id, prize_rank)
);

CREATE TABLE organizations (
    id BIGINT PRIMARY KEY DEFAULT nextval('shared_id_seq'),
    owner_id BIGINT NOT NULL REFERENCES users(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL UNIQUE,
    bank_account_no BYTEA NOT NULL UNIQUE,
    bank_name BYTEA NOT NULL,
    profile_picture_url VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    verified_at TIMESTAMP,
    deleted_at TIMESTAMP
);

-- A user can be associated with multiple organizations and an organization can have multiple users
CREATE TABLE organization_members (
    organization_id BIGINT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE SET NULL,
    role VARCHAR(255),
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, organization_id)
);

CREATE TABLE admins (
    id BIGINT PRIMARY KEY DEFAULT nextval('shared_id_seq'),
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    hashed_password VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    deleted_at TIMESTAMP
);

CREATE TYPE TRANSACTION_TYPE AS ENUM ('payment', 'withdrawal', 'refund');
CREATE TYPE TRANSACTION_STATUS AS ENUM ('pending', 'successful', 'failed', 'cancelled');

CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id BIGINT NOT NULL REFERENCES tournaments(id) ON DELETE RESTRICT,
    -- paid_by and paid_to can be either users.id, admins.id, or organizations.id
    -- No constraint is added here as it can become expensive to execute with large datasets
    -- Validation will be done in the application layer
    paid_by BIGINT NOT NULL,
    paid_to BIGINT NOT NULL,
    trx_type TRANSACTION_TYPE NOT NULL,
    trx_status TRANSACTION_STATUS NOT NULL DEFAULT 'pending',
    trx_amount NUMERIC(7,2) NOT NULL,
    CONSTRAINT positive_amount CHECK (trx_amount > 0),
    payment_method VARCHAR(50),
    payment_reference VARCHAR(100),
    processed_at TIMESTAMP,
);

-- A player can be registered to multiple tournaments and a tournament can have multiple players
CREATE TABLE registrations (
    tournament_id BIGINT NOT NULL REFERENCES tournaments(id) ON DELETE RESTRICT,
    player_id BIGINT NOT NULL REFERENCES users(id) ON DELETE SET NULL,
    registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    payment_id UUID REFERENCES transactions(id) ON DELETE RESTRICT,
    PRIMARY KEY (tournament_id, player_id)
);

CREATE TABLE roles (
    id SMALLSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE
);

-- A user can have multiple roles and a role can be associated with multiple users
CREATE TABLE users_roles (
    user_id BIGINT NOT NULL,
    CONSTRAINT fk_user_id CHECK (
        EXISTS (SELECT 1 FROM users WHERE id = user_id) OR
        EXISTS (SELECT 1 FROM admins WHERE id = user_id)
    ),
    role_id SMALLINT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);

CREATE TABLE permissions (
    id SMALLSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE
);

-- A role can have multiple permissions and a permission can be associated with multiple roles
CREATE TABLE roles_permissions (
    role_id SMALLINT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id SMALLINT NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- A tournament can have multiple organizers and an organizer can organize multiple tournaments
CREATE TABLE tournaments_organizers (
    tournament_id BIGINT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
    organizer_id BIGINT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    PRIMARY KEY (tournament_id, organizer_id)
);

-- Audit logs are partitioned by the performed_at column
-- This table is used to track changes to any table in the database,
-- except for audit_logs itself and transactions tables
CREATE TABLE audit_logs (
    id BIGSERIAL,
    table_name VARCHAR(50) NOT NULL,
    record_id BIGINT NOT NULL,
    action VARCHAR(10) NOT NULL,
    old_data JSONB,
    new_data JSONB,
    performed_by BIGINT NOT NULL,
    performed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, performed_at)
) PARTITION BY RANGE (performed_at);

CREATE OR REPLACE FUNCTION create_audit_log_partition()
RETURNS void AS $$
DECLARE
    next_quarter_start DATE;
    partition_name TEXT;
    partition_sql TEXT;
BEGIN
    -- Calculate the start of next quarter
    next_quarter_start := DATE_TRUNC('quarter', NOW()) + INTERVAL '1 quarter';
    
    -- Generate partition name
    partition_name := 'audit_logs_' || TO_CHAR(next_quarter_start, 'YYYY_"q"Q');
    
    -- Check if partition exists
    IF NOT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = partition_name
    ) THEN
        -- Create the partition
        partition_sql := FORMAT(
            'CREATE TABLE %I PARTITION OF audit_logs
            FOR VALUES FROM (%L) TO (%L)',
            partition_name,
            next_quarter_start,
            next_quarter_start + INTERVAL '1 quarter'
        );
        
        EXECUTE partition_sql;
        
        RAISE NOTICE 'Created partition: %', partition_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_encryption_key()
RETURNS TEXT AS $$
BEGIN
    -- TODO: Replace with a secure key from the environment variables
    RETURN 'your-secure-key-here';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION encrypt_sensitive_data(p_plain_text TEXT)
RETURNS BYTEA AS $$
BEGIN
    RETURN pgp_sym_encrypt(
        p_plain_text,
        get_encryption_key()
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION decrypt_sensitive_data(p_encrypted_data BYTEA)
RETURNS TEXT AS $$
BEGIN
    RETURN pgp_sym_decrypt(
        p_encrypted_data,
        get_encryption_key()
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add triggers for tables with updated_at
CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON tournaments
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON schedules
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON prizes
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON organizations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- Create a function to handle soft deletes
CREATE OR REPLACE FUNCTION handle_soft_delete()
RETURNS TRIGGER AS $$
BEGIN
    -- Don't actually delete the record, just update deleted_at
    NEW.deleted_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for each table with soft delete
CREATE TRIGGER soft_delete_users
    BEFORE DELETE ON users
    FOR EACH ROW
    WHEN (OLD.deleted_at IS NULL)
    EXECUTE FUNCTION handle_soft_delete();

CREATE TRIGGER soft_delete_tournaments
    BEFORE DELETE ON tournaments
    FOR EACH ROW
    WHEN (OLD.deleted_at IS NULL)
    EXECUTE FUNCTION handle_soft_delete();

CREATE TRIGGER soft_delete_organizations
    BEFORE DELETE ON organizations
    FOR EACH ROW
    WHEN (OLD.deleted_at IS NULL)
    EXECUTE FUNCTION handle_soft_delete();

CREATE TRIGGER soft_delete_admins
    BEFORE DELETE ON admins
    FOR EACH ROW
    WHEN (OLD.deleted_at IS NULL)
    EXECUTE FUNCTION handle_soft_delete();
