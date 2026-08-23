-- Repair schema drift caused by the former application-startup create_all().
-- Migrations 001 and 002 remain immutable and authoritative.

DO $$
DECLARE
    duplicate_sequence_groups BIGINT;
    duplicate_semantic_groups BIGINT;
    invalid_round_rows BIGINT;
BEGIN
    IF to_regclass('financial_draft_clarifications') IS NULL THEN
        RAISE EXCEPTION
            'Migration 003 requires table financial_draft_clarifications';
    END IF;

    IF to_regclass('transactions') IS NULL THEN
        RAISE EXCEPTION 'Migration 003 requires table transactions';
    END IF;

    SELECT COUNT(*)
    INTO duplicate_sequence_groups
    FROM (
        SELECT draft_id, sequence
        FROM financial_draft_clarifications
        GROUP BY draft_id, sequence
        HAVING COUNT(*) > 1
    ) duplicates;

    IF duplicate_sequence_groups > 0 THEN
        RAISE EXCEPTION USING MESSAGE = concat(
            'Cannot add uq_draft_clarification_sequence: ',
            duplicate_sequence_groups,
            ' duplicate group(s) exist'
        );
    END IF;

    SELECT COUNT(*)
    INTO duplicate_semantic_groups
    FROM (
        SELECT draft_id, semantic_key
        FROM financial_draft_clarifications
        GROUP BY draft_id, semantic_key
        HAVING COUNT(*) > 1
    ) duplicates;

    IF duplicate_semantic_groups > 0 THEN
        RAISE EXCEPTION USING MESSAGE = concat(
            'Cannot add uq_draft_clarification_semantic_key: ',
            duplicate_semantic_groups,
            ' duplicate group(s) exist'
        );
    END IF;

    SELECT COUNT(*)
    INTO invalid_round_rows
    FROM financial_draft_clarifications
    WHERE round_number NOT BETWEEN 1 AND 3;

    IF invalid_round_rows > 0 THEN
        RAISE EXCEPTION USING MESSAGE = concat(
            'Cannot add ck_draft_clarification_round: ',
            invalid_round_rows,
            ' invalid row(s) exist'
        );
    END IF;
END
$$;

DO $$
DECLARE
    clarification_schema TEXT;
    options_type TEXT;
    answer_type TEXT;
BEGIN
    SELECT namespace.nspname
    INTO clarification_schema
    FROM pg_class relation
    JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
    WHERE relation.oid = 'financial_draft_clarifications'::REGCLASS;

    SELECT columns.data_type
    INTO options_type
    FROM information_schema.columns AS columns
    WHERE columns.table_schema = clarification_schema
      AND columns.table_name = 'financial_draft_clarifications'
      AND columns.column_name = 'options_payload';

    IF options_type IS NULL THEN
        RAISE EXCEPTION
            'Required column financial_draft_clarifications.options_payload is missing';
    ELSIF options_type = 'json' THEN
        ALTER TABLE financial_draft_clarifications
            ALTER COLUMN options_payload TYPE JSONB
            USING options_payload::JSONB;
    ELSIF options_type <> 'jsonb' THEN
        RAISE EXCEPTION USING MESSAGE = concat(
            'Expected financial_draft_clarifications.options_payload ',
            'to be JSON or JSONB, found ',
            options_type
        );
    END IF;

    SELECT columns.data_type
    INTO answer_type
    FROM information_schema.columns AS columns
    WHERE columns.table_schema = clarification_schema
      AND columns.table_name = 'financial_draft_clarifications'
      AND columns.column_name = 'answer_payload';

    IF answer_type IS NULL THEN
        RAISE EXCEPTION
            'Required column financial_draft_clarifications.answer_payload is missing';
    ELSIF answer_type = 'json' THEN
        ALTER TABLE financial_draft_clarifications
            ALTER COLUMN answer_payload TYPE JSONB
            USING answer_payload::JSONB;
    ELSIF answer_type <> 'jsonb' THEN
        RAISE EXCEPTION USING MESSAGE = concat(
            'Expected financial_draft_clarifications.answer_payload ',
            'to be JSON or JSONB, found ',
            answer_type
        );
    END IF;
END
$$;

ALTER TABLE financial_draft_clarifications
    ALTER COLUMN id SET DEFAULT gen_random_uuid(),
    ALTER COLUMN status SET DEFAULT 'open';

ALTER TABLE transactions
    ALTER COLUMN currency SET DEFAULT 'CAD',
    ALTER COLUMN category SET DEFAULT 'Other';

