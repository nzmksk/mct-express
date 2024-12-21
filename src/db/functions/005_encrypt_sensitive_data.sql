CREATE OR REPLACE FUNCTION encrypt_sensitive_data(p_plain_text TEXT)
RETURNS BYTEA AS $$
BEGIN
    RETURN pgp_sym_encrypt(
        p_plain_text,
        get_encryption_key()
    );
END;
$$ LANGUAGE plpgsql;
