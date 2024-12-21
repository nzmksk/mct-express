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
