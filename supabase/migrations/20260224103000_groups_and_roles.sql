-- Create professions (Groups) table
CREATE TABLE IF NOT EXISTS public.professions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    name_en TEXT,
    description TEXT,
    icon_name TEXT,
    category TEXT,
    is_built_in BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    requires_verification BOOLEAN DEFAULT true,
    display_order INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create registration_field_configs table
CREATE TABLE IF NOT EXISTS public.registration_field_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id UUID REFERENCES public.professions(id) ON DELETE CASCADE,
    field_id TEXT NOT NULL,
    label TEXT NOT NULL,
    hint TEXT,
    field_type TEXT NOT NULL,
    is_required BOOLEAN DEFAULT false,
    field_order INTEGER DEFAULT 0,
    icon_name TEXT,
    dropdown_options JSONB,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create user_group_roles (to assign 3 levels of rights to users in a group)
CREATE TABLE IF NOT EXISTS public.user_group_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id UUID REFERENCES public.professions(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    role_level INTEGER DEFAULT 3 CHECK (role_level IN (1, 2, 3)), -- 1=Admin, 2=Editor, 3=Member
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(profession_id, user_id)
);

-- RLS for professions
ALTER TABLE public.professions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public profiles are viewable by everyone." ON public.professions FOR SELECT USING (true);
CREATE POLICY "Public profiles are insertable by authenticated." ON public.professions FOR INSERT WITH CHECK (true);
CREATE POLICY "Public profiles are updatable by authenticated." ON public.professions FOR UPDATE USING (true);
CREATE POLICY "Public profiles are deletable by authenticated." ON public.professions FOR DELETE USING (true);

-- RLS for registration_field_configs
ALTER TABLE public.registration_field_configs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Viewable by everyone" ON public.registration_field_configs FOR SELECT USING (true);
CREATE POLICY "Modifiable by admin" ON public.registration_field_configs FOR ALL USING (true);

-- RLS for user_group_roles
ALTER TABLE public.user_group_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Viewable by everyone" ON public.user_group_roles FOR SELECT USING (true);
CREATE POLICY "Modifiable by admin" ON public.user_group_roles FOR ALL USING (true);
