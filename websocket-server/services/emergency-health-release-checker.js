/**
 * EmergencyHealthReleaseChecker (Scheduled Job)
 * =====================================================
 * ตรวจสอบ emergency health release sessions ที่ครบเวลาแล้ว
 * แล้วทำ auto-release + สร้าง access tokens ให้ผู้ช่วยเหลือที่ผ่านเงื่อนไข
 *
 * Flow:
 *   1. ตรวจ sessions ที่ status = 'counting'
 *   2. ถ้า triggered_at + release_delay_minutes <= now → UPDATE เป็น 'released'
 *   3. ดึง incident responders ของเหตุการณ์นั้น
 *   4. กรองตาม recipient settings (active responder / medical / verified / whitelist)
 *   5. สร้าง emergency_health_access_tokens แบบ 1 token ต่อ 1 responder ต่อ 1 session
 *   6. Supabase Realtime จะ broadcast อัตโนมัติจากการ UPDATE ตารางที่อยู่ใน publication
 *
 * Dependencies: @supabase/supabase-js
 */

const { createClient } = require('@supabase/supabase-js');
const socketService = require('./socket-service');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_KEY =
  process.env.SUPABASE_SERVICE_KEY ||
  process.env.SUPABASE_SERVICE_ROLE_KEY ||
  process.env.SUPABASE_ANON_KEY;

const supabase = SUPABASE_URL && SUPABASE_KEY
  ? createClient(SUPABASE_URL, SUPABASE_KEY)
  : null;

const CHECK_INTERVAL_MS = parseInt(
  process.env.EMERGENCY_HEALTH_RELEASE_CHECK_INTERVAL_MS || '30000',
  10,
);

const TOKEN_TTL_HOURS = parseInt(
  process.env.EMERGENCY_HEALTH_ACCESS_TOKEN_TTL_HOURS || '24',
  10,
);

const ACTIVE_RESPONDER_STATUSES = ['en_route', 'accepted', 'arrived'];
const DEFAULT_RELEASE_FIELDS = ['blood_type', 'allergies', 'emergency_contact'];

let _intervalHandle = null;
let _isRunning = false;

function start() {
  if (_intervalHandle) {
    console.warn('[EmergencyHealthReleaseChecker] Already running — skipping start()');
    return;
  }

  if (!supabase) {
    console.warn(
      '[EmergencyHealthReleaseChecker] SUPABASE_URL / key not configured — checker disabled',
    );
    return;
  }

  console.log(
    `[EmergencyHealthReleaseChecker] Started (interval=${CHECK_INTERVAL_MS / 1000}s, token_ttl=${TOKEN_TTL_HOURS}h)`,
  );

  void _runCheck();
  _intervalHandle = setInterval(() => {
    void _runCheck();
  }, CHECK_INTERVAL_MS);
}

function stop() {
  if (_intervalHandle) {
    clearInterval(_intervalHandle);
    _intervalHandle = null;
    console.log('[EmergencyHealthReleaseChecker] Stopped');
  }
}

async function runOnce() {
  return _runCheck();
}

async function _runCheck() {
  if (!supabase) return;

  if (_isRunning) {
    console.log('[EmergencyHealthReleaseChecker] Previous check still running — skipping');
    return;
  }

  _isRunning = true;
  const now = new Date();

  try {
    const sessions = await _fetchDueSessions(now);
    if (sessions.length === 0) return;

    console.log(
      `[EmergencyHealthReleaseChecker] Found ${sessions.length} due session(s)`,
    );

    for (const session of sessions) {
      await _processSession(session, now);
    }
  } catch (error) {
    console.error('[EmergencyHealthReleaseChecker] Unexpected error in check loop:', error);
  } finally {
    _isRunning = false;
  }
}

async function _fetchDueSessions(now) {
  const { data, error } = await supabase
    .from('emergency_health_release_sessions')
    .select('id, incident_id, patient_id, release_delay_minutes, triggered_at, released_fields, status, updated_at')
    .eq('status', 'counting');

  if (error) {
    throw new Error(`Failed to fetch counting sessions: ${error.message}`);
  }

  const sessions = Array.isArray(data) ? data : [];
  return sessions.filter((session) => _isSessionDue(session, now));
}

