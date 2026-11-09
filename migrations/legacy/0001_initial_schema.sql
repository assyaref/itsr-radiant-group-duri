-- Migration 0001: Initial Schema Setup for Testing
-- Skema dasar yang diperlukan untuk menjalankan migrasi 0019 dan 0020
-- Ini adalah file sementara untuk keperluan testing database lokal

BEGIN;

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create auth schema FIRST (required before tables referencing auth.users)
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4()
);

-- Create test environment roles (Supabase-style)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN;
  END IF;
  
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
END;
$$ LANGUAGE plpgsql;

GRANT USAGE ON SCHEMA public TO authenticated, anon, service_role;
GRANT USAGE ON SCHEMA auth TO authenticated, anon, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA auth TO authenticated, anon, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, anon, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth TO authenticated, anon, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO authenticated, anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated, anon;

-- Create auth.uid() function for test environment
-- In production Supabase, this is provided by the auth system
CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID AS $$
DECLARE
  v_uid TEXT;
BEGIN
  v_uid := current_setting('test.auth.uid', true);
  IF v_uid IS NULL OR v_uid = '' THEN
    RETURN NULL;
  END IF;
  RETURN v_uid::UUID;
END;
$$ LANGUAGE plpgsql STABLE;

-- Helper to set test auth context
CREATE OR REPLACE FUNCTION auth.set_uid(p_uid UUID) RETURNS VOID AS $$
BEGIN
  PERFORM set_config('test.auth.uid', p_uid::text, true);
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION auth.uid() TO PUBLIC;
GRANT EXECUTE ON FUNCTION auth.set_uid(UUID) TO PUBLIC;

-- 1. Create profiles table ( dasar untuk semua RLS )
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users(id) PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  employee_number TEXT UNIQUE,
  role TEXT DEFAULT 'employee' NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- 2. Create tickets table
CREATE TABLE public.tickets (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'open' NOT NULL,
  priority TEXT DEFAULT 'medium' NOT NULL,
  category TEXT,
  reporter_id UUID REFERENCES public.profiles(id) NOT NULL,
  assigned_to_id UUID REFERENCES public.profiles(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- 3. Create ticket_activity_log table
CREATE TABLE public.ticket_activity_log (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  ticket_id UUID REFERENCES public.tickets(id) NOT NULL,
  actor_id UUID REFERENCES public.profiles(id) NOT NULL,
  action TEXT NOT NULL,
  old_value TEXT,
  new_value TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- 4. Create ticket_comments table
CREATE TABLE public.ticket_comments (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  ticket_id UUID REFERENCES public.tickets(id) NOT NULL,
  author_id UUID REFERENCES public.profiles(id) NOT NULL,
  content TEXT NOT NULL,
  is_internal BOOLEAN DEFAULT false NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Enable RLS on all base tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_activity_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_comments ENABLE ROW LEVEL SECURITY;

COMMIT;