-- Step 1: Add patients.owner_user_id safely (initially nullable)
ALTER TABLE patients ADD COLUMN IF NOT EXISTS owner_user_id UUID REFERENCES auth.users(id) DEFAULT auth.uid();

-- Step 2: Insert a system placeholder user in auth.users if it doesn't exist
INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
VALUES (
    '00000000-0000-0000-0000-000000000000',
    'system@placeholder.com',
    '{}'::jsonb,
    '{}'::jsonb,
    'authenticated',
    'authenticated'
)
ON CONFLICT (id) DO NOTHING;

-- Step 3: Backfill existing patients.owner_user_id with the placeholder user
UPDATE patients
SET owner_user_id = '00000000-0000-0000-0000-000000000000'
WHERE owner_user_id IS NULL;

-- Step 4: Enforce NOT NULL constraint on owner_user_id
ALTER TABLE patients ALTER COLUMN owner_user_id SET NOT NULL;

-- Step 5: Enable Row Level Security (RLS) on all sensitive tables
ALTER TABLE patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE nss_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE nds_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE gum_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE ulcer_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE ml_neuropathy_predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE final_diagnostic_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_memory ENABLE ROW LEVEL SECURITY;
ALTER TABLE gestational_diabetes_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE heart_risk_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE ppg_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE ppg_signal_metadata ENABLE ROW LEVEL SECURITY;

-- Step 6: Drop existing policies if any to prevent conflicts and ensure idempotency
-- patients
DROP POLICY IF EXISTS patients_select ON patients;
DROP POLICY IF EXISTS patients_insert ON patients;
DROP POLICY IF EXISTS patients_update ON patients;
DROP POLICY IF EXISTS patients_delete ON patients;

-- nss_assessments
DROP POLICY IF EXISTS nss_assessments_select ON nss_assessments;
DROP POLICY IF EXISTS nss_assessments_insert ON nss_assessments;
DROP POLICY IF EXISTS nss_assessments_update ON nss_assessments;
DROP POLICY IF EXISTS nss_assessments_delete ON nss_assessments;

-- nds_assessments
DROP POLICY IF EXISTS nds_assessments_select ON nds_assessments;
DROP POLICY IF EXISTS nds_assessments_insert ON nds_assessments;
DROP POLICY IF EXISTS nds_assessments_update ON nds_assessments;
DROP POLICY IF EXISTS nds_assessments_delete ON nds_assessments;

-- gum_assessments
DROP POLICY IF EXISTS gum_assessments_select ON gum_assessments;
DROP POLICY IF EXISTS gum_assessments_insert ON gum_assessments;
DROP POLICY IF EXISTS gum_assessments_update ON gum_assessments;
DROP POLICY IF EXISTS gum_assessments_delete ON gum_assessments;

-- ulcer_assessments
DROP POLICY IF EXISTS ulcer_assessments_select ON ulcer_assessments;
DROP POLICY IF EXISTS ulcer_assessments_insert ON ulcer_assessments;
DROP POLICY IF EXISTS ulcer_assessments_update ON ulcer_assessments;
DROP POLICY IF EXISTS ulcer_assessments_delete ON ulcer_assessments;

-- ml_neuropathy_predictions
DROP POLICY IF EXISTS ml_neuropathy_predictions_select ON ml_neuropathy_predictions;
DROP POLICY IF EXISTS ml_neuropathy_predictions_insert ON ml_neuropathy_predictions;
DROP POLICY IF EXISTS ml_neuropathy_predictions_update ON ml_neuropathy_predictions;
DROP POLICY IF EXISTS ml_neuropathy_predictions_delete ON ml_neuropathy_predictions;

-- final_diagnostic_decisions
DROP POLICY IF EXISTS final_diagnostic_decisions_select ON final_diagnostic_decisions;
DROP POLICY IF EXISTS final_diagnostic_decisions_insert ON final_diagnostic_decisions;
DROP POLICY IF EXISTS final_diagnostic_decisions_update ON final_diagnostic_decisions;
DROP POLICY IF EXISTS final_diagnostic_decisions_delete ON final_diagnostic_decisions;

