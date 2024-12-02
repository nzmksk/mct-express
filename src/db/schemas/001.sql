-- This ID sequence is shared by users, organizations, and admins tables
CREATE SEQUENCE shared_id_seq;

CREATE TYPE GENDER AS ENUM ('male', 'female');
CREATE TYPE ID_TYPE AS ENUM ('id_card', 'passport');
CREATE TYPE FIDE_TITLE AS ENUM ('GM', 'IM', 'FM', 'CM', 'WGM', 'WIM', 'WFM', 'WCM');

CREATE TABLE users (
    id BIGINT PRIMARY KEY DEFAULT nextval('shared_id_seq'),
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    CONSTRAINT valid_email CHECK (
        email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'
    ),
    hashed_password VARCHAR(255) NOT NULL,
    gender GENDER NOT NULL,
    phone_no VARCHAR(15) UNIQUE,
    CONSTRAINT valid_phone_no CHECK (
        phone_no ~* '^\+[1-9][0-9]{1,14}$'
    ),
    birth_date DATE,
    id_type ID_TYPE DEFAULT 'id_card',
    id_no VARCHAR(20),
    nationality VARCHAR(30),
    fide_id BIGINT UNIQUE,
    fide_title FIDE_TITLE,
    fide_rating SMALLINT,
    CONSTRAINT valid_fide_rating CHECK (fide_rating >= 0 AND fide_rating <= 3000),
    mcf_id BIGINT UNIQUE,
    mcf_rating SMALLINT,
    CONSTRAINT valid_mcf_rating CHECK (mcf_rating >= 0 AND mcf_rating <= 3000),
    is_oku BOOLEAN DEFAULT FALSE,
    bank_account_no VARCHAR(20) UNIQUE,
    bank_name VARCHAR(50),
    profile_picture_url VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
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
    time_control VARCHAR(10) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    CONSTRAINT valid_dates CHECK (
        end_date >= start_date
    ),
    location VARCHAR(100) NOT NULL,
    latitude NUMERIC(10, 7),
    longitude NUMERIC(10, 7),
    state VARCHAR(50),
    country VARCHAR(50),
    is_fide_rated BOOLEAN DEFAULT FALSE,
    is_mcf_rated BOOLEAN DEFAULT FALSE,
    registration_fee NUMERIC(7,2) NOT NULL,
    registration_opens_at TIMESTAMP NOT NULL,
    registration_closes_at TIMESTAMP NOT NULL,
    CONSTRAINT valid_registration CHECK (
        registration_opens_at < registration_closes_at AND
        registration_closes_at <= start_date::timestamp
    ),
    max_players SMALLINT NOT NULL,
    CONSTRAINT valid_max_players CHECK (max_players > 0),
    min_rating SMALLINT,
    max_rating SMALLINT,
    CONSTRAINT valid_rating_range CHECK (
        min_rating IS NULL OR
        max_rating IS NULL OR
        (min_rating <= max_rating AND min_rating >= 0 AND max_rating >= 0)
    ),
    poster_url VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by BIGINT REFERENCES users(id),
    deleted_at TIMESTAMP
) PARTITION BY RANGE (start_date);

CREATE TABLE tournaments_2025
    PARTITION OF tournaments
    FOR VALUES FROM ('2025-01-01') TO ('2025-12-31');

CREATE TABLE tour_schedules (
    tournament_id BIGINT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
    agenda VARCHAR(20) NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP NOT NULL,
    CONSTRAINT valid_schedule_times CHECK (end_time > start_time),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by BIGINT REFERENCES users(id),
    PRIMARY KEY (tournament_id, agenda)
);

CREATE TABLE tour_prizes (
    tournament_id BIGINT NOT NULL REFERENCES tournaments(id),
    prize_rank VARCHAR(10) NOT NULL,
    prize_amount NUMERIC(7,2) NOT NULL,
    PRIMARY KEY (tournament_id, prize_rank)
);

CREATE TYPE REGISTRATION_STATUS AS ENUM ('pending', 'confirmed', 'cancelled', 'waitlist');

-- A player can be registered to multiple tournaments and a tournament can have multiple players
CREATE TABLE tournaments_players (
    tournament_id BIGINT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
    player_id BIGINT NOT NULL REFERENCES users(id),
    registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status REGISTRATION_STATUS DEFAULT 'pending',
    payment_id UUID REFERENCES transactions(id),
    PRIMARY KEY (tournament_id, player_id)
);

