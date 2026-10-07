-- +goose Up
ALTER TABLE vehicles
    ADD COLUMN is_active boolean NOT NULL DEFAULT true;

-- +goose Down
ALTER TABLE vehicles
    DROP COLUMN IF EXISTS is_active;