-- conversation_memory
DROP POLICY IF EXISTS conversation_memory_select ON conversation_memory;
DROP POLICY IF EXISTS conversation_memory_insert ON conversation_memory;
DROP POLICY IF EXISTS conversation_memory_update ON conversation_memory;
DROP POLICY IF EXISTS conversation_memory_delete ON conversation_memory;

-- gestational_diabetes_assessments
DROP POLICY IF EXISTS gestational_diabetes_assessments_select ON gestational_diabetes_assessments;
DROP POLICY IF EXISTS gestational_diabetes_assessments_insert ON gestational_diabetes_assessments;
DROP POLICY IF EXISTS gestational_diabetes_assessments_update ON gestational_diabetes_assessments;
DROP POLICY IF EXISTS gestational_diabetes_assessments_delete ON gestational_diabetes_assessments;

-- heart_risk_assessments
DROP POLICY IF EXISTS heart_risk_assessments_select ON heart_risk_assessments;
DROP POLICY IF EXISTS heart_risk_assessments_insert ON heart_risk_assessments;
DROP POLICY IF EXISTS heart_risk_assessments_update ON heart_risk_assessments;
DROP POLICY IF EXISTS heart_risk_assessments_delete ON heart_risk_assessments;

-- ppg_assessments
DROP POLICY IF EXISTS ppg_assessments_select ON ppg_assessments;
DROP POLICY IF EXISTS ppg_assessments_insert ON ppg_assessments;
DROP POLICY IF EXISTS ppg_assessments_update ON ppg_assessments;
DROP POLICY IF EXISTS ppg_assessments_delete ON ppg_assessments;

-- ppg_signal_metadata
DROP POLICY IF EXISTS ppg_signal_metadata_select ON ppg_signal_metadata;
DROP POLICY IF EXISTS ppg_signal_metadata_insert ON ppg_signal_metadata;
DROP POLICY IF EXISTS ppg_signal_metadata_update ON ppg_signal_metadata;
DROP POLICY IF EXISTS ppg_signal_metadata_delete ON ppg_signal_metadata;


-- Step 7: Create minimal secure policies for patients
CREATE POLICY patients_select ON patients FOR SELECT USING (owner_user_id = auth.uid());
CREATE POLICY patients_insert ON patients FOR INSERT WITH CHECK (owner_user_id = auth.uid());
CREATE POLICY patients_update ON patients FOR UPDATE USING (owner_user_id = auth.uid()) WITH CHECK (owner_user_id = auth.uid());
CREATE POLICY patients_delete ON patients FOR DELETE USING (owner_user_id = auth.uid());

-- Step 8: Create minimal secure policies for child tables using ownership inheritance
-- nss_assessments
CREATE POLICY nss_assessments_select ON nss_assessments FOR SELECT USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY nss_assessments_insert ON nss_assessments FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY nss_assessments_update ON nss_assessments FOR UPDATE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY nss_assessments_delete ON nss_assessments FOR DELETE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));

-- nds_assessments
CREATE POLICY nds_assessments_select ON nds_assessments FOR SELECT USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY nds_assessments_insert ON nds_assessments FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY nds_assessments_update ON nds_assessments FOR UPDATE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY nds_assessments_delete ON nds_assessments FOR DELETE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));

-- gum_assessments
CREATE POLICY gum_assessments_select ON gum_assessments FOR SELECT USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY gum_assessments_insert ON gum_assessments FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY gum_assessments_update ON gum_assessments FOR UPDATE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY gum_assessments_delete ON gum_assessments FOR DELETE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));

-- ulcer_assessments
CREATE POLICY ulcer_assessments_select ON ulcer_assessments FOR SELECT USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY ulcer_assessments_insert ON ulcer_assessments FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY ulcer_assessments_update ON ulcer_assessments FOR UPDATE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY ulcer_assessments_delete ON ulcer_assessments FOR DELETE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));