CREATE TYPE TRANSACTION_TYPE AS ENUM ('payment', 'withdrawal', 'refund');
CREATE TYPE TRANSACTION_STATUS AS ENUM ('pending', 'successful', 'failed', 'cancelled');

CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id BIGINT NOT NULL REFERENCES tournaments(id),
    paid_by BIGINT NOT NULL,
    paid_to BIGINT NOT NULL,
    trx_type TRANSACTION_TYPE NOT NULL,
    trx_status TRANSACTION_STATUS NOT NULL DEFAULT 'pending',
    trx_amount NUMERIC(7,2) NOT NULL,
    CONSTRAINT positive_amount CHECK (trx_amount > 0),
    payment_method VARCHAR(50),
    payment_reference VARCHAR(100),
    processed_at TIMESTAMP,
    CONSTRAINT valid_paid_by CHECK (
        EXISTS (SELECT 1 FROM users WHERE id = paid_by AND trx_type = 'payment') OR
        EXISTS (SELECT 1 FROM admins WHERE id = paid_by AND trx_type IN ('withdrawal', 'refund'))
    ),
    CONSTRAINT valid_paid_to CHECK (
        EXISTS (SELECT 1 FROM organizations WHERE id = paid_to AND trx_type = 'withdrawal') OR
        EXISTS (SELECT 1 FROM admins WHERE id = paid_to AND trx_type = 'payment') OR
        EXISTS (SELECT 1 FROM users WHERE id = paid_to AND trx_type = 'refund')
    )
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
    role_id SMALLINT NOT NULL REFERENCES roles(id),
    PRIMARY KEY (user_id, role_id)
);

CREATE TABLE permissions (
    id SMALLSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE
);

-- A role can have multiple permissions and a permission can be associated with multiple roles
CREATE TABLE roles_permissions (
    role_id SMALLINT NOT NULL REFERENCES roles(id),
    permission_id SMALLINT NOT NULL REFERENCES permissions(id),
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE organizations (
    id BIGINT PRIMARY KEY DEFAULT nextval('shared_id_seq'),
    owner_id BIGINT NOT NULL REFERENCES users(id),
    name VARCHAR(255) NOT NULL UNIQUE,
    bank_account_no VARCHAR(20) NOT NULL UNIQUE,
    bank_name VARCHAR(50) NOT NULL,
    profile_picture_url VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- A user can be associated with multiple organizations and an organization can have multiple users
CREATE TABLE users_organizations (
    user_id BIGINT NOT NULL REFERENCES users(id),
    organization_id BIGINT NOT NULL REFERENCES organizations(id),
    PRIMARY KEY (user_id, organization_id)
);

-- A tournament can have multiple organizers and an organizer can organize multiple tournaments
CREATE TABLE tournaments_organizers (
    tournament_id BIGINT NOT NULL REFERENCES tournaments(id),
    organizer_id BIGINT NOT NULL REFERENCES organizations(id),
    PRIMARY KEY (tournament_id, organizer_id)
);

CREATE TABLE admins (
    id BIGINT PRIMARY KEY DEFAULT nextval('shared_id_seq'),
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    hashed_password VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(50) NOT NULL,
    record_id BIGINT NOT NULL,
    action VARCHAR(10) NOT NULL,
    old_data JSONB,
    new_data JSONB,
    performed_by BIGINT NOT NULL,
    performed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Primary search/filter indices
CREATE INDEX idx_tournaments_dates ON tournaments(start_date, end_date);
CREATE INDEX idx_tournaments_location ON tournaments(location, country, state);
CREATE INDEX idx_tournaments_active ON tournaments(id) 
    WHERE deleted_at IS NULL AND status NOT IN ('completed', 'cancelled');

-- Foreign key indices (for joins)
CREATE INDEX idx_tournaments_players_tournament ON tournaments_players(tournament_id);
CREATE INDEX idx_tournaments_players_player ON tournaments_players(player_id);
CREATE INDEX idx_tournaments_organizers_org ON tournaments_organizers(organizer_id);

-- Audit and tracking
CREATE INDEX idx_audit_logs_table_record ON audit_logs(table_name, record_id);

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
