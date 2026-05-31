-- Additive migration: optional PPG neuropathy screening persistence.
-- Stores derived inference outputs and metadata only; raw signal arrays are not stored.

CREATE TABLE IF NOT EXISTS ppg_assessments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID NULL REFERENCES patients(id) ON DELETE SET NULL,
    session_id TEXT NULL,
    neuropathy_probability FLOAT,
    risk_level TEXT,
    signal_quality TEXT,
    confidence FLOAT,
    features JSONB,
    reasoning_summary TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ppg_signal_metadata (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_id UUID REFERENCES ppg_assessments(id) ON DELETE CASCADE,
    signal_length INTEGER,
    sampling_rate INTEGER NULL,
    upload_source TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ppg_assessments_patient_id ON ppg_assessments(patient_id);
CREATE INDEX IF NOT EXISTS idx_ppg_assessments_session_id ON ppg_assessments(session_id);
CREATE INDEX IF NOT EXISTS idx_ppg_assessments_created_at ON ppg_assessments(created_at);
CREATE INDEX IF NOT EXISTS idx_ppg_signal_metadata_assessment_id ON ppg_signal_metadata(assessment_id);
