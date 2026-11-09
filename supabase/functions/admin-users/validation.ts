// Pure input validation for admin-users (unit-tested).
import { EMAIL_RE, normalizeEmployeeNumber, ROLES, type Role } from "../_shared/http.ts";

type Result<T> = { ok: true; value: T } | { ok: false; error: string };

export interface CreateInput {
  employee_number: string; full_name: string; email: string; department: string;
  role: Role; phone_number: string | null; password: string;
}

const str = (v: unknown) => (typeof v === "string" ? v.trim() : "");

export function validateCreate(b: Record<string, unknown>): Result<CreateInput> {
  const employee_number = normalizeEmployeeNumber(b.employee_number);
  if (!employee_number) return { ok: false, error: "Employee number must be 2–20 letters/digits" };
  const full_name = str(b.full_name);
  if (full_name.length < 1 || full_name.length > 120) return { ok: false, error: "Full name is required" };
  const email = str(b.email).toLowerCase();
  if (!EMAIL_RE.test(email)) return { ok: false, error: "A valid email address is required" };
  const department = str(b.department) || "General";
  const role = str(b.role) as Role;
  if (!ROLES.includes(role)) return { ok: false, error: "Invalid role" };
  const password = typeof b.password === "string" ? b.password : "";
  if (password.length < 8 || password.length > 128) return { ok: false, error: "Password must be at least 8 characters" };
  const phone = str(b.phone_number);
  return { ok: true, value: { employee_number, full_name, email, department, role, phone_number: phone || null, password } };
}

export interface UpdateInput {
  user_id: string;
  changes: Partial<{ full_name: string; email: string; department: string; role: Role; phone_number: string | null; is_active: boolean }>;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function validateUpdate(b: Record<string, unknown>): Result<UpdateInput> {
  const user_id = str(b.user_id);
  if (!UUID_RE.test(user_id)) return { ok: false, error: "Invalid user id" };
  const changes: UpdateInput["changes"] = {};
  if (b.full_name !== undefined) {
    const v = str(b.full_name);
    if (!v || v.length > 120) return { ok: false, error: "Full name is required" };
    changes.full_name = v;
  }
  if (b.email !== undefined) {
    const v = str(b.email).toLowerCase();
    if (!EMAIL_RE.test(v)) return { ok: false, error: "A valid email address is required" };
    changes.email = v;
  }
  if (b.department !== undefined) changes.department = str(b.department) || "General";
  if (b.phone_number !== undefined) changes.phone_number = str(b.phone_number) || null;
  if (b.role !== undefined) {
    const v = str(b.role) as Role;
    if (!ROLES.includes(v)) return { ok: false, error: "Invalid role" };
    changes.role = v;
  }
  if (b.is_active !== undefined) {
    if (typeof b.is_active !== "boolean") return { ok: false, error: "is_active must be boolean" };
    changes.is_active = b.is_active;
  }
  if (Object.keys(changes).length === 0) return { ok: false, error: "Nothing to update" };
  return { ok: true, value: { user_id, changes } };
}

export interface ResetPasswordInput { user_id: string; password: string }

/** Same rules as account creation: valid UUID, password 8–128 characters. */
export function validateResetPassword(b: Record<string, unknown>): Result<ResetPasswordInput> {
  const user_id = str(b.user_id);
  if (!UUID_RE.test(user_id)) return { ok: false, error: "Invalid user id" };
  const password = typeof b.password === "string" ? b.password : "";
  if (password.length < 8 || password.length > 128) {
    return { ok: false, error: "Password must be 8–128 characters" };
  }
  return { ok: true, value: { user_id, password } };
}
