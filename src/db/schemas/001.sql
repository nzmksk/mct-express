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
    hashed_password VARCHAR(255) NOT NULL,
    gender GENDER,
    phone_no BYTEA UNIQUE,
    birth_date DATE,
    id_type ID_TYPE,
    id_no BYTEA,
    nationality VARCHAR(30),
    fide_id BIGINT UNIQUE,
    fide_title FIDE_TITLE,
    fide_rating SMALLINT,
    mcf_id BIGINT UNIQUE,
    mcf_rating SMALLINT,
    is_oku BOOLEAN DEFAULT FALSE,
    -- For refund purposes
    bank_account_no BYTEA UNIQUE,
    bank_name BYTEA,
    profile_picture_url VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    verified_at TIMESTAMP,
    deleted_at TIMESTAMP,

    CONSTRAINT valid_email CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'),
    CONSTRAINT valid_phone_no CHECK (phone_no ~* '^\+[1-9][0-9]{1,14}$'),
    CONSTRAINT valid_birth_date CHECK (birth_date <= CURRENT_DATE),
    CONSTRAINT valid_fide_rating CHECK (
        fide_rating >= 0
        AND fide_rating <= 3000
    ),
    CONSTRAINT valid_mcf_rating CHECK (
        mcf_rating >= 0
        AND mcf_rating <= 3000
    )
);

CREATE INDEX idx_users_email ON users(email) WHERE deleted_at IS NULL;

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
        type != 'multi_stage'
        OR (
            stages IS NOT NULL
            AND jsonb_typeof(stages) = 'array'
            AND jsonb_array_length(stages) > 0
        )
    )
);

-- OTB = On The Board (physical tournament)
CREATE TYPE TOURNAMENT_MODE AS ENUM ('otb', 'online');
CREATE TYPE TOURNAMENT_FORMAT AS ENUM ('swiss', 'round_robin', 'single_elimination', 'double_elimination');
CREATE TYPE TOURNAMENT_AGE_LIMIT AS ENUM ('open', 'u8', 'u10', 'u12', 'u14', 'u16', 'u18', 'senior50', 'senior65');
CREATE TYPE TOURNAMENT_GENDER AS ENUM ('open', 'women_only');
CREATE TYPE TOURNAMENT_STATUS AS ENUM ('planned', 'ongoing', 'completed', 'postponed', 'cancelled');
CREATE TYPE GAME_VARIANT AS ENUM ('standard', 'chess960');
CREATE TYPE GAME_SPEED AS ENUM ('blitz', 'rapid', 'classical');

CREATE TABLE tournaments (
    id BIGSERIAL PRIMARY KEY,
    main_organizer_id BIGINT NOT NULL REFERENCES organizations(id) ON DELETE SET NULL,
    name VARCHAR(100) NOT NULL UNIQUE,
    mode TOURNAMENT_MODE NOT NULL DEFAULT 'otb',
    format TOURNAMENT_FORMAT NOT NULL DEFAULT 'swiss',
    age_limit TOURNAMENT_AGE_LIMIT NOT NULL DEFAULT 'open',
    gender TOURNAMENT_GENDER NOT NULL DEFAULT 'open',
    status TOURNAMENT_STATUS NOT NULL DEFAULT 'planned',
    game_variant GAME_VARIANT NOT NULL DEFAULT 'standard',
    game_speed GAME_SPEED NOT NULL DEFAULT 'classical',
    time_control_id SMALLINT REFERENCES time_controls(id) ON DELETE SET NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    location VARCHAR(100) NOT NULL,
    state VARCHAR(50),
    country VARCHAR(50),
    is_fide_rated BOOLEAN DEFAULT FALSE,
    is_mcf_rated BOOLEAN DEFAULT FALSE,
    registration_opens_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    registration_closes_at TIMESTAMP NOT NULL DEFAULT (start_date::timestamp - INTERVAL '1 day'),
    max_players SMALLINT NOT NULL,
    min_rating SMALLINT,
    max_rating SMALLINT,
    poster_url VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    updated_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
    deleted_at TIMESTAMP,

    CONSTRAINT valid_dates CHECK (end_date >= start_date),
    CONSTRAINT positive_registration_fee CHECK (
        registration_fee > 0
        AND registration_fee <= 1000
    ),
    CONSTRAINT valid_registration CHECK (
        registration_opens_at < registration_closes_at
        AND registration_closes_at <= start_date::timestamp
    ),
    CONSTRAINT valid_max_players CHECK (max_players > 0),
    CONSTRAINT valid_rating_range CHECK (
        (min_rating IS NULL OR min_rating >= 0)
        AND (max_rating IS NULL OR max_rating >= 0)
        AND (min_rating IS NULL OR max_rating IS NULL OR min_rating <= max_rating)
    )
) PARTITION BY RANGE (start_date);

