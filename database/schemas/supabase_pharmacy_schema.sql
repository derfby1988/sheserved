-- ==========================================
-- 1. Base Drug Table (medications)
-- ==========================================
CREATE TABLE public.medications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    source_type VARCHAR(20) NOT NULL,              -- 'TMT', 'TTMT', 'FDA', 'UNREG', 'SUPPLEMENT'
    reference_code VARCHAR(50),                    -- 24-digit TMT code, FDA Registration No.
    
    generic_name VARCHAR(255),
    trade_name VARCHAR(255) NOT NULL,
    dosage_form VARCHAR(100),
    strength VARCHAR(100),
    manufacturer VARCHAR(255),
    
    status VARCHAR(20) DEFAULT 'ACTIVE',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- Index for fast searching
CREATE INDEX idx_medications_trade_name ON public.medications(trade_name);
CREATE INDEX idx_medications_generic_name ON public.medications(generic_name);

-- ==========================================
-- 2. TMT Specific Details (tmt_details)
-- ==========================================
CREATE TABLE public.tmt_details (
    medication_id UUID PRIMARY KEY REFERENCES public.medications(id) ON DELETE CASCADE,
    vtm_code VARCHAR(50),   -- Virtual Therapeutic Moiety
    gp_code VARCHAR(50),    -- Generic Product
    gpu_code VARCHAR(50),   -- Generic Product Use
    tp_code VARCHAR(50),    -- Trade Product
    tpu_code VARCHAR(50)    -- Trade Product Use
);

-- ==========================================
-- 3. Clinical Knowledge (clinical_knowledge)
-- ==========================================
CREATE TABLE public.clinical_knowledge (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    generic_name VARCHAR(255) NOT NULL,
    
    indications TEXT,                      
    dosage_administration TEXT,            
    contraindications TEXT,                
    special_precautions TEXT,              
    adverse_reactions TEXT,                
    drug_interactions TEXT,                
    pregnancy_category VARCHAR(10),        
    storage_conditions TEXT,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

CREATE INDEX idx_clinical_knowledge_generic_name ON public.clinical_knowledge(generic_name);

-- ==========================================
-- 4. Unregistered / Supplements (unregistered_details)
-- ==========================================
CREATE TABLE public.unregistered_details (
    medication_id UUID PRIMARY KEY REFERENCES public.medications(id) ON DELETE CASCADE,
    origin_country VARCHAR(100),
    original_language_name VARCHAR(255),
    fda_equivalent_status VARCHAR(50),
    risk_level VARCHAR(20),
    ingredients_list TEXT
);

-- ==========================================
-- Row Level Security (RLS) setup
-- (For users just to read the pharmacy data)
-- ==========================================
ALTER TABLE public.medications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tmt_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinical_knowledge ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.unregistered_details ENABLE ROW LEVEL SECURITY;

-- Allow public read access to all catalog tables
CREATE POLICY "Enable read access for all users" ON public.medications FOR SELECT USING (true);
CREATE POLICY "Enable read access for all users" ON public.tmt_details FOR SELECT USING (true);
CREATE POLICY "Enable read access for all users" ON public.clinical_knowledge FOR SELECT USING (true);
CREATE POLICY "Enable read access for all users" ON public.unregistered_details FOR SELECT USING (true);