-- ml_neuropathy_predictions
CREATE POLICY ml_neuropathy_predictions_select ON ml_neuropathy_predictions FOR SELECT USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY ml_neuropathy_predictions_insert ON ml_neuropathy_predictions FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY ml_neuropathy_predictions_update ON ml_neuropathy_predictions FOR UPDATE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY ml_neuropathy_predictions_delete ON ml_neuropathy_predictions FOR DELETE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));

-- final_diagnostic_decisions
CREATE POLICY final_diagnostic_decisions_select ON final_diagnostic_decisions FOR SELECT USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY final_diagnostic_decisions_insert ON final_diagnostic_decisions FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY final_diagnostic_decisions_update ON final_diagnostic_decisions FOR UPDATE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY final_diagnostic_decisions_delete ON final_diagnostic_decisions FOR DELETE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));

-- conversation_memory
CREATE POLICY conversation_memory_select ON conversation_memory FOR SELECT USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY conversation_memory_insert ON conversation_memory FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY conversation_memory_update ON conversation_memory FOR UPDATE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY conversation_memory_delete ON conversation_memory FOR DELETE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));

-- gestational_diabetes_assessments
CREATE POLICY gestational_diabetes_assessments_select ON gestational_diabetes_assessments FOR SELECT USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY gestational_diabetes_assessments_insert ON gestational_diabetes_assessments FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY gestational_diabetes_assessments_update ON gestational_diabetes_assessments FOR UPDATE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY gestational_diabetes_assessments_delete ON gestational_diabetes_assessments FOR DELETE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));

-- heart_risk_assessments
CREATE POLICY heart_risk_assessments_select ON heart_risk_assessments FOR SELECT USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY heart_risk_assessments_insert ON heart_risk_assessments FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY heart_risk_assessments_update ON heart_risk_assessments FOR UPDATE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY heart_risk_assessments_delete ON heart_risk_assessments FOR DELETE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));

-- ppg_assessments
CREATE POLICY ppg_assessments_select ON ppg_assessments FOR SELECT USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY ppg_assessments_insert ON ppg_assessments FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY ppg_assessments_update ON ppg_assessments FOR UPDATE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));
CREATE POLICY ppg_assessments_delete ON ppg_assessments FOR DELETE USING (EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid()));

-- ppg_signal_metadata
CREATE POLICY ppg_signal_metadata_select ON ppg_signal_metadata FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM ppg_assessments
        JOIN patients ON patients.id = ppg_assessments.patient_id
        WHERE ppg_assessments.id = assessment_id
        AND patients.owner_user_id = auth.uid()
    )
);
CREATE POLICY ppg_signal_metadata_insert ON ppg_signal_metadata FOR INSERT WITH CHECK (
    EXISTS (
        SELECT 1 FROM ppg_assessments
        JOIN patients ON patients.id = ppg_assessments.patient_id
        WHERE ppg_assessments.id = assessment_id
        AND patients.owner_user_id = auth.uid()
    )
);
CREATE POLICY ppg_signal_metadata_update ON ppg_signal_metadata FOR UPDATE USING (
    EXISTS (
        SELECT 1 FROM ppg_assessments
        JOIN patients ON patients.id = ppg_assessments.patient_id
        WHERE ppg_assessments.id = assessment_id
        AND patients.owner_user_id = auth.uid()
    )
) WITH CHECK (
    EXISTS (
        SELECT 1 FROM ppg_assessments
        JOIN patients ON patients.id = ppg_assessments.patient_id
        WHERE ppg_assessments.id = assessment_id
        AND patients.owner_user_id = auth.uid()
    )
);
CREATE POLICY ppg_signal_metadata_delete ON ppg_signal_metadata FOR DELETE USING (
    EXISTS (
        SELECT 1 FROM ppg_assessments
        JOIN patients ON patients.id = ppg_assessments.patient_id
        WHERE ppg_assessments.id = assessment_id
        AND patients.owner_user_id = auth.uid()
    )
);
