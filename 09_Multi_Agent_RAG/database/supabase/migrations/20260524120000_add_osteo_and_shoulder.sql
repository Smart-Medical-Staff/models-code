-- Migration: Add osteoporosis and frozen shoulder assessment tables with RLS policies.
-- Safe to run on existing databases (IF NOT EXISTS)

CREATE TABLE IF NOT EXISTS osteoporosis_assessments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID REFERENCES patients(id) ON DELETE CASCADE,
    age INTEGER,
    hba1c FLOAT,
    duration INTEGER,
    bmi FLOAT,
    ca FLOAT,
    vit_d FLOAT,
    pth FLOAT,
    phos FLOAT,
    activity INTEGER,
    smoke BOOLEAN,
    frac BOOLEAN,
    steroids BOOLEAN,
    risk_score FLOAT,
    predicted_class INTEGER,
    predicted_probability FLOAT,
    severity TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS frozen_shoulder_assessments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID REFERENCES patients(id) ON DELETE CASCADE,
    hba1c FLOAT,
    age INTEGER,
    crp FLOAT,
    flex FLOAT,
    abd FLOAT,
    ext_rot FLOAT,
    int_rot FLOAT,
    pain INTEGER,
    weeks INTEGER,
    thyroid BOOLEAN,
    night_pain BOOLEAN,
    bilateral BOOLEAN,
    risk_score FLOAT,
    predicted_class INTEGER,
    predicted_probability FLOAT,
    severity TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Performance Indexes
CREATE INDEX IF NOT EXISTS idx_osteoporosis_patient_id ON osteoporosis_assessments(patient_id);
CREATE INDEX IF NOT EXISTS idx_osteoporosis_created_at ON osteoporosis_assessments(created_at);
CREATE INDEX IF NOT EXISTS idx_frozen_shoulder_patient_id ON frozen_shoulder_assessments(patient_id);
CREATE INDEX IF NOT EXISTS idx_frozen_shoulder_created_at ON frozen_shoulder_assessments(created_at);

-- Enable Row Level Security (RLS)
ALTER TABLE osteoporosis_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE frozen_shoulder_assessments ENABLE ROW LEVEL SECURITY;

-- Row Level Security Policies
-- osteoporosis_assessments
DROP POLICY IF EXISTS osteoporosis_assessments_select ON osteoporosis_assessments;
DROP POLICY IF EXISTS osteoporosis_assessments_insert ON osteoporosis_assessments;
DROP POLICY IF EXISTS osteoporosis_assessments_update ON osteoporosis_assessments;
DROP POLICY IF EXISTS osteoporosis_assessments_delete ON osteoporosis_assessments;

CREATE POLICY osteoporosis_assessments_select ON osteoporosis_assessments FOR SELECT USING (
    EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())
);
CREATE POLICY osteoporosis_assessments_insert ON osteoporosis_assessments FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())
);
CREATE POLICY osteoporosis_assessments_update ON osteoporosis_assessments FOR UPDATE USING (
    EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())
) WITH CHECK (
    EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())
);
CREATE POLICY osteoporosis_assessments_delete ON osteoporosis_assessments FOR DELETE USING (
    EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())
);

-- frozen_shoulder_assessments
DROP POLICY IF EXISTS frozen_shoulder_assessments_select ON frozen_shoulder_assessments;
DROP POLICY IF EXISTS frozen_shoulder_assessments_insert ON frozen_shoulder_assessments;
DROP POLICY IF EXISTS frozen_shoulder_assessments_update ON frozen_shoulder_assessments;
DROP POLICY IF EXISTS frozen_shoulder_assessments_delete ON frozen_shoulder_assessments;

CREATE POLICY frozen_shoulder_assessments_select ON frozen_shoulder_assessments FOR SELECT USING (
    EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())
);
CREATE POLICY frozen_shoulder_assessments_insert ON frozen_shoulder_assessments FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())
);
CREATE POLICY frozen_shoulder_assessments_update ON frozen_shoulder_assessments FOR UPDATE USING (
    EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())
) WITH CHECK (
    EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())
);
CREATE POLICY frozen_shoulder_assessments_delete ON frozen_shoulder_assessments FOR DELETE USING (
    EXISTS (SELECT 1 FROM patients WHERE patients.id = patient_id AND patients.owner_user_id = auth.uid())
);