-- Add indices for frequently queried columns
CREATE INDEX idx_tournaments_status ON tournaments(status) WHERE deleted_at IS NULL;
CREATE INDEX idx_tournaments_dates ON tournaments(start_date, end_date) WHERE deleted_at IS NULL;
CREATE INDEX idx_tournaments_registration ON tournaments(registration_opens_at, registration_closes_at) WHERE deleted_at IS NULL;

CREATE TYPE FEE_CATEGORY AS ENUM (
    'standard',          -- Base registration fee
    'rated',             -- For players with ratings (FIDE/MCF)
    'unrated',           -- For players without ratings
    'age_based',         -- For age categories (U8, U10, etc.)
    'title_holder',      -- For titled players (GM, IM, etc.)
    'early_bird'         -- For early bird registrations
);

CREATE TABLE tournament_fees (
    tournament_id BIGINT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
    category FEE_CATEGORY NOT NULL,
    fee_amount NUMERIC(5,2) NOT NULL,
    
    -- Example conditions format:
    -- For age_based:
    -- {
    --   "max_age": 18,
    --   "min_age": 12
    -- }
    --
    -- For rated_player:
    -- {
    --   "min_rating": 1800,
    --   "max_rating": 2200,
    --   "rating_type": "FIDE"  -- or "MCF"
    -- }
    --
    -- For title_holder:
    -- {
    --   "titles": ["GM", "IM", "WGM"]
    -- }
    --
    -- For early_bird:
    -- {
    --   "valid_until": "2024-05-01",
    --   "max_redemption": 32
    -- }
    conditions JSONB,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
    PRIMARY KEY (tournament_id, category),

    CONSTRAINT positive_fee CHECK (fee_amount >= 0),
    CONSTRAINT valid_conditions CHECK (
        CASE category
            WHEN 'rated' THEN 
                (conditions->>'min_rating')::int IS NOT NULL
            WHEN 'age_based' THEN 
                jsonb_typeof(conditions->'max_age') = 'number'
            WHEN 'title_holder' THEN 
                jsonb_typeof(conditions->'titles') = 'array'
            WHEN 'early_bird' THEN 
                jsonb_typeof(conditions->'valid_until') = 'string'
                AND (conditions->>'max_redemption')::int IS NOT NULL
            ELSE true
        END
    )
);

CREATE TYPE RESULT_TYPE AS ENUM ('white_win', 'black_win', 'draw');

CREATE TABLE matches (
    id BIGSERIAL PRIMARY KEY,
    tournament_id BIGINT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
    round VARCHAR(20) NOT NULL,
    white_player_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    black_player_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    result RESULT_TYPE,
    number_of_moves SMALLINT,

    CONSTRAINT valid_match_players CHECK (
        white_player_id IS NOT NULL
        AND black_player_id IS NOT NULL
        AND white_player_id != black_player_id
    ),
    CONSTRAINT valid_move_count CHECK (
        number_of_moves IS NULL
        OR (number_of_moves > 0 AND number_of_moves < 1000)
    )
);

CREATE INDEX idx_matches_tournament_id ON matches(tournament_id);

CREATE TABLE schedules (
    tournament_id BIGINT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
    match_id BIGINT NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    agenda VARCHAR(20) NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
    PRIMARY KEY (tournament_id, agenda),
    
    CONSTRAINT valid_schedule_times CHECK (end_time > start_time)
);

CREATE TABLE prizes (
    tournament_id BIGINT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
    prize_rank VARCHAR(10) NOT NULL,
    prize_amount NUMERIC(7,2) NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
    PRIMARY KEY (tournament_id, prize_rank),

    CONSTRAINT positive_prize_amount CHECK (prize_amount > 0)
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

CREATE INDEX idx_organization_members_organization_id ON organization_members(organization_id);

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
    payment_method VARCHAR(50),
    payment_reference VARCHAR(100),
    processed_at TIMESTAMP,

    CONSTRAINT positive_amount CHECK (trx_amount > 0),
);

-- A player can be registered to multiple tournaments and a tournament can have multiple players
CREATE TABLE registrations (
    tournament_id BIGINT NOT NULL REFERENCES tournaments(id) ON DELETE RESTRICT,
    player_id BIGINT NOT NULL REFERENCES users(id) ON DELETE SET NULL,
    registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    applied_fee_category FEE_CATEGORY,
    payment_id UUID REFERENCES transactions(id) ON DELETE RESTRICT,
    PRIMARY KEY (tournament_id, player_id),
);

CREATE TABLE roles (
    id SMALLSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE
);

-- A user can have multiple roles and a role can be associated with multiple users
CREATE TABLE users_roles (
    user_id BIGINT NOT NULL,
    role_id SMALLINT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id),

    -- user_id can be either a users.id or admins.id
    CONSTRAINT fk_user_id CHECK (
        NOT EXISTS (SELECT 1 FROM organizations WHERE id = user_id)
    )
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