function _isSessionDue(session, now) {
  if (!session?.triggered_at) return false;

  const triggeredAt = new Date(session.triggered_at);
  const delayMinutes = Number(session.release_delay_minutes ?? 5);
  const dueAt = new Date(triggeredAt.getTime() + delayMinutes * 60 * 1000);

  return dueAt <= now;
}

async function _processSession(session, now) {
  console.log(
    `[EmergencyHealthReleaseChecker] Releasing session=${session.id} incident=${session.incident_id}`,
  );

  const settings = await _fetchSettings(session.patient_id);
  const releasedFields = _normalizeReleasedFields(settings?.enabled_fields);

  const activeResponders = await _fetchActiveResponders(session.incident_id);
  const eligibleResponders = await _filterEligibleResponders(activeResponders, settings);

  const updatedSession = await _markSessionReleased(session.id, releasedFields, now);
  if (!updatedSession) {
    console.warn(
      `[EmergencyHealthReleaseChecker] Session ${session.id} was not updated (maybe cancelled elsewhere)`,
    );
    return;
  }

  const recipients = eligibleResponders.length > 0
    ? eligibleResponders
    : (settings?.emergency_fallback ? activeResponders : []);

  const tokenCount = await _upsertAccessTokens({
    sessionId: session.id,
    incidentId: session.incident_id,
    recipients,
    now,
  });

  console.log(
    `[EmergencyHealthReleaseChecker] Session ${session.id} released with ${tokenCount} token(s)`,
  );

  // Broadcast to incident room so responders know health data is available
  socketService.broadcastEmergencyHealthReleased(session.incident_id, {
    sessionId: session.id,
    patientId: session.patient_id,
    releasedFields: releasedFields,
    autoReleasedAt: now.toISOString(),
    tokenCount,
  });

  if (eligibleResponders.length === 0 && recipients.length === 0) {
    console.warn(
      `[EmergencyHealthReleaseChecker] Session ${session.id} released without eligible recipients (no tokens created)`,
    );
  }
}

