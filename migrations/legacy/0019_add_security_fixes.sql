-- Migration 0019: Critical Security Fixes
-- DBA Review Required Before Application to Production

-- 1. Add RLS Policies for ticket_activity_log (missing in current schema)
-- Employees can only view activity logs for their own tickets
CREATE POLICY "Employees can view activity logs for own tickets" ON public.ticket_activity_log
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.tickets
      WHERE id = ticket_id AND reporter_id = auth.uid()
    )
  );

-- IT Support and Admins can view all activity logs
CREATE POLICY "IT Support and Admins can view all activity logs" ON public.ticket_activity_log
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role IN ('it_support', 'administrator')
    )
  );

-- Only IT Support and Admins can create activity logs (prevents unauthorized activity creation)
CREATE POLICY "Only IT/Admin can create activity logs" ON public.ticket_activity_log
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role IN ('it_support', 'administrator')
    ) AND auth.uid() = actor_id
  );

-- 2. Add database trigger for automatic ticket activity logging
-- This eliminates the need for client-side activity creation
CREATE OR REPLACE FUNCTION public.log_ticket_status_change()
RETURNS TRIGGER AS $$
BEGIN
  -- Only log status changes
  IF OLD.status <> NEW.status THEN
    INSERT INTO public.ticket_activity_log (
      ticket_id, 
      actor_id, 
      action, 
      old_value, 
      new_value, 
      created_at
    ) VALUES (
      NEW.id, 
      auth.uid(), 
      'status_changed', 
      OLD.status, 
      NEW.status, 
      NOW()
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = public;

CREATE TRIGGER trigger_log_ticket_status_change
AFTER UPDATE OF status ON public.tickets
FOR EACH ROW EXECUTE FUNCTION public.log_ticket_status_change();

-- Secure the function
REVOKE ALL ON FUNCTION public.log_ticket_status_change() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.log_ticket_status_change() TO authenticated;

-- Add trigger for ticket assignment changes
CREATE OR REPLACE FUNCTION public.log_ticket_assignment_change()
RETURNS TRIGGER AS $$
BEGIN
  -- Log assignment changes
  IF OLD.assigned_to_id IS NULL AND NEW.assigned_to_id IS NOT NULL THEN
    INSERT INTO public.ticket_activity_log (
      ticket_id, 
      actor_id, 
      action, 
      new_value, 
      created_at
    ) VALUES (
      NEW.id, 
      auth.uid(), 
      'assigned', 
      NEW.assigned_to_id::text, 
      NOW()
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = public;

CREATE TRIGGER trigger_log_ticket_assignment_change
AFTER UPDATE OF assigned_to_id ON public.tickets
FOR EACH ROW EXECUTE FUNCTION public.log_ticket_assignment_change();

-- Secure the function
REVOKE ALL ON FUNCTION public.log_ticket_assignment_change() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.log_ticket_assignment_change() TO authenticated;

-- 3. Fix internal comment security - employees cannot create internal comments
DROP POLICY IF EXISTS "Users can create comments" ON public.ticket_comments;
CREATE POLICY "Users can create comments" ON public.ticket_comments
  FOR INSERT WITH CHECK (
    auth.uid() = author_id AND (
      -- Regular employees cannot create internal comments
      (is_internal = false) OR
      -- Only IT/Admin can create internal comments
      EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role IN ('it_support', 'administrator')
      )
    )
  );

-- 4. Strengthen profile access to prevent enumeration (still has limitations for pre-login)
-- Note: This still doesn't fix pre-login enumeration completely, but reduces exposure
DROP POLICY IF EXISTS "IT Support and Admins can view all profiles" ON public.profiles;
CREATE POLICY "IT Support and Admins can view all profiles" ON public.profiles
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role IN ('it_support', 'administrator')
    )
  );

-- 5. Add column-level protection for critical ticket columns
-- Prevent employees from modifying protected columns even if they can update the ticket
-- Use a trigger instead of RLS WITH CHECK for reliable column protection
CREATE OR REPLACE FUNCTION public.enforce_ticket_update_restrictions()
RETURNS TRIGGER AS $$
BEGIN
  -- Prevent changes to reporter_id, assigned_to_id, priority
  IF NEW.reporter_id <> OLD.reporter_id OR
     NEW.assigned_to_id <> OLD.assigned_to_id OR
     NEW.priority <> OLD.priority THEN
    RAISE EXCEPTION 'Cannot modify protected columns: reporter_id, assigned_to_id, priority';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = public;

DROP TRIGGER IF EXISTS trigger_enforce_ticket_update_restrictions ON public.tickets;
CREATE TRIGGER trigger_enforce_ticket_update_restrictions
  BEFORE UPDATE ON public.tickets
  FOR EACH ROW EXECUTE FUNCTION public.enforce_ticket_update_restrictions();

REVOKE ALL ON FUNCTION public.enforce_ticket_update_restrictions() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enforce_ticket_update_restrictions() TO authenticated;

-- Notes for DBA:
-- 1. This migration adds missing security policies for ticket_activity_log
-- 2. Adds server-side triggers to automatically log ticket changes
-- 3. Prevents regular employees from creating internal comments
-- 4. Strengthens column-level security to prevent unauthorized modifications
-- 5. Still requires architectural change to fix pre-login employee number enumeration