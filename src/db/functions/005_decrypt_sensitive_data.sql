CREATE OR REPLACE FUNCTION decrypt_sensitive_data(p_encrypted_data BYTEA)
RETURNS TEXT AS $$
BEGIN
    RETURN pgp_sym_decrypt(
        p_encrypted_data,
        get_encryption_key()
    );
END;
$$ LANGUAGE plpgsql;