async function _fetchSettings(userId) {
  const { data, error } = await supabase
    .from('emergency_health_data_settings')
    .select('user_id, is_enabled, release_delay_minutes, enabled_fields, require_active_responder, require_medical_profession, require_verified, emergency_fallback, whitelisted_user_ids, consent_given_at, updated_at')
    .eq('user_id', userId)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to fetch emergency settings for ${userId}: ${error.message}`);
  }

  return data || null;
}

async function _fetchActiveResponders(incidentId) {
  const { data, error } = await supabase
    .from('incident_responses')
    .select('video_id, volunteer_id, status, accepted_at')
    .eq('video_id', incidentId)
    .in('status', ACTIVE_RESPONDER_STATUSES);

  if (error) {
    throw new Error(`Failed to fetch active responders for ${incidentId}: ${error.message}`);
  }

  const responders = Array.isArray(data) ? data : [];
  const uniqueMap = new Map();

  for (const row of responders) {
    if (row?.volunteer_id) {
      uniqueMap.set(row.volunteer_id, {
        volunteer_id: row.volunteer_id,
        status: row.status,
        accepted_at: row.accepted_at,
      });
    }
  }

  return Array.from(uniqueMap.values());
}

async function _filterEligibleResponders(activeResponders, settings) {
  if (!activeResponders.length) return [];

  const responderIds = activeResponders.map((row) => row.volunteer_id);
  const { data: userRows, error: userError } = await supabase
    .from('users')
    .select('id, verification_status')
    .in('id', responderIds);

  if (userError) {
    throw new Error(`Failed to load responder users: ${userError.message}`);
  }

  const { data: roleRows, error: roleError } = await supabase
    .from('user_group_roles')
    .select('user_id, profession_id, is_active')
    .in('user_id', responderIds)
    .eq('is_active', true);

  if (roleError) {
    throw new Error(`Failed to load responder group roles: ${roleError.message}`);
  }

  const professionIds = [...new Set((roleRows || []).map((row) => row.profession_id).filter(Boolean))];
  const { data: professionRows, error: professionError } = professionIds.length > 0
    ? await supabase
        .from('professions')
        .select('id, category, is_volunteer, requires_verification')
        .in('id', professionIds)
    : { data: [], error: null };

  if (professionError) {
    throw new Error(`Failed to load professions: ${professionError.message}`);
  }

  const userMap = new Map((userRows || []).map((row) => [row.id, row]));
  const rolesByUser = new Map();
  for (const role of roleRows || []) {
    if (!rolesByUser.has(role.user_id)) {
      rolesByUser.set(role.user_id, []);
    }
    rolesByUser.get(role.user_id).push(role);
  }

  const professionMap = new Map((professionRows || []).map((row) => [row.id, row]));
  const whitelist = new Set((settings?.whitelisted_user_ids || []).filter(Boolean));
  const requireMedical = Boolean(settings?.require_medical_profession);
  const requireVerified = Boolean(settings?.require_verified);
  const requireActiveResponder = settings?.require_active_responder !== false;

  const eligible = [];

  for (const responder of activeResponders) {
    const user = userMap.get(responder.volunteer_id);
    const roles = rolesByUser.get(responder.volunteer_id) || [];

    const isWhitelisted = whitelist.has(responder.volunteer_id);
    const isVerified = user?.verification_status === 'verified';
    const hasMedicalProfession = roles.some((role) => {
      const profession = professionMap.get(role.profession_id);
      return profession?.category === 'provider' || profession?.category === 'medical';
    });

    const passesActiveResponder = requireActiveResponder ? true : true;
    const passesMedical = !requireMedical || hasMedicalProfession;
    const passesVerified = !requireVerified || isVerified;

    if (isWhitelisted || (passesActiveResponder && passesMedical && passesVerified)) {
      eligible.push({
        responderId: responder.volunteer_id,
        userId: responder.volunteer_id,
        isWhitelisted,
        isVerified,
        hasMedicalProfession,
      });
    }
  }

  return eligible;
}

async function _markSessionReleased(sessionId, releasedFields, now) {
  const payload = {
    status: 'released',
    auto_released_at: now.toISOString(),
    released_fields: releasedFields,
    updated_at: now.toISOString(),
  };

  const { data, error } = await supabase
    .from('emergency_health_release_sessions')
    .update(payload)
    .eq('id', sessionId)
    .eq('status', 'counting')
    .select('id, incident_id, patient_id, status, auto_released_at')
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to update session ${sessionId}: ${error.message}`);
  }

  return data || null;
}

async function _upsertAccessTokens({ sessionId, incidentId, recipients, now }) {
  if (!recipients.length) return 0;

  const expiresAt = new Date(now.getTime() + TOKEN_TTL_HOURS * 60 * 60 * 1000).toISOString();
  const rows = recipients.map((recipient) => ({
    session_id: sessionId,
    responder_id: recipient.responderId,
    incident_id: incidentId,
    expires_at: expiresAt,
    revoked_at: null,
    created_at: now.toISOString(),
  }));

  const { data, error } = await supabase
    .from('emergency_health_access_tokens')
    .upsert(rows, { onConflict: 'session_id,responder_id' })
    .select('id');

  if (error) {
    throw new Error(`Failed to upsert emergency access tokens: ${error.message}`);
  }

  return Array.isArray(data) ? data.length : 0;
}

function _normalizeReleasedFields(enabledFields) {
  if (Array.isArray(enabledFields) && enabledFields.length > 0) {
    return enabledFields.filter(Boolean);
  }

  if (typeof enabledFields === 'string') {
    try {
      const parsed = JSON.parse(enabledFields);
      if (Array.isArray(parsed) && parsed.length > 0) {
        return parsed.filter(Boolean);
      }
    } catch (_) {
      // ignore malformed JSON and fallback to defaults
    }
  }

  return [...DEFAULT_RELEASE_FIELDS];
}

module.exports = {
  start,
  stop,
  runOnce,
  isRunning: () => _isRunning,
};