DO $$
DECLARE
    target_table REGCLASS := 'financial_draft_clarifications'::REGCLASS;
    draft_id_attnum SMALLINT;
    sequence_attnum SMALLINT;
    semantic_key_attnum SMALLINT;
    round_number_attnum SMALLINT;
    constraint_oid OID;
    constraint_type "char";
    constraint_columns SMALLINT[];
    constraint_validated BOOLEAN;
    constraint_deferrable BOOLEAN;
    constraint_deferred BOOLEAN;
    constraint_no_inherit BOOLEAN;
    constraint_expression TEXT;
    expected_sequence_columns SMALLINT[];
    expected_semantic_columns SMALLINT[];
    expected_round_expression CONSTANT TEXT :=
        '((round_number >= 1) AND (round_number <= 3))';
BEGIN
    SELECT attnum INTO STRICT draft_id_attnum
    FROM pg_attribute
    WHERE attrelid = target_table AND attname = 'draft_id' AND NOT attisdropped;

    SELECT attnum INTO STRICT sequence_attnum
    FROM pg_attribute
    WHERE attrelid = target_table AND attname = 'sequence' AND NOT attisdropped;

    SELECT attnum INTO STRICT semantic_key_attnum
    FROM pg_attribute
    WHERE attrelid = target_table AND attname = 'semantic_key' AND NOT attisdropped;

    SELECT attnum INTO STRICT round_number_attnum
    FROM pg_attribute
    WHERE attrelid = target_table AND attname = 'round_number' AND NOT attisdropped;

    expected_sequence_columns := ARRAY[draft_id_attnum, sequence_attnum]::SMALLINT[];
    expected_semantic_columns := ARRAY[draft_id_attnum, semantic_key_attnum]::SMALLINT[];

    SELECT oid, contype, conkey, convalidated, condeferrable, condeferred
    INTO constraint_oid, constraint_type, constraint_columns,
        constraint_validated, constraint_deferrable, constraint_deferred
    FROM pg_constraint
    WHERE conrelid = target_table
      AND conname = 'uq_draft_clarification_sequence';

    IF constraint_oid IS NULL THEN
        ALTER TABLE financial_draft_clarifications
            ADD CONSTRAINT uq_draft_clarification_sequence
            UNIQUE (draft_id, sequence);
    ELSIF constraint_type <> 'u'
        OR constraint_columns IS DISTINCT FROM expected_sequence_columns
        OR NOT constraint_validated
        OR constraint_deferrable
        OR constraint_deferred
    THEN
        RAISE EXCEPTION
            'Constraint uq_draft_clarification_sequence exists with an incompatible definition';
    END IF;

    constraint_oid := NULL;
    constraint_type := NULL;
    constraint_columns := NULL;
    constraint_validated := NULL;
    constraint_deferrable := NULL;
    constraint_deferred := NULL;

    SELECT oid, contype, conkey, convalidated, condeferrable, condeferred
    INTO constraint_oid, constraint_type, constraint_columns,
        constraint_validated, constraint_deferrable, constraint_deferred
    FROM pg_constraint
    WHERE conrelid = target_table
      AND conname = 'uq_draft_clarification_semantic_key';

    IF constraint_oid IS NULL THEN
        ALTER TABLE financial_draft_clarifications
            ADD CONSTRAINT uq_draft_clarification_semantic_key
            UNIQUE (draft_id, semantic_key);
    ELSIF constraint_type <> 'u'
        OR constraint_columns IS DISTINCT FROM expected_semantic_columns
        OR NOT constraint_validated
        OR constraint_deferrable
        OR constraint_deferred
    THEN
        RAISE EXCEPTION
            'Constraint uq_draft_clarification_semantic_key exists with an incompatible definition';
    END IF;

    constraint_oid := NULL;
    constraint_type := NULL;
    constraint_columns := NULL;
    constraint_validated := NULL;
    constraint_no_inherit := NULL;
    constraint_expression := NULL;

    SELECT
        constraint_row.oid,
        constraint_row.contype,
        constraint_row.conkey,
        constraint_row.convalidated,
        constraint_row.connoinherit,
        regexp_replace(
            pg_get_expr(constraint_row.conbin, constraint_row.conrelid),
            '\s+',
            ' ',
            'g'
        )
    INTO
        constraint_oid,
        constraint_type,
        constraint_columns,
        constraint_validated,
        constraint_no_inherit,
        constraint_expression
    FROM pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = target_table
      AND constraint_row.conname = 'ck_draft_clarification_round';

    IF constraint_oid IS NULL THEN
        ALTER TABLE financial_draft_clarifications
            ADD CONSTRAINT ck_draft_clarification_round
            CHECK (round_number BETWEEN 1 AND 3)
            NOT VALID;
    ELSIF constraint_type <> 'c'
        OR constraint_columns IS DISTINCT FROM ARRAY[round_number_attnum]::SMALLINT[]
        OR constraint_expression IS DISTINCT FROM expected_round_expression
        OR constraint_no_inherit
    THEN
        RAISE EXCEPTION USING MESSAGE = concat(
            'Constraint ck_draft_clarification_round exists ',
            'with an incompatible definition: ',
            COALESCE(constraint_expression, '<unavailable>')
        );
    END IF;

    SELECT convalidated
    INTO constraint_validated
    FROM pg_constraint
    WHERE conrelid = target_table
      AND conname = 'ck_draft_clarification_round';

    IF NOT constraint_validated THEN
        ALTER TABLE financial_draft_clarifications
            VALIDATE CONSTRAINT ck_draft_clarification_round;
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE EXCEPTION
            'Migration 003 requires draft_id, sequence, semantic_key, and round_number columns';
