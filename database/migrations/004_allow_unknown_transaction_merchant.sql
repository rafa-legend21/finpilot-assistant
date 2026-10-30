-- Allow an explicitly unknown merchant while retaining an exact transaction date.
ALTER TABLE transactions
    ALTER COLUMN merchant DROP NOT NULL;