END
$$;

-- Independently prove the final constraint definitions and validation state.
DO $$
DECLARE
    target_table REGCLASS := 'financial_draft_clarifications'::REGCLASS;
    draft_id_attnum SMALLINT;
    sequence_attnum SMALLINT;
    semantic_key_attnum SMALLINT;
    round_number_attnum SMALLINT;
    expected_sequence_columns SMALLINT[];
    expected_semantic_columns SMALLINT[];
    expected_round_expression CONSTANT TEXT :=
        '((round_number >= 1) AND (round_number <= 3))';
    valid_constraint_count INTEGER;
BEGIN
    SELECT attnum INTO STRICT draft_id_attnum
    FROM pg_attribute
    WHERE attrelid = target_table AND attname = 'draft_id' AND NOT attisdropped;

    SELECT attnum INTO STRICT sequence_attnum
    FROM pg_attribute
    WHERE attrelid = target_table AND attname = 'sequence' AND NOT attisdropped;

    SELECT attnum INTO STRICT semantic_key_attnum
    FROM pg_attribute
    WHERE attrelid = target_table AND attname = 'semantic_key' AND NOT attisdropped;

    SELECT attnum INTO STRICT round_number_attnum
    FROM pg_attribute
    WHERE attrelid = target_table AND attname = 'round_number' AND NOT attisdropped;

    expected_sequence_columns := ARRAY[draft_id_attnum, sequence_attnum]::SMALLINT[];
    expected_semantic_columns := ARRAY[draft_id_attnum, semantic_key_attnum]::SMALLINT[];

    SELECT COUNT(*) INTO valid_constraint_count
    FROM pg_constraint
    WHERE conrelid = target_table
      AND conname = 'uq_draft_clarification_sequence'
      AND contype = 'u'
      AND conkey = expected_sequence_columns
      AND convalidated
      AND NOT condeferrable
      AND NOT condeferred;

    IF valid_constraint_count <> 1 THEN
        RAISE EXCEPTION
            'Postcondition failed for uq_draft_clarification_sequence';
    END IF;

    SELECT COUNT(*) INTO valid_constraint_count
    FROM pg_constraint
    WHERE conrelid = target_table
      AND conname = 'uq_draft_clarification_semantic_key'
      AND contype = 'u'
      AND conkey = expected_semantic_columns
      AND convalidated
      AND NOT condeferrable
      AND NOT condeferred;

    IF valid_constraint_count <> 1 THEN
        RAISE EXCEPTION
            'Postcondition failed for uq_draft_clarification_semantic_key';
    END IF;

    SELECT COUNT(*) INTO valid_constraint_count
    FROM pg_constraint
    WHERE conrelid = target_table
      AND conname = 'ck_draft_clarification_round'
      AND contype = 'c'
      AND conkey = ARRAY[round_number_attnum]::SMALLINT[]
      AND convalidated
      AND NOT connoinherit
      AND regexp_replace(pg_get_expr(conbin, conrelid), '\s+', ' ', 'g')
          = expected_round_expression;

    IF valid_constraint_count <> 1 THEN
        RAISE EXCEPTION
            'Postcondition failed for ck_draft_clarification_round';
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE EXCEPTION
            'Migration 003 postcondition could not resolve required clarification columns';
END
$$;
